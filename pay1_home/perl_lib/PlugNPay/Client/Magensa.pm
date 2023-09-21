package PlugNPay::Client::Magensa;

use strict;
use JSON::XS;
use Time::HiRes qw();
use PlugNPay::Processor::ID;
use PlugNPay::Util::UniqueID;
use PlugNPay::Processor::SocketConnector;
use PlugNPay::Processor::Process::MessageBuilder;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;


  return $self;
}

sub setRequestID {
  my $self = shift;
  my $requestID = shift;
  $self->{'requestID'} = $requestID;
}

sub getRequestID {
  my $self = shift;
  return $self->{'requestID'};
}

#create request with sections for Magensa processor
sub createRequestForProcessor {
  my $self = shift;
  my $query = shift;
  
  #putting data in JSON with sections
  #putting requestID data together
  my %extraProcessorData = ();
  $extraProcessorData{'processor_reference_id'} = ''; 
  
  #putting transactionData together
  my $requestID = new PlugNPay::Util::UniqueID()->inHex();
  $self->setRequestID($requestID);
  my %transactionData = ();
  
  $transactionData{'customerCode'} = $query->{'customerCode'};
  $transactionData{'username'} = $query->{'username'};
  $transactionData{'password'} = $query->{'password'};
  $transactionData{'actionType'} = 'DecryptCardSwipe';
  $transactionData{'pnp_transaction_id'} = $requestID; 
  $transactionData{'requestType'} = 'request';
  $transactionData{'notes'} = '';
  

  #putting sensitiveData together
  my %sensitiveTransactionData = ();
  
  $sensitiveTransactionData{'devicesn'} = defined $query->{'DeviceSN'} ? $query->{'DeviceSN'} : '';
  $sensitiveTransactionData{'KSN'} = $query->{'KSN'};
  $sensitiveTransactionData{'keyType'} = defined $query->{'keyType'} ? $query->{'keyType'} : '';
  $sensitiveTransactionData{'magnePrint'} = defined $query->{'EncMP'} ? $query->{'EncMP'} : '';
  $sensitiveTransactionData{'magnePrintStatus'} = defined $query->{'MPStatus'} ? $query->{'MPStatus'} : '';
  $sensitiveTransactionData{'EncTrack1'} = $query->{'EncTrack1'};
  $sensitiveTransactionData{'EncTrack2'} = $query->{'EncTrack2'};
  $sensitiveTransactionData{'EncTrack3'} = defined $query->{'EncTrack3'} ? $query->{'EncTrack3'} : '';
  
  
  #putting additionalMerchantData together
  my %addtionalMerchantData = ();
  $addtionalMerchantData{'merchant_type'} = 'ecom';
  
  my %requestHashValues = ();
  $requestHashValues{'requestID'} = $requestID; 
  $requestHashValues{'priority'} = '5';
  $requestHashValues{'processor'}='magensa';
  $requestHashValues{'type'}='request';
  $requestHashValues{'additionalProcessorData'} = \%extraProcessorData;
  $requestHashValues{'transactionData'} = \%transactionData;
  $requestHashValues{'sensitiveTransactionData'} = \%sensitiveTransactionData;
  $requestHashValues{'additionalMerchantData'} = \%addtionalMerchantData;
  
  my %requestHash = ();
  $requestHash{$requestID} = \%requestHashValues;
  
  #put all data together in JSON with sections
  my %queryForProcessor=();
  $queryForProcessor{'messageID'} = new PlugNPay::Util::UniqueID()->inHex();
  #request
  $queryForProcessor{'requests'} = \%requestHash;
  
  return \%queryForProcessor;
}

sub connectToMagensa {
  my $self = shift;
  my $query = shift;
  #Prepare Message
  my $queryForProcessor = $self->createRequestForProcessor($query);
  my $util = new PlugNPay::Processor::ID();
  my $processor_id = $util->getProcessorID("magensa");
  my $json = encode_json($queryForProcessor);
 
  #Send message to Magensa
  my $connector = new PlugNPay::Processor::SocketConnector();
  my $pendingJSON = $connector->connectToProcessor($json,$processor_id);

  #Return as hash
  return decode_json($pendingJSON);
}

sub redeemPending {
  my $self = shift;
  my $pending = shift;
  my $connector = new PlugNPay::Processor::SocketConnector();
  my $util = new PlugNPay::Processor::ID();
  my $uuid = new PlugNPay::Util::UniqueID();
  my $processorID = $util->getProcessorID('magensa');

  #Add required fields to redeem
  $pending->{'type'} = 'redeem';
  $pending->{'processor'} = 'magensa';
  $pending->{'priority'} = '6';
  $pending->{'requestID'} = $self->getRequestID();
  my $redeem = {'messageID' => $uuid->inHex(), 'requests' => { $self->getRequestID() => $pending}};
  my $sleepTime = 0.1;
  Time::HiRes::sleep($sleepTime);
  my $requestJSON = encode_json($redeem);
  my $responseJSON = $connector->connectToProcessor($requestJSON,$processorID);
  my $responses = decode_json($responseJSON)->{'responses'}{$self->getRequestID()};
  
  #If response from magensa takes longer than .1 seconds
  while ($sleepTime < 10 && !defined $responses->{'Track1'}) {
    Time::HiRes::sleep($sleepTime);
    $responseJSON = $connector->connectToProcessor($requestJSON,$processorID);
    $responses = decode_json($responseJSON)->{'responses'}{$self->getRequestID()};
    $sleepTime *= 2;
  }

  return $responses;
}


sub runRequest {
  
  my $self = shift;
  my $query = shift;
  
  my $pending = $self->connectToMagensa($query);
  my $magensaData = $self->redeemPending($pending);
  $self->cleanup($pending);

  return $magensaData;
}

sub cleanup {
  my $self = shift;
  my $pending = shift;
  my $connector = new PlugNPay::Processor::SocketConnector();
  my $util = new PlugNPay::Processor::ID();
  my $uuid = new PlugNPay::Util::UniqueID();
  my $processorID = $util->getProcessorID('magensa');

  #Add required fields to redeem
  $pending->{'type'} = 'remove';
  $pending->{'processor'} = 'magensa';
  $pending->{'priority'} = '3';
  $pending->{'requestID'} = $self->getRequestID();
  my $redeem = {'messageID' => $uuid->inHex(), 'requests' => { $self->getRequestID() => $pending}};
  my $requestJSON = encode_json($redeem);
  my $responseJSON = $connector->connectToProcessor($requestJSON,$processorID);
  my $responses = decode_json($responseJSON)->{'responses'}{$self->getRequestID()};

  return $responses;
}

1;
