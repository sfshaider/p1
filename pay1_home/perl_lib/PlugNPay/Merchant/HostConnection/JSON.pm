package PlugNPay::Merchant::HostConnection::JSON;

use strict;
use PlugNPay::Merchant::Host;
use PlugNPay::Merchant::Credential;
use PlugNPay::Merchant::HostConnection::Protocol;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub protocolToJSON {
  my $self = shift;
  my $protocol = shift;

  return {
    'protocolID'  => $protocol->getProtocolID(),
    'protocol'    => $protocol->getProtocol(),
    'description' => $protocol->getDescription()
  };
}

sub hostConnectionToJSON {
  my $self = shift;
  my $hostConnection = shift;

  my $protocol = new PlugNPay::Merchant::HostConnection::Protocol();
  $protocol->loadProtocol($hostConnection->getProtocolID());

  my $credential = new PlugNPay::Merchant::Credential();
  $credential->loadMerchantCredential($hostConnection->getCredentialID());

  my $host = new PlugNPay::Merchant::Host();
  $host->loadMerchantHost($hostConnection->getHostID());

  return {
    'hostConnectionIdentifier' => $hostConnection->getIdentifier(),
    'credentialIdentifier'     => $credential->getIdentifier(),
    'hostIdentifier'           => $host->getIdentifier(),
    'merchantID'               => $hostConnection->getMerchantID(),
    'description'              => $hostConnection->getDescription(),
    'path'                     => $hostConnection->getPath(),
    'port'                     => $hostConnection->getPort(),
    'protocol'                 => $self->protocolToJSON($protocol)
  };
}

1;
