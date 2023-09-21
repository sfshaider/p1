#!/bin/sh

go get .
GOOS=linux go build -o loggy .

# repo root is two levels above go root
cp loggy ../pay1_home/bin/loggy
