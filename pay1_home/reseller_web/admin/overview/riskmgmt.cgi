#!/bin/env perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};

#if ($ENV{'REMOTE_USER'} eq "pxaysvgtech") {
if (($ENV{'REMOTE_ADDR'} eq "96.56.10.12ddd") || ($ENV{'REMOTE_ADDR'} eq "72.80.173.22") || ($ENV{'REMOTE_USER'} =~ /paysvgtech|paysvg2/)) {
  require risktrakbeta;
}
else {
  require risktrak;
}

#use risktrak;
if ($ENV{'REMOTE_ADDR'} eq "96.56.10.12") {
  print "Content-Type: text/html\n\n";
}
#foreach my $key (sort keys %ENV) {
#  print "$key:$ENV{$key}<br>\n";
#}


$risktrak = new risktrak('admin');

if ($ENV{'SEC_LEVEL'} > 9) {
  $risktrak->head();
  print "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  $risktrak->tail();
  exit;
}

if (($risktrak::function eq "update") && ($ENV{'REMOTE_USER'} !~ /^(pnpdemo|pnpdemo2)$/)) {
  $risktrak->update_limits();
  $risktrak->head();
  $risktrak->main();
  $risktrak->tail();
}
elsif ($risktrak::function eq "overview") {
  $risktrak->head();
  $risktrak->overview_stats();
  $risktrak->tail();
}
elsif ($risktrak::function eq "detail") {
  $risktrak->head(); 
  $risktrak->main(); 
  $risktrak->tail(); 
}
elsif ($risktrak::function eq "freezelist") {
  $risktrak->head();
  $risktrak->freeze_list();
  $risktrak->tail();
}
elsif ($risktrak::function eq "thawtrans") {
  $risktrak->head();
  $risktrak->thaw_trans_html(); 
  $risktrak->tail();
}
elsif (($risktrak::function eq "release") && ($risktrak::db_status =~ /reseller/)) {
  $risktrak->release();
}
elsif ($risktrak::function eq "clone_settings") {
  $risktrak->clone_settings();
  $risktrak->head();
  $risktrak->main();
  $risktrak->tail();
}
else {
  $risktrak->head();
  $risktrak->overview_stats();
  $risktrak->tail();

#  $risktrak->head();
#  $risktrak->main();
#  $risktrak->tail(); 
}

exit;

