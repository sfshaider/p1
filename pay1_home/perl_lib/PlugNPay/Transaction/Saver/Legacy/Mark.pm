package PlugNPay::Transaction::Saver::Legacy::Mark;

use strict;

use PlugNPay::DBConnection;
use PlugNPay::Legacy::Transflags;
use PlugNPay::Transaction::Legacy::AdditionalProcessorData;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self  = {};
  bless $self, $class;
  return $self;
}

sub mark {
  my $self           = shift;
  my $input          = shift;
  my $gatewayAccount = $input->{'gatewayAccount'};
  my $transactions   = $input->{'transactions'}; # map of transactions, key = legacy order id, value = transaction object

  my %errors;

  my @orderIds = keys %{$transactions};
  if (@orderIds == 0) {
    return _buildMarkResponse(\%errors);
  }

  my $logger = new PlugNPay::Logging::DataLog({ collection => 'legacy_mark' });

  # ensure all transactions are for the gateway account specified by the input
  my %filteredTransactions;
  foreach my $orderId ( @orderIds ) {
    my $errorMessage = '';

    my $transaction = $transactions->{$orderId};
    if ( $transaction->getGatewayAccountName() ne $gatewayAccount ) {
      $errorMessage = 'Transaction account does not match merchant account';
      $logger->log({
        gatewayAccount => $gatewayAccount,
        orderId => $orderId,
        transactionGatewayAccount => $transaction->getGatewayAccountName(),
        message => $errorMessage
      });
    } elsif ($transaction->getTransactionState() ne 'AUTH') {
      $errorMessage = 'Only authorizations may be marked for postauth';
      $logger->log({
        gatewayAccount => $gatewayAccount,
        orderId => $orderId,
        transactionState => $transaction->getTransactionState(),
        message => $errorMessage
      });
    } elsif ($transaction->hasTransFlag('capture')) {
      $errorMessage = 'Operation postauth not allowed for authcapture transactions.';
      $logger->log({
        gatewayAccount => $gatewayAccount,
        orderId => $orderId,
        transactionFlags => $transaction->getTransFlags(),
        message => $errorMessage
      });
    } elsif ($transaction->hasTransFlag('avsonly') || $transaction->hasTransFlag('balance')) {
      $errorMessage = 'Operation postauth not allowed for avsonly transactions.';
      $logger->log({
        gatewayAccount => $gatewayAccount,
        orderId => $orderId,
        transactionFlags => $transaction->getTransFlags(),
        message => $errorMessage
      });
    } elsif ($transaction->hasTransFlag('gift')) {
      $errorMessage = 'Operation postauth not allowed for gift cards';
      $logger->log({
        gatewayAccount => $gatewayAccount,
        orderId => $orderId,
        transactionFlags => $transaction->getTransFlags(),
        message => $errorMessage
      });
    } else {
      $filteredTransactions{$orderId} = $transaction;
    }

    if ($errorMessage ne '') {
      $errors{$orderId} = $errorMessage;
    }
  }

  # check to see if there are any transactions left after filtering
  # if not, return the errors
  if (keys %filteredTransactions == 0) {
    return _buildMarkResponse(\%errors);
  }

  # make a copy of input
  my %subInput = %{$input};

  # override the list of transactions to only the ones that passed the tests above
  $subInput{'transactions'} = \%filteredTransactions;

  my $now = _now();
  $subInput{'_now_'} = $now;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnpdata');

  eval {
    $self->_markOperationLog(\%subInput);
    $self->_insertMarkIntoTransLog(\%subInput);
  };

  if ($@) {
    $dbs->rollback('pnpdata');
  } else {
    eval {
      $dbs->commit('pnpdata');
    };

    if ($@) {
      $logger->log({
        message => 'failed to commit sql transaction for marking transactions',
        orderIds => \@orderIds,
        gatewayAccount => $gatewayAccount
      });

      foreach my $orderId (@orderIds) {
        $errors{$orderId} = "failed to commit postauth";
      }
    }
  }

  # check filtered transactions to verify they were all marked
  my $notMarkedInOperationLog = $self->_verifyOperationLog(\%subInput);
  my $notMarkedInTransLog = $self->_verifyTransLog(\%subInput);
  my %notMarkedState; # +1 = failed op log, -1 = failed trans_lgo, 0 = failed both
  if (@{$notMarkedInOperationLog} > 0) {
    foreach my $orderId (@{$notMarkedInOperationLog}) {
      $notMarkedState{$orderId} += 1;
      $errors{$orderId} = "Failed to mark transaction";
      $logger->log({
        message => 'mark of transaction in operation_log failed',
        orderId => $orderId,
        gatewayAccount => $gatewayAccount
      });
    }
  }

  if (@{$notMarkedInTransLog} > 0) {
    foreach my $orderId (@{$notMarkedInTransLog}) {
      $notMarkedState{$orderId} -= 1;
      $errors{$orderId} = "Failed to mark transaction";
      $logger->log({
        message => 'mark of transaction in trans_log failed',
        orderId => $orderId,
        gatewayAccount => $gatewayAccount
      })
    }
  }

  # log about failing in one table and not the other
  foreach my $orderId (keys %notMarkedState) {
    if ($notMarkedState{$orderId} == 1) {
      $logger->log({
        message => 'transaction marked in trans_log but not operation_log',
        orderId => $orderId,
        gatewayAccount => $gatewayAccount
      });
    } elsif ($notMarkedState{$orderId} == -1) {
      $logger->log({
        message => 'transaction marked in operation_log but not trans_log',
        orderId => $orderId,
        gatewayAccount => $gatewayAccount
      });
    }
  }

  my $success = 0;
  if (length(keys %errors) == 0) {
    $success = 1;
  }

  return _buildMarkResponse(\%errors);
}

