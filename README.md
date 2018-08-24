# OpenResty Docker Container

[![Build Status](https://travis-ci.org/UKHomeOffice/docker-nginx-proxy.svg?branch=master)](https://travis-ci.org/UKHomeOffice/docker-nginx-proxy)

This container aims to be a generic proxy layer for your web services. It includes OpenResty with
Lua and NAXSI filtering compiled in.

## Getting Started

In this section I'll show you some examples of how you might run this container with docker.

### Prerequisites

In order to run this container you'll need docker installed.

* [Windows](https://docs.docker.com/windows/started)
* [OS X](https://docs.docker.com/mac/started/)
* [Linux](https://docs.docker.com/linux/started/)

## Usage

### Environment Variables

#### Multi-location Variables

Variables to control how to configure the proxy (can be set per location, see
[Using Multiple Locations](#using-multiple-locations)).

* `PROXY_SERVICE_HOST` - The upstream host you want this service to proxy.
* `PROXY_SERVICE_PORT` - The port of the upstream host you want this service to proxy.
* `NAXSI_RULES_URL_CSV` - A CSV of [Naxsi](https://github.com/nbs-system/naxsi) URL's of files to download and use.
(Files must end in .rules to be loaded)
* `NAXSI_RULES_MD5_CSV` - A CSV of md5 hashes for the files specified above
* `EXTRA_NAXSI_RULES` - Allows NAXSI rules to be specified as an environment variable. This allows one or two extra
rules to be specified without downloading or mounting in a rule file.
* `NAXSI_USE_DEFAULT_RULES` - If set to "FALSE" will delete the default rules file.
* `ENABLE_UUID_PARAM` - By default, a unique request ID will be generated and added to all requests as a query parameter to aid in tracing requests.
 If set to `HEADER` it will add a HTTP header to all requests instead. The name of the parameter or header is taken from `UUID_VAR_NAME`.
 Set to `FALSE` to disable this behaviour.
* `UUID_VAR_NAME` - The name of the query parameter or header (see `ENABLE_UUID_PARAM`) to use for the unique request ID. Defaults to `nginxId`.
* `CLIENT_CERT_REQUIRED` - if set to `TRUE`, will deny access at this location, see [Client Certs](#client-certs).
* `VERIFY_SERVER_CERT` - if set to `TRUE`, will verify the upstream server's TLS certificate is valid and signed by the CA, see [Verifying Upstream Server](#verifying-upstream-server).
* `USE_UPSTREAM_CLIENT_CERT` - if set to `TRUE`, will use the set of upstream client certs when connecting upstream, see [Upstream Client Certs](#upstream-client-certs).
* `ERROR_REDIRECT_CODES` - Can override when Nginx will redirect requests to its own error page. Defaults to
"`500 501 502 503 504`". To support a new code, say `505`, an error page must be provided at
`/usr/local/openresty/nginx/html/505.shtml`, see [Useful File Locations](#useful-file-locations). Set to `FALSE` to disable all error pages.
* `ADD_NGINX_LOCATION_CFG` - Arbitrary extra NGINX configuration to be added to the location context, see
[Arbitrary Config](#arbitrary-config).
* `PORT_IN_HOST_HEADER` - If FALSE will remove the port from the http `Host` header.
* `BASIC_AUTH` - Define a path for username and password file (in `username:password` format), this will turn the file into a .htpasswd file.
* `REQS_PER_MIN_PER_IP` - Will limit requests based on IP e.g. set to 60 to allow one request per second.
* `CONCURRENT_CONNS_PER_IP` - Will limit concurrent connections based on IP e.g. set to 10 to allow max of 10 connections per browser or proxy!
* `REQS_PER_PAGE` - Will limit requests to 'bursts' of x requests at a time before terminating (will default to 20)
* `DENY_COUNTRY_ON` - Set to `TRUE` to deny access to countries not listed in ALLOW_COUNTRY_CSV with 403 status for a location (set location for 403 with ADD_NGINX_LOCATION_CFG).
* `VERBOSE_ERROR_PAGES` - Set to TRUE to display debug info in 418 error pages.

#### Single set Variables

Note the following variables can only be set once:

* `ADD_NGINX_SERVER_CFG` - Arbitrary extra NGINX configuration to be added to the server context, see
[Arbitrary Config](#arbitrary-config)
* `ADD_NGINX_HTTP_CFG` - Arbitrary extra NGINX configuration to be added to the http context, see
[Arbitrary Config](#arbitrary-config)
* `LOCATIONS_CSV` - Set to a list of locations that are to be independently proxied, see the example
[Using Multiple Locations](#using-multiple-locations). Note, if this isn't set, `/` will be used as the default
location.
* `LOAD_BALANCER_CIDR` - Set to preserve client IP addresses. *Important*, to enable, see
[Preserve Client IP](#preserve-client-ip).
* `NAME_RESOLVER` - Can override the *default* DNS server used to re-resolve the backend proxy (based on TTL).
The *Default DNS Server* is the first entry in the resolve.conf file in the container and is normally correct and
managed by Docker or Kubernetes.
* `CLIENT_MAX_BODY_SIZE` - Can set a larger upload than Nginx defaults in MB.
* `HTTPS_REDIRECT_PORT` - Only required for http to https redirect and only when a non-standard https port is in use.
This is useful when testing or for development instances or when a load-balancer mandates a non-standard port.
* `LOG_FORMAT_NAME` - Can be set to `text` or `json` (default).
* `NO_LOGGING_URL_PARAMS` - Can be set to `TRUE` if you don't want to log url params. Default is empty which means URL params are logged
* `NO_LOGGING_BODY` - Defaults to true `TRUE`.  Set otherwise and nginx should log the request_body.
* `NO_LOGGING_RESPONSE` - Defaults to true `TRUE`.  Set otherwise and nginx should log the response_body
* `SERVER_CERT` - Can override where to find the server's SSL cert.
* `SERVER_KEY` - Can override where to find the server's SSL key.
* `SSL_CIPHERS` - Change the SSL ciphers support default only AES256+EECDH:AES256+EDH:!aNULL
* `SSL_PROTOCOLS` - Change the SSL protocols supported default only TLSv1.2
* `HTTP_LISTEN_PORT` - Change the default inside the container from 10080.
* `HTTPS_LISTEN_PORT` - Change the default inside the container from 10443.
* `INTERNAL_LISTEN_PORT` - Change the default inside the container from 10418. Note: This is used for internal processing and is not available externally.
* `HTTPS_REDIRECT` - Toggle whether or not we force redirects to HTTPS.  Defaults to true.
* `ALLOW_COUNTRY_CSV` - List of [country codes](http://dev.maxmind.com/geoip/legacy/codes/iso3166/) to allow.
* `STATSD_METRICS_ENABLED` - Toggle if metrics are logged to statsd (defaults to true)
* `STATSD_SERVER` - Server to send statsd metrics to, defaults to 127.0.0.1
* `DISABLE_SYSDIG_METRICS` - Set to any non-empty string to disable support for Sysdig's metric collection

### Ports

This container exposes

* `10080` - HTTP
* `10443` - HTTPS

N.B. see HTTP(S)_LISTEN_PORT above

### Useful File Locations

* `nginx.conf` is stored at `/usr/local/openresty/nginx/conf/nginx.conf`
* `/etc/keys/crt` & `/etc/keys/key` - A certificate can be mounted here to make OpenResty use it. However a self
  signed one is provided if they have not been mounted.
* `/etc/keys/client-ca` If a client CA is mounted here, it will be loaded and configured.
See `CLIENT_CERT_REQUIRED` above in [Environment Variables](#environment-variables).
* `/etc/keys/upstream-server-ca` A CA public cert must be mounted here when verifying the upstream server's certificate is required.
See `VERIFY_SERVER_CERT` above in [Environment Variables](#environment-variables).
* `/etc/keys/upstream-client-crt` A public client cert must be mounted here when when the upstream server requires client cert authentication.
See `USE_UPSTREAM_CLIENT_CERT` above in [Environment Variables](#environment-variables).
* `/etc/keys/upstream-client-key` A private client key must be mounted here when when the upstream server requires client cert authentication.
See `USE_UPSTREAM_CLIENT_CERT` above in [Environment Variables](#environment-variables).
* `/usr/local/openresty/naxsi/*.conf` - [Naxsi](https://github.com/nbs-system/naxsi) rules location in default
nginx.conf.
* `/usr/local/openresty/nginx/html/$CODE.shtml` - HTML (with SSI support) displayed when a the status code $CODE
is encountered upstream and the proxy is configured to intercept. See ERROR_REDIRECT_CODES to change this.
* `/usr/local/openresty/nginx/html/418-request-denied.shtml` - HTML (with SSI support) displayed when NAXSI
blocks a request.

### Examples

#### Self signed SSL Certificate

```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

#### Custom SSL Certificate

```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -p 8443:443 \
           -v /path/to/key:/etc/keys/key:ro \
           -v /path/to/crt:/etc/keys/crt:ro \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

#### Preserve Client IP

This proxy supports [Proxy Protocol](http://www.haproxy.org/download/1.5/doc/proxy-protocol.txt).

To use this feature you will need:

* To enable [proxy protocol](http://www.haproxy.org/download/1.5/doc/proxy-protocol.txt) on your load balancer.
  For AWS, see [Enabling Proxy Protocol for AWS](http://docs.aws.amazon.com/ElasticLoadBalancing/latest/DeveloperGuide/enable-proxy-protocol.html).
* Find the private address range of your load balancer.
  For AWS, this could be any address in the destination network. E.g.
  if you have three compute subnets defined as 10.50.0.0/24, 10.50.1.0/24 and 10.50.2.0/24,
  then a suitable range would be 10.50.0.0/22 see [CIDR Calculator](http://www.subnet-calculator.com/cidr.php).

```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'LOAD_BALANCER_CIDR=10.50.0.0/22' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

#### Extra NAXSI Rules from Environment

The example below allows large documents to be POSTED to the /documents/uploads and /documents/other_uploads locations.
See [Whitelist NAXSI rules](https://github.com/nbs-system/naxsi/wiki/whitelists) for more examples.

```shell
docker run -e 'PROXY_SERVICE_HOST=http://myapp.svc.cluster.local' \
           -e 'PROXY_SERVICE_PORT=8080' \
           -e 'EXTRA_NAXSI_RULES=BasicRule wl:2 "mz:$URL:/documents/uploads|BODY";
               BasicRule wl:2 "mz:$URL:/documents/other_uploads|BODY";' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

#### Using Multiple Locations

When the LOCATIONS_CSV option is set, multiple locations can be proxied. The settings for each proxy location can be
controlled with the use of any [Multi-location Variables](#multi-location-variables) by suffixing the variable name with
 both a number, and the '_' character, as listed in the LOCATIONS_CSV variable.

##### Two servers

The example below configures a simple proxy with two locations '/' (location 1) and '/api' (location 2):

```shell
docker run -e 'PROXY_SERVICE_HOST_1=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT_1=80' \
           -e 'PROXY_SERVICE_HOST_2=https://api.svc.cluster.local' \
           -e 'PROXY_SERVICE_PORT_2=8888' \
           -e 'LOCATIONS_CSV=/,/api' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

For more detail, see the [generated config](./docs/GeneratedConfigs.md#two-separate-proxied-servers).

##### One Server, Multiple locations

The example below will proxy the same address for two locations but will disable the UUID (nginxId) parameter for the
/about location only.

See the [generated config](./docs/GeneratedConfigs.md#same-server-proxied) for below:

```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'LOCATIONS_CSV=/,/about' \
           -e 'ENABLE_UUID_PARAM_2=FALSE' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

#### Client Certs

If a client CA certificate is mounted, the proxy will be configured to load it. If a client has the cert, the client CN
will be set in the X-Username header and logged.
```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -v "${PWD}/client_certs/ca.crt:/etc/keys/client-ca" \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

The following example will specifically deny access to clients without a cert:

```shell
docker run -e 'PROXY_SERVICE_HOST=http://serverfault.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'LOCATIONS_CSV=/,/about' \
           -e 'CLIENT_CERT_REQUIRED_2=TRUE' \
           -v "${PWD}/client_certs/ca.crt:/etc/keys/client-ca" \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```
See [./client_certs](./client_certs) for scripts that can be used to generate a CA and client certs.

#### Upstream Client Certs

If the environment variable `USE_UPSTREAM_CLIENT_CERT` is set to `TRUE`
then the client certs at `/etc/keys/upstream-client-crt` and
`/etc/keys/upstream-client-key` will be used to authenticate with the
upstream HTTPS service.

```shell
docker run -e 'PROXY_SERVICE_HOST=https://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=443' \
           -e 'USE_UPSTREAM_CLIENT_CERT=TRUE' \
           -v "/path/to/client-public.crt:/etc/keys/upstream-client-crt" \
           -v "/path/to/client-private.key:/etc/keys/upstream-client-key" \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v2.1.0
```

#### Verifying Upstream Server

If the environment variable `VERIFY_SERVER_CERT` is set to `TRUE` then
the upstream server's certificate will be validated against the CA
public cert at `/etc/keys/upstream-server-ca`.

```shell
docker run -e 'PROXY_SERVICE_HOST=https://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=443' \
           -e 'VERIFY_SERVER_CERT=TRUE' \
           -v "/path/to/ca.crt:/etc/keys/upstream-server-ca" \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v2.1.0
```

#### Arbitrary Config

The example below will return "ping ok" for the URL /ping.
```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'ADD_NGINX_LOCATION_CFG=if ($uri = /proxy-ping) return 200 "ping ok";' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

The example below will return "404" for the URL /notfound.
```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'ADD_NGINX_SERVER_CFG=location /notfound { return 404; };' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

The example below enables proxy_cache_path directive.  Allows you to define where cached files are stored.
```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'ADD_NGINX_HTTP_CFG=proxy_cache_path /data/nginx/cache levels=1:2 keys_zone=static:10m;' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

#### Basic Auth

To add basic auth to your server you need to define the username and password by mounting a file and defining that file in the `BASIC_AUTH` variable, then add the location config to you config.

```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'ADD_NGINX_LOCATION_CFG='auth_basic "Restricted"; auth_basic_user_file /etc/secrets/.htpasswd;' \
           -e BASIC_AUTH='/etc/secrets/basic-auth'
           -p 8443:443 \
           -v ~/Documents:/etc/secrets/
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

The basic auth file will look like this.
```shell
admin:testing
username:password
```
##### Basic Auth on mutliple Locations

If you're using multiple locations then we need to define the location that basic_auth will be set in relation to the `LOCATIONS_CSV`

```shell
docker run -e 'PROXY_SERVICE_HOST=http://serverfault.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'LOCATIONS_CSV=/,/about' \
           -e 'CLIENT_CERT_REQUIRED_2=TRUE' \
           -e BASIC_AUTH_2=/etc/secrets/basic-auth \
           -v "${PWD}/client_certs/ca.crt:/etc/keys/client-ca" \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

this will setup basic-auth for the the `/about` location or simply swap the 2 for a 1 to setup basic auth for the root location.



## Built With

* [OpenResty](https://openresty.org/) - OpenResty (aka. ngx_openresty) is a full-fledged web
  application server by bundling the standard Nginx core, lots of 3rd-party Nginx modules, as well
  as most of their external dependencies.
* [Nginx](https://www.nginx.com/resources/wiki/) - The proxy server core software.
* [ngx_lua](http://wiki.nginx.org/HttpLuaModule) - Embed the power of Lua into Nginx
* [Naxsi](https://github.com/nbs-system/naxsi) - NAXSI is an open-source, high performance, low
  rules maintenance WAF for NGINX
* [GeoLite data](http://www.maxmind.com">http://www.maxmind.com) This product includes GeoLite data created by MaxMind.

## Find Us

* [GitHub](https://github.com/UKHomeOffice/docker-nginx-proxy)
* [Quay.io](https://quay.io/repository/ukhomeofficedigital/nginx-proxy)

## Contributing

Feel free to submit pull requests and issues. If it's a particularly large PR, you may wish to
discuss it in an issue first.

Please note that this project is released with a [Contributor Code of Conduct](code_of_conduct.md).
By participating in this project you agree to abide by its terms.

## Versioning

We use [SemVer](http://semver.org/) for the version tags available See the tags on this repository.

## Authors

* **Lewis Marshal** - *Initial work* - [lewismarshall](https://github.com/lewismarshall)

See also the list of
[contributors](https://github.com/UKHomeOffice/docker-nginx-proxy/graphs/contributors) who
participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
