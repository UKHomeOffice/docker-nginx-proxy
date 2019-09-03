#!/usr/bin/env bash

set -e

. /defaults.sh

# TODO have an identifier to resolve all variables if present:

LOCATION_ID=$1
LOCATION=$2
NAXSI_LOCATION_RULES=/usr/local/openresty/naxsi/locations/${LOCATION_ID}
mkdir -p ${NAXSI_LOCATION_RULES}

# Resolve any location specific variable names here:
PROXY_SERVICE_HOST=$(get_id_var ${LOCATION_ID} PROXY_SERVICE_HOST)
PROXY_SERVICE_PORT=$(get_id_var ${LOCATION_ID} PROXY_SERVICE_PORT)
NAXSI_RULES_URL_CSV=$(get_id_var ${LOCATION_ID} NAXSI_RULES_URL_CSV)
NAXSI_RULES_MD5_CSV=$(get_id_var ${LOCATION_ID} NAXSI_RULES_MD5_CSV)
NAXSI_USE_DEFAULT_RULES=$(get_id_var ${LOCATION_ID} NAXSI_USE_DEFAULT_RULES)
ENABLE_UUID_PARAM=$(get_id_var ${LOCATION_ID} ENABLE_UUID_PARAM)
ADD_NGINX_LOCATION_CFG=$(get_id_var ${LOCATION_ID} ADD_NGINX_LOCATION_CFG)
REQS_PER_MIN_PER_IP=$(get_id_var ${LOCATION_ID} REQS_PER_MIN_PER_IP)
REQS_PER_PAGE=$(get_id_var ${LOCATION_ID} REQS_PER_PAGE)

msg "Setting up location '${LOCATION}' to be proxied to " \
    "${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}${LOCATION}"

eval PROXY_HOST=$(eval "echo $PROXY_SERVICE_HOST")
export PROXY_SERVICE_PORT=$(eval "echo $PROXY_SERVICE_PORT")

# Detect default configuration...
md5sum ${NGIX_CONF_DIR}/nginx.conf | cut -d' ' -f 1 >/tmp/nginx_new
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
    msg "Core NAXSI rules enabled @ /usr/local/openresty/naxsi/naxsi_core.rules"
    msg "NAXSI location rules enabled @ ${NAXSI_LOCATION_RULES}/${LOCATION_ID}.rules"
    cp /usr/local/openresty/naxsi/location.template ${NAXSI_LOCATION_RULES}/${LOCATION_ID}.rules
fi

if [ "${ENABLE_UUID_PARAM}" == "FALSE" ]; then
    UUID_ARGS=''
    msg "Auto UUID request parameter disabled for location ${LOCATION_ID}."
elif [ "${ENABLE_UUID_PARAM}" == "HEADER" ]; then
    UUID_ARGS="proxy_set_header X-Request-Id \$request_id;"
    # Ensure nginx enables this globaly
    msg "Auto UUID request header enabled for location ${LOCATION_ID}."
fi

if [ "${ADD_NGINX_LOCATION_CFG}" != "" ]; then
    msg "Enabling extra ADD_NGINX_LOCATION_CFG:${ADD_NGINX_LOCATION_CFG}"
fi
#nginx_var_for_loc=$(get_namefrom_number ${LOCATION_ID})
if [ "${REQS_PER_MIN_PER_IP}" != "" ]; then
    REQS_PER_PAGE=${REQS_PER_PAGE:-20}
    msg "Enabling REQS_PER_MIN_PER_IP:${REQS_PER_MIN_PER_IP}"
    msg "Enabling REQS_PER_PAGE:${REQS_PER_PAGE}"
    if [ "${REQS_PER_PAGE}" != "0" ]; then
      burst_setting="burst=${REQS_PER_PAGE}"
    else
      unset burst_setting
    fi
    echo "limit_req_zone \$remote_addr zone=reqsbuffer${LOCATION_ID}:10m rate=${REQS_PER_MIN_PER_IP}r/m;" \
        >${NGIX_CONF_DIR}/nginx_rate_limits_${LOCATION_ID}.conf
    REQ_LIMITS="limit_req zone=reqsbuffer${LOCATION_ID} ${burst_setting};"
fi

# Now create the location specific include file.
cat > /usr/local/openresty/nginx/conf/locations/${LOCATION_ID}.conf <<- EOF_LOCATION_CONF
location ${LOCATION} {
    set \$uuid \$request_id;
    ${REQ_LIMITS}
    ${UUID_ARGS}
    ${ADD_NGINX_LOCATION_CFG}

    set \$proxy_address "${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}";

    include  ${NAXSI_LOCATION_RULES}/*.rules ;

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
