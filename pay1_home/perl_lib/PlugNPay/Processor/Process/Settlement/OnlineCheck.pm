package PlugNPay::Processor::Process::Settlement::OnlineCheck;

use strict;
use JSON::XS;
use Time::HiRes;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Updater;
use PlugNPay::Processor::SocketConnector;
use PlugNPay::Sys::Time;
use PlugNPay::Processor::Account;
use PlugNPay::Util::UniqueID;
use PlugNPay::AWS::S3::Object;

our $cachedBucket;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub settle {
  my $self = shift;
  my $time = shift;
  my $updater = new PlugNPay::Transaction::Updater();
  my $results = {};

  if (!$time) {
    my $timeObj = new PlugNPay::Sys::Time();
    $time = $timeObj->nowInFormat('yyyymmdd_gm');
  }

  # Load successful auths
  my $transactions = $updater->loadAuthorizedChecks($time);

  # Send status request, then redeem statuses
  my $statusChanges = $self->getStatusChanges($transactions);

  # Update transactions with results
  if (keys %{$statusChanges}) {
    $results = $updater->updateACHTransactions($statusChanges);
  }

  #cleanup Java
  $self->cleanup();

  return $results;
}

sub getStatusChanges {
  my $self = shift;
  my $transactions = shift;

  #Format Requests & Responses & TransID Map
  my $requestData = $self->formatJSON($transactions);

  #Send requests
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();
  my $connectionHandler = new PlugNPay::Processor::SocketConnector();
  my $pending = {};
  foreach my $processor (keys %{$requestData->{'requests'}}) {
    eval {
      my $message = $messageBuilder->buildStatusMessage($requestData->{'requests'}{$processor});
      my @keys = keys %{$message};
      my $requestJSON = encode_json($message);
      my $responseJSON = $connectionHandler->connectToProcessor($requestJSON,$processor);
      my $responseData = decode_json($responseJSON);
      $pending->{$processor} = $responseData->{'responses'};
    };

    if ($@) {
      $self->log({'processor' => $processor, 'method' => 'ACH settlement: getStatusChanges', 'error' => $@});
    }
  }

  #Wait
  Time::HiRes::sleep(1);

  #Send Redeems
  my %results = (); #TransID => changes
  foreach my $processor (keys %{$pending}) {
    eval {
      my $message = $messageBuilder->buildStatusMessage($requestData->{'redeems'}{$processor});
      my $requestJSON = encode_json($message);
      my $responseJSON = $connectionHandler->connectToProcessor($requestJSON,$processor);
      my $response = decode_json($responseJSON);
      my $responseData = $response->{'responses'};
      # Mom's spaghetti
      %results = (%{$self->getCompletedStatusChanges($processor,$responseData)},%results);
      if ($@) {
        $self->log({'processor' => $processor, 'method' => 'ACH settlement: getStatusChanges', 'error' => $@});
      }
    };
  }

  #Return so we can update
  return \%results;
}