sub _buildMarkResponse {
  my $errors = shift;

  my $success = 0;
  if (length(keys %{$errors}) == 0) {
    $success = 1;
  }

  return {
    success => $success,
    errors => $errors
  };
}

sub _markOperationLog {
  my $self = shift;
  $self->_markOperationLogGeneral(@_);
  $self->_markOperationLogSpecific(@_);
}

sub _markOperationLogGeneral {
  my $self  = shift;
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'};
  my $transactions   = $input->{'transactions'};
  my $now            = $input->{'_now_'};

  my @orderIds       = keys %{$transactions};
  return if @orderIds == 0;

  my $orderIdParams = join( ',', map { '?' } @orderIds );

  my $query = qq/
    UPDATE operation_log 
    SET lastop = ?, lastopstatus = ?, postauthtime = ?, batch_time = ?, postauthstatus = ?
    WHERE username = ? AND orderid in ($orderIdParams) AND lastop in (?,?,?) AND lastopstatus = ?
  /;

  my $values = [ 
    'postauth',  # set lastop
    'pending', # lastopstatus
    $now, # postauthtime
    $now, # batch_time
    'pending',  # postauthstatus
    $gatewayAccount, # username = ?
    @orderIds, # orderid in (...)
    'auth', 'reauth','forceauth', # lastop in (?,?,?)
    'success' # lastopstatus = ?
  ];

  # input is passed as it is used in testing, _execute is mocked for testing
  _execute(
    { query  => $query,
      values => $values,
      %{$input}
    }
  );
}

sub _markOperationLogSpecific {
  my $self  = shift;
  my $input = shift;

  my $logger = new PlugNPay::Logging::DataLog({ collection => 'legacy_mark' });

  my $gatewayAccount = $input->{'gatewayAccount'};
  my $transactions   = $input->{'transactions'};
  my @orderIds       = keys %{$transactions};
  my $now            = $input->{'_now_'};

  return if @orderIds == 0;

  my $query = q/
    UPDATE operation_log
    SET amount = ?, auth_code = ?
    WHERE username = ? AND orderid = ?
  /;

  while (my ($orderId, $transaction) = each %{$transactions}) {
    my $amountFieldValue = _amountFieldValueFromTransaction($transaction);

    my $values = [
      $amountFieldValue,
      $transaction->getRawAuthorizationCode(),
      $gatewayAccount,
      $orderId
    ];

    _execute(
      { query  => $query,
        values => $values,
        %{$input}
      }
    );
  }
}

sub _amountFieldValueFromTransaction {
  my $transaction = shift;

  my $amount = $transaction->getSettlementAmount() || $transaction->getTransactionAmount();
  my $currency = lc $transaction->getCurrency();
  my $amountFieldValue = sprintf('%s %s', $currency, $amount);

  return $amountFieldValue;
}

