geoip = require("geoip")
g = geoip.open_type("country")
g = geoip.open("/usr/share/GeoIP/GeoLiteCountry.dat")
r = g:lookup(ngx.arg[1])
retrun r.country_code