#!/bin/env perl

use strict;
use CGI qw/:standard/;
use lib '/home/pay1/perl_lib';
use PlugNPay::AWS::ParameterStore;
use PlugNPay::AWS::S3::Object;
use PlugNPay::DBConnection;
use PlugNPay::Util::Temp;
use PlugNPay::Token;

print header(-type => 'text/plain');

my @reasonsToDie = ();
eval {
  my $param = PlugNPay::AWS::ParameterStore::getParameter('/DBINFO/SERVICE_KEY/PAY1');
  if (!defined $param || $param eq '') {
    die "undefined param";
  }
};

if ($@) {
  push  @reasonsToDie, "FAILED TO GET DBINFO SERVICE KEY PARAMETER: $@";
}

eval {
  my $s3Obj = existsOnS3();
  if (!defined $s3Obj || $s3Obj eq '') {
    die "undefined object";
  }
};

if ($@) {
  push  @reasonsToDie, "FAILED TO GET HEALTHCHECK S3 OBJECT: $@";
}

eval {
  my $tmp = new PlugNPay::Util::Temp();
  $tmp->setKey('test');
  $tmp->setValue({ 'data' => 'testing access to lambdas'});
  $tmp->setPassword('testing123');
  $tmp->setExpirationTime(1);
  my $stored = $tmp->store();
  if (!$stored) {
    die "FAILED TO STORE TO TMP LAMBDA: " . $stored->getError();
  } else {
    my $fetchStatus = $tmp->fetch();
    my $value = $tmp->getValue();
    if (!$fetchStatus || !defined $value || $value eq '') {
      die "FAILED TO FETCH FROM TMP LAMBDA";
    }
    $tmp->delete();
  }
};

if ($@) {
  push @reasonsToDie, "FAILED LAMBDA INVOKE: $@";
}

eval {
  my $dbs = new PlugNPay::DBConnection();
  my $data = $dbs->fetchallOrDie(
     'pnpdata',
     'SELECT 1 as `exists`',
     [],
     {}
  )->{'result'};

  if (!defined $data || $data eq '') {
    die 'bad response';
  }
};

if ($@) {
  push @reasonsToDie,"FAILED TO FETCH FROM PNPDATA: $@";
}


eval {
  my $dbs = new PlugNPay::DBConnection();
  my $data = $dbs->fetchallOrDie(
     'pnpmisc',
     'SELECT username FROM customers WHERE username = ?',
     ['pnpdemo'],
     {}
  )->{'result'};
  
  if ($data->[0]{'username'} ne 'pnpdemo') {
    die 'invalid user loaded';
  }
};

if ($@) {
  push @reasonsToDie,"FAILED TO FETCH FROM PNPMISC: $@";
}

eval {
  my $token = new PlugNPay::Token();
  my $cardToken = $token->getToken('4111111111111111', 'CARD_NUMBER');
  if (!defined $cardToken || $cardToken eq '') {
    die 'failed to get token for test card!';
  }

  my $card = $token->fromToken($cardToken, 'PROCESSING');
  if (!defined $card || $card ne '4111111111111111') {
    die 'invalid card returned for token!';
  }
};

if ($@) {
  push @reasonsToDie, 'Failed token test: ' . $@;
}

if (@reasonsToDie > 0) {
  die "Healthcheck failed: " . join(', ', @reasonsToDie) . "\n";
  exit;
}

print "ok\n";

exit;

sub existsOnS3 {
  my $data = '';
  my $devOrProd = 'production';
  if ($ENV{'DEVELOPMENT'} eq 'TRUE' || $ENV{'DEVELOPMENT'} == 1) {
    $devOrProd = 'dev';
  }
  my $s3Obj = new PlugNPay::AWS::S3::Object('plugnpay-' . $devOrProd . '-healthcheck');
  $s3Obj->setObjectName('test.txt');
  ($data) = $s3Obj->readObject();

  return $data
}
