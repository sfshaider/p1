package PlugNPay::API::Key;

use strict;
use PlugNPay::Util::Encryption::Random;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::API::Key::Name;
use PlugNPay::API::Key::Revision;
use MIME::Base64;

# T501 mysql updates:
#
# CREATE TABLE `api_key_name` (
#   `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
#   `customer_id` int(11) unsigned NOT NULL,
#   `name` varchar(255) NOT NULL DEFAULT '',
#   PRIMARY KEY (`id`)
# ) ENGINE=InnoDB AUTO_INCREMENT=128 DEFAULT CHARSET=latin1;
#
# THEN!!!
#
# insert into api_key_name (customer_id,name) select distinct customer_id,key_name from api_key;
# update api_key set key_name_id = (select id from api_key_name where api_key_name.`customer_id` = api_key.customer_id and api_key_name.name = api_key.key_name);

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
 
  my $settings = shift;

  if ($settings) {
    $self->setGatewayAccount($settings->{'gatewayAccount'});
    if (defined $settings->{'customerID'}) {
      # override gateway account with customer id if it is set.
      $self->setCustomerID($settings->{'customerID'});
    }
    $self->setKeyName($settings->{'keyName'});
    $self->loadKey();
  }

  return $self;
}

sub getID {
  my $self = shift;
  if (!defined $self->{'id'}) {
    die('API Key ID not loaded.');
  }
  return $self->{'id'};
}

sub setID {
  my $self = shift;
  $self->{'id'} = shift;
}

# this is now a convenience function.  use the customer id functions below instead.
sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = lc shift;
  $gatewayAccount =~ s/[^a-z0-9]//g;
  my $merchant = new PlugNPay::GatewayAccount::InternalID();
  my $id = $merchant->getIdFromUsername($gatewayAccount);
  $self->setCustomerID($id);
}

# this is now a convenience function.  use the customer id functions below instead.
sub getGatewayAccount {
  my $self = shift;
  my $merchant = new PlugNPay::GatewayAccount::InternalID();
  return $merchant->getUsernameFromId($self->getCustomerID());
}

sub setCustomerID {
  my $self = shift;
  my $customerID = shift;
  $customerID =~ s/[^\d]//g;

  if ($customerID ne $self->{'customerID'}) {
    $self->_reset();
  }

  $self->{'customerID'} = $customerID;
}

sub getCustomerID {
  my $self = shift;
  return $self->{'customerID'};
}

sub getKeyNameID {
  my $self = shift;

  if (!defined $self->{'keyNameID'}) {
    my $key = new PlugNPay::API::Key::Name();
    $key->setName($self->getKeyName());
    $key->setCustomerID($self->getCustomerID());
    $key->load();
  
    $self->{'keyNameID'} = $key->getID();
  }

  return $self->{'keyNameID'};
}

sub setKeyName {
  my $self = shift;
  my $keyName = shift;
  $keyName =~ s/[^a-zA-Z0-9_-]//g;

  if ($keyName ne $self->{'keyName'}) {
    $self->_reset();
  }

  $self->{'keyName'} = $keyName;
}


sub getKeyName {
  my $self = shift;
  return $self->{'keyName'};
}

sub _reset {
  my $self = shift;
  $self->{'keyNameID'} = undef;
  $self->{'current'} = undef;
}

sub keyNameExists {
  my $self = shift;

  my $keyName = new PlugNPay::API::Key::Name();
  $keyName->setName($self->{'keyName'});
  $keyName->setCustomerID($self->{'customerID'});
  if ($keyName->exists()) {
    $self->{'currentKeyName'} = $keyName;
    return 1;
  }
}

sub createKeyName {
  my $self = shift;

  my $keyName = new PlugNPay::API::Key::Name();
  $keyName->setName($self->{'keyName'});
  $keyName->setCustomerID($self->{'customerID'});
  $keyName->save();

  $self->{'currentKeyName'} = $keyName;
}

sub getCurrentKeyName {
  my $self = shift;

  if (!defined $self->{'currentKeyName'}) {
    my $keyName = new PlugNPay::API::Key::Name();
    $keyName->setName($self->{'keyName'});
    $keyName->setCustomerID($self->{'customerID'});
    $keyName->load();
   
    $self->{'currentKeyName'} = $keyName;
  }

  return $self->{'currentKeyName'};
}

