package PlugNPay::Order::Detail;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Order::Saver;
use PlugNPay::Order::Loader;
use PlugNPay::Util::Cache::LRUCache;

our $cache;

############### Order Details ################## 
# Order details are used for Level 3 card data #
################################################

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!defined $cache) {
    $cache = new PlugNPay::Util::Cache::LRUCache(3);
    $self->loadMeasurementIDs();
  }

  my $detailData = shift;
  if (defined $detailData) {
    $self->newDetail($detailData);
  }

  return $self;
}


#####################
# Setters & Getters #
#####################

sub setName {
  my $self = shift;
  my $name = shift;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'} || '';
}

sub setQuantity {
  my $self = shift;
  my $quantity = shift;
  $self->{'quantity'} = $quantity;
}

sub getQuantity {
  my $self = shift;
  return $self->{'quantity'} || 0;
}

sub setCost {
  my $self = shift;
  my $cost = shift;
  $self->{'cost'} = $cost;
}

sub getCost {
  my $self = shift;
  return $self->{'cost'} || 0;
}

sub setDiscount {
  my $self = shift;
  my $discount = shift;
  $self->{'discount'} = $discount;
}

sub getDiscount {
  my $self = shift;
  return $self->{'discount'};
}

sub setTax {
  my $self = shift;
  my $tax = shift;
  $self->{'tax'} = $tax;
}

sub getTax {
  my $self = shift;
  return $self->{'tax'};
}

sub setDescription {
  my $self = shift;
  my $description = shift;
  $self->{'description'} = $description;
}

sub getDescription {
  my $self = shift;
  return $self->{'description'};
}

sub setCommodityCode {
  my $self = shift;
  my $commodityCode = shift;
  $self->{'commodityCode'} = $commodityCode;
}

sub getCommodityCode {
  my $self = shift;
  return $self->{'commodityCode'};
}

sub setCustom1 {
  my $self = shift;
  my $item_info_1 = shift;
  $self->{'item_info_1'} = $item_info_1;
}

sub getCustom1 {
  my $self = shift;
  return $self->{'item_info_1'};
}

sub setCustom2 {
  my $self = shift;
  my $item_info_2 = shift;
  $self->{'item_info_2'} = $item_info_2;
}

sub getCustom2 {
  my $self = shift;
  return $self->{'item_info_2'};
}

sub setUnitOfMeasure {
  my $self = shift;
  my $unitOfMeasure = shift;
  if ($unitOfMeasure =~ /^\d+$/) {
    $self->{'unitOfMeasure'} = $unitOfMeasure;
  } else {
    $self->{'unitOfMeasure'} = $self->getUnitID($unitOfMeasure);
  }
}

sub getUnitOfMeasure {
  my $self = shift;
  return $self->getUnitCode($self->{'unitOfMeasure'});
}

sub setTaxable {
  my $self = shift;
  my $isTaxable = shift;
  $self->{'isTaxable'} = $isTaxable;
}

sub isTaxable {
  my $self = shift;
  return $self->{'isTaxable'} || '0';
}

#############
# Functions #
#############

sub save {
  my $self = shift;
  my $saver = new PlugNPay::Order::Saver();
  my $success = $saver->saveDetails($self->getDetail());
  
  return $success;
}

sub load {
  my $self = shift;
  my $orderID = shift;
  my $loader = new PlugNPay::Order::Loader();
  my $detailData = $loader->loadDetail($orderID);
  my $detail = $self->newDetail($detailData);

  return $detail;
}

sub newDetail { #Turn hash into object!
  my $self = shift;
  my $data = shift;

  $self->setOrderID($data->{'pnp_order_id'});
  $self->setName($data->{'item_name'});
  $self->setQuantity($data->{'quantity'});
  $self->setDescription($data->{'description'});
  $self->setDiscount($data->{'discount_amount'});
  $self->setTax($data->{'tax_amount'});
  $self->setCommodityCode($data->{'commodityCode'});
  $self->setCustom1($data->{'item_info_1'});
  $self->setCustom2($data->{'item_info_2'});
  $self->setUnitOfMeasure($data->{'unit_of_measure'});

  return $self;
}  

sub getUnitID {
  my $self = shift;
  my $unitCode = shift;
  
  if (!$cache->contains('measurement_code_ids') || !defined $cache) {
    $self->loadMeasurementIDs();
  }

  my %reverseCodes = reverse %{$cache->get('measurement_code_ids')};
  return $reverseCodes{$unitCode};
}

sub getUnitCode {
  my $self = shift;
  my $unitID = shift;
  
  if (!$cache->contains('measurement_code_ids') || !defined $cache) {
    $self->loadMeasurementIDs();
  }
 
  return $cache->get('measurement_code_ids')->{$unitID};
}

sub loadMeasurementIDs{
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/ SELECT id,code
                             FROM units_of_measure
                           /); 
  $sth->execute() or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $ids = {};
  foreach my $row (@{$rows}) {
    $ids->{$row->{'id'}} = $row->{'code'};
  }

  $cache->set('measurement_code_ids',$ids);
}

1;
