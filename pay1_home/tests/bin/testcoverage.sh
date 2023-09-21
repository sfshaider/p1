#!/bin/sh

perl -MDevel::Cover=-db,cover_db,-coverage,statement,time $1
cover -report html -outputdir cover_report
rm -rf cover_db

