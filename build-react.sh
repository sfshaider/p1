#!/bin/sh

WEBPACK_MODE=$2

if [ $2 eq ""]
then
    for d in  ./react-components/*/; do (cd "$d" && npm install && npm run prod); done
else
    for d in ./react-components/*/; do (cd "$d" && npm install && npm run "$2"); done
fi    
