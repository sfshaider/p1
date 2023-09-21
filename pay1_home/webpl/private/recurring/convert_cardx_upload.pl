#!/bin/env perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Recurring::Profile;
use PlugNPay::Recurring::PaymentSource;
use strict;

my $path_infile = $ARGV[0];
my $path_outfile = $ARGV[1];

my $map = {
  'MERCHANT_ACCOUNT'     => 'merchant',
  'PAYER_ID'             => 'username',
  'PRODUCT_CODE'         => 'acct_code',
  'ACCESS_METHOD'        => 'client',
  'PAYMENT_MADE_BY_USER' => 'plan',
  'ENTITY_NAME'          => 'shipname',
  'ENTITY_NUMBER'        => 'purchaseid',
  'AMOUNT'               => 'recfee',
  'TOTAL_AMOUNT'         => 'balance',
  'NAME'                 => 'card-name',
  'ADDRESS1'             => 'card-address1',
  'ADDRESS2'             => 'card-address2',
  'CITY'                 => 'card-city',
  'STATE'                => 'card-state',
  'POSTAL_CODE'          => 'card-zip',
  'COUNTRY'              => 'card-country',
  'EMAIL_ADDRESS'        => 'email',
  'PHONE_NUMBER'         => 'phone',
  'CARD_TYPE'            => 'card-type',
  'CARD_NUMBER'          => 'card-number',
  'CARD_EXPIRATION'      => 'card-exp',
  'ONE_TIME_PAYMENT'     => 'billcycle'
};

# setup the clean-up anonymous subroutines for later usage
my $cleanup = {
  'username' => sub {
                  my $v = shift;
                  $v =~ s/[^a-zA-Z0-9\_\-]//g;
                  return unpack("H*",$v); # convert username to hex
                },
  'card-number' => sub {
                  my $v = shift;
                  $v =~ s/[^0-9]//g;
                  return $v;
                },
  'card-exp' => sub {
                  my $v = shift;
                  $v =~ s/[^0-9\-]//g;
                  $v = substr($v,5,2) . '/' . substr($v,2,2); # '2022-09-30' to '09/22'
                  return $v;
                },
   'phone' => sub {
                  my $v = shift;
                  $v =~ s/[^a-zA-Z0-9]//g;
                  return $v;
                },
    'billcycle' => sub {
                  my $v = shift;
                  return '0'; # force non-recurring, merchant using bill_member for payments
                },
    'recfee' => sub {
                  my $v = shift;
                  $v =~ s/[^0-9\.]//g;
                  if ($v eq '') {
                    return $v
                  } else{
                    return sprintf("%0.02f", $v);
                  }
                },
    'balance' => sub {
                  my $v = shift;
                  $v =~ s/[^0-9\.]//g;
                  if ($v eq '') {
                    return $v;
                  } else{
                    return sprintf("%0.02f", $v);
                  }
                },
};

open(INFILE,'<',$path_infile) or die "Cant open infile for reading. $!";
open(OUTFILE,'>',$path_outfile) or die "Cant open outfile for writing. $!";

my $header_line = <INFILE>;
print OUTFILE $header_line;
$header_line =~ s/(\r|\n|\r\n)$//g; # remove ending newlines & carriage returns

