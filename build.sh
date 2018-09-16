#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -eu
set -o pipefail

OPEN_RESTY_URL='http://openresty.org/download/openresty-1.11.2.4.tar.gz'
LUAROCKS_URL='http://luarocks.org/releases/luarocks-2.4.2.tar.gz'
NAXSI_URL='https://github.com/nbs-system/naxsi/archive/0.56.tar.gz'
STATSD_URL='https://github.com/UKHomeOffice/nginx-statsd/archive/0.0.1.tar.gz'
GEOIP_URL='https://github.com/maxmind/libmaxminddb/releases/download/1.3.2/libmaxminddb-1.3.2.tar.gz'
GEOIP_MOD_URL='https://github.com/leev/ngx_http_geoip2_module/archive/3.0.tar.gz'
MAXMIND_INSTALL_PATH='/usr/share/GeoIP'
MAXMIND_LIB_PATH=${MAXMIND_INSTALL_PATH}/lib
MAXMIND_INC_PATH=${MAXMIND_INSTALL_PATH}/include

# Install dependencies to build from source
yum -y install \
    gcc-c++ \
    gcc \
    git \
    make \
    openssl-devel \
    openssl \
    perl \
    pcre-devel \
    pcre \
    readline-devel \
    tar \
    unzip \
    wget

mkdir -p openresty luarocks naxsi nginx-statsd geoip ngx_http_geoip2_module

# Prepare
wget -qO - "$OPEN_RESTY_URL" | tar xzv --strip-components 1 -C openresty/
wget -qO - "$LUAROCKS_URL"   | tar xzv --strip-components 1 -C luarocks/
wget -qO - "$NAXSI_URL"      | tar xzv --strip-components 1 -C naxsi/
wget -qO - "$STATSD_URL"     | tar xzv --strip-components 1 -C nginx-statsd/
wget -qO - "$GEOIP_URL"      | tar xzv --strip-components 1 -C geoip/
wget -qO - "$GEOIP_MOD_URL"  | tar xzv --strip-components 1 -C ngx_http_geoip2_module/

# Build
pushd geoip
./configure --prefix=${MAXMIND_INSTALL_PATH}
make
make install
echo "${MAXMIND_LIB_PATH}" > /etc/ld.so.conf.d/libmaxminddb.conf
ldconfig -v 2>/dev/null | grep -i maxmind
curl -fSL http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.mmdb.gz | gzip -d > ${MAXMIND_INSTALL_PATH}/GeoLite2-Country.mmdb
curl -fSL http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz | gzip -d > ${MAXMIND_INSTALL_PATH}/GeoLite2-City.mmdb
popd

# check maxmind module
echo "Checking maxmind module..."
ldconfig -p | grep maxmind
echo "We're in $PWD" && ls -la

pushd openresty
./configure --add-dynamic-module="/root/ngx_http_geoip2_module" \
            --add-module="../naxsi/naxsi_src" \
            --add-module="../nginx-statsd" \
            --with-http_realip_module \
            --with-http_stub_status_module
make
make install
popd
 
# Install NAXSI default rules...
mkdir -p /usr/local/openresty/naxsi/
cp "./naxsi/naxsi_config/naxsi_core.rules" /usr/local/openresty/naxsi/

pushd luarocks
./configure --with-lua=/usr/local/openresty/luajit \
    --lua-suffix=jit-2.1.0-beta2 \
    --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1
make build install
popd

luarocks install uuid
luarocks install luasocket

Remove the developer tooling
rm -fr openresty naxsi nginx-statsd geoip luarocks ngx_http_geoip2_module
yum -y remove \
    gcc-c++ \
    gcc \
    git \
    make \
    openssl-devel \
    perl \
    pcre-devel \
    readline-devel

yum clean all
