#!/usr/bin/env bash

project_base="$HOME/SITE-FOLDER"

# Restart RQ
rqworker_name="$(basename $project_base)-rqworker"
rqworker_pidfile="$project_base/etc/rqworker.pid"
pkill -e -F "$rqworker_pidfile" || true
"$project_base/.env/bin/python" "$project_base/app/manage.py" \
    rqworker --name "$rqworker_name" --pid "$rqworker_pidfile" \
    > "$project_base/log/rqworker.log" 2>&1 &

# Reload uWSGI
touch "$project_base/reload"
