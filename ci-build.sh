#!/usr/bin/env bash

set -e

TAG=ngx
BUILD_NUMBER="${BUILD_NUMBER:-${DRONE_BUILD_NUMBER}}"
PORT="${HTTPS_LISTEN_PORT:-10443}"
BUILD_NUMBER="${BUILD_NUMBER:-local}"
START_INSTANCE="docker run "
DOCKER_HOST_NAME="localhost"
MOCKSERVER="mockserver-${BUILD_NUMBER}"
SLOWMOCKSERVER="slowmockserver-${BUILD_NUMBER}"
MUTUAL_TLS="mutual-tls-${BUILD_NUMBER}"
STANDARD_TLS="standard-tls-${BUILD_NUMBER}"
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
    tear_down_container "${MUTUAL_TLS}"
    tear_down_container "${STANDARD_TLS}"
    tear_down_container "${TAG}-${BUILD_NUMBER}"
}

function add_files_to_container() {
  echo "Copying files to container: $1"
  local CONTAINER=$1
  shift
  while [[ -n $@ ]]; do
    local file=$1
    shift
    local rename=$1
    shift
    local destdir=$1
    cp ${file} ${rename}
    tar -cf - ${rename} --mode u=+rw,g=+r,o=+r --owner root --group root | docker cp - ${CONTAINER}:${destdir}
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
    echo "Running: $@ --name ${INSTANCE} -p ${PORT}:${HTTPS_LISTEN_PORT} ${TAG}"
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
docker build --build-arg GEOIP_ACCOUNT_ID=${GEOIP_ACCOUNT_ID} --build-arg GEOIP_LICENSE_KEY=${GEOIP_LICENSE_KEY} -t ${TAG} .
echo "travis_fold:end:BUILD"

echo "Running mocking-server..."
docker build -t mockserver:latest ${WORKDIR} -f docker-config/Dockerfile.mockserver
${STD_CMD} -d \
           --name="${MOCKSERVER}" mockserver:latest \
           -config=/test-servers.yaml \
           -debug \
           -port=${MOCKSERVER_PORT}
docker run --rm --link "${MOCKSERVER}:${MOCKSERVER}" martin/wait -c "${MOCKSERVER}:${MOCKSERVER_PORT}"

echo "Running slow-mocking-server..."
docker build -t slowmockserver:latest ${WORKDIR} -f docker-config/Dockerfile.slowmockserver
${STD_CMD} -d \
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
           -e \"PROXY_SERVICE_HOST=https://www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=443\""

echo "Test it's up and working..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Test limited protcol and SSL cipher... "
docker run --link ${INSTANCE}:${INSTANCE}--rm --entrypoint bash ngx -c "echo GET / | /usr/bin/openssl s_client -cipher 'AES256+EECDH' -tls1_2 -connect ${INSTANCE}:10443" &> /dev/null;
echo "Test sslv2 not accepted...."
if docker run --link ${INSTANCE}:${INSTANCE}--rm --entrypoint bash ngx -c "echo GET / | /usr/bin/openssl s_client -ssl2 -connect ${INSTANCE}:10443" &> /dev/null; then
  echo "FAIL SSL defaults settings allow ssl2 ......"
  exit 2
fi

start_test "Test enabling GEODB settings" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"ALLOW_COUNTRY_CSV=GB,FR,O1\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test GeoIP config isn't rejected..."
curl --fail -s -v -k https://${DOCKER_HOST_NAME}:${PORT}/

start_test "Test GEODB settings can reject..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"ALLOW_COUNTRY_CSV=CG\" \
           -e \"DENY_COUNTRY_ON=TRUE\" \
           -e \"ADD_NGINX_LOCATION_CFG=error_page 403 /nginx-proxy/50x.shtml;\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test GeoIP config IS rejected..."
if ! curl -v -k -H "X-Forwarded-For: 1.1.1.1" https://${DOCKER_HOST_NAME}:${PORT}/ 2>&1 \/ | grep '403 Forbidden' ; then
  echo "We were expecting to be rejected with 403 error here - we are not in the Congo!"
  exit 2
else
  echo "Rejected as expected - we are not in the Congo!"
fi

start_test "Test rate limits 1 per second" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"REQS_PER_MIN_PER_IP=60\" \
           -e \"REQS_PER_PAGE=0\" \
           -e \"CONCURRENT_CONNS_PER_IP=1\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test two connections in the same second get blocked..."
curl --fail -v -k https://${DOCKER_HOST_NAME}:${PORT}/
if curl -v -k https://${DOCKER_HOST_NAME}:${PORT}/ 2>&1 \
   | grep '503 Service Temporarily Unavailable' ; then
    echo "Passed return text on error with REQS_PER_MIN_PER_IP"
else
    echo "Failed return text on error with REQS_PER_MIN_PER_IP"
    exit 1
fi

start_test "Test multiple concurrent connections in the same second get blocked" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${SLOWMOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${SLOWMOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"REQS_PER_MIN_PER_IP=60\" \
           -e \"REQS_PER_PAGE=0\" \
           -e \"CONCURRENT_CONNS_PER_IP=1\" \
           --link \"${SLOWMOCKSERVER}:${SLOWMOCKSERVER}\" "
echo "First background some requests..."
curl -v -k https://${DOCKER_HOST_NAME}:${PORT} &>/dev/null &
curl -v -k https://${DOCKER_HOST_NAME}:${PORT} &>/dev/null &
curl -v -k https://${DOCKER_HOST_NAME}:${PORT} &>/dev/null &
curl -v -k https://${DOCKER_HOST_NAME}:${PORT} &>/dev/null &
echo "Now test we get blocked with second concurrent request..."
if curl -v -k https://${DOCKER_HOST_NAME}:${PORT}/ 2>&1 \
   | grep '503 Service Temporarily Unavailable' ; then
    echo "Passed return text on error with CONCURRENT_CONNS_PER_IP"
else
    echo "Failed return text on error with CONCURRENT_CONNS_PER_IP"
    exit 1
fi

start_test "Test response has gzip" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test gzip ok..."
curl -s -I -X GET -k --compressed https://${DOCKER_HOST_NAME}:${PORT}/gzip | grep -q 'Content-Encoding: gzip'

start_test "Start with SSL CIPHER set and PROTOCOL" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"SSL_CIPHERS=DHE-RSA-AES256-SHA\" \
           -e \"SSL_PROTOCOLS=TLSv1.2\""
echo "Test accepts defined protocol and cipher....."
docker run --link ${INSTANCE}:${INSTANCE} --rm --entrypoint bash ngx -c "echo GET / | /usr/bin/openssl s_client -cipher 'DHE-RSA-AES256-SHA' -tls1_2 -connect ${INSTANCE}:10443" &> /dev/null;



start_test "Start we auto add a protocol " "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\""

echo "Test it works if we do not define the protocol.."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/


start_test "Start with multi locations settings" "${STD_CMD} \
           -e \"LOCATIONS_CSV=/,/wiki/Wikipedia:About\" \
           -e \"PROXY_SERVICE_HOST_1=https://www.w3.org\" \
           -e \"PROXY_SERVICE_PORT_1=443\" \
           -e \"PROXY_SERVICE_HOST_2=https://en.wikipedia.org\" \
           -e \"PROXY_SERVICE_PORT_2=443\""


echo "Test for location 1 @ /..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Test for wikipedia about page..."
wget -O /dev/null --quiet --no-check-certificate --header="Host: en.wikipedia.org" https://${DOCKER_HOST_NAME}:${PORT}/wiki/Wikipedia:About

start_test "Start with Multiple locations, single proxy and NAXSI download." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=https://en.wikipedia.org\" \
           -e \"PROXY_SERVICE_PORT=443\" \
           -e \"LOCATIONS_CSV=/,/wiki/Wikipedia:About\" \
           -e \"NAXSI_RULES_URL_CSV_1=https://raw.githubusercontent.com/nbs-system/naxsi-rules/master/drupal.rules\" \
           -e \"NAXSI_RULES_MD5_CSV_1=3b3c24ed61683ab33d8441857c315432\""

echo "Test for all OK..."
wget -O /dev/null --quiet --no-check-certificate --header="Host: en.wikipedia.org" https://${DOCKER_HOST_NAME}:${PORT}/

echo "Test client certs..."
cd ./client_certs/
./create_ca.sh
./create_client_csr_and_key.sh
./sign_client_key_with_ca.sh
cd ..
start_test "Start with Client CA, and single proxy. Block unauth for /standards" \
           "${WORKDIR}/client_certs/ca.crt" "client-ca" "/etc/keys/" \
           "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"LOCATIONS_CSV=/,/standards/\" \
           -e \"CLIENT_CERT_REQUIRED_2=TRUE\" "

echo "Test access OK for basic area..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/

echo "Test access denied for /standards/..."
if wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/standards/ ; then
    echo "Error - expecting auth fail!"
    exit 1
else
    echo "Passed auth fail"
fi
echo "Test access OK for /standards/... with client cert..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/standards/ \
     --certificate=./client_certs/client.crt \
     --private-key=./client_certs/client.key

echo "Test upstream client certs..."
docker build -t mutual-tls:latest ${WORKDIR} -f docker-config/Dockerfile.mutual-tls
${STD_CMD} -d \
           -e "HTTP_LISTEN_PORT=10081" \
           -e "HTTPS_LISTEN_PORT=10444" \
           -e "PROXY_SERVICE_HOST=http://www.w3.org" \
           -e "PROXY_SERVICE_PORT=80" \
           -e "CLIENT_CERT_REQUIRED=TRUE" \
           -p 10444:10444 --name="${MUTUAL_TLS}" mutual-tls:latest
docker run --link "${MUTUAL_TLS}:${MUTUAL_TLS}" --rm martin/wait -p 10444

start_test "Start with upstream client certs" \
           "${WORKDIR}/client_certs/client.crt" "upstream-client-crt" "/etc/keys/" \
           "${WORKDIR}/client_certs/client.key" "upstream-client-key" "/etc/keys/" \
           "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=https://${MUTUAL_TLS}\" \
           -e \"PROXY_SERVICE_PORT=10444\" \
           -e \"DNSMASK=TRUE\" \
           -e \"USE_UPSTREAM_CLIENT_CERT=TRUE\" \
           --link \"${MUTUAL_TLS}:${MUTUAL_TLS}\" "

echo "Test it's up and working..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
tear_down_container "${MUTUAL_TLS}"

echo "Test failure to verify upstream server cert..."
docker build -t standard-tls:latest ${WORKDIR} -f docker-config/Dockerfile.standard-tls
${STD_CMD} -d \
           -e "HTTP_LISTEN_PORT=10081" \
           -e "HTTPS_LISTEN_PORT=10444" \
           -e "PROXY_SERVICE_HOST=http://www.w3.org" \
           -e "PROXY_SERVICE_PORT=80" \
           -p 10444:10444 --name="${STANDARD_TLS}" standard-tls:latest
docker run --link "${STANDARD_TLS}:${STANDARD_TLS}" --rm martin/wait -p 10444

start_test "Start with failing upstream server verification" \
           "${WORKDIR}/client_certs/ca.crt" "upstream-server-ca" "/etc/keys/" \
           "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=https://${STANDARD_TLS}\" \
           -e \"PROXY_SERVICE_PORT=10444\" \
           -e \"DNSMASK=TRUE\" \
           -e \"VERIFY_SERVER_CERT=TRUE\" \
           --link \"${STANDARD_TLS}:${STANDARD_TLS}\" "

echo "Test it blocks the request, returning a 502..."
if curl -ki https://${DOCKER_HOST_NAME}:${PORT}/ | grep "502 Bad Gateway" ; then
    echo "Passed failure to verify upstream server cert"
else
    echo "Failed failure to verify upstream server cert"
    exit 1
fi
tear_down_container "${STANDARD_TLS}"

cd ./client_certs/
./create_server_csr_and_key.sh
./sign_server_key_with_ca.sh
cd ..
${STD_CMD} -d \
           -e "HTTP_LISTEN_PORT=10081" \
           -e "HTTPS_LISTEN_PORT=10444" \
           -e "PROXY_SERVICE_HOST=http://www.w3.org" \
           -e "PROXY_SERVICE_PORT=80" \
           -p 10444:10444 --name="${STANDARD_TLS}" ${TAG}
docker start ${STANDARD_TLS}
docker run --link "${STANDARD_TLS}:${STANDARD_TLS}" --rm martin/wait -p 10444

start_test "Start with succeeding upstream server verification" \
           "${WORKDIR}/client_certs/ca.crt" "upstream-server-ca" "/etc/keys/" \
           "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=https://${STANDARD_TLS}\" \
           -e \"PROXY_SERVICE_PORT=10444\" \
           -e \"DNSMASK=TRUE\" \
           -e \"VERIFY_SERVER_CERT=TRUE\" \
           --link \"${STANDARD_TLS}:${STANDARD_TLS}\" "

tear_down_container "${STANDARD_TLS}"

start_test "Start with Custom error pages redirect off" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"LOCATIONS_CSV=/,/api/\" \
           -e \"ERROR_REDIRECT_CODES_2=502\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test All ok..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/api/
if curl -v -k https://${DOCKER_HOST_NAME}:${PORT}/api/dead | grep "Oh dear" ; then
    echo "Passed return text on error with ERROR_REDIRECT_CODES"
else
    echo "Failed return text on error with ERROR_REDIRECT_CODES"
    exit 1
fi

#--------------------------------------------------------------------------------------------------
# currently fails here
#wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
#docker ps -a --filter "status=running" | grep ${INSTANCE}
#docker logs ${INSTANCE}
#wget -O /dev/null --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
#tear_down_container "${STANDARD_TLS}"

# testing stuff
#clean_up
#exit
# -------------

start_test "Test custom error pages..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"ERROR_REDIRECT_CODES=502 404 500\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
if curl -k https://${DOCKER_HOST_NAME}:${PORT}/not-found | grep "404 Not Found" ; then
    if curl -k https://${DOCKER_HOST_NAME}:${PORT}/api/dead | grep "An error occurred" ; then
        echo "Passed custom error pages with ERROR_REDIRECT_CODES"
    else
        echo "Failed custom error pages with ERROR_REDIRECT_CODES on code 500"
        exit 1
    fi
else
    echo "Failed custom error pages with ERROR_REDIRECT_CODES on code 404"
    exit 1
fi

start_test "Start with Custom upload size" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"CLIENT_MAX_BODY_SIZE=15\" \
           -e \"NAXSI_USE_DEFAULT_RULES=FALSE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"DNSMASK=TRUE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
dd if=/dev/urandom of=/tmp/file.txt bs=1048576 count=10

echo "Upload a large file"
curl -k -F "file=@/tmp/file.txt;filename=nameinpost" \
     https://${DOCKER_HOST_NAME}:${PORT}/uploads/doc &> /tmp/upload_test.txt
grep "Thanks for the big doc" /tmp/upload_test.txt &> /dev/null


start_test "Start with listen for port 80" "${STD_CMD} \
           -p 8888:10080 \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"HTTPS_REDIRECT_PORT=${PORT}\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test Redirect ok..."
wget -O /dev/null --quiet --no-check-certificate http://${DOCKER_HOST_NAME}:8888/


start_test "Test text logging format..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"LOG_FORMAT_NAME=text\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test request (with logging as text)..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Testing text logs format..."
docker logs ${INSTANCE} | grep "\"GET / HTTP/1.1\" 200"

start_test "Test json logging format..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"LOG_FORMAT_NAME=json\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}?animal=cow
echo "Testing json logs format..."
docker logs ${INSTANCE}  | grep '{"proxy_proto_address":'
docker logs ${INSTANCE}  | grep 'animal=cow'


start_test "Test param logging off option works..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"LOG_FORMAT_NAME=json\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"NO_LOGGING_URL_PARAMS=TRUE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}?animal=cow
echo "Testing no logging of url params option works..."
docker logs ${INSTANCE} 2>/dev/null | grep '{"proxy_proto_address":'
docker logs ${INSTANCE} 2>/dev/null | grep 'animal=cow' | wc -l | grep 0

start_test "Test ENABLE_WEB_SOCKETS..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_WEB_SOCKETS=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/

start_test "Test ADD_NGINX_LOCATION_CFG param..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"LOCATIONS_CSV=/,/api/\" \
           -e \"ADD_NGINX_LOCATION_CFG=return 200 NICE;\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
echo "Test extra param works"
wget  -O - -o /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/wow | grep "NICE"


start_test "Test UUID GET param logging option works..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=TRUE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}
echo "Testing no logging of url params option works..."
docker logs "${MOCKSERVER}" | grep '?nginxId='
docker logs ${INSTANCE} | grep '"nginx_uuid": "'

start_test "Test UUID GET param logging option works with other params..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=TRUE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}/?foo=bar
echo "Testing no logging of url params option works..."
docker logs "${MOCKSERVER}" | grep '?foo=bar&nginxId='
docker logs ${INSTANCE} | grep '"nginx_uuid": "'

start_test "Test UUID header logging option works..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=HEADER\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}
echo "Testing no logging of url params option works..."
docker logs "${MOCKSERVER}" | grep 'Nginxid:'
docker logs ${INSTANCE} | grep '"nginx_uuid": "'

start_test "Test UUID header logging option passes through supplied value..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=HEADER\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
curl -sk -H "nginxId: 00000000-1111-2222-3333-444455556666" https://${DOCKER_HOST_NAME}:${PORT}
echo "Testing no logging of url params option works..."
docker logs "${MOCKSERVER}" | grep 'Nginxid:00000000-1111-2222-3333-444455556666'
docker logs ${INSTANCE} | grep '"nginx_uuid": "00000000-1111-2222-3333-444455556666"'

start_test "Test VERBOSE_ERROR_PAGES=TRUE displays debug info" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"VERBOSE_ERROR_PAGES=TRUE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
if curl -k https://${DOCKER_HOST_NAME}:${PORT}/\?\"==\` | grep "Sorry, we are refusing to process your request." ; then
  echo "Testing VERBOSE_ERROR_PAGES works..."
else
  echo "Testing VERBOSE_ERROR_PAGES failed..."
  exit 1
fi

start_test "Test VERBOSE_ERROR_PAGES is not set does not display debug info" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
if curl -k https://${DOCKER_HOST_NAME}:${PORT}/\?\"==\` | grep "Sorry, we are refusing to process your request." ; then
  echo "Testing VERBOSE_ERROR_PAGES failed..."
  exit 1
else
  echo "Testing VERBOSE_ERROR_PAGES works..."
fi

start_test "Test VERBOSE_ERROR_PAGES is not set displays default message info" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
if curl -k https://${DOCKER_HOST_NAME}:${PORT}/\?\"==\` | grep "Something went wrong." ; then
  echo "Testing VERBOSE_ERROR_PAGES works..."
else
  echo "Testing VERBOSE_ERROR_PAGES failed..."
  exit 1
fi

start_test "Test FEEDBACK_EMAIL is set, displays contact message info" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"FEEDBACK_EMAIL=test@test.com\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
if curl -k https://${DOCKER_HOST_NAME}:${PORT}/\?\"==\` | grep "test@test.com" ; then
  echo "Testing VERBOSE_ERROR_PAGES works..."
else
  echo "Testing VERBOSE_ERROR_PAGES failed..."
  exit 1
fi

start_test "Test FEEDBACK_EMAIL is not set, does not display email message info" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://${MOCKSERVER}\" \
           -e \"PROXY_SERVICE_PORT=${MOCKSERVER_PORT}\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link \"${MOCKSERVER}:${MOCKSERVER}\" "
if curl -k https://${DOCKER_HOST_NAME}:${PORT}/\?\"==\` | grep "please contact us on" ; then
  echo "Testing VERBOSE_ERROR_PAGES failed..."
  exit 1
else
  echo "Testing VERBOSE_ERROR_PAGES works..."
fi

echo "_________________________________"
echo "We got here, ALL tests successful"
clean_up
