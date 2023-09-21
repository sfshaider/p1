package PlugNPay::API::REST::Responder::Merchant::Order;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::Order::Loader;
use PlugNPay::Transaction::Loader;
use PlugNPay::Logging::DataLog;
use PlugNPay::Order::JSON;

use base 'PlugNPay::API::REST::Responder';

# Thought For The Day: If an order never has transactions, is it really an order?

# If we accept a create/update call here how will it interact with Transaction's create/update?

sub _getOutputData {
  my $self = shift;
  my $action = $self->getAction();
  if ($action eq 'read') {
    return $self->_read();
  } else {
    $self->setResponseCode('501');
    return {};
  }
}

# Load Orders
sub _read {
  my $self = shift;
  my $user = $self->getResourceData()->{'merchant'};
  my $options = $self->getResourceOptions();
  my $time = new PlugNPay::Sys::Time();
  my $converter = new PlugNPay::Order::JSON();
  my $timeOptions = {};
  if (!defined $user) {
    $user = $self->getGatewayAccount();
  }

  $timeOptions->{legacyStart} = $options->{'start_date'} || $options->{'startDate'};
  $timeOptions->{legacyEnd} = $options->{'end_date'} || $options->{'endDate'};
  $timeOptions->{startHour} = $options->{'start_hour'} || $options->{'startHour'};
  $timeOptions->{endHour} = $options->{'end_hour'} || $options->{'endHour'};

  if (!defined $timeOptions->{legacyStart}) {
    $time->subtractDays(30);
    $timeOptions->{legacyStart} =  $time->inFormat('yyyymmdd');
  } else {
    $timeOptions->{legacyStart} = $time->inFormatDetectType('yyyymmdd', $timeOptions->{legacyStart});
  }

  if (!defined $timeOptions->{legacyEnd}) {
    $timeOptions->{legacyEnd} =  $time->nowInFormat('yyyymmdd');
  } else {
    $timeOptions->{legacyEnd} =  $time->inFormatDetectType('yyyymmdd',$timeOptions->{legacyEnd});
  }

  $timeOptions->{newStart} = $time->inFormatDetectType('iso_gm',$timeOptions->{legacyStart});
  $timeOptions->{newEnd} = $time->inFormatDetectType('iso_gm',$timeOptions->{legacyEnd});
  my $accountCodes = {};
  $accountCodes->{'1'} = $options->{'account_code_1'} if exists $options->{'account_code_1'};
  $accountCodes->{'2'} = $options->{'account_code_2'} if exists $options->{'account_code_2'};
  $accountCodes->{'3'} = $options->{'account_code_3'} if exists $options->{'account_code_3'};
  $accountCodes->{'4'} = $options->{'account_code_4'} if exists $options->{'account_code_4'};

  my $statuses = $options->{'trans_status'} || $options->{'transStatus'};
  if ($statuses ne 'all') {
    my @statusArray = split(',',$statuses);
    $statuses = \@statusArray;
  }
  my $states = $options->{'trans_states'} || $options->{'transStates'};
  my @transactionStates = ();
  if ($states) {
    @transactionStates = split(',',$states);
  }

  my $paymentTypes = $self->getResourceOptionsArray()->{'payment_types'} || $self->getResourceOptionsArray()->{'paymentTypes'};
  my $accountTypes = $self->getResourceOptionsArray()->{'account_types'} || $self->getResourceOptionsArray()->{'accountTypes'};
  my $loader = new PlugNPay::Order::Loader();
  my $loadOptions = $loader->checkDatabasesToLoad($user,$timeOptions);

  my $startLimit = ($options->{'pageLength'} * ($options->{'page'} + 1)) - $options->{'pageLength'};
  my $count = 0;
  my $data = {};
  my @ordersArray = ();
  my $response = {};
  my $loadData = {'username' => $user, 'start_date' => $timeOptions->{'newStart'}, 'end_date' => $timeOptions->{'newEnd'},
                  'start_hour' => $timeOptions->{'startHour'}, 'end_hour' => $timeOptions->{'endHour'},
                  'card_number' => $options->{'card_number'}};

  #Load Limit data
  $loader->setLoadLimit({'offset' => $startLimit,'length' => $options->{'pageLength'}});

  if (@transactionStates > 0) {
    $loadData->{'transaction_states'} = \@transactionStates;
  }

  if (ref($statuses) eq 'ARRAY' && @{$statuses} > 0) {
    $loadData->{'transaction_status'} = $statuses;
  }

  if (ref($paymentTypes) eq 'ARRAY' && @{$paymentTypes} > 0) {
    $loadData->{'transaction_vehicles'} = $paymentTypes;
  }

  if (ref($accountTypes) eq 'ARRAY' && @{$accountTypes} > 0) {
    $loadData->{'account_types'} = $accountTypes;
  }

  if (keys %{$accountCodes} > 0) {
    $loadData->{'account_codes'} = $accountCodes;
    $loadData->{'partial_match'} = $self->getResourceOptions()->{'partial_match'} if exists $self->getResourceOptions()->{'partial_match'};
  }

  eval {
    if ($loadOptions->{'new'}) {
      $data->{'new'} = $loadData;
      $count += $loader->getOrdersListSize([$loadData]);
    }

    if ($loadOptions->{'old'}) {
      $data->{'legacy'} = $loadData;
      $count += $loader->getLegacyOrdersListSize([$loadData]);
    }

    @ordersArray = @{$converter->ordersToJSON($loader->loadOrdersSummary($data))};
  };

  if ($@) {
    my $dataLog = new PlugNPay::Logging::DataLog({'collection' => 'order'});
    $dataLog->log({
      'module'    => 'PlugNPay::API::REST::Responder::Merchant::Order',
      'error'     => $@,
      'requestor' => $self->getGatewayAccount()
    });
    $self->setResponseCode('422');
    $self->setError($@);
    $response =  {'message' => 'Load error', 'status' => 'failure', 'error' => $@};
  } else {
    $response = { 'count' => $count,'ordersList' => \@ordersArray };
    $self->setResponseCode('200');
    $response->{'message'} = 'Loaded successfully';
    $response->{'status'} = 'success';
  }

  return $response;
}

1;
