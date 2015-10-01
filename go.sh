#!/usr/bin/env bash

set -e

function download() {

    file_url=$1
    file_md5=$2
    download_path=$3

    file_path=${download_path}/$(basename ${file_url})
    error=0

    for i in {1..5}; do
        if [ ${i} -gt 1 ]; then
            echo "About to retry download for ${file_url}..."
            sleep 1
        fi
        wget -q -O ${file_path} ${file_url}
        md5=$(md5sum ${file_path} | cut -d' ' -f1)
        if [ "${md5}" == "${file_md5}" ] ; then
            echo "File downloaded & OK:${file_url}"
            error=0
            break
        else
            echo "Error: MD5 expecting '${file_md5}' but got '${md5}' for ${file_url}"
            error=1
        fi
    done
    return ${error}
}

# Resolve any variable names here:
PROXY_HOST=$(eval "echo $PROXY_SERVICE_HOST")
export PROXY_SERVICE_PORT=$(eval "echo $PROXY_SERVICE_PORT")
echo "Looking up $PROXY_HOST"
for i in 1..3 ; do

    set +e
    # DO name resolution of any hostnames

    # Cope with Skydns round-robin DNS errors...
    var=$(getent ahosts $PROXY_HOST)
    if [ $? -eq 0 ]; then
        export PROXY_SERVICE_HOST=$(echo $var | cut -d' ' -f1)
        NAME_RESOLVE=OK
    else
        NAME_RESOLVE=BAD
    fi
    set -e
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

if [ "${NAXSI_RULES_URL_CSV}" != "" ]; then
    if [ "${NAXSI_RULES_MD5_CSV}" == "" ]; then
        echo "Error, must specify NAXSI_RULES_MD5_CSV if NAXSI_RULES_URL_CSV is specified"
        exit 1
    fi
    IFS=',' read -a NAXSI_RULES_URL_ARRAY <<< "$NAXSI_RULES_URL_CSV"
    IFS=',' read -a NAXSI_RULES_MD5_ARRAY <<< "$NAXSI_RULES_MD5_CSV"
    if [ ${#NAXSI_RULES_URL_ARRAY[@]} -ne ${#NAXSI_RULES_MD5_ARRAY[@]} ]; then
        echo "Must specify the same number of items in \$NAXSI_RULES_URL_CSV and \$NAXSI_RULES_MD5_CSV"
        exit 1
    fi
    for i in "${!NAXSI_RULES_URL_ARRAY[@]}"; do
        download ${NAXSI_RULES_URL_ARRAY[$i]} ${NAXSI_RULES_MD5_ARRAY[$i]} /usr/local/openresty/naxsi
    done
fi
if [ "${NAXSI_USE_DEFAULT_RULES}" == "FALSE" ]; then
    echo "Deleting core rules..."
    rm -f /usr/local/openresty/naxsi/naxsi_core.rules
fi

eval "/usr/local/openresty/nginx/sbin/nginx -g \"daemon off;\""