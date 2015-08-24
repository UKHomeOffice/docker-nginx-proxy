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

ADD ./nginx.conf /usr/local/openresty/nginx/conf/
ADD ./go.sh /

WORKDIR /usr/local/openresty

ENTRYPOINT ["/go.sh"]

EXPOSE 443