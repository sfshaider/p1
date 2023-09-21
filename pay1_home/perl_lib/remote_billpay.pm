#!/usr/local/bin/perl

## Required by remote_strict.pm for billing presentment specific functions

require 5.001;

use pnp_environment;
use DBI;
use rsautils;
use miscutils;
use mckutils_strict;
use sysutils;
use POSIX qw(ceil floor);
use billpay_language;
use billpay_merchadmin;
use PlugNPay::CardData;
use PlugNPay::Transaction::TransactionProcessor;
use strict;

sub count_invoices {
  # counts number of invoices in billpay database, based on conditions specified
  my (%query) = %remote::query;

  my %result = ();

  if ($query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  if ($query{'status'} !~ /^(open|closed|hidden|merged|paid|expired|unpaid)$/) {
    $query{'status'} = "";
  }

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);


  my $qstr = "select count(invoice_no)";
  $qstr .= " from bills2";
  $qstr .= " where merchant=?";
  my @placeholder = ("$query{'merchant'}");

  if ($query{'status'} eq "open") {
    $qstr .= " and expire_date>? and (status is NULL or status='' or status='open')";
    push(@placeholder, "$today");
  }
  elsif ($query{'status'} eq "closed") {
    $qstr .= " and status='closed'";
  }
  elsif ($query{'status'} eq "merged") {
    $qstr .= " and status='merged'";
  }
  elsif ($query{'status'} eq "paid") {
    $qstr .= " and status='paid'";
  }
  elsif ($query{'status'} eq "hidden") {
    $qstr .= " and status='hidden'";
  }
  elsif ($query{'status'} eq "expired") {
    $qstr .= " and expire_date<=? and (status is NULL or status='' or status='open')";
    push(@placeholder, "$today");
  }
  elsif ($query{'status'} eq "unpaid") {
    $query{'status'} = "open";
    $qstr .= " and status=? and expire_date>? and (balance>0 or orderid=?)";
    push(@placeholder, "$query{'status'}", "$today", "");
  }

  my $dbh = &miscutils::dbhconnect("billpres");
  my $sth = $dbh->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  $result{'TranCount'} = sprintf("%01d", $count);

  if ($result{'TranCount'} == 0) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
    $result{'resp-code'} = "PXX";
  }
  else {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = sprintf("There are %d matching invoices.", $count);
    $result{'resp-code'} = "P00";
  }

  return %result;
}

