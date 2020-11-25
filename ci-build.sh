#!/usr/bin/env bash

set -e

TAG=ngx
: "${BUILD_NUMBER:=${DRONE_BUILD_NUMBER}}"
PORT=$((${BUILD_NUMBER} + 1025))
: "${BUILD_NUMBER:=local}"
START_INSTANCE="docker run "
: ${DOCKER_HOST_NAME:=172.17.0.1}
MOCKSERVER="mockserver-${BUILD_NUMBER}"
SLOWMOCKSERVER="slowmockserver-${BUILD_NUMBER}"
MOCKSERVER_PORT=9000
SLOWMOCKSERVER_PORT=9001
WORKDIR="${PWD}"

function tear_down_container() {
    container=$1
    if docker ps -a | grep "${container}" &>/dev/null ; then
        if docker ps | grep "${container}" &>/dev/null ; then
            docker kill "${container}" &>/dev/null || true
        fi
        docker rm "${container}" &>/dev/null || true
    fi
}

function clean_up() {
    rm -f /tmp/file.txt
    tear_down_container "${MOCKSERVER}"
    tear_down_container "${SLOWMOCKSERVER}"
    tear_down_container "${TAG}-${BUILD_NUMBER}"
}

function start_test() {
    INSTANCE="${TAG}-${BUILD_NUMBER}"
    tear_down_container "${INSTANCE}"
    HTTPS_LISTEN_PORT=${HTTPS_LISTEN_PORT:-10443}
    echo ""
    echo ""
    echo "_____________"
    echo "STARTING TEST:$1"
    echo "============="
    shift
    echo "Running:$@ --name ${INSTANCE} -p ${PORT}:${HTTPS_LISTEN_PORT} ${TAG}"
    bash -c "$@ --name ${INSTANCE} -d -p ${PORT}:${HTTPS_LISTEN_PORT} ${TAG}"
    docker run --rm --link ${INSTANCE}:${INSTANCE} martin/wait
}

clean_up

STD_CMD="${START_INSTANCE}"

echo "========"
echo "BUILD..."
echo "========"
echo "travis_fold:start:BUILD"
docker build -t ${TAG} .
echo "travis_fold:end:BUILD"

echo "Running mocking-server..."
docker build -t mockserver:latest ${WORKDIR} -f docker-config/Dockerfile.mockserver
${STD_CMD} -d \
           --log-driver json-file \
           --name="${MOCKSERVER}" mockserver:latest \
           -config=/test-servers.yaml \
           -debug \
           -port=${MOCKSERVER_PORT}
docker run --rm --link "${MOCKSERVER}:${MOCKSERVER}" martin/wait -c "${MOCKSERVER}:${MOCKSERVER_PORT}"

echo "Running slow-mocking-server..."
docker build -t slowmockserver:latest ${WORKDIR} -f docker-config/Dockerfile.slowmockserver
${STD_CMD} -d \
           --log-driver json-file \
           --name="${SLOWMOCKSERVER}" slowmockserver:latest \
           -config=/test-servers.yaml \
           -monkeyConfig=/monkey-business.yaml \
           -debug \
           -port=${SLOWMOCKSERVER_PORT}
docker run --rm --link "${SLOWMOCKSERVER}:${SLOWMOCKSERVER}" martin/wait -c "${SLOWMOCKSERVER}:${SLOWMOCKSERVER_PORT}"

echo "=========="
echo "TESTING..."
echo "=========="

start_test "Start with minimal settings" "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\""

echo "Test it's up and working..."
curl --fail -sk -o /dev/null https://${DOCKER_HOST_NAME}:${PORT}/
echo "Check the log output"
# Should look something like: {localhost:10443 0cedbe2eae0760fd180a4347975376d3 - 172.17.0.1 - [11/Sep/2019:14:00:53 +0000] "GET / HTTP/1.1" 200 32424 0.294 - "-" "curl/7.54.0"}
docker logs "$INSTANCE" | grep -E '\{[^:]+:'${HTTPS_LISTEN_PORT:-10443}' [0-9a-f]+ - [0-9.]+ - \[[0-9]+/[A-Z][a-z][a-z]/[0-9:]{13} \+[0-9]{4}\] "GET / HTTP/1\.1" [0-9]{3} [0-9]+ [0-9]+\.[0-9]{3} - "-" "[^"]+"\}'
echo "Test limited protcol and SSL cipher... "
docker run --link ${INSTANCE}:${INSTANCE}--rm --entrypoint bash ngx -c "echo GET / | /usr/bin/openssl s_client -cipher 'AES256+EECDH' -tls1_2 -connect ${INSTANCE}:10443" &> /dev/null;
echo "Test sslv2 not accepted...."
if docker run --link ${INSTANCE}:${INSTANCE}--rm --entrypoint bash ngx -c "echo GET / | /usr/bin/openssl s_client -ssl2 -connect ${INSTANCE}:10443" &> /dev/null; then
  echo "FAIL SSL defaults settings allow ssl2 ......"
  exit 2
fi

start_test "Test response has gzip" "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test gzip ok..."
curl -s -I -X GET -k --compressed https://${DOCKER_HOST_NAME}:${PORT}/gzip | grep -q 'Content-Encoding: gzip'

start_test "Start with multi locations settings" "${STD_CMD} \
           --log-driver json-file \
           -e \"LOCATIONS_CSV=/,/news\" \
           -e \"PROXY_SERVICE_HOST_1=http://www.w3.org\" \
           -e \"PROXY_SERVICE_PORT_1=80\" \
           -e \"PROXY_SERVICE_HOST_2=http://www.bbc.co.uk\" \
           -e \"PROXY_SERVICE_PORT_2=80\""


echo "Test for location 1 @ /..."
curl --fail -sk -o /dev/null https://${DOCKER_HOST_NAME}:${PORT}/
echo "Test for news..."
curl --fail -sk -o /dev/null -H "Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/news

start_test "Start with Multiple locations, single proxy and NAXSI download." "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://www.bbc.co.uk\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"LOCATIONS_CSV=/,/news\" \
           -e \"NAXSI_RULES_URL_CSV_1=https://raw.githubusercontent.com/nbs-system/naxsi-rules/master/drupal.rules\" \
           -e \"NAXSI_RULES_MD5_CSV_1=3b3c24ed61683ab33d8441857c315432\""

echo "Test for all OK..."
curl --fail -sk -o /dev/null -H "Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/

start_test "Start with Custom upload size" "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"CLIENT_MAX_BODY_SIZE=15\" \
           -e \"NAXSI_USE_DEFAULT_RULES=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
dd if=/dev/urandom of=/tmp/file.txt bs=1048576 count=10

echo "Upload a large file"
curl -k -F "file=@/tmp/file.txt;filename=nameinpost" \
     https://${DOCKER_HOST_NAME}:${PORT}/uploads/doc &> /tmp/upload_test.txt
grep "Thanks for the big doc" /tmp/upload_test.txt &> /dev/null

start_test "Start with single location, PROXY_STATIC_CACHE works." "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"PROXY_STATIC_CACHING=true\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "

echo "Test for all OK..."
curl -s -I -X GET -k --compressed https://${DOCKER_HOST_NAME}:${PORT}/gzip | grep -q 'Content-Encoding: gzip'

echo "_________________________________"
echo "We got here, ALL tests successful"
clean_up