sub getCompletedStatusChanges {
  my $self = shift;
  my $processor = shift;
  my $currentResponses = shift;
  my %completed = ();
  my $pending = {};
  my $time = 0.1;
  my @cleanupKeys = ();
  my $filesToUpload = {};
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();
  foreach my $requestID (keys %{$currentResponses}) {
    my $response = $currentResponses->{$requestID};
    if ($response->{'processor_status'} ne 'pending' && ref($response->{'statusChanges'}) eq 'HASH') {
      %completed = (%{$response->{'statusChanges'}}, %completed);
      my $merchant = $response->{'gatewayAccount'};
      $filesToUpload->{$merchant} = {'raw' => $response->{'rawResponse'}, 'required'  => $response->{'processorData'}, 'processor' => $processor};
      push @cleanupKeys,$requestID;
    } else {
      $pending->{$requestID} = $response;
    }
  }

  my $sleepTime = 0.1;
  my $connector = new PlugNPay::Processor::SocketConnector();
  while (keys(%{$pending}) > 0 && $sleepTime < 10) {
    Time::HiRes::sleep($sleepTime);
    my $JSON = encode_json($messageBuilder->build($pending));
    my $responsesFromProcessor = $connector->connectToProcessor($JSON,$processor);
    my $responseDataHash = decode_json($responsesFromProcessor);
    my $responseData = $responseDataHash->{'responses'};
    my $tempHash = {};
    foreach my $requestID (keys %{$responseData}) {
      my $response = $responseData->{$requestID};
      if ($response->{'processor_status'} ne 'pending' && $response->{'statusChanges'}) {
        %completed = (%{$response->{'statusChanges'}}, %completed);
        my $merchant = $response->{'gatewayAccount'};
        $filesToUpload->{$merchant} = {'raw' => $response->{'rawResponse'}, 'required'  => $response->{'processorData'}, 'processor' => $processor};
        push @cleanupKeys,$requestID;
      } else {
        $tempHash->{$requestID} = $response;
      }
    }

    $sleepTime *= 2;
    $pending = $tempHash;
  }

  $self->{'cleanup'}{$processor} = \@cleanupKeys;
  my $uploadStatus = 0;
  eval {
    # upload a file per merchant
    $uploadStatus = $self->writeResultsToAWS($filesToUpload);
  };

  if ($@) {
    $self->log({'processor' => $processor, 'error' => $@, 'message' => 'Failed to upload results to AWS', 'data' => $filesToUpload}, 'achSettlement');
  } elsif (!$uploadStatus) {
    $self->log({'processor' => $processor, 'error' => 'Bad response code from AWS S3 API', 'message' => 'Failed to upload results to AWS', 'data' => $filesToUpload}, 'achSettlement');
  }
  return \%completed;
}

sub formatJSON {
  my $self = shift;
  my $rows = shift;

  #Make both the REQUEST and REDEEM data
  my $requests = {};
  my $redeems = {};
  my $uuid = new PlugNPay::Util::UniqueID();
  foreach my $row (@{$rows}) {
     my $processor = $row->{'processor_code_handle'};
     my $account = $row->{'identifier'};
     $uuid->fromBinary($row->{'pnp_transaction_id'});
     my $pnpID = $uuid->inHex();

     if (!$requests->{$processor}) {
       $requests->{$processor} = {};
       $redeems->{$processor} = {};
     }

     #Only add merchant once, but add every trans ID to merchant's transMap
     unless ($requests->{$processor}{$account}) {
       # Need to load credentials
       my $processorSettings = new PlugNPay::Processor::Account({'processorName' => $processor, 'gatewayAccount' => $account});
       my $requestIDGenerator = new PlugNPay::Util::UniqueID();

       # Request Data
       $requests->{$processor}{$account} = {'gatewayAccount' => $account,
                                            'settings' => $processorSettings->getSettings(),
                                            'processorData' => $self->getNeedfulFromAWS($account),
                                            'requestID' => $requestIDGenerator->inHex(),
                                            'type' => 'statusRequest',
                                            'transactionData' => {},
                                            'processor' => $processor};

       # Redeem Data
       $redeems->{$processor}{$account} = {'gatewayAccount' => $account,
                                           'type' => 'statusRedeem',
                                           'requestID' => $requestIDGenerator->inHex(),
                                           'processor' => $processor};
     }

     # RefID -> PNPTransID association
     $requests->{$processor}{$account}{'transactionData'}{$row->{'value'}} = $pnpID;
  }

  return {'requests' => $requests, 'redeems' => $redeems};
}

