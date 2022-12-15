# ****************************************************************
# PROJECT

mkdir -p \
    ~/$PROJECT/etc \
    ~/$PROJECT/log \
    ~/$PROJECT/run
git clone git@github.com:ITCase/$PROJECT.git ~/$PROJECT/src

mkvirtualenv -a ~/$PROJECT/src $PROJECT
pip install -U pip setuptools wheel
pip install -r requirements-itcase.txt
pip install -r requirements.txt

cp default/prod.local.py settings/local.py
vi settings/local.py
    # change data

./manage.py collectstatic --clear --no-input
git reset --hard

# ****************************************************************
# POSTGRESQL

# добавляем пользователя и базу для проекта
sudo -u postgres psql
    # run:
    #     CREATE USER $PROJECT WITH PASSWORD '$PASSWORD';
    #     CREATE DATABASE $PROJECT WITH OWNER $PROJECT;
    #     GRANT ALL ON DATABASE $PROJECT TO $PROJECT;
./manage.py showmigrations
./manage.py migrate
./manage.py createsuperuser

# ****************************************************************
# SUPERVISOR

# Supervisor используется для пере/запуска RQ при перезагрузке uWSGI-инстанса
pip install supervisor
cat <<EOT > ~/$PROJECT/etc/supervisord.ini
[supervisord]
logfile = $HOME/PROJECT/log/supervisord.log
logfile_maxbytes = 1MB

[group:PROJECT]
programs = rqworker

[program:rqworker]
command = $HOME/.virtualenvs/%(group_name)s/bin/python $HOME/%(group_name)s/src/manage.py %(program_name)s --name %(group_name)s-%(program_name)s-%(process_num)s

numprocs = 2
process_name = %(group_name)s-%(program_name)s-%(process_num)s

directory = $HOME/%(group_name)s/src

autostart = true
autorestart = true

; RQ requires the TERM signal to perform a warm shutdown. If RQ does not die
; within 10 seconds, supervisor will forcefully kill it
stopsignal = TERM

redirect_stderr = true

EOT

# ****************************************************************
# UWSGI

cp ~/$PROJECT/src/default/prod.uwsgi.ini ~/$PROJECT/etc/uwsgi.ini
sudo ln -s ~/$PROJECT/etc/uwsgi.ini /etc/uwsgi/vassals/$PROJECT.ini
sudo ln -s ~/$PROJECT/etc/uwsgi-ws.ini /etc/uwsgi/vassals/$PROJECT-ws.ini

# ****************************************************************
# NGINX

cat <<EOT > ~/$PROJECT/etc/nginx.conf
server {
  server_name  .PROJECT.DOMAIN;
  access_log   off;
  expires      max;
  return       301  https://PROJECT.DOMAIN\$request_uri;
}

server {
  listen       443  http2 ssl;
  server_name  www.PROJECT.DOMAIN;
  access_log   off;

  include      enable/ssl.conf;

  ssl_certificate      ssl/PROJECT.DOMAIN/PROJECT_DOMAIN.full.crt;
  ssl_certificate_key  ssl/PROJECT.DOMAIN/PROJECT_DOMAIN.key;

  return  301  https://PROJECT.DOMAIN\$request_uri;
}

server {
  listen       443  http2 ssl  default_server;
  server_name  .PROJECT.DOMAIN;

  include  snippets/acme.conf;
  include  snippets/ssl.conf;

  ssl_certificate      ssl/PROJECT.DOMAIN/PROJECT_DOMAIN.full.crt;
  ssl_certificate_key  ssl/PROJECT.DOMAIN/PROJECT_DOMAIN.key;

  add_header  Content-Security-Policy  "block-all-mixed-content";

  access_log  off;
  error_log   $HOME/$PROJECT/log/nginx.error.log;

  # Yandex Webvisor
  set  \$frame_options  '';
  if (\$http_referer !~ '^https?:\/\/([^\/]+\.)?(PROJECT\.DOMAIN|webvisor\.com)\/'){
    set  \$frame_options  'SAMEORIGIN';
  }
  add_header  X-Frame-Options  \$frame_options;
  # /Yandex Webvisor

  set   \$root  $HOME/$PROJECT;
  set   \$src   \$root/src;

  root  \$src;

  location  ~  ^/media/(uploads|_versions) {}
  location  /static {}

  #set  \$favicon  \$src/static/img/favicon;
  #location  ~  ^/(apple-touch-icon\.png|browserconfig\.xml|safari-pinned-tab\.svg|site\.webmanifest)$ {
  #  root  \$favicon;
  #}
  #location  ~  ^/(android-chrome|favicon|mstile)(.*)\.(ico|png)$ {
  #  root  \$favicon;
  #}
  #location  ~*  ^/(?!sitemap\.xml)[-\w]+\.(txt|xml|html)$ {
  #  root  \$src/media/uploads/seo;
  #}

  client_max_body_size  10M;

  # Django
  location ~ ^/(admin|rest) {
    include  uwsgi_params;

    uwsgi_read_timeout         300;
    uwsgi_ignore_client_abort  on

    uwsgi_pass  unix://\$root/run/uwsgi.sock;
  }

  # NextJS
  location / {
    proxy_pass  http://127.0.0.1:3000;
    proxy_http_version  1.1;

    proxy_set_header  Upgrade     \$http_upgrade;
    proxy_set_header  Connection  "upgrade";
    proxy_set_header  Host        \$host;

    proxy_cache_bypass  \$http_upgrade;
    proxy_read_timeout  300;
  }
}

EOT
sudo ln -s ~/$PROJECT/etc/nginx.conf /etc/nginx/servers/$PROJECT.conf
sudo nginx -t && sudo systemctl reload nginx

# ****************************************************************
# NextJS

cd $PROJECT/src/nextjs
npm ci
npm run build
pm2 start -i 0 --name "$PROJECT" \
          --log /home/web/$PROJECT/log/pm2.log --time \
          --watch --ignore-watch="node_modules" \
          npm -- start -- --hostname=localhost -p 3000
pm2 save
pm2 startup
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u web --hp /home/web
pm2 kill
sudo systemctl start pm2-web
