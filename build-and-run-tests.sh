#!/bin/sh

ENVIRONMENT="$2"

if [ "$ENVIRONMENT" = "" ]; then
  ENVIRONMENT="dev"
fi

DEVELOPMENT="FALSE"
if [ "$ENVIRONMENT" = "dev" ]; then
  DEVELOPMENT="TRUE"
fi


IMAGE=$1

if [ "$IMAGE" = "" ]; then
  IMAGE="pay1"
fi

if [ `uname | tr "[A-Z]" "[a-z]"` = "darwin" ]; then
  LOCAL_IP=`route -n get default|grep interface|awk '{ print $2 }'| xargs ipconfig getifaddr`
else
  LOCAL_IP=`hostname -I | cut -f1 -d' '`
fi

docker container ls -a | grep '0.0.0.0:8443' | awk '{print $1}' | xargs docker container stop
echo docker image build -t $IMAGE:dev --rm=true -f $IMAGE/Dockerfile .
docker image build -t $IMAGE:dev -f $IMAGE/Dockerfile .
docker run \
  -e DEVELOPMENT=$DEVELOPMENT \
  -e PNP_TOKEN_SERVER=http://10.149.50.174:8080/token/rest/query \
  -e PNP_PROXY_SERVER=http://successlinkdev-dylan/api/proxy \
  -e PNP_COA_SERVER=10.149.50.43 \
  -e PNP_DBINFO_PASSWORD=raining23 \
  -e PNP_DBINFO_HOST=devmysql-test1 \
  -e PNP_DBINFO_USERNAME=dbinfo \
  -e PNP_DBINFO_PORT=3306 \
  -e PNP_DBINFO_DATABASE=dbinfo \
  -e PNP_AUTH_SERVER=http://$LOCAL_IP:5000 \
  -e PNP_CARDDATA_SERVICE=http://$LOCAL_IP:5001 \
  -e PNP_ORDERS_BUCKET='plugnpay-orders' \
  -e PNP_AWS_S3_ACCESS_KEY_ID='AKIAJJLTWBJDVJOEE55Q' \
  -e PNP_AWS_S3_SECRET_ACCESS_KEY='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' \
  -e PNP_AWS_REGION='us-east-1' \
  -e AWS_ACCESS_KEY_ID='AKIAJJLTWBJDVJOEE55Q' \
  -e AWS_SECRET_ACCESS_KEY='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' \
  -e ACH_SETTLEMENT_BUCKET=plugnpay-dev-ach-status-changes \
  -e AWS_REGION='us-east-1' \
  -e PNP_JOB=$PNP_JOB \
  -p 8443:443 \
  --cap-add SYS_PTRACE \
  $IMAGE:dev tests/run-tests.sh

