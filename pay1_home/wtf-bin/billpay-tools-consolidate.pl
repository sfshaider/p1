#!/bin/env perl

# Purpose: this script should be run on the 1st of every month
# It pulls all consolidated invoices from the billpay database & creates consolided versions
# It also is supposed to compare the invoiced bills between 2 merchants & only charge the one which is owed money. (NOT APPLIED YET)

# Last Updated: 08/15/09

require 5.001;
$| = 1;

use lib '/home/p/pay1/perl_lib';
use miscutils;
use strict;
use PlugNPay::GatewayAccount;

my %tally = (); # hash of hashes, which holds the tally of each merchant's clients consoldidated bills
my %invoices = (); # hash of hashes, which keeps track of the invoices numbers & its amount, that were consoldated for each merchant's clients.

open(LOG, ">>./consolidate.log") or die "Cannot open consolidate.log for appending. $!"; 

my @now = gmtime(time);
my $today = sprintf("%04d%02d%02d", $now[5]+1900, $now[4]+1, $now[3]);

my ($db_merchant, $db_client, $db_invoice_no, $db_amount, $db_balance);

my $dbh = &miscutils::dbhconnect("billpres");
my $dbh_misc = &miscutils::dbhconnect("pnpmisc");

## pull all 'open' status invoices, which are consolidate flagged, have not expired & is not an already consolidated invoice
my $sth = $dbh->prepare(qq{
    select merchant, username, invoice_no, amount, balance
    from bills2
    where status=? and consolidate=? and expire_date>=? and account_no NOT LIKE ?
    order by merchant
  }) or die "Cannot do: $DBI::errstr";
$sth->execute("open", "yes", "$today", "consolidated_%") or die "Cannot execute: $DBI::errstr";
my $rv = $sth->bind_columns(undef,\($db_merchant, $db_client, $db_invoice_no, $db_amount, $db_balance));
while($sth->fetch) {
  printf LOG ("%s - Importing: %s, %s, %s, %s\n", $today, $db_merchant, $db_client, $db_invoice_no, $db_amount);

  ## add invoice's total to tally
  #print "Before: $tally{$db_mercant}{$db_client}\n";
  if (($db_balance > 0) && ($db_balance < $db_amount)) {
    # charge remaining balance
    $tally{"$db_merchant"}{"$db_client"} = $tally{"$db_merchant"}{"$db_client"} + $db_balance;
  }
  else {
    # charge full amount
    $tally{"$db_merchant"}{"$db_client"} = $tally{"$db_merchant"}{"$db_client"} + $db_amount;
  }
  #print "After: $tally{$db_merchant}{$db_client}\n";

  ## add invoice's number to invoice list
  #print "Before: $invoices{$db_mercant}{$db_client}\n";
  $invoices{"$db_merchant"}{"$db_client"} = $invoices{"$db_merchant"}{"$db_client"} . "\|" . $db_invoice_no . "\," . $db_amount;
  #print "After: $invoices{$db_merchant}{$db_client}\n";
}
$sth->finish;

$dbh->disconnect;
$dbh_misc->disconnect;

