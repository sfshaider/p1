#!/bin/sh
export AWS_ACCESS_KEY_ID=`grep -A 3 '\[dev-login\]' < ~/.aws/credentials | grep 'aws_access_key_id' | sed -e 's/.*= //'`
export AWS_SECRET_ACCESS_KEY=`grep -A 3 '\[dev-login\]' < ~/.aws/credentials | grep 'aws_secret_access_key' | sed -e 's/.*= //'`

aws ecr get-login-password --region us-east-1 --profile dev-login| docker login --username AWS --password-stdin 301209068216.dkr.ecr.us-east-1.amazonaws.com

SKIPREACT=""
TESTING=""
RUNTESTS=""
DONTSTOP=""
PORT="8443"
OUTPUT="run"
while getopts “i:e:xrtcTo:p:” opt; do
  case "$opt" in
    i) IMAGE=${OPTARG};
      ;;
    e) ENVIRONMENT=${OPTARG};
      ;;
    r) SKIPREACT=1; 
      ;;
    t) TESTING=1;
      ;;
    T) RUNTESTS=1;
      ;;
    o) OUTPUT=${OPTARG};
      ;;
    p) PORT=${OPTARG};
      ;;
    x) DONTSTOP=1;
      ;;
    c) CAPTCHA_BYPASS=TRUE
      ;;
  esac
done

if [ "$RUNTESTS" = 1 ]; then
  TESTING="1"
  SKIPREACT="1"
fi

# inital cleanup
rm -rf bundles/*
find . -name '.DS_Store' -exec rm {} \;

if [ "$IMAGE" = "" ]; then
  echo Specify image with -i flag
  exit;
fi

if [ "$ENVIRONMENT" = "" ]; then
  echo Defaulting to dev environment
  ENVIRONMENT="dev"
fi

DEVELOPMENT="FALSE"
if [ "$ENVIRONMENT" = "dev" ]; then
  DEVELOPMENT="TRUE"
fi


echo Building image [$IMAGE] for environment [$ENVIRONMENT]
if [ "$SKIPREACT" = "1" ]; then
  echo Skipping react build...
fi


##############################
# BEGIN OF BUNDLE GENERATION #
##############################
if [ -d $IMAGE/scripts ]; then
  for s in $IMAGE/scripts/*; do
    echo running $s
    if [ -f $s ]; then
      $s
    fi
  done
fi

# create bundle directory in web_common/_js if it doesn't exist
if [ ! -e pay1_home/web_common/_js/bundle ]; then
  mkdir -p pay1_home/web_common/_js/bundle
fi

cp -r bundles/* pay1_home/web_common/_js/bundle/
############################
# END OF BUNDLE GENERATION #
############################

# run this now in background so later we don't have to wait for it
CONTAINER="$IMAGE-$ENVIRONMENT-$PORT"
TAG="$IMAGE:$ENVIRONMENT"

if [ ! "$DONTSTOP" = "1" ]; then
  echo "Stopping $container"
  docker container stop $CONTAINER && docker container rm $CONTAINER && docker image rmi $TAG
fi

if [ "$SKIPREACT" = "" ]; then
  # fix for building react until projects are updated
  export NODE_OPTIONS=--openssl-legacy-provider
  if [ ! "$IMAGE" = "apiserver" ] && [ ! "$IMAGE" = "batchfiles" ] && [ ! "$IMAGE" = "batchfiles-ec2" ]; then
    for d in  ./react-components/*/; do (echo "Building react app $d..."; cd "$d" && npm install; npm audit fix;npm run "$ENVIRONMENT"); done
  fi
fi

if [ `uname | tr "[A-Z]" "[a-z]"` = "darwin" ]; then
  LOCAL_IP=`route -n get default|grep interface|awk '{ print $2 }'| xargs ipconfig getifaddr`
else
  LOCAL_IP=`hostname -I | cut -f1 -d' '`
fi

# build base
echo docker image build -t pay1-base:latest -f base/Dockerfile .
docker image build -t pay1-base:latest -f base/Dockerfile .

# CERTIFICATE ARN is different for pay1 vs reseller
# THESE ARNs APPLY TO DEV ONLY!!!
if [ $IMAGE = "pay1" ]; then
  export CERTIFICATE_ARN=arn:aws:acm:us-east-1:301209068216:certificate/989faed6-8d07-4892-b098-011e60d000a5
elif [ $IMAGE = "reseller" ]; then
  export CERTIFICATE_ARN=arn:aws:acm:us-east-1:301209068216:certificate/f8bfe800-5650-4677-89b6-3fc382bfcbc3
elif [ $IMAGE = "apiserver" ]; then
  export CERTIFICATE_ARN=arn:aws:acm:us-east-1:301209068216:certificate/ee53914b-41f4-43c0-87ff-c9b745a5bbb8
elif [ $IMAGE = "pay-api" ]; then
  export CERTIFICATE_ARN=arn:aws:acm:us-east-1:301209068216:certificate/a45dce57-f8a1-4359-936c-5554e0f85662 
fi

VOLUMES=""
if [ "$TESTING" != "1" ]; then 
  VOLUMES="-v `pwd`/pay1_home/perl_lib:/home/pay1/perl_lib \
           -v `pwd`/pay1_home/perlpr_lib:/home/pay1/perlpr_lib \
           -v `pwd`/pay1_home/tests:/home/pay1/tests "

  if [ "$IMAGE" = "batchfiles" ]; then
    VOLUMES="$VOLUMES \
             -v `pwd`/pay1_home/batchfiles:/home/pay1/batchfiles "
  else 
    VOLUMES="$VOLUMES \
             -v `pwd`/bundles:/home/pay1/web/bundle "
  fi
