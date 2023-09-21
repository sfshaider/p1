#!/bin/env bash

mkdir -p /etc/httpd/ssl
cd /etc/httpd/ssl

openssl req -newkey rsa:2048 -nodes -keyout backend-key.pem -x509 -days 9999 -out backend-certificate.pem
openssl x509 -text -noout -in backend-certificate.pem
