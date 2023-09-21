#!/bin/sh

docker run -e PNP_DBINFO_DATABASE=localhost \
           -e PNP_DBINFO_USERNAME=dbinfo \
           -e PNP_DBINFO_PASSWORD=raining23 \
           -e PNP_DBINFO_PORT=3306 \
           -e PNP_DBINFO_DATABASE=dbinfo \
           -e PNP_DBINFO_HOST=mysql-dbinfo \
           -e PNP_PERL_LIB=/home/pay1/perl_lib \
           $@ -it pay1:dev bash 
