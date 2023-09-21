package PlugNPay::Processor::Route;

use lib '/home/pay1/perlpr_lib';

use strict;
use rsautils;
use miscutils;
use smpsutils;
use Math::BigInt;
use PlugNPay::API;
use PlugNPay::Token;
use PlugNPay::Contact;
use PlugNPay::Features;
use PlugNPay::Processor;
use PlugNPay::CreditCard;
use PlugNPay::OnlineCheck;
use PlugNPay::Environment;
use PlugNPay::DBConnection;
use PlugNPay::Order::Detail;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Logging::Alert;
use PlugNPay::Logging::DataLog;
use PlugNPay::Logging::Performance;
use PlugNPay::Logging::Transaction;
use PlugNPay::Transaction;
use PlugNPay::Transaction::Vault;
use PlugNPay::Transaction::Query;
use PlugNPay::Transaction::Saver::Legacy;
use PlugNPay::Transaction::State;
use PlugNPay::Transaction::MapAPI;
use PlugNPay::Transaction::Formatter;
use PlugNPay::Transaction::Response;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Processor::Mode;
use PlugNPay::Processor::Process;
use PlugNPay::Processor::ResponseCode;
use PlugNPay::Processor::Process::Void;
use PlugNPay::Processor::Process::Settlement;
use PlugNPay::Processor::Process::Unified;
use PlugNPay::Processor::Process::Verification;
use PlugNPay::Util::UniqueID;
use PlugNPay::Util::Cache::LRUCache;
use PlugNPay::Util::StackTrace;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Legacy::Transflags;
use PlugNPay::Processor::MetaProcessor::GoCart;
use PlugNPay::Legacy::SendMServerRequest;
use PlugNPay::Legacy::BatchMark;
use PlugNPay::Order::SupplementalData;

our $cache;
our $logger;

############# Route.pm ###############
# This module is an advanced form of #
# sendmserver from miscutils.pm      #
#                                    #
# Module checks processor, and calls #
# appropriate function depending on  #
# what is loaded from processor      #
# module table.                      #
######################################

sub new {
  my $self  = {};
  my $class = shift;
  bless $self, $class;

  if ( !defined $cache ) {
    $cache = new PlugNPay::Util::Cache::LRUCache(6);
  }

  if ( !defined $logger ) {
    $logger = new PlugNPay::Logging::DataLog( { 'collection' => 'transaction_route' } );
  }

  return $self;
}

sub loadProcessorPackage {    # Load where sendmserver function is for processor
  my $self      = shift;
  my $processor = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare(
    'pnpmisc', q/
                           SELECT m.processor_name,p.payment_type,m.package_name
                           FROM processor_module m, processor_payment_type p
                           WHERE p.id = m.payment_type_id AND m.processor_name = ? /
  );

  $sth->execute($processor) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref( {} );
  my $data = {};
  foreach my $row ( @{$rows} ) {
    if ( lc( $row->{'processor_name'} ) eq lc($processor) ) {
      $data->{ $row->{'payment_type'} } = $row->{'package_name'};
    }
  }

  $cache->set( $processor, $data );
}

sub getProcessorPackageData {    # Get package name where processor calls sendmserver
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare(
    'pnpmisc', q/
                           SELECT m.processor_name,p.payment_type,m.package_name
                           FROM processor_module m, processor_payment_type p
                           WHERE p.id = m.payment_type_id/
  );

  $sth->execute() or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref( {} );
  my $data = {};
  foreach my $row ( @{$rows} ) {
    my $procName  = $row->{'processor_name'};
    my $payMethod = $row->{'payment_type'};
    $data->{$procName}{'name'}                = $procName;
    $data->{$procName}{$payMethod}{'package'} = $row->{'package_name'};
    $data->{$procName}{$payMethod}{'method'}  = $payMethod;
  }

  $self->{'packageData'} = $data;

  return $data;
}

sub getProcessorPackage {
  my $self      = shift;
  my $processor = shift;
  my $payType   = shift;

  unless ( $cache->contains($processor) ) {
    $self->loadProcessorPackage($processor);
  }

  my $response = $cache->get($processor);
  if ($payType) {
    $response = $response->{$payType};
  }

  return $response;
}

sub addNewProcessorPackage {    # Add new processor/package combo
  my $self = shift;
  my $info = shift;
  my $dbs  = new PlugNPay::DBConnection();
  my $sth  = $dbs->prepare(
    'pnpmisc', q/
                           INSERT INTO processor_module
                           (processor_name,payment_type_id,package_name)
                           VALUES (?,?,?)
                           /
  );
  $sth->execute( $info->{'name'}, $info->{'payment_id'}, $info->{'package'} ) or die $DBI::errstr;
  $sth->finish();

  return 1;
}

sub getACHProcessors {
  my $self        = shift;
  my $onlyUnified = shift || 0;
  my $processors  = $self->getProcessorPackageData();
  my $data        = [];
  foreach my $processor ( keys %{$processors} ) {
    if ($onlyUnified) {
      if ( $processors->{$processor}{'package'} eq 'PlugNPay::Processor::Route' ) {
        push @{$data}, $processor;
      }
    } else {
      push @{$data}, $processor;
    }
  }

  return $data;
}

#################################
# Main function for this module #
# This should be the only sub   #
# called from miscutils.pm      #
#################################
sub route {
  my $self = shift;
  my $input = shift;
  my $queryRef = $input->{'transactionData'};
  my $context = $input->{'transactionContext'};
  my $transactionObject = $input->{'transactionObject'};

  # if ipaddress is not set, set it here
  if (!defined $queryRef->{'ipaddress'} || $queryRef->{'ipaddress'} eq '') {
    $queryRef->{'ipaddress'} = new PlugNPay::Environment()->get('PNP_CLIENT_IP');
  }

  my %query = %{$queryRef};
  my $username = $query{'username'};
  my $operation = $query{'operation'};

  my $fullTransactionData = $query{'__full_transaction_data__'};
  delete $query{'__full_transaction_data__'};  # so we don't pass it any further

  # when logging transaction and response, use reference to query if $fullTransactionData is not set
  if ( !$fullTransactionData && $operation !~ /query/) {
    my $stackTrace = new PlugNPay::Util::StackTrace()->string();
    my $message    = { message => 'full transaction data not set.', stackTrace => $stackTrace };
    $logger->log($message);

    my %copyOfQuery = %query;

    # need to swap back for data that was before sendmserver.
    my $realOrderId = $copyOfQuery{'order-id'};
    $copyOfQuery{'order-id'} = $copyOfQuery{'orderID'};
    $copyOfQuery{'orderID'} = $realOrderId;

    $fullTransactionData = \%copyOfQuery;
  }

  my $response;
  my $error; # returned if wantarray() is true

  my $preprocessResult = $self->preprocess( $username, $operation, \%query );
  my $validationResult;

  my $metrics = new PlugNPay::Metrics();
  my $start = $metrics->timingStart();

  # transaction validation after preprocess
  if ($preprocessResult->{'FinalStatus'}) {
    $response = $preprocessResult;
  } else {
    $validationResult = $self->validateTransaction($username,$operation,$fullTransactionData);
    if ($validationResult->{'FinalStatus'}) {
      $response = $validationResult;
    } else {
      ($response,$error) = $self->process({
        data => $preprocessResult,
        context => $context,
        transactionObject => $transactionObject
      });
    }
  }

    # transaction was processed, we can insert supplemental data
  if (inArray($operation,['auth','return','credit'])) {
    eval {
      insertSupplementalData( $username, $fullTransactionData );
    };
    if ($@) {
      $logger->log({
        message => 'Failed to log transaction supplemental data.',
        username => $username,
        orderId => $fullTransactionData->{'orderID'} || 'N/A',
        error => $@
      });
    }
  }

  my $duration = $metrics->timingEnd({
    metric => 'pay1.processor_route.process.duration',
    start => $start
  });

  if ( $response->{'FinalStatus'} =~ /^(success|pending)$/ ) {
    if ($response->{'query'}) {
      my %fraudQuery = %{ $response->{'query'} };
      my $temp       = $fraudQuery{'orderID'};
      $fraudQuery{'orderID'}  = $fraudQuery{'order-id'};
      $fraudQuery{'order-id'} = $temp;

      my %merchfraud = &miscutils::merch_fraud( $username, $operation, $response->{'limits'}, $response->{'custstatus'}, \%fraudQuery, $response->{'feature'} );
      $response->{'merchfraudlev'} = $merchfraud{'level'};
    }
  }
  if (!defined $error && !inArray($response->{'FinalStatus'},['success','pending'])) {
    $error = $response->{'MErrMsg'};
  }

  eval {
    if ($operation !~ /query/) {
      $self->logTransactionAndResponse( $username, $operation, $fullTransactionData, $response, $duration, $transactionObject );
    }
  };
  if ($@) {
    $logger->log({
      message => 'Failed to log transaction details.',
      username => $username,
      orderId => $fullTransactionData->{'orderID'} || 'N/A',
      error => $@
    });
  }

  new PlugNPay::Logging::Performance('Completed Transaction Logging');
  if (wantarray()) {
    return ($response,$error);
  }
  return $response;
}

