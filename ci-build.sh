#!/usr/bin/env bash

set -e

TAG=ngx
PORT=8443
START_INSTANCE="docker run "
DOCKER_HOST_NAME=${DOCKER_HOST_NAME:-'127.0.0.1'}
MUTUAL_TLS="mutual-tls"
STANDARD_TLS="standard-tls"

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
    tear_down_container ${INSTANCE}
}

function clean_up() {
    rm -f /tmp/file.txt
    tear_down_container mockserver
    tear_down_container slowmockserver
    tear_down_container ${MUTUAL_TLS}
    tear_down_container ${STANDARD_TLS}
    tear_down_container ${TAG}
}

function start_test() {
    INSTANCE=${TAG}
    tear_down
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
${STD_CMD} -d -p 6000:6000 \
           -v ${PWD}/test-servers.yaml:/test-servers.yaml \
           --name=mockserver quii/mockingjay-server:1.9.0 \
           -config=/test-servers.yaml \
           -debug \
           -port=6000
docker run --rm --link mockserver:mockserver martin/wait

echo "Running slow-mocking-server..."
${STD_CMD} -d -p 6001:6001 \
           -v ${PWD}/test-servers.yaml:/test-servers.yaml \
           -v ${PWD}/monkey-business.yaml:/monkey-business.yaml \
           --name=slowmockserver quii/mockingjay-server:1.9.0 \
           -config=/test-servers.yaml \
           -monkeyConfig=/monkey-business.yaml \
           -debug \
           -port=6001
docker run --rm --link slowmockserver:slowmockserver martin/wait

echo "=========="
echo "TESTING..."
echo "=========="

start_test "Start with minimal settings" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\""

echo "Test it's up and working..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Test limited protcol and SSL cipher... "
docker run --link ${TAG}:${TAG}--rm --entrypoint bash ngx -c "echo GET / | /usr/bin/openssl s_client -cipher 'AES256+EECDH' -tls1_2 -connect ${TAG}:10443" &> /dev/null;
echo "Test sslv2 not accepted...."
if docker run --link ${TAG}:${TAG}--rm --entrypoint bash ngx -c "echo GET / | /usr/bin/openssl s_client -ssl2 -connect ${TAG}:10443" &> /dev/null; then
  echo "FAIL SSL defaults settings allow ssl2 ......"
  exit 2
fi

start_test "Test enabling GEODB settings" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"ALLOW_COUNTRY_CSV=GB,FR,O1\" \
           --link mockserver:mockserver "
echo "Test GeoIP config isn't rejected..."
curl --fail -s -v -k https://${DOCKER_HOST_NAME}:${PORT}/

start_test "Test GEODB settings can reject..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"ALLOW_COUNTRY_CSV=CG\" \
           -e \"DENY_COUNTRY_ON=TRUE\" \
           -e \"ADD_NGINX_LOCATION_CFG=error_page 403 /nginx-proxy/50x.shtml;\" \
           --link mockserver:mockserver "
echo "Test GeoIP config IS rejected..."
if ! curl -v -k https://${DOCKER_HOST_NAME}:${PORT}/ 2>&1 \/ | grep '403 Forbidden' ; then
  echo "We were expecting to be rejected with 403 error here - we are not in the Congo!"
  exit 2
else
  echo "Rejected as expected - we are not in the Congo!"
fi
if ! curl -v -k https://${DOCKER_HOST_NAME}:${PORT}/ 2>&1 \
  | grep 'An error occurred' ; then
  echo "We were expecting to be rejected specific content for invalid country - we are not in the Congo!"
  exit 2
else
  echo "Rejected with correct content as expected."
fi

start_test "Test rate limits 1 per second" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"REQS_PER_MIN_PER_IP=60\" \
           -e \"REQS_PER_PAGE=0\" \
           -e \"CONCURRENT_CONNS_PER_IP=1\" \
           --link mockserver:mockserver "
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
           -e \"PROXY_SERVICE_HOST=http://slowmockserver\" \
           -e \"PROXY_SERVICE_PORT=6001\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"REQS_PER_MIN_PER_IP=60\" \
           -e \"REQS_PER_PAGE=0\" \
           -e \"CONCURRENT_CONNS_PER_IP=1\" \
           --link slowmockserver:slowmockserver "
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
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
echo "Test gzip ok..."
curl -s -I -X GET -k --compressed https://${DOCKER_HOST_NAME}:${PORT}/gzip | grep -q 'Content-Encoding: gzip'

start_test "Start with SSL CIPHER set and PROTOCOL" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"SSL_CIPHERS=RC4-MD5\" \
           -e \"SSL_PROTOCOLS=TLSv1.1\""
echo "Test excepts defined protocol and cipher....."
docker run --link ${TAG}:${TAG} --rm --entrypoint bash ngx -c "echo GET / | /usr/bin/openssl s_client -cipher 'RC4-MD5' -tls1_1 -connect ${TAG}:10443" &> /dev/null;



start_test "Start we auto add a protocol " "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\""

echo "Test It works if we do not define the protocol.."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/


start_test "Start with multi locations settings" "${STD_CMD} \
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
           -e \"PROXY_SERVICE_HOST=http://www.bbc.co.uk\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"LOCATIONS_CSV=/,/news\" \
           -e \"NAXSI_RULES_URL_CSV_1=https://raw.githubusercontent.com/nbs-system/naxsi-rules/master/drupal.rules\" \
           -e \"NAXSI_RULES_MD5_CSV_1=3b3c24ed61683ab33d8441857c315432\""

echo "Test for all OK..."
wget -O /dev/null --quiet --no-check-certificate --header="Host: www.bbc.co.uk" https://${DOCKER_HOST_NAME}:${PORT}/




echo "Test client certs..."
cd ./client_certs/
./create_ca.sh
./create_client_csr_and_key.sh
./sign_client_key_with_ca.sh
cd ..
start_test "Start with Client CA, and single proxy. Block unauth for /standards" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://www.w3.org\" \
           -e \"PROXY_SERVICE_PORT=80\" \
           -e \"LOCATIONS_CSV=/,/standards/\" \
           -e \"CLIENT_CERT_REQUIRED_2=TRUE\" \
           -v ${PWD}/client_certs/ca.crt:/etc/keys/client-ca "

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
${STD_CMD} -d \
           -e "PROXY_SERVICE_HOST=http://www.w3.org" \
           -e "PROXY_SERVICE_PORT=80" \
           -e "CLIENT_CERT_REQUIRED=TRUE" \
           -v "${PWD}/client_certs/ca.crt:/etc/keys/client-ca" \
           --name="${MUTUAL_TLS}" ${TAG}
docker run --link "${MUTUAL_TLS}:${MUTUAL_TLS}" --rm martin/wait
start_test "Start with upstream client certs" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=https://${MUTUAL_TLS}\" \
           -e \"PROXY_SERVICE_PORT=10443\" \
           -e \"DNSMASK=TRUE\" \
           -e \"USE_UPSTREAM_CLIENT_CERT=TRUE\" \
           -v \"${PWD}/client_certs/client.crt:/etc/keys/upstream-client-crt\" \
           -v \"${PWD}/client_certs/client.key:/etc/keys/upstream-client-key\" \
           --link \"${MUTUAL_TLS}:${MUTUAL_TLS}\" "
echo "Test it's up and working..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
tear_down_container "${MUTUAL_TLS}"

echo "Test failure to verify upstream server cert..."
${STD_CMD} -d \
           -e "PROXY_SERVICE_HOST=http://www.w3.org" \
           -e "PROXY_SERVICE_PORT=80" \
           --name="${STANDARD_TLS}" ${TAG}
docker run --link "${STANDARD_TLS}:${STANDARD_TLS}" --rm martin/wait
start_test "Start with failing upstream server verification" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=https://${STANDARD_TLS}\" \
           -e \"PROXY_SERVICE_PORT=10443\" \
           -e \"DNSMASK=TRUE\" \
           -e \"VERIFY_SERVER_CERT=TRUE\" \
           -v \"${PWD}/client_certs/ca.crt:/etc/keys/upstream-server-ca\" \
           --link \"${STANDARD_TLS}:${STANDARD_TLS}\" "
echo "Test it blocks the request, returning a 502..."
if curl -ki https://${DOCKER_HOST_NAME}:${PORT}/ | grep "502 Bad Gateway" ; then
    echo "Passed failure to verify upstream server cert"
else
    echo "Failed failure to verify upstream server cert"
    exit 1
fi
tear_down_container "${STANDARD_TLS}"

echo "Test successfully verifying upstream server cert..."
cd ./client_certs/
./create_server_csr_and_key.sh
./sign_server_key_with_ca.sh
cd ..
${STD_CMD} -d \
           -e "PROXY_SERVICE_HOST=http://www.w3.org" \
           -e "PROXY_SERVICE_PORT=80" \
           -v "${PWD}/client_certs/server.crt:/etc/keys/crt" \
           -v "${PWD}/client_certs/server.key:/etc/keys/key" \
           --name="${STANDARD_TLS}" ${TAG}
docker run --link "${STANDARD_TLS}:${STANDARD_TLS}" --rm martin/wait
start_test "Start with succeeding upstream server verification" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=https://${STANDARD_TLS}\" \
           -e \"PROXY_SERVICE_PORT=10443\" \
           -e \"DNSMASK=TRUE\" \
           -e \"VERIFY_SERVER_CERT=TRUE\" \
           -v \"${PWD}/client_certs/ca.crt:/etc/keys/upstream-server-ca\" \
           --link \"${STANDARD_TLS}:${STANDARD_TLS}\" "
echo "Test it allows the request through..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
tear_down_container "${STANDARD_TLS}"

start_test "Start with Custom error pages redirect off" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"LOCATIONS_CSV=/,/api/\" \
           -e \"ERROR_REDIRECT_CODES_2=502\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
echo "Test All ok..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/api/
if curl -v -k https://${DOCKER_HOST_NAME}:${PORT}/api/dead | grep "Oh dear" ; then
    echo "Passed return text on error with ERROR_REDIRECT_CODES"
else
    echo "Failed return text on error with ERROR_REDIRECT_CODES"
    exit 1
fi

start_test "Test custom error pages..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"ERROR_REDIRECT_CODES=502 404 500\" \
           --link mockserver:mockserver "
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
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
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
           -p 8888:10080 \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"HTTPS_REDIRECT_PORT=${PORT}\" \
           --link mockserver:mockserver "
echo "Test Redirect ok..."
wget -O /dev/null --quiet --no-check-certificate http://${DOCKER_HOST_NAME}:8888/


start_test "Test text logging format..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"LOG_FORMAT_NAME=text\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
echo "Test request (with logging as text)..."
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/
echo "Testing text logs format..."
#docker logs ${INSTANCE} | grep "\"GET / HTTP/1.1\" 200"

start_test "Test json logging format..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"LOG_FORMAT_NAME=json\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}?animal=cow
echo "Testing json logs format..."
#docker logs ${INSTANCE}  | grep '{"proxy_proto_address":'
#docker logs ${INSTANCE}  | grep 'animal=cow'

