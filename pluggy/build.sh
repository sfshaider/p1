#!/bin/sh

export GOPATH=`echo $PWD | sed -e '/\(.*\)\/src\/.*/ s//\1/'`
echo GOPATH for this build is $GOPATH

go get .
GOOS=linux go build -o pluggy .

# repo root is two levels above go root
cp pluggy $GOPATH/../../pay1_home/bin/pluggy
