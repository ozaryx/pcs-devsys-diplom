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
  SHELL
end
```

4. Создайте центр сертификации по инструкции ([ссылка](https://learn.hashicorp.com/tutorials/vault/pki-engine?in=vault/secrets-management)) и выпустите сертификат для использования его в настройке веб-сервера nginx (срок жизни сертификата - месяц).

Не представляется возможным

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
