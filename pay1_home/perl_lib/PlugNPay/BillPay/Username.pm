package PlugNPay::BillPay::Username;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::BillPay::Security::Password;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $username = lc shift;
  $self->setUsername($username);
  if ($self->getUsername()) {
    $self->load();
  }

  return $self;
}

sub setUsername {
  my $self = shift;
  my $username = lc shift;
  $username =~ s/[^a-z0-9\-\_\@\.]//g;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setSubAccount {
  my $self = shift;
  my $subAccount = shift;
  $self->{'subAccount'} = $subAccount;
}

sub getSubAccount {
  my $self = shift;
  return $self->{'subAccount'};
}


sub setPassword {
  my $self = shift;
  my $password = shift;
  my $options = shift;

  if ($self->checkPasswordHistory($password) || $options->{'overrideHistoryCheck'}) {
    my $passwordHasher = new PlugNPay::BillPay::Security::Password();
    $passwordHasher->setUsername($self->getUsername());
    $passwordHasher->setPassword($password);
  
    my $passwordInfo = $passwordHasher->getHashInfo();
  
    $self->setPasswordHash($passwordInfo->{'hash'});
    $self->setPasswordType($passwordInfo->{'type'});
    $self->setPasswordSalt($passwordInfo->{'salt'});

    $self->savePassword();

    return 1;
  }
  
  return 0;
}

sub setPasswordHash {
  my $self = shift;
  my $hashedPassword = shift;
  $self->{'hashedPassword'} = $hashedPassword;
}

sub getPasswordHash {
  my $self = shift;
  return $self->{'hashedPassword'};
}

sub setPasswordSalt {
  my $self = shift;
  my $salt = shift || '';
  $self->{'passwordSalt'} = $salt;
}

sub getPasswordSalt {
  my $self = shift;
  return $self->{'passwordSalt'};
}

sub setPasswordType {
  my $self = shift;
  my $type = shift;

  # setType() returns false if a password type is invalid
  if (new PlugNPay::BillPay::Security::Password()->setType($type)) {
    $self->{'passwordType'} = $type;
  }
}

sub getPasswordType {
  my $self = shift;
  return $self->{'passwordType'};
}

sub setSecurityLevel {
  my $self = shift;
  my $securityLevel = shift;
  $self->{'securityLevel'} = $securityLevel;
}

sub getSecurityLevel {
  my $self = shift;
  return $self->{'securityLevel'};
}

sub verifyPassword {
  my $self = shift;
  my $password = shift;

  my $passwordChecker = new PlugNPay::BillPay::Security::Password();

  my $returnValue =  $passwordChecker->verifyPassword({
    username => $self->getUsername(),
    password => $password,
    salt => $self->getPasswordSalt(),
    type => $self->getPasswordType(),
    hash => $self->getPasswordHash()
  });

  if ($self->getPasswordType() ne $passwordChecker->getDefaultType()) {
    $self->setPassword($password,{overrideHistoryCheck => 1});   
  }

  return $returnValue;
}

sub setTemporaryPasswordFlag {
  my $self = shift;
  my $flag = (shift(@_) ? 1 : 0);
  $self->{'temporaryPasswordFlag'} = $flag;
}

sub getTemporaryPasswordFlag {
  my $self = shift;
  return $self->{'temporaryPasswordFlag'};
}

sub passwordIsExpired {
  my $self = shift;

  my $ninetyDaysAgo = time() - (60 * 60 * 24 * 90);

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('logindb',q/
    SELECT UNIX_TIMESTAMP(last_password_change) as last_password_change
      FROM acl_login
     WHERE login = ?
  /);

  $sth->execute($self->getUsername());

  my $results = $sth->fetchall_arrayref({});

  if ($results && $results->[0] && $results->[0]{'last_password_change'} < $ninetyDaysAgo) {
    return 1;
  }

  return 0;
}

sub setAccess {
  my $self = shift;
  my $directory_access = shift;
  $self->{'directory_access'} = $directory_access;
}

sub getAccess {
  my $self = shift;
  return $self->{'directory_access'};
}
  
sub addAccess {
  my $self = shift;
  my $dir = shift;
  my $access = $self->getAccess();
  my @accessArray;
  if (!defined $access || ref($access) ne 'ARRAY') {
    @accessArray = ();
  } else {
    @accessArray = @{$access};
  }

  push @accessArray,$dir;

  $self->setAccess(\@accessArray);

}

sub canAccess {
  my $self = shift;
  my $directory = shift;

  my %dirs = map {$_ => 1} @{$self->{'acl'}};
  if ($dirs{$directory} || $dirs{'all'}) {
    return 1;
  }
}


sub savePassword {
  my $self = shift;
  my $options = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $now = time();
  $dbs->begin('logindb');
  my $sth = $dbs->prepare('logindb',q/
     INSERT INTO acl_login
       ( login,username, password,
           password_salt,
           pwtype,
           last_password_change)
       VALUES (?,?,?,?,?,FROM_UNIXTIME(?))
       ON DUPLICATE KEY UPDATE password=?,password_salt=?,pwtype=?,last_password_change=FROM_UNIXTIME(?)
  /);

  $sth->execute(
    $self->getUsername(),
    $self->getUsername(),
    $self->getPasswordHash(),
    $self->getPasswordSalt(),
    $self->getPasswordType(),
    $now,
    $self->getPasswordHash(),
    $self->getPasswordSalt(),
    $self->getPasswordType(),
    $now
  ) or die $DBI::errstr;

  $self->savePasswordHistory();
  $self->saveAccess();
  $dbs->commit('logindb');
}