#Don't really care about these results, still should log it
sub cleanup {
  my $self = shift;
  my $cleanup = $self->{'cleanup'};
  my $removedRequests = 0;
  if ($cleanup) {
    my $connector = new PlugNPay::Processor::SocketConnector();
    my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();
    foreach my $processor (keys %{$cleanup} ) {
      my $uuid =  new PlugNPay::Util::UniqueID();
      eval {
        my $message = $messageBuilder->build({$uuid->inHex() => { 'type' => 'statusCleanup', 'cleanupIDs' => $cleanup->{$processor}, 'requestID' => $uuid->inHex(), 'processor' => $processor}});
        my $JSON = encode_json($message);
        my $connector = new PlugNPay::Processor::SocketConnector();
        my $responses = $connector->connectToProcessor($JSON,$processor);
        my $responseHash = decode_json($responses);
        $self->log({'processor' => $processor, 'cleanupResponse' => $responseHash},'achSettlement');
        $removedRequests = 1;
      };
    }
  }

  return $removedRequests;
}

# Log Function #
sub log {
  my $self = shift;
  my $data = shift;
  my $collection = shift || 'transaction';
  my $logger = new PlugNPay::Logging::DataLog({'collection' => $collection});
  $logger->log($data);
}

# AWS interface #
sub getNeedfulFromAWS {
  my $self = shift;
  my $merchantName = shift;
  my $objectHandler = new PlugNPay::AWS::S3::Object(getACHSettlementBucket());
  $objectHandler->setObjectName($merchantName . '/current.json');
  my $results = {};
  eval {
    $results = decode_json($objectHandler->readObject());
  };

  if ($@) {
    $self->log({'error' => $@, 'merchant' => $merchantName, 'message' => 'Failed to read from S3 bucket'}, 'achSettlement');
  }

  return $results;
}

sub writeResultsToAWS {
  my $self = shift;
  my $dataToUpdateWith = shift;
  my $success = 1;
  my $time = new PlugNPay::Sys::Time();
  foreach my $merchantName (keys %{$dataToUpdateWith}) {
    my $merchData = $dataToUpdateWith->{$merchantName};
    my $current = $merchData->{'required'};
    $current->{'gatewayAccount'} = $merchantName;
    $current->{'processor'} = $merchData->{'processor'};
    my $timeString = $time->nowInFormat('gendatetime');
    $success &= $self->_updateProcessorDataFile($merchantName,$current);
    $self->_logResponseToS3($merchantName,'status_changes.' . $time->nowInFormat('gendatetime') . '.json', $merchData->{'raw'});
  }

  return $success;
}

sub _logResponseToS3 {
  my $self = shift;
  my $merchantName = shift;
  my $fileName = shift;
  my $rawResponse = shift;
  eval {
    my $url = $merchantName . '/' . $fileName;
    my $objectHandler = new PlugNPay::AWS::S3::Object($ENV{'ACH_SETTLEMENT_BUCKET'});
    $objectHandler->setObjectName($url);
    $objectHandler->setContentType('json');
    $objectHandler->setContent($rawResponse);
    $objectHandler->createObject();
  };

  if ($@) {
    $self->log({'gatewayAccount' => $merchantName, 'error' => $@, 'message' => 'Failed to upload results to AWS', 'data' => $rawResponse}, 'achSettlement');
  }
}

sub _updateProcessorDataFile {
  my $self = shift;
  my $merchantName = shift;
  my $current = shift;
  my $success = 0;
  eval {
    my $objectHandler = new PlugNPay::AWS::S3::Object($ENV{'ACH_SETTLEMENT_BUCKET'});
    $objectHandler->setObjectName($merchantName . '/current.json');
    $objectHandler->setContentType('json');
    $objectHandler->setContent($current);
    $success = $objectHandler->createObject();
  };

  if ($@) {
    $self->log({'gatewayAccount' => $merchantName, 'error' => $@, 'message' => 'Failed to update processor data file'}, 'achSettlement');
  }

  return $success;
}

sub getACHSettlementBucket {
  if (!defined $cachedBucket || $cachedBucket eq '') {
    my $env = $ENV{'PNP_ORDERS_BUCKET'};
    $cachedBucket = $env || PlugNPay::AWS::ParameterStore::getParameter('/S3/BUCKET/ACH_SETTLEMENT',1);
  }

  die('Failed to load bucket for ach settlement') if $cachedBucket eq '';
  
  return $cachedBucket;
}


1;
