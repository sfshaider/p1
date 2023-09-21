package PlugNPay::Processor::Process;

use strict;
use JSON::XS;
use Time::HiRes qw();
use MIME::Base64;
use PlugNPay::Order;
use PlugNPay::Util::UniqueID;
use PlugNPay::Transaction::Updater;
use PlugNPay::Transaction::Saver;
use PlugNPay::Transaction::Formatter;
use PlugNPay::Processor::SocketConnector;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Processor::Process::MessageBuilder;
use PlugNPay::Processor::ID;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  # Set transaction operation: 'auth' or 'postauth' or  'credit' or ... #
  my $operation = shift;
  $self->setOperation($operation);


  # This allows us to pass options, currently only used for Asynchronous flag setting #
  my $options = shift;
  if (defined $options && ref($options) eq 'HASH') {
    $self->{'options'} = $options;
  }

  return $self;
}

sub runAsync { #This means we will not get response data from server automatically
  my $self = shift;
  $self->{'options'}{'async'} = 1;
}

sub runSync { #This means after transaction is sent then we try to get the Processor response data immediately
  my $self = shift;
  $self->{'options'}{'async'} = 0;
}

sub setOperation {
  my $self = shift;
  my $operation = shift;
  $self->{'operation'} = $operation;
}

sub getOperation {
  my $self = shift;
  return $self->{'operation'};
}

# Wrapper for both parts of transactions #
sub processTransaction {
  my $self = shift;
  my $transaction = shift;
  my $options = shift;
  my $context = $options->{'context'};
  my %transactionIdOrderIdMap;
  my $pnpOrderID = $transaction->getPNPOrderID();
  $pnpOrderID = PlugNPay::Util::UniqueID::fromBinaryToHex($pnpOrderID);

  my $transactions;
  my @arr = ();
  if ($transaction->getTransactionMode() eq 'mark' || $transaction->getTransactionMode() eq 'postauth' ) { # mark does not go to processor, just gets a db update
    my $saver = new PlugNPay::Transaction::Saver();
    $saver->save($pnpOrderID,[$transaction]);
    my $pnpTransactionId = $transaction->getPNPTransactionID();
    $pnpTransactionId = PlugNPay::Util::UniqueID::fromBinaryToHex($pnpTransactionId);

    # push @arr,$pnpTransactionId;
  } else {
    my $pendingData = $self->dispatchTransaction($transaction);

    if (defined $self->{'options'}{'async'} && $self->{'options'}{'async'} == 1) {
      return $self->makeAsyncResponse($pendingData);
    }

    if (ref($pendingData) eq 'ARRAY' && @{$pendingData} > 0) {
      foreach my $pendingTrans (@{$pendingData}) {
        # get the transaction id
        my $pnpTransactionID = $pendingTrans->{'pnp_transaction_id'};
        $pnpTransactionID = PlugNPay::Util::UniqueID::fromBinaryToHex($pnpTransactionID);

        # save the order id for the transaction (as hex)
        $transactionIdOrderIdMap{$pnpTransactionID} = $pnpOrderID;
        push @arr,$pendingTrans->{'pnp_transaction_id'};
      }
    } elsif (ref($pendingData) eq 'HASH' && defined $pendingData->{'pnp_transaction_id'}) {
      # get the transaction id
      my $pnpTransactionID = $pendingData->{'pnp_transaction_id'};
      $pnpTransactionID = PlugNPay::Util::UniqueID::fromBinaryToHex($pnpTransactionID);

      # save the order id for the transaction (as hex)
      $transactionIdOrderIdMap{$pnpTransactionID} = $pnpOrderID;
      push @arr,$pendingData->{'pnp_transaction_id'};
    } else {
      # All transactions failed to connect to processor!
      return {};
    }
  }
  $transactions = $self->getProcessedTransactions(\@arr);#, { currentTransactionData => $transaction });
  # hackety hack hack hack!  I am not proud of this.
  # For sync this works...for async the transaction will have to be loaded from the db in order
  # to get the order id.
  # at this point order id and transaction id are hex
  foreach my $processorId (keys %{$transactions}) {
    foreach my $pnpTransactionID (keys %{$transactions->{$processorId}}) {
      $transactions->{$processorId}{$pnpTransactionID}{'pnp_order_id'} = $transactionIdOrderIdMap{$pnpTransactionID};
    }
  }
  return $transactions;
}

