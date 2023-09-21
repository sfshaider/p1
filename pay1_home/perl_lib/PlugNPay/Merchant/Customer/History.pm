package PlugNPay::Merchant::Customer::History;

use strict;
use PlugNPay::Util;
use PlugNPay::Merchant;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::Membership::Plan::Type;

###########################################
# Module: History.pm
# -----------------------------------------
# Description:
#   Loads a customer's transaction history

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub setHistoryID {
  my $self = shift;
  my $historyID = shift;
  $self->{'historyID'} = $historyID;
}

sub getHistoryID {
  my $self = shift;
  return $self->{'historyID'};
}

sub setMerchantCustomerLinkID {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  $self->{'merchantCustomerLinkID'} = $merchantCustomerLinkID;
}

sub getMerchantCustomerLinkID {
  my $self = shift;
  return $self->{'merchantCustomerLinkID'};
}

sub setBillingAccountID {
  my $self = shift;
  my $billingAccountID = shift;
  $self->{'billingAccountID'} = $billingAccountID;
}

sub getBillingAccountID {
  my $self = shift;
  return $self->{'billingAccountID'};
}

sub setTransactionStatus {
  my $self = shift;
  my $transactionStatus = shift;
  $self->{'transactionStatus'} = $transactionStatus;
}

sub getTransactionStatus {
  my $self = shift;
  return $self->{'transactionStatus'};
}

sub setTransactionAmount {
  my $self = shift;
  my $transactionAmount = shift;
  $self->{'transactionAmount'} = $transactionAmount;
}

sub getTransactionAmount {
  my $self = shift;
  return $self->{'transactionAmount'};
}

sub setTransactionDescription {
  my $self = shift;
  my $description = shift;
  $self->{'description'} = $description;
}

sub getTransactionDescription {
  my $self = shift;
  return $self->{'description'};
}

sub setTransactionDate {
  my $self = shift;
  my $transactionDate = shift;
  $self->{'transactionDate'} = $transactionDate;
}

sub getTransactionDate {
  my $self = shift;
  return $self->{'transactionDate'};
}

sub setTransactionDateTime {
  my $self = shift;
  my $transactionDateTime = shift;
  $self->{'transactionDateTime'} = $transactionDateTime;
}

sub getTransactionDateTime {
  my $self = shift;
  return $self->{'transactionDateTime'};
}

sub setTransactionTypeID {
  my $self = shift;
  my $transactionTypeID = shift;
  $self->{'transactionTypeID'} = $transactionTypeID;
}

sub getTransactionTypeID {
  my $self = shift;
  return $self->{'transactionTypeID'};
}

sub setOrderID {
  my $self = shift;
  my $orderID = shift;
  $self->{'orderID'} = $orderID;
}

sub getOrderID {
  my $self = shift;
  return $self->{'orderID'};
}

sub setTransactionID {
  my $self = shift;
  my $transactionID = shift;
  $self->{'transactionID'} = $transactionID;
}

sub getTransactionID {
  my $self = shift;
  return $self->{'transactionID'};
}

########################################
# Subroutine: loadCustomerHistory
# --------------------------------------
# Description:
#   Loads a customer's history of 
#   transactions given a date range.
sub loadCustomerHistory {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  my $options = shift;

  my $logs = [];

  my $startDay = $options->{'startDay'};
  my $startMonth = $options->{'startMonth'};
  my $startYear = $options->{'startYear'};
  my $endDay = $options->{'endDay'};
  my $endMonth = $options->{'endMonth'};
  my $endYear = $options->{'endYear'};

  my ($beginDate, $endDate);
  if ($options->{'interval'} eq 'monthly') {
    $beginDate = sprintf('%04d%02d%02d', $startYear, $startMonth, 1);
    $endDate = sprintf('%04d%02d%02d', $endYear, $endMonth, new PlugNPay::Sys::Time()->getLastOfMonth($endMonth, $endYear));
  } else {
    $beginDate = sprintf('%04d%02d%02d', $startYear, $startMonth, $startDay);
    $endDate = sprintf('%04d%02d%02d', $endYear, $endMonth, $endDay);
  }
 
  my $queryBuilder = new PlugNPay::Database::QueryBuilder();
  my $query = $queryBuilder->generateDateRange({ 'start_date' => $beginDate, 'end_date' => $endDate });

  my $sql = q/SELECT id,
                     billing_merchant_id,
                     merchant_customer_link_id,
                     transaction_amount,
                     transaction_date,
                     transaction_date_time,
                     transaction_status,
                     description,
                     order_id,
                     pnp_internal_transaction_id,
                     transaction_type_id
              FROM customer_transaction_history
              WHERE merchant_customer_link_id = ?
              AND transaction_date IN (/ . $query->{'params'} . ')'
              . ' ORDER BY id ASC';
  
  my $limit = '';
  if ( (defined $self->{'limitData'}{'limit'}) && (defined $self->{'limitData'}{'offset'}) ) {
    $limit = ' LIMIT ?,? ';
    push (@{$query->{'values'}}, $self->{'limitData'}{'offset'});
    push (@{$query->{'values'}}, $self->{'limitData'}{'limit'});
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust', $sql . $limit, [$merchantCustomerLinkID, @{$query->{'values'}}], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $logEntry = new PlugNPay::Merchant::Customer::History();
        $logEntry->_setHistoryDataFromRow($row);
        push (@{$logs}, $logEntry);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'                  => $@,
      'merchantCustomerLinkID' => $merchantCustomerLinkID,
      'function'               => 'loadCustomerHistory'
    });
  }

  return $logs;
}

