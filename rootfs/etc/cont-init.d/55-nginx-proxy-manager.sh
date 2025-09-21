#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

log() {
    echo "$@"
}

# Make sure mandatory directories exist.
mkdir -p \
    /home/site/wwwroot/config/log \
    /home/site/wwwroot/config/letsencrypt/archive \
    /home/site/wwwroot/config/letsencrypt-acme-challenge \
    /home/site/wwwroot/config/custom_ssl \
    /home/site/wwwroot/config/access \
    /home/site/wwwroot/config/nginx/default_host \
    /home/site/wwwroot/config/nginx/default_www \
    /home/site/wwwroot/config/nginx/cache \
    /home/site/wwwroot/config/nginx/proxy_host \
    /home/site/wwwroot/config/nginx/redirection_host \
    /home/site/wwwroot/config/nginx/stream \
    /home/site/wwwroot/config/nginx/dead_host \
    /home/site/wwwroot/config/nginx/temp \
    /home/site/wwwroot/config/log/letsencrypt \
    /home/site/wwwroot/config/letsencrypt-workdir \

# Make sure directories required for nginx exist.
for DIR in /var/run/nginx /var/tmp/nginx
do
    mkdir -p "$DIR"
    chown app:app "$DIR"
done

# Create symlinks for logs.
[ ! -L /home/site/wwwroot/config/log/log ] || rm /home/site/wwwroot/config/log/log
ln -snf log /home/site/wwwroot/config/logs

# Make sure to remove old letsencrypt config file.
[ ! -f $XDG_CONFIG_HOME/letsencrypt/cli.ini ] || mv $XDG_CONFIG_HOME/letsencrypt/cli.ini $XDG_CONFIG_HOME/letsencrypt/cli.ini.removed

# Fix any references to the old log path.
find /home/site/wwwroot/config/nginx -not \( -path /home/site/wwwroot/config/nginx/custom -prune \) -type f -name '*.conf' | while read file
do
    sed -i 's|/data/logs/|/home/site/wwwroot/config/log/|' "$file"
done

# Install default config.
[ -f /home/site/wwwroot/config/nginx/ip_ranges.conf ] || cp /defaults/ip_ranges.conf /home/site/wwwroot/config/nginx/
[ -f /home/site/wwwroot/config/production.json ] || cp /defaults/production.json /home/site/wwwroot/config/

# Make sure there is no migration lock held.
# See https://github.com/jlesage/docker-nginx-proxy-manager/issues/4
if [ -f /home/site/wwwroot/config/database.sqlite ]; then
    echo 'DELETE FROM migrations_lock WHERE is_locked = 1;' | sqlite3 /home/site/wwwroot/config/database.sqlite
fi

# Generate the resolvers configuration file.
if [ "$DISABLE_IPV6" == "true" ] || [ "$DISABLE_IPV6" == "on" ] || [ "$DISABLE_IPV6" == "1" ] || [ "$DISABLE_IPV6" == "yes" ];
then
    echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" { sub(/%.*$/,"",$2); print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf) ipv6=off valid=10s;" > /etc/nginx/conf.d/include/resolvers.conf
else
    echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" { sub(/%.*$/,"",$2); print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf) valid=10s;" > /etc/nginx/conf.d/include/resolvers.conf
fi

# Handle IPv6 settings.
/opt/nginx-proxy-manager/bin/handle-ipv6-setting /etc/nginx/conf.d
/opt/nginx-proxy-manager/bin/handle-ipv6-setting /home/site/wwwroot/config/nginx

# vim:ft=sh:ts=4:sw=4:et:sts=4
