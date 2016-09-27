#!/usr/bin/env bash

set -e

export LOG_UUID=FALSE

. /defaults.sh

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


if [ "${LOCATIONS_CSV}" == "" ]; then
    LOCATIONS_CSV=/
fi

if [ "${LOAD_BALANCER_CIDR}" != "" ]; then
    msg "Using proxy_protocol from '$LOAD_BALANCER_CIDR' (real client ip is forwarded correctly by loadbalancer)..."
    export REMOTE_IP_VAR="proxy_protocol_addr"
    cat > ${NGIX_CONF_DIR}/nginx_listen.conf <<-EOF-LISTEN-PP
		listen ${HTTP_LISTEN_PORT} proxy_protocol;
		listen ${HTTPS_LISTEN_PORT} proxy_protocol ssl;
		real_ip_recursive on;
		real_ip_header proxy_protocol;
		set \$real_client_ip_if_set '\$proxy_protocol_addr ';
		set_real_ip_from ${LOAD_BALANCER_CIDR};
	EOF-LISTEN-PP
else
    msg "No \$LOAD_BALANCER_CIDR set, using straight SSL (client ip will be from loadbalancer if used)..."
    export REMOTE_IP_VAR="remote_addr"
    cat > ${NGIX_CONF_DIR}/nginx_listen.conf <<-EOF-LISTEN
		listen ${HTTP_LISTEN_PORT} ;
		listen ${HTTPS_LISTEN_PORT} ssl;
		set \$real_client_ip_if_set '';
		set \$http_listen_port '${HTTP_LISTEN_PORT}';
		set \$https_listen_port '${HTTPS_LISTEN_PORT}';
	EOF-LISTEN
fi

IFS=',' read -a LOCATIONS_ARRAY <<< "$LOCATIONS_CSV"
for i in "${!LOCATIONS_ARRAY[@]}"; do
    /enable_location.sh $((${i} + 1)) ${LOCATIONS_ARRAY[$i]}
done

if [ "${NAME_RESOLVER}" == "" ]; then
    if [ "${DNSMASK}" == "TRUE" ]; then
        dnsmasq
        export NAME_RESOLVER=127.0.0.1
    else
        export NAME_RESOLVER=$(grep 'nameserver' /etc/resolv.conf | head -n1 | cut -d' ' -f2)
    fi
fi

if [ "${HTTPS_REDIRECT}" == "TRUE" ]; then
    cat > ${NGIX_CONF_DIR}/ssl_redirect.conf <<-EOF-REDIRECT-TRUE
	if (\$ssl_protocol = "") {
	  rewrite ^ https://\$host\$https_port_string\$request_uri? permanent;
	}
	EOF-REDIRECT-TRUE
else
    touch ${NGIX_CONF_DIR}/ssl_redirect.conf 
fi

msg "Resolving proxied names using resolver:${NAME_RESOLVER}"
echo "resolver ${NAME_RESOLVER};">${NGIX_CONF_DIR}/resolver.conf

echo "HTTPS_LISTEN_PORT=${HTTPS_LISTEN_PORT}">/tmp/readyness.cfg

if [ -f ${UUID_FILE} ]; then
    export LOG_UUID=TRUE
fi
if [ "${CLIENT_MAX_BODY_SIZE}" != "" ]; then
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

case "${LOG_FORMAT_NAME}" in
    "json" | "text")
        msg "Logging set to ${LOG_FORMAT_NAME}"

        if [ "${NO_LOGGING_URL_PARAMS}" ]; then
            sed -i -e 's/\$request_uri/\$uri/g' ${NGIX_CONF_DIR}/logging.conf
        fi

        if [ "${NO_LOGGING_BODY}" == "TRUE" ]; then
            sed --in-place '/\$request_body/d' ${NGIX_CONF_DIR}/logging.conf
        fi

        if [ "${NO_LOGGING_RESPONSE}" == "TRUE" ]; then
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
        exit_error_msg "Invalid log format specified:${LOG_FORMAT_NAME}. Expecting json or text."
    ;;
esac

if [ "${ADD_NGINX_SERVER_CFG}" != "" ]; then
    msg "Adding extra config for server context."
    echo ${ADD_NGINX_SERVER_CFG}>${NGIX_CONF_DIR}/nginx_server_extras.conf
fi

if [ "${ADD_NGINX_HTTP_CFG}" != "" ]; then
    msg "Adding extra config for http context."
    echo ${ADD_NGINX_HTTP_CFG}>${NGIX_CONF_DIR}/nginx_http_extras.conf
fi

GEO_CFG="${NGIX_CONF_DIR}/nginx_geoip.conf"
if [ "${ALLOW_COUNTRY_CSV}" != "" ]; then
    msg "Enabling Country codes detection:${ALLOW_COUNTRY_CSV}..."
	cat > ${NGIX_CONF_DIR}/nginx_geoip_init.conf <<-EOF-GEO-INIT
	init_by_lua '
		country = require "country"
		country:init()
	';
	EOF-GEO-INIT
    echo "set_by_lua_file \$country_code /usr/local/openresty/nginx/lua/get_country.lua \"\$${REMOTE_IP_VAR}\";">>${GEO_CFG}

    # Set up base data as that from yum package...
    ln -s /usr/share/GeoIP/GeoIP.dat /usr/share/GeoIP/GeoLiteCountry.dat

    # Refresh in background...
    /refresh_GeoIP.sh &
else
    touch ${GEO_CFG}
    touch ${NGIX_CONF_DIR}/nginx_geoip_init.conf
fi

if [ "${STATSD_METRICS_ENABLED}" = "TRUE" ]; then
    msg "Setting up statsd configuration with server ${STATSD_SERVER}"
    echo "statsd_server ${STATSD_SERVER};" > ${NGIX_CONF_DIR}/nginx_statsd_server.conf
    echo "statsd_count \"waf.status.\$status\" 1;" > ${NGIX_CONF_DIR}/nginx_statsd_metrics.conf
fi


eval "${NGINX_BIN} -g \"daemon off;\""
