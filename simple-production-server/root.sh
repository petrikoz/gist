# ****************************************************************
# PROFILE

# включаем поддержку цветов в терминале
sed -i 's/xterm-color)/xterm-color|*-256color)/g' ~/.bashrc
# подсвечиваем root'а красным
sed -i 's/033\[01;32m/033\[01;31m/g' ~/.bashrc
# подкрашиваем: @ — белым, hostname — жёлтым
sed -i 's/\]\\u@\\h/\]\\u\\\[\\033\[00m\\\]@\\\[\\033\[33;1m\\\]\\h/g' ~/.bashrc

# включаем поддержку системных аддонов для Vim
mkdir -p ~/.vim
ln -s /usr/share/vim/addons ~/.vim/after

# ****************************************************************
# SYSTEM

apt remove -y --purge snapd landscape-common
apt install -y figlet update-motd
apt update && apt upgrade -y
apt autoremove -y --purge
shutdown -r now
timedatectl set-timezone Asia/Yekaterinburg
hostnamectl set-hostname PROJECT
echo "127.0.1.1       PROJECT" >> /etc/hosts
cd /etc/update-motd.d
chmod -x \
    00-header \
    10-help-text \
    50-motd-news \
    95-hwe-eol
wget https://raw.githubusercontent.com/petrikoz/wormhole/master/roles/common/files/update-motd.d/10-hostname
wget https://raw.githubusercontent.com/petrikoz/wormhole/master/roles/common/files/update-motd.d/20-sysinfo
wget https://raw.githubusercontent.com/petrikoz/wormhole/master/roles/common/files/update-motd.d/35-diskspace
wget https://raw.githubusercontent.com/petrikoz/wormhole/master/roles/common/files/update-motd.d/40-services
chmod +x \
    10-hostname \
    20-sysinfo \
    35-diskspace \
    40-services
vi 40-services
    # replace 'services=(...)'
    # with 'services=("nginx" "postgresql" "redis" "ufw" "unattended-upgrades" "uwsgi")'

# ****************************************************************
# SYSTEMD
# максимальный размер логов на диске
sed -i "/^#SystemMaxUse=/c\SystemMaxUse=300M" /etc/systemd/journald.conf
# сколько место гарантировано должно быть свободным
sed -i "/^#SystemKeepFree=/c\SystemKeepFree=1G" /etc/systemd/journald.conf
# максимальный срок хранения логов
sed -i "/^#MaxRetentionSec=/c\MaxRetentionSec=1month" /etc/systemd/journald.conf
# максимальное время перед созданием нового файла
sed -i "/^#MaxFileSec=1month/c\MaxFileSec=1week" /etc/systemd/journald.conf
# применяем новые настройки
systemctl restart systemd-journald
# удаляем логи старше срока, заданного в MaxRetentionSec
journalctl --vacuum-time=1month
# удаляем логи тяжлелее размера, заданного в SystemMaxUse
journalctl --vacuum-size=300M

# ****************************************************************
# NODEJS

apt update && apt install -y ca-certificates curl gnupg
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
# проверить текущую LTS версию на https://nodejs.org/
NODE_MAJOR=20; echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
apt update && apt install -y nodejs
npm install -g npm@latest pm2@latest

# ****************************************************************
# NGINX

apt install -y nginx
cd /etc/nginx
mkdir /etc/nginx/ssl
openssl dhparam -out /etc/nginx/ssl/dhparams.pem 3072

# vi /etc/nginx/nginx.conf
# change in events {
worker_connections 4096;
# add after worker_processes:
# nproc * 4096
worker_rlimit_nofile 32678;

cat <<EOT > /etc/nginx/conf.d/server.conf
server_tokens  off;
server_name_in_redirect  off;
server_names_hash_bucket_size  64;

EOT

# GeoIP2
apt install -y libnginx-mod-http-geoip2
mkdir /etc/nginx/GeoIP
cd /etc/nginx/GeoIP
wget https://git.io/GeoLite2-City.mmdb
wget https://git.io/GeoLite2-Country.mmdb
cat <<EOT > /etc/nginx/conf.d/geoip2.conf
geoip2  /etc/nginx/GeoIP/GeoLite2-Country.mmdb {
  auto_reload  60m;
  \$geoip2_metadata_country_build  metadata  build_epoch;
  \$geoip2_data_country_code       country   iso_code;
  \$geoip2_data_country_name       country   names  en;
}

EOT

# config for issue SSL certificates via acme.sh
# https://github.com/acmesh-official/acme.sh
cat <<EOT > /etc/nginx/snippets/acme.conf
location  /.well-known {
  root /var/www/html;
}

EOT

# configure SSL
# see https://ssl-config.mozilla.org/
cat <<EOT > /etc/nginx/snippets/ssl.conf
ssl_session_timeout  1d;
ssl_session_cache    shared:SSL:10m;  # about 40000 sessions
ssl_session_tickets  off;

ssl_dhparam  ssl/dhparams.pem;

# intermediate configuration
ssl_protocols              TLSv1.2  TLSv1.3;
ssl_ciphers                ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers  off;

# HSTS (ngx_http_headers_module is required) (63072000 seconds)
add_header  Strict-Transport-Security  "max-age=63072000"  always;

# OCSP stapling
ssl_stapling         on;
ssl_stapling_verify  on;

resolver  8.8.8.8  1.1.1.1;

EOT

# after all changes
nginx -t && systemctl restart nginx

# ****************************************************************
# POSTGRESQL

apt install -y postgresql-common
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
apt update && apt install -y postgresql libpq-dev

# ****************************************************************
# PYTHON

apt install -y python3-pip
pip3 install -U pip setuptools

# ****************************************************************
# REDIS

apt install -y redis

# ****************************************************************
# UWSGI

