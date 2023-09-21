package PlugNPay::Transaction::Loader::Fraud;

use strict;
use PlugNPay::Token;
use PlugNPay::Sys::Time;
use PlugNPay::Processor;
use PlugNPay::DBConnection;
use PlugNPay::Database::QueryBuilder;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub loadDuplicate {
  my $self = shift;
  my $data = shift;
  my $count = 0;
  my $processor = new PlugNPay::Processor();
  my $payType = $data->{'payment_type'} || 'card';

  if ($processor->usesUnifiedProcessing($data->{'processor'}, $payType)) {
    $count = $self->_unifiedDuplicate($data);
  } else {
    $count = $self->_legacyDuplicate($data);
  }

  return $count;
}

sub _unifiedDuplicate {
  my $self = shift;
  my $data = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $timeObj = new PlugNPay::Sys::Time();
  my $newTime = $timeObj->inFormatDetectType('iso_gm', $data->{'transaction_date_time'});
 
  my $usernameInfo = ' = ? ';
  my $values = [$data->{'username'}];
  if (ref($data->{'username'}) eq 'ARRAY') {
    $usernameInfo = ' IN (' . join(',', map{'?'} @{$data->{'username'}}) . ') ';
    $values = $data->{'username'};
  }

  my @accountCodes = ();
  my @accountCodeValues = ();
  if (ref($data->{'account_code'}) eq 'HASH') {
    my $accountCodeHash = $data->{'account_code'};
    if ($accountCodeHash->{'1'}) {
      push @accountCodes, ' (tac.account_code_number = 1 AND tac.value = ?) ';
      push @accountCodeValues, $accountCodeHash->{'1'};
    }
    
    if ($accountCodeHash->{'2'}) {
      push @accountCodes, ' (tac.account_code_number = 2 AND tac.value = ?) ';
      push @accountCodeValues, $accountCodeHash->{'2'};
    }
    
    if ($accountCodeHash->{'3'}) {
      push @accountCodes, ' (tac.account_code_number = 3 AND tac.value = ?) ';
      push @accountCodeValues, $accountCodeHash->{'3'};
    }

    if ($accountCodeHash->{'4'}) {
      push @accountCodes, ' (tac.account_code_number = 4 AND tac.value = ?) ';
      push @accountCodeValues, $accountCodeHash->{'4'};
    }
  }

  my $accountCodeString = '';
  my $accountCodeTable = ' ';
  if (@accountCodeValues > 0) {
    $accountCodeString = ' AND ( ' . join(' AND ', @accountCodes) . ' ) AND tac.transaction_id = t.pnp_transaction_id ';
    $accountCodeTable = ', transaction_account_code tac ';
  }

  my $tokenObj = new PlugNPay::Token();
  $tokenObj->fromHex($data->{'pnp_token'});

  my $select = q/
    SELECT COUNT(o.id) AS `count`
      FROM `order` o, transaction t, merchant m, transaction_state s, transaction_billing_information b, processor p/ . $accountCodeTable . q/
     WHERE m.identifier / . $usernameInfo . q/
       AND t.pnp_token = ?
       AND b.full_name = ?
       AND b.postal_code = ?
       AND p.processor_code_handle = ?
       AND s.state LIKE ?
       AND t.amount = ?  / . $accountCodeString . q/
       AND t.transaction_date_time BETWEEN ? AND ?
       AND t.transaction_state_id = s.id
       AND m.id = o.merchant_id
       AND p.id = t.processor_id
       AND t.pnp_order_id = o.pnp_order_id
       AND b.transaction_id = t.pnp_transaction_id
  /;

  push @{$values}, ( 
    $tokenObj->inBinary(),
    $data->{'billing_name'},
    $data->{'billing_postal_code'},
    $data->{'processor'},
    uc($data->{'transaction_mode'}) . '%',
    $data->{'transaction_amount'},
  );
  
  push @{$values}, @accountCodeValues if @accountCodeValues > 0 && $accountCodeString ne '';
  push @{$values}, $newTime, $timeObj->nowInFormat('iso_gm');
  my $count = 0;
  eval {
    $count = $dbs->fetchallOrDie('pnp_transaction', $select, $values, {})->{'result'}[0]{'count'};
  };

  if ($@) {
    $self->log($data, $@);
  }

  return $count;
}

