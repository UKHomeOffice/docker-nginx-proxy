FROM ngx

USER 0

COPY client_certs/ca.crt /etc/keys/crt
COPY client_certs/ca.key /etc/keys/key
RUN chmod 644 /etc/keys/*

USER 1000

EXPOSE 10081 10444