package PlugNPay::API::Key::Revision;

use strict;
use PlugNPay::Util::Encryption::Random;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Security::Password;
use PlugNPay::GatewayAccount::InternalID;
use PlugNPay::Util::StackTrace;
use PlugNPay::API::Key::Name;
use MIME::Base64;
use PlugNPay::Logging::DataLog;

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

sub setKeyNameID {
  my $self = shift;
  my $keyNameID = shift;
  $self->{'keyNameID'} = $keyNameID;
}

sub getKeyNameID {
  my $self = shift;
  return $self->{'keyNameID'};
}

# for compatibility until this is permanent.
sub getKeyName {
  my $self = shift;
  my $kn = new PlugNPay::API::Key::Name();
  $kn->setID($self->getKeyNameID());
  $kn->load();
  return $kn->getName();
}

# for compatibility until this is permanent.
sub getUsername {
  my $self = shift;

  my $kn = new PlugNPay::API::Key::Name();
  $kn->setID($self->getKeyNameID());
  $kn->load();
  my $customerID = $kn->getCustomerID();
  my $internalID = new PlugNPay::GatewayAccount::InternalID();
  return $internalID->getUsernameFromId($customerID);
}


sub setRevision {
  my $self = shift;
  my $revision = shift;
  $self->{'revision'} = $revision;
}

sub getRevision {
  my $self = shift;
  return $self->{'revision'};
}

sub incrementRevision {
  my $self = shift;
  $self->setRevision($self->getRevision() + 1);
}

sub setKey {
  my $self = shift;
  my $key = shift;

  # note that this uses key name for the password hashing as it will be more unique than the gateway account
  my $passwordHasher = new PlugNPay::Security::Password();
  $passwordHasher->setUsername($self->getKeyName());
  $passwordHasher->setPassword($key);

  my $passwordInfo = $passwordHasher->getHashInfo();

  $self->setHashedKey($passwordInfo->{'hash'});
  $self->setHashType($passwordInfo->{'type'});
  $self->setSalt($passwordInfo->{'salt'});

  $self->save();
}

sub getKey {
  my $self = shift;
  return $self->{'key'};
}

sub setHashedKey {
  my $self = shift;
  my $hashedKey = shift;
  $self->{'hashedKey'} = $hashedKey;
}

sub getHashedKey {
  my $self = shift;
  return $self->{'hashedKey'};
}

sub setSalt {
  my $self = shift;
  my $salt = shift;
  $self->{'salt'} = $salt;
}

sub getSalt {
  my $self = shift;
  return $self->{'salt'};
}

sub generate {
  my $self = shift;
  my $expireOldKeyAfter = shift; # seconds

  my $newKey = encode_base64(new PlugNPay::Util::Encryption::Random()->random(30));
  chomp $newKey;

  my $time = new PlugNPay::Sys::Time();

  if ($expireOldKeyAfter !~ /^\d+$/) {
    $time->addSeconds(3600); # default of 1 hour
  } else {
    $time->addSeconds($expireOldKeyAfter);
  }

  my $dbs = new PlugNPay::DBConnection();
  $dbs->do('pnpmisc','BEGIN');
  $self->setKeyExpiration($time->inFormat('db_gm'));

  $self->incrementRevision();
  $self->setKey($newKey);
  $dbs->do('pnpmisc','COMMIT');


  return $newKey;
}

sub setHashType {
  my $self = shift;
  my $type = shift;
  $self->{'hashType'} = $type;
}

sub getHashType {
  my $self = shift;
  return $self->{'hashType'};
}

sub verifyKey {
  my $self = shift;
  my $key = shift;

  my $passwordChecker = new PlugNPay::Security::Password();

  my $returnValue = $passwordChecker->verifyPassword({
    username => $self->getKeyName(),
    password => $key,
    salt => $self->getSalt(),
    type => $self->getHashType(),
    hash => $self->getHashedKey()
  });

  if ($self->getHashType() ne $passwordChecker->getDefaultType()) {
    $self->setHashedKey($key);
  }

  return $returnValue;
}

