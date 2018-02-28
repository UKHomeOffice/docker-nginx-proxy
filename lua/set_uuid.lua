if os.getenv("LOG_UUID") == "FALSE" then
    return ""
else
    local socket = require("socket")
    local uuid = require("uuid")
    uuid.randomseed(socket.gettime()*10000)
    local uuid_str = uuid()
    ngx.var.uuid = uuid_str
    local uuid_var_name = os.getenv("UUID_VAR_NAME")
    ngx.var.uuid_log_opt = " " .. uuid_var_name .. "=" .. uuid_str
    return uuid_str
end
