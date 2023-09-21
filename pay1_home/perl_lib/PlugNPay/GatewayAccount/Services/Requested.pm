package PlugNPay::GatewayAccount::Services::Requested;

use strict;
use warnings;

use PlugNPay::GatewayAccount::Services::Service;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $input = shift;

  if ($input->{'gatewayAccount'}) { # gatewayAccount Object
    $self->setGatewayAccount($input->{'gatewayAccount'});
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $ga = shift;
  if (ref($ga) ne 'PlugNPay::GatewayAccount') {
    die('input to setGatewayAccount is not a gateway account object');
  }
  $self->{'gatewayAccount'} = $ga;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub request {
  my $self = shift;
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'} || $self->getGatewayAccount(); # gatewayAccount object
  if (ref($gatewayAccount) ne 'PlugNPay::GatewayAccount') {
    die('gatewayAccount is not a gateway account object');
  }

  my $service = $input->{'service'}; # service object
  if (ref($service) ne 'PlugNPay::GatewayAccount::Services::Service') {
    die('service is not a service object');
  }

  my $serviceId = $service->getId();
  my $customerId = $gatewayAccount->getCustomerId();

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpmisc',q/
    INSERT IGNORE INTO customer_requested_service (customer_id, service_id) values (?,?)
  /,[$customerId,$serviceId]);
}

sub getRequested {
  my $self = shift;
  my $input = shift;

  my $gatewayAccount = $input->{'gatewayAccount'} || $self->getGatewayAccount(); # gatewayAccount object
  if (ref($gatewayAccount) ne 'PlugNPay::GatewayAccount') {
    die('gatewayAccount is not a gateway account object');
  }

  my $customerId = $gatewayAccount->getCustomerId();
  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc',q/
    SELECT service_id FROM customer_requested_service WHERE customer_id = ?
  /,[$customerId],{});
  my $data = $result->{'result'};
  my %servicesRequested;
  foreach my $serviceRow (@{$data}) {
    my $serviceId = $serviceRow->{'service_id'};
    my $service = new PlugNPay::GatewayAccount::Services::Service({ id => $serviceId });
    $servicesRequested{$service->getHandle()} = $service;
  }

  return \%servicesRequested;
}


1;
