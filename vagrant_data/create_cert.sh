#!/usr/bin/env bash

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN="$(cat /root/.vault-token)"  # root

if vault status -ca-cert=/track-files/CA_cert.crt &>/dev/null; then
    vault write pki_int/revoke \
        serial_number="$(cat /track-files/wildcard_sysadm-dot-local.json | jq -r '.data.serial_number')"
    
    vault write -format=json \
        pki_int/issue/sysadm-dot-local \
        common_name="*.sysadm.local" ttl="720h" \
        > /track-files/wildcard_sysadm-dot-local.json
    
    cat /track-files/wildcard_sysadm-dot-local.json | 
     jq -r '.data.private_key' > /etc/nginx/www.sysadm.local.pem
    
    cat /track-files/wildcard_sysadm-dot-local.json | 
     jq -r '.data.certificate' > /etc/nginx/www.sysadm.local.crt
    
    cat /track-files/wildcard_sysadm-dot-local.json | 
     jq -r '.data.ca_chain[]' >> /etc/nginx/www.sysadm.local.crt
    
    systemctl restart nginx.service
else
    echo "Vault is sealed or service does not available"
fi

