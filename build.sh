#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -eu
set -o pipefail

if [ -z "$GEOIP_LICENSE_KEY" ]; then
  LOCAL_TEST=true
else
  LOCAL_TEST=false
fi

GEOIP_ACCOUNT_ID="${GEOIP_ACCOUNT_ID:-123456}"
GEOIP_LICENSE_KEY="${GEOIP_LICENSE_KEY:-xxxxxx}"
GEOIP_CITY_URL="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=${GEOIP_LICENSE_KEY}&suffix=tar.gz"
GEOIP_COUNTRY_URL="https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=${GEOIP_LICENSE_KEY}&suffix=tar.gz"
GEOIP_MOD_URL='https://github.com/leev/ngx_http_geoip2_module/archive/3.3.tar.gz'
GEOIP_UPDATE_CLI='https://github.com/maxmind/geoipupdate/releases/download/v4.7.1/geoipupdate_4.7.1_linux_amd64.tar.gz'
GEOIP_URL='https://github.com/maxmind/libmaxminddb/releases/download/1.6.0/libmaxminddb-1.6.0.tar.gz'
LUAROCKS_URL='https://luarocks.github.io/luarocks/releases/luarocks-3.7.0.tar.gz'
NAXSI_URL='https://github.com/nbs-system/naxsi/archive/1.3.tar.gz'
OPEN_RESTY_URL='http://openresty.org/download/openresty-1.19.3.2.tar.gz'
STATSD_URL='https://github.com/UKHomeOffice/nginx-statsd/archive/0.0.1-ngxpatch.tar.gz'

MAXMIND_PATH='/usr/share/GeoIP'

# Install dependencies to build from source
yum -y install \
    gcc-c++ \
    gcc \
    git \
    make \
    libcurl-devel \
    openssl-devel \
    openssl \
    perl \
    pcre-devel \
    pcre \
    readline-devel \
    tar \
    unzip \
    wget \
    zlib \
    zlib-devel 

mkdir -p openresty luarocks naxsi nginx-statsd geoip geoipupdate ngx_http_geoip2_module

# Prepare
wget -qO - "$OPEN_RESTY_URL"   | tar xzv --strip-components 1 -C openresty/
wget -qO - "$LUAROCKS_URL"     | tar xzv --strip-components 1 -C luarocks/
wget -qO - "$NAXSI_URL"        | tar xzv --strip-components 1 -C naxsi/
wget -qO - "$STATSD_URL"       | tar xzv --strip-components 1 -C nginx-statsd/
wget -qO - "$GEOIP_URL"        | tar xzv --strip-components 1 -C geoip/
wget -qO - "$GEOIP_UPDATE_CLI" | tar xzv --strip-components 1 -C geoipupdate/
wget -qO - "$GEOIP_MOD_URL"    | tar xzv --strip-components 1 -C ngx_http_geoip2_module/

# Build
pushd geoip
mkdir -p ${MAXMIND_PATH}
./configure
make check install
echo "/usr/local/lib" >> /etc/ld.so.conf.d/libmaxminddb.conf

# Only run if not testing locally
if [ "$LOCAL_TEST" = false ]; then
  curl -fSL ${GEOIP_COUNTRY_URL} | tar -xz > ${MAXMIND_PATH}/GeoLite2-Country.mmdb
  curl -fSL ${GEOIP_CITY_URL} | tar -xz > ${MAXMIND_PATH}/GeoLite2-City.mmdb
fi

chown -R 1000:1000 ${MAXMIND_PATH}
popd

pushd geoipupdate
sed -i 's/YOUR_ACCOUNT_ID_HERE/'"${GEOIP_ACCOUNT_ID}"'/g' GeoIP.conf
sed -i 's/YOUR_LICENSE_KEY_HERE/'"${GEOIP_LICENSE_KEY}"'/g' GeoIP.conf

# Only run if not testing locally
if [ "$LOCAL_TEST" = false ]; then
  ./geoipupdate -f GeoIP.conf -d ${MAXMIND_PATH}
fi
popd

echo "Checking libmaxminddb module"
ldconfig && ldconfig -p | grep libmaxminddb

echo "Install openresty"
pushd openresty
./configure --add-dynamic-module="/root/ngx_http_geoip2_module" \
            --add-module="../naxsi/naxsi_src" \
            --add-module="../nginx-statsd" \
            --with-http_realip_module \
            --with-http_v2_module \
            --with-http_stub_status_module
make install
popd

echo "Install NAXSI default rules"
mkdir -p /usr/local/openresty/naxsi/
cp "./naxsi/naxsi_config/naxsi_core.rules" /usr/local/openresty/naxsi/

echo "Installing luarocks"
pushd luarocks
./configure --with-lua=/usr/local/openresty/luajit \
            --lua-suffix=jit-2.1.0-beta2 \
            --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1
make build install
popd

echo "Installing luarocks packages"
luarocks install uuid
luarocks install luasocket

echo "Removing unnecessary developer tooling"
rm -fr openresty naxsi nginx-statsd geoip luarocks ngx_http_geoip2_module 
echo "Yum remove tooling"
yum -y remove \
    gcc-c++ \
    gcc \
    git \
    make \
    openssl-devel \
    libcurl-devel \
    perl \
    pcre-devel \
    readline-devel \
    zlib \
    zlib-devel --skip-broken

yum clean all