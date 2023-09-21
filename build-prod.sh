#!/bin/sh

ENVIRONMENT="prod"

# inital cleanup
rm -rf bundles/*
rm -f rollout.tgz

IMAGE=$1

if [ "$IMAGE" = "" ]; then
  IMAGE="pay1"
fi

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

if [ ! "$IMAGE" = "apiserver" ]; then
  for d in  ./react-components/*/; do (cd "$d" && npm install && npm audit fix && npm run "$ENVIRONMENT"); done
fi

if [ `uname | tr "[A-Z]" "[a-z]"` = "darwin" ]; then
  LOCAL_IP=`route -n get default|grep interface|awk '{ print $2 }'| xargs ipconfig getifaddr`
else
  LOCAL_IP=`hostname -I | cut -f1 -d' '`
fi

docker container rm build-prod-pay1
echo docker image build -t $IMAGE:$ENVIRONMENT --rm=true -f $IMAGE/Dockerfile .
docker image build -t $IMAGE:$ENVIRONMENT -f $IMAGE/Dockerfile .
CONTAINER="build-prod-$IMAGE"
docker container run --name $CONTAINER --rm=true -d $IMAGE:$ENVIRONMENT

# ensure a clean directory
if [ -d deploy ]; then
  rm -rf deploy
fi
mkdir deploy

docker cp $CONTAINER:/home/pay1/perl_lib deploy/perl_lib.rollout
docker cp $CONTAINER:/home/pay1/web deploy/web.rollout
docker cp $CONTAINER:/home/pay1/webtxt deploy/webtxt.rollout

docker container kill $CONTAINER
docker image rm -f $IMAGE:$ENVIRONMENT

if [ -e rollout.tgz ]; then
  rm -f rollout.tgz
fi

cd deploy
  tar -zcf ../rollout.tgz perl_lib.rollout/ web.rollout/ webtxt.rollout/
cd ..
rm -rf deploy
