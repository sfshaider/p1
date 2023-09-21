package PlugNPay::Order::Report;

use strict;
use JSON::XS;
use PlugNPay::CardData;
use PlugNPay::Merchant;
use PlugNPay::CreditCard;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Util::UniqueID;
use PlugNPay::AWS::S3::Object;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::JSON;
use PlugNPay::Transaction::Loader;
use PlugNPay::Order::Report::Status;

our $cachedBucket;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $merchant = shift;
  if ($merchant) {
    $self->setMerchantID($merchant);
  }

  return $self;
}

sub setMerchantID {
  my $self = shift;
  my $merchant = shift;

  if ($merchant !~ /^[0-9]+$/) {
    $merchant = new PlugNPay::Merchant($merchant)->getMerchantID();
  }

  $self->{'merchantID'} = $merchant;
}

sub setOrderRequestID {
  my $self = shift;
  my $orderRequestID = shift;
  $self->{'orderRequestID'} = $orderRequestID;
}

sub getOrderRequestID {
  my $self = shift;
  return $self->{'orderRequestID'};
}

sub setCreationDate {
  my $self = shift;
  my $creationDate = shift;
  $self->{'creationDate'} = $creationDate;
}

sub getCreationDate {
  my $self = shift;
  return $self->{'creationDate'};
}

sub setQueryData {
  my $self = shift;
  my $query = shift;
  $self->{'query'} = $query;
}

sub getQueryData {
  my $self = shift;
  return $self->{'query'};
}

sub setStatusID {
  my $self = shift;
  my $statusID = shift;
  $self->{'statusID'} = $statusID;
}

sub getStatusID {
  my $self = shift;
  return $self->{'statusID'};
}

sub setBatchID {
  my $self = shift;
  my $batchID = shift;
  $self->{'batchID'} = $batchID;
}

sub getBatchID {
  my $self = shift;
  return $self->{'batchID'};
}

sub setS3Link {
  my $self = shift;
  my $s3Link = shift;
  $self->{'s3Link'} = $s3Link;
}

sub getS3Link {
  my $self = shift;
  return $self->{'s3Link'};
}

sub setRequestTokens {
  my $self = shift;
  my $requestTokens = shift;
  $self->{'requestTokens'} = $requestTokens;
}

sub getRequestTokens {
  my $self = shift;
  return $self->{'requestTokens'};
}

# subroutines to check status
sub isPending {
  my $self = shift;
  my $batchID = shift || $self->{'batchID'};
  return $self->_batchStatus($batchID, 'PENDING');
}

sub isProcessing {
  my $self = shift;
  my $batchID = shift || $self->{'batchID'};
  return $self->_batchStatus($batchID, 'PROCESSING');
}

sub isComplete {
  my $self = shift;
  my $batchID = shift || $self->{'batchID'};
  return $self->_batchStatus($batchID, 'COMPLETED');
}

sub isProblem {
  my $self = shift;
  my $batchID = shift || $self->{'batchID'};
  return $self->_batchStatus($batchID, 'PROBLEM');
}

sub loadOrderBatch {
  my $self = shift;
  my $batchID = uc shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/SELECT id,
                                              merchant_id,
                                              query,
                                              status_id,
                                              creation_date,
                                              batch_id,
                                              s3_link
                                       FROM orders_s3
                                       WHERE UPPER(batch_id) = ?/);
  $sth->execute($batchID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  if (@{$rows} > 0) {
    $self->_setOrderRequestData($rows->[0]);
  }
}

sub _setOrderRequestData {
  my $self = shift;
  my $row = shift;

  $self->{'orderRequestID'} = $row->{'id'};
  $self->{'merchantID'}     = $row->{'merchant_id'};
  $self->{'statusID'}       = $row->{'status_id'};
  $self->{'creationDate'}   = $row->{'creation_date'};
  $self->{'batchID'}        = $row->{'batch_id'};
  $self->{'s3Link'}         = $row->{'s3_link'};
  eval {
    $self->{'query'} = decode_json($row->{'query'});
  };

  $self->{'query'} = {} if $@;
  $self->{'requestTokens'} = $self->{'query'}{'requestTokens'};
}

sub saveOrderRequest {
  my $self = shift;
  my $orderDetails = shift;

  my $status = new PlugNPay::Util::Status();
  eval {
    # set status to pending
    my $orderStatus = new PlugNPay::Order::Report::Status();
    my $pendingStatusID = $orderStatus->loadStatusID('PENDING');

    # create a batch ID
    my $util = new PlugNPay::Util::UniqueID();
    my $batchID = uc $util->inHex();

    if (!$orderDetails->{'query'}{'gatewayAccount'}) {
      $orderDetails->{'query'}{'gatewayAccount'} = new PlugNPay::Merchant($self->{'merchantID'})->getMerchantUsername();
    }

    my $json;
    eval {
      $json = encode_json($orderDetails->{'query'});
    };

    $json = '{}' if $@;

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc', q/INSERT INTO orders_s3
                                         ( merchant_id,
                                           query,
                                           creation_date,
                                           status_id,
                                           batch_id )
                                       VALUES (?,?,?,?,?)/);
    $sth->execute($self->{'merchantID'},
                  $json, 
                  new PlugNPay::Sys::Time()->nowInFormat('iso'),
                  $pendingStatusID,
                  $batchID) or die $DBI::errstr;
    $self->setBatchID($batchID);
    $status->setTrue();
  };

  if ($@) {
    my $dataLog = new PlugNPay::Logging::DataLog({ 'collection' => 'orders_s3' });
    $dataLog->log({
      'function'   => 'saveOrderRequest',
      'error'      => $@,
      'merchantID' => $self->{'merchantID'}
    });

    $status->setFalse();
    $status->setError('Failed to save orders request.');
  }

  return $status;
}

