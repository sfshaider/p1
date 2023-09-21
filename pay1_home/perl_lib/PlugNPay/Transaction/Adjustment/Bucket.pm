package PlugNPay::Transaction::Adjustment::Bucket;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Clone;
use PlugNPay::Util::Memcached;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'memcached'} = new PlugNPay::Util::Memcached('Adjustment-Bucket');

  my $gatewayAccount = shift;
 
  if ($gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
  }

  return $self;
}

sub setID {
  my $self = shift;
  my $id = shift;
  $self->{'id'} = $id;
}

sub getID {
  my $self = shift;
  return $self->{'id'};
}

sub setGatewayAccount {
  my $self = shift;
  my $username = shift;
  $self->{'gatewayAccount'} = $username;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setPaymentVehicleSubtypeID {
  my $self = shift;
  my $paymentVehicleSubtypeID = shift;
  $self->{'paymentVehicleSubtypeID'} = $paymentVehicleSubtypeID;
}

sub getPaymentVehicleSubtypeID {
  my $self = shift;
  return $self->{'paymentVehicleSubtypeID'};
}

sub setDefaultPaymentVehicleSubtypeID {
  my $self = shift;
  my $paymentVehicleSubtypeID = shift;
  $self->{'defaultPaymentVehicleSubtypeID'} = $paymentVehicleSubtypeID;
}

sub getDefaultPaymentVehicleSubtypeID {
  my $self = shift;
  return $self->{'defaultPaymentVehicleSubtypeID'};
}

sub setBase {
  my $self = shift;
  my $base = shift;
  $self->{'base'} = $base;
}

sub getBase {
  my $self = shift;
  return $self->{'base'};
}

sub setCOARate {
  my $self = shift;
  my $coaRate = shift;
  $self->{'coaRate'} = $coaRate;
}

sub getCOARate {
  my $self = shift;
  return $self->{'coaRate'};
}

sub setCOAAdjustmentAmount {
  my $self = shift;
  my $coaAdjustmentAmount = shift;
  $self->{'coaAdjustmentAmount'} = $coaAdjustmentAmount;
}

sub getCOAAdjustmentAmount {
  my $self = shift;
  return $self->{'coaAdjustmentAmount'};
}

sub setTotalRate {
  my $self = shift;
  my $totalRate = shift;
  $self->{'totalRate'} = $totalRate;
}

sub getTotalRate {
  my $self = shift;
  return $self->{'totalRate'};
}

sub setFixedAdjustment {
  my $self = shift;
  my $fixedAdjustment = shift;
  $self->{'fixedAdjustment'} = $fixedAdjustment;
}

sub getFixedAdjustment {
  my $self = shift;
  return $self->{'fixedAdjustment'};
}

sub setMode {
  my $self = shift;
  my $mode = shift;
  $self->{'mode'} = $mode;
}

sub getMode {
  my $self = shift;
  return $self->{'mode'};
}

sub setTransactionAmount {
  my $self = shift;
  my $amount = shift;
  $self->{'transactionAmount'} = $amount;
}

sub getTransactionAmount {
  my $self = shift;
  return $self->{'transactionAmount'};
}

sub bucketExistsForSubtypeID {
  my $self = shift;
  my $subtypeID = shift;

  my $allBuckets = $self->getAllBuckets();

  foreach my $bucket (@{$allBuckets}) {
    if ($bucket->{'paymentVehicleSubtypeID'} eq $subtypeID) {
      return 1;
    }
  }
  return 0;
}

sub getBuckets {
  my $self = shift;
  my $options = shift;

  if ($options->{'all'} == 1) {
    return $self->getAllBuckets();
  }

  my $allBuckets = $self->getAllBuckets();
  my @requestedBuckets;

  # if we are not getting all buckets, get the info needed to get the specific bucket(s)
  # also add on to the query to limit to the desired results
  if (!defined $options || $options->{'all'} != 1) {
    if (!defined $self->getMode()) {
      die('Bucket mode must be set before loading buckets.');
    }

    my $subtypeID = $self->getPaymentVehicleSubtypeID();
    if (!$self->bucketExistsForSubtypeID($subtypeID)) {
      $subtypeID = $self->getDefaultPaymentVehicleSubtypeID();
    }
    my $amount = $self->getTransactionAmount();
    my $mode = $self->getMode();
    my @bucketData;
    my @sortedBuckets;
    foreach my $bucket (@{$allBuckets}) {
      if ($bucket->{'paymentVehicleSubtypeID'} eq $subtypeID && $bucket->{'base'} <= $amount + 0) {
        push @bucketData, $bucket;
        @sortedBuckets =  sort { $b->{'base'} <=> $a->{'base'} } @bucketData;
      }
    }
    @requestedBuckets = $mode eq 'single' ? @sortedBuckets[0] : @sortedBuckets;
  }

  my $buckets = \@requestedBuckets;

  return $buckets;
}

sub getAllBuckets {
  my $self = shift;

  my $query = q/
    SELECT id,payment_vehicle_subtype_id,base,coa_rate,total_rate,fixed_adjustment FROM adjustment_bucket
     WHERE username = ?
  /;

  my @values = ( $self->getGatewayAccount() );

  my $cacheKey = getCacheKey($self->getGatewayAccount());

  my $data = $self->{'memcached'}->get($cacheKey);
  if ($data) {
    my $buckets = $self->bucketsFromData($data);
    return $buckets;
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', $query) or die($DBI::errstr);

  $sth->execute(@values) or die($DBI::errstr);

  my $data = $sth->fetchall_arrayref({});
  $self->{'memcached'}->set($cacheKey, $data, 900);

  my $buckets = $self->bucketsFromData($data);

  return $buckets;
}

sub bucketsFromData {
  my $self = shift;
  my $data = shift;

  my $objectCloner = new PlugNPay::Util::Clone();

  my @buckets;
  foreach my $row (@{$data}) {
    my $bucket = $objectCloner->deepClone($self);
    $bucket->setPaymentVehicleSubtypeID($row->{'payment_vehicle_subtype_id'});
    $bucket->setBase($row->{'base'});
    $bucket->setCOARate($row->{'coa_rate'});
    $bucket->setTotalRate($row->{'total_rate'});
    $bucket->setFixedAdjustment($row->{'fixed_adjustment'});
    push @buckets,$bucket;
  }

  return \@buckets;
}

sub _removeAllBuckets {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('pnpmisc', q/
    DELETE FROM adjustment_bucket
    WHERE username=?
  /);

  $sth->execute($self->getGatewayAccount());
}

sub setBuckets {
  my $self = shift;
  my $buckets = shift; # array reference

  if (!defined $buckets || ref $buckets ne 'ARRAY') {
    return;
  }

  # Clear the cache
  my $cacheKey = getCacheKey($self->getGatewayAccount());
  $self->{'memcached'}->delete($cacheKey);

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnpmisc'); # start a transaction

  # remove existing buckets
  $self->_removeAllBuckets();

  if (!@{$buckets}) {        # if there are no buckets to be saved then we want to
    $dbs->commit('pnpmisc'); # commit the removal of the buckets
    return 1;
  }

  my @placeholders;
  my @values;

  foreach my $bucket (@{$buckets}) {
    push(@placeholders,'(?,?,?,?,?,?)');
    # add values
    push @values, $self->getGatewayAccount();
    push @values, $bucket->getPaymentVehicleSubtypeID();
    push @values, $bucket->getBase();
    push @values, $bucket->getCOARate();
    push @values, $bucket->getTotalRate();
    push @values, $bucket->getFixedAdjustment();
  }

  my $query = q/
    INSERT INTO adjustment_bucket (
      username, 
      payment_vehicle_subtype_id, 
      base, 
      coa_rate,
      total_rate, 
      fixed_adjustment
    ) VALUES / . join(',',@placeholders);

  my $sth;
  if (($sth = $dbs->prepare('pnpmisc',$query)) && $sth->execute(@values)) {
    $dbs->commit('pnpmisc');
  } else {
    $dbs->rollback('pnpmisc');
  }
}

sub getCacheKey {
  my $username = shift;

  my $digestor = new PlugNPay::Util::Hash();
  $digestor->add($username);
  my $cacheKey = 'username-' . $digestor->sha256('0x');
  return $cacheKey;
}

1;
