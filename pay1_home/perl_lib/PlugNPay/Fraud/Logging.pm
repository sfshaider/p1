package PlugNPay::Fraud::Logging;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Logging::DataLog;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub log {
  my $self = shift;
  my $transactionObj = shift;
  my $options = shift || {};
  my $results = $options->{'finalStatus'} || 'pending';
  my @errors = keys %{$options->{'errors'}}; #Used to log error count
  my $descr = 'Transaction failed fraud check, number of fraud matches: ' . @errors;

  my @values = (
    $transactionObj->getGatewayAccount(),
    $transactionObj->getOrderID(),
    $transactionObj->getTransactionDateTime(),
    $results,
    $descr,
    $transactionObj->getAccountCode(1),
    $transactionObj->getAccountCode(2),
    $transactionObj->getAccountCode(3)
  );

  my $insert = q/
    INSERT INTO fraud_log
    (username, orderid, trans_time, status, descr, acct_code, acct_code2, acct_code3)
    VALUES
    (?,?,?,?,?,?,?,?)
  /;

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->executeOrDie('fraudtrack', $insert, \@values);
  }; 

  if ($@) {
    my $logData = {
      'username'  => $transactionObj->getGatewayAccount(),
      'transTime' => $transactionObj->getTransactionDateTime(),
      'orderID'   => $transactionObj->getOrderID()
    };
    $self->_errorLog($@,$logData);
  }

  return 1;
}

sub _errorLog {
  my $self = shift;
  my $error = shift;
  my $data = shift;

  new PlugNPay::Logging::DataLog({'collection' => 'fraudtrack'})->log({
    'error'  => $error,
    'data'   => $data,
    'module' => ref($self)
  });
}

1;
