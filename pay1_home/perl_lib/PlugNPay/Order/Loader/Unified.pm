package PlugNPay::Order::Loader::Unified;

use strict;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::Loader;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Util::UniqueID;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $loadLimitData = shift;
  if ($loadLimitData) {
    $self->setLoadLimit($loadLimitData);
  }

  return $self;
}

#######################
# Order table queries #
#######################
#Loads a SPECIFIC order
sub load {
  my $self = shift;
  my $orderID = shift;
  my $merchantID = shift;
  my $select = q/
                SELECT pnp_order_id,
                       merchant_id ,
                       merchant_order_id,
                       merchant_classification_id,
                       creation_date_time
                  FROM `order`
                 WHERE /;
  my @values;
  my $orderIdBinary = PlugNPay::Util::UniqueID::fromHexToBinary($orderID);

  if ($merchantID) {
    $select .= ' (merchant_order_id = ? OR pnp_order_id = ?) AND merchant_id = ? ';
    @values = ($orderID,$orderIdBinary,$merchantID);
  } else {
    $select .= ' pnp_order_id = ?';
    @values = ($orderIdBinary);
  }

  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('pnp_transaction', $select, \@values, {})->{'result'};
  my $data = $rows->[0];
  if ($data) {
    my $time = new PlugNPay::Sys::Time();
    $time->fromFormat('iso_gm',$data->{'creation_date_time'});
    $data->{'creation_date'} = $time->inFormat('db_gm');
    $data->{'order_details'} = $self->loadOrderDetails($data->{'pnp_order_id'});
    $data->{'order_transaction_ids'} = new PlugNPay::Transaction::Loader()->loadTransactionIDs($data->{'pnp_order_id'});
  }
  return $data;
}

#Loads orders by merchant name
sub loadOrdersByMerchants {
  my $self = shift;
  my $usernames = shift;
  my @params = ();

  if (ref($usernames) ne 'ARRAY') {
    $usernames = [$usernames];
  }

  foreach my $username (@{$usernames}) {
     my $search =  '( m.identifier = ? AND o.merchant_id = m.id)';
     push @params,$search;
  }
  my $dbs = new PlugNPay::DBConnection();
  my $select = q/
                SELECT o.merchant_order_id, m.identifier, o.creation_date_time
                  FROM `order` o, merchant m
                 WHERE / . join(' OR ',@params);
  return $dbs->fetchallOrDie('pnp_transaction', $select, $usernames, {})->{'result'};
}

sub loadOrders {
  my $self = shift;
  my $data = shift;
  my $select = 'SELECT o.merchant_order_id, o.pnp_order_id, m.identifier, o.creation_date_time ';
  if (ref($data) eq 'HASH') {
    $data = [$data];
  }

  return $self->_loadMultipleOrders($select,$data);
}