sub makeAsyncResponse {
  my $self = shift;
  my $pendingData = shift;
  my $pendingResponse = {};
  my $uuid = new PlugNPay::Util::UniqueID();
  foreach my $trans (@{$pendingData}) {
    $uuid->fromBinary($trans->{'pnp_transaction_id'});

    my $tempResponse = {
                        'FinalStatus'          => 'pending',
                        'MStatus'              => 'pending',
                        'pnp_transaction_id'   => $uuid->inHex(),
                        'transaction_state_id' => $trans->{'transaction_state_id'}
    };

    $pendingResponse->{$uuid->inHex()} = $tempResponse;
  }

  return {'pending' => $pendingResponse};
}

# First part of transaction: Send data to processor #
sub dispatchTransaction {
  my $self = shift;
  my $transaction = shift;
  my $updater = new PlugNPay::Transaction::Updater();
  my $formatter = new PlugNPay::Transaction::Formatter();
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();

  my $order;
  if (ref($transaction) =~ /^PlugNPay::Order/) {
    $order = $transaction;
  } elsif (ref($transaction) =~ /^PlugNPay::Transaction/) {
    ########################################################
    # If Transaction Obj: make array of single transaction #
    # This is due to request format on the JAVA code side  #
    ########################################################
    $order = new PlugNPay::Order();
    $order->setMerchantID(new PlugNPay::GatewayAccount::InternalID()->getMerchantID($transaction->getGatewayAccount()));
    my $merchantOrderID = $transaction->getOrderID();

    if (defined $merchantOrderID && $merchantOrderID ne '') {
      $order->setMerchantOrderID($merchantOrderID);
    } else {
      $order->setMerchantOrderID($order->generateMerchantOrderID());
    }

    my $pnpOrderID = $transaction->getPNPOrderID();
    if (defined $pnpOrderID && $pnpOrderID ne '') {
      $order->setPNPOrderID($pnpOrderID);
    } else {
      $transaction->setPNPOrderID($order->getPNPOrderID());
    }

    $order->setOrderClassifier($transaction->getMerchantClassifierID());
    $order->addOrderTransaction($transaction);
  }

  if (!defined $order) {
    return {'MStatus' => 'Bad Transaction Format', 'FinalStatus' => 'Failure'};
  }

  ########################################
  # If order obj: Send transaction array #
  # The function will then return array  #
  # reference of pending transaction IDs #
  ########################################
  my $saveStatus;
  if ($order->exists($order->getPNPOrderID())) {
    $order->loadOrderIDs($order->getPNPOrderID());
    $saveStatus = $order->update($self->getOperation());
  } else {
    $saveStatus = $order->save($self->getOperation());
  }

  if ($saveStatus) {
    my $lvl3 = $formatter->prepareLevel3($order->getOrderDetails());
    my $processors = {};
    foreach my $trans (@{$order->getOrderTransactions()}) {
      my $info = $formatter->prepareTransaction($trans,$self->getOperation());
      $info->{'transactionData'}{'level3data'} = $lvl3;

      if (!defined $processors->{$trans->getProcessor()}) {
        my $hash = {};
        $hash->{$info->{'requestID'}} = $info;
        $processors->{$trans->getProcessor()} = $hash;
      } else {
        $processors->{$trans->getProcessor()}{$info->{'requestID'}} = $info;
      }
    }
    my @responseData = ();
    foreach my $processor (keys %{$processors}) {
      my $JSON = JSON::XS->new->utf8->encode($messageBuilder->build($processors->{$processor}));
      my $responses = '{}';
      eval {
        my $connector = new PlugNPay::Processor::SocketConnector();
        $responses = $connector->connectToProcessor($JSON,$processor);
      };

      if ($@) {
        $updater->failPendingTransactions($processors->{$processor},$@);
      } else {
        my $data = JSON::XS->new->utf8->decode($responses);
        push @responseData,@{$updater->updatePendingTransactions($data->{'responses'})}; #Perl magic!
      }
    }

    return \@responseData;
  } else {
    return {'MStatus' => 'failure', 'FinalStatus' => 'failure', 'MErrMsg' => 'Transaction save failure, will not dispatch'};
  }
}

sub decodePendingTransaction {
  my $self = shift;
  my $data = shift;
  my $idFormatter = new PlugNPay::Util::UniqueID();
  my $transactionID = $data->{'pnp_transaction_id'};
  if ($data->{'pnp_transaction_id'} =~ /^[a-fA-F0-9]+$/) {
    $idFormatter->fromHex($data->{'pnp_transaction_id'});
    $transactionID = $idFormatter->inBinary();
  }

  my $respData = {
                   'pnp_transaction_id' => $transactionID,
                   'transaction_state_id' => $data->{'transaction_state_id'},
                   'average_transaction_time' => $data->{'average_transaction_time'}
                 };

  return $respData;
}

