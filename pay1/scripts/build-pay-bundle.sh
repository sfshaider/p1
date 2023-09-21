#!/bin/sh

node pay1/node-scripts/create-pay-bundle.js > bundles/pay.js

sha256Result=$(shasum -a 256 bundles/pay.js | awk '{print $1}')
cp bundles/pay.js bundles/pay.${sha256Result}.js