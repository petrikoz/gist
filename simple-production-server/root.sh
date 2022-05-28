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
apt autoremove -y --purge
apt update && apt upgrade -y
shutdown -r now
apt install -y \
    figlet \
    software-properties-common \
    ufw \
    unattended-upgrades \
    update-motd \
    update-notifier-common
timedatectl set-timezone Asia/Yekaterinburg
hostnamectl set-hostname $PROJECT
echo "127.0.1.1       $PROJECT" >> /etc/hosts
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
# NODEJS

curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
apt install -y nodejs
npm install -g npm@latest pm2@latest

# ****************************************************************
# NGINX

apt install -y nginx
cd /etc/nginx
mkdir /etc/nginx/ssl
openssl dhparam -out /etc/nginx/ssl/dhparams.pem 3072

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
nginx -t && systemctl restart nginx

# ****************************************************************
# NetAngels's SSL

git clone https://gist.github.com/c696073e978c7e9dc6dbdacd5bd30571.git ~/ssl-renew
pip install psutil httpx
chmod 640 ~/ssl-renew
cd ~/ssl-renew
chmod u+x netangels-ssl-renew.py
# добавляем в конфиг нужные значения
vi config.ini
# первый запуск вручную
/usr/bin/env /root/ssl-renew/netangels-ssl-renew.py > /root/ssl-renew/log 2>&1
# если всё нормально, то добавим запуск по расписанию
(crontab -l ; echo "43 2 * * *    /usr/bin/env /root/ssl-renew/netangels-ssl-renew.py > /root/ssl-renew/log 2>&1") | sort - | uniq - | crontab -

# ****************************************************************
# POSTGRESQL

echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/postgresql.list
wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt update && apt install -y postgresql

# ****************************************************************
# PYTHON

apt install -y python3-pip
pip3 install -U pip setuptools wheel

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
# USER

# создаём пользователя для проектов
useradd -md /home/web -s /bin/bash web
usermod -aG sudo web

# опционально добавляем пароль к пользователю
passwd web

# логи для проектов
cat <<EOT > /etc/logrotate.d/web
/home/web/*/log/*.log {
    create 644 web web
    compress
    copytruncate
    daily
    dateext
    rotate 3
    size 1M
    su web web
}

EOT

# копируем свои ключи в нового пользователя
mkdir -m 700 /home/web/.ssh
cp -r /root/.ssh/authorized_keys /home/web/.ssh
chown -R web:web /home/web/.ssh

# логин под созданным пользователем
sudo -iu web

# добавляем SSH-ключи с GitHub'а
whet https://gist.githubusercontent.com/petrikoz/7a2e1457bbf4708369c660346e5c0038/raw/e0bf728f06b22c1ec062258a8c09039f84f6c3f2/ssh-import-id.py
pip install httpx
chmod u+x ssh-import-id.py
python3 ssh-import-id.py USERNAME USERNAME_1 USERNAME_2

# подкрашиваем: @ — белым, hostname — жёлтым
sed -i 's/\]\\u@\\h/\]\\u\\\[\\033\[00m\\\]@\\\[\\033\[33;1m\\\]\\h/g' ~/.bashrc

# устанавляиваем зависимости
pip install --user virtualenvwrapper

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
