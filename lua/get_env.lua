if os.getenv(ngx.arg[1]) == "FALSE" then
    return ""
else
    return os.getenv(ngx.arg[1])
end