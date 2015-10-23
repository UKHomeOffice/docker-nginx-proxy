#!/usr/bin/env bash
. ./settings.cfg
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 730 -key ca.key -subj "${DN}/CN=MyApp" -out ca.crt
