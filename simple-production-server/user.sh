# ****************************************************************
# PROJECT

mkdir -p ~/etc ~/log ~/run ~/tmp

git clone git@github.com:ITCase/PROJECT.git ~/src

poetry install --no-root --without=dev,test

cp production/local.py settings/local.py
vi settings/local.py
    # change data

./manage.py collectstatic --no-input

# ****************************************************************
# POSTGRESQL

# добавляем пользователя и базу для проекта
sudo -u postgres psql
    # run:
    #     CREATE USER PROJECT WITH PASSWORD 'PASSWORD';
    #     CREATE DATABASE PROJECT WITH OWNER PROJECT;
    #     GRANT ALL ON DATABASE PROJECT TO PROJECT;
./manage.py showmigrations
./manage.py migrate
./manage.py createsuperuser

# ****************************************************************
# SUPERVISOR

cp ~/src/production/supervisord.ini ~/etc/supervisord.ini

# ****************************************************************
# UWSGI

touch ~/etc/uwsgi-reload
sudo cp ~/src/production/uwsgi.ini /etc/uwsgi/vassals/PROJECT.ini

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

 echo GITHUB-TOKEN | docker login ghcr.io --username GITHUB-USER --password-stdin
docker pull ghcr.io/itcase/PROJECT-web:prod-YYYYMMDD
docker logout ghcr.io
docker run -d --restart=always -p 127.0.0.1:3000:3000 --name PROJECT-web-YYYYMMDD ghcr.io/itcase/PROJECT-web:prod-YYYYMMDD
# если уже есть запщуенный фронт, то делаем так
docker create --restart=always -p 127.0.0.1:3000:3000 --name PROJECT-web-YYYYMMDD ghcr.io/itcase/PROJECT-web:prod-YYYYMMDD
docker rm -f PROJECT-web-ПРЕДЫДУЩАЯ_YYYYMMDD && docker start PROJECT-web-YYYYMMDD