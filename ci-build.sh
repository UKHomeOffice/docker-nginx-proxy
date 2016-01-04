#!/usr/bin/env bash

set -e

TAG=ngx
COUNT=0
PORT=8443
START_INSTANCE="docker run --privileged=true "

source ./helper.sh

function tear_down_container() {
    container=$1
    if [ "${TEAR_DOWN}" == "true" ]; then
        if docker ps -a | grep "${container}" &>/dev/null ; then
            if docker ps | grep "${container}" &>/dev/null ; then
                ${SUDO_CMD} docker stop "${container}"
            fi
            ${SUDO_CMD} docker rm "${container}"
        fi
    fi
}

function tear_down() {
    tear_down_container ${INSTANCE}
}

function clean_up() {
    rm -f /tmp/file.txt
    tear_down_container mockserver
}

function wait_until_started() {
    sleep 1
    ${SUDO_CMD} docker exec -it ${INSTANCE} /readyness.sh POLL
}

function start_test() {
    COUNT=$((COUNT + 1))
    PORT=$((PORT + 1))
    INSTANCE=${TAG}_$COUNT
    tear_down
    echo ""
    echo ""
    echo "_____________"
    echo "STARTING TEST:$1"
    echo "============="
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
    clean_up
fi
STD_CMD="${SUDO_CMD} ${START_INSTANCE}"

echo "========"
echo "BUILD..."
echo "========"
${SUDO_CMD} docker build -t ${TAG} .

echo "Running mocking-server..."
${STD_CMD} -d -p 8080:8080 \
           -v ${PWD}/test-servers.yaml:/test-servers.yaml \
           --name=mockserver quay.io/ukhomeofficedigital/mockingj-server:v0.1.0 \
           -config=/test-servers.yaml \
           -port=8080
echo "sleep 5..."
sleep 5
${SUDO_CMD} docker ps

echo "=========="
echo "TESTING..."
echo "=========="

start_test "Start with minimal settings" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\""

echo "Test it's up and working..."
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Test limited protcol and SSL cipher... "
echo "GET /" | openssl s_client -cipher 'AES256+EECDH' -tls1_2 -connect ${DOCKER_HOST_NAME}:${PORT}
echo "Test sslv2 not excepted...."
set +e
echo "GET /" | openssl s_client -ssl2 -connect ${DOCKER_HOST_NAME}:${PORT}
if [ $? -ne 1 ]; then 
  echo "FAIL SSL defaults settings allow ssl2 ......" 
  exit 2 
fi
set -e

start_test "Start with SSL CIPHER set and PROTOCOL" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"SSL_CIPHER=RC4-MD5\" \
           -e \"SSL_PROTOCOL=TLSv1.1\""
echo "Test excepts defined protocol and cipher....."
echo "GET /" | openssl s_client -cipher 'RC4-MD5' -tls1_1 -connect ${DOCKER_HOST_NAME}:${PORT}

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
start_test "Start with Client CA, and single proxy. Block unauth for /standards" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"LOCATIONS_CSV=/,/standards/\" \
           -e \"CLIENT_CERT_REQUIRED_2=TRUE\" \
           -v ${PWD}/client_certs/ca.crt:/etc/keys/client-ca "

echo "Test access OK for basic area..."
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/

echo "Test access denied for /standards/..."
if wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/standards/ ; then
    echo "Error - expecting auth fail!"
    exit 1
else
    echo "Passed auth fail"
fi
echo "Test access OK for /standards/... with client cert..."
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/standards/ \
     --certificate=./client_certs/client.crt \
     --private-key=./client_certs/client.key



start_test "Start with Custom error pages redirect off" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=mockserver\" \
           -e \"PROXY_SERVICE_PORT=8080\" \
           -e \"LOCATIONS_CSV=/,/api/\" \
           -e \"ERROR_REDIRECT_CODES_2=502\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
echo "Test All ok..."
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/api/
if curl -v -k https://${DOCKER_HOST_NAME}:${PORT}/api/dead | grep "Oh dear" ; then
    echo "Passed return text on error with ERROR_REDIRECT_CODES"
else
    echo "Failed return text on error with ERROR_REDIRECT_CODES"
    exit 1
fi

start_test "Start with Custom upload size" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=mockserver\" \
           -e \"PROXY_SERVICE_PORT=8080\" \
           -e \"CLIENT_MAX_BODY_SIZE=15\" \
           -e \"NAXSI_USE_DEFAULT_RULES=FALSE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"DNSMASK=TRUE\" \
           --link mockserver:mockserver "
dd if=/dev/urandom of=/tmp/file.txt bs=1048576 count=10

echo "Upload a large file"
curl -k -F "file=@/tmp/file.txt;filename=nameinpost" \
     https://${DOCKER_HOST_NAME}:${PORT}/uploads/doc &> /tmp/upload_test.txt
grep "Thanks for the big doc" /tmp/upload_test.txt &> /dev/null

start_test "Start with listen for port 80" "${STD_CMD} \
           -p 8888:80 \
           -e \"PROXY_SERVICE_HOST=mockserver\" \
           -e \"PROXY_SERVICE_PORT=8080\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"HTTPS_PORT=$((PORT + 1))\" \
           --link mockserver:mockserver "
echo "Test Redirect ok..."
wget -O /dev/null --no-check-certificate http://${DOCKER_HOST_NAME}:8888/

start_test "Test text logging format..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=mockserver\" \
           -e \"PROXY_SERVICE_PORT=8080\" \
           -e \"DNSMASK=TRUE\" \
           -e \"LOG_FORMAT_NAME=text\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
echo "Test request (with logging as text)..."
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Testing text logs format..."
${SUDO_CMD} docker logs ${INSTANCE} | grep '127.0.0.1 - -'

start_test "Test json logging format..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=mockserver\" \
           -e \"PROXY_SERVICE_PORT=8080\" \
           -e \"DNSMASK=TRUE\" \
           -e \"LOG_FORMAT_NAME=json\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Testing json logs format..."
${SUDO_CMD} docker logs ${INSTANCE}  | grep '{"proxy_proto_address":'

start_test "Test ENABLE_WEB_SOCKETS..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=mockserver\" \
           -e \"PROXY_SERVICE_PORT=8080\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_WEB_SOCKETS=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/

start_test "Test ADD_NGINX_LOCATION_CFG param..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=mockserver\" \
           -e \"PROXY_SERVICE_PORT=8080\" \
           -e \"LOCATIONS_CSV=/,/api/\" \
           -e \"ADD_NGINX_LOCATION_CFG=return 200 NICE;\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
echo "Test extra param works"
wget -O- --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/wow | grep "NICE"

echo "__________________________________"
echo "We got here, ALL tests successfull"
