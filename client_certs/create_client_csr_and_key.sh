#!/usr/bin/env bash
. ./settings.cfg
openssl genrsa -out client.key 4096
openssl req -new -key client.key  -subj "${DN}/CN=Test Client" -out client.csr