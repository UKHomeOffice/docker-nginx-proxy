# OpenResty Docker Container

This container aims to be a generic proxy layer for your web services. It includes OpenResty with 
Lua and NAXSI filtering compiled in.

It will also pass A UUID as an additional query parameter to the URL, using the following schema
`http://$PROXY_SERVICE_HOST:$PROXY_SERVICE_PORT/?nginxId=$uuid`

## Getting Started

In this section I'll show you some examples of how you might run this container with docker.

### Prerequisities

In order to run this container you'll need docker installed.

* [Windows](https://docs.docker.com/windows/started)
* [OS X](https://docs.docker.com/mac/started/)
* [Linux](https://docs.docker.com/linux/started/)

## Usage

### Enviroment Variables

* `PROXY_SERVICE_HOST` - The upstream host you want this service to proxy
* `PROXY_SERVICE_PORT` - The port of the upstream host you want this service to proxy
* `NAXSI_RULES_URL_CSV` - A CSV of [Naxsi](https://github.com/nbs-system/naxsi) URL's of files to download and use. (Files must end in .conf to be loaded)
* `NAXSI_RULES_MD5_CSV` - A CSV of md5 hashes for the files specified above
* `NAXSI_USE_DEFAULT_RULES` - If set to "FALSE" will delete the default rules file...

### Ports

This container exposes

* `80` - HTTP
* `443` - HTTPS

### Useful File Locations

* `nginx.conf` is stored at `/usr/local/openresty/nginx/conf/nginx.conf`
* `/etc/keys/crt` & `/etc/keys/key` - A certificate can be mounted here to make OpenResty use it. However a self 
  signed one is provided if they have not been mounted.
* `/usr/local/openresty/naxsi/*.conf` - [Naxsi](https://github.com/nbs-system/naxsi) rules location in default nginx.conf.
  
### Examples

#### Self signed SSL Certificate

```shell
docker run -e 'PROXY_SERVICE_HOST=upstream' \
           -e 'PROXY_SERVICE_PORT=8080' \
           -d \ 
           quay.io/ukhomeofficedigital/ngx-openresty:v0.1.1
```

#### Custom SSL Certificate


```shell
docker run -e 'PROXY_SERVICE_HOST=upstream' \
           -e 'PROXY_SERVICE_PORT=8080' \
           -v /path/to/key:/etc/keys/key:ro \
           -v /path/to/crt:/etc/keys/crt:ro \
           -d \ 
           quay.io/ukhomeofficedigital/ngx-openresty:v0.1.1
```

## Built With

* [OpenResty](https://openresty.org/) - OpenResty (aka. ngx_openresty) is a full-fledged web 
  application server by bundling the standard Nginx core, lots of 3rd-party Nginx modules, as well 
  as most of their external dependencies.
* [ngx_lua](http://wiki.nginx.org/HttpLuaModule) - Embed the power of Lua into Nginx
* [Naxsi](https://github.com/nbs-system/naxsi) - NAXSI is an open-source, high performance, low 
  rules maintenance WAF for NGINX 

## Find Us

* [GitHub](https://github.com/UKHomeOffice/docker-ngx-openresty)
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
[contributors](https://github.com/UKHomeOffice/docker-ngx-openresty/graphs/contributors) who 
participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
