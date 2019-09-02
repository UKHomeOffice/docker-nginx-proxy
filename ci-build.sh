#!/usr/bin/env bash

set -e

TAG=ngx
BUILD_NUMBER="${BUILD_NUMBER:-${DRONE_BUILD_NUMBER}}"
PORT=$((${BUILD_NUMBER} + 1025))
BUILD_NUMBER="${BUILD_NUMBER:-local}"
START_INSTANCE="docker run "
DOCKER_HOST_NAME=172.17.0.1
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

function tear_down() {
    tear_down_container "${INSTANCE}"
}

function clean_up() {
    rm -f /tmp/file.txt
    tear_down_container "${MOCKSERVER}"
    tear_down_container "${SLOWMOCKSERVER}"
    tear_down_container "${TAG}-${BUILD_NUMBER}"
}

function add_files_to_container() {
  local CONTAINER=$1
  shift
  while [[ -n $@ ]]; do
    local file=$1
    shift
    local dest=$1
    docker cp ${file} ${CONTAINER}:${dest}
    shift
  done
}

function start_test() {
    INSTANCE="${TAG}-${BUILD_NUMBER}"
    tear_down
    HTTPS_LISTEN_PORT=${HTTPS_LISTEN_PORT:-10443}
    echo ""
    echo ""
    echo "_____________"
    echo "STARTING TEST:$1"
    echo "============="
    shift
    # handle files that need to be mounted in
    local files=""
    while [[ $@ != docker* ]]; do
      # should be in format - file destination file destination etc.
      files="${files} $1"
      shift
    done
    echo "Running:$@ --name ${INSTANCE} -p ${PORT}:${HTTPS_LISTEN_PORT} ${TAG}"
    bash -c "$@ --name ${INSTANCE} -d -p ${PORT}:${HTTPS_LISTEN_PORT} ${TAG}"
    # if files needed to be mounted in, the container stops immediately so start it again
    if [[ ${files} != "" ]]; then
      echo "${files}"
      add_files_to_container ${INSTANCE} ${files}
      docker start ${INSTANCE}
    fi
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
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
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
           -e \"ENABLE_UUID_PARAM=FALSE\" \
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
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Test for news..."
wget -O /dev/null --quiet --no-check-certificate --header="Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/news

start_test "Start with Multiple locations, single proxy and NAXSI download." "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://www.bbc.co.uk\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"LOCATIONS_CSV=/,/news\" \
           -e \"NAXSI_RULES_URL_CSV_1=https://raw.githubusercontent.com/nbs-system/naxsi-rules/master/drupal.rules\" \
           -e \"NAXSI_RULES_MD5_CSV_1=3b3c24ed61683ab33d8441857c315432\""

echo "Test for all OK..."
wget -O /dev/null --quiet --no-check-certificate --header="Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/

start_test "Start with Custom upload size" "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"CLIENT_MAX_BODY_SIZE=15\" \
           -e \"NAXSI_USE_DEFAULT_RULES=FALSE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
dd if=/dev/urandom of=/tmp/file.txt bs=1048576 count=10

echo "Upload a large file"
curl -k -F "file=@/tmp/file.txt;filename=nameinpost" \
     https://${DOCKER_HOST_NAME}:${PORT}/uploads/doc &> /tmp/upload_test.txt
grep "Thanks for the big doc" /tmp/upload_test.txt &> /dev/null

start_test "Test text logging format..." "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"LOG_FORMAT_NAME=text\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test request (with logging as text)..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Testing text logs format..."
docker logs ${INSTANCE} | grep "\"GET / HTTP/1.1\" 200"

start_test "Test json logging format..." "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"LOG_FORMAT_NAME=json\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}?animal=cow
echo "Testing json logs format..."
docker logs ${INSTANCE}  | grep '{"proxy_proto_address":'
docker logs ${INSTANCE}  | grep 'animal=cow'

start_test "Test custom logging format..." "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"LOG_FORMAT_NAME=custom\" \
           -e \"CUSTOM_LOG_FORMAT=' \\\$host:\\\$server_port \\\$uuid \\\$http_x_forwarded_for \\\$remote_addr \\\$remote_user [\\\$time_local] \\\$request \\\$status \\\$body_bytes_sent \\\$request_time \\\$http_x_forwarded_proto \\\$http_referer \\\$http_user_agent '\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
wget -O /dev/null --quiet --no-check-certificate --header="Host: example.com" https://${DOCKER_HOST_NAME}:${PORT}?animal=cow
echo "Testing custom logs format..."
docker logs ${INSTANCE} | egrep '^\{\sexample\.com:10443.*\[.*\]\sGET\s\/\?animal\=cow\sHTTP/[0-9]\.[0-9]\s200.*\s\}$'

start_test "Test ADD_NGINX_LOCATION_CFG param..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"LOCATIONS_CSV=/,/api/\" \
           -e \"ADD_NGINX_LOCATION_CFG=return 200 NICE;\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test extra param works"
wget  -O - -o /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/wow | grep "NICE"


start_test "Test UUID header logging option works..." "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"ENABLE_UUID_PARAM=HEADER\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}
echo "Testing no logging of url params option works..."
docker logs "${MOCKSERVER}" | grep 'Nginxid:'
docker logs ${INSTANCE} | grep '"nginx_uuid": "'

start_test "Test setting UUID name works..." "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"ENABLE_UUID_PARAM=HEADER\" \
           -e \"UUID_VAR_NAME=custom_uuid_name\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}
docker logs "${MOCKSERVER}" 2>/dev/null | grep "custom_uuid_name"
echo "Testing setting UUID_VAR_NAME works"

start_test "Test setting empty UUID name defaults correctly..." "${STD_CMD} \
           --log-driver json-file \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"ENABLE_UUID_PARAM=HEADER\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}
docker logs "${MOCKSERVER}" 2>/dev/null | grep -i "nginxId"
echo "Testing UUID_VAR_NAME default if empty works"

echo "_________________________________"
echo "We got here, ALL tests successful"
clean_up