sub validateTransaction {
  my $self = shift;
  my $username = shift;
  my $operation = shift;
  my $fullTransactionData = shift;

  my $transactionObject = $self->getTransactionObject($username,$operation,$fullTransactionData);

  my $features = new PlugNPay::Features($username,'general');
  my $response = {};
  # Check for required custom values
  if ($transactionObject && (my $fields = $features->get('req_custom_fields')) ne '') {
    if (ref($fields) eq 'ARRAY') {
      my $customData = $transactionObject->getCustomData();
      my @missingFields;
      foreach my $field (@{$fields}) {
        my $value = $customData->{$field};
        if (!defined $value || $value eq '') {
          push @missingFields,$field;
        }
      }
      if (@missingFields > 0) {
       $response = {
          'FinalStatus' => 'problem',
          'MStatus'     => 'problem',
          'MErrMsg'     => 'Data submitted was insufficient to create transaction, missing fields: ' . join(',',@missingFields)
        };
      }
    }
  }

  return $response;
}

sub logTransactionAndResponse {
  my $self             = shift;
  my $username         = shift;
  my $operation        = shift;
  my $transactionHash  = shift;
  my $responseHash     = shift;
  my $duration         = shift;
  my $transactionObject = undef; # TODO accept as input but RUN TESTS TO MAKE SURE IT WORKS.  NOT TO BE DONE IN T1838!!!

  # work off a copy of the hash
  # not really needed if this is already a copy of sendmserver's query but we don't know at this point
  my %copyOfHash = %{$transactionHash};
  my $transactionHash = \%copyOfHash;

  eval {
    if (!$transactionObject) {
      $transactionObject = $self->getTransactionObject($username,$operation,$transactionHash);
    }
    return if !$transactionObject;

    my $transactionResponseObject = $transactionObject->getResponse();
    if (!$transactionResponseObject) {
      $transactionResponseObject = new PlugNPay::Transaction::Response();
      $transactionResponseObject->setRawResponse($responseHash);
      $transactionObject->setResponse($transactionResponseObject);
      my $transactionState = new PlugNPay::Transaction::State();
      my $status = $transactionResponseObject->getStatus();
      my $state = $transactionState->translateLegacyOperation($operation,$status);
      $transactionObject->setTransactionState($state);
    }

    my $logData = {
      transaction     => $transactionObject,
      transactionData => $transactionHash,
      operation       => $operation,
      duration        => $duration,
    };

    my $transactionLogger = new PlugNPay::Logging::Transaction();
    $transactionLogger->log($logData);
  };

  if ($@) {
    my $stackTrace = new PlugNPay::Util::StackTrace()->string();
    my $message    = { message => $@, stackTrace => $stackTrace };
    $logger->log($message);
  }
}

sub getTransactionObject {
  my $self = shift;
  my $username = shift;
  my $operation = shift;
  my $objectOperations = [
    'auth',
    'authprev',
    'reauth',
    'postauth',
    'void',
    'return',
    'credit',
    'returnprev'
  ];

  if (!inArray($operation,$objectOperations)) {
    return undef;
  }

  my $transactionHash = shift;

  my $orderId = $transactionHash->{'orderID'};
  my $cacheKey = sprintf('%s:%s:%s',$username,$operation,$orderId);

  if ($self->{'lastGeneratedTransactionObjectKey'} eq $cacheKey) {
    return $self->{'lastGeneratedTransactionObject'};
  }

  my $cardNumber = $transactionHash->{'card_number'} || $transactionHash->{'card-number'};
  $transactionHash->{'card_number'} = $cardNumber;

  my $api = new PlugNPay::API('payscreens');
  $api->setLegacyParameters($transactionHash);

  my $type = $api->getLegacyUnderscored()->{'accttype'} || 'card';
  my $transactionObject = new PlugNPay::Transaction( $operation, $type );
  $transactionObject->setGatewayAccount($username);

  my $transactionMapper = new PlugNPay::Transaction::MapAPI();
  $transactionMapper->setTransaction($transactionObject);
  $transactionMapper->map( $api => $transactionObject );



  $self->{'lastGeneratedTransactionObjectKey'} = $cacheKey;
  $self->{'lastGeneratedTransactionObject'} = $transactionObject;

  return $transactionObject;
}

