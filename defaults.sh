#!/usr/bin/env bash
export NGIX_CONF_DIR=/usr/local/openresty/nginx/conf
export UUID_FILE=/tmp/uuid_on
export DEFAULT_ERROR_CODES="500 501 502 503 504"
export HTTPS_PORT_STRING=":${HTTPS_PORT}"

if [ "${HTTPS_PORT_STRING}" == ":" ]; then
    export HTTPS_PORT_STRING=""
fi

function download() {

    file_url=$1
    file_md5=$2
    download_path=$3

    file_path=${download_path}/$(basename ${file_url})
    error=0

    for i in {1..5}; do
        if [ ${i} -gt 1 ]; then
            msg "About to retry download for ${file_url}..."
            sleep 1
        fi
        wget -q -O ${file_path} ${file_url}
        md5=$(md5sum ${file_path} | cut -d' ' -f1)
        if [ "${md5}" == "${file_md5}" ] ; then
            msg "File downloaded & OK:${file_url}"
            error=0
            break
        else
            msg "Error: MD5 expecting '${file_md5}' but got '${md5}' for ${file_url}"
            error=1
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