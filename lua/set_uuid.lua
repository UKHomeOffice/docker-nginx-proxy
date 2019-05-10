if os.getenv("LOG_UUID") == "FALSE" then
    return ""
else
    local uuid_str = ""
    if ngx.req.get_headers()["nginxId"] == nil then
        local socket = require("socket")
        local uuid = require("uuid")
        uuid.randomseed(socket.gettime()*10000)
        uuid_str = uuid()
    else
	uuid_str = ngx.req.get_headers()["nginxId"]
    end
    ngx.var.uuid = uuid_str
    ngx.var.uuid_log_opt = " nginxId=" .. uuid_str
    return uuid_str
end