sub saveAccess {
  my $self = shift;

  my $access = $self->getAccess();
  my @params = ();
  my @values = ();
  
  foreach my $dir (@{$access}) {
    push @values,$self->getUsername();
    push @values,$dir;
    push @params,'(?,?)';
  }

  my $insert = 'INSERT INTO acl_dir
                             (login,directory)
                             VALUES ' . join(',',@params);
  
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('logindb');   
  my $sth = $dbs->prepare($insert);
  eval { $sth->execute(@values) or die $DBI::errstr; };
}

sub savePasswordHistory {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('logindb',q/
    INSERT INTO acl_login_password_history
      (login,password,password_salt,pwtype)
    SELECT login,password,password_salt,pwtype
      FROM acl_login
     WHERE login = ?
  /);
  
  eval {
    $sth->execute($self->getUsername());
  };
}
  
sub checkPasswordHistory {
  my $self = shift;
  my $password = shift;
  
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('logindb',q/
    SELECT login,password,password_salt,pwtype
      FROM acl_login_password_history
     WHERE login = ?
        OR login = ?
  /);

  $sth->execute($self->getUsername(),$self->getUsername());

  my $results = $sth->fetchall_arrayref({});

  my $passwordChecker = new PlugNPay::BillPay::Security::Password();
  $passwordChecker->setUsername($self->getUsername());

  if ($results) {
    foreach my $historicalPassword (@{$results}) {
      my $result =  $passwordChecker->verifyPassword({
        username => $self->getUsername(),
        password => $password,
        salt => $historicalPassword->{'password_salt'},
        type => $historicalPassword->{'pwtype'},
        hash => $historicalPassword->{'password'}
      });

      if ($result) {
        return 0;
      }
    }
  }
  return 1;
}

sub didLogIn {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('logindb',q/
    UPDATE acl_login
       SET last_login = FROM_UNIXTIME(?),
           login_failures = ?
     WHERE login = ?
  /)or die($DBI::errstr);

  $sth->execute(time(),0,$self->getUsername());
}

sub failedLogIn {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();

  # Increment failures
  my $sth = $dbs->prepare('logindb',q/
    UPDATE acl_login 
       SET login_failures = login_failures + 1 
     WHERE login = ?
  /) or die ($DBI::errstr);

  $sth->execute($self->getUsername());

  # Check failure count
  $sth = $dbs->prepare('logindb',q/
    SELECT login_failures
      FROM acl_login
     WHERE login = ?
  /);

  $sth->execute($self->getUsername());

  my $results = $sth->fetchall_arrayref({});

  # If there are more than 5 failed logins, lock the account.
  if ($results && $results->[0]{'login_failures'} > 5) {
    $self->lock();
  }
} 

sub _getLockedPrefix {
  return 'locked ';
}

sub lock {
  my $self = shift;
  
  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('logindb',q/
    UPDATE acl_login
       SET pwtype = CONCAT(?,pwtype)
     WHERE login = ?
       AND pwtype NOT LIKE ?
  /);

  $sth->execute($self->_getLockedPrefix(),$self->getUsername(),$self->_getLockedPrefix() . '%');
}

sub unlock {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('logindb',q/
    UPDATE acl_login
       SET pwtype = SUBSTR(pwtype,LENGTH(?)+1),
           login_failures = ?
     WHERE login = ?
       AND pwtype LIKE ?
  /);

  $sth->execute($self->_getLockedPrefix(),0,$self->getUsername(),$self->_getLockedPrefix() . '%');
}

sub load {
  my $self = shift;
  my $username = shift || $self->getUsername();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('logindb',q/
    SELECT login as username,
           password,
           password_salt as passwordSalt,
           username as gatewayAccount,
           pwtype as passwordType,
           seclevel as securityLevel,
           subacct as subAccount,
           tempflag as temporaryPasswordFlag
      FROM acl_login 
     WHERE login = ?
  /);

  $sth->execute($username);

  my $row = $sth->fetchrow_hashref;

  if ($row) {
    $self->setValuesFromHashRef($row);
  }

  $sth->finish;

  $self->loadACL();
}

sub loadACL {
  my $self = shift;
  my $username = $self->getUsername();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('logindb',q/
    SELECT directory
      FROM acl_dir
     WHERE login = ?
  /);

  $sth->execute($username);

  my $results = $sth->fetchall_arrayref({});

  my @dirs = map {$_->{'directory'}} @{$results};

  $self->{'acl'} = \@dirs;
  
}

sub setValuesFromHashRef {
  my $self = shift;
  my $hashRef = shift;

  if (ref($hashRef) eq 'HASH') {
    $self->setUsername($hashRef->{'username'});
    $self->setGatewayAccount($hashRef->{'gatewayAccount'});
    $self->setTemporaryPasswordFlag($hashRef->{'temporaryPasswordFlag'});
    $self->setPasswordHash($hashRef->{'password'});
    $self->setPasswordSalt($hashRef->{'passwordSalt'});
    $self->setPasswordType($hashRef->{'passwordType'});
    $self->setSecurityLevel($hashRef->{'securityLevel'});
  }
}

sub exists { # can be called as an object or at the package level
  my $self = shift;
  my $loginName = shift || $self;
  my $dbs = new PlugNPay::DBConnection->getHandleFor('logindb');
  my $sth = $dbs->prepare(q/
                             SELECT count(login) as `exists`
                             FROM acl_login
                             WHERE login = ?
                           /);
  $sth->execute($loginName);
  my $results = $sth->fetchall_arrayref({});

  if ($results && $results->[0]) {
    return $results->[0]{'exists'};
  }

}

1;