# display the totals.
# print the whole thing somewhat sorted
foreach my $k1 ( sort keys %tally ) {
  print LOG "Merchant: $k1\n";

  # from merchant's reseller info, figure out what admin domain the customer should use
  my $sth_merch = $dbh_misc->prepare(qq{
      select admindomain
      from privatelabel
      where username=?
    }) or die "Can't prepare: $DBI::errstr";
  $sth_merch->execute("$k1") or die "Can't execute: $DBI::errstr";
  my $merch_admindomain = $sth_merch->fetchrow;
  $sth_merch->finish;

  if ($merch_admindomain eq "") {
    $merch_admindomain = "pay1.plugnpay.com";
  }

  my $gatewayAccount = new PlugNPay::GatewayAccount($k1);
  my $merchant_company = $gatewayAccount->getCompanyName();

  # get merchant's company name
  my $sth2 = $dbh_misc->prepare(qq{
      select features
      from customers
      where username=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth2->execute("$k1") or die "Cannot execute: $DBI::errstr";
  my $db_features = $sth2->fetchrow;
  $sth2->finish;
  $dbh_misc->disconnect;

  # parse feature list into hash
  my %feature_list;
  if ($db_features =~ /(.*)=(.*)/) {
    my @array = split(/\,/,$db_features);
    foreach my $entry (@array) {
      my ($name, $value) = split(/\=/, $entry);
      $feature_list{"$name"} = "$value";
    }
  }

  # grab default email options
  my $merch_email_cust = $feature_list{'billpay_email_cust'};   # default email customer setting
  my $merch_express_pay = $feature_list{'billpay_express_pay'}; # default express pay setting
  my $merch_pubemail = lc($feature_list{'pubemail'}); # grab Email Management's publisher-email address

  # grab merchant's settings for how long consolided invoices are good for
  $feature_list{'billpay_payperiod'} =~ s/[^0-9]//g;
  if ($feature_list{'billpay_payperiod'} < 1) {
    $feature_list{'billpay_payperiod'} = 7; # default to 7 days, for consolidated invoices when not specified
  }

  # set starting invoice number for merchant's new consoldied invoices
  my $invoice_no = sprintf("%04d%02d%02d%02d%02d%02d%05d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0], 00000);

  # figure out the expire date for merchant's new consolidated invoices
  my @expire_time = gmtime(time + ($feature_list{'billpay_payperiod'} * 86400)); # 1 day = 86400 seconds
  my $expire = sprintf("%04d%02d%02d", $expire_time[5]+1900, $expire_time[4]+1, $expire_time[3]);

  # loop through merchant's consolidated invoices
  for my $k2 ( sort keys %{ $tally{$k1} } ) {
    print LOG "-- Client: $k2 = $tally{$k1}{$k2}\n";

    my %row_data; # this holds the consolidated invoice's details

    # include certain basic fields/settings
    $row_data{'merchant'} = $k1;
    $row_data{'merch_company'} = $merch_company;
    $row_data{'merch_pubemail'} = $merch_pubemail;
    $row_data{'merch_admindomain'} = $merch_admindomain;
    $row_data{'overwrite'} = "yes";
    $row_data{'email_cust'} = "yes";
    $row_data{'express_pay'} = $merch_express_pay;

    # add the customer's data to the consolidated invoice
    $row_data{'email'} = $k2;

    $row_data{'enter_date'} = $today;
    $row_data{'expire_date'} = $expire;

    $row_data{'invoice_no'} = $invoice_no;
    $row_data{'account_no'} = "consolidated_$today";

    $row_data{'status'} = "open";

    #if (($row_data{'billcycle'} > 0) && ($row_data{'monthly'} > 0)) {
    #  $row_data{'billcycle'} =~ s/\D//g;
    #  $row_data{'monthly'} =~ s/[^0-9\.]//g;
    #  $row_data{'monthly'} = sprintf("%0.2f", $row_data{'monthly'});
    #}
    #else {
    #  $row_data{'billcycle'} = "";
    #  $row_data{'monthly'} = "";
    #}

    #if ($row_data{'balance'} > 0) {
    #  $row_data{'balance'} =~ s/[^0-9\.]//g;
    #  if ($row_data{'balance'} eq "") {
    #    $row_data{'balance'} = $row_data{'amount'};
    #  }
    #  $row_data{'balance'} = sprintf("%0.2f", $row_data{'balance'});
    #}
    #else {
    #  $row_data{'balance'} = "";
    #}

    $row_data{'amount'} = $tally{$k1}{$k2};

    print LOG "---- Invoices:\n";
    my @temp = split(/\|/, $invoices{"$k1"}{"$k2"});
    foreach (my $i = 0; $i <= $#temp; $i++) {
      if ($temp[$i] =~ /\w/) {
        my ($invoice, $amount) = split(/\,/, $temp[$i]);
        printf LOG ("     %s => %0.2f\n", $invoice, $amount);

        # filter out unwanted characters from product data
        $row_data{"item$i"} = "invoice$i";
        $row_data{"cost$i"} = $amount;
        $row_data{"qty$i"} = 1;
        $row_data{"descr$i"} = "Invoice: $invoice";

        #### close invoice with a 'merged' status (consider adding the invoice_no it was consolidated into).
        my $sth3 = $dbh->prepare(qq{
             update bills2
             set status=? 
             where merchant=? and username=? and invoice_no=?
          }) or die "Cannot prepare: $DBI::errstr";
        $sth3->execute("merged", "$k1", "$k2", "$invoice") or die "Cannot execute: $DBI::errstr";
        $sth3->finish;
      }
    }

    #### should create & send new invoice to client, with all of these consolidatd invoices in it.

    # add invoice to database
    &update_bill(%row_data);

    # incriment invoice number for use with next new consoldied invoice
    $invoice_no = $invoice_no + 1;
  }
  print LOG "\n";
}

close(LOG);

exit;

sub update_bill {
  my %query = @_;

  my $data;

  # do data filtering & other checks
  # login email address filter
  $query{'email'} =~ s/\,(com|org|net|mil|gov|tv|cc|ws|info|biz|bz)$/\.$1/;
  $query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.]//g;
  $query{'email'} =~ lc($query{'email'});

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
    print LOG "ERROR: Invalid email address \"$query{'email'}\".\n";
    return;
  }

  $query{'invoice_no'} =~ s/[^a-zA-Z0-9\_\-]//g;
  $query{'account_no'} =~ s/[^a-zA-Z0-9\_\-\ ]//g;
  $query{'amount'} = sprintf("%0.2f", $query{'amount'});

  $query{'status'} = lc($query{'status'});
  $query{'status'} =~ s/[^a-z]//g;
  if ($query{'status'} !~ /^(open|closed|paid)$/) {
    $query{'status'} = "open";
  }

  $query{'orderid'} =~ s/\D//g;

  $query{'tax'} =~ s/[^0-9\.]//g;
  $query{'tax'} = sprintf("%0.2f", $query{'tax'});

  $query{'shipping'} =~ s/[^0-9\.]//g;
  $query{'shipping'} = sprintf("%0.2f", $query{'shipping'});

  $query{'handling'} =~ s/[^0-9\.]//g;
  $query{'handling'} = sprintf("%0.2f", $query{'handling'});

  $query{'discount'} =~ s/[^0-9\.]//g;
  $query{'discount'} = sprintf("%0.2f", $query{'discount'});

  if (($query{'billcycle'} > 0) && ($query{'monthly'} > 0)) {
    $query{'billcycle'} =~ s/\D//g;

    $query{'monthly'} =~ s/[^0-9\.]//g;
    $query{'monthly'} = sprintf("%0.2f", $query{'monthly'});
  }
  else {
    $query{'billcycle'} = "";
    $query{'monthly'} = "";
  }

  if ($query{'balance'} > 0) {
    $query{'balance'} =~ s/[^0-9\.]//g;
    if ($query{'balance'} eq "") {
      $query{'balance'} = $query{'amount'};
    }
    $query{'balance'} = sprintf("%0.2f", $query{'balance'});
  }
  else {
    $query{'balance'} = "";
  }

  $query{'public_notes'} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]/ /g;
  $query{'private_notes'} =~ s/[^a-zA-Z_0-9\ \_\-\.\,]/ /g;

  # check for invoice_no existance
  my $sth1 = $dbh->prepare(qq{
      select invoice_no 
      from bills2
      where username=? and invoice_no=? and merchant=?
    }) or die "Cannot prepare: $DBI::errstr";
  $sth1->execute("$query{'email'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
  my ($db_invoice_no) = $sth1->fetchrow;
  $sth1->finish;

  if (($db_invoice_no eq "$query{'invoice_no'}") && ($query{'overwrite'} eq "yes")) {
    # if match was found, allow the update to happen
    my $sth2 = $dbh->prepare(qq{
        update bills2
        set enter_date=?, expire_date=?, account_no=?, amount=?, status=?, orderid=?, tax=?, shipping=?, handling=?, discount=?, billcycle=?, monthly=?, balance=?, public_notes=?, private_notes=?
        where username=? and invoice_no=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$query{'enter_date'}", "$query{'expire_date'}", "$query{'account_no'}", "$query{'amount'}", "$query{'status'}", "$query{'orderid'}", "$query{'tax'}", "$query{'shipping'}", "$query{'handling'}", "$query{'discount'}", "$query{'billcycle'}", "$query{'monthly'}", "$query{'balance'}", "$query{'public_notes'}", "$query{'private_notes'}", "$query{'email'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    my $sth3 = $dbh->prepare(qq{
        delete from billdetails2
        where username=? and invoice_no=? and merchant=?
      }) or die "Cannot prepare: $DBI::errstr";
    $sth3->execute("$query{'email'}", "$query{'invoice_no'}", "$query{'merchant'}") or die "Cannot execute: $DBI::errstr";
    $sth3->finish;

    #sleep(2);

    for (my $i = 1; $i <= 50; $i++) {
      # filter out unwanted characters from product data
      $query{"item$i"} =~ s/[^a-zA-Z_0-9\_\-]//g;
      $query{"cost$i"} =~ s/[^0-9\.]//g;
      $query{"cost$i"} = sprintf("%0.2f", $query{"cost$i"});
      $query{"qty$i"} =~ s/[^0-9\.]//g;
      $query{"descr$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.]//g;

      if (($query{"item$i"} ne "") && ($query{"cost$i"} >= 0) && ($query{"qty$i"} > 0) && ($query{"descr$i"} ne "")) {
        my $sth4 = $dbh->prepare(qq{
            insert into billdetails2
            (merchant, username, invoice_no, item, cost, qty, descr, amount)
            values (?,?,?,?,?,?,?,?)
          }) or die "Cannot prepare: $DBI::errstr";
        $sth4->execute("$query{'merchant'}", "$query{'email'}", "$query{'invoice_no'}", "$query{\"item$i\"}", "$query{\"cost$i\"}", "$query{\"qty$i\"}", "$query{\"descr$i\"}", "$query{'amount'}") or die "Cannot execute: $DBI::errstr";
        $sth4->finish;
      }
    }

    print LOG " + Consolidated Invoice \'$query{'invoice_no'}\' updated.\n";
  }
  elsif (($db_invoice_no eq "$query{'invoice_no'}") && ($query{'overwrite'} ne "yes")) {
    print LOG " + Consolidated Invoice \'$query{'invoice_no'}\' rejected. Invoice already exists in database...\n";
  }
  else {
    # if no match was found, allow the insert to happen
    my $sth2 = $dbh->prepare(qq{
        insert into bills2
        (merchant, username, invoice_no, enter_date, expire_date, account_no, amount, status, orderid, tax, shipping, handling, discount, billcycle, monthly, balance, public_notes, private_notes)
        values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      }) or die "Cannot prepare: $DBI::errstr";
    $sth2->execute("$query{'merchant'}", "$query{'email'}", "$query{'invoice_no'}", "$query{'enter_date'}", "$query{'expire_date'}", "$query{'account_no'}", "$query{'amount'}", "$query{'status'}", "$query{'orderid'}", "$query{'tax'}", "$query{'shipping'}", "$query{'handling'}", "$query{'discount'}", "$query{'billcycle'}", "$query{'monthly'}", "$query{'balance'}", "$query{'public_notes'}", "$query{'private_notes'}") or die "Cannot execute: $DBI::errstr";
    $sth2->finish;

    for (my $i = 1; $i <= 50; $i++) {
      # filter out unwanted characters from product data
      $query{"item$i"} =~ s/[^a-zA-Z_0-9\_\-]//g;
      $query{"cost$i"} =~ s/[^0-9\.]//g;
      $query{"cost$i"} = sprintf("%0.2f", $query{"cost$i"});
      $query{"qty$i"} =~ s/[^0-9\.]//g;
      $query{"descr$i"} =~ s/[^a-zA-Z_0-9\ \_\-\.]//g;

      if (($query{"item$i"} ne "") && ($query{"cost$i"} >= 0) && ($query{"qty$i"} > 0) && ($query{"descr$i"} ne "")) {
        my $sth = $dbh->prepare(qq{
            insert into billdetails2
            (merchant, username, invoice_no, item, cost, qty, descr, amount)
            values (?,?,?,?,?,?,?,?)
          }) or die "Cannot prepare: $DBI::errstr";
        $sth->execute("$query{'merchant'}", "$query{'email'}", "$query{'invoice_no'}", "$query{\"item$i\"}", "$query{\"cost$i\"}", "$query{\"qty$i\"}", "$query{\"descr$i\"}", "$query{'amount'}") or die "Cannot execute: $DBI::errstr";
        $sth->finish;
      }
    }

    print LOG " + Consolidated Invoice \'$query{'invoice_no'}\' added.\n";
  }

  if ($query{'email_cust'} eq "yes") {
    &email_customer(%query);
  }

  return;
}

sub email_customer {
  my %query = @_;

  my $emailmessage = "";

  # send email to customer
  #open(MAIL,"| /usr/lib/sendmail -t");
  $emailmessage .= "To: $query{'email'}\n";
  if ($query{'merch_pubemail'} =~ /\w/) {
    $emailmessage .= "From: $query{'merch_pubemail'}\n";
  }
  else {
    $emailmessage .= "From: billpaysupport\@plugnpay.com\n";
  }
  $emailmessage .= "Subject: Billing Presentment - $query{'merch_company'} - $query{'invoice_no'}\n";
  $emailmessage .= "\n";

  $emailmessage .= "A new consolidated invoice has been inserted into the Billing Presentment system, which relates to your account.\n";
  $emailmessage .= "\n\n";

  $emailmessage .= "Merchant: $query{'merch_company'}\n";
  $emailmessage .= "Email: $query{'email'}\n";
  $emailmessage .= "Invoice Number: $query{'invoice_no'}\n";
  if ($query{'account_no'} =~ /\w/) {
    $emailmessage .= "Account Number: $query{'account_no'}\n";
  }
  #$emailmessage .= sprintf ("Enter Date: %02d\/%02d\/%04d\n", substr($query{'enter_date'},4,2), substr($query{'enter_date'},6,2), substr($query{'enter_date'},0,4));
  $emailmessage .= sprintf ("Expire Date: %02d\/%02d\/%04d\n", substr($query{'expire_date'},4,2), substr($query{'expire_date'},6,2), substr($query{'expire_date'},0,4));

  $emailmessage .= "Amount: $query{'amount'}\n";
  $emailmessage .= "Status: $query{'status'}\n";
  if ($query{'monthly'} > 0) {
    $emailmessage .= "Installment Fee: $query{'monthly'}\n";
  }
  if ($query{'balance'} > 0) {
    $emailmessage .= "Balance: $query{'balance'}\n";
  }

  $emailmessage .= "\n";
  $emailmessage .= "Once logged in, you may go to the following URL to see the full invoice:\n";
  $emailmessage .= "https://$query{'merch_admindomain'}/billpay/edit.cgi\?function=view_bill_details_form\&invoice_no=$query{'invoice_no'}\n";

  $emailmessage .= "\n";
  $emailmessage .= "Don\'t have a Billing Presentment account yet, sign-up for FREE online:\n";
  $emailmessage .= "https://$query{'merch_admindomain'}/billpay_signup.cgi\n";

  $emailmessage .= "\n";
  $emailmessage .= "This free sign-up allows you to login, so you may review \& pay all invoiced bills you receive from $query{'merch_company'} online.\n";

  if ($query{'express_pay'} eq "yes") {
    $emailmessage .= "\n";
    $emailmessage .= "Wish to make a one-time express payment, go to the below URL:\n";
    $emailmessage .= "https://$query{'merch_admindomain'}/billpay_express.cgi\?email=$query{'email'}\&invoice_no=$query{'invoice_no'}\n";
  }

  $emailmessage .= "\n";
  if ($query{'merch_pubemail'} =~ /\w/) {
    $emailmessage .= "If you have questions on this invoice, please contact us at \"$query{'merch_pubemail'}\".\n\n";
  }
  else {
    $emailmessage .= "If you have questions on this invoice, please contact the merchant noted above directly.\n\n";
  }

  $emailmessage .= "Thank you,\n";
  $emailmessage .= "$query{'merch_company'}\n";
  $emailmessage .= "Support Staff\n\n";

#$emailmessage .= "------------------------------------------------\n";
#foreach my $key (sort keys %query) {
#  $emailmessage .= "QUERY: $key = $query{$key}\n";
#}

  #close(MAIL);

  my @now = gmtime(time);
  my $today = sprintf("%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);

  my %errordump = ("billpres_upload","$today");
  my ($junk1,$junk2,$message_time) = &miscutils::genorderid();
  my $dbh_email = &miscutils::dbhconnect("emailconf");
  my $sth_email = $dbh_email->prepare(qq{
      insert into message_que2
      (message_time,username,status,format,body)
      values (?,?,?,?,?)
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%errordump);
  $sth_email->execute("$message_time","$query{'merchant'}","pending","text","$emailmessage") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%errordump);;
  $sth_email->finish;
  $dbh_email->disconnect;

  return;
}

##############################################################################################################################3

##### This is the basic code on how to compaire 2 different accounts to each other & see who needs to actually be billed

## now see if client should be billed by merchant:
## so loop through each merchant
#foreach $k1 ( sort keys %tally ) {
#  print "Merchant: $k1\n";
#
#  # now loop through each of the merchant's clients
#  for $k2 ( sort keys %{ $tally{$k1} } ) {
#    #print "-- Client: $k2 = \$$tally{$k1}{$k2}\n";
#
#    # figure out balance [merchant's client total, minus client's merchant total]
#    my $balance = $tally{$k1}{$k2} - $tally{$k2}{$k1};
#    #print "------ Balance: \$$balance\n";
#
#    if ($balance > 0) {
#      # only charge the client when balance is in favor of merchant
#      print "------ CHARGE: Client $k2 - \$$balance\n";
#    }
#  }
#  print "\n";
#}

##### This is the basic code on how to list the various merchant's clients & what their total due is for their consolided flagged bills.

## display the totals...
## print the whole thing somewhat sorted
#foreach $k1 ( sort keys %tally ) {
#  print "Merchant: $k1\n";
#  for $k2 ( sort keys %{ $tally{$k1} } ) {
#    print "-- Client: $k2 = $tally{$k1}{$k2}\n";
#  }
#  print "\n";
#}

##### Ideas:
# - use 'alias' field to assocate a PnP merchant to a given group of customer's records, so we can match username records


