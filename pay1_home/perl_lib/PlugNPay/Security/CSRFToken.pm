package PlugNPay::Security::CSRFToken;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;
use PlugNPay::Util::UniqueID;
use PlugNPay::Security::GlobalSettings;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
}

sub getToken {
  my $self = shift;
  if (!defined $self->{'token'}) {
    $self->{'token'} = $self->_generateToken();
  }
  return $self->{'token'};
}

sub setToken {
  my $self = shift;
  my $token = shift;
  $self->{'token'} = $token;
  $self->_loadToken();
}

sub activity {
  my $self = shift;
  $self->setLastActiveTime(time());
  $self->_updateActivity();
}

sub setLastActiveTime {
  my $self = shift;
  my $time = shift;
  $self->{'lastActiveTime'} = $time;
}

sub getLastActiveTime {
  my $self = shift;
  return $self->{'lastActiveTime'};
}

sub setCreatedTime {
  my $self = shift;
  my $time = shift;
  $self->{'createdTime'} = $time;
}

sub getCreatedTime {
  my $self = shift;
  return $self->{'createdTime'};
}

sub verify {
  my $self = shift;
  return $self->verifyToken($self->getToken());
}

sub verifyToken {
  my $self = shift;

  my $uid = new PlugNPay::Util::UniqueID();

  # do a format validation before checking the db
  if ($uid->validate() && $self->_tokenExists()) {
    my $securityGlobalSettings = new PlugNPay::Security::GlobalSettings();
    my $sessionTimeout = $securityGlobalSettings->get('csrf_token_lifetime');
    my $now = new PlugNPay::Sys::Time();
    my $tokenExpires = new PlugNPay::Sys::Time();
    $tokenExpires->fromFormat('unix',$self->getLastActiveTime() + $sessionTimeout);

    return $now->isBefore($tokenExpires);
  }
}

sub _tokenExists {
  my $self = shift;
  return $self->{'exists'};
}

sub _loadToken {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT UNIX_TIMESTAMP(creation_time) as creation_time,
           UNIX_TIMESTAMP(last_active_time) as last_active_time
      FROM security_csrf_token
     WHERE token = ?
  /);

  $sth->execute($self->getToken());

  my $results = $sth->fetchall_arrayref({});

  delete $self->{'exists'};
  if ($results && $results->[0]) {
    $self->{'exists'} = 1;
    my $createdTime = $results->[0]{'creation_time'};
    my $lastActiveTime = $results->[0]{'last_active_time'};

    $self->setCreatedTime($createdTime);
    $self->setLastActiveTime($lastActiveTime);
  }
}

sub _updateActivity {
  my $self = shift;
  my $activeTime = $self->getLastActiveTime();
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    UPDATE security_csrf_token SET last_active_time = FROM_UNIXTIME(?) WHERE token = ?
  /);

  $sth->execute($activeTime,$self->getToken());
}

sub _generateToken {
  my $self = shift;
  my $token = new PlugNPay::Util::UniqueID();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    INSERT INTO security_csrf_token(token,creation_time,last_active_time) VALUES(?,FROM_UNIXTIME(?),FROM_UNIXTIME(?))
  /);

  $sth->execute($token->inHex(),$token->time()->inFormat('unix'),$token->time()->inFormat('unix'));

  $self->setCreatedTime($token->time()->inFormat('unix'));

  return $token->inHex();
}

sub _cleanupTokens {
  my $self = shift;
  my $now = new PlugNPay::Sys::Time()->inFormat('db');

  my $securityGlobalSettings = new PlugNPay::Security::GlobalSettings();
  my $sessionTimeout = $securityGlobalSettings->get('session_timeout');

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    DELETE FROM security_csrf_token WHERE last_active_time < DATE_SUB(?,INTERVAL ? SECOND)
  /);
  $sth->execute($now,$sessionTimeout);
}

sub destroyTokens {
  my $self = shift;
  my $expireTime = $ENV{'PNP_CSRF_EXPIRE_TIME'} || 5;
  my $currentTime = new PlugNPay::Sys::Time()->nowInFormat('unix');

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc', q/DELETE FROM security_csrf_token
                                       WHERE last_active_time < DATE_SUB(FROM_UNIXTIME(?), INTERVAL ? MINUTE)/);
  $sth->execute($currentTime,
                $expireTime) or die $DBI::errstr;
}

1;