################################
# Subroutine: loadHistoryEntry
# ------------------------------
# Description:
#   Loads an entry given an ID
sub loadHistoryEntry {
  my $self = shift;
  my $historyID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               billing_merchant_id,
               merchant_customer_link_id,
               transaction_amount,
               transaction_date,
               transaction_date_time,
               transaction_status,
               description,
               order_id,
               pnp_internal_transaction_id,
               transaction_type_id
        FROM customer_transaction_history
        WHERE id = ?/, [$historyID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setHistoryDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadHistoryEntry'
    });
  }
}

####################################
# Subroutine: saveHistoryEntry
# ----------------------------------
# Description:
#   Saves transaction results for 
#   a customer. Internal use only.
sub saveHistoryEntry {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  my $transactionData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my $time = new PlugNPay::Sys::Time();

  my $dateTime = $transactionData->{'transactionDate'} || $transactionData->{'transactionDateTime'};

  my $transactionID = $transactionData->{'transactionID'};
  if ($transactionID =~ /^[a-fA-F0-9]+$/) {
    $transactionID = &PlugNPay::Util::hexToBinary($transactionID);
  }

  eval {
    my $params = [
      $merchantCustomerLinkID,
      $transactionData->{'billingAccountID'},
      $transactionData->{'transactionStatus'},
      $transactionData->{'transactionAmount'},
      $transactionData->{'description'},
      $time->inFormatDetectType('yyyymmdd', $dateTime),
      $time->inFormatDetectType('iso_gm', $dateTime),
      $transactionData->{'transactionTypeID'},
      $transactionData->{'orderID'},
      $transactionID
    ];

    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/INSERT INTO customer_transaction_history
        ( merchant_customer_link_id,
          billing_merchant_id,
          transaction_status,
          transaction_amount,
          description,
          transaction_date,
          transaction_date_time,
          transaction_type_id,
          order_id,
          pnp_internal_transaction_id )
        VALUES (?,?,?,?,?,?,?,?,?,?)/, $params);
  };

  if ($@) {
    $self->_log({
      'error'           => $@,
      'transactionData' => $transactionData,
      'function'        => 'saveHistoryEntry'
    });

    $status->setFalse();
    $status->setError('Failed to save history entry');
  }

  return $status;
}

sub _setHistoryDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'historyID'}              = $row->{'id'};
  $self->{'billingAccountID'}       = $row->{'billing_merchant_id'};
  $self->{'merchantCustomerLinkID'} = $row->{'merchant_customer_link_id'};
  $self->{'transactionAmount'}      = $row->{'transaction_amount'};
  $self->{'transactionDate'}        = $row->{'transaction_date'};
  $self->{'transactionDateTime'}    = $row->{'transaction_date_time'};
  $self->{'transactionStatus'}      = $row->{'transaction_status'};
  $self->{'description'}            = $row->{'description'};
  $self->{'orderID'}                = $row->{'order_id'};
  $self->{'transactionID'}          = $row->{'pnp_internal_transaction_id'};
  $self->{'transactionTypeID'}      = $row->{'transaction_type_id'};
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData; 
}

sub getHistoryTableCount {
  my $self = shift;
  my $merchantCustomerLinkID = shift;
  my $options = shift;

  my $count = 0;

  my $startDay = $options->{'startDay'};
  my $startMonth = $options->{'startMonth'};
  my $startYear = $options->{'startYear'};
  my $endDay = $options->{'endDay'};
  my $endMonth = $options->{'endMonth'};
  my $endYear = $options->{'endYear'};

  my ($beginDate, $endDate);
  if ($options->{'interval'} eq 'monthly') {
    $beginDate = sprintf('%04d%02d%02d', $startYear, $startMonth, 1);
    $endDate = sprintf('%04d%02d%02d', $endYear, $endMonth, new PlugNPay::Sys::Time()->getLastOfMonth($endMonth, $endYear));
  } else {
    $beginDate = sprintf('%04d%02d%02d', $startYear, $startMonth, $startDay);
    $endDate = sprintf('%04d%02d%02d', $endYear, $endMonth, $endDay);
  }

  my $queryBuilder = new PlugNPay::Database::QueryBuilder();
  my $query = $queryBuilder->generateDateRange({ 'start_date' => $beginDate, 'end_date' => $endDate });

  eval {
    # Get the count first
    my $sql = q/SELECT COUNT(*) as `count`
                FROM customer_transaction_history
                WHERE merchant_customer_link_id = ?
                AND transaction_date IN (/;
    $sql .= $query->{'params'} . ')';

    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust', $sql, [$merchantCustomerLinkID, @{$query->{'values'}}], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'getHistoryTableCount' 
    });
  }

  return $count;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'customer_history' });
  $logger->log($logInfo);
}

1;
