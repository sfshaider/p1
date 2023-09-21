#!/bin/bash

if [ ! "$DEBUG" = "" ]; then
    echo SetEnv DEBUG $DEBUG >> /etc/httpd/conf/env.conf
    echo PerlSetEnv DEBUG $DEBUG >> /etc/httpd/conf/env.conf
fi

if [ ! "$DEVELOPMENT" = "" ]; then
    echo SetEnv DEVELOPMENT $DEVELOPMENT >> /etc/httpd/conf/env.conf
    echo PerlSetEnv DEVELOPMENT $DEVELOPMENT >> /etc/httpd/conf/env.conf
fi

if [ ! "$CAPTCHA_BYPASS" = "" ]; then
    echo SetEnv CAPTCHA_BYPASS $CAPTCHA_BYPASS >> /etc/httpd/conf/env.conf
    echo PerlSetEnv CAPTCHA_BYPASS $CAPTCHA_BYPASS >> /etc/httpd/conf/env.conf
fi

if [ ! "$DEBUG_MICROSERVICE_DURATION" = "" ]; then
    echo SetEnv DEBUG_MICROSERVICE_DURATION $DEBUG_MICROSERVICE_DURATION >> /etc/httpd/conf/env.conf
    echo PerlSetEnv DEBUG_MICROSERVICE_DURATION $DEBUG_MICROSERVICE_DURATION >> /etc/httpd/conf/env.conf
fi

if [ ! "$DEBUG_RESPONSELINK_DURATION" = "" ]; then
    echo SetEnv DEBUG_RESPONSELINK_DURATION $DEBUG_RESPONSELINK_DURATION >> /etc/httpd/conf/env.conf
    echo PerlSetEnv DEBUG_RESPONSELINK_DURATION $DEBUG_RESPONSELINK_DURATION >> /etc/httpd/conf/env.conf
fi

if [ ! "$DEBUG_DB_PREPARE" = "" ]; then
    echo SetEnv DEBUG_DB_PREPARE $DEBUG_DB_PREPARE >> /etc/httpd/conf/env.conf
    echo PerlSetEnv DEBUG_DB_PREPARE $DEBUG_DB_PREPARE >> /etc/httpd/conf/env.conf
fi


PNP_ENVS=`env | sed -e 's/=.*//' | grep '^PNP_' | xargs echo`

for PNP_ENV in $PNP_ENVS; do
  VALUE=$(eval echo "\$$PNP_ENV")
  if [ ! "$VALUE" = "" ]; then
    echo SetEnv $PNP_ENV $VALUE >> /etc/httpd/conf/env.conf
    echo PerlSetEnv $PNP_ENV $VALUE >> /etc/httpd/conf/env.conf
  fi
done

AWS_ENVS=`env | sed -e 's/=.*//' | grep '^AWS_' | xargs echo`

for AWS_ENV in $AWS_ENVS; do
  VALUE=$(eval echo "\$$AWS_ENV")
  if [ ! "$VALUE" = "" ]; then
    echo SetEnv $AWS_ENV $VALUE >> /etc/httpd/conf/env.conf
    echo PerlSetEnv $AWS_ENV $VALUE >> /etc/httpd/conf/env.conf
  fi
done
