if os.getenv("LOG_UUID") == "FALSE" then
    return ""
else
    local uuid_str = ""
    if ngx.req.get_headers()["nginxId"] == nil then
        local uuid = require("uuid")
        local unpack = unpack or table.unpack

        uuid.set_rng(function()
            local random_bytes = require("resty.openssl.rand").bytes(16)
            return random_bytes
        end)

        uuid_str = uuid()
    else
        uuid_str = ngx.req.get_headers()["nginxId"]
    end
    ngx.var.uuid = uuid_str
    ngx.var.uuid_log_opt = " nginxId=" .. uuid_str
    return uuid_str
end
