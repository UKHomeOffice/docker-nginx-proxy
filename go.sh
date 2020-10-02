#!/usr/bin/env bash

set -e

. /defaults.sh

# Generate a selfsigned key and certificate if we don't have one
if [ ! -f /etc/keys/crt ]; then
  dir=`mktemp -d`
  openssl req -x509 -days 1000 -newkey rsa:2048 -nodes -subj '/CN=waf' -keyout "$dir/key" -out "$dir/crt"
  install -m 0600 -o nginx -g nginx "$dir/key" /etc/keys/key
  install -m 0644 -o nginx -g nginx "$dir/crt" /etc/keys/crt
  rm -rf "$dir"
  SSL_STAPLING=off
fi

cat > /etc/nginx/conf/server_certs.conf <<-EOF_CERT_CONF
    ssl_certificate     /etc/keys/crt;
    ssl_certificate_key /etc/keys/key;
    # Can add SSLv3 for IE 6 but this opens up to poodle
    ssl_protocols TLSv1.2;
    # reduction to only the best ciphers
    # And make sure we prefer them
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling ${SSL_STAPLING:-on};
    ssl_dhparam /etc/nginx/ssl/dhparam.pem;
EOF_CERT_CONF

: "${LOCATIONS_CSV:=/}"

cat > /etc/nginx/conf/nginx_listen.conf <<-EOF-LISTEN
	set \$http_listen_port '${HTTP_LISTEN_PORT}';
	set \$https_listen_port '${HTTPS_LISTEN_PORT}';
	set \$internal_listen_port '10418';
	listen localhost:10418 ssl;
	listen ${HTTP_LISTEN_PORT};
	listen ${HTTPS_LISTEN_PORT} ssl;
EOF-LISTEN

cat > "${NGINX_CONF_DIR}/nginx_server_extras_requestid.conf" <<-EOF-UUID
  set \$uuid $UUID_VARIABLE_NAME;
EOF-UUID

if test -n "${REAL_IP_HEADER:-}" -a -n "${REAL_IP_FROM:-}"; then
cat > /etc/nginx/conf/nginx_server_extras_real_ip.conf <<-EOF-REALIP
    set_real_ip_from '${REAL_IP_FROM}';
    real_ip_header '${REAL_IP_HEADER}';
    real_ip_recursive on;
EOF-REALIP
fi


IFS=',' read -a LOCATIONS_ARRAY <<< "$LOCATIONS_CSV"
for i in "${!LOCATIONS_ARRAY[@]}"; do
    /enable_location.sh $((${i} + 1)) ${LOCATIONS_ARRAY[$i]}
done

dnsmasq -u root -p 5462

msg "Resolving proxied names using resolver:127.0.0.1:5462"

echo "HTTPS_LISTEN_PORT=${HTTPS_LISTEN_PORT}">/tmp/readyness.cfg

if [ -n "${CLIENT_MAX_BODY_SIZE:-}" ]; then
    UPLOAD_SETTING="client_max_body_size ${CLIENT_MAX_BODY_SIZE}m;"
    echo "${UPLOAD_SETTING}">/etc/nginx/conf/upload_size.conf
    msg "Setting '${UPLOAD_SETTING};'"
fi

if [ -n "${CLIENT_BODY_BUFFER_SIZE:-}" ]; then
    UPLOAD_SETTING="client_body_buffer_size ${CLIENT_BODY_BUFFER_SIZE}m;"
    echo "${UPLOAD_SETTING}">>/etc/nginx/conf/upload_size.conf
    msg "Setting '${UPLOAD_SETTING};'"
fi

cat > /etc/nginx/conf/error_logging.conf <<-EOF_ERRORLOGGING
error_log /dev/stderr ${ERROR_LOG_LEVEL:-error};
EOF_ERRORLOGGING

if [ -n "${ADD_NGINX_SERVER_CFG:-}" ]; then
    msg "Adding extra config for server context."
    echo ${ADD_NGINX_SERVER_CFG}>/etc/nginx/conf/nginx_server_extras.conf
fi

if [ -n "${PROXY_STATIC_CACHING:-}" ]; then
# Include the HTTP-level Proxy Cache Configuration.
cat > /etc/nginx/conf/nginx_cache_http.conf <<- EOF_HTTPCACHE_CONF
    # Cache path for static files
    proxy_cache_path /tmp/nginx-cache levels=1:2 keys_zone=staticcache:8m max_size=100m inactive=60m use_temp_path=off;
    # Keyzone size 8MB, Cache size 100MB, Inactive delete 60min
    proxy_cache_key "$scheme$request_method$host$request_uri";
    proxy_cache_valid 200 302 60m; # Cache successful responses for 60 minutes
    proxy_cache_valid 404 1m; # expire 404 responses 1 minute
EOF_HTTPCACHE_CONF
# Check `enable_location.sh` for the Server-block config.
fi

exec nginx -g 'daemon off;'
