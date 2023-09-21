#!/bin/env bash

# start loggy
echo [start.sh] Starting Loggy server...
/home/pay1/bin/loggy -daemon

# /home/pay1/httpd-bin/gencert-answers.sh | /home/pay1/httpd-bin/gencert.sh
/home/pay1/httpd-bin/set-httpd-env.sh
mkdir -p /home/pay1/etc/ssl/
/home/pay1/bin/pluggy -getcert
chmod -R go-rw /home/pay1/etc/ssl

# start responselink proxy
echo [start.sh] Starting Responselink Proxy...
/home/pay1/bin/responselink -logbase /home/pay1/log/loggy

echo [start.sh] Starting Memcached...
memcached -u root -m 1024 -d

echo [start.sh] Starting httpd...
httpd -d /etc/httpd -f conf/httpd.conf

/home/pay1/bin/loggy -reader
sleep 500
