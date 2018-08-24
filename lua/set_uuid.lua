if os.getenv("LOG_UUID") == "FALSE" then
    return ""
else
    local uuid_str = ""
    local uuid_var_name = os.getenv("UUID_VAR_NAME")
    if ngx.req.get_headers()[uuid_var_name] == nil then
        local socket = require("socket")
        local uuid = require("uuid")
        uuid.randomseed(socket.gettime()*10000)
        uuid_str = uuid()
    else
        uuid_str = ngx.req.get_headers()[uuid_var_name]
    end
    ngx.var.uuid = uuid_str
    ngx.var.uuid_log_opt = " " .. uuid_var_name .. "=" .. uuid_str
    return uuid_str
end
