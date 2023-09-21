package PlugNPay::Transaction::TestMode;

use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;
use strict;

our $_response_cache;
our $_test_cards;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_response_cache) {
    $_response_cache = new PlugNPay::Util::Cache::LRUCache(5);
  }

  $self->loadTestCards();

  return $self;
}

sub process {
  my $self = shift;
  my $transactionObject = shift;

  my $paymentName;
  my $results;

  if ($transactionObject->getPayment()) {
    my $paymentName = $transactionObject->getPayment()->getName();
    my $isConvenienceCharge = $transactionObject->isConvenienceChargeTransaction();

    my @resultRules = split(/\s+/,$paymentName);
    
    if (shift @resultRules == 'force') {
      my $nextRule = shift @resultRules;
      if ($nextRule =~ /^(convenience|coa|cardcharge)$/ && !$isConvenienceCharge) {
        $results = $self->simulate('success');
      } else {
        my $trigger = $nextRule;
        my $status = shift @resultRules || $trigger;
        $results = $self->simulate($status,$trigger);
      }
    }
  } else {
    $results = simulate('badcard','nodata');
  }

  return %{$results};
}

sub simulate {
  my $self = shift;
  my $status = shift;
  my $trigger = shift;

  if ($status eq 'success' || !defined $trigger || $trigger eq $status) {
    $trigger = '';
  }

  my $key = $status . '-' . $trigger;
  if ($_response_cache->contains($key)) {
    return $_response_cache->get($key);
  }

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT finalstatus,mstatus,merrmsg,resp_code_prefix,resp_code_number
    FROM transaction_response
    WHERE status = ? AND `trigger` = ?
  /);

  $sth->execute($status,$trigger);

  my $resultSettings = $sth->fetchrow_hashref;
  my %results;
  $results{'FinalStatus'} = $resultSettings->{'finalstatus'};
  $results{'MErrMsg'} = $resultSettings->{'merrmsg'};
  $results{'MStatus'} = $resultSettings->{'mstatus'};
  $results{'resp-code'} = $resultSettings->{'resp_code_prefix'} . sprintf('%02d',$resultSettings->{'resp_code_number'});
  if ($status eq 'success') {
    $results{'auth_code'} = 'TESTAUTH';
  }

  $_response_cache->set($key,\%results);

  return \%results;
}

sub loadTestCards {
  my $self = shift;

  if (ref $_test_cards eq 'HASH') {
    return;
  }

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT card_number
    FROM test_cards
  /);

  $sth->execute();
  my $rows = $sth->fetchall_arrayref({});

  my %cards;
  foreach my $row (@{$rows}) {
    $cards{$row->{'card_number'}} = 1;
  }

  $_test_cards = \%cards;
}

sub isTestCard {
  my $self = shift;
  my $cardNumber = shift;
  
  $self->loadTestCards();

  return (exists $_test_cards->{$cardNumber})
}

1;
