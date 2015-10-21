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
    export NAME_RESOLVER=$(grep 'nameserver' /etc/resolv.conf | head -n1 | cut -d' ' -f2)
fi
echo "Resolving proxied names using resolver:${NAME_RESOLVER}"
echo "resolver ${NAME_RESOLVER};">${NGIX_CONF_DIR}/resolver.conf

if [ "${LOAD_BALANCER_CIDR}" != "" ]; then
    echo "Using proxy_protocol from '$LOAD_BALANCER_CIDR' (real client ip is forwarded correctly by loadbalancer)..."
    cp ${NGIX_CONF_DIR}/nginx_listen_proxy_protocol.conf ${NGIX_CONF_DIR}/nginx_listen.conf
    echo -e "\nset_real_ip_from ${LOAD_BALANCER_CIDR};" >> ${NGIX_CONF_DIR}/nginx_listen.conf
else
    echo "No \$LOAD_BALANCER_CIDR set, using straight SSL (client ip will be from loadbalancer if used)..."
    cp ${NGIX_CONF_DIR}/nginx_listen_plain.conf ${NGIX_CONF_DIR}/nginx_listen.conf
fi

eval "/usr/local/openresty/nginx/sbin/nginx -g \"daemon off;\""