sub _verifyOperationLog {
  my $self = shift;
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'};
  my $transactions   = $input->{'transactions'};
  my @orderIds       = keys %{$transactions};

  my %markedStatus;

  my $orderIdParams = join( ',', map { '?' } @orderIds );

  # query to find orderIds that are not postauth pending
  my $query = qq/
    SELECT orderid
    FROM operation_log
    WHERE username = ? AND orderid in ($orderIdParams) AND lastop != ? AND lastopstatus != ?
  /;

  my $values = [ $gatewayAccount, @orderIds, 'postauth', 'pending' ];

  my $result = _fetchAll({
    query => $query,
    values => $values,
    %{$input}
  });

  my @notMarked;
  my $rows = $result->{'rows'};
  foreach my $row (@{$rows}) {
    my $orderId = $row->{'orderid'};
    push @notMarked,$orderId;
  }

  return \@notMarked;
}

sub _insertMarkIntoTransLog {
  my $self  = shift;
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'};
  my $transactions   = $input->{'transactions'};
  my $now            = $input->{'_now_'};

  my $transDate = _transDateFromTransTime($now);
  my @fieldValuesArray;

  my $fields;
  my $params;
  my @values;

  # create base map to reassign values of to ensure key order remains 
  # constant when calling keys and values functions on it repeatedly
  # when building the variables array
  my %fieldValues = (
    'username'      => undef,
    'processor'     => undef,
    'merchant_id'   => undef,
    'orderid'       => undef,
    'card_name'     => undef,
    'card_addr'     => undef,
    'card_city'     => undef,
    'card_state'    => undef,
    'card_zip'      => undef,
    'card_country'  => undef,
    'card_number'   => undef,
    'card_exp'      => undef,
    'amount'        => undef,
    'trans_date'    => undef,
    'trans_time'    => undef,
    'trans_type'    => undef,
    'operation'     => undef,
    'accttype'      => undef,
    'result'        => undef,
    'finalstatus'   => undef,
    'descr'         => undef,
    'acct_code'     => undef,
    'acct_code2'    => undef,
    'acct_code3'    => undef,
    'acct_code4'    => undef,
    'auth_code'     => undef,
    'avs'           => undef,
    'cvvresp'       => undef,
    'shacardnumber' => undef,
    'length'        => undef,
    'refnumber'     => undef,
    'transflags'    => undef,
    'ipaddress'     => undef,
    'duplicate'     => undef,
    'batch_time'    => undef
  );

  foreach my $orderId ( keys %{$transactions} ) {
    my $transaction = $transactions->{$orderId};

    my $bi = $transaction->getBillingInformation();
    my $payment = $transaction->getPayment();

    my $expiration = '';
    # get expration in eval in case of ach, ignore error
    eval {
      $expiration = sprintf('%02d/%02d',$payment->getExpirationMonth(),$payment->getExpirationYear());
    };

    my $accountType = 'credit';
    # account type does not exist on credit card object, so the following will fail if card transaction
    eval {
      $accountType = $payment->getAccountType();
    };

    my $amountFieldValue = _amountFieldValueFromTransaction($transaction);

    my $cardAddr = $bi->getAddress1() . ' ' . $bi->getAddress2();
    $cardAddr =~ s/\s+$//;

    my $transflags = new PlugNPay::Legacy::Transflags();
    my @flags = $transaction->getTransFlags();
    $transflags->addFlag(@flags);

    $fieldValues{'username'}      = $gatewayAccount;
    $fieldValues{'processor'}     = $transaction->getProcessorShortName();
    $fieldValues{'merchant_id'}   = $transaction->getProcessorMerchantId();
    $fieldValues{'orderid'}       = $transaction->getMerchantTransactionID();
    $fieldValues{'card_name'}     = $bi->getName();
    $fieldValues{'card_addr'}     = $cardAddr;
    $fieldValues{'card_city'}     = $bi->getCity() || '';
    $fieldValues{'card_state'}    = $bi->getState() || '';
    $fieldValues{'card_zip'}      = $bi->getPostalCode() || '';
    $fieldValues{'card_country'}  = $bi->getCountry() || '';
    $fieldValues{'card_number'}   = $payment->getMaskedNumber(6,4,'*',2) || '';
    $fieldValues{'accttype'}      = $accountType;
    $fieldValues{'card_exp'}      = $expiration;
    $fieldValues{'amount'}        = $amountFieldValue;
    $fieldValues{'trans_date'}    = $transDate;
    $fieldValues{'trans_time'}    = $now;
    $fieldValues{'trans_type'}    = 'postauth';
    $fieldValues{'operation'}     = 'postauth';
    $fieldValues{'result'}        = 'pending';
    $fieldValues{'finalstatus'}   = 'pending';
    $fieldValues{'descr'}         = '';
    $fieldValues{'acct_code'}     = $transaction->getAccountCode(1) || '';
    $fieldValues{'acct_code2'}    = $transaction->getAccountCode(2) || '';
    $fieldValues{'acct_code3'}    = $transaction->getAccountCode(3) || '';
    $fieldValues{'acct_code4'}    = $transaction->getAccountCode(4) || '';
    $fieldValues{'auth_code'}     = $transaction->getRawAuthorizationCode() || '';
    $fieldValues{'avs'}           = $transaction->getResponse()->getAVSResponse() || '';
    $fieldValues{'cvvresp'}       = $transaction->getResponse()->getSecurityCodeResponse() || '';
    $fieldValues{'shacardnumber'} = $payment->getCardHash();
    $fieldValues{'length'}        = '';
    $fieldValues{'refnumber'}     = $transaction->getProcessorReferenceID() || '';
    $fieldValues{'transflags'}    = $transflags->toLegacyString();
    $fieldValues{'ipaddress'}     = $transaction->getIPAddress();
    $fieldValues{'duplicate'}     = '';
    $fieldValues{'batch_time'}    = $now; # set by genfiles later

    # only do this once
    if ( !defined $fields ) {
      $fields = join( ',', map {  '`' . $_ . '`'; } keys %fieldValues );
      $params = join( ',', map { '?' } keys %fieldValues );
    }

    push @values, values %fieldValues;
  }

  my $paramGroups = join(',',map { '(' . $params . ')' } keys %{$transactions});
  my $query = qq/INSERT INTO trans_log ($fields) VALUES $paramGroups/;
  # input is passed as it is used in testing.
  _execute(
    { query  => $query,
      values => \@values,
      %{$input}
    }
  );
}

