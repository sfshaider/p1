package PlugNPay::Transaction::TransactionRouting;

use PlugNPay::Features;
use PlugNPay::CreditCard;
use PlugNPay::Fraud::BankBin;
use PlugNPay::Fraud::GeoLocate;
use PlugNPay::Logging::DataLog;
use PlugNPay::API;
use PlugNPay::Transaction;
use PlugNPay::Transaction::MapAPI;
use PlugNPay::Transaction::Routing::Filter;
use strict;

###
# Step 1. Grab Filter from Dbase
# Step 2. Process Filter and obtain new username
# Step 3 Validate returned UN is valid and on allowed list and if so reset pt_gateway_account to new account.

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;

  return $self;
}

sub setTransaction {
  my $self = shift;
  my $transaction = shift;
  $self->{'transaction'} = $transaction->clone();
  $self->_setFeatures();
}

sub getTransaction {
  my $self = shift;
  return $self->{'transaction'};
}

sub setLegacyTransaction {
  my $self = shift;
  my $query = shift;

  my $api = new PlugNPay::API('api_payment');
  $api->setLegacyParameters($query);
  my $payType = $query->{'accttype'} || 'card';
  my $transaction = new PlugNPay::Transaction('auth', $payType);
  # some day maybe paymethod will be consistent?
  $transaction->setGatewayAccount($api->parameter('pt_gateway_account'));
  my $mapper = new PlugNPay::Transaction::MapAPI();
  $mapper->setAPI($api);
  $mapper->setTransaction($transaction);
  $mapper->map();

  $self->{'transaction'} = $transaction;
  $self->_setFeatures();
}

sub setIPAddress {
  my $self = shift;
  my $ipaddress = shift;

  $self->{'ipAddress'} = $ipaddress;
}

sub _setFeatures {
  my $self = shift;
  $self->{'features'} = new PlugNPay::Features($self->{'transaction'}->getGatewayAccount(),'general');
}

sub tranRouting {
  my $self = shift;
  my $username = $self->{'transaction'}->getGatewayAccount();
  if ($self->{'features'}->get('routing_accts') ne '') {
    ### Acct set up for routing.
    $username = $self->_acctFiltersQuery();
  }

  if ($username ne $self->{'transaction'}->getGatewayAccount()) {
    $self->{'transaction'}->setGatewayAccount($username);
    $self->_logMatch({
        'message'=> 'Transaction Routing Match Found',
        'originalUsername' => $self->{'transaction'}->getGatewayAccount(), 
        'username'         => $username,
        'orderID'          => $self->{'transaction'}->getOrderID(),
        'routeType'        => 'transactionRouting'
    });
  }

  return $username; 
}

sub balanceRouting {
  my $self = shift;
  my $username = $self->{'transaction'}->getGatewayAccount();

  if ($self->{'features'}->get('chkvolume') ne '') {
    $username = $self->_dailyBalance();
  }

  if ($username ne $self->{'transaction'}->getGatewayAccount()) {
    $self->{'transaction'}->setGatewayAccount($username);
    $self->_logMatch({
        'message'=> 'Balance Routing Match Found',
        'originalUsername' => $self->{'transaction'}->getGatewayAccount(),
        'username'         => $username, 
        'orderID'          => $self->{'transaction'}->getOrderID(),
        'routeType'        => 'balanceRouting'
    });
  }

  return $username;
}

sub _acctFiltersQuery {
  my $self = shift;

  my $routing_accts = $self->{'features'}->get('routing_accts');

  my $filters = new PlugNPay::Transaction::Routing::Filter();
  $filters->setMaster($self->{'transaction'}->getGatewayAccount());
  my $results = $filters->get();

  my %matched = ();
  # loop through and make sure each rule for a filterid matched
  foreach my $filter (@{$results}) {
    ### Check to make sure returned username is actually allowed.
    if ($filter->{'username'} !~ /$routing_accts/) {
      next;
    }

    if (!exists $matched{$filter->{'filterid'}}) {
      $matched{$filter->{'filterid'}} = 1;
    }

    $matched{$filter->{'filterid'}} = $matched{$filter->{'filterid'}} && $self->_parseFilter($filter->{'param'},$filter->{'filter'});
  }

  # return the username for the first filter that fully matched
  foreach my $filter (@{$results}) {
    if ($matched{$filter->{'filterid'}}) {
      ## Obtained match, return associated username
      ## Set name/value pair for debug
      $self->{'tranRoutingMatch'} = "$filter->{'username'},$filter->{'filterid'},$filter->{'param'},$filter->{'filter'}";
      return $filter->{'username'};
    } 
  }

  return $self->{'transaction'}->getGatewayAccount();
}

sub _parseFilter {
  my $self = shift;
  my $param = shift;
  my $filter = shift;
  if (ref($self->{'transaction'}->getPayment()) eq 'PlugNPay::CreditCard') {
    if ($param eq "cardbinregion") {
      return $self->_cardBinRegion($param,$filter);
    } elsif (($param =~ /^(cardcategory|cardtype|cardbrand|cardisbiz|cardisdebit)$/)) {
      ### brand = Visa, MC, AMEX Etc...
      ### type = debit/credit
      ### category = business, consumer
      return $self->_cardRouting($param,$filter);
    }
  }
  if ($param eq "ipcountry") {
    return $self->_ipCountry($param,$filter);
  } else {  ### Any other paramters that only require a simple filter match
    return $self->_regexMatch($param,$filter);
  }
}