#Loads multiple orders
sub _loadMultipleOrders {
  my $self = shift;
  my $select = shift;
  my $data = shift;
  $select .= ' FROM ';

  my $databases = {' `order` o ' => 1, ' merchant m ' => 1};
  my $databaseRelations = {'o.merchant_id = m.id'};
  my @params = ();
  my @values = ();
  my $builder = new PlugNPay::Database::QueryBuilder();
  my $time = new PlugNPay::Sys::Time();

  foreach my $query (@{$data}) {
    my $search = ' ';
    if (defined $query->{'username'}) {
      $search .= ' AND m.identifier = ? ';
      push @values,$query->{'username'};
    }

    if (defined $query->{'orderID'}) {
      $search .= ' AND o.pnp_order_id = ? ';
      my $binaryOrderID = PlugNPay::Util::UniqueID::fromHexToBinary($query->{'orderID'});
      push(@values,$binaryOrderID);
    }

    my $dateSearch = $builder->generateDateRange($query);
    $search .= ' AND creation_date IN (' . $dateSearch->{'params'} . ') ';
    push @values,@{$dateSearch->{'values'}};

    if ($query->{'start_hour'}) {
      $search .= ' AND o.creation_date_time >= ? ';
      my $dateFormat = $time->inFormatDetectType('yyyymmdd',$query->{'start_date'});
      my $hourString = $dateFormat . $query->{'start_hour'} . "0000";
      my $startHour = $time->inFormatDetectType('iso',$hourString);
      push @values, $startHour;
    }

    if ($query->{'end_hour'}) {
      $search .= ' AND o.creation_date_time <= ? ';
      my $dateFormat = $time->inFormatDetectType('yyyymmdd',$query->{'end_date'});
      my $hourString = $dateFormat . $query->{'end_hour'} . "0000";
      my $endHour = $time->inFormatDetectType('iso',$hourString);
      push @values, $endHour;
    }

    if ($query->{'card_number'}) {
      $databases->{' `transaction` t '} = 1;
      $databaseRelations->{' o.pnp_order_id = t.pnp_order_id '} = 1;
      $search .= ' AND t.pnp_transaction_id IN ( SELECT pnp_transaction_id FROM card_transaction WHERE ';
      $search .= ' card_first_six = ? AND card_last_four = ?) ';
      my $cardNumber = $query->{'card_number'};
      my $firstSix = substr($cardNumber,0,6);
      my $lastFour = substr($cardNumber,-4,4);
      push @values, $firstSix;
      push @values, $lastFour;
    }

    if ($query->{'account_codes'}) {
      $databases->{' `transaction` t '} = 1;
      $databaseRelations->{' o.pnp_order_id = t.pnp_order_id '} = 1;
      $search .= ' AND t.pnp_transaction_id IN ( SELECT transaction_id FROM transaction_account_code WHERE ';
      my @spookyQuery = ();
      my @spookyValues = ();
      foreach my $code (keys %{$query->{'account_codes'}}) {
        my $value  = $query->{'account_codes'}{$code};
        my $searchOption = ' (account_code_number = ? AND value ';
        if ($query->{'partial_match'} eq 'true') {
          $value = '%' . $value . '%';
          $searchOption .= ' LIKE ?) ';
        } else {
          $searchOption .= ' = ?) ';
        }
        push @spookyQuery,$searchOption;
        push @spookyValues, $code;
        push @spookyValues, $value;
      }

      if (@spookyQuery > 0) {
        push @values, @spookyValues;
        $search .= join(' OR ', @spookyQuery) . ')  ';
      }
    }

    my $transStateInfo = $self->_generateTransStateSearch($query);
    if ($transStateInfo->{'searchString'} && @{$transStateInfo->{'values'}} > 0) {
       foreach my $db (@{$transStateInfo->{'databases'}}) {
         $databases->{$db->{'name'}} = 1;
         $databaseRelations->{$db->{'relation'}} = 1;
       }
       $search .= $transStateInfo->{'searchString'};
       push @values, @{$transStateInfo->{'values'}};
    }

    push @params, ' ( ' . join(' AND ', keys %{$databaseRelations}) . $search . ' ) ';
  }

  my $limitData = $self->getLoadLimit() || {};
  my $limit = '';
  if (defined $limitData->{'offset'} && defined $limitData->{'length'}) {
    $limit = ' ORDER BY o.id ASC LIMIT ?,? ';
    push @values,$limitData->{'offset'};
    push @values,$limitData->{'length'};
  }

  my $orders = [];
  if (@params > 0) {
    my $dbs = new PlugNPay::DBConnection();
    $select .= ' ' .join(', ', keys %{$databases}) . ' WHERE ' . join(' OR ',@params)  . $limit;
    $orders = $dbs->fetchallOrDie('pnp_transaction', $select, \@values, {})->{'result'};
  }

  return $orders;
}

#Probably the most shameful thing I have ever coded.
sub _generateTransStateSearch {
  my $self = shift;
  my $query = shift;
  my $databaseAdditions = [];
  my @values = ();
  my $search = '';

  if (exists $query->{'transaction_states'} && exists $query->{'transaction_status'}) {
    my $statesToSearch = {};
    foreach my $state (@{$query->{'transaction_states'}}) {
      foreach my $status (@{$query->{'transaction_status'}}) {
        if ($state eq 'POSTAUTH_READY') {
          my $newState = 'AUTH';
          $statesToSearch->{$newState} = '?';
        } else {
          my $newState = uc($state) . (uc($status) ne 'SUCCESS' ? '_' . uc($status) : '');
          $statesToSearch->{$newState} = '?';
        }
      }
    }

    @values = keys %{$statesToSearch};
    my @additionalParams = values %{$statesToSearch};
    $search .= ' AND s.state IN (' . join(',',@additionalParams) . ') ';

  } elsif (exists $query->{'transaction_states'}) {
    my @stateSearch = map{ ' state LIKE ? '} @{$query->{'transaction_states'}};
    $search .= ' AND s.id IN (SELECT id FROM transaction_state WHERE ' . join(' OR ', @stateSearch) . ') ';
    @values = map { uc($_) . '%' } @{$query->{'transaction_states'}};

  } elsif (exists $query->{'transaction_status'}) {
    my @statusSearch = ();
    foreach my $status (@{$query->{'transaction_status'}}) {
      if (uc($status) eq 'SUCCESS') {
        push @statusSearch, ' state NOT LIKE ? AND state NOT LIKE ?';
        push @values, '%_PROBLEM';
        push @values, '%_PENDING';
      } elsif (uc($status) eq 'PENDING') {
        push @statusSearch, ' state LIKE ?';
        push @values, '%_PENDING';
      } else {
        push @statusSearch, ' state LIKE ?';
        push @values, '%_PROBLEM';
      }
    }

    $search .= ' AND s.id IN (SELECT id FROM transaction_state WHERE ' . join(' OR ', @statusSearch) . ') ';
  }

  if (@values > 0) {
    push @{$databaseAdditions}, {'name' => ' `transaction` t ', 'relation' => 'o.pnp_order_id = t.pnp_order_id'};
    push @{$databaseAdditions}, {'name' => ' transaction_state s ', 'relation' => 't.transaction_state_id = s.id'};
  }

  return {'databases' => $databaseAdditions, 'searchString' => $search, 'values' => \@values};
}

