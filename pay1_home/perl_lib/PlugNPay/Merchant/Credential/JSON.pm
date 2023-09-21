package PlugNPay::Merchant::Credential::JSON;

use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub credentialToJSON {
  my $self = shift;
  my $credential = shift;

  return {
    'credentialIdentifier'  => $credential->getIdentifier(),
    'merchantID'            => $credential->getMerchantID(),
    'username'              => $credential->getUsername(),
    'passwordToken'         => $credential->getPasswordToken(),
    'certificate'           => $credential->getCertificate()
  };
}

1;
