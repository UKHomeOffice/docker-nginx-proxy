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
EXTRA_NAXSI_RULES=$(get_id_var ${LOCATION_ID} EXTRA_NAXSI_RULES)
CLIENT_CERT_REQUIRED=$(get_id_var ${LOCATION_ID} CLIENT_CERT_REQUIRED)
PORT_IN_HOST_HEADER=$(get_id_var ${LOCATION_ID} PORT_IN_HOST_HEADER)
ENABLE_UUID_PARAM=$(get_id_var ${LOCATION_ID} ENABLE_UUID_PARAM)
ERROR_REDIRECT_CODES=$(get_id_var ${LOCATION_ID} ERROR_REDIRECT_CODES)

msg "Setting up location '${LOCATION}' to be proxied to " \
    "http://${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}${LOCATION}"

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
    msg "Proxying to : http://$PROXY_SERVICE_HOST:$PROXY_SERVICE_PORT"
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
    if [ "${EXTRA_NAXSI_RULES}" != "" ]; then
        msg "Adding extra NAXSI rules from environment"
        echo ''>>${NAXSI_LOCATION_RULES}/location.rules
        echo ${EXTRA_NAXSI_RULES}>>${NAXSI_LOCATION_RULES}/${LOCATION_ID}.rules
    fi
fi

if [ "${CLIENT_CERT_REQUIRED}" == "TRUE" ]; then
    if [ ! -f /etc/keys/client-ca ]; then
        exit_error_msg "Missing client CA cert at location:/etc/keys/client-ca"
    fi
    msg "Denying access to '${LOCATION}' for clients with no certs."
    CERT_TXT="if (\$ssl_client_verify != SUCCESS) { return 403; }"
    export LOAD_CLIENT_CA=TRUE
else
    CERT_TXT=""
fi

if [ "${PORT_IN_HOST_HEADER}" == "FALSE" ]; then
    msg "Setting host only proxy header"
    PROXY_HOST_SETTING='$host'
else
    msg "Setting host and port proxy header"
    PROXY_HOST_SETTING='$host:$server_port'
fi
if [ "${ENABLE_UUID_PARAM}" == "FALSE" ]; then
    UUID_ARGS=''
    msg "Auto UUID request parameter disabled for location ${LOCATION_ID}."
else
    UUID_ARGS='set $args $args$uuidopt;'
    # Ensure nginx enables this globaly
    msg "Auto UUID request parameter enabled for location ${LOCATION_ID}."
    touch ${UUID_FILE}
fi
if [ "${ERROR_REDIRECT_CODES}" == "" ]; then
    ERROR_REDIRECT_CODES="${DEFAULT_ERROR_CODES}"
fi
# Now create the location specific include file.
cat > /usr/local/openresty/nginx/conf/locations/${LOCATION_ID}.conf <<- EOF_LOCATION_CONF
location ${LOCATION} {
    ${UUID_ARGS}
    ${CERT_TXT}

    error_page ${ERROR_REDIRECT_CODES} /50x.html;

    set \$proxy_address "${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}";

    include  ${NAXSI_LOCATION_RULES}/*.rules ;

    $(cat /location_template.conf)
    proxy_set_header Host ${PROXY_HOST_SETTING};
    proxy_set_header X-Username "$ssl_client_s_dn_cn";
}
EOF_LOCATION_CONF
