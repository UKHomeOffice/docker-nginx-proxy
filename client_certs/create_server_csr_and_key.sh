#!/usr/bin/env bash
. ./settings.cfg
openssl genrsa -out server.key 4096
openssl req -new -key server.key  -subj "${DN}/CN=standard-tls" -out server.csr
