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
USE_UPSTREAM_CLIENT_CERT=$(get_id_var ${LOCATION_ID} USE_UPSTREAM_CLIENT_CERT)
PORT_IN_HOST_HEADER=$(get_id_var ${LOCATION_ID} PORT_IN_HOST_HEADER)
ENABLE_UUID_PARAM=$(get_id_var ${LOCATION_ID} ENABLE_UUID_PARAM)
ERROR_REDIRECT_CODES=$(get_id_var ${LOCATION_ID} ERROR_REDIRECT_CODES)
ENABLE_WEB_SOCKETS=$(get_id_var ${LOCATION_ID} ENABLE_WEB_SOCKETS)
ADD_NGINX_LOCATION_CFG=$(get_id_var ${LOCATION_ID} ADD_NGINX_LOCATION_CFG)
BASIC_AUTH=$(get_id_var ${LOCATION_ID} BASIC_AUTH)
REQS_PER_MIN_PER_IP=$(get_id_var ${LOCATION_ID} REQS_PER_MIN_PER_IP)
REQS_PER_PAGE=$(get_id_var ${LOCATION_ID} REQS_PER_PAGE)
CONCURRENT_CONNS_PER_IP=$(get_id_var ${LOCATION_ID} CONCURRENT_CONNS_PER_IP)
DENY_COUNTRY_ON=$(get_id_var ${LOCATION_ID} DENY_COUNTRY_ON)

# Backwards compatability
# This tests for the presence of :// which if missing means we do nt have 
# a protocol so we default to http://
if [ "`echo ${PROXY_SERVICE_HOST} | grep '://'`" = "" ]; then
  PROXY_SERVICE_HOST="http://${PROXY_SERVICE_HOST}"
fi

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
    if [ "${EXTRA_NAXSI_RULES}" != "" ]; then
        msg "Adding extra NAXSI rules from environment"
        echo ''>>${NAXSI_LOCATION_RULES}/location.rules
        echo ${EXTRA_NAXSI_RULES}>>${NAXSI_LOCATION_RULES}/${LOCATION_ID}.rules
    fi
fi
# creates .htpasswd file from file
if [[ "${BASIC_AUTH}" == "" ]]; then
  
  echo "Basic Auth not set for Location $LOCATION_ID, skipping..."
else
  HTPASSWD=$(dirname ${BASIC_AUTH})
  if [ -f "$HTPASSWD/.htpasswd_${LOCATION_ID}" ]; then #has the htpasswd file already been created.
    echo "$HTPASSWD/.htpasswd_$LOCATION_ID already created, skipping"
  else
    echo "Creating .htpasswd file from ${BASIC_AUTH} in location ${LOCATION_ID}"
    sed -i '/^$/d' ${BASIC_AUTH} #remove all empty lines.
    while IFS= read line
       do
          #for every line in the file add user and password to .htpasswd
          USER=$(echo $line | cut -d ":" -f 1 |  tr -d '[[:space:]]')
          PASSWORD=$(echo $line | cut -d ":" -f 2 | tr -d '[[:space:]]') #remove whitespace from lines.
          printf "$USER:$(openssl passwd -crypt $PASSWORD)\n" >> ${HTPASSWD}/.htpasswd_$LOCATION_ID
       done < ${BASIC_AUTH}
      rm ${BASIC_AUTH} #delete file now not needed
  fi
  BASIC_AUTH_CONFIG="auth_basic \"Restricted\"; auth_basic_user_file $HTPASSWD/.htpasswd_$LOCATION_ID;"
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
if [ "${USE_UPSTREAM_CLIENT_CERT}" == "TRUE" ]; then
    if [ ! -f /etc/keys/upstream-client-crt ]; then
        exit_error_msg "Missing client public cert, for upstream server, at location:/etc/keys/upstream-client-crt"
    elif [ ! -f /etc/keys/upstream-client-key ]; then
        exit_error_msg "Missing client private key, for upstream server, at location:/etc/keys/upstream-client-key"
    fi
    msg "Will use upstream client certs for '${LOCATION}'."
    SSL_CERTIFICATE="proxy_ssl_certificate /etc/keys/upstream-client-crt; proxy_ssl_certificate_key /etc/keys/upstream-client-key;"
