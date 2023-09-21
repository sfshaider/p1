package PlugNPay::GatewayAccount::InternalID;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::Memcached;
use PlugNPay::Die;

#For pnpmisc customer_id (InternalID)
our $customerCache;
our $internalIDCache;

#For new trans DB internal merch id
our $accountCache;
our $idCache;



sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  $self->{'memcached'} = new PlugNPay::Util::Memcached('GatewayAccount::InternalID');

  # cache for transaction id table, not using memcached yet
  if (!defined $accountCache || !defined $idCache) {
    $accountCache = new PlugNPay::Util::Cache::LRUCache(10);
    $idCache = new PlugNPay::Util::Cache::LRUCache(10);
  }

  return $self;
}

 ###########
 # Methods #
 ###########

# renamed functions for clarity
sub getPNPMiscCustomerId {
  my $self = shift;
  my $username = shift;

  my $cacheKey = customersUsernameCacheKey($username);

  my $cachedID = $self->{'memcached'}->get($cacheKey);

  if ($cachedID ne '') {
    return $cachedID;
  }

  my $id = $self->_loadIDFromDatabase($username);

  if ($id > 0) {
    $self->{'memcached'}->set($cacheKey,$id,900);
  } else {
    die_metadata('failed to get id for username',{
      username => $username
    });
  }

  return $id;
}

sub getPNPMiscCustomerFromId {
  my $self = shift;
  my $id = shift;

  my $cacheKey = customersIDCacheKey($id);

  my $cachedUsername = $self->{'memcached'}->get($cacheKey);

  if ($cachedUsername ne '') {
    return $cachedUsername;
  }

  my $username = $self->_loadPNPMiscUsername($id);

  if ($username ne '') {
    $self->{'memcached'}->set($cacheKey, $username, 900);
  } else {
    die_metadata('username does not exist for id',{
      id => $id
    });
  }

  return $username;
}

sub getPNPTransactionMerchantId {
  my $self = shift;
  my $username = shift;

  my $cacheKey = merchantUsernameCacheKey($username);

  my $cachedID = $self->{'memcached'}->get($cacheKey);

  if ($cachedID ne '') {
    return $cachedID;
  }

  my $id = $self->_loadMerchantID($username);

  if ($id ne '') {
    $self->{'memcached'}->set($cacheKey, $id, 900);
  } else {
    die_metadata('failed to get merchant id',{
      username => $username
    });
  }

  return $id;
}

sub getPNPTransactionMerchantFromId {
  my $self = shift;
  my $id = shift;

  my $cacheKey = merchantIDCacheKey($id);

  my $cachedUsername = $self->{'memcached'}->get($cacheKey);

  if ($cachedUsername ne '') {
    return $cachedUsername;
  }

  my $username = $self->_loadMerchantByID($id);

  if ($username ne '') {
    $self->{'memcached'}->set($cacheKey, $username, 900);
  } else {
    die_metadata('username does not exist for id',{
      id => $id
    });
  }

  return $username;
}





# old functions for compatibility
sub getIdFromUsername {
  my $self = shift;
  return $self->getPNPMiscCustomerId(@_);
}

sub getUsernameFromId {
  my $self = shift;
  return $self->getPNPMiscCustomerFromId(@_);
}

sub getMerchantName {
  my $self = shift;
  return $self->getPNPTransactionMerchantFromId(@_);
}

sub getMerchantID {
  my $self = shift;
  return $self->getPNPTransactionMerchantId(@_);
}





# private functions
sub customersUsernameCacheKey {
  my $username = shift;
  return "customers-username-$username";
}

sub customersIDCacheKey {
  my $id = shift;
  return "customers-id-$id";
}

sub merchantUsernameCacheKey {
  my $username = shift;
  return "pnp-transaction-username-$username";
}

sub merchantIDCacheKey {
  my $id = shift;
  return "pnp-transaction-id-$id";
}

sub _loadIDFromDatabase {
  my $self = shift;
  my $username = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id
  	  FROM customer_id
     WHERE username = ?/);
  $sth->execute($username) or die $DBI::errstr;

  my $rows = $sth->fetchall_arrayref({});

  my $id;
  if($rows->[0]{'id'}) {
    $id = $rows->[0]{'id'};
  } else {
    $id = $self->_insertUsername($username);
  }

  if ($id <= 0) {
    die('invalid id loaded for username');
  }

  return $id;
}



sub _loadPNPMiscUsername {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT username
    FROM customer_id
    WHERE id = ?/);
  $sth->execute($id) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  #Set to cache only if user was selected
  my $username = '';
  if($rows->[0]{'username'}) {
    $username = $rows->[0]{'username'};
  } else {
    die('id does not exist for username');
  }

  return $username;
}

###############################
# For new transaction DB only #
###############################


sub _generateMerchantID {
  my $self = shift;
  my $username = shift;

  my $id = $self->getPNPMiscCustomerId($username);

  # get the id from customer_id table in pnpmisc
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
                              INSERT INTO merchant
                              (identifier,id)
                              VALUES (?,?)
                            /);
  $sth->execute($username,$id) or die $DBI::errstr;

  return $id;
}


sub _loadMerchantID {
  my $self = shift;
  my $username = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
    SELECT id
      FROM merchant
     WHERE identifier = ?/
  );
  $sth->execute($username) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  my $id;
  if ($rows->[0]{'id'}) {
    $id = $rows->[0]{'id'};
  } else {
    $id = $self->_generateMerchantID($username);
  }

  if ($id <= 0) {
    die('invalid id loaded for merchant');
  }

  return $id;
}

sub _loadMerchantByID {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnp_transaction',q/
    SELECT identifier
    FROM merchant
    WHERE id = ?/
  );
  $sth->execute($id) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  my $identifier;
  if ($rows->[0]{identifier}) {
    $identifier = $rows->[0]{'identifier'};
  } else {
    die('id does not exist for merchant');
  }

  return $identifier;
}

sub _insertUsername {
  my $self = shift;
  my $username = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
               INSERT INTO customer_id (username)
               VALUES (?)/);
  $sth->execute($username) or die $DBI::errstr;
  return $sth->{'mysql_insertid'};
}

sub _deleteTestData {
  my $self = shift;
  my $username = shift;

  return if $ENV{'DEVELOPMENT'} ne 'TRUE';

  my $id = $self->getPNPMiscCustomerId($username);

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpmisc',q/DELETE FROM customer_id WHERE username = ?/,[$username]);
  $dbs->executeOrDie('pnp_transaction',q/DELETE FROM merchant WHERE identifier = ?/,[$username]);

  $self->_deleteTestCacheData($username, $id);
}

sub _deleteTestCacheData {
  my $self = shift;
  my $username = shift;
  my $id = shift;

  return if $ENV{'DEVELOPMENT'} ne 'TRUE';

  my $m = $self->{'memcached'};
  $m->delete(customersUsernameCacheKey($username));
  $m->delete(merchantUsernameCacheKey($username));
  $m->delete(customersIDCacheKey($id));
  $m->delete(merchantIDCacheKey($id));
}

1;
