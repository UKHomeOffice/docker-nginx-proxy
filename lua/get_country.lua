-- Compatibility: Lua-5.1
function split(str, pat)
    local t = {}  -- NOTE: use {n = 0} in Lua-5.0
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(t,cap)
        end
        last_end = e+1
        s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
        cap = str:sub(last_end)
        table.insert(t, cap)
    end
    return t
end

geoip = require("geoip")
g = geoip.open_type("country")
g = geoip.open("/usr/share/GeoIP/GeoLiteCountry.dat")

-- Lookup country code:
r = g:lookup(ngx.arg[1])

-- Work out if country is allowed:
local allow_country_csv = os.getenv("ALLOW_COUNTRY_CSV")
if not allow_country_csv == "" then
    ngx.var.allowed_country = "no"
    for country in split(allow_country_csv, ",") do
        if country == r.country_code then
            ngx.var.allowed_country = "yes"
            break
        end
    end
end

return r.country_code