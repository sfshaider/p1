#!/bin/bash

export PERL5LIB=/home/pay1/perl_lib
export TEST_INTEGRATION=1
echo "Starting responselink proxy..."
/home/pay1/bin/responselink --logbase=/tmp/
cd /home/pay1/perl_lib
prove . -r