else
    SSL_CERTIFICATE=""
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
elif [ "${ENABLE_UUID_PARAM}" == "HEADER" ]; then
    UUID_ARGS='proxy_set_header nginxId $uuidopt;'
    # Ensure nginx enables this globaly
    msg "Auto UUID request header enabled for location ${LOCATION_ID}."
    touch ${UUID_FILE}
else
    UUID_ARGS='if ($is_args) {set $args $args&nginxId=$uuidopt;} if ($is_args = "") { set $args nginxId=$uuidopt;}'
    # Ensure nginx enables this globaly
    msg "Auto UUID request parameter enabled for location ${LOCATION_ID}."
    touch ${UUID_FILE}
fi

if [ "${ERROR_REDIRECT_CODES}" == "" ]; then
    ERROR_REDIRECT_CODES="${DEFAULT_ERROR_CODES}"
fi
ERROR_PAGES=""
for code in ${ERROR_REDIRECT_CODES}; do
  # Set up an individual error page for each code
  msg "Enabling redirect on status code: ${code}"
  ERROR_PAGES="${ERROR_PAGES} error_page ${code} /nginx-proxy/${code}.shtml;"
done

if [ "${ENABLE_WEB_SOCKETS}" == "TRUE" ]; then
    msg "Enable web socket support"
    WEB_SOCKETS="include ${NGIX_CONF_DIR}/nginx_web_sockets_proxy.conf;"
else
    unset WEB_SOCKETS
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
    echo "limit_req_zone \$${REMOTE_IP_VAR} zone=reqsbuffer${LOCATION_ID}:10m rate=${REQS_PER_MIN_PER_IP}r/m;" \
        >${NGIX_CONF_DIR}/nginx_rate_limits_${LOCATION_ID}.conf
    REQ_LIMITS="limit_req zone=reqsbuffer${LOCATION_ID} ${burst_setting};"
fi
if [ "${CONCURRENT_CONNS_PER_IP}" != "" ]; then
    msg "Enabling CONCURRENT_CONNS_PER_IP:${CONCURRENT_CONNS_PER_IP}"
    echo "limit_conn_zone \$${REMOTE_IP_VAR} zone=connbuffer${LOCATION_ID}:10m;" \
        >>${NGIX_CONF_DIR}/nginx_rate_limits_${LOCATION_ID}.conf
    CONN_LIMITS="limit_conn connbuffer${LOCATION_ID} ${CONCURRENT_CONNS_PER_IP};"
fi
if [ "${DENY_COUNTRY_ON}" == "TRUE" ]; then
    msg "Enabling GeoIP denies, unless IP is one of ${ALLOW_COUNTRY_CSV}, for location ${LOCATION_ID}."
    DENY_COUNTRY="if (\$allowed_country = no) { return 403; }"
fi

# Now create the location specific include file.
cat > /usr/local/openresty/nginx/conf/locations/${LOCATION_ID}.conf <<- EOF_LOCATION_CONF
location ${LOCATION} {
    ${REQ_LIMITS}
    ${CONN_LIMITS}
    ${UUID_ARGS}
    ${CERT_TXT}
    ${ADD_NGINX_LOCATION_CFG}
    ${BASIC_AUTH_CONFIG}
    ${DENY_COUNTRY}

    ${ERROR_PAGES}

    set \$proxy_address "${PROXY_SERVICE_HOST}:${PROXY_SERVICE_PORT}";

    include  ${NAXSI_LOCATION_RULES}/*.rules ;

    ${WEB_SOCKETS}
    $(cat /location_template.conf)
    ${SSL_CERTIFICATE}
    proxy_set_header Host ${PROXY_HOST_SETTING};
    proxy_set_header X-Username "$ssl_client_s_dn_cn";
    proxy_set_header X-Real-IP \$${REMOTE_IP_VAR};

}
EOF_LOCATION_CONF
