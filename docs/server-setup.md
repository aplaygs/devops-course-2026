# Конфигурация виртуальной машины devops-vm

Документ описывает итоговое состояние сервера после ПР № 5 и № 6 и порядок его восстановления со снимка `01-clean-install`. Используется как исходные данные для Ansible-роли в ПР № 11.

Обозначения: **[Хост]** — команда в терминале macOS, **[VM]** — команда на сервере.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | Parallels Desktop 26 (macOS, Apple Silicon); VirtualBox на ARM не используется |
| Гостевая ОС | Ubuntu Server 24.04.5 LTS, arm64 (образ `ubuntu-24.04.5-live-server-arm64.iso`) |
| Имя машины / узла | `devops-vm` |
| Оперативная память | 2048 МБ |
| Процессор | 2 ядра |
| Диск | 64 ГБ, динамически расширяемый (`expanded`), LVM: `/` — 30 ГБ, `/boot` — 2 ГБ, `/boot/efi` — 1 ГБ |
| Учётная запись при установке | `student` (группа `sudo`), пакет OpenSSH server установлен, snaps не выбирались |

## 2. Сетевые интерфейсы

| Адаптер Parallels | Интерфейс | Адрес | Назначение |
|---|---|---|---|
| Shared Network (аналог NAT) | `enp0s5` | `10.211.55.6/24` (DHCP) | выход в Интернет, репозитории пакетов |
| Host-Only | `enp0s6` | `10.37.129.4/24` (DHCP) | прямой доступ с хоста: SSH, веб-сервер (ПР № 6), имя `devops.local` |

Проверка: `ip -brief address`.

## 3. Правило проброса портов

Настраивается для сети Shared (Parallels → Настройки → Сеть → Shared → Port Forwarding или командой):

| Имя | Протокол | Порт хоста | Порт гостя |
|---|---|---|---|
| ssh | TCP | `127.0.0.1:2222` | `2222` (до hardening — `22`) |

```bash
# [Хост] на чистой машине (sshd ещё на 22):
prlsrvctl net set Shared --nat-tcp-del ssh 2>/dev/null; prlsrvctl net set Shared --nat-tcp-add ssh,2222,devops-vm,22
# [Хост] после перевода sshd на 2222 (раздел 5, шаг 5.4):
prlsrvctl net set Shared --nat-tcp-del ssh; prlsrvctl net set Shared --nat-tcp-add ssh,2222,devops-vm,2222
prlsrvctl net info Shared | grep -A2 "TCP rules"
```

## 4. Учётные записи

| Имя | Группы | Аутентификация по SSH |
|---|---|---|
| `devops` | `devops sudo users` | только по ключу `~/.ssh/devops_vm` (ed25519); пароль задан, нужен для `sudo` |
| `student` | `student adm cdrom sudo dip plugdev lxd` | запрещена (`AllowUsers devops`); вход только с консоли Parallels |
| `root` | — | запрещена (`PermitRootLogin no`) |

Ключевой материал: на хосте `~/.ssh/devops_vm` (закрытый, 600) и `~/.ssh/devops_vm.pub`; на сервере `/home/devops/.ssh` — 700, `authorized_keys` — 600.

Отпечаток ключа хоста (сверяется при первом подключении): `SHA256:APijKNrMpcQgr9BBKZEYouXpE1Sg3dypFpa4D+oaITw` (ED25519), команда проверки `[VM] sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`.

Конфигурация клиента `~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

- Порт: **2222**; служба `ssh.service`, активация по сокету `ssh.socket` **отключена**.
- Основной файл `/etc/ssh/sshd_config` не изменялся (копия: `/etc/ssh/sshd_config.backup`).
- Изменения — в файле `/etc/ssh/sshd_config.d/99-hardening.conf`:

| Директива | Значение |
|---|---|
| `Port` | `2222` |
| `PermitRootLogin` | `no` |
| `PasswordAuthentication` | `no` |
| `PubkeyAuthentication` | `yes` |
| `PermitEmptyPasswords` | `no` |
| `MaxAuthTries` | `3` |
| `LoginGraceTime` | `30` |
| `AllowUsers` | `devops` |
| `X11Forwarding` | `no` |
| `ClientAliveInterval` | `300` |
| `ClientAliveCountMax` | `2` |

- В `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` **закомментирована**: файлы читаются по алфавиту и действует первое значение, поэтому без этого 99-й файл её не переопределяет.
- Проверка действующих значений: `sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"`.

## 6. Правила межсетевого экрана

