#!/bin/sh

perltidy -i=2 -cti=1 -bar -nolq -nsbl -vt=2 -l=200 -ce -pt=1  -olc -nolq -nsbl -vmll -dws -dnl $1
mv $1.tdy $1
perl -c $1 # for good measure