my @header = split(/\"\,\"/, $header_line);
substr($header[0],0,1) = ''; # remove leading double quote qualifer from first entry
$header[$#header] =~ s/\"$//g; # remove trailing double quote qualifer from last entry

while(<INFILE>) {
  my $line = $_;
  $line =~ s/(\r|\n|\r\n)$//g; # remove ending newlines & carriage returns

  my $data = {
   'status' => 'ACTIVE',
  };

  my @tmp = split(/\"\,\"/, $line);
  if (scalar @tmp != scalar @header) {
    next; # skip this one, when header & line element counts don't match
  }
  substr($tmp[0],0,1) = ''; # remove leading double quote qualifer from first entry
  $tmp[$#tmp] =~ s/\"$//g; # remove trailing double quote qualifer from last entry

  for (my $i = 0; $i <= $#tmp; $i++) {
    ## do special clean-ups here
    my $key = $map->{$header[$i]};
    my $val = $tmp[$i];
    $val =~ s/^null$//gi; # make all 'null' values a blank field include
    $val = $cleanup->{$key}->($val) if (exists $cleanup->{$key});

    $data->{$map->{$header[$i]}} = $val;
  }

  # ensure user doesn't exist & then store if username is unique
  my $profile = new PlugNPay::Recurring::Profile();
  if ($profile->checkExists($data->{'username'}, $data->{'merchant'})) {
    print "SKIPPING: M:$data->{'merchant'}, U:$data->{'username'} - Profile Exists\n";
  } else {
    my $respProf = &storeProfile($data);
    if ($respProf->{'status'}) {
      print "STORED: M:$data->{'merchant'}, U:$data->{'username'}";
      my $respPay = &storePaymentCC($data);
      if ($respPay->{'status'}) {
        print " + CardData\n";
      } else {
        print " - CardData [FIX]\n";
      }
    }
  }

  # outfile entry for username
  my $outline = '';
  foreach (my $i=0; $i <= $#tmp; $i++) {
    if ($header[$i] !~ /^(CARD_)/) {
      $outline .= sprintf("\"%s\",", $tmp[$i]);
    }
  }
  chop $outline;
  print OUTFILE "$outline\n";
}

close(INFILE);
close(OUTFILE);

exit;

sub storeProfile {
  my ($data) = @_;

  my $prof = {
    'merchant' => $data->{'merchant'},
    'customer' => $data->{'username'},
  };

  my $profile = new PlugNPay::Recurring::Profile($prof);
  $profile->setName($data->{'card-name'});
  $profile->setEmail($data->{'email'});
  $profile->setCompany($data->{'card-company'});
  $profile->setAddress1($data->{'card-address1'});
  $profile->setAddress2($data->{'card-address2'});
  $profile->setCity($data->{'card-city'});
  $profile->setState($data->{'card-state'});
  $profile->setPostalCode($data->{'card-zip'});
  $profile->setCountry($data->{'card-country'});
  $profile->setShippingName($data->{'shipname'});
  $profile->setShippingAddress1($data->{'address1'});
  $profile->setShippingAddress2($data->{'address2'});
  $profile->setShippingCity($data->{'city'});
  $profile->setShippingState($data->{'state'});
  $profile->setShippingPostalCode($data->{'zip'});
  $profile->setShippingCountry($data->{'country'});
  $profile->setPhone($data->{'phone'});
  $profile->setFax($data->{'fax'});
  $profile->setStatus($data->{'status'});
  $profile->setBillCycle($data->{'billcycle'});
  $profile->setRecurringFee($data->{'recfee'});
  $profile->setStartDate($data->{'startdate'});
  $profile->setEndDate($data->{'enddate'});
  $profile->setBalance($data->{'balance'});
  $profile->setAccountCode($data->{'acct_code'});
  $profile->setPurchaseId($data->{'purchaseid'});

  my $resp = $profile->saveProfile();
  return { 'status' => $resp->{'status'}, 'errorMessage' => $resp->{'errorMessage'} };
}

sub storePaymentCC {
  my ($data) = @_;

  my $payment = new PlugNPay::Recurring::PaymentSource();
  $payment->setCardNumber($data->{'card-number'});
  $payment->setExpMonth(substr($data->{'card-exp'},0,2));
  $payment->setExpYear(substr($data->{'card-exp'},-2,2));
  $payment->setPaymentSourceType('card');

  my $resp = $payment->updatePaymentSource($data->{'merchant'}, $data->{'username'});
  return { 'status' => $resp->{'status'}, 'errorMessage' => $resp->{'errorMessage'}, 'billedStatus' => $resp->{'billedStatus'} };
}