# This is process function for new processors #
sub updateTransaction {
  my $self               = shift;
  my $transaction        = shift;
  my $username           = $transaction->{'username'};
  my $operation          = $transaction->{'operation'};
  my %data               = %{ $transaction->{'query'} };
  my $loader             = new PlugNPay::Transaction::Loader();
  my $stateMachine       = new PlugNPay::Transaction::State();
  my $loadedTransactions = {};
  my @transIDs           = ();
  my $pnp_transaction_id = undef;
  my $hexID;
  my @settlementArray = ();

  if ( defined $data{'pnp_transaction_id'} ) {
    my $uuid = new PlugNPay::Util::UniqueID();
    if ( $data{'pnp_transaction_id'} =~ /^[a-fA-F0-9]+$/ ) {
      $hexID = $data{'pnp_transaction_id'};
      $uuid->fromHex( $data{'pnp_transaction_id'} );
      $pnp_transaction_id = $uuid->inBinary();
    } else {
      $pnp_transaction_id = $data{'pnp_transaction_id'};
      $uuid->fromBinary( $data{'pnp_transaction_id'} );
      $hexID = $uuid->inHex();
    }
    push @transIDs, $pnp_transaction_id;
    $loadedTransactions = $loader->newLoad( { 'pnp_transaction_id' => $pnp_transaction_id } )->{$username}{$hexID};
    if ( $stateMachine->getStateNames()->{ $loadedTransactions->{'transaction_state_id'} } !~ /POSTAUTH/i ) {
      my $settlementAmount = ( $loadedTransactions->{'settlement_amount'} ? $loadedTransactions->{'settlement_amount'} : $loadedTransactions->{'transaction_amount'} );
      push @settlementArray, { 'pnp_transaction_id' => $pnp_transaction_id, 'settlement_amount' => $settlementAmount };
    }
  } else {
    my ( $currency, $amount ) = split( / /, $data{'amount'} );
    my $options = {
      'merchant' => $transaction->{'username'},
      'amount'   => $amount || $data{'amount'},
      'currency' => $currency
    };
    if ( $data{'transdate'} ) {
      $options->{'transaction_date_time'} = $data{'transdate'},;
    }

    my $loaded = $loader->newLoad($options)->{ $transaction->{'username'} };

    push @transIDs, ( keys %{$loaded} );

    if ( @transIDs != 1 ) {
      if ( @transIDs > 1 ) {
        my @transactionsToUpdate = ();

        foreach my $transID (@transIDs) {
          push @transactionsToUpdate, $loaded->{$transID};
          my $settlementAmount = ( $loaded->{$transID}{'settlement_amount'} ? $loaded->{$transID}{'settlement_amount'} : $loaded->{$transID}{'transaction_amount'} );
          if ( $stateMachine->getStateNames()->{ $loaded->{$transID}{'transaction_state_id'} } !~ /POSTAUTH/i ) {
            push @settlementArray, { 'pnp_transaction_id' => $transID, 'settlement_amount' => $settlementAmount };
          }
        }
        $loadedTransactions = \@transactionsToUpdate;
      } else {
        return { 'FinalStatus' => 'problem', 'MStatus' => 'Failure', 'MErrMsg' => 'Transaction not found' };
      }
    } else {
      my $settlementAmount = ( $loaded->{ $transIDs[0] }{'settlement_amount'} ? $loaded->{ $transIDs[0] }{'settlement_amount'} : $loaded->{ $transIDs[0] }{'transaction_amount'} );
      if ( $stateMachine->getStateNames()->{ $loaded->{ $transIDs[0] }{'transaction_state_id'} } !~ /POSTAUTH/i ) {
        push @settlementArray, { 'pnp_transaction_id' => $transIDs[0], 'settlement_amount' => $settlementAmount };
      }
      $loadedTransactions = [ $loaded->{ $transIDs[0] } ];
    }

  }

  if ( $operation =~ /^void/ ) {
    my $processObj   = new PlugNPay::Processor::Process::Void();
    my $pending      = $processObj->void($loadedTransactions);
    my $responses    = $processObj->redeemPending($pending);
    my @keys         = keys %{$responses};
    my $transactions = $responses->{ $keys[0] };
    if ( defined $hexID ) {
      return $transactions->{$hexID};
    } else {
      my @responseIDs = keys %{$transactions};
      return $transactions->{ $responseIDs[0] };
    }
  } elsif ( lc($operation) =~ /postauth/ ) {
    my $processObj = new PlugNPay::Processor::Process::Settlement();
    my $success    = $processObj->markForSettlement( \@settlementArray );
    if ($success) {
      return { 'FinalStatus' => 'success', 'MStatus' => 'Success', 'MErrMsg' => 'Successfully settled transactions', 'transactions' => \@settlementArray };
    } else {
      return { 'FinalStatus' => 'problem', 'MStatus' => 'Failure', 'MErrMsg' => 'Unable to mark transactions' };
    }
  } else {
    return { 'FinalStatus' => 'problem', 'MStatus' => 'Failure', 'MErrMsg' => 'Invalid Operation' };
  }
}

# This is *ONLY* for unified processors!
sub sendmserver {
  my $self = shift;
  my $unified = new PlugNPay::Processor::Process::Unified();
  my $result = $unified->sendmserver(@_);
  return $result;
}