sub deleteOrderRequest {
  my $self = shift;
  my $batchID = uc shift;
  my $merchantID = shift || $self->{'merchantID'};

  my $dbs = new PlugNPay::DBConnection();

  my $status = new PlugNPay::Util::Status();
  eval {
    my $sth = $dbs->prepare('pnpmisc', q/DELETE FROM orders_s3
                                         WHERE UPPER(batch_id) = ?
                                         AND merchant_id = ?/);
    $sth->execute($batchID,
                  $merchantID) or die $DBI::errstr;
    $status->setTrue();
  };

  if ($@) {
    my $dataLog = new PlugNPay::Logging::DataLog({ 'collection' => 'orders_s3' });
    $dataLog->log({
      'function'   => 'deleteOrderRequest',
      'error'      => $@,
      'merchantID' => $self->{'merchantID'}
    });

    $status->setFalse();
    $status->setError('Failed to delete orders request.');
  }

  return $status;
}

sub deleteProcessedOrderRequests {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();

  my $orderStatus = new PlugNPay::Order::Report::Status();
  my $completedStatusID = $orderStatus->loadStatusID('COMPLETED');
  my $problemStatusID   = $orderStatus->loadStatusID('PROBLEM');

  my $sth = $dbs->prepare('pnpmisc', q/SELECT id,
                                              creation_date
                                       FROM orders_s3
                                       WHERE status_id = ?
                                       OR status_id = ?/);
  $sth->execute($completedStatusID,
                $problemStatusID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  if (@{$rows} > 0) {
    my $today = new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd');
    foreach my $row (@{$rows}) {
      my $dateCreated = new PlugNPay::Sys::Time()->inFormatDetectType('yyyymmdd', $row->{'creation_date'});
      my $expireDate = new PlugNPay::Sys::Time('yyyymmdd', $dateCreated);
      $expireDate->addDays(2);
      if ($today >= $expireDate->inFormat('yyyymmdd')) {
        $self->_deleteProcessedOrder($row->{'id'});
      }
    }
  }
}

sub _deleteProcessedOrder {
  my $self = shift;
  my $orderRequestID = shift;

  my $dbs = new PlugNPay::DBConnection();
  eval {
    my $sth = $dbs->prepare('pnpmisc', q/DELETE FROM orders_s3
                                         WHERE id = ?/);
    $sth->execute($orderRequestID) or die $DBI::errstr;
  };

  if ($@) {
    my $dataLog = new PlugNPay::Logging::DataLog({ 'collection' => 'orders_s3' });
    $dataLog->log({
      'function'   => '_deleteProcessedOrder',
      'error'      => $@
    });
  }
}

sub batchIDExists {
  my $self = shift;
  my $batchID = uc shift;
  my $merchantID = shift || $self->{'merchantID'};

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/SELECT COUNT(*) as `exists`
                                       FROM orders_s3
                                       WHERE UPPER(batch_id) = ?
                                       AND merchant_id = ?/);
  $sth->execute($batchID,
                $merchantID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  return $rows->[0]{'exists'};
}

# this subroutine will be called by background process #
sub processBatches {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $orderStatus = new PlugNPay::Order::Report::Status();

  my @requests;
  eval {
    $dbs->begin('pnpmisc');
    my $statusID = $orderStatus->loadStatusID('PENDING');

    # grab the pending IDs in the table
    my $sth = $dbs->prepare('pnpmisc', q/SELECT id,
                                                merchant_id,
                                                query,
                                                batch_id
                                         FROM orders_s3
                                         WHERE status_id = ?
                                         LIMIT 30
                                         FOR UPDATE/);
    $sth->execute($statusID) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    if (@{$rows} > 0) {
      # if there are pending rows
      # change them to processing
      my @batchIDs = ();
      my @placeHolders = ();
      foreach my $row (@{$rows}) {
        push (@batchIDs, $row->{'batch_id'});
        push (@placeHolders, '?');

        # push object to be used for processing
        my $request = new PlugNPay::Order::Report();
        $request->_setOrderRequestData($row);
        push (@requests, $request);
      }

      my $processingStatusID = $orderStatus->loadStatusID('PROCESSING');
      my $processingSth = $dbs->prepare('pnpmisc', q/UPDATE orders_s3
                                                     SET status_id = ?
                                                     WHERE batch_id IN (/ . join(',', @placeHolders) . q/)/);
      $processingSth->execute($processingStatusID,
                              @batchIDs) or die $DBI::errstr;
      $dbs->commit('pnpmisc');
    }
  };

  if ($@) {
    $dbs->rollback('pnpmisc');
    my $dataLog = new PlugNPay::Logging::DataLog({ 'collection' => 'orders_s3' });
    $dataLog->log({
      'function'   => 'processBatches',
      'error'      => $@,
      'merchantID' => $self->{'merchantID'}
    });
  }

  # if we're here, we can begin loading orders =^.^=
  if (@requests > 0 && !$@) {
    # if there are batches to process
    my $completedStatusID = $orderStatus->loadStatusID('COMPLETED');
    my $problemStatusID   = $orderStatus->loadStatusID('PROBLEM');

    foreach my $request (@requests) {
      my $batchID = $request->{'batchID'};
     
      eval {
        my $orderResults = $request->_loadOrdersForBatch();
        my $merchant = $orderResults->{'merchant'};
        my $transactions = $orderResults->{'transactions'};

        my $convertedTrans = [];
        my $converter = new PlugNPay::Transaction::JSON();
        foreach my $transID (keys %{$transactions}) {
          # transaction object contains card info
          my $transactionObj = $transactions->{$transID};

          # convert trans obj to hash
          my $transaction = $converter->transactionToJSON($transactions->{$transID});

          # if payment is card
          if (exists $transaction->{'payment'}{'card'}) {
            my $creditCard = $transactionObj->getCreditCard();
            $transaction->{'payment'}{'card'}{'type'}  = uc $creditCard->getType();
            $transaction->{'payment'}{'card'}{'brand'} = $creditCard->getBrandName();

            if (!$request->{'requestTokens'}) {
              delete $transaction->{'payment'}{'card'}{'token'};
            }
          }

          push (@{$convertedTrans}, $transaction);
        }

        my $objectName = $merchant . '-' . $batchID . '.json';

        my $s3 = new PlugNPay::AWS::S3::Object(getOrdersReportingBucket());
        $s3->setObjectName($objectName);
        $s3->setContentType('json');
        $s3->setContent({ 'transactions' => $convertedTrans });
        my $response = $s3->createObject();
        if (!$response) {
          # failed to put object
          die "Failed to put object in S3\n";
        } else {
          # create the presigned url
          $s3->setExpireTime(6);
          my $signedURL = $s3->getPresignedURL();
          if (!$signedURL) {
            # failed to create signed url
            die "Failed to create signed url for S3 object\n";
          } else {
            # successfully got signed url, save it to orders_s3 table
            my $updateSTH = $dbs->prepare('pnpmisc', q/UPDATE orders_s3
                                                       SET s3_link = ?,
                                                           status_id = ?
                                                       WHERE id = ?/);
            $updateSTH->execute($signedURL,
                                $completedStatusID,
                                $request->{'orderRequestID'}) or die $DBI::errstr;
          }
        }
      };

      if ($@) {
        print STDERR $@ . "\n";
        my $dataLog = new PlugNPay::Logging::DataLog({ 'collection' => 'orders_s3' });
        $dataLog->log({
          'function'   => 'processBatches',
          'error'      => $@,
          'merchantID' => $request->{'merchantID'}
        });

        my $updateSTH = $dbs->prepare('pnpmisc', q/UPDATE orders_s3
                                                   SET status_id = ?
                                                   WHERE id = ?/);
        $updateSTH->execute($problemStatusID,
                            $request->{'orderRequestID'}) or die $DBI::errstr;
      }
    }
  }
}

sub _loadOrdersForBatch {
  my $self = shift;
  my $merchant = new PlugNPay::Merchant($self->{'merchantID'})->getMerchantUsername();

  my $transactionLoader = new PlugNPay::Transaction::Loader({ 'loadPaymentData' => 1 });
  return {
    'transactions' => $transactionLoader->load($self->{'query'})->{$merchant},
    'merchant'     => $merchant
  };
}

sub _batchStatus {
  my $self = shift;
  my $batchID = uc shift;
  my $status = uc shift;

  my $orderStatus = new PlugNPay::Order::Report::Status();
  my $statusID = $orderStatus->loadStatusID($status);

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/SELECT COUNT(*) as `status`
                                       FROM orders_s3
                                       WHERE UPPER(batch_id) = ?
                                       AND status_id = ?/);
  $sth->execute($batchID,
                $statusID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  return $rows->[0]{'status'};
}

sub getOrdersReportingBucket {
  if (!defined $cachedBucket || $cachedBucket eq '') {
    my $env = $ENV{'PNP_ORDERS_BUCKET'};
    $cachedBucket = $env || PlugNPay::AWS::ParameterStore::getParameter('/S3/BUCKET/ORDERS_REPORTING',1);
  }

  die('Failed to load bucket for orders reporting') if $cachedBucket eq '';
  
  return $cachedBucket;
}

1;