start_test "Test custom logging format..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"LOG_FORMAT_NAME=custom\" \
           -e \"CUSTOM_LOG_FORMAT=' \\\$host:\\\$server_port \\\$uuid \\\$http_x_forwarded_for \\\$remote_addr \\\$remote_user [\\\$time_local] \\\$request \\\$status \\\$body_bytes_sent \\\$request_time \\\$http_x_forwarded_proto \\\$http_referer \\\$http_user_agent '\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
wget -O /dev/null --quiet --no-check-certificate --header="Host: example.com" https://${DOCKER_HOST_NAME}:${PORT}?animal=cow
echo "Testing custom logs format..."
docker logs ${INSTANCE} | egrep '^\{\sexample\.com:10443.*\[.*\]\sGET\s\/\?animal\=cow\sHTTP/1\.\d\s200.*\s\}$'

start_test "Test param logging off option works..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"LOG_FORMAT_NAME=json\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"NO_LOGGING_URL_PARAMS=TRUE\" \
           --link mockserver:mockserver "
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}?animal=cow
echo "Testing no logging of url params option works..."
#docker logs ${INSTANCE} 2>/dev/null | grep '{"proxy_proto_address":'
#docker logs ${INSTANCE} 2>/dev/null | grep 'animal=cow' | wc -l | grep 0