sub getCurrent {
  my $self = shift;

  my $keyName = $self->getCurrentKeyName();

  if (!defined $self->{'current'}) {
    my $keyNameID = $keyName->getID();
    my $current = new PlugNPay::API::Key::Revision();
    $current->setKeyNameID($keyNameID);
    $current->load();

    $self->{'current'} = $current;
  }

  return $self->{'current'};
}

sub setRevision {
  my $self = shift;
  my $revision = shift;
  my $current = $self->getCurrent();
  return $current->setRevision($revision);
}

sub getRevision {
  my $self = shift;
  my $current = $self->getCurrent();
  return $current->getRevision();
}

sub incrementRevision {
  my $self = shift;

  my $current = $self->getCurrent();
  $current->setRevision($current->getRevision() + 1);
}

sub getKey {
  my $self = shift;

  my $current = $self->getCurrent();
  return $current->getKey();
}

sub generate {
  my $self = shift;

  if (!$self->keyNameExists()) {
    $self->createKeyName();
  }

  my $current = $self->getCurrent();
  my $key = $current->generate();
  return $key;
}

sub verifyKey {
  my $self = shift;
  my $key = shift;
  $key =~ s/[^a-zA-Z0-9\+\/]//g;

  my $current = $self->getCurrent();

  return $current->verifyKey($key);
}

# adding to minimize code changes, renaming to keep consistent naming convention for loading and saving data.
sub saveKey {
  my $self = shift;
  return $self->save(@_);
}

sub save {
  my $self = shift;

  my $keyName = new PlugNPay::API::Key::Name();
  $keyName->setName($self->{'keyName'});
  $keyName->setCustomerID($self->{'customerID'});
  $keyName->save();

  my $current = $self->getCurrent();
  $current->save();
}

sub loadKey {
  my $self = shift;
  return $self->load();
}

sub load {
  my $self = shift;

  my $current = $self->getCurrent();
  return $current->load();
}

sub getKeyRevisionFor {
  my $self = shift;
  my $keyName = shift;
  my $revision = shift;

  my $key = new PlugNPay::API::Key::Name();
  $key->setName($keyName);
  $key->setCustomerID($self->getCustomerID());
  $key->load();

  my $keyNameID = $key->getID();

  my $keyRevision = new PlugNPay::API::Key::Revision();
  $keyRevision->setKeyNameID($keyNameID);
  $keyRevision->setRevision($revision);

  return $keyRevision;
}

sub expireKey {
  my $self = shift;
  my $keyName = shift;
  my $revision = shift;

  my $keyRevision = $self->getKeyRevisionFor($keyName,$revision);
  $keyRevision->expire();
}

sub setKeyExpiration {
  my $self = shift;
  my $keyName = shift;
  my $revision = shift;
  my $time = shift; # format: 'yyyy/mm/dd HH:mm:ss' (24 hour time) OR undef, if undef, expiration will be removed and the key will be active again.

  my $keyRevision = $self->getKeyRevisionFor($keyName,$revision);
  $keyRevision->setKeyExpiration($time);
}

sub deleteKey {
  my $self = shift;
  my $keyName = shift;
  my $revision = shift;

  $self->setKeyName($keyName);

  # if revision is not defined, delete the key name and all revisions.
  # if revision is defined, delete just the revision.
  my $current = $self->getCurrent();
  $current->delete($revision);

  if (!defined $revision) {
    # delete the key name
    my $keyName = $self->getCurrentKeyName();
    $keyName->delete();
  }
}

sub listApiKeys {
  my $self = shift;

  my $result = {};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT akn.name as key_name, ak.revision as revision, ak.expires as expires
        FROM api_key ak, api_key_name akn
       WHERE ak.key_name_id = akn.id AND akn.customer_id = ?
       ORDER BY akn.name,ak.revision DESC
    /);
  
    $sth->execute($self->getCustomerID());
    $result = $sth->fetchall_arrayref({});
  };

  if ($@) {
    die('Failed to load list of api keys.');
  }

  return $result;
}

sub genRandKey {
  my $self = shift;
  die('You really do not want to do this.  Come up with a descriptive name.');
}

1;
