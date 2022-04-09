#!/usr/bin/env bash

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN="$(cat /root/.vault-token)"

cat << 'EOF' > /track-files/track-policy.hcl
# Enable secrets engine
path "sys/mounts/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# List enabled secrets engine
path "sys/mounts" {
  capabilities = [ "read", "list" ]
}

# Work with pki secrets engine
path "pki*" {
  capabilities = [ "create", "read", "update", "delete", "list", "sudo" ]
}
EOF

vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

vault write -field=certificate pki/root/generate/internal \
  common_name="sysadm.local" \
  ttl=87600h > /track-files/CA_cert.crt

vault write pki/config/urls \
  issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
  crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"

vault secrets enable -path=pki_int pki

vault secrets tune -max-lease-ttl=43800h pki_int

vault write -format=json pki_int/intermediate/generate/internal \
  common_name="sysadm.local Intermediate Authority" \
  | jq -r '.data.csr' > /track-files/pki_intermediate.csr

vault write -format=json pki/root/sign-intermediate csr=@/track-files/pki_intermediate.csr \
  format=pem_bundle ttl="43800h" \
  | jq -r '.data.certificate' \
  > /track-files/intermediate.cert.pem

vault write pki_int/intermediate/set-signed \
  certificate=@/track-files/intermediate.cert.pem

vault write pki_int/roles/sysadm-dot-local \
  allowed_domains="sysadm.local" \
  allow_subdomains=true \
  max_ttl="720h"

vault write -format=json pki_int/issue/sysadm-dot-local \
    common_name="*.sysadm.local" ttl="720h" \
    > /track-files/wildcard_sysadm-dot-local.json

cat /track-files/wildcard_sysadm-dot-local.json |
 jq -r '.data.private_key' > /etc/nginx/www.sysadm.local.pem

cat /track-files/wildcard_sysadm-dot-local.json |
 jq -r '.data.certificate' > /etc/nginx/www.sysadm.local.crt

cat /track-files/wildcard_sysadm-dot-local.json |
 jq -r '.data.ca_chain[]' >> /etc/nginx/www.sysadm.local.crt

cp /track-files/CA_cert.crt /vagrant_data

