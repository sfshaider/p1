#!/usr/local/bin/perl

package nisc;
 
require 5.001;
 
use miscutils;
use rsautils;
use strict;


sub storealliance {
  my ($username,$operation,@pairs) = @_;
  my %result = ();
  my %query = @pairs;  
  my $orderID = $query{'order-id'};
  my $amount = $query{'amount'};
 
  my $dbh_dup = &miscutils::dbhconnect("pnpmisc");
  my $sth_dup = $dbh_dup->prepare(qq{
        select operation
        from alliancehold
        where orderid='$orderID'
        and username='$username'
        and operation='$operation'
        }) or die "Can't do: $dbi::errstr";
  $sth_dup->execute;
  my ($chkfinalstatus) = $sth_dup->fetchrow;
  $sth_dup->finish;
  $dbh_dup->disconnect;
 
  if ($chkfinalstatus eq "") {
    if ($amount ne "") {
      $result{'FinalStatus'} = "pending";
      $result{'MStatus'} = "pending";
      $result{'MErrMsg'} = "";
      $result{'Duplicate'} = "";
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} = "No amount given";
      return %result;
    }
  }
  else {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "problem";
    $result{'MErrMsg'} = "Duplicate $alliance::operation";
    $result{'Duplicate'} = "yes";
    return %result;
  }
 
  my $trans_time = (&miscutils::gendatetime())[2];
 
  my ($enccardnumber,$length) = &rsautils::rsa_encrypt_card($query{'card-number'},'/home/p/pay1/pwfiles/keys/key');
 
  my $pairs_string = "";
  foreach my $key (keys %query) {
    if (($key ne "card-number")  && ($key ne "order-id") && ($key ne "operation")) {
      $pairs_string .= "$key\t$query{$key}\t";
    }
  }
  chomp $pairs_string;

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(qq{
          insert into alliancehold
          (username,trans_time,operation,orderID,enccardnumber,length,pairs)
          values (?,?,?,?,?,?,?)
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute("$username","$trans_time","$operation","$orderID","$enccardnumber","$length","$pairs_string") 
                or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  $sth->finish;
  $dbh->disconnect;

  $result{'FinalStatus'} = "pending";
  $result{'MStatus'} = "pending";
  $result{'auth-code'} = "";
  $result{'resp-code'} = "00"; 
  $result{'MErrMsg'} = "";
  $main::result{'FinalStatus'} = "pending";
  $main::result{'MStatus'} = "pending";

  return %result;
}



1;