start_test "Test ENABLE_WEB_SOCKETS..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_WEB_SOCKETS=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
wget -O /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/

start_test "Test ADD_NGINX_LOCATION_CFG param..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"LOCATIONS_CSV=/,/api/\" \
           -e \"ADD_NGINX_LOCATION_CFG=return 200 NICE;\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
echo "Test extra param works"
wget  -O - -o /dev/null --quiet --no-check-certificate https://${DOCKER_HOST_NAME}:${PORT}/wow | grep "NICE"


start_test "Test UUID GET param logging option works..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=TRUE\" \
           --link mockserver:mockserver "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}
echo "Testing no logging of url params option works..."
#docker logs mockserver | grep '?nginxId='
#docker logs ${INSTANCE} | grep '"nginx_uuid": "'

start_test "Test UUID GET param logging option works with other params..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=TRUE\" \
           --link mockserver:mockserver "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}/?foo=bar
echo "Testing no logging of url params option works..."
#docker logs mockserver | grep '?foo=bar&nginxId='
#docker logs ${INSTANCE} | grep '"nginx_uuid": "'

start_test "Test UUID header logging option works..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=HEADER\" \
           --link mockserver:mockserver "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}
echo "Testing no logging of url params option works..."
#docker logs mockserver | grep 'Nginxid:'
#docker logs ${INSTANCE} | grep '"nginx_uuid": "'

