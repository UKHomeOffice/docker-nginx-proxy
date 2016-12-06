#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -e

OPEN_RESTY_URL=http://openresty.org/download
OPEN_RESTY_VER=1.9.15.1
LUAROCKS_VER=2.2.1
NAXSI_VER=0.54
STATSD_VER=0.0.1

# Install all dependacies to build from source
yum -y install \
    gcc-c++ \
    gcc \
    geoip \
    geoip-devel \
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

# Prepare
wget -O ngx_openresty-${OPEN_RESTY_VER}.tar.gz ${OPEN_RESTY_URL}/openresty-${OPEN_RESTY_VER}.tar.gz
tar xzvf ngx_openresty-${OPEN_RESTY_VER}.tar.gz
rm ngx_openresty-${OPEN_RESTY_VER}.tar.gz

wget -O luarocks-${LUAROCKS_VER}.tar.gz http://luarocks.org/releases/luarocks-${LUAROCKS_VER}.tar.gz
tar xzvf luarocks-${LUAROCKS_VER}.tar.gz
rm luarocks-${LUAROCKS_VER}.tar.gz

wget -O naxsi-${NAXSI_VER}.tar.gz https://github.com/nbs-system/naxsi/archive/${NAXSI_VER}.tar.gz
tar xzvf naxsi-${NAXSI_VER}.tar.gz
rm naxsi-${NAXSI_VER}.tar.gz

wget -O nginx_statsd-${STATSD_VER}.tar.gz https://github.com/UKHomeOffice/nginx-statsd/archive/${STATSD_VER}.tar.gz
tar -xvzf nginx_statsd-${STATSD_VER}.tar.gz
rm nginx_statsd-${STATSD_VER}.tar.gz

# Build!
cd openresty-${OPEN_RESTY_VER}
./configure --add-module=../naxsi-0.54/naxsi_src \
            --add-module=../nginx-statsd-${STATSD_VER} \
            --with-http_realip_module \
            --with-http_geoip_module \
            --with-http_stub_status_module
make
make install
cd ..

# Install NAXSI default rules...
mkdir -p /usr/local/openresty/naxsi/
cp ./naxsi-0.54/naxsi_config/naxsi_core.rules  /usr/local/openresty/naxsi/

cd luarocks-${LUAROCKS_VER}
./configure --with-lua=/usr/local/openresty/luajit \
    --lua-suffix=jit-2.1.0-beta2 \
    --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1
make build
make install
cd ..
luarocks install uuid
luarocks install luasocket
luarocks install lua-geoip
cd -

# Cleaning up source...
rm -fr openresty-${OPEN_RESTY_VER}
rm -fr luarocks-${LUAROCKS_VER}
rm -fr naxsi-${NAXSI_VER}
rm -fr nginx-statsd-${STATSD_VER}

# Remove the developer tooling
yum -y remove \
    gcc-c++ \
    gcc \
    geoip-devel \
    make \
    openssl-devel \
    perl \
    pcre-devel \
    readline-devel

yum clean all
