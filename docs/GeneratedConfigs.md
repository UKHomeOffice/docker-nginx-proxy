## Example Generated Configurations:

### Multiple locations

#### Two separate proxied servers

The command below will proxy two separate web servers at separate addresses:

```
docker run -e 'LOCATIONS_CSV=/,/api' \ 
           -e 'PROXY_SERVICE_HOST_1=myapp.svc.cluster.local' \
           -e 'PROXY_SERVICE_PORT_1=8080' \
           -e 'PROXY_SERVICE_HOST_2=myapi.svc.cluster.local' \
           -e 'PROXY_SERVICE_PORT_2=8888' \
           -d \ 
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0
```

The configurations below are generated:

```
location / {
    set $args $args$uuidopt;


    set $proxy_address "myapp.svc.cluster.local:8080";

    include  /usr/local/openresty/naxsi/locations/1/*.rules ;


    set $backend_upstream "http://$proxy_address";
    proxy_pass $backend_upstream;
    proxy_redirect  off;
    proxy_intercept_errors on;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host $host:$server_port;
    proxy_set_header X-Username "";
}
location /news {
    set $args $args$uuidopt;


    set $proxy_address "myapi.svc.cluster.local:8888";

    include  /usr/local/openresty/naxsi/locations/2/*.rules ;


    set $backend_upstream "http://$proxy_address";
    proxy_pass $backend_upstream;
    proxy_redirect  off;
    proxy_intercept_errors on;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host $host:$server_port;
    proxy_set_header X-Username "";
}
```

#### Same server proxied

Given the command below to proxy one web server and the two locations:

```
docker run --rm=true -it -p 8443:443 \
           -e 'LOCATIONS_CSV=/,/news' \
           -e 'PROXY_SERVICE_HOST=www.bbc.co.uk' \
           -e 'PROXY_SERVICE_PORT=80' \
           -e 'ENABLE_UUID_PARAM_2=FALSE' \
           -e 'PORT_IN_HOST_HEADER_1=FALSE' \
           quay.io/ukhomeofficedigital/nginx-proxy:v1.0.0`
```

The configuration below is generated for `/`. Note specifically the `PORT_IN_HOST_HEADER_1` option above and that the 
port is missing from the line `proxy_set_header Host $host;` in the configuration below.

```
cat /usr/local/openresty/nginx/conf/locations/1.conf
location / {
    set $args $args$uuidopt;


    set $proxy_address "www.bbc.co.uk:80";

    include  /usr/local/openresty/naxsi/locations/1/*.rules ;


    set $backend_upstream "http://$proxy_address";
    proxy_pass $backend_upstream;
    proxy_redirect  off;
    proxy_intercept_errors on;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host $host;
    proxy_set_header X-Username "";
}
```

The configuration below is generated for `/news`. Note specifically the options `ENABLE_UUID_PARAM_2=FALSE` and setting 
missing from below: `set $args $args$uuidopt;` but present above.
```
cat /usr/local/openresty/nginx/conf/locations/2.conf
location /news {



    set $proxy_address "www.bbc.co.uk:80";

    include  /usr/local/openresty/naxsi/locations/2/*.rules ;


    set $backend_upstream "http://$proxy_address";
    proxy_pass $backend_upstream;
    proxy_redirect  off;
    proxy_intercept_errors on;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host $host:$server_port;
    proxy_set_header X-Username "";
}
```