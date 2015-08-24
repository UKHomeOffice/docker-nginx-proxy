FROM quay.io/ukhomeofficedigital/docker-centos-base:master

MAINTAINER Lewis Marshall <lewis@technoplusit.co.uk>

WORKDIR /root
ADD ./build.sh /root/
RUN ./build.sh

RUN yum install -y openssl && \
    mkdir -p /etc/keys && \
    cd /etc/keys && \
    openssl req -x509 -newkey rsa:2048 -keyout key -out crt -days 360 -nodes -subj '/CN=test'

ADD ./nginx.conf /usr/local/openresty/nginx/conf/

WORKDIR /usr/local/openresty

ENTRYPOINT ["/usr/local/openresty/nginx/sbin/nginx", "-g", "daemon off;"]

EXPOSE 443