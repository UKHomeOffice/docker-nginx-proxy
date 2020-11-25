#!/usr/bin/env bash

set -e

. /defaults.sh

# TODO have an identifier to resolve all variables if present:

LOCATION_ID=$1
LOCATION=$2
NAXSI_LOCATION_RULES=/etc/nginx/naxsi/locations/${LOCATION_ID}
mkdir -p ${NAXSI_LOCATION_RULES}

# Resolve any location specific variable names here:
PROXY_SERVICE_HOST=$(get_id_var ${LOCATION_ID} PROXY_SERVICE_HOST)
PROXY_SERVICE_PORT=$(get_id_var ${LOCATION_ID} PROXY_SERVICE_PORT)
NAXSI_RULES_URL_CSV=$(get_id_var ${LOCATION_ID} NAXSI_RULES_URL_CSV)
NAXSI_RULES_MD5_CSV=$(get_id_var ${LOCATION_ID} NAXSI_RULES_MD5_CSV)
NAXSI_USE_DEFAULT_RULES=$(get_id_var ${LOCATION_ID} NAXSI_USE_DEFAULT_RULES)
REQS_PER_SEC=$(get_id_var ${LOCATION_ID} REQS_PER_SEC)
REQS_PER_PAGE=$(get_id_var ${LOCATION_ID} REQS_PER_PAGE)
RATE_LIMIT_DELAY=$(get_id_var ${LOCATION_ID} RATE_LIMIT_DELAY)
RATE_LIMIT_ZONE_KEY=$(get_id_var ${LOCATION_ID} RATE_LIMIT_ZONE_KEY)
UUID_VARIABLE_NAME=$(get_id_var ${LOCATION_ID} UUID_VARIABLE_NAME)

msg "Setting up location '${LOCATION}' to be proxied to " \
    "${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}${LOCATION}"

eval PROXY_HOST=$(eval "echo $PROXY_SERVICE_HOST")
export PROXY_SERVICE_PORT=$(eval "echo $PROXY_SERVICE_PORT")

# Detect default configuration...
md5sum /etc/nginx/nginx.conf | cut -d' ' -f 1 >/tmp/nginx_new
if diff /container_default_ngx /tmp/nginx_new ; then
    if [ "$PROXY_SERVICE_HOST" == "" ] || [ "$PROXY_SERVICE_PORT" == "" ] || [ "$PROXY_HOST" == "" ]; then
        echo "Default config requires PROXY_SERVICE_HOST and PROXY_SERVICE_PORT to be set."
        echo "PROXY_SERVICE_HOST=$PROXY_HOST"
        echo "PROXY_SERVICE_PORT=$PROXY_SERVICE_PORT"
        exit 1
    fi
    msg "Proxying to : $PROXY_SERVICE_HOST:$PROXY_SERVICE_PORT"
fi