sub _regexMatch {
  my $self = shift;
  my $param = shift;
  my $filter = shift;
  my $value = "";

  if ($param eq 'pt_billing_country') {
    $value = $self->{'transaction'}->getBillingInformation()->getCountry;
  } elsif ($param eq 'pt_shipping_country') {
    $value = $self->{'transaction'}->getShippingInformation()->getCountry;
  } elsif ($param eq 'pt_currency') {
    $value = lc $self->{'transaction'}->getCurrency();
  } elsif ($param eq 'pt_transaction_amount') {
    $value = $self->{'transaction'}->getTransactionAmount();
  } elsif (($param eq 'pt_ach_account_type') && (ref($self->{'transaction'}->getPayment()) eq 'PlugNPay::OnlineCheck')) {
    $value = $self->{'transaction'}->getPayment()->getAccountType();
  } elsif ($param eq 'pb_override_adjustment') {
    $value = $self->{'transaction'}->getOverrideAdjustment();
  } else {
    return 0;
  }

  return $self->_checkFilter($value,$filter);
}

sub _cardBinRegion {
  my $self = shift;
  my $param = shift;
  my $filter = shift;

  my $bankbin = new PlugNPay::Fraud::BankBin($self->{'transaction'}->getCreditCard());
  my $region = $bankbin->getRegion();

  return $self->_checkFilter($region,$filter);
}

sub _ipCountry {
  my $self = shift;
  my $param = shift;
  my $filter = shift;

  my $locate = new PlugNPay::Fraud::GeoLocate($self->{'ipAddress'});

  return $self->_checkFilter($locate->getCountry(),$filter);
}

sub _cardRouting {
  my $self = shift;
  my $param = shift;
  my $filter = shift;
  my $differentiator;
  my $filterCheck = 0;
  my $card = $self->{'transaction'}->getCreditCard();
  if ($param eq "cardcategory") {  ### debit/consumer/rewards/business
    $differentiator = $card->getCategory();
  } elsif ($param eq "cardtype") {   ####  debit|credit|Business
    $differentiator = $card->getType();
  } elsif ($param eq "cardbrand") {  ###  Visa,Mastercard,Amex
    $differentiator = $card->getBrand();
  } elsif ($param eq "cardisbiz") {  ###  Consumer|Business
    $differentiator = $card->isBusinessCard();
  } elsif ($param eq "cardisdebit") {  ###  is Debit | Credit
    $differentiator = $card->isDebit();
  }
  if (defined $differentiator) {
    $filterCheck = $self->_checkFilter($differentiator,$filter);
  }
  return $filterCheck;
}

sub _checkFilter {
  my $self = shift;
  my $value = shift;
  my $filter = shift;

  if ($filter =~ /^([\<\=\>]{1,2})(.+)$/) {
    my $op = $1;
    my $filter = $2;
    if (($op eq "<") && ($value < $filter)) {
      return 1;
    } elsif (($op eq "<=") && ($value <= $filter)) {
      return 1;
    } elsif (($op eq "==") && ($value == $filter)) {
      return 1;
    } elsif (($op eq ">=") && ($value >= $filter)) {
      return 1;
    } elsif (($op eq ">") && ($value > $filter)) {
      return 1;
    }
  } elsif ($filter =~ /^!(.*)/) {
    $filter = $1;
    if ($value !~ /$filter/) {
      return 1;
    }
  } elsif ($value =~ /$filter/) {
    return 1;
  }

  return 0;
}

sub _dailyBalance {
  my $self = shift;
  my $chkvolume = $self->{'features'}->get('chkvolume');
  my $balanceMode = $self->{'features'}->get('routing_balancemode');
  my $cardamount = $self->{'transaction'}->getTransactionAmount();

  my (%dailyVol,$username);

  my @array = split('\|',$chkvolume);
  my @accountArray = ();
  my %linkedAccountsHash = ();
  for (my $pos=0;$pos<=$#array;$pos+=2) {
    $linkedAccountsHash{$array[$pos]} = $array[$pos+1];
    $accountArray[++$#accountArray] = $array[$pos];
  }

  my $dailyTotal = 1;
  my %percentVol = (); ## Percent Volume that each account has currently processed.

  ### Obtain Current Daily Balance
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
  my $date = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);
  my ($volume);

  my $query = q/
    SELECT username,volume
    FROM merch_stats
    WHERE username in (/ . join(',',map('?',@accountArray)) . q/)
    AND trans_date=?
    AND type=?
  /;

  my $dbh = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare($query) or die $DBI::errstr;
  $sth->execute(@accountArray,$date,'auth') or die $DBI::errstr;

  my $results = $sth->fetchall_arrayref({});

  foreach my $data (@{$results}) {
    $dailyVol{$data->{'username'}} = $data->{'volume'};
    $dailyTotal += $data->{'volume'};
  }

  if ($balanceMode eq "serial") {
    foreach my $acct (@accountArray) {
      if ($dailyVol{$acct} < $linkedAccountsHash{$acct}) {
        $username = $acct;
        ## First account found that has a daily balance less then limit.  Return account.
        last;
      }
    }
  } else {
    foreach my $key (keys %linkedAccountsHash) {
      my $targetVol = $dailyTotal * $linkedAccountsHash{$key};
      my $actualVol = $dailyVol{$key};

      ### Chris says we should calculate what values would look like with current transaction added.
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

sub _logMatch {
  my $self = shift;
  my $logData = shift;
  $logData->{'package'} = 'PlugNPay::Transaction::TransactionRouting';

  my $dataLogger = new PlugNPay::Logging::DataLog({'collection' => 'transaction_route'});
  $dataLogger->log($logData);
}

1;