fi

PORTBINDING=""
if [ ! "$IMAGE" = "batchfiles" ] && [ ! "$IMAGE" = "batchfiles-ec2" ]; then 
  PORTBINDING="-p $PORT:443 "
fi

# build $IMAGE-$ENVIRONMENT
echo docker image build -t $TAG --rm=true -f $IMAGE/Dockerfile .
docker image build -t $TAG -f $IMAGE/Dockerfile .
echo Output is $OUTPUT
case "$OUTPUT" in 
  run) 
    if [ "$RUNTESTS" = 1 ]; then
      SETTERMINAL="-it"
      TESTS="integrationtests.sh"
    fi
    docker run \
      --name $CONTAINER \
      -e DEVELOPMENT=$DEVELOPMENT \
      -e LOCAL=TRUE \
      -e PNP_TOKEN_SERVER=http://token.local:8080/token/rest/query \
      -e PNP_SERVICE_NAME=pay1 \
      -e PNP_DBINFO_PASSWORD=raining23 \
      -e PNP_DBINFO_HOST=10.180.1.80 \
      -e PNP_DBINFO_USERNAME=dbinfo \
      -e PNP_DBINFO_PORT=3306 \
      -e PNP_DBINFO_DATABASE=dbinfo \
      -e PNP_ORDERS_BUCKET='plugnpay-orders' \
      -e AWS_REGION='us-east-1' \
      -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
      -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
      -e AWS_DEFAULT_REGION='us-east-1' \
      -e ACH_SETTLEMENT_BUCKET=plugnpay-dev-ach-status-changes \
      -e PNP_PARAMETER_STORE_PROXY='http://microservice-pay1-param.local' \
      -e PNP_JOB=$PNP_JOB \
      -e DEBUG=1 \
      -e DATALOG_MAKEPATH=1 \
      -e CAPTCHA_BYPASS=$CAPTCHA_BYPASS \
      -e CERTIFICATE_ARN=$CERTIFICATE_ARN \
      -e PROCESSOR=$PROCESSOR \
      -e PROCESSOR_TASK=$PROCESSOR_TASK \
      $PORTBINDING \
      $VOLUMES \
      --cap-add SYS_PTRACE \
      $SETTERMINAL $TAG $TESTS
    ;;
  image)
    TIMESTAMP=`date +%Y%m%d%H%M%S`
    docker image tag $IMAGE:$ENVIRONMENT $IMAGE:$TIMESTAMP
    docker image save $IMAGE:$TIMESTAMP -o $IMAGE.$TIMESTAMP.image
    gzip -9 $IMAGE.$TIMESTAMP.image
    docker image rm -f $IMAGE:$ENVIRONMENT $IMAGE:$TIMESTAMP
    ;;
  zip)
    if [ "$IMAGE" = "pay1" ]; then
      CONTAINER="build-zip-$IMAGE-$ENVIRONMENT"
      # run the container so we can copy files out of it
      echo Running container to extract file structure
      docker container run --name $CONTAINER --rm=true -d $IMAGE:$ENVIRONMENT

      echo Creating a clean temporary deploy directory
      # ensure a clean directory
      if [ -d deploy ]; then
        rm -rf deploy
      fi
      mkdir deploy

      echo Copying perl_lib.rollout...
      docker cp $CONTAINER:/home/pay1/perl_lib deploy/perl_lib.rollout
      echo Copying perlpr_lib.rollout...
      docker cp $CONTAINER:/home/pay1/perlpr_lib deploy/perlpr_lib.rollout
      echo Copying web.rollout...
      docker cp $CONTAINER:/home/pay1/web deploy/web.rollout
      echo Copying webtxt.rollout...
      docker cp $CONTAINER:/home/pay1/webtxt deploy/webtxt.rollout

      echo Stopping container...
      docker container kill $CONTAINER
      echo Removing container...
      docker image rm -f $IMAGE:$ENVIRONMENT

      echo Removing rollout.tgz if one already exists...
      if [ -e rollout.tgz ]; then
        rm -f rollout.tgz
      fi

      echo "Building deployment zip file (rollout.tgz)"
      cd deploy
      tar --disable-copyfile --no-xattrs -zcf ../rollout.tgz perl_lib.rollout/ perlpr_lib.rollout/ web.rollout/ webtxt.rollout/ 
      cd ..
      rm -rf deploy
    elif [ "$IMAGE" = "batchfiles-ec2" ]; then
      CONTAINER="build-zip-$IMAGE-$ENVIRONMENT"
      # run the container so we can copy files out of it
      echo Running container to extract file structure
      docker container run --name $CONTAINER --rm=true -d $IMAGE:$ENVIRONMENT

      echo Creating a clean temporary deploy directory
      # ensure a clean directory
      if [ -d deploy ]; then
        rm -rf deploy
      fi
      mkdir deploy

      echo Copying batchfiles...
      docker cp $CONTAINER:/home/pay1/batchfiles deploy/batchfiles.rollout
      echo Stopping container...
      docker container kill $CONTAINER
      echo Removing container...
      docker image rm -f $IMAGE:$ENVIRONMENT

      echo Removing batchfiles-rollout.tgz if one already exists...
      if [ -e batchfiles-rollout.tgz ]; then
        rm -f batchfiles-rollout.tgz
      fi

      echo "Building deployment zip file (batchfiles-rollout.tgz)"
      cd deploy
      tar --disable-copyfile --no-xattrs -zcf ../batchfiles-rollout.tgz batchfiles.rollout/ 
      cd ..
      rm -rf deploy
    else
      echo Deployment zip only supported for pay1 or batchfiles-ec2
    fi
    ;;
esac