# собираем через PIP с поддержкой SSL
apt install -y libssl-dev
UWSGI_PROFILE_OVERRIDE=ssl=true pip3 install --no-cache-dir uwsgi

mkdir -p /var/log/uwsgi
mkdir -p /etc/uwsgi/vassals

cat <<EOT > /etc/uwsgi/emperor.ini
[uwsgi]
emperor = %dvassals

touch-reload = %p

log-date = true
log-truncate = true
logto = /var/log/uwsgi/emperor.log

EOT
cat <<EOT > /etc/logrotate.d/uwsgi
/var/log/uwsgi/*.log {
  compress
  copytruncate
  dateext
  rotate 3
  size 1M
}

EOT
cat <<EOT > /etc/systemd/system/uwsgi.service
[Unit]
Description=uWSGI Emperor
After=syslog.target

[Service]
ExecStart=/usr/local/bin/uwsgi --ini /etc/uwsgi/emperor.ini
RuntimeDirectory=uwsgi
Restart=always
KillSignal=SIGQUIT
Type=notify
NotifyAccess=all

[Install]
WantedBy=multi-user.target

EOT
systemctl daemon-reload
systemctl enable uwsgi
systemctl start uwsgi

# ****************************************************************
# UFW

ufw limit ssh
ufw allow 'Nginx Full'
ufw enable
systemctl start ufw

# ****************************************************************
# NetAngels's SSL

git clone https://gist.github.com/c696073e978c7e9dc6dbdacd5bd30571.git ~/ssl-renew
apt install -y python3-httpx python3-psutil
chmod 640 ~/ssl-renew
cd ~/ssl-renew
chmod u+x netangels-ssl-renew.py
# добавляем в конфиг нужные значения
vi config.ini
# первый запуск вручную
/usr/bin/env /root/ssl-renew/netangels-ssl-renew.py > /root/ssl-renew/log 2>&1
# если всё нормально, то добавим запуск по расписанию
(crontab -l ; echo "43 2 * * *    /usr/bin/env /root/ssl-renew/netangels-ssl-renew.py > /root/ssl-renew/log 2>&1") | sort - | uniq - | crontab -

# ********************************************************************************************************************************
# USER

# создаём пользователя для проектов
useradd -md /home/PROJECT -s /bin/bash PROJECT
usermod -aG docker PROJECT

# опционально добавляем пароль к пользователю
passwd PROJECT

# логи для проектов
cat <<EOT > /etc/logrotate.d/PROJECT
/home/PROJECT/log/*.log {
    create 644 PROJECT PROJECT
    compress
    copytruncate
    daily
    dateext
    rotate 3
    size 1M
    su PROJECT PROJECT
}

EOT

# копируем свои ключи в нового пользователя
mkdir -m 700 /home/PROJECT/.ssh
cp -r /root/.ssh/authorized_keys /home/PROJECT/.ssh
chown -R PROJECT:PROJECT /home/PROJECT/.ssh

# правим права доступа к домашней директории
chmod a+rx /home/PROJECT

# логин под созданным пользователем
sudo -iu PROJECT

# добавляем SSH-ключи с GitHub'а
whet https://gist.githubusercontent.com/petrikoz/7a2e1457bbf4708369c660346e5c0038/raw/e0bf728f06b22c1ec062258a8c09039f84f6c3f2/ssh-import-id.py
pip install --user --break-system-packages httpx
chmod u+x ssh-import-id.py
python3 ssh-import-id.py USERNAME USERNAME_1 USERNAME_2

# подкрашиваем: @ — белым, hostname — жёлтым
sed -i 's/\]\\u@\\h/\]\\u\\\[\\033\[00m\\\]@\\\[\\033\[33;1m\\\]\\h/g' ~/.bashrc

# устанавляиваем зависимости
pip install --user --break-system-packages virtualenvwrapper

# конфиг BASH'а
cat <<EOT >> ~/.bashrc

################################################################
# Utilities
################################################################

function hsi() {
  history | grep -i \$1
}

################################################################
# Aliases
################################################################

alias md='mkdir -p'
alias ll='ls -hl'

################################################################
# Completion
################################################################

#== Package installer for Python
_pip_completion()
{
    COMPREPLY=( \$( COMP_WORDS="\${COMP_WORDS[*]}" \\
                   COMP_CWORD=\$COMP_CWORD \\
                   PIP_AUTO_COMPLETE=1 \$1 ) )
}
complete -o default -F _pip_completion pip

#== Pyhton virtualenv wrapper
export VIRTUALENVWRAPPER_PYTHON=/usr/bin/python3
source \$HOME/.local/bin/virtualenvwrapper.sh

EOT

# конфиг GIT'а
cat <<EOT >> ~/.gitconfig
[alias]
    b = branch
    co = checkout
    fo = fetch -v origin
    foc = !git fetch -v origin "\$(git rev-parse --abbrev-ref HEAD)"
    l = log
    ll = log --graph --pretty='%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'
    pl = pull
    plc = !git pull origin "\$(git rev-parse --abbrev-ref HEAD)"
    res = reset
    resh = reset --hard
    s = status
    ss = status -s
[pull]
    rebase = true

EOT

# конфиг VIM'а
cat <<EOT >> ~/.vimrc
syntax on
filetype indent plugin on
set modeline

EOT
# включаем поддержку системных аддонов для Vim
mkdir -p ~/.vim
ln -s /usr/share/vim/addons ~/.vim/after
# настраиваем форматирование для Pyhton
mkdir -p ~/.vim/ftplugin/
cat <<EOT >> ~/.vim/ftplugin/python.vim
set tabstop=8
set expandtab
set shiftwidth=4
set softtabstop=4

EOT

# выхоим обратно в root'а
exit  # или Ctrl+D
