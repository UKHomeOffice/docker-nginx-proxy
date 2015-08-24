#!/usr/bin/env bash

# Resolve any variable names here:
PROXY_HOST=$(eval "echo $PROXY_SERVICE_HOST")
export PROXY_SERVICE_PORT=$(eval "echo $PROXY_SERVICE_PORT")
echo "Looking up $PROXY_HOST"
for i in 1..3 ; do
    # DO name resolution of any hostnames

    # Cope with Skydns round-robin DNS errors...
    var=$(getent ahosts $PROXY_HOST)
    if [ $? -eq 0 ]; then
        export PROXY_SERVICE_HOST=$(echo $var | cut -d' ' -f1)
        NAME_RESOLVE=OK
    else
        NAME_RESOLVE=BAD
    fi
done

# Detect default configuration...
md5sum /usr/local/openresty/nginx/conf/nginx.conf | cut -d' ' -f 1 >/tmp/nginx_new
if diff /container_default_ngx /tmp/nginx_new ; then
    if [ "$PROXY_SERVICE_HOST" == "" ] || [ "$PROXY_SERVICE_PORT" == "" ] || [ "$PROXY_HOST" == "" ]; then
        echo "Default config requires PROXY_SERVICE_HOST and PROXY_SERVICE_HOST to be set."
        echo "PROXY_SERVICE_HOST=$PROXY_HOST"
        echo "PROXY_SERVICE_PORT=$PROXY_SERVICE_PORT"
        exit 1
    fi
    if [ "$NAME_RESOLVE" == "BAD" ] ; then
        echo "Name specified for default config can't be resolved:$PROXY_SERVICE_HOST"
        exit 1
    fi
    echo "Proxying to : http://$PROXY_SERVICE_HOST:$PROXY_SERVICE_PORT"
fi

eval "/usr/local/openresty/nginx/sbin/nginx -g \"daemon off;\""