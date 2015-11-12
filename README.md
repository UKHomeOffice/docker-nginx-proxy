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
* `ENABLE_UUID_PARAM` - If set to "FALSE", will NOT add a UUID url parameter to all requests. The Default will add this
 for easy tracking in down stream logs e.g. `nginxId=50c91049-667f-4286-c2f0-86b04b27d3f0`.
* `CLIENT_CERT_REQUIRED` - if set to `TRUE`, will deny access at this location, see [Client Certs](#client-certs).
* `ERROR_REDIRECT_CODES` - Can override when Nginx will redirect requests to the error page. Defaults to 
"`500 501 502 503 504`"

#### Single set Variables

Note the following variables can only be set once:

* `LOCATIONS_CSV` - Set to a list of locations that are to be independently proxied, see the example 
[Using Multiple Locations](#using-multiple-locations). Note, if this isn't set, `/` will be used as the default 
location.
* `LOAD_BALANCER_CIDR` - Set to preserve client IP addresses. *Important*, to enable, see 
[Preserve Client IP](#preserve-client-ip).
* `NAME_RESOLVER` - Can override the *default* DNS server used to re-resolve the backend proxy (based on TTL). 
The *Default DNS Server* is the first entry in the resolve.conf file in the container and is normally correct and 
managed by Docker or Kubernetes.  
* `CLIENT_MAX_BODY_SIZE` - Can set a larger upload than Nginx defaults in MB.
* `HTTPS_PORT` - Only required for http to https redirect and only a non-standard https port is in use. This is useful
 when testing or for development instances.
* `LOG_FORMAT_NAME` - Can be set to `text` or `json` (default).

### Ports

This container exposes

* `80` - HTTP
* `443` - HTTPS

### Useful File Locations

* `nginx.conf` is stored at `/usr/local/openresty/nginx/conf/nginx.conf`
* `/etc/keys/crt` & `/etc/keys/key` - A certificate can be mounted here to make OpenResty use it. However a self 
  signed one is provided if they have not been mounted.
* `/etc/keys/client-ca` If a client CA is mounted here, it will be loaded and configured. 
See `CLIENT_CERT_REQUIRED` above in [Environment Variables](#environment-variables).
* `/usr/local/openresty/naxsi/*.conf` - [Naxsi](https://github.com/nbs-system/naxsi) rules location in default 
nginx.conf.
* `/usr/local/openresty/nginx/html/50x.html` - HTML displayed when a 500 error occurs. See ERROR_REDIRECT_CODES to 
change this.
  
### Examples

#### Self signed SSL Certificate

```shell
docker run -e 'PROXY_SERVICE_HOST=stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/ngx-openresty:v0.5.2
```

#### Custom SSL Certificate

```shell
docker run -e 'PROXY_SERVICE_HOST=stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -p 8443:443 \
           -v /path/to/key:/etc/keys/key:ro \
           -v /path/to/crt:/etc/keys/crt:ro \
           quay.io/ukhomeofficedigital/ngx-openresty:v0.5.2
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
docker run -e 'PROXY_SERVICE_HOST=stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'LOAD_BALANCER_CIDR=10.50.0.0/22' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/ngx-openresty:v0.5.2
```

#### Extra NAXSI Rules from Environment

The example below allows large documents to be POSTED to the /documents/uploads and /documents/other_uploads locations.
See [Whitelist NAXSI rules](https://github.com/nbs-system/naxsi/wiki/whitelists) for more examples.

```shell
docker run -e 'PROXY_SERVICE_HOST=myapp.svc.cluster.local' \
           -e 'PROXY_SERVICE_PORT=8080' \
           -e 'EXTRA_NAXSI_RULES=BasicRule wl:2 "mz:$URL:/documents/uploads|BODY";
               BasicRule wl:2 "mz:$URL:/documents/other_uploads|BODY";' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/ngx-openresty:v0.5.2
```

#### Using Multiple Locations

When the LOCATIONS_CSV option is set, multiple locations can be proxied. The settings for each proxy location can be 
controlled with the use of any [Multi-location Variables](#multi-location-variables) by suffixing the variable name with
 both a number, and the '_' character, as listed in the LOCATIONS_CSV variable. 
 
##### Two servers 

The example below configures a simple proxy with two locations '/' (location 1) and '/api' (location 2):

```shell
docker run -e 'PROXY_SERVICE_HOST_1=stackexchange.com' \
           -e 'PROXY_SERVICE_PORT_1=80' \
           -e 'PROXY_SERVICE_HOST_2=api.svc.cluster.local' \
           -e 'PROXY_SERVICE_PORT_2=8888' \
           -e 'LOCATIONS_CSV=/,/api' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/ngx-openresty:v0.5.2
```           

For more detail, see the [generated config](./docs/GeneratedConfigs.md#two-separate-proxied-servers).

##### One Server, Multiple locations

The example below will proxy the same address for two locations but will disable the UUID (nginxId) parameter for the
/about location only.

See the [generated config](./docs/GeneratedConfigs.md#same-server-proxied) for below:

```shell
docker run -e 'PROXY_SERVICE_HOST=stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'LOCATIONS_CSV=/,/about' \
           -e 'ENABLE_UUID_PARAM_2=FALSE' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/ngx-openresty:v0.5.2
```

#### Client Certs

If a client CA certificate is mounted, the proxy will be configured to load it. If a client has the cert, the client CN
will be set in the X-Username header and logged.
```shell
docker run -e 'PROXY_SERVICE_HOST=stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -v "${PWD}/client_certs/ca.crt:/etc/keys/client-ca" \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/ngx-openresty:v0.5.2
```

The following example will specifically deny access to clients without a cert:

```shell
docker run -e 'PROXY_SERVICE_HOST=serverfault.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'LOCATIONS_CSV=/,/about' \
           -e 'CLIENT_CERT_REQUIRED_2=TRUE' \
           -v "${PWD}/client_certs/ca.crt:/etc/keys/client-ca" \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/ngx-openresty:v0.5.2
```

See [./client_certs](./client_certs) for scripts that can be used to generate a CA and client certs.  

## Built With

* [OpenResty](https://openresty.org/) - OpenResty (aka. ngx_openresty) is a full-fledged web 
  application server by bundling the standard Nginx core, lots of 3rd-party Nginx modules, as well 
  as most of their external dependencies.
* [ngx_lua](http://wiki.nginx.org/HttpLuaModule) - Embed the power of Lua into Nginx
* [Naxsi](https://github.com/nbs-system/naxsi) - NAXSI is an open-source, high performance, low 
  rules maintenance WAF for NGINX 

## Find Us

* [GitHub](https://github.com/UKHomeOffice/docker-nginx-proxy)
* [Quay.io](https://quay.io/repository/ukhomeofficedigital/ngx-openresty)

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
