FROM quay.io/ukhomeofficedigital/centos-base:latest

ARG GEOIP_ACCOUNT_ID
ARG GEOIP_LICENSE_KEY

WORKDIR /root
ADD ./build.sh /root/
RUN ./build.sh

RUN yum install -y openssl && \
    yum clean all && \
    mkdir -p /etc/keys && \
    openssl req -x509 -newkey rsa:2048 -keyout /etc/keys/key -out /etc/keys/crt -days 360 -nodes -subj '/CN=test' && \
    chmod 644 /etc/keys/key

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

RUN useradd -u 1000 nginx && \
    install -o nginx -g nginx -d \
      /usr/local/openresty/naxsi/locations \
      /usr/local/openresty/nginx/{client_body,fastcgi,proxy,scgi,uwsgi}_temp && \
    chown -R nginx:nginx /usr/local/openresty/nginx/{conf,logs} /usr/share/GeoIP

WORKDIR /usr/local/openresty

EXPOSE 10080 10443

USER 1000

ENTRYPOINT [ "/go.sh" ]