sub count_clients {
  # counts number of client contacts in billpay database
  my (%query) = %remote::query;

  my %result = ();

  if ($query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my $dbh = &miscutils::dbhconnect("billpres");
  my $sth = $dbh->prepare(qq{
      select count(username)
      from client_contact
      where merchant=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$query{'merchant'}") or die "Can't execute: $DBI::errstr";
  my ($count) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  $result{'TranCount'} = sprintf("%01d", $count);

  if ($result{'TranCount'} == 0) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
    $result{'resp-code'} = "PXX";
  }
  else {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = sprintf("There are %d clients currently stored.", $count);
    $result{'resp-code'} = "P00";
  }

  return %result;
}

sub list_clients {
  # gets list of client email contacts in billpay database
  my (%query) = %remote::query;

  my %result = ();

  if ($query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my $idx = 0;

  my $dbh = &miscutils::dbhconnect("billpres");
  my $sth = $dbh->prepare(qq{
      select username, clientcompany, clientname, clientid, alias
      from client_contact
      where merchant=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$query{'merchant'}") or die "Can't execute: $DBI::errstr";
  while (my $data = $sth->fetchrow_hashref()) {
    $idx = sprintf("%05d" ,$idx);
    foreach my $key (keys %$data) {
      # write aXXXXX result entry
      my $a = $data->{$key};
      $a =~ s/(\W)/'%' . unpack("H2",$1)/ge;
      if ($key eq "username") { $key = "email"; }
      $result{"a$idx"} .= "$key\=$a\&";
    }
    chop $result{"a$idx"};
    $idx++;
  }
  $sth->finish;
  $dbh->disconnect;

  $result{'TranCount'} = sprintf("%01d", $idx);

  if ($result{'TranCount'} == 0) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
    $result{'resp-code'} = "PXX";
  }
  else {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = sprintf("There are %d clients currently listed.", $idx);
    $result{'resp-code'} = "P00";
  }

  return %result;
}

sub update_client {
  # add/update client contact info in billpay database
  my (%query) = %remote::query;

  my %result = ();

  if ($query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  # create placeholder email address for when unknown email feature is enabled; but now make account number required.
  if (($remote::feature{'billpay_unknown_email'} eq "yes") && ($query{'email'} eq "") && ($query{'account_no'} ne "")) {
    $query{'account_no'} =~ s/[^a-zA-Z0-9\_\-\ ]//g;
    if ($query{'account_no'} =~ /\w/) {
      $query{'email'} = sprintf("%s\@%s\.%s", $query{'account_no'}, $query{'merchant'}, "pnp");
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Invalid Account Number";
      $result{'resp-code'} = "PXX";
      return %result;
    }
  }

  # do data filtering & other checks
  # login email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $query{'email'} = lc($query{'email'});

  # validiate email format
  my $position = index($query{'email'},"\@");
  my $position1 = rindex($query{'email'},"\.");
  my $elength  = length($query{'email'});
  my $pos1 = $elength - $position1;
  if (($position < 1)
     || ($position1 < $position)
     || ($position1 >= $elength - 2)
     || ($elength < 5)
     || ($position > $elength - 5)
   ) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Invalid Email Address";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  if (exists $query{'clientname'}) {
    $query{'clientname'} =~ s/[^a-zA-Z0-9\ \'\.]/ /g;
  }
  if (exists $query{'clientcompany'}) {
    $query{'clientcompany'} =~ s/[^a-zA-Z0-9\ \'\.]/ /g;
  }
  if (exists $query{'clientaddr1'}) {
    $query{'clientaddr1'} =~ s/[\r\n]//;
    $query{'clientaddr1'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if (exists $query{'clientaddr2'}) {
    $query{'clientaddr2'} =~ s/[\r\n]//;
    $query{'clientaddr2'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if (exists $query{'clientcity'}) {
    $query{'clientcity'} =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;
  }
  if (exists $query{'clientstate'}) {
    $query{'clientstate'} =~ s/[^a-zA-Z]//g;
    $query{'clientstate'} = substr($query{'clientstate'},0,2);
    $query{'clientstate'} = uc($query{'clientstate'});
  }
  if (exists $query{'clientzip'}) {
    $query{'clientzip'} =~ s/[^a-zA-Z\'0-9 ]/ /g;
  }
  if (exists $query{'clientcountry'}) {
    $query{'clientcountry'} =~ s/[^a-zA-Z]//g;
    $query{'clientcountry'} = substr($query{'clientcountry'},0,2);
    $query{'clientcountry'} = uc($query{'clientcountry'});
  }
  if (exists $query{'clientid'}) {
    $query{'clientid'} =~ s/\W//g;
    $query{'clientid'} = lc($query{'clientid'});
  }
  if (exists $query{'alias'}) {
    $query{'alias'} =~ s/[^a-zA-Z0-9]//g;
    $query{'alias'} = lc($query{'alias'});
  }

  if ($query{'consolidate'} ne "yes") {
    $query{'consolidate'} = "";
  }

  my $dbh = &miscutils::dbhconnect("billpres");

  # check for clientID existance
  if ($query{'clientid'} ne "") {
    my $sth0a = $dbh->prepare(qq{
        select username, clientname, clientcompany, clientid, alias
        from client_contact
        where clientid=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    my $rc = $sth0a->execute("$query{'clientid'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    my ($db_username, $db_clientname, $db_clientcompany, $db_clientid, $db_alias) = $sth0a->fetchrow;
    $sth0a->finish;

    if (($query{'mode'} eq "add_client") && ($db_username ne "")) {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Client already exists.";
      $result{'resp-code'} = "PXX";
      return %result;
    }

    if (($rc >= 1) && ($query{'email'} ne "$db_username")) {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "ClientID already in use by client";
      if (($db_clientname ne "") || ($db_clientcompany ne "")) {
        $result{'MErrMsg'} .= "$db_clientcompany - $db_clientname";
      }
      else {
        $result{'MErrMsg'} .= "email: $db_username";
      }
      $result{'resp-code'} = "PXX";
      return %result;
    }
  }

  # start by checking for client existance
  my $sth1a = $dbh->prepare(qq{
      select username
      from client_contact
      where username=? and merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  my $rc = $sth1a->execute("$query{'email'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my ($db_username) = $sth1a->fetchrow;
  $sth1a->finish;

 if ($db_username eq "$query{'email'}") {
    # if match was found, allow the update to happen
    my $sth2a = $dbh->prepare(qq{
        update client_contact
        set clientname=?, clientcompany=?, clientaddr1=?, clientaddr2=?, clientcity=?, clientstate=?, clientzip=?, clientcountry=?, clientid=?, alias=?, consolidate=?
        where username=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2a->execute("$query{'clientname'}", "$query{'clientcompany'}", "$query{'clientaddr1'}", "$query{'clientaddr2'}", "$query{'clientcity'}", "$query{'clientstate'}", "$query{'clientzip'}", "$query{'clientcountry'}", "$query{'clientid'}", "$query{'alias'}", "$query{'consolidate'}", "$query{'email'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    $sth2a->finish;

    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = "Client has been updated in your contact list.";
    $result{'resp-code'} = "P00";
  }
  else {
    # if no match was found, allow the insert to happen
    my $sth2a = $dbh->prepare(qq{
        insert into client_contact
        (merchant, username, clientname, clientcompany, clientaddr1, clientaddr2, clientcity, clientstate, clientzip, clientcountry, clientid, alias, consolidate)
        values (?,?,?,?,?,?,?,?,?,?,?,?,?)
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2a->execute("$query{'merchant'}", "$query{'email'}", "$query{'clientname'}", "$query{'clientcompany'}", "$query{'clientaddr1'}", "$query{'clientaddr2'}", "$query{'clientcity'}", "$query{'clientstate'}", "$query{'clientzip'}", "$query{'clientcountry'}", "$query{'clientid'}", "$query{'alias'}", "$query{'consolidate'}") or die "Cannot execute: $DBI::errstr";
    $sth2a->finish;

    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = "Client has been added to your contact list.";
    $result{'resp-code'} = "P00";
  }

  $dbh->disconnect;

  return %result;
}

sub query_client {
  # query client contacts in billpay database
  my (%query) = %remote::query;

  my %result = ();

  if ($query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my $idx = 0;

  my @placeholder;

  my $qstr = "select *";
  $qstr .= " from client_contact";
  $qstr .= " where merchant=?";
  push(@placeholder, "$query{'merchant'}");

  # create placeholder email address for when unknown email feature is enabled; but now make account number required.
  if (($remote::feature{'billpay_unknown_email'} eq "yes") && ($query{'email'} eq "") && ($query{'account_no'} ne "")) {
    $query{'account_no'} =~ s/[^a-zA-Z0-9\_\-\ ]//g;
    if ($query{'account_no'} =~ /\w/) {
      $query{'email'} = sprintf("%s\@%s\.%s", $query{'account_no'}, $query{'merchant'}, "pnp");
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Invalid Account Number";
      $result{'resp-code'} = "PXX";
      return %result;
    }
  }

  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $query{'email'} = lc($query{'email'});
  if ($query{'email'} ne "") {
    if ($query{'fuzzyflg'} == 1) {
      $qstr .= " and username like ?";
      push(@placeholder, "\%$query{'email'}\%");
    }
    else {
      $qstr .= " and username=?";
      push(@placeholder, "$query{'email'}");
    }
  }

  my @field_list = ('clientcompany', 'clientname', 'clientaddr1', 'clientaddr2', 'clientstate', 'clientzip', 'clientcountry', 'clientid', 'alias');
  for (my $i = 0; $i <= $#field_list; $i++) {
    $query{$field_list[$i]} =~ s/[\r\n]//;
    $query{$field_list[$i]} =~ s/[^a-zA-Z0-9\_\.\/\@\:\-\&\ \#\'\,]//g;

    if ($query{$field_list[$i]} ne "") {
      if ($query{'fuzzyflg'} == 1) {
        $qstr .= " and $field_list[$i] like ?";
        push(@placeholder, "\%$query{$field_list[$i]}\%");
      }
      else {
        $qstr .= " and $field_list[$i]=?";
        push(@placeholder, "$query{$field_list[$i]}");
      }
    }
  }

  $qstr .= " order by username";

  my $dbh = &miscutils::dbhconnect("billpres");
  my $sth = $dbh->prepare(qq{ $qstr }) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't execute: $DBI::errstr";
  while (my $data = $sth->fetchrow_hashref()) {
    $idx = sprintf("%05d" ,$idx);
    foreach my $key (keys %$data) {
      # write aXXXXX result entry
      my $a = $data->{$key};
      $a =~ s/(\W)/'%' . unpack("H2",$1)/ge;
      if ($key eq "username") { $key = "email"; }
      $result{"a$idx"} .= "$key\=$a\&";
    }
    chop $result{"a$idx"};
    $idx++;
  }
  $sth->finish;
  $dbh->disconnect;

  $result{'TranCount'} = sprintf("%01d", $idx);

  if ($result{'TranCount'} == 0) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
    $result{'resp-code'} = "PXX";
  }
  else {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = sprintf("There are %d clients currently listed.", $idx);
    $result{'resp-code'} = "P00";
  }

  return %result;
}

sub delete_client {
  # remove specific client's contact info from billpay database.
  my (%query) = %remote::query;

  my %result = ();

  if ($query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  # do data filtering & other checks
  # email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $query{'email'} = lc($query{'email'});

  # validiate email format
  my $position = index($query{'email'},"\@");
  my $position1 = rindex($query{'email'},"\.");
  my $elength  = length($query{'email'});
  my $pos1 = $elength - $position1;
  if (($position < 1)
     || ($position1 < $position)
     || ($position1 >= $elength - 2)
     || ($elength < 5)
     || ($position > $elength - 5)
   ) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Invalid Email Address";
    $result{'resp-code'} = "PXX";
    return %result;
  }


  my $dbh = &miscutils::dbhconnect("billpres");

  my $sth = $dbh->prepare(qq{
      delete from client_contact
      where username=? and merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$query{'email'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my ($test) = $sth->finish;

  if (($test ne "") && ($query{'alldata'} eq "yes")) {
    my $sth = $dbh->prepare(qq{
        delete from bills2
        where username=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth->execute("$query{'email'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    my ($test) = $sth->finish;

    my $sth2 = $dbh->prepare(qq{
        delete from billdetails2
        where username=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$query{'email'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;
  }

  $dbh->disconnect;

  if ($test ne "") {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = "Client $query{'email'} has been removed from the database.";
    $result{'resp-code'} = "P00";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Client $query{'email'} does not exist in the database.";
    $result{'resp-code'} = "PXX";
  }

  return %result;
}

sub upload_invoice {
  my (%query) = %remote::query;

  my (%result, $errvar);
  my $filelimit = 5000;
  my ($date,$time) = &miscutils::gendatetime_only();

  my $path_webtxt = &pnp_environment::get('PNP_WEB_TXT');
  my $base_path = "$path_webtxt/admin/billpay/data/";

  if ($remote::query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my @required = ('batchid','num-txns');
  foreach my $var (@required) {
    $remote::query{$var} =~ s/[^a-zA-Z0-9]//g;
    if ($remote::query{$var} eq "") {
      $errvar .= "$var: ";
    }
  }

  if ($errvar ne "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "The following variables were missing or were non-numeric: $errvar";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my $filename = $remote::query{'merchant'} . "_" . $date . "_" . $remote::query{'batchid'} . "\.txt";
  my $filepath = $base_path . $filename;

  # URL decode file data
  $remote::query{'data'} =~ tr/+/ /;
  $remote::query{'data'} =~ s/%([a-fA-F0-9]{2,2})/chr(hex($1))/eg;
  $remote::query{'data'} =~ s/<!--(.|\n)*-->//g;

  $remote::query{'data'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\r\n\t \,\!]/x/g;
  my @data = split(/\r\n|\n/,$remote::query{'data'});
  if (@data > $filelimit) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "File exceeds maximum transaction limit of $filelimit.";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  if (($remote::query{'overwrite'} ne "yes") && (-e $filepath)) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "A file with the same Batch ID already exists and Overwrite is not enabled.";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my $trn_cnt = 0;

  $filepath =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
  &sysutils::filelog("write",">$filepath");
  open(OUTFILE,">$filepath");
  foreach my $line (@data) {
    if ($line ne "") {
      if ($line !~ /^(\!BATCH)/i) {
        $trn_cnt++;
      }
      #print "LINE:$trn_cnt:$line: <br>\n";
      print OUTFILE "$line\n";
    }
  }
  close OUTFILE;

  # force 666 file permissions - to ensure files cannot be executed
  chmod(0666, "$filepath");

  delete $remote::query{'data'};

  # load language data
  my $billpay_language = new billpay_language(%query);

  # initialize billpay_merchadmin
  my @array2 = %query;
  my $billpay_merchadmin = billpay_merchadmin->new(@array2);

  if ((-e $filepath) && (-s $filepath) && (-T $filepath)) {
    if ($remote::query{'num-txns'} == $trn_cnt) {

      %remote::count = (); # hold tally of invoices which are added/updated/rejected

      if ($remote::query{'filetype'} eq "baystate") {
        $remote::dbh = &miscutils::dbhconnect("billpres");
        %result = &import_invoices_baystate("$base_path", "$filename", "$remote::query{'email_cust'}", "$remote::query{'merch_company'}", "$remote::query{'overwrite'}", "$remote::query{'express_pay'}");
        $remote::dbh->disconnect;
      }
      else {
        $remote::dbh = &miscutils::dbhconnect("billpres");
        %result = &import_invoices("$base_path", "$filename", "$remote::query{'email_cust'}", "$remote::query{'merch_company'}", "$remote::query{'overwrite'}", "$remote::query{'express_pay'}");
        $remote::dbh->disconnect;
      }

      # apply count tally results
      foreach my $key (sort keys %remote::count) {
        $result{"$key"} = sprintf ("%01d", $remote::count{$key});
      }

      $result{'FinalStatus'} = "success";
      $result{'aux-msg'} =  "Invoice Batch uploaded successfully.";
      $result{'resp-code'} = "P00";
      #$result{'num-txns'} = $remote::query{'num-txns'};
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Transaction count mismatch. $trn_cnt:$remote::query{'num-txns'}";
      $result{'resp-code'} = "PXX";
    }
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "There was a problem uploading your invoice batch please contact support.";
    if (!-T $filepath) {
      $result{'MErrMsg'} .= " File is not a text file.";
    }
    $result{'resp-code'} = "PXX";
    unlink $filepath;
  }

  return %result;
}

sub import_invoices {
  # this is the import function for billpay specific invoice upload files
  my ($filepath, $filename, $email_cust, $merch_company, $overwrite, $express_pay) = @_;

  my @header;
  my %header;

  # assign unique starting invoice_no, to be used later if necessary
  my @now = gmtime(time);
  my $invoice_no = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0], 00000);
  #sleep(2);

  my $idx = 0;
  my %result;

  # open database file for reading
  my $filteredname = &sysutils::filefilter("$filepath","$filename") or die "FileFilter Rejection";
  &sysutils::filelog("read","$filteredname");
  open(INFILE, "$filteredname") or die "Cannot open $filename for reading. $!";

  # read file into memory
  while(<INFILE>) {
    my $theline = $_;
    chop $theline;

    my %row_data;
    $row_data{'express_pay'} = $express_pay;

    # find out 1st letter
    my $letter = substr($theline, 0, 1);
    #print "LETTER: $letter \n";

    if ($letter eq "!") {
      # if 1st letter is a "!" then find out header and put the values in an array
      @header = split(/\t/, $theline); # grab contents of header
      $header[0] =~ s/\!//g; # remove "!" from first character
      $header[$#header] =~ s/\s//g; # remove white space characters
      for (my $a = 0; $a <= $#header; $a++) {
        $header[$a] =~ s/^\s+//g; # remove leading whitespace
        $header[$a] =~ s/\s+$//g; # remove trailing whitespace
      }
    }
    else {
      my @temp = split(/\t/, $theline);  # grab contents of row
      for (my $a = 0; $a <= $#header; $a++) {
        $temp[$a] =~ s/^\s+//g; # remove leading whitespace
        $temp[$a] =~ s/\s+$//g; # remove trailing whitespace
        # put row's data into row_data hash
        $row_data{"$header[$a]"} = $temp[$a];
        #print "<!-- row_data -- \'$header[$a]\' -- \'$temp[$a]\'>\n";
      }

      if ($row_data{'BATCH'} eq "billpay_invoice") {
        delete $row_data{'BATCH'};

        # assign unique invoice_no, if when not already defined
        if ($row_data{'invoice_no'} eq "") {
          $row_data{'invoice_no'} = $invoice_no;
          $invoice_no = $invoice_no + 1; # incriment invoice number for next order
        }

        # pass on certain fields
        $row_data{'merchant'} = $remote::query{'merchant'};
        $row_data{'email_cust'} = $email_cust;
        $row_data{'merch_company'} = $merch_company;
        $row_data{'overwrite'} = $overwrite;

        # add invoice to database
        ($row_data{'FinalStatus'}, $row_data{'MErrMsg'}) = &update_invoice(%row_data);

        # put invoice's response data in result aXXXXX field
        $idx = sprintf("%05d" ,$idx);
        foreach my $key (keys %row_data) {
          #$key =~ tr/A-Z/a-z/;

          # write aXXXXX result entry
          my $a = $row_data{$key};
          $a =~ s/(\W)/'%' . unpack("H2",$1)/ge;
          if ($key eq "username") { $key = "email"; }
          $result{"a$idx"} .= "$key\=$a\&";
        }
        chop $result{"a$idx"};
        $idx++;
      }
    }
  }
  close(INFILE);

  return %result;
}

sub import_invoices_baystate {
  # this is the import function for baystate QB specific invoice upload files
  my ($filepath, $filename, $email_cust, $merch_company, $overwrite, $express_pay) = @_;

  my @header;
  my %header;

  # assign unique starting invoice_no, to be used later if necessary
  my @now = gmtime(time);
  my $invoice_no = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0], 00000);
  #sleep(2);

  my $idx = 0;
  my %result;

  # open database file for reading
  my $filteredname = &sysutils::filefilter("$filepath","$filename") or die "FileFilter Rejection";
  &sysutils::filelog("read","$filteredname");
  open(INFILE, "$filteredname") or die "Cannot open $filename for reading. $!";

  # first line in the file is the header line, so read it & create the header
  my $theline = <INFILE>;
  chop $theline;
  $theline =~ s/[^a-zA-Z0-9\_\-\t]//g; # remove anything that is not alphanumeric, dash, underscore or tab character
  @header = split(/\t/, $theline); # grab contents of header
  $header[$#header] =~ s/\s//g; # remove white space characters

  my %HoH = (); # this is a hash of hashes, which holds all the merged QB invoice data.
  my %HoH_count; # this a hash that track of how many items are each QB invoice, so we can incriment X in the itemX, costX, qtyX & descrX as we go along.

  # read rest of file into memory
  while(<INFILE>) {
    my $theline = $_;
    chop $theline;

    my %row_data;

    my @temp = split(/\t/, $theline);  # grab contents of row
    for (my $a = 0; $a <= $#header; $a++) {
      $temp[$a] =~ s/^\s+//g; # remove leading whitespace
      $temp[$a] =~ s/\s+$//g; # remove trailing whitespace
      # put row's data into row_data hash
      $row_data{"$header[$a]"} = $temp[$a];
      #print "<!-- row_data -- \'$header[$a]\' -- \'$temp[$a]\'>\n";
    }

    # start building the billpay invoices here
    # NOTE: commented $HoH lines below are listed for possible future usage, but are not needed at this time for basic invoice usage)
    my $invoice = $row_data{'TxnId'};

    if ($HoH{"$invoice"}->{'invoice_no'} !~ /\w/) {
      $HoH{"$invoice"}{'invoice_no'} = $row_data{'TxnId'};

      my ($customer, $project) = split(/\:/, $row_data{'Customer'}, 2); # example: "customer_last, customer_first:project_name"
      #my ($customer_last, $customer_first) = split(/\, /, $customer, 2);
      #$HoH{"$invoice"}{'clientname'} = "$customer_first $customer_last";
      $HoH{"$invoice"}{'account_no'} = "$project";

      $HoH{"$invoice"}{'email'} = &billpay_merchadmin::get_client_email("$row_data{'CustomerAccountNumber'}"); # lookup email address, using clientID number

      my @enter_date = split(/\//, $row_data{'TxnDate'}, 3); # example: "01/31/2008"
      $HoH{"$invoice"}{'enter_date'} = sprintf("%04d%02d%02d", $enter_date[2], $enter_date[0], $enter_date[1]);

      #$HoH{"$invoice"}{''} = $row_data{'RefNumber'};
      #$HoH{"$invoice"}{''} = $row_data{'Class'};
      #$HoH{"$invoice"}{''} = $row_data{'ARAccount'};

      $HoH{"$invoice"}{'balance'} = $row_data{'BalanceRemaining'};
      $HoH{"$invoice"}{'percent'} = "";
      $HoH{"$invoice"}{'monthly'} = "";
      $HoH{"$invoice"}{'billcycle'} = "0";

      $HoH{"$invoice"}{'clientname'} = $row_data{'BillToLine1'};
      $HoH{"$invoice"}{'clientcompany'} = $row_data{'BillToLine2'};
      $HoH{"$invoice"}{'clientaddr1'} = $row_data{'BillToLine3'};
      $HoH{"$invoice"}{'clientaddr2'} = $row_data{'BillToLine4'};
      $HoH{"$invoice"}{'clientcity'} = $row_data{'BillToCity'};
      $HoH{"$invoice"}{'clientstate'} = $row_data{'BillToState'};
      $HoH{"$invoice"}{'clientzip'} = $row_data{'BillToPostalCode'};
      $HoH{"$invoice"}{'clientcountry'} = $row_data{'BillToCountry'};

      #$HoH{"$invoice"}{''} = $row_data{'ShipToLine1'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToLine2'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToLine3'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToLine4'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToCity'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToState'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToPostalCode'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipToCountry'};

      #$HoH{"$invoice"}{''} = $row_data{'PONumber'};
      #$HoH{"$invoice"}{''} = $row_data{'Terms'};
      #$HoH{"$invoice"}{''} = $row_data{'SalesRep'};
      #$HoH{"$invoice"}{''} = $row_data{'ShipDate'};

      my @expire_date = split(/\//, $row_data{'DueDate'}, 3); # example: "01/31/2008"
      $HoH{"$invoice"}{'expire_date'} = sprintf("%04d%02d%02d", $expire_date[2], $expire_date[0], $expire_date[1]);

      #$HoH{"$invoice"}{''} = $row_data{'ShipMethod'};
      #$HoH{"$invoice"}{''} = $row_data{'FOB'};
      #$HoH{"$invoice"}{''} = $row_data{'Class'};
      $HoH{"$invoice"}{'private_notes'} = $row_data{'Memo'};

      #$HoH{"$invoice"}{''} = $row_data{'SalesTaxCode'};
      #$HoH{"$invoice"}{''} = $row_data{'SalesTaxItem'};
      #$HoH{"$invoice"}{''} = $row_data{'SalesTaxPercentage'};

      $row_data{'SalesTaxTotal'} =~ s/[^0-9\.]//g;
      $HoH{"$invoice"}{'tax'} = sprintf("%0.02f", $row_data{'SalesTaxTotal'});

      #$HoH{"$invoice"}{''} = $row_data{'Other'};
      #$HoH{"$invoice"}{''} = $row_data{'TxnLineServiceDate'};
    }

    # incriment item X counter for the given TxnID
    $HoH_count{"$invoice"} = $HoH_count{"$invoice"} + 1;
    my $x = $HoH_count{"$invoice"};

    $row_data{'TxnLineQuantity'} =~ s/[^0-9\.]//g;
    $HoH{"$invoice"}{"qty$x"} = $row_data{'TxnLineQuantity'};

    $row_data{'TxnLineItem'} =~ s/[^a-zA-Z_0-9\.\_\-]//g;
    $HoH{"$invoice"}{"item$x"} = $row_data{'TxnLineItem'};

    $row_data{'TxnLineDescription'} =~ s/[^a-zA-Z_0-9\ \_\-\.\,\+\/\(\)]//g;
    $HoH{"$invoice"}{"descr$x"} = $row_data{'TxnLineDescription'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineOther1'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineOther2'};

    $row_data{'TxnLineCost'} =~ s/[^0-9\.\-]//g;
    $HoH{"$invoice"}{"cost$x"} = sprintf("%0.02f", $row_data{'TxnLineCost'});

    $row_data{'TxnLineAmount'} =~ s/[^0-9\.\-]//g;
    $HoH{"$invoice"}{'amount'} = sprintf("%0.02f", $HoH{"$invoice"}->{'amount'} + $row_data{'TxnLineAmount'});

    #$HoH{"$invoice"}{''} = $row_data{'TxnLineSalesTaxCode'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineClass'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineTaxCode'};
    #$HoH{"$invoice"}{''} = $row_data{'TxnLineCDNTaxCode'};

    #print "<br>KEY: $HoH{$invoice}->{'invoice_no'}, Amount: $HoH{$invoice}->{'amount'} , Count: $HoH_count{$invoice}\n";
    #print "<hr>\n";
  }
  close(INFILE);

  # now loop through the completed QB invoice & add it to the database.

  foreach my $key (sort keys %HoH) {
    # this 1st loop gets the KEY for each QB invoice.
    if ($key =~ /\w/) {
      my %row_data;
      #print "<p>Invoice No: $key, Email: $HoH{$key}->{'email'}, Amount: $HoH{$key}->{'amount'}\n";

      my $deref = $HoH{"$key"};
      foreach my $key2 (sort keys %$deref) {
        # this 2nd loop refferences the specfic fields related to the single QB invoice.
        if ($key =~ /\w/) {
          $row_data{"$key2"} = $$deref{"$key2"};
          #print "<br>&bull; $key2 --> $$deref{"$key2"}\n";
        }
      }

      # pass on certain fields
      $row_data{'merchant'} = $remote::query{'merchant'};
      $row_data{'express_pay'} = $express_pay;
      $row_data{'email_cust'} = $email_cust;
      $row_data{'merch_company'} = $merch_company;
      $row_data{'overwrite'} = $overwrite;

      # add invoice to database
      ($row_data{'FinalStatus'}, $row_data{'MErrMsg'}) = &update_invoice(%row_data);

      # put invoice's response data in result aXXXXX field
      $idx = sprintf("%05d" ,$idx);
      foreach my $key (keys %row_data) {
        # write aXXXXX result entry
        my $a = $row_data{$key};
        $a =~ s/(\W)/'%' . unpack("H2",$1)/ge;
        if ($key eq "username") { $key = "email"; }
        $result{"a$idx"} .= "$key\=$a\&";
      }
      chop $result{"a$idx"};
      $idx++;

    }
  }

  return %result;
}

sub update_invoice {
  # add/update invoice in billpay database
  my %query;

  if ($remote::query{'mode'} =~ /^(add_invoice|update_invoice)$/) {
    %query = %remote::query;

    # see if merchant is subscribed to service
    my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
    if ($service_ok ne "yes") {
      return ("problem", "$service_type");
    }
  }
  else {
    %query = @_;
  }

  my $data;

  if ($query{'merchant'} eq "") {
    return ('problem', 'Missing merchant/publisher name.');
  }

  # create placeholder email address for when unknown email feature is enabled; but now make account number required.
  if (($remote::feature{'billpay_unknown_email'} eq "yes") && ($query{'email'} eq "") && ($query{'account_no'} ne "")) {
    $query{'account_no'} =~ s/[^a-zA-Z0-9\_\-\ ]//g;
    if ($query{'account_no'} =~ /\w/) {
      $query{'email'} = sprintf("%s\@%s\.%s", $query{'account_no'}, $query{'merchant'}, "pnp");
    }
    else {
      return ("problem", "Invalid Account Number");
    }
  }

  # do data filtering & other checks
  # login email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $query{'email'} = lc($query{'email'});

  # validiate email format
  my $position = index($query{'email'},"\@");
  my $position1 = rindex($query{'email'},"\.");
  my $elength  = length($query{'email'});
  my $pos1 = $elength - $position1;
  if (($position < 1)
     || ($position1 < $position)
     || ($position1 >= $elength - 2)
     || ($elength < 5)
     || ($position > $elength - 5)
   ) {
    return ("problem", "Invalid Email Address");
  }

  $query{'invoice_no'} =~ s/[^a-zA-Z0-9\_\-]//g;

  if ( ($query{'enter_date_year'} >= 2000) &&
       (($query{'enter_date_month'} >= 1) && ($query{'enter_date_month'} <= 12)) &&
       (($query{'enter_date_day'} >= 1) && ($query{'enter_date_day'} <= 31)) ) {
    $query{'enter_date'} = sprintf("%04d%02d%02d", $query{'enter_date_year'}, $query{'enter_date_month'}, $query{'enter_date_day'});
  }

  if (($query{'enter_date'} eq "") || ($query{'enter_date'} < 20000101)) {
    my @now = gmtime(time);
    $query{'enter_date'} = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);
  }

  if ( ($query{'expire_date_year'} >= 2000) &&
       (($query{'expire_date_month'} >= 1) && ($query{'expire_date_month'} <= 12)) &&
       (($query{'expire_date_day'} >= 1) && ($query{'expire_date_day'} <= 31)) ) {
    $query{'expire_date'} = sprintf("%04d%02d%02d", $query{'expire_date_year'}, $query{'expire_date_month'}, $query{'expire_date_day'});
  }

  if (($query{'expire_date'} eq "") || ($query{'expire_date'} < 20000101)) {
    my @future = gmtime(time);
    $future[4] = $future[4] + 1; # sets 1 month into future
    if ($future[4] >= 12) {
      $future[4] = $future[4] - 12;
      $future[5] = $future[5] + 1;
    }
    $query{'expire_date'} = sprintf("%04d%02d%02d", $future[5]+1900, $future[4]+1, $future[3]);
  }

  # reject enter dates with "/" or "-" in it.
  if (($query{'enter_date'} =~ /(\/|\-)/) || (length($query{'enter_date'}) != 8)) {
    $remote::count{'reject_cnt'} = $remote::count{'reject_cnt'} + 1;
    $remote::count{"reject_$query{'status'}"} = $remote::count{"reject_$query{'status'}"} + 1;
    return ("problem", "Invalid Enter Date");
  }

  # reject expire_dates with "/" in it.
  if (($query{'expire_date'} =~ /(\/|\-)/) || (length($query{'expire_date'}) != 8)) {
    $remote::count{'reject_cnt'} = $remote::count{'reject_cnt'} + 1;
    $remote::count{"reject_$query{'status'}"} = $remote::count{"reject_$query{'status'}"} + 1;
    return ("problem", "Invalid Expire Date")
  }

  # assign unique invoice_no, if when not already defined
  if ($query{'invoice_no'} eq "") {
    my @now = gmtime(time);
    $query{'invoice_no'} = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0], $$);
    sleep(1);
  }

  if ($query{'invoice_no'} !~ /\w/) {
    $remote::count{'reject_cnt'} = $remote::count{'reject_cnt'} + 1;
    $remote::count{"reject_$query{'status'}"} = $remote::count{"reject_$query{'status'}"} + 1;
    return ("problem", "Invalid Invoice Number");
  }

  $query{'public_notes'} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]/ /g;
  $query{'private_notes'} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]/ /g;

  if ($query{'enter_date'} eq "") {
    my @now = gmtime(time);
    $query{'enter_date'} = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1]);
  }
  #$query{'enter_date'} = sprintf("%08d", $query{'enter_date'});
  #$query{'expire_date'} = sprintf("%08d", $query{'enter_date'});

  $query{'account_no'} =~ s/[^a-zA-Z0-9\_\-\ ]//g;
  $query{'amount'} = sprintf("%0.02f", $query{'amount'});

  $query{'status'} = lc($query{'status'});
  $query{'status'} =~ s/[^a-z]//g;
  if ($query{'status'} !~ /^(open|closed|hidden|merged|paid)$/) {
    $query{'status'} = "open";
  }

  $query{'orderid'} =~ s/\D//g;

  $query{'tax'} =~ s/[^0-9\.]//g;
  $query{'tax'} = sprintf("%0.02f", $query{'tax'});

  $query{'shipping'} =~ s/[^0-9\.]//g;
  $query{'shipping'} = sprintf("%0.02f", $query{'shipping'});

  $query{'handling'} =~ s/[^0-9\.]//g;
  $query{'handling'} = sprintf("%0.02f", $query{'handling'});

  $query{'discount'} =~ s/[^0-9\.]//g;
  $query{'discount'} = sprintf("%0.02f", $query{'discount'});

  if (($query{'billcycle'} > 0) && (($query{'monthly'} ne "") || ($query{'percent'} ne ""))) {
    $query{'billcycle'} =~ s/\D//g;
    $query{'percent'} =~ s/[^0-9\.]//g;
    $query{'monthly'} =~ s/[^0-9\.]//g;

    if ($query{'percent'} ne "") {
      $query{'percent'} = sprintf("%f", $query{'percent'});
    }

    if ($query{'monthly'} ne "") {
      $query{'monthly'} = sprintf("%0.02f", $query{'monthly'});
    }
  }
  else {
    $query{'billcycle'} = "";
    $query{'percent'} = "";
    $query{'monthly'} = "";
  }

  if ($query{'balance'} > 0) {
    $query{'balance'} =~ s/[^0-9\.]//g;
    if ($query{'balance'} eq "") {
      $query{'balance'} = $query{'amount'};
    }
    $query{'balance'} = sprintf("%0.02f", $query{'balance'});
  }
  else {
    $query{'balance'} = "";
  }

  if ($query{'shipsame'} eq "yes") {
    $query{'shipcompany'} = "$query{'clientcompany'}";
    $query{'shipname'} = "$query{'clientname'}";
    $query{'shipaddr1'} = "$query{'clientaddr1'}";
    $query{'shipaddr2'} = "$query{'clientaddr2'}";
    $query{'shipcity'} = "$query{'clientcity'}";
    $query{'shipstate'} = "$query{'clientstate'}";
    $query{'shipzip'} = "$query{'clientzip'}";
    $query{'shipcountry'} = "$query{'clientcountry'}";
  }

  ## clean-up & update shipping address info, as necessary
  if (exists $query{'shipname'}) {
    $query{'shipname'} =~ s/[^a-zA-Z0-9\ \'\.]/ /g;
  }
  if (exists $query{'shipcompany'}) {
    $query{'shipcompany'} =~ s/[^a-zA-Z0-9\ \'\.]/ /g;
  }
  if (exists $query{'shipaddr1'}) {
    $query{'shipaddr1'} =~ s/[\r\n]//;
    $query{'shipaddr1'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if (exists $query{'shipaddr2'}) {
    $query{'shipaddr2'} =~ s/[\r\n]//;
    $query{'shipaddr2'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if (exists $query{'shipcity'}) {
    $query{'shipcity'} =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;
  }
  if (exists $query{'shipstate'}) {
    $query{'shipstate'} =~ s/[^a-zA-Z]//g;
    $query{'shipstate'} = substr($query{'shipstate'},0,2);
    $query{'shipstate'} = uc($query{'shipstate'});
  }
  if (exists $query{'shipzip'}) {
    $query{'shipzip'} =~ s/[^a-zA-Z\'0-9 ]/ /g;
  }
  if (exists $query{'shipcountry'}) {
    $query{'shipcountry'} =~ s/[^a-zA-Z]//g;
    $query{'shipcountry'} = substr($query{'shipcountry'},0,2);
    $query{'shipcountry'} = uc($query{'shipcountry'});
  }

  # check for invoice_no existance
  my $sth1 = $remote::dbh->prepare(qq{
      select invoice_no
      from bills2
      where username=? and invoice_no=? and merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth1->execute("$query{'email'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my ($db_invoice_no) = $sth1->fetchrow;
  $sth1->finish;

  if (($query{'mode'} eq "add_invoice") && ($db_invoice_no ne "")) {
    return ("problem", "Invoice Already Exists");
  }

  if (($db_invoice_no eq "$query{'invoice_no'}") && ($query{'overwrite'} eq "yes")) {
    # if match was found, allow the update to happen
    my $sth2 = $remote::dbh->prepare(qq{
        update bills2
        set enter_date=?, expire_date=?, account_no=?, amount=?, status=?, orderid=?, tax=?, shipping=?, handling=?, discount=?, billcycle=?, percent=?, monthly=?, balance=?, public_notes=?, private_notes=?, shipname=?, shipcompany=?, shipaddr1=?, shipaddr2=?, shipcity=?, shipstate=?, shipzip=?, shipcountry=?
        where username=? and invoice_no=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$query{'enter_date'}", "$query{'expire_date'}", "$query{'account_no'}", "$query{'amount'}", "$query{'status'}", "$query{'orderid'}", "$query{'tax'}", "$query{'shipping'}", "$query{'handling'}", "$query{'discount'}", "$query{'billcycle'}", "$query{'percent'}", "$query{'monthly'}", "$query{'balance'}", "$query{'public_notes'}", "$query{'private_notes'}", "$query{'shipname'}", "$query{'shipcompany'}", "$query{'shipaddr1'}", "$query{'shipaddr2'}", "$query{'shipcity'}", "$query{'shipstate'}", "$query{'shipzip'}", "$query{'shipcountry'}", "$query{'email'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    my $sth3 = $remote::dbh->prepare(qq{
        delete from billdetails2
        where username=? and invoice_no=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth3->execute("$query{'email'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    $sth3->finish;

    for (my $i = 1; $i <= 50; $i++) {
      # filter out unwanted characters from product data
      $query{"item$i"} =~ s/[^a-zA-Z_0-9\.\_\-]//g;
      $query{"cost$i"} =~ s/[^0-9\.\-]//g;
      $query{"cost$i"} = sprintf("%0.02f", $query{"cost$i"});
      $query{"qty$i"} =~ s/[^0-9\.]//g;
      $query{"descr$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.\,\+\/\(\)]//g;
      $query{"weight$i"} =~ s/[^0-9\.]//g;
      $query{"descra$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]//g;
      $query{"descrb$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]//g;
      $query{"descrc$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]//g;

      if (($query{"item$i"} ne "") && ($query{"cost$i"} =~ /\d/) && ($query{"qty$i"} > 0) && ($query{"descr$i"} ne "")) {
        my $sth4 = $remote::dbh->prepare(qq{
            insert into billdetails2
            (merchant, username, invoice_no, item, cost, qty, descr, weight, descra, descrb, descrc, amount)
            values (?,?,?,?,?,?,?,?,?,?,?,?)
          }) or die "Cannot prepare: $DBI::errstr";
        $sth4->execute("$query{'merchant'}", "$query{'email'}", "$query{'invoice_no'}", "$query{\"item$i\"}", "$query{\"cost$i\"}", "$query{\"qty$i\"}", "$query{\"descr$i\"}", "$query{\"weight$i\"}", "$query{\"descra$i\"}", "$query{\"descrb$i\"}", "$query{\"descrc$i\"}", "$query{'amount'}") or die "Cannot execute: $DBI::errstr";
        $sth4->finish;
      }
    }

    $remote::count{'update_cnt'} = $remote::count{'update_cnt'} + 1;
    $remote::count{"update_$query{'status'}"} = $remote::count{"update_$query{'status'}"} + 1;
    #return ("success", "Invoice Updated");
  }
  elsif (($db_invoice_no eq "$query{'invoice_no'}") && ($query{'overwrite'} ne "yes")) {
    $remote::count{'reject_cnt'} = $remote::count{'reject_cnt'} + 1;
    $remote::count{"reject_$query{'status'}"} = $remote::count{"reject_$query{'status'}"} + 1;
    return ("problem", "Invoice Already Exists");
  }
  else {
    # if no match was found, allow the insert to happen
    my $sth2 = $remote::dbh->prepare(qq{
        insert into bills2
        (merchant, username, invoice_no, enter_date, expire_date, account_no, amount, status, orderid, tax, shipping, handling, discount, billcycle, percent, monthly, balance, public_notes, private_notes, shipname, shipcompany, shipaddr1, shipaddr2, shipcity, shipstate, shipzip, shipcountry)
        values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$query{'merchant'}", "$query{'email'}", "$query{'invoice_no'}", "$query{'enter_date'}", "$query{'expire_date'}", "$query{'account_no'}", "$query{'amount'}", "$query{'status'}", "$query{'orderid'}", "$query{'tax'}", "$query{'shipping'}", "$query{'handling'}", "$query{'discount'}", "$query{'billcycle'}", "$query{'percent'}", "$query{'monthly'}", "$query{'balance'}", "$query{'public_notes'}", "$query{'private_notes'}", "$query{'shipname'}", "$query{'shipcompany'}", "$query{'shipaddr1'}", "$query{'shipaddr2'}", "$query{'shipcity'}", "$query{'shipstate'}", "$query{'shipzip'}", "$query{'shipcountry'}") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    for (my $i = 1; $i <= 50; $i++) {
      # filter out unwanted characters from product data
      $query{"item$i"} =~ s/[^a-zA-Z_0-9\.\_\-]//g;
      $query{"cost$i"} =~ s/[^0-9\.\-]//g;
      $query{"cost$i"} = sprintf("%0.02f", $query{"cost$i"});
      $query{"qty$i"} =~ s/[^0-9\.]//g;
      $query{"descr$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.\,\+\/\(\)]//g;
      $query{"weight$i"} =~ s/[^0-9\.]//g;
      $query{"descra$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]//g;
      $query{"descrb$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]//g;
      $query{"descrc$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]//g;

      if (($query{"item$i"} ne "") && ($query{"cost$i"} =~ /\d/) && ($query{"qty$i"} > 0) && ($query{"descr$i"} ne "")) {
        my $sth = $remote::dbh->prepare(qq{
            insert into billdetails2
            (merchant, username, invoice_no, item, cost, qty, descr, weight, descra, descrb, descrc, amount)
            values (?,?,?,?,?,?,?,?,?,?,?,?)
          }) or die "Cannot prepare: $DBI::errstr";
        $sth->execute("$query{'merchant'}", "$query{'email'}", "$query{'invoice_no'}", "$query{\"item$i\"}", "$query{\"cost$i\"}", "$query{\"qty$i\"}", "$query{\"descr$i\"}", "$query{\"weight$i\"}", "$query{\"descra$i\"}", "$query{\"descrb$i\"}", "$query{\"descrc$i\"}", "$query{'amount'}") or die "Cannot execute: $DBI::errstr";
        $sth->finish;
      }
    }

    $remote::count{'add_cnt'} = $remote::count{'add_cnt'} + 1;
    $remote::count{"add_$query{'status'}"} = $remote::count{"add_$query{'status'}"} + 1;
    #return ("success", "Invoice Successfully Added");
  }

  ## clean-up & update client contact info, as necessary
  if (exists $query{'clientname'}) {
    $query{'clientname'} =~ s/[^a-zA-Z0-9\ \'\.]/ /g;
  }
  if (exists $query{'clientcompany'}) {
    $query{'clientcompany'} =~ s/[^a-zA-Z0-9\ \'\.]/ /g;
  }
  if (exists $query{'clientaddr1'}) {
    $query{'clientaddr1'} =~ s/[\r\n]//;
    $query{'clientaddr1'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if (exists $query{'clientaddr2'}) {
    $query{'clientaddr2'} =~ s/[\r\n]//;
    $query{'clientaddr2'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if (exists $query{'clientcity'}) {
    $query{'clientcity'} =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;
  }
  if (exists $query{'clientstate'}) {
    $query{'clientstate'} =~ s/[^a-zA-Z]//g;
    $query{'clientstate'} = substr($query{'clientstate'},0,2);
    $query{'clientstate'} = uc($query{'clientstate'});
  }
  if (exists $query{'clientzip'}) {
    $query{'clientzip'} =~ s/[^a-zA-Z\'0-9 ]/ /g;
  }
  if (exists $query{'clientcountry'}) {
    $query{'clientcountry'} =~ s/[^a-zA-Z]//g;
    $query{'clientcountry'} = substr($query{'clientcountry'},0,2);
    $query{'clientcountry'} = uc($query{'clientcountry'});
  }

  if (exists $query{'consolidate'}) {
    $query{'consolidate'} =~ s/^(yes)$//g;
  }

  # start by checking for client existance
  my $sth1a = $remote::dbh->prepare(qq{
      select username
      from client_contact
      where username=? and merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  my $rc = $sth1a->execute("$query{'email'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my ($db_username) = $sth1a->fetchrow;
  $sth1a->finish;

  if ($db_username eq "$query{'email'}") {
    # if match was found, allow the update to happen
    my $sth2a = $remote::dbh->prepare(qq{
        update client_contact
        set clientname=?, clientcompany=?, clientaddr1=?, clientaddr2=?, clientcity=?, clientstate=?, clientzip=?, clientcountry=?
        where username=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2a->execute("$query{'clientname'}", "$query{'clientcompany'}", "$query{'clientaddr1'}", "$query{'clientaddr2'}", "$query{'clientcity'}", "$query{'clientstate'}", "$query{'clientzip'}", "$query{'clientcountry'}", "$query{'email'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    $sth2a->finish;
  }
  else {
    # if no match was found, allow the insert to happen
    my $sth2a = $remote::dbh->prepare(qq{
        insert into client_contact
        (merchant, username, clientname, clientcompany, clientaddr1, clientaddr2, clientcity, clientstate, clientzip, clientcountry, consolidate)
        values (?,?,?,?,?,?,?,?,?,?,?)
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2a->execute("$query{'merchant'}", "$query{'email'}", "$query{'clientname'}", "$query{'clientcompany'}", "$query{'clientaddr1'}", "$query{'clientaddr2'}", "$query{'clientcity'}", "$query{'clientstate'}", "$query{'clientzip'}", "$query{'clientcountry'}", "$query{'consolidate'}") or die "Cannot execute: $DBI::errstr";
    $sth2a->finish;
  }

  if (($query{'email_cust'} eq "yes") && ($query{'status'} ne "hidden")) {
    &billpay_merchadmin::email_customer_html(%query);
  }

  return ("success", "Invoice Successfully Stored");
}

sub query_invoice {
  # search for invoices in billpay database
  my (%query) = %remote::query;

  my %result = ();

  if ($query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my $count = 0;
  my $idx = 0;

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my @now2 = gmtime(time + 86400);
  my $tomorrow = sprintf("%04d%02d%02d", $now2[5]+1900, $now2[4]+1, $now2[3]);

  my ($startdate, $enddate);
  if ($query{'startdate'} eq "") {
    $startdate = sprintf("%04d%02d%02d", $query{'startyear'}, $query{'startmonth'}, $query{'startday'});
  }
  else {
    $startdate = $query{'startdate'};
  }

  if ($query{'enddate'} eq "") {
    $enddate = sprintf("%04d%02d%02d", $query{'endyear'}, $query{'endmonth'}, $query{'endday'});
  }
  else {
    $enddate = $query{'enddate'};
  }

  if ($startdate < 20060101) {
    $startdate = 20060101;
  }
  if ($enddate > $today) {
    $enddate = $tomorrow;
  }
  if ($enddate < $startdate) {
    my $old_startdate = $startdate;
    $startdate = $enddate;
    $enddate = $old_startdate;
  }

  if ($query{'status'} !~ /(open|expired|closed|hidden|merged|paid|unpaid)/) {
    $query{'status'} = "";
  }

  if ($query{'qresp'} ne "simple") {
    $query{'qresp'} = "";
  }

  if ($query{'alias'} ne "") {
    $query{'alias'} =~ s/[^a-zA-Z0-9]//g;
    $query{'alias'} = lc($query{'alias'});

    my $dbh = &miscutils::dbhconnect("billpres");
    my $sth = $dbh->prepare(qq{
        select username
        from client_contact
        where merchant=? and alias=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$query{'merchant'}", "$query{'alias'}") or die "Can't execute: $DBI::errstr";
    my ($email) = $sth->fetchrow;
    $sth->finish;
    $dbh->disconnect;

    if ($email =~ /\w/) {
      $query{'email'} = $email;
    }
  }

  my @placeholder;

  my $qstr = "select *";
  $qstr .= " from bills2";
  $qstr .= " where merchant=?";
  push(@placeholder, "$query{'merchant'}");

  if ($query{'status'} ne "") {
    if ($query{'status'} eq "expired") {
      $query{'status'} = "open";
      $qstr .= " and status=? and expire_date<=?";
      push(@placeholder, "$query{'status'}", "$today");
    }
    elsif ($query{'status'} eq "unpaid") {
      $query{'status'} = "open";
      $qstr .= " and status=? and expire_date>? and (balance>0 or orderid=?)";
      push(@placeholder, "$query{'status'}", "$today", "");
    }
    else {
      $qstr .= " and status=?";
      push(@placeholder, "$query{'status'}");
    }
  }

  if ($query{'invoices'} eq "enter_date") {
    # limit exported invoices to only those within the enter date range
    $qstr .= " and enter_date>=? and enter_date<=?";
    push(@placeholder, "$startdate", "$enddate");
  }
  elsif ($query{'invoices'} eq "expire_date") {
    # limit exported invoices to only those within the expire date range
    $qstr .= " and expire_date>=? and expire_date<=?";
    push(@placeholder, "$startdate", "$enddate");
  }

  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $query{'email'} = lc($query{'email'});
  if ($query{'email'} ne "") {
    if ($query{'fuzzyflg'} == 1) {
      $qstr .= " and username like ?";
      push(@placeholder, "\%$query{'email'}\%");
    }
    else {
      $qstr .= " and username=?";
      push(@placeholder, "$query{'email'}");
    }
  }

  $query{'invoice_no'} =~ s/[^a-zA-Z0-9\_\-]//g;
  if ($query{'invoice_no'} ne "") {
    if ($query{'fuzzyflg'} == 1) {
      $qstr .= " and invoice_no like ?";
      push(@placeholder, "\%$query{'invoice_no'}\%");
    }
    else {
      $qstr .= " and invoice_no=?";
      push(@placeholder, "$query{'invoice_no'}");
    }
  }

  $query{'account_no'} =~ s/\W//g;
  if ($query{'account_no'} ne "") {
    if ($query{'fuzzyflg'} == 1) {
      $qstr .= " and account_no like ?";
      push(@placeholder, "\%$query{'account_no'}\%");
    }
    else {
      $qstr .= " and account_no=?";
      push(@placeholder, "$query{'account_no'}");
    }
  }

  $query{'orderid'} =~ s/\D//g;
  if ($query{'orderid'} ne "") {
    if ($query{'fuzzyflg'} == 1) {
      $qstr .= " and orderid like ?";
      push(@placeholder, "\%$query{'orderid'}\%");
    }
    else {
      $qstr .= " and orderid=?";
      push(@placeholder, "$query{'orderid'}");
    }
  }

  my @field_list = ('shipname', 'shipcompany', 'shipaddr1', 'shipaddr2', 'shipcity', 'shipstate', 'shipzip', 'shipcountry');
  for (my $i = 0; $i <= $#field_list; $i++) {
    $query{$field_list[$i]} =~ s/[\r\n]//;
    $query{$field_list[$i]} =~ s/[^a-zA-Z0-9\_\.\/\@\:\-\&\ \#\'\,]//g;

    if ($query{$field_list[$i]} ne "") {
      if ($query{'fuzzyflg'} == 1) {
        $qstr .= " and $field_list[$i] like ?";
        push(@placeholder, "\%$query{$field_list[$i]}\%");
      }
      else {
        $qstr .= " and $field_list[$i]=?";
        push(@placeholder, "$query{$field_list[$i]}");
      }
    }
  }

  if (($query{'amount_min'} ne "") && ($query{'amount_max'} ne "")) {
    $query{'amount_min'} = sprintf("%0.02f", $query{'amount_min'});
    $query{'amount_max'} = sprintf("%0.02f", $query{'amount_max'});
    $qstr .= " and amount>=? and amount<=?";
    push(@placeholder, "$query{'amount_min'}", "$query{'amount_max'}");
  }

  if ($query{'sort_by'} eq "expire_date") {
    $qstr .= " order by expire_date";
  }
  else {
    $qstr .= " order by enter_date";
  }

  my $dbh = &miscutils::dbhconnect("billpres");
  my $sth = $dbh->prepare(qq{ $qstr }) or die "Cannot do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Cannot execute: $DBI::errstr";
  while (my $invoice = $sth->fetchrow_hashref()) {
    my %invoice;
    foreach my $key (keys %{$invoice}) {
      $invoice{"$key"} = $invoice->{"$key"};
      $invoice{"$key"} =~ s/(\r|\n|\r\n)/  /g;
    }

    if ($invoice{'merchant'} eq "$query{'merchant'}") {
      $count = $count + 1;

      $invoice{'amount'} = sprintf("%0.02f", $invoice{'amount'});
      $invoice{'tax'} = sprintf("%0.02f", $invoice{'tax'});
      $invoice{'shipping'} = sprintf("%0.02f", $invoice{'shipping'});
      $invoice{'handling'} = sprintf("%0.02f", $invoice{'handling'});
      $invoice{'discount'} = sprintf("%0.02f", $invoice{'discount'});

      if ($invoice{'status'} eq "") {
        $invoice{'status'} = "open";
      }

      if ($invoice{'billcycle'} ne "") {
        $invoice{'billcycle'} = sprintf("%d", $invoice{'billcycle'});
      }

      if ($invoice{'percent'} ne "") {
        $invoice{'percent'} = sprintf("%f", $invoice{'percent'});
      }

      if ($invoice{'monthly'} ne "") {
        $invoice{'monthly'} = sprintf("%0.02f", $invoice{'monthly'});
      }

      if ($invoice{'balance'} ne "") {
        $invoice{'balance'} = sprintf("%0.02f", $invoice{'balance'});
      }

      my $a = 0;

      # add itemized product info
      my $sth2 = $dbh->prepare(qq{
          select *
          from billdetails2
          where merchant=? and username=? and invoice_no=?
          order by item
        }) or die "Cannot do: $DBI::errstr";
      $sth2->execute("$invoice{'merchant'}", "$invoice{'username'}", "$invoice{'invoice_no'}") or die "Cannot execute: $DBI::errstr";
      while (my $product = $sth2->fetchrow_hashref()) {
        my %product;
        foreach my $key (keys %{$product}) {
          $product{"$key"} = $product->{"$key"};
        }

        if (($product{'item'} ne "") && ($product{'cost'} =~ /\d/) && ($product{'qty'} > 0) && ($product{'descr'} ne "")) {
          $a = $a + 1;

          $invoice{"item$a"} = $product{'item'};
          $invoice{"cost$a"} = sprintf("%0.02f", $product{'cost'});
          $invoice{"qty$a"} = $product{'qty'};
          $invoice{"descr$a"} = $product{'descr'};

          if ($product{'weight'} =~ /\w/) {
            $invoice{"weight$a"} = $product{'weight'};
          }
          if ($product{'descra'} =~ /\w/) {
            $invoice{"descra$a"} = $product{'descra'};
          }
          if ($product{'descrb'} =~ /\w/) {
            $invoice{"descrb$a"} = $product{'descrb'};
          }
          if ($product{'descrc'} =~ /\w/) {
            $invoice{"descrc$a"} = $product{'descrc'};
          }
        }
      }
      $sth2->finish;

      # add client contact info
      my $sth3 = $dbh->prepare(qq{
          select *
          from client_contact
          where merchant=? and username=?
        }) or die "Cannot prepare: $DBI::errstr";
      $sth3->execute("$invoice{'merchant'}", "$invoice{'username'}") or die "Cannot execute: $DBI::errstr";
      my $client = $sth3->fetchrow_hashref();
      $sth3->finish;

      foreach my $key (keys %$client) {
        if ($key !~ /^(merchant|username)$/) {
          $invoice{"$key"} = $client->{$key};
        }
      }

      # calculate payment amount due for open/unpaid invoices
      if (($invoice{'status'} eq "open") && ($invoice{'expire_date'} > $today) && (($invoice{'balance'} > 0) || ($invoice{'orderid'} eq ""))) {
        my %charge_data = &calc_invoice_payment(%invoice);
        foreach my $key (keys %charge_data) {
          $invoice{"$key"} = $charge_data{$key};
        }
      }

      # put invoice's response data in result aXXXXX field
      $idx = sprintf("%05d" ,$idx);
      if ($query{'qresp'} eq "simple") {

        my @list = ('merchant', 'username', 'invoice_no', 'account_no', 'status', 'expire_date', 'amount', 'balance', 'monthly', 'percent', 'clientcompany', 'clientname', 'alias', 'payment_amt', 'payment_min', 'payment_max'); # list only these fields

        for (my $i = 0; $i <= $#list; $i++) {
          my $key = $list[$i];
          if ($invoice{$key} !~ /\w/) { next; }

          if ($query{'client'} =~ /^(angelivr)$/) {
            my $a = $invoice{$key};
            if ($key eq "username") { $key = "email"; }
            my $f = sprintf("invoice%0d\_%s", $idx, $key);
            $result{"$f"} .= "$a";
          }
          else {
            # write aXXXXX simple result entry
            my $a = $invoice{$key};
            $a =~ s/(\W)/'%' . unpack("H2",$1)/ge;
            if ($key eq "username") { $key = "email"; }
            $result{"a$idx"} .= "$key\=$a\&";
          }
        }
      }
      else {
        foreach my $key (sort keys %invoice) {
          # write aXXXXX full result entry
          my $a = $invoice{$key};
          $a =~ s/(\W)/'%' . unpack("H2",$1)/ge;
          if ($key eq "username") { $key = "email"; }
          $result{"a$idx"} .= "$key\=$a\&";
        }
      }
      chop $result{"a$idx"};
      $idx++;
    }
  }
  $sth->finish;
  $dbh->disconnect;

  $result{'TranCount'} = sprintf("%01d", $count);

  if ($result{'TranCount'} == 0) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
    $result{'resp-code'} = "PXX";
  }
  else {
    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = sprintf("There are %d matching invoices.", $count);
    $result{'resp-code'} = "P00";
  }

  if ($query{'client'} =~ /^(angelivr)$/) {
    $result{'next_page'} = $query{'next_page'};
    &output_angel_query(%result);
  }
  else {
    return %result;
  }
}

sub delete_invoice {
  # delete specific invoice from billpay database
  my (%query) = %remote::query;

  my %result = ();

  if ($query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  # do data filtering & other checks
  # email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $query{'email'} = lc($query{'email'});

  # validiate email format
  my $position = index($query{'email'},"\@");
  my $position1 = rindex($query{'email'},"\.");
  my $elength  = length($query{'email'});
  my $pos1 = $elength - $position1;
  if (($position < 1)
     || ($position1 < $position)
     || ($position1 >= $elength - 2)
     || ($elength < 5)
     || ($position > $elength - 5)
   ) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Invalid Email Address";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  $query{'invoice_no'} =~ s/[^a-zA-Z0-9\_\-]//g;
  if ($query{'invoice_no'} !~ /\w/) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing Invoice Number";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  my $dbh = &miscutils::dbhconnect("billpres");
  my $sth = $dbh->prepare(qq{
      delete from bills2
      where username=? and invoice_no=? and merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$query{'email'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my ($test) = $sth->finish;

  if ($test ne "") {
    my $sth2 = $dbh->prepare(qq{
        delete from billdetails2
        where username=? and invoice_no=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$query{'email'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    $result{'FinalStatus'} = "success";
    $result{'aux-msg'} = "Invoice has been removed from the database.";
    $result{'resp-code'} = "P00";
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Invoice does not exist in the database.";
    $result{'resp-code'} = "PXX";
  }
  $dbh->disconnect;

  return %result;
}

sub calc_invoice_payment {
  # calculate payment requirements for invoice supplied
  # NOTE: simply pass the function the entire invoice as a hash & it will figure things out itself
  my (%invoice) = @_;

  my ($charge, $charge_type, $amount, $balance, $monthly, $percent, $billcycle);

  # we are really only working with these fields...
  $amount = $invoice{'amount'};
  $balance = $invoice{'balance'};
  $monthly = $invoice{'monthly'};
  $percent = $invoice{'percent'};
  $billcycle = $invoice{'billcycle'};

  ## see if we need to charge an installment fee
  if (($billcycle > 0) && ($balance > 0) && (($monthly > 0) || $percent > 0)) {

    if ($balance > 0) { $balance = sprintf("%0.02f", $balance); }
    if ($monthly > 0) { $monthly = sprintf("%0.02f", $monthly); }
    if ($percent > 0) { $percent = sprintf("%f", $percent); }

    # calculate installment amount
    if (($balance > 0) && (($monthly > 0) || ($percent > 0))) {
      if ($percent > 0) {
        # figure out percentage installment amount
        $charge = ($percent / 100) * $balance;
        $charge_type = "percent_installment";

        if (($percent > 0) && ($charge < $monthly)) {
          # now if installment is less then monthly minimim, charge the minimum
          $charge = $monthly;
          $charge_type = "minimum_installment";
        }
      }
      else {
        # when invoice is only monthly based, set the monthly amount for the installment amount.
        $charge = $monthly;
        $charge_type = "flatrate_installment";
      }

      # now if the balenace is less then the installment amount, charge the remaining balance only
      if ($charge > $balance) {
        $charge = $balance;
        $charge_type = "remainder_installment"
      }
    }

    if ($charge > 0) { $charge = sprintf("%0.02f", $charge); }

  }
  ## since we are not charging the installment fee, see if we need to charge the balance on the invoice
  elsif ($balance > 0) {
    # charge the balance on an invoice
    $charge = $balance;
    $charge_type = "balance";
  }
  # since we are not charging a balance or an installment payment payment, charge the full amount of the bill
  else {
    # charge the full amount of the bill
    $charge = $amount;
    $charge_type = "full_amount";
  }

  # return calculated payment requirements
  my %payment = ();

  $payment{'payment_amt'} = $charge;
  $payment{'payment_type'} = $charge_type;
  if ($remote::feature{'billpay_allow_overpay'} =~ /yes/i) {
    if (($invoice{'billcycle'} > 0) && ($invoice{'balance'} > 0) && ($charge > 0)) {
      $payment{'payment_min'} = $charge;
      $payment{'payment_max'} = $balance;
    }
  }

  return %payment;
}

sub output_angel_query {
  my (%query) = @_;
  my ($status, $message);

  if ($query{'FinalStatus'} eq "success") {
    $status = "OK";
    $message = "$query{'aux-msg'}";
  }
  else {
    $status = "NOTOK";
    $message = "$query{'MErrMsg'}.\n"
  }
  $query{'next_page'} =~ s/[^0-9\/]//g;

  #my $resp = "Content-Type: text/xml\n\n";   ## DCP 20100716
  my $resp = "<ANGELXML>\n";
  $resp .= "<VARIABLES>\n";
  $resp .= "  <VAR name=\"status\" value=\"$status\" />\n";
  $resp .= "  <VAR name=\"MErrMsg\" value=\"$query{'MErrMsg'}\" />\n";
  $resp .= "  <VAR name=\"TranCount\" value=\"$query{'TranCount'}\" />\n";

  foreach (my $i = 0; $i < $query{'TranCount'}; $i++) {
    my $j = $i + 1;

    # format & clean up some of the data...
    my ($firstname, $lastname) = &split_clientname($query{"invoice$i\_clientname"});
    my $expire = $query{"invoice$i\_expire_date"};
    $query{"invoice$i\_expire_date"} = sprintf("%02d\/%02d\/%04d", substr($expire,4,2), substr($expire,6,2), substr($expire,0,4) );

    $resp .= "  <VAR name=\"invoice$j\_first_name\" value=\"$firstname\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_last_name\" value=\"$lastname\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_company\" value=\"$query{\"invoice$i\_clientcompany\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_alias\" value=\"$query{\"invoice$i\_alias\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_account\" value=\"$query{\"invoice$i\_account_no\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_email\" value=\"$query{\"invoice$i\_email\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_number\" value=\"$query{\"invoice$i\_invoice_no\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_grandtotal\" value=\"$query{\"invoice$i\_amount\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_due\" value=\"$query{\"invoice$i\_balance\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_installment_due\" value=\"$query{\"invoice$i\_payment_amt\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_due_date\" value=\"$query{\"invoice$i\_expire_date\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_min_due\" value=\"$query{\"invoice$i\_payment_min\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_max_due\" value=\"$query{\"invoice$i\_payment_max\"}\" />\n";
    $resp .= "  <VAR name=\"invoice$j\_convfeeamt\" value=\"$query{\"invoice$i\_convfeeamt\"}\" />\n";
  }

  $resp .= "</VARIABLES>\n";
  $resp .= "<MESSAGE>\n";
  $resp .= "  <PLAY>\n";
  $resp .= "    <PROMPT type=\"text\">.</PROMPT>\n";
  $resp .= "  </PLAY>\n";
  $resp .= "  <GOTO destination=\"$query{'next_page'}\" />\n";
  $resp .= "</MESSAGE>\n";
  $resp .= "</ANGELXML>\n";

  print header( -type=>'text/html');  ### DCP 20100716
  print $resp;
  exit;
}

sub split_clientname {
  my ($card_name) = @_;

  my ($names0, $names1, $names2) = split(/ +/,$card_name,3);
  my ($firstname, $lastname);

  if ($names2 ne "") {
    $firstname = "$names0 $names1";
    $lastname = "$names2";
  }
  else {
    $firstname = "$names0";
    $lastname = "$names1";
    if ($lastname eq "") {
      my $len = length($firstname) / 2;
      $lastname = substr($firstname,$len);
      $firstname = substr($firstname,0,$len);
    }
  }

  return("$firstname", "$lastname");
}

sub bill_invoice {
  # pay specific invoice from billpay database
  my (%query) = %remote::query;

  my ($merchant, $username, $invoice_no, $account_no, $status, $expire_date, $amount, $profileid, $shacardnumber, $cardname, $cardcompany, $cardaddr1, $cardaddr2, $cardcity, $cardstate, $cardzip, $cardcountry, $cardnumber, $exp, $cvv, $enccardnumber, $length, $shipcompany, $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip, $shipcountry, $phone, $fax, $email, $db_item, $db_cost, $db_qty, $db_descr, $db_weight, $db_descra, $db_descrb, $db_descrc, $paymethod, $routingnum, $accountnum, $checknum, $checktype, $accttype, $acctclass, $commcardtype, $tax, $shipping, $handling, $discount, $balance, $percent, $monthly, $billcycle, $public_notes, $private_notes, $lastbilled, $lastattempted, $merch_company, $merch_status, $merch_cards_allowed, $merch_chkprocessor, $merch_feature, $merch_alliance_status, $charge, $db_username);

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

  my %result = ();

  if ($query{'merchant'} eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing merchant/publisher name.";
    $result{'resp-code'} = "P98";
    return %result;
  }

  # see if merchant is subscribed to service
  my ($service_ok, $service_type) = &mckutils::check_service("$query{'merchant'}", "billpay");
  if ($service_ok ne "yes") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "$service_type";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  # do data filtering & other checks

  # find out email from alias, if necessary
  if ($query{'alias'} ne "") {
    $query{'alias'} =~ s/[^a-zA-Z0-9]//g;
    $query{'alias'} = lc($query{'alias'});

    my $dbh = &miscutils::dbhconnect("billpres");
    my $sth = $dbh->prepare(qq{
        select username
        from client_contact
        where merchant=? and alias=?
      }) or die "Can't do: $DBI::errstr";
    $sth->execute("$query{'merchant'}", "$query{'alias'}") or die "Can't execute: $DBI::errstr";
    my ($email) = $sth->fetchrow;
    $sth->finish;
    $dbh->disconnect;

    if ($email =~ /\w/) {
      $query{'email'} = $email;
    }
  }

  # email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz|pnp)$/\.$1/;
  $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $query{'email'} = lc($query{'email'});

  # validiate email format
  my $position = index($query{'email'},"\@");
  my $position1 = rindex($query{'email'},"\.");
  my $elength  = length($query{'email'});
  my $pos1 = $elength - $position1;
  if (($position < 1)
     || ($position1 < $position)
     || ($position1 >= $elength - 2)
     || ($elength < 5)
     || ($position > $elength - 5)
   ) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Invalid Email Address";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  $query{'invoice_no'} =~ s/[^a-zA-Z0-9\_\-]//g;
  if ($query{'invoice_no'} !~ /\w/) {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Missing Invoice Number";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  $query{'account_no'} =~ s/[^a-zA-Z0-9\_\-\ ]//g;
  $query{'profileid'} =~ s/[^0-9]//g;

  my $dbh = &miscutils::dbhconnect("billpres");

  # get general transaction info

  my @placeholder = ();
  my $qstr = "select merchant, username, invoice_no, account_no, status, expire_date, amount, tax, shipping, handling, discount, balance, percent, monthly, billcycle, public_notes, private_notes, lastbilled, lastattempted, shipcompany, shipname, shipaddr1, shipaddr2, shipcity, shipstate, shipzip, shipcountry";
  $qstr .= " from bills2";
  $qstr .= " where username=? and invoice_no=? and merchant=?";
  push(@placeholder, "$query{'email'}", "$query{'invoice_no'}", "$query{'merchant'}");

  if ($query{'account_no'} ne "") {
    $qstr .= " and account_no=?";
    push(@placeholder, "$query{'account_no'}");
  }

  my $sth = $dbh->prepare(qq{ $qstr }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute(@placeholder) or die "Cannot execute: $DBI::errstr";
  ($merchant, $username, $invoice_no, $account_no, $status, $expire_date, $amount, $tax, $shipping, $handling, $discount, $balance, $percent, $monthly, $billcycle, $public_notes, $private_notes, $lastbilled, $lastattempted, $shipcompany, $shipname, $shipaddr1, $shipaddr2, $shipcity, $shipstate, $shipzip, $shipcountry) = $sth->fetchrow;
  $sth->finish;

  if ($query{'merchant'} ne "$merchant") {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "No Records Found";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  if ($query{'profileid'} ne "") {
    # get get existing billing profile info from DB
    my $sth2 = $dbh->prepare(qq{
        select username, profileid, shacardnumber, cardname, cardcompany, cardaddr1, cardaddr2, cardcity, cardstate, cardzip, cardcountry, cardnumber, exp, enccardnumber, length
        from billing2
        where username=? and profileid=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$username", "$query{'profileid'}") or die "Cannot execute: $DBI::errstr";
    ($db_username, $profileid, $shacardnumber, $cardname, $cardcompany, $cardaddr1, $cardaddr2, $cardcity, $cardstate, $cardzip, $cardcountry, $cardnumber, $exp, $enccardnumber, $length) = $sth2->fetchrow;
    $sth2->finish;

    if ($shacardnumber ne "") {
      my $cd = new PlugNPay::CardData();
      my $ecrypted_card_data = '';
      eval {
        $ecrypted_card_data = $cd->getBillpayCardData({customer => "$db_username", profileID => "$profileid"});
      };
      if (!$@) {
        $enccardnumber = $ecrypted_card_data;
      }

      $cardnumber = &rsautils::rsa_decrypt_file($enccardnumber,$length,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");

      if ($cardnumber =~ /\d{9} \d/) {
        ($routingnum, $accountnum) = split(/ /, $cardnumber, 2);
        $accttype = "checking";
        $cardnumber = "";
      }
      else {
        $accttype = "";
        $cvv = $query{'card-cvv'};
      }
    }

    # get instant contact info
    my $sth3 = $dbh->prepare(qq{
        select username, phone, fax, email
        from customer2
        where username=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth3->execute("$ENV{'REMOTE_USER'}") or die "Cannot execute: $DBI::errstr";
    ($db_username, $phone, $fax, $email) = $sth3->fetchrow;
    $sth3->finish;
  }
  else {
    # when no profileid is supplied, use what the user provided us.

    $cardname = $query{'card-name'};
    $cardcompany = $query{'card-company'};
    $cardaddr1 = $query{'card-address1'};
    $cardaddr2 = $query{'card-address2'};
    $cardcity = $query{'card-city'};
    $cardstate = $query{'card-state'};
    $cardzip = $query{'card-zip'};
    $cardcountry = $query{'card-country'};
    $phone = $query{'phone'};
    $fax = $query{'fax'};
    $email = $query{'email'};

    $cardnumber = $query{'card-number'};
    $exp = $query{'card-exp'};
    $cvv = $query{'card-cvv'};

    if ($cardnumber =~ /^(\d{9} \d)/) {
      ($routingnum, $accountnum) = split(/ /, $cardnumber, 2);
      $cardnumber = "";
      $accttype = "checking";
    }
    elsif (($query{'routingnum'} =~ /\d/) && ($query{'accountnum'} =~ /\d/)) {
      $routingnum = $query{'routingnum'};
      $accountnum = $query{'accountnum'};
      $cardnumber = "";
      $accttype = $query{'accttype'};
    }
    else {
      $accttype = "";
    }

    $acctclass = $query{'acctclass'};
    $checknum = $query{'checknum'};
    $checktype = $query{'checktype'};
    $commcardtype = $query{'commcardtype'};
  }

  $dbh->disconnect;

  # get merchant's company name, account status, allowed card types & ach processor info
  my $dbh_pnpmisc = &miscutils::dbhconnect("pnpmisc");
  my $sth_pnpmisc = $dbh_pnpmisc->prepare(qq{
      select company, status, cards_allowed, chkprocessor, features
      from customers
      where username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth_pnpmisc->execute("$merchant") or die "Cannot execute: $DBI::errstr";
  ($merch_company, $merch_status, $merch_cards_allowed, $merch_chkprocessor, $merch_feature) = $sth_pnpmisc->fetchrow;
  $sth_pnpmisc->finish;
  $dbh_pnpmisc->disconnect;

  my %feature;
  my @array_feature = split(/\,/,$merch_feature);
  foreach my $entry (@array_feature) {
    my ($name,$value) = split(/\=/,$entry);
    $feature{"$name"} = $value;
  }

  # verify merchant can accept that payment type &/or card type
  if ($merch_status !~ /(live|debug|test)/i) {
    # error: merchant account not active
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'} = "Merchant cannot accept online payments at this time.";
    $result{'resp-code'} = "PXX";
    return %result;
  }

  if ($accttype eq "checking") {
    # check for ACH/echeck ability
    my $allow_ach = &detect_ach("$merch_chkprocessor","$merchant");
    if ($allow_ach !~ /yes/i) {
      # error: ACH/eCheck not supported
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Merchant does not accept online check payments at this time.";
      $result{'resp-code'} = "PXX";
      return %result;
    }
  }
  #else {
  #  # check for cardtype & find out it's allowed
  #  my $cardtype = &detect_cardtype("$cardnumber");
  #  if ($cardtype !~ /($merch_cards_allowed)/i) {
  #    # error: card type not supported
  #    $result{'FinalStatus'} = "problem";
  #    $result{'MErrMsg'} = "Merchant does not accept this card type at this time.";
  #    $result{'resp-code'} = "PXX";
  #    return %result;
  #  }
  #}

  ## see if we need to charge an installment fee
  if (($billcycle > 0) && ($balance > 0) && (($monthly > 0) || $percent > 0)) {

    if ($balance > 0) { $balance = sprintf("%0.02f", $balance); }
    if ($monthly > 0) { $monthly = sprintf("%0.02f", $monthly); }
    if ($percent > 0) { $percent = sprintf("%f", $percent); }

    # calculate installment amount
    if (($balance > 0) && (($monthly > 0) || ($percent > 0))) {
      if ($percent > 0) {
        # figure out percentage installment amount
        $charge = ($percent / 100) * $balance;
        #$charge_type = "percent_installment"

        if (($percent > 0) && ($charge < $monthly)) {
          # now if installment is less then monthly minimim, charge the minimum
          $charge = $monthly;
          #$charge_type = "minimum_installment";
        }
      }
      else {
        # when invoice is only monthly based, set the monthly amount for the installment amount.
        $charge = $monthly;
        #$charge_type = "flatrate_installment";
      }

      # now if the balenace is less then the installment amount, charge the remaining balance only
      if ($charge > $balance) {
        $charge = $balance;
        #$charge_type = "remainder_installment"
      }
    }

    if ($charge > 0) { $charge = sprintf("%0.02f", $charge); }

    # now see about under & over payments
    if ($query{'payment_amount'} ne "") {
      $query{'payment_amount'} =~ s/[^0-9\.]//g;
      $query{'payment_amount'} = sprintf("%0.02f", $query{'payment_amount'});

      if ($query{'payment_amount'} < $charge) {
        # error: payment amount less then minimum allowed
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} = "Must pay at least the minimum specified.";
        $result{'resp-code'} = "PXX";
        return %result;
      }
      elsif ($query{'payment_amount'} > $balance) {
        # error: payment amount more then maximum allowed
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} = "Can only pay as much as current balance";
        $result{'resp-code'} = "PXX";
        return %result;
      }
      elsif (($query{'payment_amount'} <= $balance) && ($query{'payment_amount'} >= $charge)) {
        $charge = $query{'payment_amount'};
      }
    }
  }
  ## since we are not charging the installment fee, see if we need to charge the balance on the invoice
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

  my $orderid = new PlugNPay::Transaction::TransactionProcessor()->generateOrderID();

  my @array = (
    "publisher-name", "$merchant",
    "mode", "auth",
    "card-amount", "$charge",
    "tax", "$tax",
    "shipping", "$shipping",
    "handling", "$handling",
    "discount", "$discount",
    "orderID", "$orderid",
    "ipaddress", "$query{'ipaddress'}",
    "acct_code", "$account_no",
    "acct_code2", "$invoice_no",
    "acct_code3", "billpay",
    "card-name", "$cardname",
    "card-address1", "$cardaddr1",
    "card-address2", "$cardaddr2",
    "card-city", "$cardcity",
    "card-state", "$cardstate",
    "card-zip", "$cardzip",
    "card-country", "$cardcountry",
    "shipinfo", "1",
    "shipcompany", "$shipcompany",
    "shipname", "$shipname",
    "address1", "$shipaddr1",
    "address2", "$shipaddr2",
    "city", "$shipcity",
    "state", "$shipstate",
    "zip", "$shipzip",
    "country", "$shipcountry",
    "email", "$email",
    "phone", "$phone",
    "fax", "$fax",
    "public_notes", "$public_notes",
    "billpay_invoice_no", "$invoice_no",
    "billpay_account_no", "$account_no",
    "billpay_email", "$username"
  );

  if ($accttype =~ /checking|savings/i) {
    push (@array,
     "accttype", "$accttype",
     "routingnum", "$routingnum",
     "accountnum", "$accountnum",
     "paymethod", "$paymethod",
     "checknum", "$checknum",
     "acctclass", "$acctclass",
     "commcardtype", "$commcardtype" );
  }
  else {
    push (@array,
     "card-number", "$cardnumber",
     "card-exp", "$exp",
     "card-cvv", "$cvv",
     "commcardtype", "$commcardtype" );
  }

  if ($query{'comments'} =~ /\w/) {
    push(@array, "comments", "$query{'comments'}");
  }

  my $subtotal = 0;
  my $totalwgt = 0;

  $dbh = &miscutils::dbhconnect("billpres");

  my $cnt = 0;
  my $sth4 = $dbh->prepare(qq{
      select item, cost, qty, descr, weight, descra, descrb, descrc
      from billdetails2
      where username=? and invoice_no=? and merchant=?
      order by item
    }) or die "Cannot do: $DBI::errstr";
  $sth4->execute("$username", "$invoice_no", "$merchant") or die "Cannot execute: $DBI::errstr";
  my $rv = $sth4->bind_columns(undef,\($db_item, $db_cost, $db_qty, $db_descr, $db_weight, $db_descra, $db_descrb, $db_descrc));
  while($sth4->fetch) {
    if (($db_item ne "") && ($db_cost =~ /\d/) && ($db_qty > 0) && ($db_descr ne "")) {
      $cnt = $cnt + 1;
      $db_cost = sprintf("%0.02f", $db_cost);
      push (@array, "item$cnt", "$db_item", "cost$cnt", "$db_cost", "quantity$cnt", "$db_qty", "description$cnt", "$db_descr");

      if ($feature{'billpay_extracols'} =~ /weight/) {
        push (@array, "weight$cnt", "$db_weight");
      }
      if ($feature{'billpay_extracols'} =~ /descra/) {
        push (@array, "descra$cnt", "$db_descra");
      }
      if ($feature{'billpay_extracols'} =~ /descrb/) {
        push (@array, "descrb$cnt", "$db_descrb");
      }
      if ($feature{'billpay_extracols'} =~ /descrc/) {
        push (@array, "descrc$cnt", "$db_descrc");
      }

      $subtotal += ($db_cost * $db_qty);
      $totalwgt += ($db_weight * $db_qty);
    }
  }
  $sth4->finish;

  $totalwgt = sprintf("%s", $totalwgt);
  if ($totalwgt > 0) {
    push (@array, "test_wgt", "$totalwgt");
  }

  $subtotal = sprintf("%0.02f", $subtotal);
  if ($subtotal > 0) {
    push (@array, "subtotal", "$subtotal");
  }

  if ($cnt > 0) {
    push (@array, "receipt_type", "itemized", "easycart", "1");
  }
  else {
    push (@array, "receipt_type", "simple");
  }

  my $payment = mckutils->new(@array);
  %result = $payment->purchase("auth");
  $result{'auth-code'} = substr($result{'auth-code'},0,6);
  $payment->database();
  %remote::query = (%remote::query,%mckutils::query,%result);
  $payment->email();

  # record payment attempt
  my $sth5 = $dbh->prepare(qq{
      insert into billingstatus2
      (orderid, username, profileid, invoice_no, account_no, trans_date, amount, descr, result, billusername)
      values (?,?,?,?,?,?,?,?,?,?)
    }) or die "Cannot prepare: $DBI::errstr";
  $sth5->execute("$orderid", "$username", "$profileid", "$invoice_no", "$account_no", "$today", "$charge", "$remote::query{'descr'}", "$remote::query{'result'}", "$merchant") or die "Cannot execute: $DBI::errstr";
  $sth5->finish;

  $dbh->disconnect;

  if ($profileid ne "") {
    &record_bill_history("$username", "$profileid", "pay_bill", "Bill Payment Attempted - $remote::query{'result'}");
  }

  if ($result{'FinalStatus'} =~ /success/i) {
    # update transaction status

    # adjust balance, if needed
    if ($balance > 0) {
      $balance = $balance - $charge;
      $balance = sprintf("%0.02f", $balance);
      if ($balance < 0) {
        $balance = 0.00;
      }
    }

    # extend expire_date, if needed
    if (($billcycle > 0) && ($balance > 0) && (($monthly > 0) || ($percent > 0))) {
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

    if ($query{'comments'} =~ /\w/) {
      my @now = gmtime(time);
      my $today = sprintf("%02d\/%02d\/%04d \@ %02d\:%02d\:%02d GMT", $now[4]+1, $now[3], $now[5]+1900, $now[2], $now[1], $now[0]);
      $private_notes .= "\n$today - Customer Comments:\n$query{'comments'}\n";
      $private_notes =~ s/^\s+//g; # strip leading whitespace
      $private_notes =~ s/\s+$//g; # strip tailing whitespace
    }

    my $sth2 = $dbh->prepare(qq{
        update bills2
        set status=?, orderid=?, lastbilled=?, lastattempted=?, balance=?, expire_date=?, private_notes=?
        where username=? and invoice_no=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$status", "$remote::query{'orderID'}", "$today", "$today", "$balance", "$expire_date", "$private_notes", "$username", "$invoice_no", "$merchant") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    $result{'FinalStatus'} = "success";
    $result{'MErrMsg'} = "Your payment was approved.";

    #$data = &thankyou_template($dbh, %remote::query);
  }
  elsif ($result{'FinalStatus'} =~ /^(badcard|problem|fraud)$/i) {
    # don't do anything - leave transaction as is
    my $sth3 = $dbh->prepare(qq{
        update bills2
        set lastattempted=?
        where username=? and invoice_no=? and merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
    $sth3->execute("$today", "$username", "$invoice_no", "$merchant") or die "Cannot execute: $DBI::errstr";
    $sth3->finish;

    if ($result{'FinalStatus'} eq "badcard")  {
      $remote::query{'FinalStatus'} = "badcard";
      $result{'MErrMsg'} = "Your payment was declined.";
    }
    elsif ($result{'FinalStatus'} eq "problem")  {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Your payment cannot be processed at this time.  Please try again later.";
    }
    elsif ($result{'FinalStatus'} eq "fraud")  {
      $result{'FinalStatus'} = "fraud";
      $result{'MErrMsg'} = "Your payment was declined.";
    }
  }
  else {
    # Error: unknown FinalStatus response
    #$result{'FinalStatus'} = "problem";
    #$result{'MErrMsg'} = "Unknown payment response - please contact support.";
  }

  return %result;
}

sub detect_ach {
  # checks to see if ACH/eCheck can be used or not. (Yes = ok,  No = no ach)
  my ($merch_chkprocessor, $merchant) = @_;

  if ($merch_chkprocessor ne "") {
    my $ach_allowed = "no"; # assume ACH not allowed by default
    my ($cards_allowed, $allow_overpay) = &get_merchant_cards_allowed("$merchant"); # now get card types allowed

    # now see if checking or savings is allowed by the merchant
    my @temp = split(/ /, $cards_allowed);
    for (my $i = 0; $i <= $#temp; $i++) {
      if ($temp[$i] =~ /(checking|savings)/i) {
        $ach_allowed = "yes";
      }
    }
    return "$ach_allowed";
  }
  else {
    # error: no ACH/eCheck processor
    return "no";
  }
}

sub detect_cardtype {
  my ($cardnumber) = @_;

  my ($cardtype);

  my $cardbin = substr($cardnumber,0,6);
  if ( ($cardbin =~ /^(491101|491102)/)
    || ($cardbin =~ /^(564182)/)
    || ($cardbin =~ /^(490302|490303|490304|490305|490306|490307|490308|490309)/)
    || ($cardbin =~ /^(490335|490336|490337|490338|490339|490525|491174|491175|491176|491177|491178|491179|491180|491181|491182)/)
    || ($cardbin =~ /^(4936)/)
    || (($cardbin >= 633300) && ($cardbin < 633349))
    || (($cardbin >= 675900) && ($cardbin < 675999)) ) {
    $cardtype = "SWTCH";
  }
  elsif ( (($cardbin >= 633450) && ($cardbin < 633499)) || (($cardbin >= 676700) && ($cardbin < 676799)) ) {
    $cardtype = "SOLO";
  }
  elsif ($cardbin =~ /^(4)/) {
    $cardtype = "VISA";
  }
  elsif ($cardbin =~ /^(51|52|53|54|55)/) {
    $cardtype = "MSTR";
  }
  elsif ($cardbin =~ /^(37|34)/) {
    $cardtype = "AMEX";
  }
  elsif (($cardbin =~ /^(3088|3096|3112|3158|3337)/)
    || (($cardbin >= 352800) && ($cardbin < 359000))) {
    $cardtype = "JCB";
  }
  elsif ($cardbin =~ /^(30|36|38[0-8])/) {
    $cardtype = "DNRS";
  }
  elsif ($cardbin =~ /^(389)/) {
    $cardtype = "CRTB";
  }
  elsif ($cardbin =~ /^(6011)/) {
    $cardtype = "DSCR";
  }
  elsif ($cardbin =~ /^(1800|2131)/) {
    $cardtype = "JAL";
  }
  elsif ($cardbin =~ /^(7775|7776|7777)/) {
    $cardtype = "KC";
  }
  elsif ($cardbin =~ /^(7)/) {
    $cardtype = "MYAR";
  }

  return $cardtype;
}

sub record_bill_history {
  my ($username, $profileid, $action, $descr) = @_;

  if ($username eq "") {
    $username = $ENV{'REMOTE_USER'};
  }
  else {
    $username = substr($username,0,255);
  }

  $action = substr($action,0,20);
  $descr = substr($descr,0,200);

  my $ipaddress = $ENV{'REMOTE_ADDR'};

  my @now = gmtime(time);
  my $trans_time = sprintf("%04d%02d%02d%02d%02d%02d", $now[5], $now[4], $now[3], $now[2], $now[1], $now[0]);
  my $entryid = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5], $now[4], $now[3], $now[2], $now[1], $now[0], $$);

  my $dbh = &miscutils::dbhconnect("billpres");
  my $sth = $dbh->prepare(qq{
      insert into history2
      (entryid, ipaddress, trans_time, username, profileid, action, descr)
      values (?,?,?,?,?,?,?)
    }) or die "Cannot prepare: $DBI::errstr";
  $sth->execute("$entryid", "$ipaddress", "$trans_time", "$username", "$profileid", "$action", "$descr") or die "Cannot execute: $DBI::errstr";
  $sth->finish;
  $dbh->disconnect;

  return;
}


1;