####################################
# Second part of trans processing  #
# Retrieves transaction responses  #
####################################
sub getProcessedTransactions {
  my $self = shift;
  my $ids = shift;
  my $options = shift || {};
  if (ref($ids) ne 'ARRAY') {
    $ids = [$ids];
  }

  my $fromProcessor = $self->getProcessedFromJava($ids, $options);

  my @successfulKeys = ();
  my $missingKeys = [];
  my $uuid = new PlugNPay::Util::UniqueID();
  my $stateObj = new PlugNPay::Transaction::State();
  foreach my $procId (keys %{$fromProcessor}) {
    my @transKeys = keys %{$fromProcessor->{$procId}};
    push @successfulKeys, @transKeys;
  }

  foreach my $id (@{$ids}) {
    if ($id =~ /^[a-fA-F0-9]+$/) {
      $uuid->fromHex($id);
    } else {
      $uuid->fromBinary($id);
    }

    if (!grep($uuid->inHex(), @successfulKeys) && !grep($uuid->inBinary(), @successfulKeys)) {
      push @{$missingKeys}, $id;
    }
  }

  # load order ids from database if they do not exist in the response.
  my $fromDatabase = $self->getProcessedFromDatabase($missingKeys);

  my %results = (%{$fromProcessor},%{$fromDatabase});
  #TODO: Add third part, a hook to java to request data again (from proc)

  return \%results;
}

# singular, accepts a context as an option so another query doesn't have to be made
sub getProcessedTransaction {
  my $self = shift;
  my $id = shift;
  my $options = shift || {};
  my $currentTransactionData = $options->{'currentTransactionData'};

  my $fromProcessor = $self->getProcessedFromJava($id, { currentTransactionData => $currentTransactionData });
  foreach my $processorId (keys %{$fromProcessor}) {
    if ($fromProcessor->{$processorId}{$id}) {
      return $fromProcessor;
    }
  }

  return $self->getProcessedFromDatabase($id);
}

sub getProcessedFromJava {
  my $self = shift;
  my $ids = shift;
  my $options = shift;
  my $currentTransactionData = $options->{'currentTransactionData'};

  my $info;

  eval {
    if (length(@{$ids}) == 1 && $currentTransactionData) {
      my $procIDObj = new PlugNPay::Processor::ID();
      my $processorId = $currentTransactionData->getProcessorID();
      my $processor = $procIDObj->getProcessorName($processorId);
      my $transactionId = $currentTransactionData->getPNPTransactionID();
      my $hexTransactionId = PlugNPay::Util::UniqueID::fromBinaryToHex($transactionId);

      $info = {
        $processorId => {
          $hexTransactionId => {
            'transactionData' => {
                     'pnp_transaction_id' => $hexTransactionId,
                     'processor_id' => $processorId
            },
            'type' => 'redeem',
            'processor' => $processor,
            'requestID' => $hexTransactionId,
            'priority' => '6'
          }
        }
      };
    }
  };
  # TODO handle eval error

  # if no context was passed or there are multiple transactions being requested
  if (!$info) {
    @{$ids} = map { PlugNPay::Util::UniqueID::fromHexToBinary($_) } @{$ids};
    $info = $self->_loadPendingInfo($ids); #Load pending ID and pnpID and vehicle
  }

  my $transactions = $self->_retrieveTransactions($info); #connect to server, get transactions in hash, then cleanup

  return $transactions;
}

sub _loadPendingInfo {
  my $self = shift;
  my $ids = shift;
  my $loader = new PlugNPay::Transaction::Loader();
  my $data;

  if (ref($ids) ne 'ARRAY') {
    $ids = [$ids];
  }
  return $loader->loadPendingTransactionProcessor($ids);
}

sub _retrieveTransactions {
  my $self = shift;
  my $loadedInformation = shift;
  my $options = shift;
  my $transactions = {};

  eval{
    my $updater = new PlugNPay::Transaction::Updater();
    my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();

    foreach my $processorID (keys %{$loadedInformation}) {
      my $data = $loadedInformation->{$processorID};
      my $JSON = encode_json($messageBuilder->build($data));
      my $connector = new PlugNPay::Processor::SocketConnector();
      my $responses = $connector->connectToProcessor($JSON,$processorID);
      my $responseData = decode_json($responses);
      $transactions->{$processorID} = $self->getCompletedTransactions($responseData->{'responses'},$processorID); #Iterate through array, make sure all transactions finish or time out.
      my $errors = $updater->finalizeTransactions($transactions->{$processorID});
      my $cleanup = !$options->{'noCleanup'};
      if ($cleanup) { # ugh
        $self->cleanupTransactions($processorID,$transactions->{$processorID},$errors);
      }
    }
  };
  # TODO handle eval error

  return $transactions;
}

