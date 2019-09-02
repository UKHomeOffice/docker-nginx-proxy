#!/usr/bin/env bash

set -e

export LOG_UUID=FALSE

. /defaults.sh

# Generate a selfsigned key and certificate if we don't have one
if [ ! -f /etc/keys/crt ]; then
  dir=`mktemp -d`
  openssl req -x509 -days 1000 -newkey rsa:2048 -nodes -subj '/CN=waf' -keyout "$dir/key" -out "$dir/crt"
  install -m 0600 -o nginx -g nginx "$dir/key" /etc/keys/key
  install -m 0644 -o nginx -g nginx "$dir/crt" /etc/keys/crt
  rm -rf "$dir"
fi

cat > ${NGIX_CONF_DIR}/server_certs.conf <<-EOF_CERT_CONF
    ssl_certificate     ${SERVER_CERT};
    ssl_certificate_key ${SERVER_KEY};
    # Can add SSLv3 for IE 6 but this opens up to poodle
    ssl_protocols ${SSL_PROTOCOLS};
    # reduction to only the best ciphers
    # And make sure we prefer them
    ssl_ciphers ${SSL_CIPHERS};
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_dhparam ${NGIX_CONF_DIR}/dhparam.pem;
EOF_CERT_CONF

: "${LOCATIONS_CSV:=/}"

INTERNAL_LISTEN_PORT="${INTERNAL_LISTEN_PORT:-10418}"
NGIX_LISTEN_CONF="${NGIX_CONF_DIR}/nginx_listen.conf"

cat > ${NGIX_LISTEN_CONF} <<-EOF-LISTEN
		set \$http_listen_port '${HTTP_LISTEN_PORT}';
		set \$https_listen_port '${HTTPS_LISTEN_PORT}';
		set \$internal_listen_port '${INTERNAL_LISTEN_PORT}';
		listen localhost:${INTERNAL_LISTEN_PORT} ssl;
EOF-LISTEN

cat >> ${NGIX_LISTEN_CONF} <<-EOF-LISTEN-NONPP
	listen ${HTTP_LISTEN_PORT};
	listen ${HTTPS_LISTEN_PORT} ssl;
	set \$real_client_ip_if_set '';
EOF-LISTEN-NONPP

IFS=',' read -a LOCATIONS_ARRAY <<< "$LOCATIONS_CSV"
for i in "${!LOCATIONS_ARRAY[@]}"; do
    /enable_location.sh $((${i} + 1)) ${LOCATIONS_ARRAY[$i]}
done

if [ -z "${NAME_RESOLVER:-}" ]; then
    if [ "${DNSMASK}" == "TRUE" ]; then
        dnsmasq -p 5462
        export NAME_RESOLVER=127.0.0.1:5462
    else
        export NAME_RESOLVER=$(grep 'nameserver' /etc/resolv.conf | head -n1 | cut -d' ' -f2)
    fi
fi

cat > ${NGIX_CONF_DIR}/ssl_redirect.conf <<-EOF-REDIRECT-TRUE
if (\$ssl_protocol = "") {
  rewrite ^ https://\$host\$request_uri? permanent;
}
EOF-REDIRECT-TRUE

msg "Resolving proxied names using resolver:${NAME_RESOLVER}"
echo "resolver ${NAME_RESOLVER};">${NGIX_CONF_DIR}/resolver.conf

echo "HTTPS_LISTEN_PORT=${HTTPS_LISTEN_PORT}">/tmp/readyness.cfg

if [ -f ${UUID_FILE} ]; then
    export LOG_UUID=TRUE
fi
if [ -n "${CLIENT_MAX_BODY_SIZE:-}" ]; then
    UPLOAD_SETTING="client_max_body_size ${CLIENT_MAX_BODY_SIZE}m;"
    echo "${UPLOAD_SETTING}">${NGIX_CONF_DIR}/upload_size.conf
    msg "Setting '${UPLOAD_SETTING};'"
fi

if [ -f /etc/keys/client-ca ]; then
    msg "Loading client certs."
    cat > ${NGIX_CONF_DIR}/client_certs.conf <<-EOF_CLIENT_CONF
      ssl_client_certificate /etc/keys/client-ca;
      ssl_verify_client optional;
EOF_CLIENT_CONF
else
    msg "No client certs mounted - not loading..."
fi

cat >> ${NGIX_CONF_DIR}/error_logging.conf <<-EOF_ERRORLOGGING
error_log /dev/stderr ${ERROR_LOG_LEVEL:-error};
EOF_ERRORLOGGING

case "${LOG_FORMAT_NAME}" in
    json|text|custom)
        msg "Logging set to ${LOG_FORMAT_NAME}"

        if [ "${LOG_FORMAT_NAME}" = "custom" ]; then
            : "${CUSTOM_LOG_FORMAT?ERROR:Custom log format specified, but no 'CUSTOM_LOG_FORMAT' given}"

            cat >> ${NGIX_CONF_DIR}/logging.conf <<- EOF_LOGGING
log_format extended_${LOG_FORMAT_NAME} '{'
${CUSTOM_LOG_FORMAT}
'}';
EOF_LOGGING
        fi

        if [ "${NO_LOGGING_URL_PARAMS:-}" == TRUE ]; then
            sed -i -e 's/\$request_uri/\$uri/g' ${NGIX_CONF_DIR}/logging.conf
        fi

        if [ "${NO_LOGGING_BODY:-}" == TRUE ]; then
            sed --in-place '/\$request_body/d' ${NGIX_CONF_DIR}/logging.conf
        fi

        if [ "${NO_LOGGING_RESPONSE:-}" == TRUE ]; then
            sed --in-place '/\$response_body/d' ${NGIX_CONF_DIR}/logging.conf
            touch ${NGIX_CONF_DIR}/response_body.conf
        else
		cat > ${NGIX_CONF_DIR}/response_body.conf <<-EOF-LOGGING-BODY-TRUE

			lua_need_request_body on;
                        set \$response_body "";
			body_filter_by_lua '
				local resp_body = string.sub(ngx.arg[1], 1, 1000)
				ngx.ctx.buffered = (ngx.ctx.buffered or "") .. resp_body
				if ngx.arg[2] then
					ngx.var.response_body = ngx.ctx.buffered
				end
			';
EOF-LOGGING-BODY-TRUE
        fi

        echo "map \$request_uri \$loggable { ~^/nginx_status/  0; default 1;}">>${NGIX_CONF_DIR}/logging.conf #remove logging for the sysdig agent.
        echo "access_log /dev/stdout extended_${LOG_FORMAT_NAME} if=\$loggable;" >> ${NGIX_CONF_DIR}/logging.conf
        ;;
    *)
        exit_error_msg "Invalid log format specified:${LOG_FORMAT_NAME}. Expecting custom, json or text."
    ;;
esac

if [ -n "${ADD_NGINX_SERVER_CFG:-}" ]; then
    msg "Adding extra config for server context."
    echo ${ADD_NGINX_SERVER_CFG}>${NGIX_CONF_DIR}/nginx_server_extras.conf
fi

if [ -n "${ADD_NGINX_HTTP_CFG:-}" ]; then
    msg "Adding extra config for http context."
    echo ${ADD_NGINX_HTTP_CFG}>${NGIX_CONF_DIR}/nginx_http_extras.conf
fi

eval "${NGINX_BIN} -g \"daemon off;\""
