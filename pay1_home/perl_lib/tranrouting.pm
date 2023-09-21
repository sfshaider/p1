#!/usr/local/bin/perl

#$| = 1;

package tranrouting;

use miscutils;
use PlugNPay::Features;
use strict;


###
# Step 1. Grab Filter from Dbase
# Step 2. PRocess Filter and obtain new username
# Step 3 Validate returned UN is valid and on allowed list and if so reset publisher-name to new account.

sub new {
  my $type = shift;
  my ($query) = @_;
  $tranrouting::features = new PlugNPay::Features($$query{'publisher-name'},'general');

  return [], $type;
}


sub tran_routing {
  shift;
  my ($query) = @_;
  my ($filter);

  if ($tranrouting::features->get('routing_accts') eq "") {
    ### Acct Not set up for routing.  Abort abort abort
    return;
  }

  my $username = &acct_filters_query($query);
  if ($username ne "") {
    $$query{'publisher-name'} = $username;
  }

}

sub balance_routing {
  shift;
  my ($query) = @_;
  my ($filter);

  if ($tranrouting::features->get('chkvolume') eq "") {
    ### Acct Not set up for balancing.  Abort abort abort
    return;
  }

  my $username = &dailyBalance($tranrouting::features->get('chkvolume'),$$query{'card-amount'});

  if ($username ne "") {
    $$query{'publisher-name'} = $username;
  }
}

sub acct_filters_query {
  my ($query) = @_;

  my ($param,$filter,$filterid,$username);

  my $routing_accts = $tranrouting::features->get('routing_accts');

  my $dbh = &miscutils::dbhconnect("tranrouting");

  ## Loop through filters ordered by weight looking for a match.
  my $sth = $dbh->prepare(qq{
    select param,filter,filterid,username
    from filters
    where master=?
    order by weight
  }) or die "Can't do: $DBI::errstr";
  $sth->execute($$query{'publisher-name'}) or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($param,$filter,$filterid,$username));
  while($sth->fetch) {
    ### Check to make sure returned username is actually allowed.
    if ($username !~ /$routing_accts/) {
      next;
    }

    my $match = &parse_filter($param,$filter,$query);
    if ($match == 1) {
      ## Obtained match, return associated username
      ## Set name/value pair for debug
      $$query{'tranroutingmatch'} = "$$query{'publisher-name'},$filterid,$param,$filter";
      last;
    }
    else {
      # No match, erase username
      $username = "";
    }
  }
  $sth->finish;

  $dbh->disconnect;

  return $username;
}


sub parse_filter {
  my ($param,$filter,$query) = @_;

  my ($match);

  if ($param eq "cardbinregion") {
    $match = &BankBinRegion($filter,$query);
  }
  elsif ($param eq "cardcountry") {

  }
  elsif ($param eq "ipcountry") {

  }
  elsif ($param eq "cardtype") {

  }
  elsif ($param eq "cardproducttype") {
    ## i.e.  Debit

  }
  elsif ($param eq "amount") {

  }
  elsif ($param eq "currency") {

  }
  ### .....

  return $match;
}


sub BankBinRegion {
  require PlugNPay::Fraud::BankBin;
  my ($filter,$query) = @_;
  my ($match);

  my $bankbin = new PlugNPay::Fraud::BankBin($$query{'card-number'});

  my $region = $bankbin->getRegion();

  ###  TEMP CODE
  if ($region =~ /$filter/) {
    ### Match.
    $match = 1;
  }
  else {
    ### Do Nothing
    $match = 0;
  }
  return $match;
}



sub dailyBalance {
  my ($chkvolume,$cardamount) = @_;

  my (@linked_accounts,%linked_accounts,%dailyVol,$str,$username);

  my @array = split('\|',$chkvolume);
  my $k = 0;
  for(my $i=0; $i<=$#array; $i++) {
    $linked_accounts{$array[$i]} = $array[$i+1];
    $linked_accounts[$k] = $array[$i];
    $str .= "\'$array[$i]\',";
    $i++;
    $k++;
  }
  chop $str;

  my $balanceModeTest = 0;
  my $balanceMode = ""; ## Choices are serial || parallel   serial - fills up one account then moves on to 2nd, 3rd etc...  parallel spreads tran volume across multiple accounts based on weighting

  foreach my $key (keys %linked_accounts) {
    $balanceModeTest += $linked_accounts{$key};
  }
  if ($balanceModeTest <= 1) {
    $balanceMode = "parallel";
  }
  else {
    $balanceMode = "serial";
  }

  my $dailyTotal = 1;
  my %percentVol = (); ## Percent Volume that each account has currently processed.

  ### Obtain Current Daily Balance
  my $dbh1 = &miscutils::dbhconnect("pnpmisc");
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
  my $date = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);
  my ($volume);

  my $sth = $dbh1->prepare(qq{
        select username,volume
        from merch_stats
        where username in ($str) and trans_date=? and type='auth'
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%mckutils::query);
  $sth->execute("$date") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%mckutils::query);
  while (my $data = $sth->fetchrow_hashref()) {
    $dailyVol{$data->{'username'}} = $data->{'volume'};
    $dailyTotal += $data->{'volume'};
  }
  $sth->finish;
  $dbh1->disconnect;

  if ($balanceMode eq "serial") {
    foreach my $acct (@linked_accounts) {
      if ($dailyVol{$acct} < $linked_accounts{$acct}) {
        $username = $acct;
        ## First account found that has a daily balance less then limit.  Return account.
        last;
      }
    }
  }
  else {
    foreach my $key (keys %linked_accounts) {
      my $targetVol = $dailyTotal * $linked_accounts{$key};
      my $actualVol = $dailyVol{$key};

     ### Chris says we should calculate what values would look like with current transaction added.
#      my $targetVol = ($dailyTotal + $cardamount) * $linked_accounts{$key};
#      my $actualVol = $dailyVol{$key} + $cardamount;
      $percentVol{$key} =  sprintf("%.2f",$actualVol/$targetVol);
    }
    my $lowPercent = 100000;
    foreach my $key (keys %percentVol) {
      if ($percentVol{$key} <= $lowPercent) {
        $username = $key;
        $lowPercent = $percentVol{$key};
      }
    }
  }
  return $username;
}


1;