#Get count of orders
sub getOrdersListSize {
  my $self = shift;
  my $data = shift;
  if (ref($data) eq 'HASH') {
    $data = [$data];
  }
  my $select = 'SELECT COUNT(o.id) AS `count` ';

  return $self->_loadMultipleOrders($select, $data)->[0]{'count'};
}

#Does this order exist? The world may never know...
sub orderExists {
  my $self = shift;
  my $merchantOrderID = shift;
  my $merchant = shift;
  my $internalID = new PlugNPay::GatewayAccount::InternalID();
  my $merchID = $internalID->getMerchantID($merchant);

  my $dbs = new PlugNPay::DBConnection();
  my $select = q/
                SELECT COUNT(id) AS `exists`
                  FROM `order`
                 WHERE merchant_order_id = ?
                   AND merchant_id = ?/;

  my $rows = $dbs->fetchallOrDie('pnp_transaction', $select, [$merchantOrderID, $merchID], {})->{'result'};

  return $rows->[0]{'exists'}; #Oh wait now we know.
}

#There's a spooky column in the order table meant to do something bad, luckily it's not used yet
sub getLegacyStatus {
  my $self = shift;
  my $orderID = shift;
  my $merchant = shift;
  my $internalID = new PlugNPay::GatewayAccount::InternalID();
  my $merchID = $internalID->getMerchantID($merchant);
  my $dbs = new PlugNPay::DBConnection();

  my $select = q/
                SELECT legacy_transaction
                  FROM `order`
                 WHERE merchant_order_id = ?
                   AND merchant_id = ? /;
  my $rows = $dbs->fetchallOrDie('pnp_transaction', $select, [$orderID, $merchID], {})->{'result'};
  return $rows->[0]{'legacy_transaction'};
}

#Does this date range/order id for merchant exist in this db (Advanced exists func)
sub checkDatabase {
  my $self = shift;
  my $username = shift;
  my $options = shift;
  my $select = 'SELECT COUNT(o.pnp_order_id) AS `exists`
                  FROM `order` o, `merchant` m
                 WHERE o.merchant_id = m.id
                   AND m.identifier = ? ';
  my @values = ($username);

  if ($options->{'orderID'}) {
    push @values, $options->{'orderID'};
    $select .= ' AND o.merchant_order_id = ?';
  } else {
    my $startDate = $options->{'newStart'};
    my $endDate = $options->{'newEnd'};
    my $builder = new PlugNPay::Database::QueryBuilder();
    my $time = new PlugNPay::Sys::Time();
    $startDate = $time->inFormatDetectType('yyyymmdd',$startDate);
    $endDate = $time->inFormatDetectType('yyyymmdd',$endDate);
    my $dateSearch = $builder->generateDateRange({'start_date' => $startDate, 'end_date' => $endDate});
    $select .= ' AND creation_date IN (' . $dateSearch->{'params'} . ') ';
    push @values,@{$dateSearch->{'values'}};

    if (defined  $startDate) {
      $select .= ' AND o.creation_date_time >= ? ';
      push @values,$startDate . 'T' . '000000Z';
    }

    if (defined $endDate) {
      $select .= ' AND o.creation_date_time <= ? ';
      push @values,$endDate . 'T' . '240000Z';
    }
  }

  my $exists = 0;
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('pnp_transaction', $select, \@values, {})->{'result'};
    $exists = $rows->[0]{'exists'} ? 1 : 0;
  };

  $self->log({'message' => 'load error', 'error' => $@}) if $@;

  return $exists;
}