# Determines which module to use for processor #
sub process {
  my $self   = shift;
  my $input = shift;

  my $data = $input->{'data'};
  my $context = $input->{'context'};
  my $transactionObject = $input->{'transactionObject'};

  my $method = $data->{'paymethod'} =~ /checking|savings/i ? 'ach' : $data->{'paymethod'};
  my $procssorType = $method eq 'credit' ? 'card' : $method; # translate credit to card if need be
  $data->{'currentProcessor'} = $data->{ lc($procssorType) . 'Processor' } || $data->{'cardProcessor'};

  my $module;

  if ( $method eq 'gift' || $method eq 'prepaid' || $method eq 'card' ) {
    $method = 'credit';
  }

  my $packageData = $self->getProcessorPackage( $data->{'currentProcessor'} );
  my %result = ();
  if ( defined $data->{'result'} ) {
    %result = %{ $data->{'result'} };
  }

  my %result1 = ();
  if ( defined $data->{'result1'} ) {
    %result1 = %{ $data->{'result1'} };
  }
  if ( $data->{'username'} eq '' || $data->{'currentProcessor'} eq '' || $data->{'paymethod'} eq '' ) {
    $result{'FinalStatus'} = 'problem';
    $result{'MStatus'}     = 'problem';
    $result{'MErrMsg'}     = 'Missing required setup information, please contact technical support.';
    %result = ( %result, %result1 );
    return \%result;
  } elsif ( ($data->{'operation'} =~ /^(auth|sale|credit|storedata)$/) && ($data->{'query'}{'orderID'} =~ /^\d+$/) ) {
    my $maxValue = new Math::BigInt('18446744073709551615');
    my $bigOrderID = new Math::BigInt("$data->{'query'}{'orderID'}");
    if ($bigOrderID > $maxValue) {
      my $features = new PlugNPay::Features($data->{'username'}, 'general');
      if (!$features->get('allow_big_orderid')) {
        $result{'FinalStatus'} = 'problem';
        $result{'MStatus'}     = 'problem';
        $result{'MErrMsg'}     = 'Order ID out of range, order ID may not exceed max integer value.';
        %result = ( %result, %result1 );
        return \%result;
      }
    }
  }
  if ( $data->{'operation'} eq 'storedata' || $data->{'paymethod'} eq 'goCart' ) {
    eval {
      my %query = %{ $data->{'query'} };

      #swapping to maintain legacy code
      my $temp = $query{'order-id'};
      $query{'order-id'} = $query{'orderID'};
      $query{'orderID'}  = $temp;
      my @pairs = %query;
      require pnplite;
      if ($query{'paymethod'} eq 'goCart') {
        my $goCartData = {'clientResponse' => $query{'pt_client_response'}, 'goCartOrderID' => $query{'pt_order_classifier'}};
        my $goCartProcessor = new PlugNPay::Processor::MetaProcessor::GoCart($query{'username'});
        my $responseData = $goCartProcessor->postProcess($goCartData);
        for my $key (keys %{$responseData}) {
          push @pairs, ($key, $responseData->{$key});
        }
      }
      %result = &pnplite::sendmserver( $data->{'username'}, $data->{'operation'}, @pairs );
    };
  } else {
    $module = $packageData->{$method};
    if ( !defined $module ) {
      $module = lc $data->{'currentProcessor'};
      $module =~ s/://g;
    }

    $logger->log(
      { 'message'         => $data->{'username'} . ' is making a ' . $data->{'operation'} . ' request to module ' . $module . ' for processor ' . $data->{'currentProcessor'},
        'operation'       => $data->{'operation'},
        'processorModule' => $module,
        'processor'       => $data->{'currentProcessor'},
        'orderID'         => $data->{'query'}{'orderID'},
        'username'        => $data->{'username'}
      }
    );
    my $processorObject = new PlugNPay::Processor( { 'shortName' => $data->{'currentProcessor'} } );
    if ( $processorObject->getStatus() eq 'down' ) {
      $logger->log(
        { 'processor' => $processorObject->getShortName(),
          'status'    => $processorObject->getStatus(),
          'orderID'   => $data->{'query'}{'orderID'},
          'merchant'  => $data->{'username'}
        }
      );
      $result{'FinalStatus'} = 'problem';
      $result{'MErrMsg'} = 'The processor ' . $processorObject->getName() . ' is currently down.';
      $result{'MStatus'} = 'Problem';
    } else {
      if ( $data->{'username'} =~ /^test/ && $module !~ /^PlugNPay/ ) {
        my $module2 = $module . "tst";
        eval "require $module2";
        $logger->log( { 'message' => 'Using test module: ' . $module . ' -> ' . $module2, 'username' => $data->{'username'} } );
      } else {
        my $exec = "require $module;";
        eval "require $module;";
        if ($@) {
          $logger->log( { 'message' => 'Failed to load module: ' . $module . ', username' => $data->{'username'}, errorMessage => $@ } );
        }
      }
      eval {
        if ( $module =~ /^PlugNPay/ ) {
          my $response = $module->sendmserver($data,$context);

          if ( defined $response && ref($response) eq 'HASH' ) {
            %result = %{$response};
          } else {
            $result{'FinalStatus'} = 'problem';
            $result{'MStatus'}     = 'problem';
            $result{'MErrMsg'}     = 'No response received from processor, unable to complete transaction.';
          }
        } else {
          my $username  = $data->{'username'};
          my $operation = $data->{'operation'};
          my %query     = %{ $data->{'query'} };

          #swapping to maintain legacy code
          my $temp = $query{'order-id'};
          $query{'order-id'} = $query{'orderID'};
          $query{'orderID'}  = $temp;

          my @pairs = %query;
          my $sendMServerRequest = createSendMServerRequest($data->{'currentProcessor'},$username,$operation,\%query);

          my $resultRef;
          if (isQueryOperation($operation)) {
            if (bypassSendMServerForQueries($module)) {
              if ($operation eq 'details') {
                my %r = smpsutils::details( $username, $operation, %query );
                $resultRef = \%r;
              } elsif (inArray($operation,['query','card-query','batch-prep','batchquery'])) {
                my $input = {
                  username => $username,
                  operation => $operation,
                  query => \%query,
                  options => {}
                };

                if (inArray($operation,['batch-prep','batchquery'])) {
                  $input->{'options'}{'no-capture'} = 1;
                }

                my %r = smpsutils::query( $input );
                $resultRef = \%r;
              } else {
                $logger->log({ 'message' => 'Operation of query type sent to processor module, consider bypassing', username => $data->{'username'}, operation => $operation, module => $module });
              }
            }
          } elsif ($operation eq 'batch-commit' && bypassSendMServerForBatchCommit($module)) {
            my $batchMark = new PlugNPay::Legacy::BatchMark();
            $resultRef = $batchMark->viaRoute($username,\%query);
          }

          # resultref will be defined if a query was done already
          if (defined $resultRef) {
            %result = %{$resultRef};
          } else {
            eval '%result = ' . $module . '::sendmserver($sendMServerRequest);';
            die $@ if $@;

            if ($result{'saveToTransactionDatabase'}) {
              #if result hash item set, then we save AFTER returning from sendmserver
              delete $result{'saveToTransactionDatabase'};
              my $legacySaver = new PlugNPay::Transaction::Saver::Legacy();
              my $transactionData = $transactionObject;
              my $shouldBypass = 0; #bypass order summary save here
              if (!$transactionData) {
                my $pairData = $sendMServerRequest->getPairs();
                $shouldBypass = 1;
                $transactionData = {
                  'data' => $pairData,
                  'username' => $sendMServerRequest->getGatewayAccount(),
                  'operation' => $sendMServerRequest->getOperation(),
                  'responseData' => \%result
                };
              }
              $legacySaver->save($transactionData, \%result, $shouldBypass);
              
              #cleanup
              delete $result{'processor_status'};
              delete $result{'processor_message'};
              delete $result{'transaction_state_id'};
            } else {
              # if transaction object is passed, it is the responsibility of process to insert into ordersummary and orderdetails
              if ($transactionObject && inArray($operation,['auth','authprev'])) {
                # order summary.  all required info is in the transaction object
                my $legacySaver = new PlugNPay::Transaction::Saver::Legacy();
                $legacySaver->storeTransactionOrderSummary($transactionObject, \%result);

                # TODO: orderdetails, requires order object to be set on transaction
                if ($transactionObject->getOrder()) {
                  # insert order details
                }
              }
            }
          }
        }
      };
      if ($@) {
        my $error = $@;
        $result{'FinalStatus'} = 'problem';
        $result{'MStatus'}     = 'problem';
        $result{'MErrMsg'}     = 'Processing error occurred, please contact technical support.';
        if ( $error !~ /ModPerl::Util::exit/i ) {
          eval {
            my $message = 'An error occurred during transaction processing: ' . $error . '  -- Processor: ' . $data->{'currentProcessor'} . ' --Merchant: ' . $data->{'username'};
            if ( $data->{'currentProcessor'} eq "" ) {
              $message = 'Merchant ' . $data->{'username'} . ' attempted to process with no processor! --Operation: ' . $data->{'operation'} . '  --Error: ' . $error;
            }
            my $alerter = new PlugNPay::Logging::Alert();
            $alerter->alert( 6, $message );
            $alerter->sendAlerts();    #Normally done via cronjob, but this is a priority.
          };
        }
        $logger->log(
          { 'error'     => $error,
            'message'   => 'Processing error occurred',
            'username'  => $data->{'username'},
            'operation' => $data->{'operation'},
            'payMethod' => $method,
            'package'   => $packageData,
            'orderID'   => $data->{'query'}{'orderID'}
          }
        );
      }
    }
  }
  %result = ( %result, %result1 );

  return \%result;
}

sub insertSupplementalData {
  my $username = shift;
  my $fullTransactionData = shift;

  # if there's no username we can't get/create an internal id and therefore can not insert
  # supplemental data, so return.
  if (!defined $username || $username eq '' ) {
    return
  }

  my $customData = getCustomData($username, $fullTransactionData);

  # if there is no custom data, return
  if (scalar(keys %{$customData}) == 0) {
    return
  }

  my $gatewayAccountInternalId = new PlugNPay::GatewayAccount::InternalID();
  my $merchantId = $gatewayAccountInternalId->getIdFromUsername($username);
  my $orderId = $fullTransactionData->{'orderID'};

  my $now = new PlugNPay::Sys::Time();
  my $transTime = $fullTransactionData->{'trans_time'} || $now->inFormat('db');
  # take trans time in "db" gm time and make it look like RFC3339 format by adding T and Z
  $transTime =~ s/ /T/;
  $transTime .= 'Z';

  my $data = {
    merchant_id => $merchantId,
    order_id => $orderId,
    transaction_date => $transTime, # is actually transaction time, in RFC3339 format
    supplemental_data => {
      customData => $customData
    }
  };

  my $supplementalData = new PlugNPay::Order::SupplementalData();
  $supplementalData->insertSupplementalData({
    items => [$data]
  });
}

