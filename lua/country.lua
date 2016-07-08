-- country.lua
local country = {}

-- Compatibility: Lua-5.1
function country:split(str, pat)
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

function country:init(from_nginx)
    GeoIP = require "geoip";
    local geoip_country = require "geoip.country";
    local geoip_file = "/usr/share/GeoIP/GeoIP.dat"
    local geoip_country_filename = geoip_file
    GeoDB = geoip_country.open(geoip_country_filename)
    local allow_country_csv = os.getenv("ALLOW_COUNTRY_CSV")
    AllowedCountries = country:split(allow_country_csv, ",")
end

function country:get_country_code(ip)
    -- Work out if country is allowed:
    local country_id = GeoDB:query_by_addr(ip, "id")
    local country_code = GeoIP.code_by_id(country_id)
    return country_code
end

function country:get_allowed_countries()
    return AllowedCountries
end

return country