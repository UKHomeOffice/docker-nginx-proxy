#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -eu
set -o pipefail

LUAROCKS_URL='http://luarocks.org/releases/luarocks-2.4.2.tar.gz'
NAXSI_URL='https://github.com/nbs-system/naxsi/archive/0.56.tar.gz'
OPEN_RESTY_URL='http://openresty.org/download/openresty-1.11.2.4.tar.gz'
STATSD_URL='https://github.com/UKHomeOffice/nginx-statsd/archive/0.0.1.tar.gz'

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
    wget

mkdir -p openresty luarocks naxsi nginx-statsd

# Prepare
wget -qO - "$OPEN_RESTY_URL"   | tar xzv --strip-components 1 -C openresty/
wget -qO - "$LUAROCKS_URL"     | tar xzv --strip-components 1 -C luarocks/
wget -qO - "$NAXSI_URL"        | tar xzv --strip-components 1 -C naxsi/
wget -qO - "$STATSD_URL"       | tar xzv --strip-components 1 -C nginx-statsd/

# Build
pushd openresty
./configure --add-module="../naxsi/naxsi_src" \
            --add-module="../nginx-statsd" \
            --with-http_realip_module \
            --with-http_stub_status_module
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

# Remove the developer tooling
rm -fr openresty naxsi nginx-statsd luarocks
yum -y remove \
    gcc-c++ \
    gcc \
    git \
    make \
    openssl-devel \
    libcurl-devel \
    perl \
    pcre-devel \
    readline-devel

yum clean all
