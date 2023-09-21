package PlugNPay::Logging::Transaction;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Logging::Format;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Features;
use PlugNPay::Metrics;
use PlugNPay::Currency;
use File::Basename;
use Cwd qw(abs_path);

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;
  return $self;
}

sub log {
  my $self = shift;
  my $data = shift;

  my $transactionData = $data->{'transactionData'};

  my $transactionObj = $data->{'transaction'} if $data->{'transaction'};
  my $operation = $data->{'operation'};

  my @deleteParameters = ('customname99999999','customvalue99999999');
  # delete the parameters we don't want to log
  foreach my $parameter (@deleteParameters) {
    delete $data->{$parameter};
    delete $transactionData->{$parameter};
    delete $transactionObj->{$parameter};
  }

  my $duration = $data->{'duration'} if $data->{'duration'};
  my $remoteIpAddress = $data->{'remoteIpAddress'} if $data->{'remoteIpAddress'};
  my $ipAddress = $data->{'ipAddress'} if $data->{'ipAddress'};
  my $templateName = $data->{'templateName'} if $data->{'templateName'};

  if (ref($transactionObj) !~ /^PlugNPay::Transaction/) {
    die("expected object to be of type PlugNPay::Transaction, got " . ref($transactionObj) . " instead");
  }

  die('No Order ID for transaction found.') if (!defined $transactionObj->getOrderID());

  my $accountName = $transactionObj->getGatewayAccount();
  my $gatewayAccount = new PlugNPay::GatewayAccount($accountName);
  my $internalIdObj = new PlugNPay::GatewayAccount::InternalID();
  my $merchantId = $internalIdObj->getIdFromUsername($accountName);
  my $merchantOrderId = $transactionObj->getOrderID();
  my $transactionDateTime = $transactionObj->getTransactionDateTime('iso_gm_nano_log');
  my $transactionType = $transactionObj->getTransactionType();
  my $transactionAmount = $transactionObj->getTransactionAmount();
  my $currency = $transactionObj->getCurrency();
  my $gatewayAccount = new PlugNPay::GatewayAccount($accountName);
  my $features = new PlugNPay::Features($accountName, 'general');
  my $fraud = new PlugNPay::Features($accountName, 'fraud_config');
  my $response = $transactionObj->getResponse();
  my $processorID = $transactionObj->getProcessorID();
  my $isDuplicate = 0;
  my $finalStatus;
  if ($response) {
    $isDuplicate = $response->getDuplicate();
    $finalStatus = $response->getStatus();
  }

  eval {
    my $currencyInfo = new PlugNPay::Currency($currency);
    my $currencyMultiple = (10 ** $currencyInfo->getPrecision()) || 100;
    my @transCountMetricPath = ('transaction','status',$accountName,$transactionType,$finalStatus);
    my @transVolumeMetricPath = ('transaction','volume',$accountName,$currency,$transactionType,$finalStatus);
    my @transactionTimingMetricPath = ('transaction','duration',$accountName,$processorID,$transactionType);
    my $requestUri = $ENV{'REQUEST_URI'};
    $requestUri =~ s/^\///g; # remove leading slash from uri
    if ($requestUri) {
      if ($requestUri =~ /\/api\//) {
        $requestUri =~ s/:\w//g; # remove variables from uri
        $requestUri =~ s/\!.*//g; # remove rest options from uri
      }
      $requestUri =~ s/\?.*$//; # remove queryString
      $requestUri =~ s/\.//; # remove periods
      $requestUri =~ s/[^a-zA-Z0-9_]/_/g;
      push @transCountMetricPath,$requestUri;
    } else {
      my $scriptName = basename($0) || 'UNKNOWN';
      $scriptName = abs_path($0);
      $scriptName =~ s/^\/home\/(p\/)?pay1\///; # remove path to pay1 home dir
      $scriptName =~ s/[^a-zA-Z0-9_]/_/g;
      push @transCountMetricPath,$scriptName;
    }

    my $metrics = new PlugNPay::Metrics();

    # send stat for transaction count
    $metrics->increment({
      metric => join('.',@transCountMetricPath),
      value => 1
    });

    # send stat for transaction volume
    $metrics->increment({
      metric => join('.',@transVolumeMetricPath),
      # value => $transactionAmount in smallest individual unit of currency
      value => sprintf('%d',$transactionAmount * $currencyMultiple)
    });

    # send stat for transaction duration
    $metrics->timing({
      metric => join('.',@transactionTimingMetricPath),
      value => sprintf('%d',($duration * 1000.00))
    });
  };

  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'transactions'});

  my %rawData;
  my $cardInfo = $transactionObj->getCreditCard();
  my $cardNumber;
  if ($cardInfo) {
    $cardNumber = $cardInfo->getNumber();
    %rawData = map { ($_ =~ /$cardNumber/) ? 'CARD_DATA_FOUND' : $_  } %{$transactionData};
    foreach my $key (keys %rawData) {
      if ($key =~ /(cvv|security_code)/ && $rawData{$key} =~ /^\d{3,4}$/) {
        $rawData{$key} = 'POTENTIAL_CARD_SECURITY_CODE_REMOVED';
      }
    }
  } else {
    %rawData = %{$transactionData};
  }

  # map raw fields to supplementalData
  eval {
    my $supplementalDataMappings = $features->get('supplementalDataMappings');
    if ($supplementalDataMappings) {
      foreach my $fieldName (@{$supplementalDataMappings}) {
        my $mappedFieldName = 'x-mapped-' . $fieldName;
        my $customData = $transactionObj->getCustomData();
        $customData->{$mappedFieldName} = $rawData{$fieldName};
      }
    }
  };

  my $transLogFormatter = new PlugNPay::Transaction::Logging::Format();
  my $transactionHash = $transLogFormatter->format($transactionObj);
  my $fraudSettings = $fraud->getFeatures();

  foreach (keys %{$fraudSettings}){
    delete $fraudSettings->{$_} if $fraudSettings->{$_} eq "";
  }

  my $logData = {
    'merchantId'          => $merchantId,
    'merchantOrderId'     => $merchantOrderId,
    'isDuplicate'         => "$isDuplicate",   # we want this as a string
    'transactionDateTime' => $transactionDateTime,
    'transactionType'     => $transactionType,
    'operation'           => $operation,
    'finalStatus'         => $finalStatus,
    'transactionDetails'  => {
      'transaction' => $transactionHash,
      'rawData'     => \%rawData
    },
    'features'        => $features->getFeatures(),
    'fraudSettings'   => $fraudSettings,
    'duration'        => $duration,
    'remoteIpAddress' => $remoteIpAddress,
    'ipAddress'       => $ipAddress,
    'templateName'    => $templateName,
    'secureProtocol'  => $ENV{'SSL_PROTOCOL'} || $ENV{'X-SSL_PROTOCOL'} || 'N/A',
    'secureCipher'    => $ENV{'SSL_CIPHER'} || $ENV{'X-SSL_CIPHER'} || 'N/A'
  };

  $logger->log($logData, { stackTraceEnabled => 1 });
}

1;