# adding to minimize code changes, renaming to keep consistent naming convention for loading and saving data.
sub saveKey {
  my $self = shift;
  return $self->save(@_);
}

sub save {
  my $self = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      INSERT INTO api_key (
                    key_name_id,revision,
                    hashed_key,hash_type,salt,
                    username,key_name
                  )
           VALUES (?,?,?,?,?,?,?)
    /) or die($DBI::errstr);
  
    $sth->execute($self->getKeyNameID(),
                  $self->getRevision(),
                  $self->getHashedKey(),
                  $self->getHashType(),
                  $self->getSalt(),
                  $self->getUsername(),
                  $self->getKeyName()
                 ) or die($DBI::errstr);
  
    $self->loadKey();
  };

  if ($@) {
    die('Failed to save key revision.');

  }
}

# adding to minimize code changes, renaming to keep consistent naming convention for loading and saving data.
sub loadKey {
  my $self = shift;
  return $self->load(@_);
}

sub load {
  my $self = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT id,key_name_id,revision,hashed_key,hash_type,salt
        FROM api_key
       WHERE (id = ? OR key_name_id = ?)
         AND (expires > UTC_TIMESTAMP() OR expires is NULL)
       ORDER BY revision DESC
    /) or die($DBI::errstr);
  
    $sth->execute($self->{'id'},$self->{'keyNameID'}) or die($DBI::errstr);
  
    my $result = $sth->fetchall_arrayref({}) or die($DBI::errstr);
  
    if ($result && defined $result->[0]) {
      my $row = $result->[0];
      $self->setID($row->{'id'});
      $self->setKeyNameID($row->{'key_name_id'});
      $self->setRevision($row->{'revision'});
      $self->setHashedKey($row->{'hashed_key'});
      $self->setHashType($row->{'hash_type'});
      $self->setSalt($row->{'salt'});
    }
  };

  if ($@) {
    die('Failed to load api key revision.');
  }
}

sub expire {
  my $self = shift;

  my $keyNameID = $self->{'keyNameID'};
  my $revision = $self->{'revision'};

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    UPDATE api_key SET expires = UTC_TIMESTAMP()
     WHERE key_name_id = ? 
       AND revision = ?
  /);

  $sth->execute($keyNameID,$revision);
}

sub setKeyExpiration {
  my $self = shift;
  my $time = shift; # format: 'yyyy/mm/dd HH:mm:ss' (24 hour time) OR undef, if undef, expiration will be removed and the key will be active again.

  my $keyNameID = $self->{'keyNameID'};
  my $revision = $self->{'revision'};

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    UPDATE api_key
       SET expires = ?
     WHERE key_name_id = ?
       AND revision = ?
  /);

  $sth->execute($time,$keyNameID,$revision);
}

sub delete {
  my $self = shift;
  my $revision = shift;

  my $keyNameID = $self->{'keyNameID'};

  my @placeholders;

  my $query = q/
    DELETE FROM api_key
     WHERE key_name_id = ?
  /;

  push(@placeholders, $keyNameID);

  if ($revision) {
    $query .= q/
      AND revision = ?
    /;
    push(@placeholders, $revision);
  }

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',$query) or die($DBI::errstr);

  $sth->execute(@placeholders) or die($DBI::errstr);
}

sub listAPIKeys {
  my $self = shift;

  my $result;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT key_name_id,revision,expires
        FROM api_key
       WHERE key_name_id = ?
       ORDER BY revision DESC
    /);
  
    $sth->execute($self->{'keyNameID'});
    $result = $sth->fetchall_arrayref({});
  };

  if ($@) {
    die('Failed to load api key revision list');
  }

  return $result;
}

sub genRandKey {
  my $self = shift;
  die('This is a stupid feature.  Do not use it.');
}

1;
