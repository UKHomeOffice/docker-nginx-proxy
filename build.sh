#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -e

OPEN_RESTY_URL=http://openresty.org/download
OPEN_RESTRY_VER=1.9.7.4
LUAROCKS_VER=2.2.1

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
wget -O ngx_openresty-${OPEN_RESTRY_VER}.tar.gz ${OPEN_RESTY_URL}/openresty-${OPEN_RESTRY_VER}.tar.gz
tar xzvf ngx_openresty-${OPEN_RESTRY_VER}.tar.gz
rm ngx_openresty-${OPEN_RESTRY_VER}.tar.gz

wget -O luarocks-${LUAROCKS_VER}.tar.gz http://luarocks.org/releases/luarocks-${LUAROCKS_VER}.tar.gz
tar xzvf luarocks-${LUAROCKS_VER}.tar.gz
rm luarocks-${LUAROCKS_VER}.tar.gz

wget -O naxsi.zip https://github.com/nbs-system/naxsi/archive/master.zip
unzip naxsi.zip
rm naxsi.zip

# Build!
cd openresty-${OPEN_RESTRY_VER}
./configure --add-module=../naxsi-master/naxsi_src \
            --with-http_realip_module \
            --with-http_geoip_module
make
make install
cd ..

# Install NAXSI default rules...
mkdir -p /usr/local/openresty/naxsi/
cp ./naxsi-master/naxsi_config/naxsi_core.rules  /usr/local/openresty/naxsi/

cd luarocks-${LUAROCKS_VER}
./configure --with-lua=/usr/local/openresty/luajit \
    --lua-suffix=jit-2.1.0-beta1 \
    --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1
make build
make install
cd ..
luarocks install uuid
luarocks install luasocket
#luarocks --from=http://geoip.luaforge.net/rocks install geoip
#http://files.luaforge.net/releases/geoip/geoip/0.1-1
cd -

exit 0
# Cleaning up source...
rm -fr openresty-${OPEN_RESTRY_VER}
rm -fr luarocks-${LUAROCKS_VER}
rm -fr naxsi-master

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
