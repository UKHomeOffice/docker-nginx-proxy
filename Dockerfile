# quay.io/ukhomeofficedigital/centos-base:latest
FROM quay.io/ukhomeofficedigital/centos-base@sha256:784951d9caa3459a017806bf65c42d49655038f4aeb91f5eccdfd18f198b166e
MAINTAINER Lewis Marshall <lewis@technoplusit.co.uk>

WORKDIR /root

RUN yum -y install deltarpm && yum -y update && yum -y upgrade && yum clean all && yum -y erase deltarpm

ADD ./build.sh /root/
RUN ./build.sh

RUN yum install -y openssl && yum clean all

# This takes a while so best to do it during build
RUN openssl dhparam -out /usr/local/openresty/nginx/conf/dhparam.pem 2048

RUN yum install -y bind-utils dnsmasq && \
    yum clean all

ADD ./naxsi/location.rules /usr/local/openresty/naxsi/location.template
ADD ./nginx*.conf /usr/local/openresty/nginx/conf/
RUN mkdir -p /usr/local/openresty/nginx/conf/locations /usr/local/openresty/nginx/lua
ADD ./lua/* /usr/local/openresty/nginx/lua/
RUN md5sum /usr/local/openresty/nginx/conf/nginx.conf | cut -d' ' -f 1 > /container_default_ngx
ADD ./defaults.sh /
ADD ./go.sh /
ADD ./enable_location.sh /
ADD ./location_template.conf /
ADD ./logging.conf /usr/local/openresty/nginx/conf/
ADD ./security_defaults.conf /usr/local/openresty/nginx/conf/
ADD ./html/ /usr/local/openresty/nginx/html/
ADD ./readyness.sh /
ADD ./helper.sh /
ADD ./refresh_geoip.sh /

RUN yum remove -y kernel-headers && \
    yum clean all

RUN rm -rf /var/cache/yum

RUN yum --enablerepo=extras install epel-release -y && \
      yum install python-pip -y && \
      pip install awscli

RUN useradd -u 1000 nginx && \
    install -o nginx -g nginx -d \
      /etc/keys \
      /usr/local/openresty/naxsi/locations \
      /usr/local/openresty/nginx/{client_body,fastcgi,proxy,scgi,uwsgi}_temp && \
    chown -R nginx:nginx /usr/local/openresty/nginx/{conf,logs} /usr/share/GeoIP


WORKDIR /usr/local/openresty

EXPOSE 10080 10443

USER 1000

ENTRYPOINT [ "/go.sh" ]
