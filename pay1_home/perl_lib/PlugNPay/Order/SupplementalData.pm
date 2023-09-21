package PlugNPay::Order::SupplementalData;

use strict;
use warnings FATAL => 'all';
use PlugNPay::AWS::ParameterStore;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Logging::DataLog;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Util::Status;

our $cachedServer;
our $noCache;

sub new {
  my $class = shift;
  my $self  = {};
  bless $self, $class;
  return $self;
}

sub getServer {
  my $server;
  if ( $noCache || !defined $cachedServer || $cachedServer eq '' ) {
    my $env = $ENV{'PNP_SUPPLEMENTAL_DATA'};
    $server = $env || _getServerParameter();
  } else {
    $server = $cachedServer;
  }

  if ( !defined $noCache && !defined $cachedServer ) {
    $cachedServer = $server;
  }

  return $server;
}

sub noCache {
  $noCache = 1;
}

sub _getServerParameter {
  return PlugNPay::AWS::ParameterStore::getParameter( '/SUPPLEMENTALDATA/SERVER', 0 );
}

sub insertSupplementalData {
  my $self  = shift;
  my $input = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $itemsFieldName = 'items';
  my $items = _input( $itemsFieldName, $input->{$itemsFieldName}, 'ARRAY' );

  my $requestData = _formatHash( { 'items' => $items } );

  if ($status) {
    my $ms = _createMicroserviceCaller(
      { requestData => $requestData,  
        method      => 'POST',
        server      => getServer()
      }
    );

    _processRequest(
      $ms,
      sub {
        my $success = shift;

        if ( !$success ) {
          my $logger = new PlugNPay::Logging::DataLog( { 'collection' => 'SupplementalData' } );
          $logger->log(
            { 'status'   => 'ERROR',
              'message'  => 'Failed to insert supplemental data.',
              'function' => 'insertSupplementalData',
              'module'   => 'PlugNPay::Order::SupplementalData',
              'error'    => $ms->getErrors(),
            }
          );
          $status->setFalse();
          $status->setError("Failed to insert supplemental data.");
          $status->setErrorDetails( $ms->getErrors() );
        }
      }
    );
  }

  return $status;
}

sub getSupplementalData {
  my $self  = shift;
  my $input = shift;

  my $requestData;
  my $response;
  my ( $orders, $merchantIds, $dates );

  eval {
    my $ordersFieldName = 'orders';
    $orders = _input( $ordersFieldName, $input->{$ordersFieldName}, 'ARRAY' );
  };

  eval {
    my $merchantIdsFieldName = 'merchant_ids';
    my $datesFieldName       = 'dates';
    $merchantIds = _input( $merchantIdsFieldName, $input->{$merchantIdsFieldName}, 'ARRAY' );
    $dates       = _input( $datesFieldName,       $input->{$datesFieldName},       'ARRAY' );
  };

  if ( defined $orders ) {
    $requestData = { query => { orders => _formatArray($orders) } };
  } elsif ( defined $merchantIds && defined $dates ) {
    $requestData = {
      query => {
        merchant_ids => _formatArray($merchantIds),
        dates        => _formatArray($dates)
      }
    };
  } else {
    $response = { status => 'error', message => 'Insufficient data' };
    return $response;
  }

  my $ms = _createMicroserviceCaller(
    { requestData => $requestData,
      method      => 'POST',
      server      => getServer(),
      subURL      => '/load'
    }
  );

  _processRequest(
    $ms,
    sub {
      my $success = shift;

      if ($success) {
        $response = $ms->getDecodedResponse();
        if ( @{ $ms->getErrors() } > 0 && ( $response == {} || !$response ) ) {
          $response = { 'errors' => $ms->getErrors(), 'status' => 'failed to load supplemental data: ' . $ms->getResponseCode() };
          my $logger = new PlugNPay::Logging::DataLog( { 'collection' => 'SupplementalData' } );
          $logger->log(
            { 'status'   => 'ERROR',
              'message'  => 'Failed to load supplemental data',
              'function' => 'getSupplementalData',
              'module'   => 'PlugNPay::Order::SupplementalData',
              'error'    => $ms->getErrors()
            }
          );
        }
      } else {
        my $logger = new PlugNPay::Logging::DataLog( { 'collection' => 'SupplementalData' } );
        $logger->log(
          { 'status'   => 'ERROR',
            'message'  => 'Failed to load supplemental data',
            'function' => 'getSupplementalData',
            'module'   => 'PlugNPay::Order::SupplementalData',
            'error'    => $ms->getErrors()
          }
        );
        $response = $ms->getDecodedResponse();
      }
    }
  );

  return $response;
}

