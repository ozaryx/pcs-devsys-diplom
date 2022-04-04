# Курсовая работа по итогам модуля "DevOps и системное администрирование"

Курсовая работа необходима для проверки практических навыков, полученных в ходе прохождения курса "DevOps и системное 
администрирование".

Мы создадим и настроим виртуальное рабочее место. Позже вы сможете использовать эту систему для выполнения домашних 
заданий по курсу

## Задание

1. Создайте виртуальную машину Linux.

Vagrant
```shell
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-20.04"

  config.vm.synced_folder "./data", "/vagrant_data"
  config.vm.network "private_network", ip: "192.168.56.20"
  config.vm.network "forwarded_port", guest: 80, host:58080
  config.vm.network "forwarded_port", guest: 443, host:58443
  config.vm.provider "virtualbox" do |v|
    v.memory = 1524
    v.cpus = 3
  end
end
```

2. Установите ufw и разрешите к этой машине сессии на порты 22 и 443, при этом трафик на интерфейсе localhost (lo) 
должен ходить свободно на все порты.

```shell
vagrant@vagrant:~$ ip -br a
lo               UNKNOWN        127.0.0.1/8 ::1/128 
eth0             UP             10.0.2.15/24 fe80::a00:27ff:feb1:285d/64 
eth1             UP             192.168.56.20/24 fe80::a00:27ff:fe16:bb08/64 
```

Добавить установку ufw и настройку в секцию провижининга 
```shell
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-20.04"

...

  config.vm.provision "shell", inline: <<-SHELL
    apt-get update
    apt-get install -y ufw
    ufw allow in on eth0 to 10.0.2.15
    ufw allow in on eth1 to 192.168.56.20 port 22
    ufw allow in on eth1 to 192.168.56.20 port 443
    echo y | ufw enable

  SHELL
end
```

