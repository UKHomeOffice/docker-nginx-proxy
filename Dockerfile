FROM quay.io/ukhomeofficedigital/docker-centos-base:master

MAINTAINER Lewis Marshall <lewis@technoplusit.co.uk>

WORKDIR /root
ADD ./build.sh /root/
RUN ./build.sh

RUN yum install -y openssl && \
    yum clean all && \
    mkdir -p /etc/keys && \
    cd /etc/keys && \
    openssl req -x509 -newkey rsa:2048 -keyout key -out crt -days 360 -nodes -subj '/CN=test'

RUN yum install -y bind-utils && \
    yum clean all

RUN mkdir -p /usr/local/openresty/naxsi/location
ADD ./location.rules /usr/local/openresty/naxsi/location/

ADD ./nginx*.conf /usr/local/openresty/nginx/conf/
RUN mkdir /usr/local/openresty/nginx/conf/locations
RUN mkdir -p /usr/local/openresty/nginx/lua
ADD ./lua/* /usr/local/openresty/nginx/lua/
RUN md5sum /usr/local/openresty/nginx/conf/nginx.conf | cut -d' ' -f 1 > /container_default_ngx
ADD ./defaults.sh /
ADD ./go.sh /
ADD ./enable_location.sh /
ADD ./location_template.conf /

WORKDIR /usr/local/openresty

ENTRYPOINT ["/go.sh"]

EXPOSE 80
EXPOSE 443
