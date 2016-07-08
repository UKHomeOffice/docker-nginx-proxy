-- get_country.lua
local country = require("country")
local ip = ngx.arg[1]
country_code = country:get_country_code(ip)
allowed_countries = country:get_allowed_countries()

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