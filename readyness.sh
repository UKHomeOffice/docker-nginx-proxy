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

# Test for port ready...
run_test "wget -O /dev/null --no-check-certificate https://localhost:443/ping" $1
