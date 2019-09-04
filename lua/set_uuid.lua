if os.getenv("LOG_UUID") == "FALSE" then
    return ""
else
    local socket = require("socket")
    local uuid = require("uuid")
    uuid.randomseed(socket.gettime()*10000)
    local uuid_str = uuid()
    ngx.var.uuid = uuid_str
    ngx.var.uuid_log_opt = " X-Request-Id=" .. uuid_str
    return uuid_str
end
