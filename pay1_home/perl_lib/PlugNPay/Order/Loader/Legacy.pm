package PlugNPay::Order::Loader::Legacy;

use strict;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;
use PlugNPay::Logging::DataLog;

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


# functionally equivilent to Unified's load, i hope...
sub load {
  my $self = shift;
  my $orderID = shift;
  my $username = shift;

  return $self->loadOrders([{ orderID => $orderID ,username => $username }]);
}

#op_log functions
# This is here because, realistically, the whole transaction directory should be inside order/
# Also, operation_log is "order level" info, sort of
sub loadOrders {
  my $self = shift;
  my $data = shift;
  if (ref($data) eq 'HASH') {
    $data = [$data];
  }

  my $select = q/
     SELECT orderid AS `merchant_order_id`,
            orderid AS `pnp_order_id`,
            username AS `identifier`,
            COALESCE(authtime,returntime) AS `creation_date_time`
       FROM operation_log
       WHERE /;

  return $self->_loadMultipleOrders($select, $data);
}

sub _loadMultipleOrders {
  my $self = shift;
  my $select = shift;
  my $data = shift;
  my $builder = new PlugNPay::Database::QueryBuilder();
  my $time = new PlugNPay::Sys::Time();
  my @values = ();
  my @params = ();

  foreach my $query (@{$data}) {
    my @search = ();
    if (defined $query->{'username'}) {
      push @search, ' username = ? ';
      push @values, $query->{'username'};
    }

    if (defined $query->{'orderID'}) { # no seriously how was this missing?
      push @search, ' orderid = ? ';
      push @values,$query->{'orderid'};
    }

    my $dateSearch = $builder->generateDateRange($query);
    push @search, ' trans_date IN (' . $dateSearch->{'params'} . ') ';
    push @values, @{$dateSearch->{'values'}};

    if ($query->{'start_date'}) {
      push @search, ' trans_date >= ? ';
      my $startDate = $time->inFormatDetectType('yyyymmdd',$query->{'start_date'});
      push @values, $startDate;
    }

    if ($query->{'end_date'}) {
      push @search, ' trans_date <= ? ';
      my $endDate = $time->inFormatDetectType('yyyymmdd',$query->{'end_date'});
      push @values, $endDate;
    }

    if ($query->{'start_hour'}) {
      push @search, ' COALESCE(authtime,returntime) >= ? ';

      my $datefmt = $time->inFormatDetectType('yyyymmdd',$query->{'start_date'});
      my $hourstr = $datefmt . $query->{'start_hour'} . "0000";
      my $startHour = $time->inFormatDetectType('gendatetime',$hourstr);

      push @values, $startHour;
    }

    if ($query->{'end_hour'}) {
      push @search, ' COALESCE(authtime,returntime) <= ? ';
      my $datefmt = $time->inFormatDetectType('yyyymmdd',$query->{'end_date'});
      my $hourstr = $datefmt . $query->{'end_hour'} . "0000";
      my $endHour = $time->inFormatDetectType('gendatetime',$hourstr);
      push @values, $endHour;
    }

    if ($query->{'card_number'}) {
        push @search, ' (card_number = ? OR card_number = ? OR card_number = ?)';
        my $cardnumber = $query->{'card_number'};
        my $shortcard1 = substr($cardnumber,0,4) . "**" . substr($cardnumber,-2,2);
        my $shortcard2 = substr($cardnumber,0,4) . "**" . substr($cardnumber,-4,4);
        my $shortcard3 = substr($cardnumber,0,6) . "**" . substr($cardnumber,-4,4);
        push @values, $shortcard1;
        push @values, $shortcard2;
        push @values, $shortcard3;
    }

    if ($query->{'account_codes'}) {
      my @spookyQuery = ();
      my @spookyValues = ();
      foreach my $code (keys %{$query->{'account_codes'}}) {
        my $value = $query->{'account_codes'}{$code};
        my $searchOption = ' = ? ';
        if ($query->{'partial_match'} eq 'true') {
          $value = '%' . $value . '%';
          $searchOption = ' LIKE ? ';
        }

        if ($code == 1) {
          push @spookyQuery, ' acct_code ' . $searchOption;
        } else {
          push @spookyQuery, ' acct_code' . $code . $searchOption;
        }

        push @spookyValues, $value;
      }

      if (@spookyQuery > 0) {
        push @values, @spookyValues;
        push @search,join(' AND ', @spookyQuery);
      }
    }

    if (exists $query->{'transaction_states'}) {
      my @qmarks = ('?') x  @{$query->{'transaction_states'}};
      push @search,' lastop IN ( ' . join(',', @qmarks) . ' ) ';
      push @values,@{$query->{'transaction_states'}};
    }

    if (exists $query->{'transaction_status'}) {
      my @qmarks =  ();
      my @statusValues = ();
      foreach my $status (@{$query->{'transaction_status'}}) {
         push @qmarks, '?';
         push @statusValues, lc($status);
         if (lc($status) eq 'problem') {
           push @qmarks, '?';
           push @statusValues, 'badcard';
         }
      }

      push @search,' lastopstatus IN ( ' . join(',', @qmarks) . ' ) ';
      push @values,@statusValues;
    }

    push @params,' ( ' . join(' AND ',@search) . ' ) ';
  }

  my $limitData = $self->getLoadLimit() || {};
  my $limit = '';
  if (defined $limitData->{'offset'} && defined $limitData->{'length'}) {
    $limit = ' ORDER BY trans_date ASC LIMIT ?,? ';
    push @values,$limitData->{'offset'};
    push @values,$limitData->{'length'};
  }
  my $orders = [];
  if (@params > 0) {
    $select .= join(' OR ',@params)  . $limit;
    my $dbs = new PlugNPay::DBConnection();
    $orders = $dbs->fetchallOrDie('pnpdata', $select, \@values, {})->{'result'};
  }

  return $orders;
}