sub getCustomData {
  my $username = shift;
  my $fullTransactionData = shift;


  # get field names
  my %customData;
  foreach my $key (keys %{$fullTransactionData}) {
    if ($key =~ /^customname(\d+)$/) {
      my $customDataKey = $fullTransactionData->{$key};

      # payscreensVersion isn't custom data
      next if $customDataKey eq 'payscreensVersion';

      my $customDataValue = $fullTransactionData->{'customvalue' . $1};
      $customData{$customDataKey} = $customDataValue;
    }
  }
  
  my $features = new PlugNPay::Features($username, 'general');

  my $supplementalDataMappings = $features->get('supplementalDataMappings');
  if ($supplementalDataMappings) {
    foreach my $fieldName (@{$supplementalDataMappings}) {
      my $mappedFieldName = 'x-mapped-' . $fieldName;
      $customData{$mappedFieldName} = $fullTransactionData->{$fieldName};
    }
  }
  
  return \%customData;
}

sub isQueryOperation {
  my $operation = shift;
  return inArray($operation,['query','card-query','batch-prep','batchquery','details']);
}

# control with files in ~pay1/etc/route-query/
# files:
# "legacy" : if this file exists, does not bypass, legacy behavior, existence of file enables bypass
# "<processor>" : if a processor file exists, under normal conditions, it will use legacy behavior. if legacy file exists, it enables bypass
sub bypassSendMServerForQueries {
  my $processor = lc shift;
  $processor =~ s/[^a-z0-9]//;

  my $bypass = 0;
  my $processorFileExists = 0;

  if (-e "/home/pay1/etc/route-query/$processor" ) {
    $processorFileExists = 1;
  }


  if (-e "/home/pay1/etc/route-query/legacy-default" ) {
    $bypass = $processorFileExists;
  } else {
    $bypass = !$processorFileExists;
  }

  return $bypass;
}

# control with files in ~pay1/etc/route-batchcommit/
# files:
# "legacy" : if this file exists, does not bypass, legacy behavior, existence of file enables bypass
# "<processor>" : if a processor file exists, under normal conditions, it will use legacy behavior. if legacy file exists, it enables bypass
sub bypassSendMServerForBatchCommit {
  my $processor = lc shift;
  $processor =~ s/[^a-z0-9]//;

  my $bypass = 0;
  my $processorFileExists = 0;

  if (-e "/home/pay1/etc/route-batchcommit/$processor" ) {
    $processorFileExists = 1;
  }


  if (-e "/home/pay1/etc/route-batchcommit/legacy-default" ) {
    $bypass = $processorFileExists;
  } else {
    $bypass = !$processorFileExists;
  }

  return $bypass;
}

# Get transaction type/operation #
sub getOperationFromTransaction {
  my $self        = shift;
  my $transaction = shift;

  my $operation = 'auth';

  if ( $transaction->getTransactionType eq 'auth' ) {
    if ( $transaction->doPostAuth() ) {
      $operation = 'postauth';
    }
  } elsif ( $transaction->getTransactionType eq 'storedata' ) {
    $operation = 'storedata';
  } else {
    $operation = 'credit';
  }

  return $operation;
}

sub createSendMServerRequest {
  my $processor = shift;
  my $username = shift;
  my $operation = shift;
  my $query = shift;

  my $sendMServerRequest = new PlugNPay::Legacy::SendMServerRequest();
  $sendMServerRequest->setProcessor($processor);
  $sendMServerRequest->setGatewayAccount($username);
  $sendMServerRequest->setOperation($operation);
  $sendMServerRequest->setPairs($query);

  my $toLoad = {};
  # skip loading trans data if it is an auth, batch-commit, or query type (query, card-query, etc)
  # also skip for inquiry/settle, which some older processors call. They effectively do the same thing, at least in paytechtempaiso.pm
  if (!inArray($operation,['auth','batch-commit','inquiry','settle']) && !isQueryOperation($operation)) {
    my $search = {
      version => 'legacy',
      gatewayAccount => $username,
      orderID => $query->{'order-id'},
      operationIn => ['auth','reauth','forceauth','return','postauth']#,
      # status => $status
    };
    $toLoad->{$query->{'order-id'}} = $search;
  }

  my $origOrderId = $query->{'origorderid'};
  if (defined $origOrderId && $origOrderId ne '') {
    $toLoad->{$origOrderId} = {gatewayAccount => $username, orderID => $origOrderId} if !exists $toLoad->{$origOrderId};
  }

  my $prevOrderId = $query->{'prevorderid'};
  if (defined $prevOrderId && $prevOrderId ne '') {
    $toLoad->{$prevOrderId} = {gatewayAccount => $username, orderID => $prevOrderId} if !exists $toLoad->{$prevOrderId};
  }

  my $existingTransactionData = loadExistingTransactionData($toLoad);
  $sendMServerRequest->setExistingTransactionData($existingTransactionData);

  return $sendMServerRequest;
}

sub loadExistingTransactionData {
  my $transactionsToLoad = shift || {};
  my @values = values %{$transactionsToLoad};
  my $loaded = {};

  if (@values > 0) {
    my $loader = new PlugNPay::Transaction::Loader({ loadPaymentData => 1 });
    $loaded = $loader->load(\@values);
  }

  return $loaded;
}

##############################################################################
#                                                                            #
# This function was the first half of the old sendmserver sub from miscutils #
#                                                                            #
#                                  Goodluck...                               #
#                                                                            #
##############################################################################

