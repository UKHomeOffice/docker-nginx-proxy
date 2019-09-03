#!/usr/bin/env bash

set -e

function wait_until_cmd() {
    cmd="$@"
    max_retries=5
    wait_time=${WAIT_TIME:-1}
    retries=0
    while true ; do
        if ! bash -c "${cmd}" &> /dev/null ; then
            retries=$((retries + 1))
            echo "Testing for readyness..."
            if [ ${retries} -eq ${max_retries} ]; then
                return 1
            else
                echo "Retrying, $retries out of $max_retries..."
                sleep ${wait_time}
            fi
        else

            return 0
        fi
    done
    echo
    return 1
}

function run_test() {
    if [ "${2}" == "POLL" ]; then
        wait_until_cmd "${1}"
    else
        ${1}
    fi
}

wait_until_cmd "ls /tmp/readyness.cfg"
source /tmp/readyness.cfg
# Test for port ready...
run_test "wget -O /dev/null --no-check-certificate https://localhost:${HTTPS_LISTEN_PORT}/ping" $1
