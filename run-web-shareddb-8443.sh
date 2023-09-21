#!/bin/sh

docker run -e PNP_DBINFO_PASSWORD=raining23 -e PNP_DBINFO_HOST=mysql-dbinfo -e PNP_DBINFO_USERNAME=dbinfo -e PNP_DBINFO_PORT=3306 -e PNP_DBINFO_DATABASE=dbinfo -p 8443:443 $@ pay1:dev
