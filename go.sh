#!/usr/bin/env bash

set -e

export LOG_UUID=FALSE

. /defaults.sh

if [ "${LOCATIONS_CSV}" == "" ]; then
    LOCATIONS_CSV=/
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

msg "Resolving proxied names using resolver:${NAME_RESOLVER}"
echo "resolver ${NAME_RESOLVER};">${NGIX_CONF_DIR}/resolver.conf

if [ "${LOAD_BALANCER_CIDR}" != "" ]; then
    msg "Using proxy_protocol from '$LOAD_BALANCER_CIDR' (real client ip is forwarded correctly by loadbalancer)..."
    cp ${NGIX_CONF_DIR}/nginx_listen_proxy_protocol.conf ${NGIX_CONF_DIR}/nginx_listen.conf
    echo -e "\nset_real_ip_from ${LOAD_BALANCER_CIDR};" >> ${NGIX_CONF_DIR}/nginx_listen.conf
else
    msg "No \$LOAD_BALANCER_CIDR set, using straight SSL (client ip will be from loadbalancer if used)..."
    cp ${NGIX_CONF_DIR}/nginx_listen_plain.conf ${NGIX_CONF_DIR}/nginx_listen.conf
fi

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
    "extended_json" | "extended_text")
        msg "Logging set to ${LOG_FORMAT_NAME}"
        echo "access_log /dev/stdout ${LOG_FORMAT_NAME};">${NGIX_CONF_DIR}/logging.conf
        ;;
    *)
        exit_error_msg "Invalid log format specified:${LOG_FORMAT_NAME}. Expenting extended_json or extended_text."
    ;;
esac

eval "/usr/local/openresty/nginx/sbin/nginx -g \"daemon off;\""