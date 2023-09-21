#!/bin/sh

FILES=`git diff --name-only | egrep '^pay1_home/(perl_lib|perlpr_lib|web)/' | egrep '\.(pm|cgi)$' | sed -e 's/^pay1_home/\/home\/pay1/'`

echo $FILES | xargs -L 1 -t docker run \
           -e PNP_DBINFO_DATABASE=localhost \
           -e PNP_DBINFO_USERNAME=dbinfo \
           -e PNP_DBINFO_PASSWORD=raining23 \
           -e PNP_DBINFO_PORT=3306 \
           -e PNP_DBINFO_DATABASE=dbinfo \
           -e PNP_DBINFO_HOST=mysql-dbinfo \
           -e PNP_PERL_LIB=/home/pay1/perl_lib \
           $@ pay1:dev perlcritic 

