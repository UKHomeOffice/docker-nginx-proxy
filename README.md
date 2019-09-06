# Nginx+Naxsi Docker Container

[![Build Status](https://travis-ci.org/UKHomeOffice/docker-nginx-proxy.svg?branch=master)](https://travis-ci.org/UKHomeOffice/docker-nginx-proxy)

This container aims to be a generic proxy layer for your web services. It includes nginx with
NAXSI filtering compiled in.

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
* `NAXSI_USE_DEFAULT_RULES` - If set to "FALSE" will delete the default rules file.
* `ENABLE_UUID_PARAM` - If set to "FALSE", will NOT add a UUID header to all requests. If set to HEADER will add this
 for easy tracking in down stream logs e.g. `X-Request-Id: 50c91049-667f-4286-c2f0-86b04b27d3f0`.
* `REQS_PER_MIN_PER_IP` - Will limit requests based on IP e.g. set to 60 to allow one request per second.
* `REQS_PER_PAGE` - Will limit requests to 'bursts' of x requests at a time before terminating (will default to 20)

#### Single set Variables

Note the following variables can only be set once:

* `ADD_NGINX_SERVER_CFG` - Arbitrary extra NGINX configuration to be added to the server context, see
[Arbitrary Config](#arbitrary-config)
* `AWS_REGION` - Sets the AWS region this container is running in. Used to construct urls from which to download resources from. Defaults to 'eu-west-1' if not set.
* `LOCATIONS_CSV` - Set to a list of locations that are to be independently proxied, see the example
[Using Multiple Locations](#using-multiple-locations). Note, if this isn't set, `/` will be used as the default
location.
* `CLIENT_MAX_BODY_SIZE` - Can set a larger upload than Nginx defaults in MB.
* `CUSTOM_LOG_FORMAT` - Set this to override the logging format in use.
* `HTTP_LISTEN_PORT` - Change the default inside the container from 10080.
* `HTTPS_LISTEN_PORT` - Change the default inside the container from 10443.
* `ERROR_LOG_LEVEL` - The log level to use for nginx's `error_log` directive (default: 'error')

### Ports

This container exposes

* `10080` - HTTP
* `10443` - HTTPS

N.B. see HTTP(S)_LISTEN_PORT above

### Useful File Locations

* `nginx.conf` is stored at `/etc/nginx/conf/nginx.conf`
* `/etc/keys/crt` & `/etc/keys/key` - A certificate can be mounted here to make nginx use it. However a self
  signed one is provided if they have not been mounted.
* `/etc/nginx/conf/naxsi/*.conf` - [Naxsi](https://github.com/nbs-system/naxsi) rules location in default
nginx.conf.
* `/etc/nginx/html/$CODE.shtml` - HTML (with SSI support) displayed when a the status code $CODE
is encountered upstream and the proxy is configured to intercept.
* `/etc/nginx/html/418-request-denied.shtml` - HTML (with SSI support) displayed when NAXSI
blocks a request.

### Examples

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

The example below will proxy the same address for two locations but will disable the UUID (X-Request-Id) header for the
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

#### Arbitrary Config

The example below will return "404" for the URL /notfound.
```shell
docker run -e 'PROXY_SERVICE_HOST=http://stackexchange.com' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'ADD_NGINX_SERVER_CFG=location /notfound { return 404; };' \
           -p 8443:443 \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

## Built With

* [Nginx](https://www.nginx.com/resources/wiki/) - The proxy server core software.
* [Naxsi](https://github.com/nbs-system/naxsi) - NAXSI is an open-source, high performance, low
  rules maintenance WAF for NGINX

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
