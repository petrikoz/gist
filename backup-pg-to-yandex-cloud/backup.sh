#!/bin/sh

BASE_DIR=/root/yandex-cloud
PROJECT=НАЗВАНИЕ-ПРОЕКТА

BACKUPS_DIR="$BASE_DIR/backups"
mkdir  -m 700 -p "$BACKUPS_DIR"

DB_BACKUP_TMP="/tmp/$PROJECT.sql"
sudo -u postgres pg_dump -d $PROJECT -f "$DB_BACKUP_TMP" -bcO --column-inserts

mv "$DB_BACKUP_TMP" "$BACKUPS_DIR/${PROJECT}_$(date '+%Y-%m-%d %H:%M:%S').sql"

"$BASE_DIR/rclone" --config "$BASE_DIR/rclone.conf" copy "$BACKUPS_DIR" "yandex_cloud:$PROJECT" > "$BASE_DIR/rclone.log" 2>&1
