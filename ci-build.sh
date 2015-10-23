#!/usr/bin/env bash

set -e

TAG=ngx
COUNT=0
PORT=8443
START_INSTANCE="docker run --privileged=true "

source ./helper.sh

function tear_down() {
    if [ "${TEAR_DOWN}" == "true" ]; then
        if docker ps -a | grep ${INSTANCE} &>/dev/null ; then
            if docker ps | grep ${INSTANCE} &>/dev/null ; then
                ${SUDO_CMD} docker stop ${INSTANCE}
            fi
            ${SUDO_CMD} docker rm ${INSTANCE}
        fi
    fi
}

function wait_until_started() {
    sleep 1
    ${SUDO_CMD} docker exec -it ${INSTANCE} /readyness.sh POLL
}

function start_test() {
    tear_down
    COUNT=$((COUNT + 1))
    PORT=$((PORT + 1))
    INSTANCE=${TAG}_$COUNT
    echo "STARTING TEST:$1"
    shift
    echo "Running:$@ --name ${INSTANCE} -p ${PORT}:443 ${TAG}"
    bash -c "$@ --name ${INSTANCE} -d -p ${PORT}:443 ${TAG}"
    if ! wait_until_started ; then
        echo "Error, not started in time..."
        ${SUDO_CMD} docker logs ${INSTANCE}
        exit 1
    fi
}

# Cope with local builds with docker machine...
if [ "${DOCKER_MACHINE_NAME}" == "" ]; then
    DOCKER_HOST_NAME=localhost
    SUDO_CMD=sudo
    # On travis... need to do this for it to work!
    ${SUDO_CMD} service docker restart ; sleep 10
else
    DOCKER_HOST_NAME=$(docker-machine ip ${DOCKER_MACHINE_NAME})
    TEAR_DOWN=true
    SUDO_CMD=""
fi
STD_CMD="${SUDO_CMD} ${START_INSTANCE}"

echo "========"
echo "BUILD..."
echo "========"
${SUDO_CMD} docker build -t ${TAG} .

echo "=========="
echo "TESTING..."
echo "=========="
start_test "Start with minimal settings" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\""

echo "Test it's up and working..."
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/

start_test "Start with multi locations settings" "${STD_CMD} \
           -e \"LOCATIONS_CSV=/,/news\" \
           -e \"PROXY_SERVICE_HOST_1=www.w3.org\" \
           -e \"PROXY_SERVICE_PORT_1=80\" \
           -e \"PROXY_SERVICE_HOST_2=www.bbc.co.uk\" \
           -e \"PROXY_SERVICE_PORT_2=80\""

echo "Test for location 1 @ /..."
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Test for news..."
wget -O /dev/null --no-check-certificate --header="Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/news

start_test "Start with Multiple locations, single proxy and NAXSI download." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.bbc.co.uk\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"LOCATIONS_CSV=/,/news\" \
           -e \"NAXSI_RULES_URL_CSV_1=https://raw.githubusercontent.com/nbs-system/naxsi-rules/master/drupal.rules\" \
           -e \"NAXSI_RULES_MD5_CSV_1=3b3c24ed61683ab33d8441857c315432\""

echo "Test for all OK..."
wget -O /dev/null --no-check-certificate --header="Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/

echo "Test client certs..."
cd ./client_certs/
./create_ca.sh
./create_client_csr_and_key.sh
./sign_client_key_with_ca.sh
cd ..
start_test "Start with Client CA, and single proxy. Block unauth for /news" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.bbc.co.uk\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"LOCATIONS_CSV=/,/news\" \
           -e \"CLIENT_CERT_REQUIRED_2=TRUE\" \
           -v ${PWD}/client_certs/ca.crt:/etc/keys/client_ca "

echo "Test access OK for basic area..."
wget -O /dev/null --no-check-certificate --header="Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/

echo "Test access denied for /news..."
if wget -O /dev/null --no-check-certificate --header="Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/news ; then
    echo "Error - expecting auth fail!"
    exit 1
else
    echo "Passed auth fail"
fi
echo "Test access OK for /news... with client cert..."
wget -O /dev/null --no-check-certificate \
   --certificate=./client_certs/client.crt \
   --private-key=./client_certs/client.key \
   --header="Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/news
