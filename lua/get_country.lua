#!/usr/bin/env lua

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

local geoip = require "geoip";
local geoip_country = require "geoip.country";
local geoip_file = "/usr/share/GeoIP/GeoIP.dat"
local geoip_country_filename = geoip_file
local geodb = geoip_country.open(geoip_country_filename)

local ip = ngx.arg[1]
local country_id = geodb:query_by_addr(ip, "id")
local country_code = geoip.code_by_id(country_id)

-- Work out if country is allowed:
local allow_country_csv = os.getenv("ALLOW_COUNTRY_CSV")
local allowed_countries = {}
allowed_countries = split(allow_country_csv, ",")
if allow_country_csv == "" then
    ngx.var.allowed_country = "NA"
else
    ngx.var.allowed_country = "no"
    for key,country in pairs(allowed_countries) do
        if country == country_code then
            ngx.var.allowed_country = "yes"
            break
        end
    end
end

return country_code