sub _verifyTransLog {
  my $self = shift;
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'};
  my $transactions   = $input->{'transactions'};
  my @orderIds       = keys %{$transactions};

  my %markedStatus;

  my $orderIdParams = join( ',', map { '?' } @orderIds );

  # query to find orderIds that *have* a postauth pending row, a bit different than the operation log check above
  my $query = qq/
    SELECT orderid
    FROM trans_log
    WHERE username = ? AND orderid in ($orderIdParams) AND operation = ? AND finalstatus = ?
  /;

  my $values = [ $gatewayAccount, @orderIds, 'postauth', 'pending' ];

  my $result = _fetchAll({
    query => $query,
    values => $values,
    %{$input}
  });

  my %markedStatus;

  # iterate over query results and set marked rows in %markedStatus
  my $rows = $result->{'rows'};
  foreach my $row (@{$rows}) {
    my $orderId = $row->{'orderid'};
    $markedStatus{$orderId} = 1;
  }

  my @notMarked;
  # iterate over order ids and find ones that did not have a marked row
  foreach my $orderId (@orderIds) {
    if ($markedStatus{$orderId} != 1) {
      push @notMarked,$orderId;
    }
  }

  return \@notMarked;
}


# call to execute, can be mocked for testing.
sub _execute {
  my $input = shift;

  my $query  = $input->{'query'};
  my $values = $input->{'values'};

  my $dbs = new PlugNPay::DBConnection();
  return $dbs->executeOrDie( 'pnpdata', $query, $values );
}

# call to fetch, can be mocked for testing.
sub _fetchAll {
  my $input = shift;

  my $query  = $input->{'query'};
  my $values = $input->{'values'};

  my $dbs = new PlugNPay::DBConnection();
  return $dbs->fetchallOrDie( 'pnpdata', $query, $values, {} );
}

sub _now {
  return new PlugNPay::Sys::Time()->nowInFormat('gendatetime');
}

sub _transDateFromTransTime {
  my $transTime = shift;
  my $transDate = substr( $transTime, 0, 8 );
  return $transDate;
}

1;
