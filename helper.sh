#!/usr/bin/env bash

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

