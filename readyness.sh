#!/usr/bin/env bash

set -e

source /helper.sh

function run_test() {
    if [ "${2}" == "POLL" ]; then
        wait_until_cmd "${1}"
    else
        ${1}
    fi
}

source /tmp/readyness.cfg
# Test for port ready...
run_test "wget -O /dev/null --no-check-certificate https://localhost:${HTTPS_LISTEN_PORT}/ping" $1