sub getCompletedTransactions {
  my $self = shift;
  my $transactionHash = shift;
  my $processorID = shift;
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();

  my $completedTransactions = {};
  my $pendingTransactions = {};
  my $formatter = new PlugNPay::Transaction::Formatter();
  foreach my $transID (keys %{$transactionHash}) {
    my $transaction = $transactionHash->{$transID};
    if ($transaction->{'transaction_status'} eq 'pending') {
      $pendingTransactions->{$transaction->{'pnp_transaction_id'}} = $messageBuilder->requestContent($transaction,$processorID);
    } else {
      $completedTransactions->{$transaction->{'pnp_transaction_id'}} = $formatter->processResponse($transaction);
    }
  }

  my $sleepTime = 0.1;
  my $connector = new PlugNPay::Processor::SocketConnector();
  while (keys(%{$pendingTransactions}) > 0 && $sleepTime < 10){
    Time::HiRes::sleep($sleepTime);
    my $JSON = encode_json($messageBuilder->build($pendingTransactions));
    my $responses = $connector->connectToProcessor($JSON,$processorID);
    my $responseDataHash = decode_json($responses);
    my $responseData = $responseDataHash->{'responses'};

    my $tempHash = {};
    foreach my $transactionID (keys %{$responseData}) {
      my $transaction = $responseData->{$transactionID};
      if (ref($transaction) ne 'HASH') {
        $transaction = decode_json($transaction);
      }

      if ($transaction->{'transaction_status'} eq 'pending') {
        $tempHash->{$transactionID} = $messageBuilder->requestContent($transaction,$processorID,'5','redeem');
      } else {
        $completedTransactions->{$transaction->{'pnp_transaction_id'}} = $formatter->processResponse($transaction);;
      }
    }
    $pendingTransactions = $tempHash;
    $sleepTime *= 2;
   }

  return $completedTransactions;
}

sub getProcessedFromDatabase {
  my $self = shift;
  my $ids = shift;
  unless (ref($ids) eq 'ARRAY' && @{$ids} > 0) {
    return {};
  }

  my $loaded = {};
  eval {
    my $loader = new PlugNPay::Transaction::Loader();
    my $idMachine = new PlugNPay::Processor::ID();
    my $formatter = new PlugNPay::Transaction::Formatter();
    my @dataArray = map{ {'pnp_transaction_id' => $_} } @{$ids};
    my $fromDB = $loader->unifiedLoad(\@dataArray);
    foreach my $merchant (keys %{$fromDB}) {
      foreach my $transactionID (keys %{$fromDB->{$merchant}}) {
        my $procID = $idMachine->getProcessorID($fromDB->{$merchant}{$transactionID}{'processor'});
        my $transResponse = $formatter->formatLoadedAsResponse($fromDB->{$merchant}{$transactionID});
        $transResponse->{'_via_'} = 'db';
        $loaded->{$procID}{$transactionID} = $transResponse;
      }
    }
  };

  if ($@) {
    my $logger = new PlugNPay::DataLog({'collection' => 'transaction_process'});
    $logger->log({'error' => $@, 'message' => 'An error occured while in loadFromDatabase', 'transactionIDs' => $ids});
  }

  return $loaded;
}

# This is the final part, tells Processor Server to remove #
# Response data from the storage hash. This is called if   #
# and only if we successfully retrieved the response info  #
sub cleanupTransactions {
  my $self = shift;
  my $processorID = shift;
  my $data = shift;
  my $error = shift;
  my $uuidFormat = new PlugNPay::Util::UniqueID();
  my $messageBuilder = new PlugNPay::Processor::Process::MessageBuilder();

  my $json = JSON::XS->new->utf8->encode($messageBuilder->buildRemoveMessage($data,$processorID,$error));
  my $connector = new PlugNPay::Processor::SocketConnector();
  my $responses = $connector->connectToProcessor($json,$processorID);
  my $respHash = JSON::XS->new->utf8->decode($responses);

  return $respHash->{'responses'};
}

1;
