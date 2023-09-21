#!/usr/bin/perl

use lib $ENV{'PNP_PERL_LIB'};
use smpsutils;

# get something that will fail

smpsutils::getcardnumber('chrisinc','noexist','testprocessor','blah',undef,{ suppressAlert => 1 });