Политики по умолчанию: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`; журналирование `medium`.

| Порт | Действие | Комментарий |
|---|---|---|
| `2222/tcp` | `LIMIT` | SSH, ≥ 6 соединений за 30 с с одного адреса — блокировка |
| `80/tcp` | `ALLOW` | HTTP (ПР № 6) |
| `443/tcp` | `ALLOW` | HTTPS (ПР № 6) |

Правила действуют и для IPv4, и для IPv6. Правило `ufw allow ssh` **не** используется: оно открыло бы порт 22 из `/etc/services`.

## 7. Снимки состояния

| Снимок | Создан | Состояние |
|---|---|---|
| `01-clean-install` | 2026-10-12 17:50 | система сразу после установки |
| `02-keys-configured` | 2026-10-12 18:01 | пользователь `devops`, вход по ключу, `~/.ssh/config` |
| `03-ssh-hardened` | 2026-10-12 18:02 | hardening SSH, порт 2222 |
| `04-nginx-https` | 2026-10-16 11:53 | Nginx, HTTPS с самоподписанным сертификатом, ресурс доставлен rsync |

Список: `prlctl snapshot-list devops-vm`; откат: `prlctl snapshot-switch devops-vm -i <ID>`.

Имя узла: `hostname -f` → `devops-vm.devops.local` (строка `127.0.1.1 devops-vm.devops.local devops-vm` в `/etc/hosts` сервера). На хосте в `/etc/hosts`: `10.37.129.4   devops.local`.

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` (1.24.0, репозиторий Ubuntu), служба `nginx.service` включена в автозапуск; на сервере также установлен `rsync` |
| Процессы | главный — `root` (читает конфигурацию и ключ, открывает порты 80/443), рабочие — `www-data` |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site` (root:root, 644), ссылка в `/etc/nginx/sites-enabled/devops-site` |
| Стандартный ресурс | отключён: удалена ссылка `/etc/nginx/sites-enabled/default`, файл в `sites-available` сохранён |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталоги `755`, файлы `644`; запись для `www-data` невозможна |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log`; перенаправления 301 (блок порта 80) — в общий `/var/log/nginx/access.log` |
| Сертификат | `/etc/ssl/certs/devops.crt`, root:root, `644`; самоподписанный, CN и SAN `DNS:devops.local`, RSA 2048, срок 365 дней (до 16.10.2027) |
| Закрытый ключ | `/etc/ssl/private/devops.key`, root:root, `600` (каталог `/etc/ssl/private` — 700); в репозиторий не добавляется |
| Протоколы | `TLSv1.2 TLSv1.3`; HSTS **не** используется |
| Доставка содержимого | `scripts/deploy.sh` из каталога `site/` репозитория (rsync `--delete --chmod=D755,F644`) |

Порт 80 отвечает `301` с переходом на `https://$host$request_uri`; порт 443 обслуживает каталог ресурса, страница ошибки — `/404.html`. Правила UFW для 80/443 — из раздела 6 (профили `Nginx Full` и т. п. не добавляются).

Формирование сертификата:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"
```

Конфигурация `/etc/nginx/sites-available/devops-site`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    root /var/www/devops-site;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log  /var/log/nginx/devops-site.error.log;
}
```

Изменения применяются только командой `sudo nginx -t && sudo systemctl reload nginx` (не `restart`).

Хостовая система: сертификат для проверки клиентом — `~/devops.crt` (`scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`). На macOS 15+ `/usr/bin/rsync` — это `openrsync`, не поддерживающий `--chmod`; нужен `brew install rsync` (`/opt/homebrew/bin/rsync` раньше в `PATH`).

Особенности стенда: после возобновления приостановленной VM часы гостя отстают, и `apt` отклоняет индексы репозиториев (`Release file ... is not valid yet`) — синхронизировать время: `[Хост] ssh devops "sudo date -s @$(date +%s)"`.

---

## Восстановление со снимка 01-clean-install (≈ 10 минут)

Пароль `student` спрашивается при `ssh-copy-id` и при первом `sudo`; пароль `devops` задаётся на шаге 2.

```bash
# 1. [Хост] проброс на порт 22, ключ для student
prlsrvctl net set Shared --nat-tcp-del ssh 2>/dev/null; prlsrvctl net set Shared --nat-tcp-add ssh,2222,devops-vm,22
ssh-keygen -R "[127.0.0.1]:2222"            # если ругается REMOTE HOST IDENTIFICATION HAS CHANGED после отката — ключ хоста тот же, сверить отпечаток из раздела 4
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 student@127.0.0.1
ssh -t -i ~/.ssh/devops_vm -p 2222 student@127.0.0.1

# 2. [VM, под student] пользователь devops и его ключ
sudo adduser --gecos "" devops               # ввести пароль devops
sudo usermod -aG sudo devops
sudo install -d -m 700 -o devops -g devops /home/devops/.ssh
sudo install -m 600 -o devops -g devops ~/.ssh/authorized_keys /home/devops/.ssh/authorized_keys

# 3. [VM] hardening SSH
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo sed -i 's/^PasswordAuthentication yes/# PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf
printf '%s\n' 'Port 2222' 'PermitRootLogin no' 'PasswordAuthentication no' 'PubkeyAuthentication yes' \
  'PermitEmptyPasswords no' 'MaxAuthTries 3' 'LoginGraceTime 30' 'AllowUsers devops' \
  'X11Forwarding no' 'ClientAliveInterval 300' 'ClientAliveCountMax 2' \
  | sudo tee /etc/ssh/sshd_config.d/99-hardening.conf
sudo sshd -t && echo OK
sudo systemctl disable --now ssh.socket && sudo systemctl enable --now ssh.service && sudo systemctl restart ssh
sudo ss -tlnp | grep sshd                    # 0.0.0.0:2222

# 4. [VM] межсетевой экран (разрешающие правила — ДО enable)
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP' && sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable && sudo ufw logging medium

# 5. [VM] имя узла
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
# сессию НЕ закрывать до шага 6

# 6. [Хост, новый терминал] проброс на 2222 и проверка
prlsrvctl net set Shared --nat-tcp-del ssh; prlsrvctl net set Shared --nat-tcp-add ssh,2222,devops-vm,2222
ssh devops 'hostname -f'
scp -P 2222 -i ~/.ssh/devops_vm scripts/audit.sh devops@127.0.0.1:~ && ssh -t devops 'bash ~/audit.sh'   # код возврата 0
```

### Восстановление веб-сервера (после шагов 1–6)

```bash
# [VM]
sudo apt update && sudo apt install -y nginx rsync
sudo install -d -o devops -g devops -m 755 /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"
sudo nano /etc/nginx/sites-available/devops-site       # текст конфигурации — раздел 8
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

# [Хост] сертификат для клиента (сформирован заново — старый ~/devops.crt не подходит) и доставка
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
scripts/deploy.sh                                       # код возврата 0
```