#This next func is whack
sub query {
  my $self = shift;
  my $processor = shift;
  my $vehicle = shift;
  my $queryData = shift;
  my $loader = new PlugNPay::Transaction::Loader();
  my $dbs = new PlugNPay::DBConnection();
  my $time = new PlugNPay::Sys::Time();
  my $transactions = $loader->query($processor,$vehicle,$queryData);
  my $query = 'SELECT pnp_order_id,merchant_order_id,
                      merchant_id,creation_date_time,merchant_classification_id
                 FROM `order` ';
  my @params = ();
  my @checks = ();

  foreach my $id (keys %{$transactions}) {
    push @params,$id;
    push @checks, ' pnp_order_id = ? ';
  }

  if (@checks > 0) {
    $query .= ' WHERE ' . join(' OR ',@checks);
    my $rows = $dbs->fetchallOrDie('pnp_transaction', $query, \@params, {})->{'result'};
    foreach my $row (@{$rows}){
      $time->fromFormat('iso_gm',$row->{'creation_date_time'});
      $transactions->{$row->{'pnp_order_id'}}{'merchant_order_id'} = $row->{'merchant_order_id'};
      $transactions->{$row->{'pnp_order_id'}}{'merchant_id'} = $row->{'merchant_id'};
      $transactions->{$row->{'pnp_order_id'}}{'creation_date'} = $time->inFormat('db_gm');
      $transactions->{$row->{'pnp_order_id'}}{'merchant_classification_id'} = $row->{'merchant_classification_id'};
    }
  }

  if (defined $queryData->{'merchant_order_id'}) {
     my $select = q/SELECT o.pnp_order_id, o.merchant_order_id, o.merchant_id,
                           o.creation_date_time, t.transaction_vehicle_id
                      FROM `order` o, transaction t
                     WHERE o.pnp_order_id = t.pnp_order_id
                       AND o.merchant_order_id = ?/;
    my $rows = $dbs->fetchallOrDie('pnp_transaction', $select, [$queryData->{'merchant_order_id'}], {})->{'result'};

    foreach my $row (@{$rows}) {
      my $loadedVh;
      if ( $row->{'transaction_vehicle_id'} eq '2' ) {
        $loadedVh = 'ach';
      } else {
        $loadedVh = 'card';
      }

      if (!defined $transactions->{$row->{'pnp_order_id'}}) {
        my $orders = $loader->newLoad($loadedVh,{'pnp_transaction_id' => $row->{'pnp_transaction_id'}});
        $time->fromFormat('iso_gm',$row->{'creation_date_time'});
        $transactions->{$row->{'pnp_order_id'}}{$row->{'pnp_transaction_id'}} = $orders;
        $transactions->{$row->{'pnp_order_id'}}{'merchant_order_id'} = $row->{'merchant_order_id'};
        $transactions->{$row->{'pnp_order_id'}}{'merchant_id'} = $row->{'merchant_id'};
        $transactions->{$row->{'pnp_order_id'}}{'creation_date'} = $time->inFormat('db_gm');
      }
    }
  }

  return $transactions;
}

#Order Details table AKA level 3 Data
sub loadOrderDetails {
  my $self = shift;
  my $orderID = shift;
  my $select = q/
                SELECT d.item_name AS `name`,
                       d.quantity AS `quantity`,
                       d.cost AS `cost`,
                       d.description AS `description`,
                       d.discount_amount AS `discount`,
                       d.tax_amount AS `tax`,
                       d.commodity_code AS `commodity_code`,
                       d.item_info_1 AS `custom_1`,
                       d.item_info_2 AS `custom_2`,
                       u.code AS `unit`,
                       d.is_taxable AS `isTaxable`
                  FROM order_details d, units_of_measure u
                 WHERE d.pnp_order_id = ?
                   AND d.unit_of_measure = u.id /;

  my $dbs = new PlugNPay::DBConnection();
  return $dbs->fetchallOrDie('pnp_transaction', $select, [$orderID], {})->{'result'};
}

sub loadDetailsByMerchOrderID { #can probably conslidate these two...
  my $self = shift;
  my $orderID = shift;
  my $merchant = shift;
  my $select = q/
                SELECT d.item_name AS `name`,
                       d.quantity AS `quantity`,
                       d.cost AS `cost`,
                       d.description AS `description`,
                       d.discount_amount AS `discount`,
                       d.tax_amount AS `tax`,
                       d.commodity_code AS `commodity_code`,
                       d.item_info_1 AS `custom_1`,
                       d.item_info_2 AS `custom_2`,
                       u.code AS `unit`,
                       d.is_taxable AS `isTaxable`
                  FROM order_details d, units_of_measure u, `order` o, `merchant` m
                 WHERE o.merchant_order_id = ?
                   AND m.identifier = ?
                   AND m.id = o.merchant_id
                   AND o.pnp_order_id = d.pnp_order_id
                   AND d.unit_of_measure = u.id /;

  my $dbs = new PlugNPay::DBConnection();
  return $dbs->fetchallOrDie('pnp_transaction', $select, [$orderID,$merchant], {})->{'result'};
}

#Responder interface stuff, not used by normal code
sub setLoadLimit {
  my $self = shift;
  my $limitHash = shift;

  $self->{'limitData'} = $limitHash;
}

sub getLoadLimit {
  my $self = shift;
  return $self->{'limitData'};
}

#Logging
sub log {
  my $self = shift;
  my $data = shift;
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'order'});
  $data->{'subModule'} = 'Unified';
  $logger->log($data);
}

1;
