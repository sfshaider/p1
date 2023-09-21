#!/bin/sh

if [ ! -d web ]; then
  echo Please run this script from within the pay1_home directory.
  exit 1
fi

WORK_DIR=`pwd`
echo Working dir is $WORK_DIR

if [ -e perl_lib.rollout ]; then
  rm -rf perl_lib.rollout
fi

if [ -e web.rollout ]; then
  rm -rf web.rollout
fi

if [ -e webtxt.rollout ]; then
  rm -rf webtxt.rollout
fi

echo Copying Main Directories
cp -r perl_lib perl_lib.rollout
cp -r web web.rollout
cp -r webtxt webtxt.rollout

echo Copying web_common into web
cd web_common
  find . | cpio -pdmv $WORK_DIR/web.rollout/
cd $WORK_DIR
echo Back in `pwd`;

echo Copying react builds into web
cd react/_js/
echo `pwd`
  find . | cpio -pdmv $WORK_DIR/web.rollout/_js/
cd $WORK_DIR
echo Back in `pwd`;

echo Copying reseller web into web/newreseller
cd reseller_web/
echo `pwd`
  find . | cpio -pdmv $WORK_DIR/web.rollout/newreseller/
cd $WORK_DIR
echo Back in `pwd`;

echo Copying web_common into web for reseller
cd web_common
  find . | cpio -pdmv $WORK_DIR/web.rollout/newreseller/
cd $WORK_DIR
echo Back in `pwd`;

if [ -e rollout.tgz ]; then
  rm -f rollout.tgz
fi

tar -zcf rollout.tgz perl_lib.rollout/ web.rollout/ webtxt.rollout/
rm -rf web.rollout perl_lib.rollout webtxt.rollout

