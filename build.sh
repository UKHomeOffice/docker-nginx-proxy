#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -eu
set -o pipefail

OPEN_RESTY_URL='http://openresty.org/download/openresty-1.13.6.1.tar.gz'
LUAROCKS_URL='http://luarocks.org/releases/luarocks-2.4.4.tar.gz'
NAXSI_URL='https://github.com/nbs-system/naxsi/archive/0.55.3.tar.gz'
STATSD_URL='https://github.com/UKHomeOffice/nginx-statsd/archive/0.0.1.tar.gz'
GEOIP_URL='https://github.com/maxmind/geoip-api-c/releases/download/v1.6.12/GeoIP-1.6.12.tar.gz'

# Install dependencies to build from source
yum -y install \
    gcc-c++ \
    gcc \
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

mkdir -p openresty luarocks naxsi nginx-statsd geoip

# Prepare
wget -qO - "$OPEN_RESTY_URL" | tar xzv --strip-components 1 -C openresty/
wget -qO - "$LUAROCKS_URL"   | tar xzv --strip-components 1 -C luarocks/
wget -qO - "$NAXSI_URL"      | tar xzv --strip-components 1 -C naxsi/
wget -qO - "$STATSD_URL"     | tar xzv --strip-components 1 -C nginx-statsd/
wget -qO - "$GEOIP_URL"      | tar xzv --strip-components 1 -C geoip/

# Build!
pushd geoip
./configure
make
make check install
popd
rm -fr geoip

pushd openresty
./configure --add-module="../naxsi/naxsi_src" \
            --add-module="../nginx-statsd" \
            --with-http_realip_module \
            --with-http_geoip_module \
            --with-http_stub_status_module
make
make install
popd

# Install NAXSI default rules...
mkdir -p /usr/local/openresty/naxsi/
cp "./naxsi/naxsi_config/naxsi_core.rules" /usr/local/openresty/naxsi/

rm -fr openresty naxsi nginx-statsd

pushd luarocks
./configure --with-lua=/usr/local/openresty/luajit \
    --lua-suffix=jit-2.1.0-beta2 \
    --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1
make build install
popd
rm -fr luarocks

luarocks install uuid
luarocks install luasocket
luarocks install lua-geoip

# Remove the developer tooling
yum -y remove \
    gcc-c++ \
    gcc \
    make \
    openssl-devel \
    perl \
    pcre-devel \
    readline-devel

yum clean all
