#!/bin/sh

go get .
GOOS=linux go build -o responselink .

# repo root is two levels above go root
cp responselink ../pay1_home/bin/responselink
rm responselink
