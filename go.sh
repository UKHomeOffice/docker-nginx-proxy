#!/usr/bin/env bash

# Resolve any variable names here:
PROXY_HOST=$(eval "echo $PROXY_SERVICE_HOST")
export PROXY_SERVICE_PORT=$(eval "echo $PROXY_SERVICE_PORT")
echo "Looking up $PROXY_HOST:$PROXY_PORT"
for i in 1..3 ; do
    # DO name resolution of any hostnames

    # Cope with Skydns round-robin DNS errors...
    # DIG +short not working and getent hanging so using nslookup!!!???
    var=$(nslookup $PROXY_HOST)
    if [ $? -eq 0 ]; then
        export PROXY_SERVICE_HOST=$(echo $var | cut -d' ' -f 10)
    else
        echo "One failed lookup..."
    fi
done

echo "Using: $PROXY_SERVICE_HOST:"

eval "/usr/local/openresty/nginx/sbin/nginx -g \"daemon off;\""