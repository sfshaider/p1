#!/bin/env perl

# PURPOSE: - do last attempt to auto bill on their expire date
#          - retry each failed attempt every X days for up to Y days before the expire date
#              Where: 'X' is the frequency (e.g. every 2 days)
#                     'Y' is the duration (e.g. over a 6 day period)

# Last Updated: 01/28/08

# History:
# 07/12/06 - stated design of this script
# 01/29/08 - fixed missing 'use Time::Local' module call

require 5.001;
$|=1;

use lib '/home/p/pay1/perl_lib';
use CGI;
use SHA;
use rsautils;
use mckutils_strict;
use miscutils;
use remote_strict;
use POSIX qw(ceil floor);
use Time::Local;
use PlugNPay::GatewayAccount;
use strict;

# initialize basic values/settings:
my $secs_in_day  = 86400;  # number of seconds in a day
my $frequency = 1; # number of days between each billing attempt
my $duration = 3; # max number of days the the system should cover

# figure out total number of seconds in between each billing attempt
my $total_seconds = $frequency * $secs_in_day;

# figure out how many bill dated occure on that frequency within that duration
my $count_dates = $duration / $frequency;

# figure out what todays date is
my @now = gmtime(time);
my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

my $now_year = $now[5] + 1900;
my $now_month = $now[4] + 1;
my $now_day = $now[3];

# figure out what todays date is in GMT Epoch Seconds
my $now_time = &cal2sec(0,0,0,$now_day,$now_month,$now_year); # today's date in GMT Epoch Seconds

# figure out what the billing dates we want match enddate to are
my @bill_dates = ("$today"); # initialize & define first attempt as todays date

# now get the rest of the billing dates over that frequency & duration
for (my $i = 1; $i <= $count_dates; $i++) {
  my @postbill_date = gmtime($now_time + ($total_seconds * $i)); # figure out next bill date

  # set the next bill date 
  my $charge_date = sprintf("%04d%02d%02d", $postbill_date[5]+1900, $postbill_date[4]+1, $postbill_date[3]);

  # now store the charge date to the list of billing dates to match to.
  push(@bill_dates, $charge_date);
}