sub preprocess {
  my $self      = shift;
  my $username  = shift;
  my $operation = shift;
  my $queryRef  = shift;
  my %query     = %{$queryRef};

  #swapping for legacy code functionality
  my $temp1 = $query{'order-id'};
  $query{'order-id'} = $query{'orderID'};
  $query{'orderID'}  = $temp1;
  my $env      = new PlugNPay::Environment();
  my $remoteIP = $env->get('PNP_CLIENT_IP');
  my @pairs    = %query;
  my %result   = ();
  my %result1  = ();
  my (%merchfraud);
  my %feature        = ();
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);

  if ( !defined $query{'card-amount'} ) {
    my ( undef, $actualAmount ) = split( /\s+/, $query{'amount'} );
    $query{'card-amount'} = $actualAmount;
  }

  my $ipcheck;
  my $ipaddress = substr( $remoteIP, 0, 23 );
  if ( -e "/home/p/pay1/outagefiles/pre_ipcheck.txt" ) {
    if ( $ipaddress ne '' ) {
      $ipcheck = &miscutils::precheckip( $gatewayAccount->getGatewayAccountName(), $ipaddress );
    }
  }

  if ( $ipcheck eq "block" ) {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( time() );
    my $now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
    open( DEBUG, ">>/home/p/pay1/database/debug/preIPcheck_debug.txt" );
    print DEBUG "$now, UN:" . $gatewayAccount->getGatewayAccountName() . ", IP:$ipaddress\n";
    close(DEBUG);

    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "The value for the variable publisher-name or merchant being submitted," . $gatewayAccount->getGatewayAccountName() . ", is incorrect.  Check setup email for proper value.";
    return \%result;
  }

  if ( ( $gatewayAccount->getReseller() =~ /^(vermont|vermont2|vermont3)$/ ) && ( $gatewayAccount->canProcessReturns() eq "yes" ) && ( $operation eq "return" ) && ( $query{'card-number'} ne "" ) ) {
    my ( $error, %message );
    $error                = "Mode:$operation\nUN:" . $gatewayAccount->getGatewayAccountName() . "\nIP:$remoteIP\n\nVermont Systems Account\nCredits re-enabled for this account.";
    $message{'riskemail'} = "dprice\@plugnpay.com";
    $message{'creditflg'} = 1;
    $message{'reseller'}  = $gatewayAccount->getReseller();
  }

  if ( $gatewayAccount->getFeatures()->getFeatureString() ne "" ) {
    my @array = split( /\,/, $gatewayAccount->getFeatures()->getFeatureString() );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $feature{$name} = $value;
    }
  }

  if ( $feature{'highflg'} == 1 ) {
    @pairs = ( @pairs, 'highflg', '1' );
    $query{'highflg'} = "1";
  }

  if ( $gatewayAccount->getGatewayAccountName() =~ /(legalint2|kwikwebcom)/ ) {
    $gatewayAccount->setCardProcessor('testprocessor');
  }

  ##  Need to add check of cancelled date to turn off ability to do a return after 30 days.
  if ( ( $gatewayAccount->getStatus() eq "cancelled" ) && ( $operation !~ /^(return)$/ ) ) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "C: " . substr( $gatewayAccount->getStatusReason(), 0, 4 );
    return \%result;
  } elsif ( ( $gatewayAccount->getStatus() eq "hold" ) && ( $operation =~ /^(auth|forceauth|reauth|return)$/ ) ) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "C: " . substr( $gatewayAccount->getStatusReason(), 0, 4 );
    return \%result;
  }

  if ( ( $operation eq "return" ) && ( $feature{'allow_multret'} eq "1" ) ) {
    my ( %amt, %date, $netamt, $trans_date, $operation, $amount, $retamt, $transflagString, $cardnumber );

    my $creditamount = substr( $query{'amount'}, 4 );
    my $dbhdata      = new PlugNPay::DBConnection()->getHandleFor("pnpdata");
    my $sth          = $dbhdata->prepare(
      qq/
        SELECT trans_date,operation,amount,transflags
        FROM trans_log
        WHERE orderid = ?
        AND operation IN ('auth','postauth','return','void')
        AND finalstatus IN ('success','pending')
        AND username = ?
        AND (duplicate IS NULL OR duplicate = ?)
        ORDER BY trans_time
        /
      )
      or die "Can't do: $DBI::errstr";
    $sth->execute( $query{'order-id'}, $gatewayAccount->getGatewayAccountName(), '' ) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %remote::query );

    my $rv = $sth->bind_columns( undef, \( $trans_date, $operation, $amount, $transflagString ) );
    while ( $sth->fetch ) {
      $amt{$operation} = substr( $amount, 4 );
      $date{$operation} = $trans_date;
    }
    $sth->finish();

    if ( ( $operation eq "void" ) && ( $amt{'return'} > 0 ) ) {
      $amt{'return'} = 0;
    }

    my $tflag;
    # create transflag object in case data is stored as hex bitmap string
    $tflag = new PlugNPay::Legacy::Transflags();
    $tflag->fromString($transflagString);
    if ( ( $tflag =~ /capture/ ) || ( $gatewayAccount->getProcessingType() =~ /capture/ ) ) {
      $netamt = $amt{'auth'} - $amt{'return'};
    } else {
      $netamt = $amt{'postauth'} - $amt{'return'};
    }

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( time() );
    my $now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
    open( DEBUG, ">>/home/p/pay1/database/debug/multiplereturns_debug.txt" );
    print DEBUG "$now, UN:" . $gatewayAccount->getGatewayAccountName() . ", OID:$query{'order-id'}, PRIMARYNETAMT:$netamt, NETAMT:$netamt, AMTTOBERETURNED:$amt{'return'}\n";
    close(DEBUG);

    if ( ( $netamt > 0 ) && ( $amt{'return'} > 0 ) ) {
      ## There is still a net charge to card on orderID and the amount of previous returns is  > 0
      my $sth = $dbhdata->prepare(
        qq/
            SELECT card_name,card_addr,card_city,card_state,card_zip,card_country,card_exp,accttype,enccardnumber,length
            FROM trans_log
            WHERE orderid = ?
            AND username = ?
            AND operation IN ('auth','forceauth','return','storedata')
            AND (duplicate IS NULL OR duplicate = ?)
            /
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %remote::query );
      $sth->execute( $query{'order-id'}, $gatewayAccount->getGatewayAccountName(), '' ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %remote::query );
      my $translogRows  = $sth->fetchall_arrayref( {} );
      my $card_name     = $translogRows->[0]{'card_name'};
      my $card_addr     = $translogRows->[0]{'card_addr'};
      my $card_city     = $translogRows->[0]{'card_city'};
      my $card_state    = $translogRows->[0]{'card_state'};
      my $card_zip      = $translogRows->[0]{'card_zip'};
      my $card_country  = $translogRows->[0]{'card_country'};
      my $card_exp      = $translogRows->[0]{'card_exp'};
      my $accttype      = $translogRows->[0]{'accttype'};
      my $enccardnumber = $translogRows->[0]{'enccardnumber'};
      my $length        = $translogRows->[0]{'length'};

      $enccardnumber = &smpsutils::getcardnumber( $gatewayAccount->getGatewayAccountName(), $query{'order-id'}, 'misc_multireturn', $enccardnumber );
      if ( $enccardnumber eq "" ) {
        %result = ( %query, %result );
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} .= "No previous billing information found.";
        $result{'resp-code'} = "PXX";
        return \%result;
      } else {
        $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
      }

      my $cc             = new PlugNPay::CreditCard($cardnumber);
      my $shacardnumber  = $cc->getCardHash();
      my @cardHashes     = $cc->getCardHashArray();
      my $cardHashQmarks = '?' . ',?' x ($#cardHashes);

      my @queryArray = ( $date{'return'}, @cardHashes, $gatewayAccount->getGatewayAccountName(), 'return', 'void', "%lnk$query{'order-id'}%" );

      my ( $db_amt, $amt, $retamt, %amt, $db_op );
      my $sth3 = $dbhdata->prepare(
        qq/
                SELECT amount,operation
                FROM trans_log FORCE INDEX(tlog_tdatesha_idx)
                WHERE trans_date>=?
                AND shacardnumber in ($cardHashQmarks)
                AND username=?
                AND operation IN (?,?)
                AND (duplicate IS NULL OR duplicate='')
                AND acct_code4 LIKE ?
                order by trans_time
            /
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query, 'username', $gatewayAccount->getGatewayAccountName() );
      $sth3->execute(@queryArray) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %query, 'username', $gatewayAccount->getGatewayAccountName() );

      my $amt_rows = $sth3->fetchall_arrayref( {} );
      foreach my $amt_row ( @{$amt_rows} ) {
        my ( $currency, $db_amt ) = split( / /, $amt_row->{'amount'} );
        if ( $amt_row->{'operation'} eq 'void' ) {
          $amt{$currency} -= $db_amt;
          $retamt -= $db_amt;
        } else {
          $amt{$currency} += $db_amt;
          $retamt += $db_amt;
        }
      }

      $retamt       = sprintf( "%.2f", $retamt + .0001 );
      $creditamount = sprintf( "%.2f", $creditamount + .0001 );
      $netamt       = sprintf( "%.2f", $netamt + .0001 );
      my $retPlusCredit = sprintf( "%.2f", $retamt + $creditamount );

      if ( $retPlusCredit <= $netamt ) {
        my ($dummy);
        ## There is still a net charge to card on orderID and the amount of previous returns is  > 0
        ## The amount of the new return plus previous returns is still less or equal to original charge amount so we will allow it.
        ## Need to create new orderID and setup other parameters.
        $query{'lnkreturn'} = $query{'order-id'};
        $query{'acct_code4'} .= ":lnk$query{'order-id'}";
        $query{'order-id'} = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
        ( $query{'card-name'}, $query{'card-address'}, $query{'card-city'}, $query{'card-state'}, $query{'card-zip'}, $query{'card-country'}, $query{'card-exp'}, $query{'accttype'} ) =
        #     v                     v                       v                    v                     v                   v                       v                   v
        ( $card_name,          $card_addr,             $card_city,          $card_state,          $card_zip,          $card_country,          $card_exp,          $accttype );
        $query{'card-number'} = $cardnumber;
        $result1{'orderID'}   = $query{'order-id'};
        $result1{'lnkreturn'} = $query{'lnkreturn'};
      } else {
        ### Log for now,  DCP 20101116
        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( time() );
        my $now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
        open( DEBUG, ">>/home/p/pay1/database/debug/high_multireturn_debug.txt" );
        print DEBUG "$now, UN:" . $gatewayAccount->getGatewayAccountName() . ", OID:$query{'order-id'}, NETAMT:$netamt, RETAMT:$retamt, CREDAMT:$creditamount\n";
        close(DEBUG);

        $result{'FinalStatus'} = "problem";
        $result{'MStatus'}     = "problem";
        $result{'MErrMsg'}     = "Return amount exceeds current net balance.";
        return \%result;
      }

      ### Log for now,  DCP 20101116
      my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( time() );
      my $now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
      open( DEBUG, ">>/home/p/pay1/database/debug/multiplereturns_debug.txt" );
      print DEBUG "$now, UN:"
        . $gatewayAccount->getGatewayAccountName()
        . ", OID:$query{'order-id'}, LNKRETURN:$query{'lnkreturn'}, PRIMARYNETAMT:$netamt, PREVRETSAMT:$retamt, AMTTOBERETURNED:$creditamount\n";
      close(DEBUG);

    }
  }

  my $paymethod = 'credit';

  if ( $query{'accttype'} ) {
    $paymethod = $query{'accttype'} =~ /checkings|savings/ ? 'ach' : $query{'accttype'};
  } elsif ( $query{'paymethod'} ) {
    $paymethod = $query{'paymethod'} =~ /gift|prepaid/ ? 'gift' : $query{'paymethod'};
  }

  my $procMethod = ( $paymethod eq 'gift' ? 'credit' : $paymethod );
  my $procToCheck = $procMethod eq 'credit' ? $gatewayAccount->getCardProcessor() : $gatewayAccount->getProcessorByProcMethod($procMethod);

  if ($operation !~ /query/ && !processorCanBeUsed($procToCheck)) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "Processor not enabled. Operation not allowed.";
    return \%result;
  }

  my $processorPackage = $self->getProcessorPackage( $procToCheck, $procMethod );

  if ( $operation eq "return" ) {
    my ( $oid, $chktransdate, $chkoperation, $chkamt, $returnRows );
    my $dbs = new PlugNPay::DBConnection();

    # new processors are only supported via transaction processor, so that means these checks have already been done.
    # TODO: verify the above statement
    if ( $processorPackage ne 'PlugNPay::Processor::Route' ) {
      my $sth = $dbs->prepare(
        'pnpdata', qq/
           SELECT orderid,trans_date,operation,amount,transflags
           FROM trans_log
           WHERE orderid = ?
           AND operation IN ('auth','postauth')
           AND finalstatus = ?
           AND username = ?
           ORDER BY operation DESC
          /
        )
        or die "Can't prepare: $DBI::errstr";
      $sth->execute( $query{'order-id'}, 'success', $gatewayAccount->getGatewayAccountName() ) or die "Can't execute: $DBI::errstr";
      $returnRows   = $sth->fetchall_arrayref( {} );
      $oid          = $returnRows->[0]{'orderid'};
      $chktransdate = $returnRows->[0]{'trans_date'};
      $chkoperation = $returnRows->[0]{'operation'};
      $chkamt       = $returnRows->[0]{'amount'};
      my $transFlagsString = $returnRows->[0]{'transflags'};
      # create transflags object in case they are stored as a hex bitmap string
      my $transFlags = new PlugNPay::Legacy::Transflags();
      $transFlags->fromString($transFlagsString);

      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 178 ) );
      my $returncutoff = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
      $chkamt = substr( $chkamt, 4 );
      if ( $oid ne "" && $chktransdate < $returncutoff ) {
        $result{'FinalStatus'} = "problem";
        $result{'MStatus'}     = "problem";
        $result{'MErrMsg'}     = "Transaction too old. Operation not allowed.";
        return \%result;
      }

      if ( ( $operation eq "return" ) && ( $gatewayAccount->canProcessReturns() eq "yes" ) && ( $query{'order-id'} !~ /^00/ ) ) {
        if ( $query{'card-number'} ne "" ) {    # && $processorPackage !~ /^PlugNPay::Processor::Route/) {
          $result{'FinalStatus'} = "problem";
          $result{'MStatus'}     = "problem";
          $result{'MErrMsg'}     = "Operation not allowed due to account settings.";

          my ( $error, %message );
          $error                    = "Mode:credit\nUN:" . $gatewayAccount->getGatewayAccountName() . "\nIP:$remoteIP\n\nCredits not permitted for this account. Disabled by merchant.";
          $message{'riskemail'}     = "michelle\@plugnpay.com";
          $message{'creditflg'}     = 1;
          $message{'reseller'}      = $gatewayAccount->getReseller();
          $message{'order-id'}      = $query{'order-id'};
          $message{'amount'}        = $query{'amount'};
          $message{'card-name'}     = $query{'card-name'};
          $message{'card-address1'} = $query{'card-address1'};
          $message{'card-address2'} = $query{'card-address2'};
          $message{'card-city'}     = $query{'card-city'};
          $message{'card-state'}    = $query{'card-city'};
          $message{'card-zip'}      = $query{'card-zip'};

          &miscutils::riskemail( $error, %message );
          return \%result;
        }

        if ( ( ( $gatewayAccount->getProcessingType() eq "authonly" ) && ( $chkoperation ne "postauth" ) )
          || ( ( ( $gatewayAccount->getProcessingType() eq "authcapture" ) || ( $transFlags =~ /capture/ ) ) && ( $chkoperation ne "auth" ) ) ) {
          $result{'FinalStatus'} = "problem";
          $result{'MStatus'}     = "problem";
          $result{'MErrMsg'}     = "Operation not allowed by processing type.";
          return \%result;
        }
      }
    }

    ### Mark all new returns
    if ( ( $operation eq "return" ) && ( $query{'card-number'} ne "" ) ) {
      if ( exists $query{'acct_code4'} ) {
        $query{'acct_code4'} .= ":credit";
      } else {
        $query{'acct_code4'} = "credit";
      }
      @pairs = %query;
    }

    my $submittedAmount = substr( $query{'amount'}, 4 );

    #############################
    # Check for vanilla returns #
    #############################
    # this is to detect returns via pnpremote and other legacy code paths that do not send payment data for returns:
    my $returnCheck_Legacy = $operation eq "return" && !defined $query{'__from_transaction_object__'} && $query{'card-number'} eq '';

    # this is to detect a return that comes in via transaction processor, such as VT or REST because it will always already have a card number loaded
    # the check for origorderid is to differentiate between a credit referencing payment data from another transaction and a standard credit
    # return with origorderid = credit, i.e. "returnprev"
    # return without origorderid = return on existing transaction, confirmed by the existince of a value for $chkamt later
    my $returnCheck_FromTransactionProcessor = $operation eq "return" && $query{'__from_transaction_object__'} && !defined $query{'origorderid'};

    # remove the card number for returns via transaction processor if the processor is perl-based to prevent accidental credits
    # this might not be necessary, but it's being done as a precautionary measure.
    if ($operation eq 'return' && $returnCheck_FromTransactionProcessor && $processorPackage ne 'PlugNPay::Processor::Route') {
      $query{'card-number'} = '';
    }

    # $chkamt is verfied to be non-blank here, proving the existence of a transaction to return against
    # if this is not checked, it evaluates as 0 in the comparison with $sumbittedAmount, and a standard credit via transaction processor would fail here.
    if ( ($returnCheck_Legacy || $returnCheck_FromTransactionProcessor) && defined $chkamt && $chkamt ne '' && $submittedAmount > $chkamt ) {
      if ( $feature{'allow_highreturnsflg'} != 1 ) {
        $result{'FinalStatus'} = "problem";
        $result{'MStatus'}     = "problem";
        $result{'MErrMsg'}     = "Return amount can not be greater than settled amount.";
        return \%result;
      } else {
        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( time() );
        my $now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
        open( DEBUG, ">>/home/p/pay1/database/debug/high_return_debug.txt" );
        print DEBUG "$now, UN:" . $gatewayAccount->getGatewayAccountName() . ", SCRIPT:$ENV{'SCRIPT_NAME'}, OID:$query{'order-id'}, ORIGAMT:$chkamt, AMT:$submittedAmount\n";
        close(DEBUG);
      }
    }
  }

  my $card_type = &miscutils::cardtype( $query{'card-number'} );

  if ( ( ( $feature{'allow_avsonly'} == 1 ) || ( $query{'transflags'} =~ /recinit/ ) ) && ( $query{'card-amount'} == 0.00 ) ) {
    if ( ( $query{'transflags'} !~ /avsonly/ ) ) {
      if ( $query{'transflags'} ne '' ) {
        $query{'transflags'} .= ",avsonly";
      } else {
        $query{'transflags'} = "avsonly";
      }
    }
  }

  if ( $query{'transflags'} =~ /milstar/ ) {
    my $cardnumber = $query{'card-number'};
    $cardnumber =~ s/[^0-9]//g;
    my $cardbin = substr( $cardnumber, 0, 6 );

    if ( $cardbin =~ /^(60194|60191)/ ) {    ## Milstar Range
      $card_type = "MS";
      $gatewayAccount->setCardProcessor("milstar");
    }
  } elsif ( $query{'transflags'} =~ /zipmark/ ) {
    $gatewayAccount->setCardProcessor("milstar");
  }

  if ( $gatewayAccount->getGatewayAccountName() eq '' ) {
    $result{'FinalStatus'} = 'problem';
    $result{'MStatus'}     = 'problem';
    $result{'MErrMsg'}     = "The value for the variable publisher-name or merchant being submitted, " . $gatewayAccount->getGatewayAccountName() . ", is incorrect.  Check setup email for proper value.";
    my $ipaddress = substr( $remoteIP, 0, 23 );
    &miscutils::checkip( $gatewayAccount->getGatewayAccountName(), $ipaddress );
    return \%result;
  }

  if ( $query{'card-number'} eq "" && defined $query{'pnp_token'} ) {
    my $token = new PlugNPay::Token();
    $query{'card-number'} = $token->fromToken( $query{'pnp_token'} );
  }

  #swapping for new code consistency
  my $temp = $query{'order-id'};
  $query{'order-id'} = $query{'orderID'};
  $query{'orderID'}  = $temp;
  @pairs             = %query;

  my $dataToReturnToRoute = {
    'query'           => \%query,
    'pairs'           => \@pairs,
    'cardProcessor'   => $gatewayAccount->getCardProcessor(),
    'walletProcessor' => $gatewayAccount->getWalletProcessor(),
    'achProcessor'    => $gatewayAccount->getACHProcessor(),
    'operation'       => $operation,
    'username'        => $gatewayAccount->getGatewayAccountName(),
    'feature'         => \%feature,
    'custstatus'      => $gatewayAccount->getStatus(),
    'limits'          => $gatewayAccount->getLimits(),
    'result'          => \%result,
    'result1'         => \%result1,
    'paymethod'       => $paymethod,
    'emvProcessor'    => $gatewayAccount->getEmvProcessor()
  };

  return $dataToReturnToRoute;
}

