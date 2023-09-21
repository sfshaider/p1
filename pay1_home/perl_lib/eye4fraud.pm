#!/usr/local/bin/perl

package eye4fraud;

use strict;
use miscutils;

##Session Query via HTTPS post
# POST https://www.eye4fraud.com/api/
## Mandatory Inputs


sub check_transaction {
  my ($query,$APILogin,$APIKey,$SiteName,$itemCnt) = @_;
  my (%result,%req,%error,%res,$resp);

  my $url = "https://www.eye4fraud.com/api/";
  my $output = "";
  my $contype = "text/html";

  ## Mandatory
  $req{'SiteName'} = $SiteName;
  $req{'ApiLogin'} = $APILogin;
  $req{'ApiKey'} = $APIKey;


  ###  Additional Fields

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
  my $orderDate = sprintf("%04d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);

  $req{'TransactionId'} = $$query{'orderID'};
  $req{'OrderDate'} = $orderDate;
  $req{'OrderNumber'} = $$query{'order-id'};

  my ($fname, $mname, $lname);
  if ((! exists $$query{'card-fname'}) && (exists $$query{'card-name'})) {
    my @names = split(/\ +/,$$query{'card-name'});
    $fname = $names[0];
    $lname = $names[@names - 1];
    if (@names > 2) {
      $mname = $names[1];
    }
    $req{'BillingFirstName'} = $fname;
    $req{'BillingMiddleName'} = $mname;
    $req{'BillingLastName'} = $lname;
  }
  else {
    $req{'BillingFirstName'} = $$query{'card-fname'};
    $req{'BillingLastName'} = $$query{'card-lname'};
  }
  $req{'BillingCompany'} = $$query{'card-company'};
  $req{'BillingAddress1'} = $$query{'card-address1'};
  $req{'BillingAddress2'} = $$query{'card-address2'};
  $req{'BillingCity'} = $$query{'card-city'};
  $req{'BillingState'} = $$query{'card-state'};
  $req{'BillingZip'} = $$query{'card-zip'};
  $req{'BillingCountry'} = $$query{'card-country'};
  $req{'BillingEveningPhone'} = $$query{'phone'};
  $req{'BillingEmail'} = $$query{'email'};
  $req{'IPAddress'} = $$query{'ipaddress'};


  $fname = "";
  $mname = "";
  $lname = "";
  if ((! exists $$query{'shipfname'}) && (exists $$query{'shipname'})) {
    my @names = split(/\ +/,$$query{'shipname'});
    $fname = $names[0];
    $lname = $names[@names - 1];
    if (@names > 2) {
      $mname = $names[1];
    }
    $req{'ShippingFirstName'} = $fname;
    $req{'ShippingMiddleName'} = $mname;
    $req{'ShippingLastName'} = $lname;
  }
  else {
    $req{'ShippingFirstName'} = $$query{'card-fname'};
    $req{'ShippingLastName'} = $$query{'card-lname'};
  }

  $req{'ShippingCompany'} = $$query{'company'};
  $req{'ShippingAddress1'} = $$query{'address1'};
  $req{'ShippingAddress2'} = $$query{'address2'};
  $req{'ShippingCity'} = $$query{'city'};
  $req{'ShippingState'} = $$query{'state'};
  $req{'ShippingZip'} = $$query{'zip'};
  $req{'ShippingCountry'} = $$query{'country'};
  $req{'ShippingEveningPhone'} = $$query{''};
  $req{'ShippingEmail'} = $$query{'shipemail'};
  $req{'ShippingCost'} = $$query{'shipping'};
  $req{'GrandTotal'} = $$query{'card-amount'};
  $req{'CCType'} = $$query{'card-type'};
  $req{'CCFirst6'} = substr($fraud::cardnumber,0,6);
  $req{'CCLast4'} = substr($fraud::cardnumber,-4);
  $req{'CIDResponse'} = $$query{'cvvresp'};
  $req{'AVSCode'} = $$query{'avs-code'};
  #$req{'LineItems'} = $$query{''};


  ### OptionalFields
  $req{'CustomerID'} = $$query{'CustomerID'};
  $req{'BillingCellPhone'} = $$query{'BillingCellPhone'};
  $req{'ShippingMethod'} = $$query{'shipmethod'};
  $req{'ShippingCellPhone'} = $$query{'ShippingCellPhone'};
  $req{'CCExpires'} = $$query{'card-exp'};
  $req{'ReferringCode'} = $$query{'ReferringCode'};
  $req{'AlternateBillingEmail'} = $$query{'AlternateBillingEmail'};
  $req{'CustomerComments'} = $$query{'CustomerComments'};
  $req{'SalesRepComments'} = $$query{'SalesRepComments'};
  $req{'InboundCallerID'} = $$query{'InboundCallerID'};
  $req{'RepeatCustomer'} = $$query{'RepeatCustomer'};
  $req{'HighRiskDeliveryMethod'} = $$query{'HighRiskDeliveryMethod'};
  $req{'ShippingDeadline'} = $$query{'ShippingDeadline'};


  ### Order Details

  if ($itemCnt > 0) {
    for(my $i=1; $i<=$itemCnt; $i++) {
      my $ProductName = substr($$query{"item$i"},0,23);
      my $ProductQty = substr($$query{"quantity$i"},0,5);
      my $ProductSellingPrice = substr($$query{"cost$i"},0,9);
      my $ProductDescription = substr($$query{"description$i"},0,79);
      my $ProductCostPrice  = substr($$query{"customa$i"},0,79);

      $req{"LineItems[$i][ProductName]"}=$ProductName;
      $req{"LineItems[$i][ProductQty]"}=$ProductQty;
      $req{"LineItems[$i][ProductSellingPrice]"}=$ProductSellingPrice;
      $req{"LineItems[$i][ProductDescription]"}=$ProductDescription;
      $req{"LineItems[$i][ProductCostPrice]"}=$ProductCostPrice;
    }
  }

  my ($resp, %headers);

  ($resp, %headers) = &formpost(\%req,"$url","$$query{'publisher-name'}");

  my @linepairs = split(/\n\r?/,$resp);
  foreach my $pair (@linepairs) {
    my($key,$val) = split(/=/,$pair);
    $res{$key} = $val;
  }
  
  if (1) {
    my $now = gmtime(time);
    open (DEBUG,">>/home/p/pay1/database/debug/eye4fraud_debug.txt");
    print DEBUG "DATE:$now, IP:$ENV{'REMOTE_ADDR'}, SCRIPT:$ENV{'SCRIPT_NAME'}, PID:$$, URL:$url, ";
    foreach my $key (sort keys %req) {
      print DEBUG "RQ:$key:$req{$key}, ";
    }
    print DEBUG "\n";
    print DEBUG "RESP:$resp\n";
    foreach my $key (sort keys %res) {
      print DEBUG "RSP:$key:$res{$key}, ";
    }
    print DEBUG "\n";
    foreach my $key (sort keys %headers) {
      print DEBUG "H:$key:$headers{$key}, ";
    }
    print DEBUG "\n\n";
    close(DEBUG);
  }

  return %res;

}


sub formpost {
  my ($req,$url,$merchant) = @_;
  my $pairs = "";

  $url =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\|]/x/g;

  foreach my $key (keys %$req) {
    $_ = $$req{$key};
    s/(\W)/'%' . unpack("H2",$1)/ge;
    if($pairs ne "") {
      $pairs = "$pairs\&$key=$_" ;
    }
    else{
      $pairs = "$key=$_" ;
    }
  }

  my ($response,%headers) = &miscutils::formpostproxy("$url","$pairs","$merchant",'post');

  return ($response,%headers);

}






1;
