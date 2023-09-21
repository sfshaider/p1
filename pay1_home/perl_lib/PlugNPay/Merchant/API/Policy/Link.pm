package PlugNPay::Merchant::API::Policy::Link;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub linkPolicyToKey {
  my $self = shift;
  my $params = shift;

  my $policyObj = $params->{'policy'};
  my $keyObj = $params->{'key'};

  $self->_checkPolicyAndKey($policyObj,$keyObj);

  eval {
    my $dbs = new PlugNPay::DBConnection();

    my $sth = $dbs->prepare('pnpmisc',q/
      INSERT IGNORE INTO merchant_api_policy_api_key_link
        (policy_id,key_id)
      VALUES (?,?)
    /) or die($DBI::errstr);

    $sth->execute($policyObj->getID(),$keyObj->getID()) or die($DBI::errstr);
  };

  if ($@) {
    die('Failed to link api key to policy.  Database error.');
  }
}

sub unlinkPolicyFromKey {
  my $self = shift;
  my $params = shift;

  my $policyObj = $params->{'policy'};
  my $keyObj = $params->{'key'};

  $self->_checkPolicyAndKey($policyObj,$keyObj);

  eval {
    my $dbs = new PlugNPay::DBConnection();

    my $sth = $dbs->prepare('pnpmisc',q/
      DELETE FROM merchant_api_policy_api_key_link
            WHERE policy_id = ? and key_id = ?
    /);

    $sth->execute($policyObj->getID(),$keyObj->getID()) or die($DBI::errstr);
  };

  if ($@) {
    die('Failed to unlink api key from policy.  Database error.');
  }
}

sub linkPolicyToContext {
  my $self = shift;
  my $params = shift;

  my $policyObj = $params->{'policy'};
  my $contextObj = $params->{'context'};


}

sub _checkPolicyAndKey {
  my $self = shift;
  my $policyObj = shift;
  my $keyObj = shift;

  if ($keyObj->getGatewayAccount() ne $policyObj->getGatewayAccount()) {
    die('Can not link keys and policies across gateway accounts.');
  }

  if (!$keyObj->getID()) {
    die("Key object is not persistently stored.");
  }

  if (!$policyObj->getID()) {
    die("Policy object is not persistently stored.");
  }
}

1;