sub _legacyDuplicate {
  my $self = shift;
  my $data = shift;

  my $generator = new PlugNPay::Database::QueryBuilder();
  my $dbs = new PlugNPay::DBConnection();
  my $timeObj = new PlugNPay::Sys::Time();
  my $newTime = $timeObj->inFormatDetectType('gendatetime', $data->{'transaction_date_time'});
  my $usernameInfo = ' username = ? ';
  my @usernames = ($data->{'username'});
  if (ref($data->{'username'}) eq 'ARRAY') {
    $usernameInfo = ' username IN (' . join(',',map{'?'} @{$data->{'username'}}) . ') ';
    @usernames = @{$data->{'usernames'}};
  }

  my @accountCodes = ();
  my @accountCodeValues = ();
  if (ref($data->{'account_code'}) eq 'HASH') {
    my $accountCodeHash = $data->{'account_code'};
    if ($accountCodeHash->{'1'}) {
      push @accountCodes, ' acct_code = ? ';
      push @accountCodeValues, $accountCodeHash->{'1'};
    }

    if ($accountCodeHash->{'2'}) {
      push @accountCodes, ' acct_code2 = ? ';
      push @accountCodeValues, $accountCodeHash->{'2'};
    }

    if ($accountCodeHash->{'3'}) {
      push @accountCodes, ' acct_code3 = ? ';
      push @accountCodeValues, $accountCodeHash->{'3'};
    }

    if ($accountCodeHash->{'4'}) {
      push @accountCodes, ' acct_code4 = ? ';
      push @accountCodeValues, $accountCodeHash->{'4'};
    }
  }

  my $startDate = substr($newTime,0,8);
  my $endDate = $timeObj->nowInFormat('yyyymmdd');
  my $dateSearch = $generator->generateDateRange({'start_date' => $startDate, 'end_date' => $endDate});

  my $select = q/
    SELECT COUNT(*) AS `count`
      FROM operation_log FORCE INDEX (oplog_tdatesha_idx)
     WHERE  / . $usernameInfo . q/
       AND trans_date IN (/ . $dateSearch->{'params'} . q/)
       AND shacardnumber = ?
       AND processor = ?
       AND amount LIKE ?
       AND card_name = ?
       AND card_zip = ? /  . join(' AND ', @accountCodes) . q/
       AND authtime BETWEEN ? AND ?
  /;

  my $values = \@usernames;
  push @{$values}, @{$dateSearch->{'values'}};

  push @{$values}, (
    $data->{'shacardnumber'},
    $data->{'processor'},
    '% ' . $data->{'transaction_amount'}, #Cause it's "<CURRENCY> <AMOUNT>"
    $data->{'billing_name'},
    $data->{'billing_postal_code'}
  );

  push @{$values}, @accountCodeValues if @accountCodeValues > 0;
  push @{$values}, $newTime, $timeObj->nowInFormat('gendatetime');

  my $count = 0;
  eval {
    $count = $dbs->fetchallOrDie('pnpdata', $select, $values, {})->{'result'}[0]{'count'};
  };

  if ($@) {
    $self->log($data, $@);
  }

  return $count;
}

sub log {
  my $self = shift;
  my $data = shift;
  my $error = shift;

  #for safety
  $data->{'shacardnumber'} = 'REMOVED BY LOGGER' if $data->{'shacardnumber'};

  new PlugNPay::Logging::DataLog({'collection' => 'fraudtrack'})->log({
    'data'   => $data,
    'error'  => $@,
    'module' => ref($self)
  });
}

1;