sub getNormalizedSupplementalData {
  my $self     = shift;
  my $options  = shift;
  my $response = $self->getSupplementalData($options);

  my $data           = $response->{'data'};
  my $normalizedData = {};
  my $internalId     = new PlugNPay::GatewayAccount::InternalID();
  foreach my $set ( @{$data} ) {
    my $merchantId       = $set->{'merchant_id'};
    my $merchantUsername = $internalId->getUsernameFromId($merchantId);

    if ( !defined $normalizedData->{'byId'} ) {
      $normalizedData->{'byId'} = {};
    }

    if ( !defined $normalizedData->{'byUsername'} ) {
      $normalizedData->{'byUsername'} = {};
    }

    if ( !defined $normalizedData->{'byId'}{$merchantId} ) {
      $normalizedData->{'byId'}{$merchantId}             = {};
      $normalizedData->{'byUsername'}{$merchantUsername} = $normalizedData->{'byId'}{$merchantId};
    }

    %{ $normalizedData->{'byId'}{$merchantId} } = ( %{ $normalizedData->{'byId'}{$merchantId} }, %{ $set->{'orders'} } );
  }

  return $normalizedData;
}

sub deleteSupplementalData {
  my $self  = shift;
  my $input = shift;

  my $dateFieldName = 'date';
  my $date = _input( $dateFieldName, $input->{$dateFieldName}, '' );

  my $requestData = _formatHash( { transaction_date => $date } );

  my $ms = _createMicroserviceCaller(
    { requestData => $requestData,
      method      => 'DELETE',
      server      => getServer()
    }
  );

  _processRequest(
    $ms,
    sub {
      my $success = shift;

      my $status = new PlugNPay::Util::Status(1);

      if ($success) {
        $status->setTrue();
      } else {
        my $logger = new PlugNPay::Logging::DataLog( { 'collection' => 'SupplementalData' } );
        $logger->log(
          { 'status'   => 'ERROR',
            'message'  => 'Failed to delete supplemental data.',
            'function' => 'deleteSupplementalData',
            'module'   => 'PlugNPay::Order::SupplementalData',
            'error'    => $ms->getErrors()
          }
        );
        $status->setFalse();
        $status->setError('Failed to delete supplemental data.');
        $status->setErrorDetails( $ms->getErrors() );
      }

      return $status;
    }
  );
}

sub _processRequest {
  my $microservice = shift;
  my $callback     = shift;

  my $status = $microservice->doRequest();
  if ( ref($callback) ne 'CODE' ) {
    die('callback is not a subroutine');
  }

  &{$callback}($status);
}

sub _createMicroserviceCaller {
  my $input = shift;

  my $requestDataFieldName = 'requestData';
  my $requestData = _input( $requestDataFieldName, $input->{$requestDataFieldName}, 'HASH' );

  my $methodFieldName = 'method';
  my $method = _input( $methodFieldName, $input->{$methodFieldName}, '' );

  my $serverFieldName = 'server';
  my $server = _input( $serverFieldName, $input->{$serverFieldName}, '' );

  my $subURLFieldName = 'subURL';
  my $subURL          = '';
  if ( defined $input->{$subURLFieldName} ) {
    $subURL = _input( $subURLFieldName, $input->{$subURLFieldName}, '' );
  }

  my $ms = new PlugNPay::ResponseLink::Microservice( $server . '/supplementalData' . $subURL );
  $ms->setTimeout(10);
  $ms->setMethod($method);
  $ms->setContentType('application/json');
  $ms->setContent($requestData);

  return $ms;
}

sub _input {
  my $name    = shift;
  my $value   = shift;
  my $refType = shift;

  my ( $package, undef, $line, $function ) = caller(1);

  my $location = "function $function in $package line $line";

  if ( !defined $value ) {
    die("Undefined value for $name passed to $location");
  }

  my $isType = ref($value);
  if ( defined $refType && $isType ne $refType ) {
    die( sprintf( 'Invalid type "%s" for %s, expected "%s" passed to %s', $isType, $name, $refType, $location ) );
  }

  return $value;
}

sub _formatHash {
  my $data = shift;

  my $formattedHash = {};

  foreach my $key ( keys( %{$data} ) ) {
    next if !defined $key || $key eq '';
    if ( ref( $data->{$key} ) eq 'HASH' ) {
      $formattedHash->{ sprintf( "%s", $key ) } = _formatHash( $data->{$key} );
    } elsif ( ref( $data->{$key} ) eq 'ARRAY' ) {
      $formattedHash->{$key} = _formatArray( $data->{$key} );
    } else {
      my $val = defined $data->{$key} ? $data->{$key} : '';
      $formattedHash->{ sprintf( "%s", $key ) } = sprintf( "%s", $val );
    }
  }
  return $formattedHash;
}

sub _formatArray {
  my $data = shift;

  my $formattedArray = [];

  foreach my $val ( @{$data} ) {
    if ( ref($val) eq 'HASH' ) {
      push @{$formattedArray}, _formatHash($val);
    } elsif ( ref($val) eq 'ARRAY' ) {
      push @{$formattedArray}, _formatArray($val);
    } else {
      $val = defined $val ? $val : '';
      push @{$formattedArray}, sprintf( "%s", $val );
    }
  }
  return $formattedArray;
}

1;