3. Установите hashicorp vault ([инструкция по ссылке](https://learn.hashicorp.com/tutorials/vault/getting-started-install?in=vault/getting-started#install-vault)).

На данный момент установить hashicorp vault не представляется возможным
```shell
Hashicorp has blocked access from Russia to all their services:

We’re sorry, but because of the conflict underway in Ukraine, HashiCorp is prohibiting availability of our products and services in Russia and Belarus.
```

Добавить установку пакета в секцию провижининга 
```shell
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-20.04"

...

  config.vm.provision "shell", inline: <<-SHELL
...
    curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
    apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    apt-get update && apt-get install vault
    vault server -dev -dev-root-token-id root
  SHELL
end
```

4. Создайте центр сертификации по инструкции ([ссылка](https://learn.hashicorp.com/tutorials/vault/pki-engine?in=vault/secrets-management)) и выпустите сертификат для использования его в настройке веб-сервера nginx (срок жизни сертификата - месяц).

*Connect to Vault*
*Connect to the target Vault server.*

Export an environment variable for the vault CLI to address the target Vault server.
```
~# export VAULT_ADDR=http://127.0.0.1:8200
~# export VAULT_TOKEN=root
```

View the policies required to complete this track.
```
~# cat /track-files/track-policy.hcl
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
```

Login with the userpass auth method as track-user.
```
~# vault login -method=userpass \
  username=track-user \
  password=track-password
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                    Value
---                    -----
token                  s.sPxBRLLuqI9myGh4Qd3K9ARU
token_accessor         K4JzOdx4fyLER1qb7FQwYDw8
token_duration         768h
token_renewable        true
token_policies         ["default" "track-policy"]
identity_policies      []
policies               ["default" "track-policy"]
token_meta_username    track-user
```

**Generate Root CA**
*Generate a self-signed certificate authority (CA) root certificate using the PKI secrets engine.*

Enable the pki secrets engine at the pki path.
```
~# vault secrets enable pki
Success! Enabled the pki secrets engine at: pki/
```

Tune the pki secrets engine to issue certificates with a maximum time-to-live (TTL) of 1 month.
```
~# vault secrets tune -max-lease-ttl=87600h pki
Success! Tuned the secrets engine at: pki/
```

Generate the root certificate and save the certificate in /track-files/CA_cert.crt.
```
~# vault write -field=certificate pki/root/generate/internal \
  common_name="sysadm.local" \
  ttl=87600h > /track-files/CA_cert.crt
```
This generates a new self-signed CA certificate and private key. Vault automatically revokes the generated root at the end of its lease period (TTL); the CA certificate will sign its own Certificate Revocation List (CRL).

Configure the CA and CRL URLs.
```
~# vault write pki/config/urls \
  issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
  crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
Success! Data written to: pki/config/urls
```

**Generate Intermediate CA**
Generate an intermediate CA using the root CA you generated.

Enable the pki secrets engine at the pki_int path.
```
~# vault secrets enable -path=pki_int pki
Success! Enabled the pki secrets engine at: pki_int/
```

Tune the pki_int secrets engine to issue certificates with a maximum time-to-live (TTL) of 1 month.
```
~# vault secrets tune -max-lease-ttl=43800h pki_int
Success! Tuned the secrets engine at: pki_int/
```

Generate an intermediate certificate signing request (CSR) and save it in /track-files/pki_intermediate.csr.
```
~# vault write -format=json pki_int/intermediate/generate/internal \
        common_name="sysadm.local Intermediate Authority" \
        | jq -r '.data.csr' > /track-files/pki_intermediate.csr
```

Sign the intermediate CSR with the root certificate and save the generated certificate as /track-files/intermediate.cert.pem.
```
:~# vault write -format=json pki/root/sign-intermediate csr=@/track-files/pki_intermediate.csr \
        format=pem_bundle ttl="43800h" \
        | jq -r '.data.certificate' \
        > /track-files/intermediate.cert.pem
```

Import the signed certificate into Vault.
```
~# vault write pki_int/intermediate/set-signed \
    certificate=@/track-files/intermediate.cert.pem
Success! Data written to: pki_int/intermediate/set-signed
```

**Create a Role and Issue Certificates**
Create a role named sysadm-dot-local which allows subdomains.
```
~# vault write pki_int/roles/sysadm-dot-local \
  allowed_domains="sysadm.local" \
  allow_subdomains=true \
  max_ttl="720h"
Success! Data written to: pki_int/roles/sysadm-dot-local
```

Request a new certificate for the www.sysadm.local domain based on the sysadm-dot-local role.
```
~# vault write pki_int/issue/sysadm-dot-local common_name="www.sysadm.local" ttl="720h"
Key                 Value
---                 -----
ca_chain            [-----BEGIN CERTIFICATE-----
MIIDpjCCAo6gAwIBAgIUfhizdabo7cdbxCJ+G7TWf4Qi+qkwDQYJKoZIhvcNAQEL
BQAwFjEUMBIGA1UEAxMLZXhhbXBsZS5jb20wHhcNMjIwNDA0MDQzMjEzWhcNMjcw
NDAzMDQzMjQzWjAtMSswKQYDVQQDEyJleGFtcGxlLmNvbSBJbnRlcm1lZGlhdGUg
QXV0aG9yaXR5MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA52MyVcj7
RL8gdATCBVX1FUDh5bbXfei+LcUQS/Z8MSEP+HJOrjbctF03xeflo3dr4TaakSRB
JNkKiCu5BOiPjx2KeZ0JDS6p/lT5+pVWMd72sR5c1XBChffac1MiTMYJflrT5WaK
AHS08sp6bb7QGI8g58gSlCpRCremRxzroINL/sUnCYEDruJn3wW0pzlcRcvE0jQx
na0dz7MwBrf8XsqfLFfyxH6Un6dANSsAvebnldgWIlFXth9624EvPnDtsQ6mk+4I
NEqHUVkdMxK+SNk30lIFlLMctuJkckwtAldsQZ8k6USWQJ39ZveYMxaV5ocOUnh9
VNc8zEYyNU+pZwIDAQABo4HUMIHRMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8E
BTADAQH/MB0GA1UdDgQWBBTj/mKPTd3cxVlsCFF8SkAmloqCbjAfBgNVHSMEGDAW
gBTcPUlNXqe3t7QDWZJBNSSrUiVjODA7BggrBgEFBQcBAQQvMC0wKwYIKwYBBQUH
MAKGH2h0dHA6Ly8xMjcuMC4wLjE6ODIwMC92MS9wa2kvY2EwMQYDVR0fBCowKDAm
oCSgIoYgaHR0cDovLzEyNy4wLjAuMTo4MjAwL3YxL3BraS9jcmwwDQYJKoZIhvcN
AQELBQADggEBABqzrnZTp0GE0mCCBYCfoe4YZ4W5I1DhKIGx7GZ+fWzAtjyrpPHh
8txaN2dZhUe2/NLsy01zCvAwN58nbrGyajMop10OoXdaV7OIeklj+JCeIAhojtTA
HONcr8E09qgEvsMEnBmQGghHnZWPhjpEz9IxqYST5x+UoK4QTHAHB4aRWzVKSokH
XlWDTQcpbPiVvsJsz6XtvNCjwxM5Lyxlktr5eagDQ19Nq1yEGrzHn06ZzHyv/7co
hHV3JTSviKVKiP6T9j44vNCSQEL5AfnWOyUbNwWWyFSashk6VaLDeq7mSgVGpLux
Lp2ghXxRQcLFvTDiot2ArWPCB4db8DpRbHA=
-----END CERTIFICATE-----]
certificate         -----BEGIN CERTIFICATE-----
MIIDZjCCAk6gAwIBAgIUZOemmTNsDJk6Mcxy/4vycyyR2aIwDQYJKoZIhvcNAQEL
BQAwLTErMCkGA1UEAxMiZXhhbXBsZS5jb20gSW50ZXJtZWRpYXRlIEF1dGhvcml0
eTAeFw0yMjA0MDQwNDMzMTZaFw0yMjA0MDUwNDMzNDZaMBsxGTAXBgNVBAMTEHRl
c3QuZXhhbXBsZS5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDF
JXJ1p6X0qQJcQKBcwXAJ1jTe5qef6MB9EkZ689hicNUX4kesJkhNDaSF0uH7thuM
HT3uy24jBuckaTqAoRa9RUDOsk2YjvDx/e4oJrinOxjh6TQxPi+dNnI2NyPVsbqd
0Q7lrTQz0AV7nHBYxCjSjORniJCQ/mJvZUtNfkx/2zT7lU3Zg71MAKYBZuxlDk+U
eO13TJk3t+0E7jT0ZIO9O452sSdTEV+C/R0E3xVF5OzslsvZb+aYD1z8JVZBE5hw
+LOwryNTxGsLUl0yqyzMr0/9S1UqO9Jx4Q/Yy+Etn/KFeCOx1SricSsAkOYwuk3x
47osXUdJJHurjlUHVBR7AgMBAAGjgY8wgYwwDgYDVR0PAQH/BAQDAgOoMB0GA1Ud
JQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjAdBgNVHQ4EFgQUp9095vFZUyH+wHuH
HTUQu95v8ZYwHwYDVR0jBBgwFoAU4/5ij03d3MVZbAhRfEpAJpaKgm4wGwYDVR0R
BBQwEoIQdGVzdC5leGFtcGxlLmNvbTANBgkqhkiG9w0BAQsFAAOCAQEAq9BRjlIU
KPNOk/i2kq7JQHvY8bHXlISLraByRWixys52i9/U4c2k7IcPvKVKDWTnX8xEIVao
YZjg803E5IddgkPSzB1/tDfDhssFgPQnTZyFA85UENE8VC70ZGtit/1XtvNvZJpg
X7mJd3UZYl2dZlPJrF/CyuDRPrcSaD1yNwxaSg3JmTZVlVA22i48DVozO+5VozuS
YUNJ7C45lOstOSGm2rEJPWS0amr/Dzy8jWXndq9GVT2nuNicBe70efRh8p2riRP0
N6cuDPbuJ7oarzqb0PxI1E5y8Oj1JJnvKI4uppJQ97WRNLkI+zGxpmkzrqhIsXyb
zKd8Y6bHdoyabQ==
-----END CERTIFICATE-----
expiration          1649133226
issuing_ca          -----BEGIN CERTIFICATE-----
MIIDpjCCAo6gAwIBAgIUfhizdabo7cdbxCJ+G7TWf4Qi+qkwDQYJKoZIhvcNAQEL
BQAwFjEUMBIGA1UEAxMLZXhhbXBsZS5jb20wHhcNMjIwNDA0MDQzMjEzWhcNMjcw
NDAzMDQzMjQzWjAtMSswKQYDVQQDEyJleGFtcGxlLmNvbSBJbnRlcm1lZGlhdGUg
QXV0aG9yaXR5MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA52MyVcj7
RL8gdATCBVX1FUDh5bbXfei+LcUQS/Z8MSEP+HJOrjbctF03xeflo3dr4TaakSRB
JNkKiCu5BOiPjx2KeZ0JDS6p/lT5+pVWMd72sR5c1XBChffac1MiTMYJflrT5WaK
AHS08sp6bb7QGI8g58gSlCpRCremRxzroINL/sUnCYEDruJn3wW0pzlcRcvE0jQx
na0dz7MwBrf8XsqfLFfyxH6Un6dANSsAvebnldgWIlFXth9624EvPnDtsQ6mk+4I
NEqHUVkdMxK+SNk30lIFlLMctuJkckwtAldsQZ8k6USWQJ39ZveYMxaV5ocOUnh9
VNc8zEYyNU+pZwIDAQABo4HUMIHRMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8E
BTADAQH/MB0GA1UdDgQWBBTj/mKPTd3cxVlsCFF8SkAmloqCbjAfBgNVHSMEGDAW
gBTcPUlNXqe3t7QDWZJBNSSrUiVjODA7BggrBgEFBQcBAQQvMC0wKwYIKwYBBQUH
MAKGH2h0dHA6Ly8xMjcuMC4wLjE6ODIwMC92MS9wa2kvY2EwMQYDVR0fBCowKDAm
oCSgIoYgaHR0cDovLzEyNy4wLjAuMTo4MjAwL3YxL3BraS9jcmwwDQYJKoZIhvcN
AQELBQADggEBABqzrnZTp0GE0mCCBYCfoe4YZ4W5I1DhKIGx7GZ+fWzAtjyrpPHh
8txaN2dZhUe2/NLsy01zCvAwN58nbrGyajMop10OoXdaV7OIeklj+JCeIAhojtTA
HONcr8E09qgEvsMEnBmQGghHnZWPhjpEz9IxqYST5x+UoK4QTHAHB4aRWzVKSokH
XlWDTQcpbPiVvsJsz6XtvNCjwxM5Lyxlktr5eagDQ19Nq1yEGrzHn06ZzHyv/7co
hHV3JTSviKVKiP6T9j44vNCSQEL5AfnWOyUbNwWWyFSashk6VaLDeq7mSgVGpLux
Lp2ghXxRQcLFvTDiot2ArWPCB4db8DpRbHA=
-----END CERTIFICATE-----
private_key         -----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAxSVydael9KkCXECgXMFwCdY03uann+jAfRJGevPYYnDVF+JH
rCZITQ2khdLh+7YbjB097stuIwbnJGk6gKEWvUVAzrJNmI7w8f3uKCa4pzsY4ek0
MT4vnTZyNjcj1bG6ndEO5a00M9AFe5xwWMQo0ozkZ4iQkP5ib2VLTX5Mf9s0+5VN
2YO9TACmAWbsZQ5PlHjtd0yZN7ftBO409GSDvTuOdrEnUxFfgv0dBN8VReTs7JbL
2W/mmA9c/CVWQROYcPizsK8jU8RrC1JdMqsszK9P/UtVKjvSceEP2MvhLZ/yhXgj
sdUq4nErAJDmMLpN8eO6LF1HSSR7q45VB1QUewIDAQABAoIBAEv1kLNaY+vvjpRC
5ka21VdE7FwR3PYU9M171CIdf/r15HTuX5UpruPZZNGXHjEgyl5jCfDO+uGOEFMM
JFlZN+y3GTBKrPEh6h4jK7bWrIDqmTy54L00a54UU08mUa1NbEzQNwAxixKHjQVC
klrxQZVWac6mZKUpDn5DNg9moU0FWHXqAQT8M547Zs6wodepe026wPeOkakjXbcB
VFIBDRPvOouuNLFqcFya/AzeoBmpBZq5wP9R5fi2FViARv+YWHORw9tVV6+qISrK
poPD7UjwRId2Le0XSJ5EPil4jDrrKq+Ne2BYlL0mYC7nVugCD5J/GRCBjkzwXJ1c
qEPSqHECgYEA1MRdEdSOi7yIJzPfPMHVEopPnHGRrL0BueLPhMTiIpbm5hHNX6Gb
zt2aYVfKlQGp3dD7bSiJlaUv7x4zdeerDWT/KaFvM0J87BIFenCbdStwjwkOToH9
V7hFnKooaIe8sUxrUmmFNF7qzBkwEQStEGzT8VzdpuuDZaw3kNLYNkMCgYEA7TSH
QJoZSia+JPo0ZTCRN9tfelezy1xbjjN53jWuAN4FmFs7BpWZHKJPbvYzPYtHLn+Q
6Pm5N+57fHCWdxXiZ2wFoT6iPNgXbBt/lXhh7XR6tNTdEvO9v1CJRIyfa0VeL0LC
wjLUdVh045mc5LXe9BfbLoLOi1LtPRKo2/wBMWkCgYAg0Nh584q4yq9FPJ7lxA+U
+Hgm7O1G8y/c97qCA8vNAfFC8uP2J/rcARnagavhJ4yHhcABqgruZbfq7YGKYdzk
B/vC8/8urMaPsofdxphzjeuiZAcs3Keya91wuF3bIXRc9ChpYZUF6s3UBN6BAXOf
4OkfhO8624A8oj8/uwVV+QKBgQCZ0VBLoiH4JbtzuxQy8hWZRRZa/XhHzTJJujOy
1thpE5BJRg+2q1fIa7Ba4ihEJocYLfzINvfWvz0wasoHmxdfvXrBHx6RmgdGQWaw
hInsM3ZGwSpC2fAXmaAJ5a6THz5+IyqsR83h8mSKGtjUruNPIhEtzgEl87aHvgvl
6zrS0QKBgAZDgCkzelndKr4/8P4Jh7rHSJ6aiQQ0zStGJU2lAoTsKh+DIxEsq5Fi
yjCXPz3JgDR/0g/sG3IOvh/BLljggl2+RXvyoiu9AthrXDygJJbUet9928T0Pq8F
ZBGqINHJKouBTMq2X6qUPWtxSNo6dprNOOqckPvrA05k4fXVVokS
-----END RSA PRIVATE KEY-----
private_key_type    rsa
serial_number       64:e7:a6:99:33:6c:0c:99:3a:31:cc:72:ff:8b:f2:73:2c:91:d9:a2
```

The response displays the PEM-encoded private key, key type and certificate serial number.

Request another certificate and save the serial number in the file /track-files/cert-serial-number.txt.
```
~# vault write -format=json \
  pki_int/issue/sysadm-dot-local \
  common_name="www.sysadm.local" \
  ttl="720h" | jq -r ".data.serial_number" \
  > /track-files/cert-serial-number.txt
```


5. Установите корневой сертификат созданного центра сертификации в доверенные в хостовой системе.

Не представляется возможным

6. Установите nginx.

Добавить установку пакета в секцию провижининга 
```shell
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-20.04"

...

  config.vm.provision "shell", inline: <<-SHELL
...
    apt-get install -y nginx
    
    if [ ! -f /var/www/netology/index.html ]; then cp -r /vagrant_data/www/netology /var/www; fi
    if [ ! -f /etc/nginx/sites-available/netology ]; then cp /vagrant_data/nginx/netology /etc/nginx/sites-available; fi
    if [ -L /etc/nginx/sites-enabled/default ]; then /etc/nginx/sites-enabled/default; fi
    if [ ! -L /etc/nginx/sites-enabled/netology ]; then ln -s /etc/nginx/sites-available/netology /etc/nginx/sites-enabled; fi

    systemctl restart nginx

  SHELL
end
```

7. По инструкции ([ссылка](https://nginx.org/en/docs/http/configuring_https_servers.html)) настройте nginx на https, 
используя ранее подготовленный сертификат:
  - можно использовать стандартную стартовую страницу nginx для демонстрации работы сервера;
  - можно использовать и другой html файл, сделанный вами;

```shell
vagrant@vagrant:~$ cat /etc/nginx/sites-available/netology
server {
    listen              10.0.2.15:80;
    listen              443 ssl;
    server_name         www.sysadm.local;
    ssl_certificate     www.sysadm.local.crt;
    ssl_certificate_key www.sysadm.local.key;
    ssl_protocols       TLSv1.1 TLSv1.2;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    
    location / {
        root /var/www/netology;
    }    
}

```

8. Откройте в браузере на хосте https адрес страницы, которую обслуживает сервер nginx.

![]()

9. Создайте скрипт, который будет генерировать новый сертификат в vault:
  - генерируем новый сертификат так, чтобы не переписывать конфиг nginx;
  - перезапускаем nginx для применения нового сертификата.

```shell
cat /root/create_cert.sh

#!/usr/bin/env bash
openssl
systemctl restart nginx
```

10. Поместите скрипт в crontab, чтобы сертификат обновлялся какого-то числа каждого месяца в удобное для вас время.

```shell
# crontab -e

0 1 24 * * /root/create_cert.sh 
```

## Результат

Результатом курсовой работы должны быть снимки экрана или текст:

- Процесс установки и настройки ufw
- Процесс установки и выпуска сертификата с помощью hashicorp vault
- Процесс установки и настройки сервера nginx
- Страница сервера nginx в браузере хоста не содержит предупреждений 
- Скрипт генерации нового сертификата работает (сертификат сервера nginx должен быть "зеленым")
- Crontab работает (выберите число и время так, чтобы показать, что crontab запускается и делает что надо)

## Как сдавать курсовую работу

Курсовую работу выполните в файле readme.md в github репозитории. В личном кабинете отправьте на проверку ссылку на .md-файл в вашем репозитории.

Также вы можете выполнить задание в [Google Docs](https://docs.google.com/document/u/0/?tgif=d) и отправить в личном кабинете на проверку ссылку на ваш документ.
Если необходимо прикрепить дополнительные ссылки, просто добавьте их в свой Google Docs.

Перед тем как выслать ссылку, убедитесь, что ее содержимое не является приватным (открыто на комментирование всем, у кого есть ссылка), иначе преподаватель не сможет проверить работу. 
Ссылка на инструкцию [Как предоставить доступ к файлам и папкам на Google Диске](https://support.google.com/docs/answer/2494822?hl=ru&co=GENIE.Platform%3DDesktop).
