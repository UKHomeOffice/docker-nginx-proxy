# docker-ngx-openresty
A generic WAF proxy layer

Includes LUA and NAXI filtering.

By default will proxy the addresses from the environment variables below:
PROXY_SERVICE_HOST
PROXY_SERVICE_PORT

Will also set a UUID param e.g.: http://$PROXY_SERVICE_HOST:$PROXY_SERVICE_PORT/?nginxId=$uuid; 