my $start_billdate = $bill_dates[0];
my $end_billdate = $bill_dates[$#bill_dates];

my ($db_merchant, $db_username, $db_invoice_no, $db_expire_date, $db_status, $db_lastbilled, $db_lastattempted);

my $dbh = &miscutils::dbhconnect("billpres");

  # now select from the invoice database, all those open bills which are within the date range we are looking for
  my $sth = $dbh->prepare(qq{
     select merchant, username, invoice_no, expire_date, lastbilled, lastattempted 
     from bills2
     where status='open' and expire_date>=? and expire_date<=?
     order by expire_date
    }) or die "Cannot do: $DBI::errstr";
  $sth->execute("$start_billdate", "$end_billdate") or die "Cannot execute: $DBI::errstr";
  my $rv = $sth->bind_columns(undef,\($db_merchant, $db_username, $db_invoice_no, $db_expire_date, $db_status, $db_lastbilled, $db_lastattempted));
  while($sth->fetch) {
    # now see if the expire_date matched once of the billdates generated
    my $continue = 0;
    for (my $i = 0; $i <= $#bill_dates; $i++) {
      if ($db_expire_date == $bill_dates[$i]) {
        $continue = 1;
      }
    }

    if ($continue == 0) {
      # skip to next invoice
      next;
    }

    # now see if we should autopay this bill
    my $sth2 = $dbh->prepare(qq{
        select profileid
        from autopay2
        where username=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$db_username", "$db_merchant") or die "Cannot execute: $DBI::errstr";
    my ($db_profileid) = $sth2->fetchrow;
    $sth2->finish;

    if ($db_profileid ne "") {
      &pay_bill_form($db_merchant, $db_username, $db_profileid, $db_invoice_no);
    }
    else {
      # skip to next invoice
      next;
    }
  }
  $sth->finish;


exit;

sub cal2sec {
  # converts date to seconds (in GMT Epoch Seconds)
  my ($seconds, $minutes, $hours, $day, $month, $year) = @_;

  # $day is day in month (1-31)
  # $month is month in year (1-12)
  # $year is four-digit year e.g., 1967
  # $hours, $minutes and $seconds represent UTC time

  #use Time::Local;

  my $time = &timegm($seconds, $minutes, $hours, $day, $month-1, $year-1900);

  return($time);
}

sub pay_bill_form {
  my ($db_merchant, $db_username, $db_profileid, $db_invoice_no) = @_;

  my ($data, $merchant, $username, $invoice_no, $account_no, $status, $expire_date, $amount, $profileid, $shacardnumber, $cardname, $cardcompany, $cardaddr1, $cardaddr2, $cardcity, $cardstate, $cardzip, $cardcountry, $cardnumber, $exp, $enccardnumber, $length, $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip, $shipcountry, $phone, $fax, $email, $db_item, $db_cost, $db_qty, $db_descr, $accttype, $routingnum, $accountnum, $tax, $shipping, $handling, $discount, $balance, $monthly, $billcycle, $lastbilled, $lastattempted, $merch_company, $merch_status, $merch_cards_allowed, $merch_chkprocessor, $merch_alliance_status, $charge);

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  # get general transaction info
  my $sth = $dbh->prepare(qq{
      select merchant, username, invoice_no, account_no, status, expire_date, amount, tax, shipping, handling, discount, balance, monthly, billcycle, lastbilled, lastattempted
      from bills2
      where merchant=? and username=? and invoice_no=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$db_merchant", "$db_username", "$db_invoice_no") or die "Cannot execute: $DBI::errstr";
  ($merchant, $username, $invoice_no, $account_no, $status, $expire_date, $amount, $tax, $shipping, $handling, $discount, $balance, $monthly, $billcycle, $lastbilled, $lastattempted) = $sth->fetchrow;
  $sth->finish;

  # get billing profile info
  my $sth2 = $dbh->prepare(qq{
      select username, profileid, shacardnumber, cardname, cardcompany, cardaddr1, cardaddr2, cardcity, cardstate, cardzip, cardcountry, cardnumber, exp, enccardnumber, length
      from billing2
      where username=? and profileid=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth2->execute("$db_username", "$db_profileid") or die "Cannot execute: $DBI::errstr";
  ($username, $profileid, $shacardnumber, $cardname, $cardcompany, $cardaddr1, $cardaddr2, $cardcity, $cardstate, $cardzip, $cardcountry, $cardnumber, $exp, $enccardnumber, $length) = $sth2->fetchrow;
  $sth2->finish;

  if ($shacardnumber ne "") {
    $cardnumber = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");

    if ($cardnumber =~ /\d{9} \d/) {
      ($routingnum, $accountnum) = split(/ /, $cardnumber, 2);
      $accttype = "checking";
      $cardnumber = "";
    }
    else {
      $accttype = "";
    }
  }

  # get instant contact info 
  my $sth3 = $dbh->prepare(qq{
      select username, shipname, shipaddr1, shipaddr2, shipcity, shipstate, shipzip, shipcountry, phone, fax, email
      from customer2
      where username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth3->execute("$db_username") or die "Cannot execute: $DBI::errstr";
  ($username, $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip, $shipcountry, $phone, $fax, $email) = $sth3->fetchrow;
  $sth3->finish;

  # get merchant's company name, account status, allowed card types & ach processor info
  my $gatewayAccount = new PlugNPay::GatewayAccount($merchant);
  $merch_company = $gatewayAccount->getCompanyName();
  $merch_status = $gatewayAccount->getStatus();
  $merch_cards_allowed = join(",",@{$gatewayAccount->getAllowedCardTypes()}); 
  $merch_chkprocessor = $gatewayAccount->getCheckProcessor();

  if ($merch_chkprocessor =~ /(alliance)/i){
    my $sth2_pnpmisc = $dbh_pnpmisc->prepare(qq{
        select status
        from alliance
        where username=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2_pnpmisc->execute("$merchant") or die "Cannot execute: $DBI::errstr";
    ($merch_alliance_status) = $sth2_pnpmisc->fetchrow;
    $sth2_pnpmisc->finish;
  }
  $dbh_pnpmisc->disconnect;

  # verify merchant can accept that payment type &/or card type
  if ($merch_status !~ /(live|debug|test)/i) {
    # error: merchant account not active
    $data = "Sorry, $merch_company cannot accept online payments at this time.\n";
    $data .= "<br>Please contact $merch_company directly for payment assistance.\n";
    return $data;
  }

  if ($cardnumber =~ / /) {
    # check for ACH/echeck ability
    my $allow_ach = &detect_ach("$merch_chkprocessor", "$merch_alliance_status"); 
    if ($allow_ach !~ /yes/i) {
      # error: ACH/eCheck not supported
      $data = "Sorry, $merch_company does not accept online check payments at this time.\n";
      $data .= "<br>Please use a credit card to pay this bill.\n";
      return $data;
    }
  }
  else {
    # check for cardtype & find out it's allowed
    my $cardtype = &detect_cardtype("$cardnumber");
    if ($cardtype !~ /($merch_cards_allowed)/) {
      # error: card type not supported
      $data = "Sorry, $merch_company does not accept this card type at this time.\n";
      $data .= "<br>Please use a different card type to pay this bill.\n";
      return $data;
    }
  }

  ## see if we need to charge an installment fee
  if (($billcycle > 0) && ($balance > 0) && ($monthly > 0)) {
    ## if we need to charge raminder or full installment fee
    if ($monthly > $balance) {
      # charge remainder of balance 
      $charge = $balance;
      #$charge_type = "installment"
    }
    else {
      # charge full installment fee
      $charge = $monthly;
      #$charge_type = "installment";
    }
  }
  ## since we are not charging the monthly fee, see if we need to charge the balance on the invoice
  elsif ($balance > 0) { 
    # charge the balance on an invoice
    $charge = $balance;
    #$charge_type = "balance";
  }
  # since we are not charging a balance or an installment payment payment, charge the full amount of the bill
  else {
    # charge the full amount of the bill
    $charge = $amount;
    #$charge_type = "full_amount";
  }

  # do API's auth here
  #use remote_strict;

  my ($orderid, $dummy1, $dummy2) = &miscutils::genorderid();

  my @array = (
    "publisher-name","$merchant",
    "mode","auth",
    "card-amount","$charge",
    "tax","$tax",
    "shipping","$shipping",
    "handling","$handling",
    "discount","$discount",
    "orderID","$orderid",
    "ipaddress","$ENV{'REMOTE_ADDR'}",
    "acct_code","$account_no",
    "acct_code2","$invoice_no",
    "acct_code3","billpay",
    "card-name","$cardname",
    "card-address1","$cardaddr1",
    "card-address2","$cardaddr2",
    "card-city","$cardcity",
    "card-state","$cardstate",
    "card-zip","$cardzip",
    "card-country","$cardcountry",
    "shipinfo","1",
    "shipname","$shipname",
    "address1","$shipaddr1",
    "address2","$shipaddr2",
    "city","$shipcity",
    "state","$shipstate",
    "zip","$shipzip",
    "country","$shipcountry",
    "email","$email",
    "phone","$phone",
    "fax","$fax"
  );

  if ($accttype =~ /checking|savings/i) {
    push (@array, "accttype", "$accttype", "routingnum", "$routingnum", "accountnum", "$accountnum");
  }
  else {
    push (@array, "card-number", "$cardnumber", "card-exp", "$exp");
  }

  my $cnt = 0;
  my $sth4 = $dbh->prepare(qq{
      select item, cost, qty, descr
      from billdetails2
      where merchant=? and username=? and invoice_no=?
      order by item
    }) or die "Cannot do: $DBI::errstr";
  $sth4->execute("$db_merchant", "$db_username", "$db_invoice_no") or die "Cannot execute: $DBI::errstr";
  my $rv = $sth4->bind_columns(undef,\($db_item, $db_cost, $db_qty, $db_descr));
  while($sth4->fetch) {
    if (($db_item ne "") && ($db_cost > 0) && ($db_qty > 0) && ($db_descr ne "")) {
      $cnt = $cnt + 1;
      $db_cost = sprintf("%0.2f", $db_cost);
      push (@array, "item$cnt", "$db_item", "cost$cnt", "$db_cost", "quantity$cnt", "$db_qty", "description$cnt", "$db_descr");
    }
  }
  $sth4->finish;

  if ($cnt > 0) {
    push (@array, "receipt_type", "itemized", "easycart", "1");
  }
  else {
    push (@array, "receipt_type", "simple");
  }

  my $payment = mckutils->new(@array);
  my %result = $payment->purchase("auth");
  $result{'auth-code'} = substr($result{'auth-code'},0,6);
  $payment->database();
  %remote::query = (%remote::query,%mckutils::query,%result);
  $payment->email();

  # record payment attempt
  my $sth5 = $dbh->prepare(qq{
      insert into billingstatus2 
      (orderid, merchant, username, profileid, invoice_no, account_no, trans_date, amount, descr, result, billusername)
      values (?,?,?,?,?,?,?,?,?,?,?)
    }) or die "Cannot prepare: $DBI::errstr";
  $sth5->execute("$orderid", "$db_merchant", "$db_username", "$profileid", "$invoice_no", "$account_no", "$today", "$charge", "$remote::query{'descr'}", "$remote::query{'result'}", "$merchant") or die "Cannot execute: $DBI::errstr";
  $sth5->finish;

  &record_history("$db_username", "$profileid", "pay_bill", "Bill Payment Attempted - $remote::query{'result'}");

  if ($result{'FinalStatus'} =~ /success/i) {
    # update transaction status

    # adjust balance, if needed
    if ($balance > 0) {
      $balance = $balance - $charge;
      if ($balance < 0) {
        $balance = 0.00;
      }
    }

    # extend expire_date, if needed
    if (($billcycle > 0) && ($balance > 0) && ($monthly > 0)) {
      # figure out what the new expire date will be
      my $expire_year  = substr($expire_date, 0, 4);
      my $expire_month = substr($expire_date, 4, 2);
      my $expire_day   = substr($expire_date, 6, 2);

      $expire_month = $expire_month + $billcycle;
      $expire_month = ceil($expire_month);

      if ($expire_month > 12) {
        my $c = $expire_month % 12;
        $expire_month = $expire_month - ($c * 12);
        $expire_year = $expire_year + $c;
      }

      $expire_date = sprintf("%04d%02d%02d", $expire_year, $expire_month, $expire_day);
      $remote::query{'expire_date'} = $expire_date;
    }

    if ($balance > 0) {
      $status = "open";
      $remote::query{'balance'} = $balance;
    }
    else {
      $status = "paid";
    }

    my $sth2 = $dbh->prepare(qq{
        update bills2
        set status=?, orderid=?, lastbilled=?, lastattempted=?, balance=?, expire_date=?
        where merchant=? and username=? and invoice_no=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$status", "$remote::query{'orderID'}", "$today", "$today", "$balance", "$expire_date", "$db_merchant", "$db_username", "$invoice_no") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    $data = "Your payment was approved.\n";
    $data .= "<br>OrderID: $remote::query{'orderID'}\n";

#     $data = &thankyou_template(%remote::query);
  }
  elsif ($result{'FinalStatus'} =~ /badcard/i) {
    # don't do anything - leave transaction as is
    my $sth3 = $dbh->prepare(qq{
        update bills2
        set lastattempted=?
        where merchant=? and username=? and invoice_no=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth3->execute("$today", "$db_merchant", "$db_username", "$invoice_no") or die "Cannot execute: $DBI::errstr";
    $sth3->finish;

    $data = "Your payment was declined.\n";
    $data .= "<br>Reason: $result{'MErrMsg'}\n";
  }
  elsif ($result{'FinalStatus'} =~ /problem/i) {
    # don't do anything - leave transaction as is
    my $sth4 = $dbh->prepare(qq{
        update bills2
        set lastattempted=?
        where merchant=? and username=? and invoice_no=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth4->execute("$today", "$db_merchant", "$db_username", "$invoice_no") or die "Cannot execute: $DBI::errstr";
    $sth4->finish;

    $data = "Your payment resulted in a problem.  Please try again later.\n";
    $data .= "<br>Reason: $result{'MErrMsg'}\n";
  }
  elsif ($result{'FinalStatus'} =~ /fraud/i) {
    # don't do anything - leave transaction as is
    my $sth5 = $dbh->prepare(qq{
        update bills2
        set lastattempted=?
        where merchant=? and username=? and invoice_no=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth5->execute("$today", "$db_merchant", "$db_username", "$invoice_no") or die "Cannot execute: $DBI::errstr";
    $sth5->finish;

    $data = "Your payment was declined.\n";
    $data .= "<br>Reason: $result{'MErrMsg'}\n";
  }
  else {
    # Error: unknown FinalStatus response
    $data .= "Error: Unknown FinalStatus response.\n";
    $data .= "<br>Please contact Technical Support for assistance.\n";
    $data .= sprintf("<br>Date: %02d\/%02d\/04d\n", substr($today,4,2), substr($today,6,2), substr($today,0,4));
    $data .= "<br>OrderID: $remote::query{'orderID'}\n";
    $data .= "<br>Amount: $remote::query{'card-amount'}\n";

#    foreach my $key (sort keys %result) {
#      $data .= "<br>RESULT: $key = \'$result{$key}\'\n";
#    }
  }

  return $data;
}

