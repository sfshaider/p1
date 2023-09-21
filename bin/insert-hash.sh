#!/bin/sh
for file in `find /home/pay1/perl_lib /home/pay1/perlpr_lib -name "*.pm"`; do
  lineNum=$(grep -n -m 1 "package" $file |cut -d : -f 1)
  hash="\""$(openssl dgst -sha256 $file | awk '{print $2}')"\";"
  sed -i ''$((lineNum+=1))' iour $__moduleDigest = '$hash'' $file
done