sub debugLog {
  my $self         = shift;
  my $originalData = shift;
  my %data         = %{$originalData};                                                          #Do not want to alter original data
  my $dataLog      = new PlugNPay::Logging::DataLog( { 'collection' => 'route_debug_log' } );

  if ( $data{'card-number'} || $data{'magstripe'} ) {
    my $info = $data{'card-number'} || $data{'magstripe'};
    my $card = new PlugNPay::CreditCard($info);

    $data{'card-number'}   = '';
    $data{'card-cvv'}      = '';
    $data{'magstripe'}     = '';
    $data{'masked-number'} = $card->getMaskedNumber();
  } elsif ( $data{'accountnum'} ) {
    my $ach = new PlugNPay::OnlineCheck();
    $ach->setAccountNumber( $data{'accountnum'} );
    $ach->setABARoutingNumber( $data{'routingnum'} );
    $data{'accountnum'}  = '';
    $data{'routingnum'}  = '';
    $data{'masked-data'} = $ach->getMaskedNumber();
  }

  $dataLog->log( { 'transaction' => \%data } );
}

sub processorCanBeUsed {
  my $processor = shift;

  # check for invalid characters in processor name
  if ($processor =~ /[^a-z0-9-_]/) {
    die("Invalid characters in processor name");
  }

  my $containerDirectory = '/home/pay1/etc/container-processors';

  # if the container-processor directory does not exist, allow all processors
  if ( ! -d $containerDirectory ) {
    return 1;
  }

  # return truthy if a file exists in the container directory with the processor name
  if ( -e "$containerDirectory/$processor" ) {
    return 1;
  }

  # processor is not allowed to be used in a container
  return 0;
}

1;