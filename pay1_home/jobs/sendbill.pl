#!/bin/env perl

#require 5.8.0;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use rsautils;
use Time::Local qw(timegm);
use miscutils;
use mckutils_strict;
use PlugNPay::GatewayAccount;
use PlugNPay::DBConnection;
use PlugNPay::Email;
use PlugNPay::CardData;
use strict;

my @merchantList;

my $checkUser = $ARGV[0];
$checkUser =~ s/[^a-zA-Z0-9]//g;

## Custom Settings:

my $forceRun = 0;  # set this to '1', if you wish to bypass last attempted enforcement
my $lookback_start = ''; # set starting date in YYYYMMDD format (leave blank if not using)
my $lookback_end = ''; # set ending date in YYYYMMDD format (leave blank if not using)

## *** Lookback dates MUST BOTH be set together, OR they will be IGNORED!

# Notes:
# - setting forceRun will bypass last attempted, regardless if you're doing a lookback or re-try to today's run
#   (useful if re-trying customer profiles that were attempted that same date &/or if the delta is larger then merchant's lookahead setting)
# - when doing a lookback, set forceRun to '1' & set both lookback dates


print "SENDBILL Started: " . gmtime(time) . "\n\n";;

open(OUTFILE,'>',"/home/pay1/private/sendbill2.chk");
print OUTFILE "sendbill\n";
close(OUTFILE);

my ($plCompany,$plEmail) = &privateLabel();

my $merchantList = &merchantList($checkUser,\@merchantList);
print "\n";

my $dbh_misc = PlugNPay::DBConnection::database('pnpmisc');

