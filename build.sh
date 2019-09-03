#!/usr/bin/env bash
# Script to install the openresty from source and to tidy up after...

set -eu
set -o pipefail

NAXSI_URL='https://github.com/nbs-system/naxsi/archive/0.56.tar.gz'
OPEN_RESTY_URL='http://openresty.org/download/openresty-1.11.2.4.tar.gz'

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

mkdir -p openresty naxsi

# Prepare
wget -qO - "$OPEN_RESTY_URL"   | tar xzv --strip-components 1 -C openresty/
wget -qO - "$NAXSI_URL"        | tar xzv --strip-components 1 -C naxsi/

# Build
pushd openresty
./configure --add-module="../naxsi/naxsi_src" \
            --with-http_realip_module \
            --with-http_stub_status_module
make install
popd

# Install NAXSI default rules...
mkdir -p /usr/local/openresty/naxsi/
cp "./naxsi/naxsi_config/naxsi_core.rules" /usr/local/openresty/naxsi/

# Remove the developer tooling
rm -fr openresty naxsi
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
