#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

log() {
    if [ -n "${1-}" ]; then
        echo "$@"
    else
        while read OUTPUT; do
            echo "$OUTPUT"
        done
    fi
}

check_db() {
    echo 'SELECT 1' | mysql &> /dev/null
}

install_db() {
    log "Installing database..."
    add-pkg --virtual upgrade-deps mariadb mariadb-client jq | log
    # Make sure mariadb listen on port 3306
    #sed-patch 's/^skip-networking/#skip-networking/' /etc/my.cnf.d/mariadb-server.cnf
}

uninstall_db() {
    log "Uninstalling database..."
    del-pkg upgrade-deps | log
}

start_db() {
    log "Starting database..."

    # Start mysqld.
    mkdir -p /run/mysqld
    /usr/bin/mysqld --user=$(whoami) --datadir /home/site/wwwroot/config/mysql --tmpdir /tmp/ &
    pid="$!"

    # Wait until it is ready.
    for i in $(seq 1 30); do
        if check_db; then
            break
        fi
        sleep 1
    done

    if ! check_db; then
        log "ERROR: Failed to start the database."
        exit 1
    fi
}

stop_db() {
    # Kill mysqld.
    log "Shutting down database..."
    if ! kill -s TERM "$pid" || ! wait "$pid"; then
        log "ERROR: Failed to stop the database."
        exit 1
    fi
}

# Check if a mysql database exists.
if [ ! -d /home/site/wwwroot/config/mysql ]; then
    exit 0
fi

# Handle case where a previous conversion didn't went well.
if [ -f /home/site/wwwroot/config/db_convert_in_progress ]; then
    rm -f /home/site/wwwroot/config/database.sqlite
fi

log "MySQL database conversion needed."
touch /home/site/wwwroot/config/db_convert_in_progress

# Temporarily start the database.
install_db
start_db

# Dump the database.
log "Dumping database..."
/usr/bin/mysqldump --skip-extended-insert --compact nginxproxymanager > /tmp/mysqldump.sql

# Convert the database.
log "Converting database..."
/opt/nginx-proxy-manager/bin/mysql2sqlite /tmp/mysqldump.sql | sqlite3 /home/site/wwwroot/config/database.sqlite

# Update the database settings in configuration.
if [ -f /home/site/wwwroot/config/production.json ]; then
    if [ "$(jq -r '.database.engine' /home/site/wwwroot/config/production.json)" == "mysql" ]
    then
        log "Updating database settings in config file..."
        jq -n 'input | .database = input.database' /home/site/wwwroot/config/production.json /defaults/production.json > /home/site/wwwroot/config/production.json.updated
    fi
fi

# Database converted properly.
log "Database conversion done."
rm /home/site/wwwroot/config/db_convert_in_progress
rm /tmp/mysqldump.sql
mv /home/site/wwwroot/config/mysql /home/site/wwwroot/config/mysql.converted
if [ -f /home/site/wwwroot/config/production.json.updated ]; then
    mv /home/site/wwwroot/config/production.json /home/site/wwwroot/config/production.json.old
    mv /home/site/wwwroot/config/production.json.updated /home/site/wwwroot/config/production.json
fi

# Stop the database.
stop_db
uninstall_db

# vim:ft=sh:ts=4:sw=4:et:sts=4
