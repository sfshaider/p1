#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use lib $ENV{'PNP_PERL_LIB'};
use Test::More qw( no_plan );
use PlugNPay::Email;

my $email = new PlugNPay::Email("legacy");

sub testLogging {
  eval {
    $email->setTo('dpezella@plugnpay.com');
    $email->setCC('cc@mail.com');
    $email->setBCC('bcc@mail.com');
    $email->setFrom('from@mail.com');
    $email->setSubject('This is the subject');
    $email->setContent('Test email content');
    $email->setFormat('text');
    $email->send();
  };

  return $@ ? 0 : 1;

}

is(&testLogging,1,'Logging Test');


1;