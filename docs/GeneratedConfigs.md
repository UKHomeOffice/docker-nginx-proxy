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

    include  /etc/nginx/conf/naxsi/locations/1/*.rules ;


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

    include  /etc/nginx/conf/naxsi/locations/2/*.rules ;


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
