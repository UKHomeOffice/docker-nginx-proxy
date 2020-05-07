FROM alpine@sha256:6a92cd1fcdc8d8cdec60f33dda4db2cb1fcdcacf3410a8e05b3741f44a9b5998

USER root

ENTRYPOINT ["tini", "--"]

RUN ["apk", "--no-cache", "upgrade"]
RUN ["apk", "--no-cache", "add", "tini", "dnsmasq", "bash", "curl", "openssl"]
# naxsi and awscli are not available from the main Alpine repositories yet.
RUN ["apk", "--no-cache", "--repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing", "add", \
     "nginx-naxsi=1.16.0-r1", "nginx-naxsi-mod-http-naxsi=1.16.0-r1", "nginx-naxsi-mod-http-xslt-filter=1.16.0-r1"]

RUN ["apk", "--no-cache", "--repository=http://dl-cdn.alpinelinux.org/alpine/edge/community", "add", "aws-cli"]

RUN ["install", "-d", "/etc/nginx/ssl"]
RUN ["openssl", "dhparam", "-out", "/etc/nginx/ssl/dhparam.pem", "2048"]

# forward request and error logs to docker log collector
RUN ["ln", "-sf", "/dev/stdout", "/var/log/nginx/access.log"]
RUN ["ln", "-sf", "/dev/stderr", "/var/log/nginx/error.log"]

RUN ["install", "-o", "nginx", "-g", "nginx", "-d", \
     "/etc/keys", "/etc/nginx/conf/locations", "/etc/nginx/conf/naxsi/locations", "/etc/nginx/naxsi"]
ADD ./naxsi/location.rules /etc/nginx/naxsi/location.template
ADD ./nginx.conf /etc/nginx
ADD ./nginx_rate_limits_null.conf /etc/nginx/conf/
RUN md5sum /etc/nginx/nginx.conf | cut -d' ' -f 1 > /container_default_ngx
ADD ./defaults.sh /
ADD ./go.sh /
ADD ./enable_location.sh /
ADD ./html/ /etc/nginx/html/

RUN ["chown", "-R", "nginx:nginx", "/etc/nginx/conf"]

EXPOSE 10080 10443

CMD [ "/go.sh" ]