#The number of orders for search criteria
sub getOrderListSize {
  my $self = shift;
  my $data = shift;
  my @orders = ();
  if (ref($data) eq 'HASH') {
    $data = [$data];
  }
  my $select = 'SELECT COUNT(orderid) AS `count`
                  FROM operation_log
                 WHERE ';

  return $self->_loadMultipleOrders($select,$data)->[0]{'count'};
}

#Do these orders exists for this search?
sub checkDatabase {
  my $self = shift;
  my $username = shift;
  my $options = shift;
  my $exists = 0;
  my $select = 'SELECT COUNT(orderid) AS `exists`
                  FROM operation_log
                 WHERE username = ?';
  my @params = ($username);
  my $builder = new PlugNPay::Database::QueryBuilder();

  if ($options->{'orderID'}) {
    $select .= ' AND orderid = ? ';
    push @params, $options->{'orderID'};

  } else {
    my $time = new PlugNPay::Sys::Time();
    my $legacyStart = $options->{'legacyStart'};
    my $legacyEnd = $options->{'legacyEnd'};
    my $dateRange = {};
    if (defined  $legacyStart) {
      $dateRange->{'start_date'} = $time->inFormatDetectType('yyyymmdd',$legacyStart);
    }

    if (defined $legacyEnd) {
      $dateRange->{'end_date'} = $time->inFormatDetectType('yyyymmdd',$legacyEnd);
    }

    if (%{$dateRange}) {
      my $built = $builder->generateDateRange($dateRange);
      push @params, @{$built->{'values'}};
      $select .= ' AND trans_date IN (' . $built->{'params'} . ')';
    }
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('pnpdata', $select, \@params, {})->{'result'};
    $exists = $rows->[0]{'exists'} ? 1 : 0;
  };

  $self->log({'message' => 'load error', 'error' => $@}) if $@;

  return $exists;
}

#Level 3 Data
sub loadOrderDetails {
  my $self = shift;
  my $orderID = shift;
  my $merchant = shift;
  my $select = q/ SELECT item,
                         quantity,
                         cost,
                         description,
                         customa,
                         customb,
                         customc,
                         customd,
                         custome,
                         unit
                    FROM orderdetails
                   WHERE orderid = ?
                     AND username = ? /;
  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('pnpdata', $select, [$orderID,$merchant], {})->{'result'};
  my @items = ();
  foreach my $row (@{$rows}){
    my $hash = {};
    $hash->{'name'}           = $row->{'item'} || '';
    $hash->{'cost'}           = $row->{'cost'} || '';
    $hash->{'description'}    = $row->{'description'} || '';
    $hash->{'quantity'}       = $row->{'quantity'} || '';
    $hash->{'discount'}       = $row->{'customa'} || '';
    $hash->{'tax'}            = $row->{'customb'} || '';
    $hash->{'commodity_code'} = $row->{'customc'} || '';
    $hash->{'custom_1'}       = $row->{'customd'} || '';
    $hash->{'custom_2'}       = $row->{'custome'} || '';
    $hash->{'unit'}           = $row->{'unit'} || '';
    $hash->{'isTaxable'}      = ($hash->{'tax'} ne '' ? 1 : 0);
    push @items, $hash;
  }

  return \@items;
}

#Responder limit data, not used normally
sub setLoadLimit {
  my $self = shift;
  my $limitHash = shift;

  $self->{'limitData'} = $limitHash;
}

sub getLoadLimit {
  my $self = shift;

  return $self->{'limitData'};
}

#Loggers for Joggers
sub log {
  my $self = shift;
  my $data = shift;
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'order'});
  $data->{'subModule'} = 'Legacy';
  $logger->log($data);
}

1;
