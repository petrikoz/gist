# Gist

Local replacement for [my GitHub Gist](https://gist.github.com/petrikoz).

## backup-pg-to-yandex-cloud

Backup dump of PostgreSQL's database to [Yandex Cloud](https://cloud.yandex.ru/).

Usage under `root` user:

```shell
mkdir -m 640 /root/backup-pg-to-yandex-cloud
cd /root/backup-pg-to-yandex-cloud

# rclone
wget https://downloads.rclone.org/rclone-current-linux-amd64.zip
unzip rclone-current-linux-amd64.zip
cp rclone-*-linux-amd64/rclone ./
chown root:root rclone
chmod 700 rclone
rm -rf rclone-*-linux-amd64*
wget https://raw.githubusercontent.com/petrikoz/gist/master/backup-pg-to-yandex-cloud/rclone.conf
chmod 600 rclone.conf
# put your data to rclone.conf

# script
wget https://raw.githubusercontent.com/petrikoz/gist/master/backup-pg-to-yandex-cloud/backup.sh
chmod 700 backup.sh
# put your data to backup.sh

# cron
(crontab -l ; echo "0 8-23 * * *    /bin/sh /root/backup-pg-to-yandex-cloud/backup.sh > /root/backup-pg-to-yandex-cloud/backup.log 2>&1") | sort - | uniq - | crontab -
```

## github-ssh-import-id.py

Copy available SSH keys from [GitHub](https://docs.github.com/en/rest) by username

Usage:

```shell
whet https://raw.githubusercontent.com/petrikoz/gist/master/github-ssh-import-id.py
pip install httpx
chmod u+x github-ssh-import-id.py
python3 ssh-import-id.py USERNAME USERNAME_1 USERNAME_2
```

## google-spreadsheet-to-json.py

Convert public (should be available for read via link) Google Spreadsheet to JSON

```shell
whet https://raw.githubusercontent.com/petrikoz/gist/master/google-spreadsheet-to-json.py
pip install httpx
chmod u+x google-spreadsheet-to-json.py
python3 google-spreadsheet-to-json.py 'SPREADSHEET-ID-FROM-ITS-LINK'
```

## netangels-hosting-reload-rq.sh

Add support [Django RQ](https://github.com/rq/django-rq) to [uWSGI reload](https://uwsgi-docs-additions.readthedocs.io/en/latest/Options.html#touch-reload) on [NetAngels hosting](https://www.netangels.ru/hosting/).

```shell
whet https://raw.githubusercontent.com/petrikoz/gist/master/netangels-hosting-reload-rq.sh
# put your data to netangels-hosting-reload-rq.sh
chmod 755 netangels-hosting-reload-rq.sh
```

## netangels-ssl-renew

Renew SSL certificates on [NetAngels' VDS](https://www.netangels.ru/cloud/) via [API](https://api.netangels.ru/modules/gateway_api.api.certificates/)

Usage under `root` user:

```shell
mkdir -m 640 /root/netangels-ssl-renew
cd /root/netangels-ssl-renew

# script
pip3 install httpx psutil
wget https://raw.githubusercontent.com/petrikoz/gist/master/netangels-ssl-renew/ssl-renew.py
chmod 700 ssl-renew.py

# config
wget https://raw.githubusercontent.com/petrikoz/gist/master/netangels-ssl-renew/config.ini
# put your data to config.ini

# cron
(crontab -l ; echo "43 2 * * *    /usr/bin/env /root/netangels-ssl-renew/ssl-renew.py > /root/netangels-ssl-renew/ssl-renew.log 2>&1") | sort - | uniq - ↪ | crontab -
```

## simple-production-server

Simple production server for 'Django + NextJS' projects.

* `root.sh` — commands run under `root` user
* `user.sh` — commands run under created simple user