start_test "Test VERBOSE_ERROR_PAGES=TRUE displays debug info" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           -e \"VERBOSE_ERROR_PAGES=TRUE\" \
           --link mockserver:mockserver "
if curl -k https://${DOCKER_HOST_NAME}:${PORT}/\?\"==\` | grep "Sorry, we are refusing to process your request." ; then
  echo "Testing VERBOSE_ERROR_PAGES works..."
else
  echo "Testing VERBOSE_ERROR_PAGES failed..."
  exit 1
fi

start_test "Test VERBOSE_ERROR_PAGES is not set does not display debug info" "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=FALSE\" \
           --link mockserver:mockserver "
if curl -k https://${DOCKER_HOST_NAME}:${PORT}/\?\"==\` | grep "Sorry, we are refusing to process your request." ; then
  echo "Testing VERBOSE_ERROR_PAGES failed..."
  exit 1
else
  echo "Testing VERBOSE_ERROR_PAGES works..."
fi

start_test "Test setting UUID name works..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=6000\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=HEADER\" \
           -e \"UUID_VAR_NAME=custom_uuid_name\" \
           --link mockserver:mockserver "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}
docker logs mockserver 2>/dev/null | grep "custom_uuid_name"
echo "Testing setting UUID_VAR_NAME works"

start_test "Test setting empty UUID name defaults correctly..." "${STD_CMD} \
           -e \"PROXY_SERVICE_HOST=http://mockserver\" \
           -e \"PROXY_SERVICE_PORT=8080\" \
           -e \"DNSMASK=TRUE\" \
           -e \"ENABLE_UUID_PARAM=HEADER\" \
           -e \"UUID_VAR_NAME=\" \
           --link mockserver:mockserver "
curl -sk https://${DOCKER_HOST_NAME}:${PORT}
docker logs mockserver 2>/dev/null | grep "nginxId"
echo "Testing UUID_VAR_NAME default if empty works"

echo "_________________________________"
clean_up
echo "We got here, ALL tests successful"
exit 0
