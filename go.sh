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
    ssl_stapling on;
    ssl_dhparam ${NGIX_CONF_DIR}/dhparam.pem;
EOF_CERT_CONF

: "${LOCATIONS_CSV:=/}"

NGIX_LISTEN_CONF="${NGIX_CONF_DIR}/nginx_listen.conf"

cat > ${NGIX_LISTEN_CONF} <<-EOF-LISTEN
	set \$http_listen_port '${HTTP_LISTEN_PORT}';
	set \$https_listen_port '${HTTPS_LISTEN_PORT}';
	set \$internal_listen_port '10418';
	listen localhost:10418 ssl;
	listen ${HTTP_LISTEN_PORT};
	listen ${HTTPS_LISTEN_PORT} ssl;
	set \$real_client_ip_if_set '';
EOF-LISTEN

IFS=',' read -a LOCATIONS_ARRAY <<< "$LOCATIONS_CSV"
for i in "${!LOCATIONS_ARRAY[@]}"; do
    /enable_location.sh $((${i} + 1)) ${LOCATIONS_ARRAY[$i]}
done

dnsmasq -p 5462

msg "Resolving proxied names using resolver:127.0.0.1:5462"

echo "HTTPS_LISTEN_PORT=${HTTPS_LISTEN_PORT}">/tmp/readyness.cfg

if [ -f ${UUID_FILE} ]; then
    export LOG_UUID=TRUE
fi
if [ -n "${CLIENT_MAX_BODY_SIZE:-}" ]; then
    UPLOAD_SETTING="client_max_body_size ${CLIENT_MAX_BODY_SIZE}m;"
    echo "${UPLOAD_SETTING}">${NGIX_CONF_DIR}/upload_size.conf
    msg "Setting '${UPLOAD_SETTING};'"
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

      sed --in-place '/\$request_body/d' ${NGIX_CONF_DIR}/logging.conf
      sed --in-place '/\$response_body/d' ${NGIX_CONF_DIR}/logging.conf
      touch ${NGIX_CONF_DIR}/response_body.conf
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

eval "${NGINX_BIN} -g \"daemon off;\""
