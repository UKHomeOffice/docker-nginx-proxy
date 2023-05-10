FROM alpine:3.18.0@sha256:02bb6f428431fbc2809c5d1b41eab5a68350194fb508869a33cb1af4444c9b11

USER root

ENTRYPOINT ["tini", "--"]

RUN ["apk", "--no-cache", "upgrade"]
RUN ["apk", "--no-cache", "add", \
  "bash", \
  "curl", \
  "dnsmasq", \
  # If you update these nginx packages you MUST update the software components list: https://pay-team-manual.cloudapps.digital/manual/policies-and-procedures/software-components-list.html
  "nginx-mod-http-naxsi=1.24.0-r3", \
  "nginx-mod-http-xslt-filter=1.24.0-r3", \
  "openssl", \
  "py-pip", \
  "python3", \
  "tini" \
]

RUN ["pip", "install", "awscli~=1.20.0"]

RUN ["install", "-d", "/etc/nginx/ssl"]
RUN ["openssl", "dhparam", "-out", "/etc/nginx/ssl/dhparam.pem", "2048"]

# forward request and error logs to docker log collector
RUN ["ln", "-sf", "/dev/stdout", "/var/log/nginx/access.log"]
RUN ["ln", "-sf", "/dev/stderr", "/var/log/nginx/error.log"]

RUN ["install", "-o", "nginx", "-g", "nginx", "-d", \
     "/etc/keys", "/etc/nginx/conf/locations", "/etc/nginx/conf/naxsi/locations", "/etc/nginx/naxsi"]
ADD ./naxsi/location.rules /etc/nginx/naxsi/location.template
ADD ./nginx.conf /etc/nginx

ADD ./nginx_big_buffers.conf /etc/nginx/conf/
ADD ./nginx_rate_limits_null.conf /etc/nginx/conf/
ADD ./nginx_cache_http.conf /etc/nginx/conf/
RUN md5sum /etc/nginx/nginx.conf | cut -d' ' -f 1 > /container_default_ngx
ADD ./defaults.sh /
ADD ./go.sh /
ADD ./enable_location.sh /
ADD ./html/ /etc/nginx/html/

RUN ["chown", "-R", "nginx:nginx", "/etc/nginx/conf"]

EXPOSE 10080 10443

CMD [ "/go.sh" ]
