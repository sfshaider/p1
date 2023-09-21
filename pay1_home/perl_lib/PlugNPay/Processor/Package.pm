package PlugNPay::Processor::Package;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::Memcached;
use PlugNPay::Debug;

#########################
#    Purpose of File    #
# To load package name  #
# of processor module.  #
#                       #
# Originally part of    #
# Route.pm, but seemed  #
# to be getting too big #
# so moving it here...  #
#                       #
#     Eventually :)     #
#########################

our $cache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->{'memcached'} = new PlugNPay::Util::Memcached('Processor::Package');

  return $self;
}

sub loadMultipleProcessors {
  my $self = shift;
  my $processors = shift || $self;

  if (ref($processors) ne 'ARRAY' || @{$processors} == 0) {
    return [];
  }
  my @response = ();
  foreach my $processor (@{$processors}) {
    my $currentCardPack = $self->getProcessorPackage($processor, 'card');
    my $currentACHPack = $self->getProcessorPackage($processor, 'ach');
    push @response, {'processor_name' => $processor, 'package_name' => $currentCardPack, 'payment_type' => 'credit'};
    push @response, {'processor_name' => $processor, 'package_name' => $currentACHPack, 'payment_type' => 'ach'};
  }
  
  return \@response;
}

sub _doNotUse {
  my $self = shift;
  my $processors = shift || $self;

  if (ref($processors) ne 'ARRAY' || @{$processors} == 0) {
    return [];
  }

  my $params = join(',', map {'?'} @{$processors});
  
  if ($params && $processors) {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT m.processor_name,m.package_name,p.payment_type
      FROM processor_module m, processor_payment_type p
      WHERE p.id = m.payment_type_id 
      AND m.processor_name IN (/ . $params . q/)/
    );
    $sth->execute(@{$processors}) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    return $rows;
  } else {
    return [];
  }
}

########################## NOTICE ###########################
# The following will replace the same functions in Route.pm #
#############################################################

sub getProcessorPackage {
  my $self = shift;
  my $processor = shift;
  my $payType = lc shift;

  my $processorData = $self->loadProcessorPackage($processor);

  my $response;
  if ($payType) {
    $payType = ($payType eq 'card' ? 'credit' : $payType);
    $response = $processorData->{$payType};
  }

  return $response;
}

sub addNewProcessorPackage { # Add new processor/package combo
  my $self = shift;
  my $info = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
                           INSERT INTO processor_module
                           (processor_name,payment_type_id,package_name)
                           VALUES (?,?,?)
                           /);
  $sth->execute($info->{'name'},$info->{'payment_id'},$info->{'package'}) or die $DBI::errstr;

  return 1;
}


sub loadProcessorPackage { # Load where sendmserver function is for processor
  my $self = shift;
  my $processor = shift;


  my $cachedProcessorData = $self->{'memcached'}->get($processor);
  if ($cachedProcessorData ne '') {
    debug { message => 'loaded processor data from cache' };
    return $cachedProcessorData;
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/ 
                           SELECT m.processor_name,p.payment_type,m.package_name
                           FROM processor_module m, processor_payment_type p
                           WHERE p.id = m.payment_type_id AND m.processor_name = ? /);

  $sth->execute($processor) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  
  my $data = {};
  foreach my $row (@{$rows}) {
    if (lc($row->{'processor_name'}) eq lc($processor)) {
      $data->{$row->{'payment_type'}} = $row->{'package_name'};
    }
  }

  $self->{'memcached'}->set($processor,$data, 900);
  return $data;
}

sub getProcessorPackageData { # Get package name where processor calls sendmserver
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/ 
                           SELECT m.processor_name,p.payment_type,m.package_name
                           FROM processor_module m, processor_payment_type p
                           WHERE p.id = m.payment_type_id/);

  $sth->execute() or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $data = {};
  foreach my $row (@{$rows}){
    my $procName = $row->{'processor_name'};
    my $payMethod = $row->{'payment_type'};
    $data->{$procName}{'name'} = $procName;
    $data->{$procName}{$payMethod}{'package'} = $row->{'package_name'};
    $data->{$procName}{$payMethod}{'method'} = $payMethod;
  }

  $self->{'packageData'} = $data;

  return $data;
}

1;