if [ "${NAXSI_RULES_URL_CSV}" != "" ]; then
    if [ "${NAXSI_RULES_MD5_CSV}" == "" ]; then
        exit_error_msg "Error, must specify NAXSI_RULES_MD5_CSV if NAXSI_RULES_URL_CSV is specified"
    fi
    IFS=',' read -a NAXSI_RULES_URL_ARRAY <<< "$NAXSI_RULES_URL_CSV"
    IFS=',' read -a NAXSI_RULES_MD5_ARRAY <<< "$NAXSI_RULES_MD5_CSV"
    if [ ${#NAXSI_RULES_URL_ARRAY[@]} -ne ${#NAXSI_RULES_MD5_ARRAY[@]} ]; then
        exit_error_msg "Must specify the same number of items in \$NAXSI_RULES_URL_CSV and \$NAXSI_RULES_MD5_CSV"
    fi
    for i in "${!NAXSI_RULES_URL_ARRAY[@]}"; do
        download ${NAXSI_RULES_URL_ARRAY[$i]} ${NAXSI_RULES_MD5_ARRAY[$i]} ${NAXSI_LOCATION_RULES}
    done
fi
if [ "${NAXSI_USE_DEFAULT_RULES}" == "FALSE" ]; then
    msg "Not setting up NAXSI default rules for location:'${LOCATION}'"
else
    msg "Core NAXSI rules enabled @ /etc/nginx/naxsi/naxsi_core.rules"
    msg "NAXSI location rules enabled @ ${NAXSI_LOCATION_RULES}/${LOCATION_ID}.rules"
    cp /etc/nginx/naxsi/location.template ${NAXSI_LOCATION_RULES}/${LOCATION_ID}.rules
fi

if [ "${REQS_PER_SEC}" != "" ]; then
    REQS_PER_PAGE=${REQS_PER_PAGE:-20}
    RATE_LIMIT_DELAY=${RATE_LIMIT_DELAY:-""}
    RATE_LIMIT_ZONE_KEY=${RATE_LIMIT_ZONE_KEY:-"binary_remote_addr"}
    msg "Enabling REQS_PER_SEC:${REQS_PER_SEC}"
    msg "Enabling REQS_PER_PAGE:${REQS_PER_PAGE}"
    msg "Enabling RATE_LIMIT_DELAY:${RATE_LIMIT_DELAY}"
    msg "Using RATE_LIMIT_ZONE_KEY:${RATE_LIMIT_ZONE_KEY}"
    if [ "${REQS_PER_PAGE}" != "0" ]; then
      burst_setting="burst=${REQS_PER_PAGE}"
    else
      unset burst_setting
    fi
    echo "limit_req_zone \$${RATE_LIMIT_ZONE_KEY} zone=reqsbuffer${LOCATION_ID}:10m rate=${REQS_PER_SEC}r/s;" \
        >/etc/nginx/conf/nginx_rate_limits_${LOCATION_ID}.conf
    REQ_LIMITS="limit_req zone=reqsbuffer${LOCATION_ID} ${burst_setting} ${RATE_LIMIT_DELAY};"
fi

# Now create the location specific include file.
cat > /etc/nginx/conf/locations/${LOCATION_ID}.conf <<- EOF_LOCATION_CONF
location ${LOCATION} {
    set \$uuid ${UUID_VARIABLE_NAME};
    ${REQ_LIMITS}
    proxy_set_header X-Request-Id \$uuid;

    set \$proxy_address "${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}";

    include  ${NAXSI_LOCATION_RULES}/*.rules ;

    # We need to re-use these later, but cannot use include due to using variables.
    set \$_request \$request;
    if (\$_request ~ (.*)email=[^&+]*(.*)) {
        set \$_request \$1email=****\$2;
    }
    set \$_http_referer \$http_referer;
    if (\$_http_referer ~ (.*)email=[^&+]*(.*)) {
        set \$_http_referer \$1email=****\$2;
    }

    set \$backend_upstream "\$proxy_address";
    proxy_pass \$backend_upstream;
    proxy_redirect  off;
    proxy_intercept_errors on;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Host \$host:\$server_port;
    proxy_set_header X-Real-IP \$remote_addr;

}
EOF_LOCATION_CONF

# If Static Caching is enabled, add Cache Config for the Server Block...
if [ -n "${PROXY_STATIC_CACHING:-}" ]; then
ESCAPED_LOCATION=$(eval "echo $LOCATION | sed 's;/;\\\/;g'")

cat >> /etc/nginx/conf/locations/${LOCATION_ID}.conf <<-EOF_SERVERCACHE_CONF

# Allow Nginx to cache static assets - follow the same proxy config as above.
location ~* ^${ESCAPED_LOCATION}(.+)\.(jpg|jpeg|gif|png|svg|ico|css|bmp|js|html|htm|ttf|otf|eot|woff|woff2)$ {
    proxy_cache staticcache;
    add_header X-Proxy-Cache $upstream_cache_status; # Hit or Miss

    # Nginx cache to ignore Node.js "Cache-Control: public, max-age=0"
    proxy_ignore_headers Cache-Control;
    proxy_hide_header Cache-Control;
    add_header Cache-Control "public";
    expires 60m; # "Cache-Control: max-age=3600" tells client to cache for 60 minutes

    set \$uuid ${UUID_VARIABLE_NAME};
    ${REQ_LIMITS}
    proxy_set_header X-Request-Id \$uuid;

    set \$proxy_address "${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}";

    include  ${NAXSI_LOCATION_RULES}/*.rules ;

    # Re-use these again...
    set \$_request \$request;
    if (\$_request ~ (.*)email=[^&+]*(.*)) {
        set \$_request \$1email=****\$2;
    }
    set \$_http_referer \$http_referer;
    if (\$_http_referer ~ (.*)email=[^&+]*(.*)) {
        set \$_http_referer \$1email=****\$2;
    }

    set \$backend_upstream "\$proxy_address";
    proxy_pass \$backend_upstream;
    proxy_redirect  off;
    proxy_intercept_errors on;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Host \$host:\$server_port;
    proxy_set_header X-Real-IP \$remote_addr;
}
EOF_SERVERCACHE_CONF
fi