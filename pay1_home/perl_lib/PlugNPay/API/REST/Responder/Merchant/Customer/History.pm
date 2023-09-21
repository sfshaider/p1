package PlugNPay::API::REST::Responder::Merchant::Customer::History;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::Merchant::Customer::History;
use PlugNPay::Merchant::Customer::History::JSON;

use base 'PlugNPay::API::REST::Responder::Abstract::Merchant::Customer';

sub _read {
  my $self = shift;
  my $merchantCustomer = $self->getMerchantCustomer();
  my $options = $self->getResourceOptions();

  my $startDay = $options->{'startDay'} || substr(new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd'), 6, 2);
  my $endDay = $options->{'endDay'} || $startDay;

  my $startMonth = $options->{'startMonth'} || substr(new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd'), 4, 2);
  my $endMonth = $options->{'endMonth'} || $startMonth;

  my $startYear = $options->{'startYear'} || substr(new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd'), 1, 4);
  my $endYear = $options->{'endYear'} || $startYear;

  my $validDates = new PlugNPay::Sys::Time();
  if (!$validDates->validDate($startDay, $startMonth, $startYear)) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Invalid start date' };
  }

  if (!$validDates->validDate($endDay, $endMonth, $endYear)) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Invalid end date' };
  }

  if (!$validDates->isValidDateRange({
    'startDay'   => $startDay,
    'startMonth' => $startMonth,
    'startYear'  => $startYear,
    'endDay'     => $endDay,
    'endMonth'   => $endMonth,
    'endYear'    => $endYear    
  })) {
    $self->setResponseCode(422);
    return { 'status' => 'error', 'message' => 'Invalid date range.' };
  }

  my $historyOptions = {
    'startDay'   => $startDay,
    'startMonth' => $startMonth,
    'startYear'  => $startYear,
    'endDay'     => $endDay,
    'endMonth'   => $endMonth,
    'endYear'    => $endYear,
    'interval'   => $options->{'interval'}
  };

  my $history = new PlugNPay::Merchant::Customer::History();
  $history->setLimitData({ 'limit' => $options->{'pageLength'}, 'offset' => $options->{'page'} * $options->{'pageLength'} });

  my $transactions = $history->loadCustomerHistory($merchantCustomer->getMerchantCustomerLinkID(), $historyOptions);
  my $count = $history->getHistoryTableCount($merchantCustomer->getMerchantCustomerLinkID(), $historyOptions);

  my $logs = [];
  if (@{$transactions} > 0) {
    my $json = new PlugNPay::Merchant::Customer::History::JSON();
    foreach my $log (@{$transactions}) {
      push (@{$logs}, $json->transactionLogToJSON($log));
    }
  }

  $self->setResponseCode(200);
  return { 'status' => 'success', 'logs' => $logs, 'count' => $count };
}

1;