foreach my $merchant (sort @$merchantList) {

  my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);

  open(CHECKOUT,'>',"/home/pay1/private/sendbill.txt");
  print CHECKOUT "$merchant\n";
  close(CHECKOUT);

  my $sth = $dbh_misc->prepare(q{
      SELECT p.username,p.ftpun,p.ftppw,p.refresh,p.email_choice,p.fromemail,p.recmessage,p.lookahead,p.recurbatch,p.chkrecurbatch,p.installbilling,p.recnotifemail,
             c.proc_type,c.merchemail,c.company,c.status,c.reason,c.reseller,c.parentacct,c.subacct,c.currency,c.processor,c.chkprocessor
      FROM pnpsetups p, customers c
      WHERE p.username=?
      AND c.username=p.username
    }) or die "Cant prepare: $DBI::errstr";
  $sth->execute($merchant) or die "Cant execute: $DBI::errstr";
  my $data = $sth->fetchrow_hashref;
  $sth->finish;

  if (length($data->{'currency'}) != 3) {
    $data->{'currency'} = 'usd';
  }

  # filter important merchant info
  $data->{'username'} =~ s/[^a-zA-Z0-9]//g;
  $data->{'fromemail'} =~ s/[^a-zA-Z0-9\@\${'\-\+\*\=\/\.\_]//g;
  $data->{'recnotifemail'} =~ s/[^a-zA-Z0-9\@\${'\-\+\*\=\/\.\,\_]//g;
  $data->{'merchant_email'} =~ s/[^a-zA-Z0-9\@\${'\-\+\*\=\/\.\,\_]//g;
  $data->{'reseller'} =~ s/[^a-zA-Z0-9]//g;
  $data->{'parentacct'} =~ s/[^a-zA-Z0-9]//g;
  $data->{'lookahead'} =~ s/[^0-9]//g;
  $data->{'merchant'} = $merchant;
  $data->{'doRefresh'} = 0;

  my $accountFeatures = $gatewayAccount->getFeatures();
  if ($accountFeatures->get('sendRecNotification')) {
    # Set merchant/customer success notification flag
    # Values: email_customer, email_merchant, email_both, blank/NULL [none]
    $data->{'sendRecNotification'} = $accountFeatures->get('sendRecNotification');
  }

  if ($plCompany->{"$data->{'reseller'}"} ne '') {
    $data->{'privatelabelcompany'} = $plCompany->{"$data->{'reseller'}"};
    $data->{'privatelabelemail'} = $plEmail->{"$data->{'reseller'}"};
  }
  else {
    $data->{'privatelabelcompany'} = $plCompany->{'default'};
    $data->{'privatelabelemail'} = $plEmail->{'default'};
  }

  if ($data->{'status'} ne 'live') {
    printf("%s\: Skipping account. Status: %s, Reason: %s\n", $data->{'merchant'}, $data->{'status'}, $data->{'reason'});
    next;
  }

  if (($data->{'lookahead'} eq '') || ($data->{'lookahead'} > 10)) {
    $data->{'lookahead'} = 6;
  }

  if (&check_database($data->{'merchant'}) != 1) {
    printf("%s\: Can't connect to membership database.\n", $data->{'merchant'});
    next;
  }

  $data->{'doRefresh'} = &sendbill($data,$gatewayAccount);

  if ($accountFeatures->get('forceRecRefresh')) {
    # See if we should force run the refresh script, even if no-one was billed.
    # * This is for merchants that require a forced resync of their password data at least once a day.
    $data->{'doRefresh'} = 1;
  }

  if (-e "/home/pay1/private/stopsendbill.txt") {
    last;
  }

  if (($data->{'refresh'} eq 'yes') && ($data->{'doRefresh'} == 1) && ($data->{'ftpun'} !~ /NO\s*FTP/i) && ($data->{'ftppw'} !~ /NO\s*FTP/i)) {
    print "Performing Refresh:\n";
    my $status = &doRefresh($data);
    print "\nRefresh Status: $status\n";
  }
}

$dbh_misc->breakConnection();

PlugNPay::DBConnection::cleanup();

unlink "/home/pay1/private/sendbill2.chk";

print "\nSENDBILL Complete: " . gmtime(time) . "\n\n";

exit;

sub check_database {
  ## checks if we can connect to merchant's database
  my ($merchant) = @_;

  my $dbh;
  eval {
    $dbh = PlugNPay::DBConnection::database($merchant);
  };

  if ($@) {
    # Log DBH error
    return 0; # failed DBH connection
  }
  else {
    return 1; # successful DBH connection
  }
}

sub doRefresh {
  ## invoke merchant's refresh script to sync database info with their site
  my ($data) = @_;

  my $path_recadmin = sprintf("/home/pay1/web/payment/recurring/%s/admin", $data->{'merchant'});
  if (!-e "$path_recadmin/refresh.cgi") {
    return 'unfound';
  }

  eval {
    local($SIG{ALRM}) = sub { die 'failure' };

    alarm 300;

    my $delta1 = time();

    chdir("$path_recadmin");
    $data->{'ftpun'} =~ s/(\W)/'%' . unpack('H2',$1)/ge;
    $data->{'ftppw'} =~ s/(\W)/'%' . unpack('H2',$1)/ge;
    my $pairs = sprintf("FTPun=%s FTPpw=%s", $data->{'ftpun'}, $data->{'ftppw'});

    my $a = `$path_recadmin/refresh.cgi $pairs`;

    my $delta2 = time();

    my $refreshtime = $delta2 - $delta1;
    print "\nRefresh Time: $refreshtime\n";
    print "$a\n";

    alarm 0;
  };

  if ($@) {
    return 'failure';
  }

  return 'success';
}


sub sendbill {
  ## scan merchant's customer profiles & processing a recurring payment if needed.
  ## generate reports before & after processing, as needed.
  my ($data,$gatewayAccount) = @_;

  my %resultList;

  print "\n---------------------------------------\n";
  print "MERCHANT: $data->{'merchant'}\n";

  my ($dummy,$dummy2,$timestr) = &miscutils::gendatetime();

  my @now = gmtime(time());
  $data->{'today'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);
  $data->{'fixlookahead'} = $data->{'lookahead'};

  &generatePreBillReport($data);

  my $total = 0;
  my $orderID = &generateOrderID;

  print "aaaa\n";
  my $customerList = &customerList($data);
  print "bbbb\n";

  my $dbh = PlugNPay::DBConnection::database($data->{'merchant'});

  foreach my $username (sort @$customerList) {
    print "r $username ";
    if (-e "/home/pay1/private/stopsendbill.txt") {
      last;
    }

    my $sth = $dbh->prepare(q{
        SELECT *
        FROM customer
        WHERE username=?
      }) or die "Cant prepare: $DBI::errstr";
    $sth->execute($username) or die "Cant execute: $DBI::errstr";
    my $custData = $sth->fetchrow_hashref;
    $sth->finish;

    my $cd = new PlugNPay::CardData();
    my $ecrypted_card_data = '';
    eval {
      $ecrypted_card_data = $cd->getRecurringCardData({customer => "$username", username => "$data->{'merchant'}"});
    };
    if (!$@) {
      $custData->{'enccardnumber'} = $ecrypted_card_data;
    }

    # X:Y,Z    Y = number of months    Z = new monthly fee
    if (($custData->{'plan'} =~ /:.*,/) && ($custData->{'plan'} !~ /x$/)) {
      if ($custData->{'plan'} =~ /:(.+),(.+)/) {
        my $months = $1;
        my $newmonthly = $2;
        my $startmonths = ((substr($custData->{'startdate'},0,4) - 1900) * 12) + substr($custData->{'startdate'},4,2);
        my $endmonths = ((substr($custData->{'enddate'},0,4) - 1900) * 12) + substr($custData->{'enddate'},4,2);
        if ((substr($custData->{'startdate'},6,2) > 28) && (substr($custData->{'enddate'},6,2) == 1)) {
          $endmonths = $endmonths - 1;
        }
        my $deltamonths = $endmonths - $startmonths;
        if (($deltamonths > $months)) {
          $custData->{'monthly'} = $newmonthly;
        }
      }
      else {
        next;
      }
    }

    my ($currency2,$monthly2) = split(/ /,$custData->{'monthly'});
    if ($currency2 =~ /^[a-zA-Z]{3}$/) {
      $currency2 =~ tr/A-Z/a-z/;
      $custData->{'monthly'} = $monthly2;
      $custData->{'currency'} = $currency2;
    }
    else {
      $custData->{'currency'} = $data->{'currency'};
    }
    $custData->{'monthly'} =~ s/[^0-9\.]//g;

    if ($data->{'installbilling'} ne 'yes') {
      $custData->{'balance'} = '';
    }
    else {
      $custData->{'balance'} =~ s/[^0-9\.]//g;
    }

    if (($data->{'installbilling'} eq 'yes') && ($custData->{'balance'} ne '')) {
      if (($custData->{'balance'} < $custData->{'monthly'} + 1.00) && ($custData->{'monthly'} > 1.00)) {
        $custData->{'monthly'} = $custData->{'balance'};
      }
      elsif ($custData->{'balance'} < $custData->{'monthly'}) {
        $custData->{'monthly'} = $custData->{'balance'};
      }
    }
    my $checkmonth = substr($custData->{'enddate'},4,2);
    if ($checkmonth > 12) {
      next;
    }

    if ($data->{'parentacct'} ne '') {
      $custData->{'bill_acct'} = $data->{'parentacct'};
    }
    elsif ($custData->{'billusername'} ne '') {
      $custData->{'bill_acct'} = $custData->{'billusername'};
    }
    else {
      $custData->{'bill_acct'} = $data->{'merchant'};
    }

    $data->{'bill_acct'} = $custData->{'bill_acct'};

    $custData = &calculateAmountDue($data,$custData);
    print "x";

    if ($custData->{'amountdue'} > 0) {
      $custData->{'card-number'} = &rsautils::rsa_decrypt_file($custData->{'enccardnumber'},$custData->{'length'},"print enccardnumber 497","/home/pay1/pwfiles/keys/key");
      my $mylen = length($custData->{'card-number'});
      if (($mylen < 13) || ($mylen > 40)) {
        next;
      }

      $custData->{'accttype'} = '';
      $custData->{'card-number'} =~ s/[^0-9 ]//g;

      if ($custData->{'card-number'} =~ /\d{9} \d/) {
        $custData->{'accttype'} = 'checking';
        ($custData->{'routingnum'},$custData->{'accountnum'}) = split(/ /,$custData->{'card-number'},2);
      }
      else {
        $custData->{'commcardtype'} = '';
        $custData->{'accttype'} = '';
        $custData->{'card-number'} =~ s/[^0-9]//g;
      }

      $orderID = &miscutils::incorderid($orderID);

      if ($custData->{'country'} eq '') {
        $custData->{'country'} = 'US';
      }
      $custData->{'addr'} = "$custData->{'addr1'} $custData->{'addr2'}";

      my ($exp_month,$exp_year) = split(/\//,$custData->{'exp'});
      $exp_month = sprintf("%02d", $exp_month);
      $exp_year = sprintf("%02d", substr($exp_year,-2));
      my $test_date = sprintf("%04d", substr($exp_year,-2)+2000) . $exp_month;

      my $current_date = substr($data->{'today'},0,6);
      my $current_year = substr($data->{'today'},2,2);
      if ($current_date > $test_date) {
        $exp_year = sprintf("%2d", $current_year+1);
      }
      my $expDate = $exp_month . '/' . $exp_year;

      $custData->{'lastattempted'} = $data->{'today'};
      &updateLastAttempted($data,$custData);

      my $acct_code4 = "$data->{'merchant'}:$username";

      print "t ";

      my $transflags = 'recurring';
      if ($data->{'processor'} eq 'fdmsintl') {
        $transflags = '';
      }

      my $checktype = '';
      if (($custData->{'accttype'} =~ /^(checking|savings)$/) && ($data->{'chkprocessor'} ne "")) {
        if ($custData->{'commcardtype'} eq 'business') {
          $checktype = 'CCD';
        }
        else {
          $checktype = 'PPD';
        }
      }

      # permit only numeric IDs to be passed
      my $origorderid = '';
      if ($custData->{'orderid'} =~ /^\d+$/ ) {
        $origorderid = $custData->{'orderid'}; 
      }

      # Contact the credit server
      ####  Insert call to mckutils
      my %paymentHash = (
        'publisher-name' => $custData->{'bill_acct'},
        'orderID'        => $orderID,
        'origorderid'    => $origorderid,
        'accttype'       => $custData->{'accttype'},
        'card-amount'    => $custData->{'monthly'},
        'currency'       => $custData->{'currency'},
        'phone'          => $custData->{'phone'},
        'acct_code'      => $custData->{'acct_code'},
        'acct_code3'     => 'recurring',
        'acct_code4'     => $acct_code4,
        'email'          => $custData->{'email'},
        'card-name'      => $custData->{'name'},
        'card-address'   => $custData->{'addr'},
        'card-city'      => $custData->{'city'},
        'card-state'     => $custData->{'state'},
        'card-zip'       => $custData->{'zip'},
        'card-country'   => $custData->{'country'},
        'transflags'     => $transflags,
        'commcardtype'   => $custData->{'commcardtype'},
        'subacct'        => $data->{'subacct'},
        'authtype'       => 'authonly',
        'nofraudcheck'   => 'yes',
        'client'         => 'sendbill'
      );


      if ($custData->{'accttype'} =~ /^(checking|savings)$/) {
        $paymentHash{'routingnum'}   = $custData->{'routingnum'};
        $paymentHash{'accountnum'}   = $custData->{'accountnum'};
        $paymentHash{'checknum'}     = '9999';
        $paymentHash{'checktype'}    = $checktype;
        if ($data->{'chkrecurbatch'} eq 'yes') {
          $paymentHash{'authtype'} = 'authpostauth';
        }
      }
      else {
        $paymentHash{'card-number'}  = $custData->{'card-number'};
        $paymentHash{'card-exp'}     = $expDate;
        if ($data->{'recurbatch'} eq 'yes') {
          $paymentHash{'authtype'} = 'authpostauth';
        }
      }

      my @array = %paymentHash;
      my $payment = mckutils->new(@array);
      $mckutils::buypassfraud = 'yes';
      $mckutils::skipsecurityflag = 1;
      my %result = $payment->purchase('auth');

      if ($result{'FinalStatus'} eq 'success') {
        eval {
          $payment->logFeesIfApplicable(\%mckutils::query, \%mckutils::result, $mckutils::adjustmentFlag, $mckutils::conv_fee_acct, $mckutils::conv_fee_oid);
        };
      }

      $custData->{'card-number'} = ''; # erase the decrypted card number

      print "$username $orderID $expDate $result{'FinalStatus'} $result{'MErrMsg'} $custData->{'accttype'} ";
      print "t";

      if (($result{'FinalStatus'} eq 'success') && ($mckutils::query{'conv_fee_amt'} > 0 ) && ($result{'MErrMsg'} !~ /^Duplicate/)) {
        my %orig = ();
        my @orig = ('orderID','card-amount','publisher-name','publisher-email','acct_code','acct_code2','acct_code3','amountcharged');
        foreach my $var (@orig) {
          $orig{$var} = $mckutils::query{$var};
        }

        my %legacyorigfeatures = %mckutils::feature;

        ### Set Features for Conv. Account
        $mckutils::accountFeatures = new PlugNPay::Features($mckutils::query{'conv_fee_acct'},'general');

        #### To support legacy feature hash - currently redundant as it is pulled out again in purchase
        my $features = $mckutils::accountFeatures->getSetFeatures();
        foreach my $var (@{$features}) {
          $mckutils::feature{$var} = $mckutils::accountFeatures->get($var);
        }

        ## Mark transaction as a conv. fee transaction
        $mckutils::convfeeflag = 1;

        $mckutils::query{'card-amount'} = $mckutils::query{'conv_fee_amt'};
        $mckutils::query{'publisher-name'} = $mckutils::query{'conv_fee_acct'};
        if ($mckutils::query{'conv_fee_acct'} eq $orig{'publisher-name'}) {
          $mckutils::query{'orderID'} =  $mckutils::query{'orderID'} . '1';
        }
        else {
          $mckutils::query{'orderID'} = &miscutils::incorderid($mckutils::query{'orderID'});
        }
        $mckutils::orderID = $mckutils::query{'orderID'};
        $mckutils::query{'acct_code3'} = "ConvFeeC:$orig{'orderID'}:$orig{'publisher-name'}";

        my %resultCF = $payment->purchase('auth');

        $result{'auth-codeCF'} = substr($resultCF{'auth-code'},0,6);
        $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
        $result{'MErrMsgCF'} = $resultCF{'MErrMsg'};
        $result{'orderIDCF'} = $mckutils::query{'orderID'};
        $result{'convfeeamt'} = $mckutils::query{'conv_fee_amt'};

        my (%result1,$voidstatus);

        if (($resultCF{'FinalStatus'} ne 'success') && ($mckutils::query{'conv_fee_failrule'} =~ /VOID/i)) {
          my $price = sprintf("%3s %0.2f", $mckutils::query{'currency'}, $orig{'card-amount'});
          ## Void Main transaction
          for(my $i=1; $i<=3; $i++) {
            %result1 = &miscutils::sendmserver($orig{'publisher-name'},'void',
                'acct_code', $mckutils::query{'acct_code'},
                'acct_code4', $mckutils::query{'acct_code4'},
                'txn-type', 'auth',
                'amount', "$price",
                'order-id', "$orderID",
                'accttype', $mckutils::query{'accttype'}
              );
            last if($result1{'FinalStatus'} eq 'success');
          }
          $result{'voidstatus'} = $result1{'FinalStatus'};
          $result{'FinalStatus'} = $resultCF{'FinalStatus'};
          $result{'MErrMsg'} = $resultCF{'MErrMsg'};
        }
        if ($resultCF{'FinalStatus'} eq 'success') {
          $mckutils::query{'totalchrg'} = sprintf("%0.2f", $orig{'card-amount'}+$mckutils::query{'conv_fee_amt'});
        }
        $payment->database();

        %mckutils::result = (%mckutils::result,%result);

        foreach my $var (@orig) {
          $mckutils::query{$var} = $orig{$var};
        }

        ## Set Features Back to Primary Account
        $mckutils::accountFeatures = new PlugNPay::Features($mckutils::query{'publisher-name'},'general');

        #### To support legacy feature hash
        %mckutils::feature = %legacyorigfeatures;

        $mckutils::query{'convfeeamt'} = $result{'convfeeamt'};

        $mckutils::conv_fee_amt = $mckutils::query{'conv_fee_amt'};
        $mckutils::conv_fee_acct = $mckutils::query{'conv_fee_acct'};
        $mckutils::conv_fee_oid = $result{'orderIDCF'};

        delete $mckutils::query{'conv_fee_amt'};
        delete $mckutils::query{'conv_fee_acct'};
        delete $mckutils::query{'conv_fee_failrule'};

        ## un Mark transaction as a conv. fee transaction since tran is now complete
        $mckutils::convfeeflag = 0;
      } ## End Conv. Fee Block

      my $bill_descr = sprintf("%02d/%02d/%04d Payment", $now[4]+1, $now[3], $now[5]+1900);

      &appendBillingStatus($data->{'merchant'},$custData->{'username'},$data->{'today'},$custData->{'amountdue'},$orderID,$bill_descr,$result{'FinalStatus'},$custData->{'bill_acct'});

      $resultList{"$custData->{'username'}"} = {
        'FinalStatus' => $result{'FinalStatus'},
        'name' =>  $custData->{'name'},
        'today' => $data->{'today'},
        'delta' => $custData->{'delta'},
        'monthly' => $custData->{'monthly'},
        'orderID' => $orderID,
        'auth-code' => substr($result{'auth-code'},0,6),
        'billacct' => $custData->{'bill_acct'},
        'email' => $custData->{'email'},
        'password' => $custData->{'password'},
        'balance' => $custData->{'balance'},
        'lastattempted' => $custData->{'lastattempted'}
      };

      if ($result{'FinalStatus'} eq 'success') {
        &transactionSuccess($data,$custData,\%result,$gatewayAccount);
      }
      else {  ### Transaction Failed
        &transactionFailed($data,$custData,\%result,$gatewayAccount);
      }

      $total += $custData->{'amountdue'};
      print "v\n";

      # force incriment main orderID, to prevent clashing of orderIDs due to convfee auth
      $orderID = &miscutils::incorderid($orderID);
    }
    print "w\n";
  }
  printf("Total: %0.2f\n", $total);

  $dbh->breakConnection();

  if (scalar keys %resultList > 0) {
    &emailMerchantNotification($data,\%resultList);
    &generatePostBillReport($data,\%resultList);
    return 1;
  }
  else {
    print "No Recurring Payment Processed.\n";
    return 0;
  }
}

sub transactionSuccess {
  ## update the customer profle, upon payment success
  ## then send success notification to customer, if needed
  my ($data,$custData,$result,$gatewayAccount) = @_;

  my @placeholder;
  my $qstr = "UPDATE customer";
  $qstr .= " SET lastbilled=?,enddate=?";
  push(@placeholder, $data->{'today'}, $custData->{'expire'});

  if (($data->{'installbilling'} eq 'yes') && ($custData->{'balance'} ne '')) {
    $custData->{'balance'} = $custData->{'balance'} - $custData->{'monthly'};
    $custData->{'balance'} = sprintf("%0.2f", $custData->{'balance'} + .0001);

    $qstr .= ",balance=?";
    if ($custData->{'balance'} eq "0.00") {
      push(@placeholder, '0');
    }
    else {
      push(@placeholder, $custData->{'balance'});
    }
  }
  $qstr .= " WHERE username=?";
  push(@placeholder, $custData->{'username'});

  my $dbh = PlugNPay::DBConnection::database($data->{'merchant'});
  my $sth = $dbh->prepare(qq{ $qstr }) or die "Cant prepare: $DBI::errstr";
  $sth->execute(@placeholder) or die "Cant execute: $DBI::errstr";
  $sth->finish;

  &emailCustomerSuccess($data,$custData,$result);
}

sub transactionFailed {
  ## bump-up lastattempted in customer profle, upon payment failure
  ## then send failure notification to customer, if needed
  my ($data,$custData,$result) = @_;

  if (($data->{'email_choice'} =~ /email_/)
      && (($data->{'today'} - $custData->{'enddate'}) > 0)
      && ($custData->{'delta'} > $data->{'fixlookahead'})
      && ($custData->{'lastattempted'} !~ /x/)
      && (length($custData->{'lastattempted'}) >= 8)) {

    $custData->{'lastattempted'} .= 'x';
    &updateLastAttempted($data,$custData);
    &emailCustomerFail($data,$custData,$result);
  }
}

sub appendBillingStatus {
  ## append payment attempt to customer's billing history
  my ($merchant,$username,$trans_date,$amount,$orderid,$descr,$result,$billusername) = @_;

  my $dbh = PlugNPay::DBConnection::database($merchant);
  my $sth = $dbh->prepare(q{
      INSERT INTO billingstatus
      (username,trans_date,amount,orderid,descr,result,billusername)
      VALUES (?,?,?,?,?,?,?)
    }) or die "Cant prepare: $DBI::errstr";
  $sth->execute($username,$trans_date,$amount,$orderid,$descr,$result,$billusername) or die "Cant execute: $DBI::errstr";
  $sth->finish;
  return;
}

sub updateLastAttempted {
  ## updates customer profile's 'lastattempted' field, to indicate a payment was attempted
  my ($data,$custData) = @_;

  my $dbh = PlugNPay::DBConnection::database($data->{'merchant'});
  my $sth = $dbh->prepare(q{
      UPDATE customer
      SET lastattempted=?
      WHERE username=?
    }) or die "Cant prepare: $DBI::errstr";
  $sth->execute($custData->{'lastattempted'}, $custData->{'username'}) or die "Cant execute: $DBI::errstr";
  $sth->finish;
}


sub generateOrderID {
  ## generate a unique starting orderID; so it can be incrimented upon as each payment is attempted
  my @now = gmtime(time());
  my $id = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0], '00000');
  return $id;
}

sub generatePostBillReport {
  ## generate list of customers that were recur bill attempted & how they resulted.
  my($data,$resultList) = @_;

  if (scalar keys %{$resultList} > 0) {
    print "\nResults:\n\n";
    printf("%-11s %-24s %-40s %-8s %-6s %-10s %-18s %-8s %-12s %-10s %-8s %s\n", 'FinalStatus', 'Username', 'Name', 'Today', 'Delta', 'Monthly', 'OrderID', 'AuthCode', 'BillAcct', 'Balance', 'LastAtt', 'Email');
    foreach my $username (sort keys %{$resultList}) {
      my $entry = $resultList->{"$username"};
      printf("%-11s %-24s %-40s %-8s %6s %-10s %-18s %-8s %-12s %-10s %-8s %s\n", $entry->{'FinalStatus'}, $username, $entry->{'name'}, $entry->{'today'}, $entry->{'delta'}, $entry->{'monthly'}, $entry->{'orderID'}, $entry->{'auth_code'}, $entry->{'bill_acct'}, $entry->{'balance'}, $entry->{'lastattempted'}, $entry->{'email'});
    }
  }
}

sub generatePreBillReport {
  ## generate list of customers that are within processing window (today's date +/- lookhead)
  my ($data) = @_;

  my @ec = gmtime(time()-($data->{'fixlookahead'}*3600*24));
  my $endcheck = sprintf("%04d%02d%02d", $ec[5]+1900, $ec[4]+1, $ec[3]);

  my @ec2 = gmtime(time()+($data->{'lookahead'}*3600*24));
  my $endcheck2 = sprintf("%04d%02d%02d", $ec2[5]+1900, $ec2[4]+1, $ec2[3]);

  if (($lookback_start ne '') && ($lookback_end ne '')) {
    $endcheck = $lookback_start;
    $endcheck2 = $lookback_end;
  }

  printf("\nPreBilling Report: %s thru %s\n\n", $endcheck, $endcheck2);
  printf("%1s %-24s  %-40s  %-10s  %-10s  %-10s  %10s  %10s  %10s  %-10s\n", '', 'Username', 'Name', 'StartDate', 'EndDate', 'LastBilled', 'Monthly', 'Balance', 'BillCycle', 'AmtDue');

  my $total = 0;
  my $maxnum = 0;

  my $dbh = PlugNPay::DBConnection::database($data->{'merchant'});

  my $sth = $dbh->prepare(q{
      SELECT *
      FROM customer
      WHERE billcycle<>?
      AND enddate>=?
      AND enddate<=?
      ORDER BY CAST(billcycle AS SIGNED INTEGER) ASC, username
    }) or die "Cant prepare: $DBI::errstr";
  $sth->execute('0',$endcheck,$endcheck2) or die "Cant execute: $DBI::errstr";
  while (my $custData = $sth->fetchrow_hashref) {
    $custData->{'monthly'} =~ s/[^0-9\.]//g;
    if (($data->{'installbilling'} eq 'yes') && ($custData->{'balance'} ne '')) {
      if ($custData->{'balance'} < 0.01) {
        next;
      }
      elsif ($custData->{'balance'} < $custData->{'monthly'}) {
        $custData->{'monthly'} = $custData->{'balance'};
      }
    }

    my $checkmonth = substr($custData->{'enddate'},4,2);
    if ($checkmonth > 12) {
      next;
    }

    $custData = &calculateAmountDue($data,$custData);

    if ($custData->{'amountdue'} >= 0) {
      $custData->{'startdate'} = sprintf("%02d/%02d/%04d", substr($custData->{'startdate'},4,2), substr($custData->{'startdate'},6,2), substr($custData->{'startdate'},0,4));
      if ($custData->{'enddate'} ne '') {
        $custData->{'enddate'} = sprintf("%02d/%02d/%04d", substr($custData->{'enddate'},4,2), substr($custData->{'enddate'},6,2), substr($custData->{'enddate'},0,4));
      }
      if ($custData->{'lastbilled'} ne '') {
        $custData->{'lastbilled'} = sprintf("%02d/%02d/%04d", substr($custData->{'lastbilled'},4,2), substr($custData->{'lastbilled'},6,2), substr($custData->{'lastbilled'},0,4));
      }
      if ($custData->{'balance'} ne '') {
        $custData->{'balance'} = sprintf("%0.2f", $custData->{'balance'});
      }

      my ($warnflg);
      my $cardlength = length $custData->{'cardnumber'};
      if (($cardlength > 20) || ($cardlength < 8)) {
        $warnflg = '*';
      }

      $total += $custData->{'amountdue'};

      printf("%1s %-24s  %-40s  %-10s  %-10s  %-10s  %10.2f  %10s  %10s  %-10.2f\n", $warnflg, $custData->{'username'}, $custData->{'name'}, $custData->{'startdate'}, $custData->{'enddate'}, $custData->{'lastbilled'}, $custData->{'monthly'}, $custData->{'balance'}, $custData->{'billcycle'}, $custData->{'amountdue'});

      $maxnum++;
      if ($maxnum > 2000) {
        print "-- Max Limit Reached, Self-Terminating Pre-Billing Report.\n";
        last;
      }
    }
  }
  $sth->finish;

  $dbh->breakConnection();

  printf("\nTotal: %0.2f\n", $total);
}

sub calculateAmountDue {
  ## calculates customer's payment amount & what their new enddate would be if payment was successful.
  my ($data,$custData) = @_;

  my $eemonth = substr($custData->{'enddate'},4,2);
  my $eeday = substr($custData->{'enddate'},6,2);
  my $eeyear = substr($custData->{'enddate'},0,4);

  my $end = $custData->{'enddate'};
  my ($monthly,$dummy,$expire,$amountdue);

  # carol 03/02/2004
  if (($eemonth == 2) && ($eeday > 28)) {
    $end = $eeyear . '0301';
  }
  elsif ((($eemonth == 4) || ($eemonth == 6) || ($eemonth == 9) || ($eemonth == 11)) && ($eeday > 30)) {
    $end = sprintf("%04d%02d%02d", $eeyear, $eemonth+1, '01');
  }

  if (($end < 19970101) || ($eemonth < 1) || ($eemonth > 12) || ($eeday < 1) || ($eeday > 31)) {
    $end = '19970101';
  }
  if ($end > 20370101) {
    $end = '20370101';
  }

  my $period_end = timegm(0,0,0,substr($end,6,2),substr($end,4,2)-1,substr($end,0,4)-1900);
  my ($dummy1,$dummy2,$dummy3,$day,$month,$year,$dummy4) = gmtime($period_end-($data->{'lookahead'}*3600*24));
  my $enddate = sprintf("%04d%02d%02d", $year+1900, $month+1, $day);

  my $enddatedays = timegm(0,0,0,substr($enddate,6,2),substr($enddate,4,2)-1,substr($enddate,0,4)-1900) / (3600 * 24);
  my $todaydays = timegm(0,0,0,substr($data->{'today'},6,2),substr($data->{'today'},4,2)-1,substr($data->{'today'},0,4)-1900) / (3600 * 24);
  $custData->{'delta'}=  $todaydays - $enddatedays;

  $custData->{'monthly'} =~ s/[^0-9\.]//g;

  if (((($data->{'today'} - $enddate) > 0) && ($custData->{'delta'} <= $data->{'fixlookahead'})) || ($forceRun == 1)) {
    $amountdue = $custData->{'monthly'};
    if ($custData->{'billcycle'} >= 1) {
      my $expiremonth = substr($end,4,2) + $custData->{'billcycle'};
      if ($expiremonth > 24) {
        $expire = sprintf("%04d%02d%02d", substr($end,0,4)+2, $expiremonth-24, substr($end,6,2));
      }
      elsif ($expiremonth > 12) {
        $expire = sprintf("%04d%02d%02d", substr($end,0,4)+1, $expiremonth-12, substr($end,6,2));
      }
      else {
        $expire = sprintf("%04d%02d%02d", substr($end,0,4), $expiremonth, substr($end,6,2));
      }

      my $monthday = substr($expire,4,4);
      if ((($monthday > "0930") && ($monthday < "1001"))
         || (($monthday > "0430") && ($monthday < "0501"))
         || (($monthday > "0630") && ($monthday < "0701"))
         || (($monthday > "1130") && ($monthday < "1201"))
         || (($monthday > "0228") && ($monthday < "0301"))) {
        $expiremonth = substr($expire,4,2) + 1;
        if ($expiremonth > 12) {
          $expire = sprintf("%04d%02d%02d", substr($expire,0,4)+1, $expiremonth-12, 1);
        }
        else {
          $expire = sprintf("%04d%02d%02d", substr($expire,0,4), $expiremonth, 1);
        }
      }
    }
    else {
      my $period_end = timegm(0,0,0,substr($end,6,2),substr($end,4,2)-1,substr($end,0,4)-1900);
      my ($dummy1,$dummy2,$dummy3,$day,$month,$year,$dummy4) = gmtime($period_end+($custData->{'billcycle'}*28*3600*24));
      $expire = sprintf("%04d%02d%02d", $year+1900, $month+1, $day);
    }
  }
  else {
    $amountdue = 0;
  }
  $custData->{'amountdue'} = $amountdue;
  $custData->{'expire'} = $expire;

  return $custData;
}


sub privateLabel {
  ## retrieves private label company name & email address to use within notifications
  my ($plcompany,$plemail) = @_;

  $plcompany->{'default'} = "Plug \& Pay";
  $plemail->{'default'} = "noreply\@plugnpay.com";

  my $dbh_misc = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh_misc->prepare(q{
      SELECT username,company,email
      FROM privatelabel
    }) or die "Cant prepare: $DBI::errstr";
  $sth->execute() or die "Cant execute: $DBI::errstr";
  while (my ($username,$company,$email) = $sth->fetchrow) {
    # filter merchant username, company & email
    $username =~ s/[^a-zA-Z0-9]//g;
    $company =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;
    $email =~ s/[^a-zA-Z0-9\@\$\-\+\*\=\/\.\,\_]//g;

    $plcompany->{$username} = $company;
    $plemail->{$username} = $email;
  }
  $sth->finish;

  $dbh_misc->breakConnection();

  return ($plcompany,$plemail);
}


sub merchantList {
  ## list all merchants subscribed to Membership Management & return list of only those which have a MM database setup.
  my ($checkUser,$merchantList) = @_;

  my @placeholder;
  my $qstr = "SELECT username";
  $qstr .= " FROM pnpsetups";
  $qstr .= " WHERE recurbill=?";
  push(@placeholder, 'yes');
  if ($checkUser ne '') {
    $qstr .= " AND username=?";
    push(@placeholder, $checkUser);
  }
  $qstr .= " ORDER BY username";

  my $dbh_misc = PlugNPay::DBConnection::database('pnpmisc');

  my $sth = $dbh_misc->prepare(qq{ $qstr }) or die "Cant prepare: $DBI::errstr";
  $sth->execute(@placeholder) or die "Cant execute: $DBI::errstr";
  while (my ($username) = $sth->fetchrow) {
    $username =~ s/[^a-zA-Z0-9]//g; # merchant username filter
    push (@$merchantList, $username);
    printf("Include: %-12s\n", $username);
  }
  $sth->finish;

  $dbh_misc->breakConnection();

  return $merchantList;
}


sub customerList {
  ## generate list of customer profiles within the the time window (today +/- lookhead) & have not been recur bill attempted today.
  my ($data) = @_;

  my @customerList = ();

  my ($dummy1,$dummy2,$dummy3,$day,$month,$year,$dummy4) = gmtime(time()-($data->{'fixlookahead'}*3600*24));
  my $endcheck1 = sprintf("%04d%02d%02d", $year+1900, $month+1, $day);

  ($dummy1,$dummy2,$dummy3,$day,$month,$year,$dummy4) = gmtime(time()+($data->{'lookahead'}*3600*24));
  my $endcheck2 = sprintf("%04d%02d%02d", $year+1900, $month+1, $day);

  my $dbh = PlugNPay::DBConnection::database($data->{'merchant'});

  my @placeholder;
  my $qstr .= "SELECT username";
  $qstr .= " FROM customer";
  $qstr .= " WHERE billcycle<>?";
  push(@placeholder, '0');
  $qstr .= " AND enddate>=?";
  push(@placeholder, $endcheck1);
  $qstr .= " AND enddate<=?";
  push(@placeholder, $endcheck2);
  if (!$forceRun) {
    $qstr .= " AND (lastattempted<? OR lastattempted IS NULL OR lastattempted='')";
    push(@placeholder, $data->{'today'});
  }
  $qstr .= " AND (username IS NOT NULL AND username!='')";
  $qstr .= " ORDER BY billusername,username";

  my $sth = $dbh->prepare(qq{ $qstr }) or die "Cant prepare: $DBI::errstr";
  $sth->execute(@placeholder) or die "Cant execute: $DBI::errstr";
  while (my ($username) = $sth->fetchrow) {
    if ($username =~ m/[^a-zA-Z_0-9\.\_\-\@]/) {
      print "s $username "; # skip username, contains an invalid character
    }
    else {
      push(@customerList, $username); # username OK, proceed normally
    }
  }
  $sth->finish;

  $dbh->breakConnection();

  return \@customerList;
}

sub emailCustomerSuccess {
  ## Sends customer success notification
  ## * NOTE: Process this email inline, in case sendbill fails before merchant's run is completed
  my ($data,$custData,$result) = @_;

  if (($data->{'sendRecNotification'} =~ /(_customer|_both)$/) && ($custData->{'email'} ne '') && ($data->{'installbilling'} ne 'yes')) {
    my %message;
    $message{'To'} = $custData->{'email'};
    if ($data->{'fromemail'} ne '') {
      $message{'From'} = $data->{'fromemail'};
    }
    else {
      $message{'From'} = $data->{'merchant_email'};
    }
    $message{'Subject'} = "$data->{'company'} Payment Success Notification\n";

    my $shortcard = substr($custData->{'card-number'},-4,4);
    $message{'Content'} = "The payment account we have on file ending in\n";
    $message{'Content'} .= "$shortcard was charged $custData->{'monthly'} on $data->{'today'} by $data->{'company'}.\n\n";
    $message{'Content'} .= "If you have questions about this charge please contact\n";
    if ($data->{'recnotifemail'} ne '') {
      $message{'Content'} .= $data->{'recnotifemail'};
    }
    else {
      $message{'Content'} .= $data->{'merchant_email'};
    }
    $message{'Content'} .= "\n\n\n";
    $message{'Content'} .= "Name: $custData->{'name'}\n";
    $message{'Content'} .= "Order ID: $result->{'orderID'}\n\n";
    $message{'Content'} .= "Amount: $custData->{'monthly'}\n";

    &_notify($custData->{'bill_acct'}, \%message);
  }
}

sub emailCustomerFail {
  ## Sends customer failure notification
  ## * NOTE: Process this email inline, in case sendbill fails before merchant's run is completed
  my ($data,$custData,$result) = @_;

  if (($data->{'email_choice'} =~ /^(_customer|_both)$/) && ($custData->{'email'} ne '') && ($data->{'installbilling'} ne 'yes')) {
    my %message;
    $message{'To'} = $custData->{'email'};
    if ($data->{'fromemail'} ne '') {
      $message{'From'} = $data->{'fromemail'};
    }
    else {
      $message{'From'} .= $data->{'merchant_email'};
    }
    $message{'Subject'} = "$data->{'company'} - Payment Failure Notification";
    if ($data->{'recmessage'} ne '') {
      my $temprecmessage = $data->{'recmessage'};
      if ($temprecmessage =~ /\[FAILMESSAGE\]/) {
        my $merrmsg = $result->{'MErrMsg'};
        $temprecmessage =~ s/\[FAILMESSAGE\]/$merrmsg/;
      }
      if ($temprecmessage =~ /\[PNP_username\]/) {
        $temprecmessage =~ s/\[PNP_username\]/$custData->{'username'}/;
      }
      if ($temprecmessage =~ /\[PNP_password\]/) {
        $temprecmessage =~ s/\[PNP_password\]/$custData->{'password'}/;
      }
      if ($temprecmessage =~ /\[PNP_company\]/) {
        $temprecmessage =~ s/\[PNP_company\]/$data->{'company'}/;
      }
      $message{'Content'} = $temprecmessage;
    }
    else {
      $message{'Content'} = "An attempt to renew your subscription to $data->{'company'} has failed\n";
      $message{'Content'} .= "because the charge was rejected by your credit card company.  To\n";
      $message{'Content'} .= "continue your subscription to our site please resubscribe with a\n";
      $message{'Content'} .= "different credit card number.\n";
    }
    &_notify($data->{'bill_acct'}, \%message);
  }
}


sub emailMerchantNotification {
  ## Send merchant success/failure notification lists
  my ($data,$resultList) = @_;

  my ($successList, $failureList);
  foreach my $username (sort keys %{$resultList}) {
    my $entry = $resultList->{"$username"};
    if ($entry->{'FinalStatus'} =~ /success|pending/) {
      $successList .= sprintf("%s %s %s %s %d %s\n", $username, $entry->{'name'}, $entry->{'today'}, $entry->{'monthly'}, $entry->{'orderID'}, $entry->{'auth_code'});
    }
    else {
      if ( ($data->{'email_choice'} =~ /(_failure|_merchant|_both)$/) &&
           ( ($data->{'installbilling'} ne 'yes') || ( ($data->{'installbilling'} eq 'yes') && (($entry->{'balance'} eq '') || ($entry->{'balance'} > 0.00)) ) )) {
        $failureList .= sprintf("%s %s %s %s\n", $username, $entry->{'name'}, $entry->{'today'}, $entry->{'monthly'});
      }
    }
  }

  ## send success notification to merchant
  if (($data->{'sendRecNotification'} =~ /(_merchant|_both)$/) && ($successList ne '')) {
    my %message;
    if ($data->{'recnotifemail'} ne '') {
      $message{'To'} = $data->{'recnotifemail'};
    }
    else {
      $message{'To'} = $data->{'merchant_email'};
    }
    $message{'From'} = $data->{'privatelabelemail'};
    $message{'Subject'} = "$data->{'bill_acct'} - $data->{'privatelabelcompany'} Recurring Payment Success Notification\n";
    $message{'Content'} = "$successList";

    print $message{'Content'};
    &_notify($data->{'merchant'}, \%message);
  }

  ## send failure notification to merchant
  if (($data->{'email_choice'} =~ /(_failure|_merchant|_both)$/) && ($failureList ne '')) {
    my %message;
    if ($data->{'recnotifemail'} ne '') {
      $message{'To'} = $data->{'recnotifemail'};
    }
    else {
      $message{'To'} = $data->{'merchant_email'};
    }
    $message{'From'} = $data->{'privatelabelemail'};
    $message{'Subject'} = "$data->{'bill_acct'} - $data->{'privatelabelcompany'} Recurring Payment Failure Notification";
    $message{'Content'} = "$failureList";

    print $message{'Content'};
    &_notify($data->{'merchant'}, \%message);
  }
}

sub _notify {
  ## sends the email notification
  my ($bill_acct, $draft) = @_;

  my $email = new PlugNPay::Email();
  $email->setVersion('legacy');
  $email->setGatewayAccount($bill_acct);
  $email->setTo($draft->{'To'});
  $email->setFrom($draft->{'From'});
  if ($draft->{'Cc'} ne '') {
    $email->setCC($draft->{'Cc'});
  }
  $email->setSubject($draft->{'Subject'});
  $email->setContent($draft->{'Content'});
  $email->setFormat('text');
  $email->send();
}

