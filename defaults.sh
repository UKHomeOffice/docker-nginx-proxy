#!/usr/bin/env bash
export NGIX_CONF_DIR=/usr/local/openresty/nginx/conf
export NGINX_BIN=/usr/local/openresty/nginx/sbin/nginx
export UUID_FILE=/tmp/uuid_on
export DEFAULT_ERROR_CODES="500 501 502 503 504"
export LOG_FORMAT_NAME=${LOG_FORMAT_NAME:-json}
export SERVER_CERT=${SERVER_CERT:-/etc/keys/crt}
export SERVER_KEY=${SERVER_KEY:-/etc/keys/key}
export SSL_CIPHERS=${SSL_CIPHERS:-'AES256+EECDH:AES256+EDH:!aNULL'}
export SSL_PROTOCOLS=${SSL_PROTOCOLS:-'TLSv1.2'}
export HTTP_LISTEN_PORT=${HTTP_LISTEN_PORT:-80}
export HTTPS_LISTEN_PORT=${HTTPS_LISTEN_PORT:-443}
export HTTPS_REDIRECT=${HTTPS_REDIRECT:-'TRUE'}
export NO_LOGGING_BODY=${NO_LOGGING_BODY:-'TRUE'}
export NO_LOGGING_RESPONSE=${NO_LOGGING_RESPONSE:-'TRUE'}

export HTTPS_REDIRECT_PORT_STRING=":${HTTPS_REDIRECT_PORT}"
if [ "${HTTPS_REDIRECT_PORT_STRING}" == ":" ]; then
    export HTTPS_REDIRECT_PORT_STRING=""
fi

function download() {

    file_url=$1
    if [ $# -eq 3 ]; then
      file_md5=$2
      download_path=$3
    else
      download_path=$2
    fi

    file_path=${download_path}/$(basename ${file_url})
    error=0

    for i in {1..5}; do
        if [ ${i} -gt 1 ]; then
            msg "About to retry download for ${file_url}..."
            sleep 1
        fi
        if curl --max-time 30 --fail -s -o ${file_path} ${file_url} ; then
            error=0
        fi
        if [ -n ${file_md5} ]; then
            md5=$(md5sum ${file_path} | cut -d' ' -f1)

            if [ "${md5}" == "${file_md5}" ] ; then
                error=0
            else
                msg "Error: MD5 expecting '${file_md5}' but got '${md5}' for ${file_url}"
                error=1
            fi
        fi
        if [ ${error} -eq 0 ]; then
            msg "File downloaded & OK:${file_url}"
            break
        fi
    done
    return ${error}
}

function get_id_var() {
    LOCATION_ID=$1
    VAR_NAME=$2
    NEW_VAR_NAME="${VAR_NAME}_${LOCATION_ID}"
    if [ "${!NEW_VAR_NAME}" == "" ]; then
        NEW_VAR_NAME=${VAR_NAME}
    fi
    echo ${!NEW_VAR_NAME}
}

function msg() {
    if [ "${LOCATION}" != "" ]; then
        LOC_TXT=${LOCATION_ID}:${LOCATION}:
    fi
    echo "SETUP:${LOC_TXT}$1"
}

function exit_error_msg() {
    echo "ERROR:$1"
    exit 1
}
