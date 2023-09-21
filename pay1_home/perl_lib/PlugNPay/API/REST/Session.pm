package PlugNPay::API::REST::Session;

use strict;
use PlugNPay::Logging::MessageLog;
use PlugNPay::Util::UniqueID;
use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->setSingleUse();
  my $id = shift;
  if (defined $id) {
    $self->setSessionID($id);
    my $session = $self->loadSessionByID($id);
    $self->setAvailableSessions($session);
  }
  
  return $self;
}

sub setAvailableSessions {
  my $self = shift;
  my $session_keys = shift;
  $self->{'session_keys'} = $session_keys;
}

sub getAvailableSessions {
  my $self = shift;
  return $self->{'session_keys'};
}

sub setSessionID {
  my $self = shift;
  my $session_id = shift;
  $self->{'session_id'} = $session_id;
}

sub getSessionID {
  my $self = shift;
  return $self->{'session_id'};
}

sub authenticate {
  my $self = shift;

  #Delete all invalid sessions from DB before authenticating/invalidating next batch.
  $self->deleteInvalidSessions();
  my $id = $self->getSessionID();
 
  #load available sessions from DB
  my $sessions = $self->getAvailableSessions();
  $self->invalidateExpiredSessions($sessions);
  my $requestedSession = $sessions->{$id};

  my $timeObj = new PlugNPay::Sys::Time();
  my $time = $timeObj->inFormat('unix');
  my $pnpTime = new PlugNPay::Sys::Time();
  $pnpTime->fromFormat('db',$requestedSession->{'exp_time'});
  my $expTime = $pnpTime->inFormat('unix');
  
  if (defined $requestedSession && $requestedSession->{'valid'}) {
    #Set Gateway Account from database load
    $self->setGatewayAccount($requestedSession->{'gatewayAccount'});

    if($expTime > $time) {
      #Not Expired
      if (!$requestedSession->{'multi_use'}) {
        $self->invalidateSession($id);
      }

      return {'status'=>1, 'message' => 'Session Authenticated'};
    } else {
      #Expired
      $self->_logBadSession($id);
      return {'status'=>0, 'message'=>'Session Expired'};
    }
  } else {
    #Invalid session OR session doesn't exist
    $self->_logBadSession($id);
    return {'status' => 0,'message'=>'Bad Session'};
  }
}

sub invalidateExpiredSessions {
  my $self = shift;
  my $sessions = shift;
  
  #Make SQL Transaction
  my $dbs = new PlugNPay::DBConnection();
  $dbs->do('pnpmisc','BEGIN');

  foreach my $id (keys %{$sessions} ) {
    my $session = $sessions->{$id};
    my $timeObj = new PlugNPay::Sys::Time();
    my $time = $timeObj->inFormat('unix');
    my $pnpTime = new PlugNPay::Sys::Time();
    $pnpTime->fromFormat('db',$session->{'exp_time'});
    my $expTime = $pnpTime->inFormat('unix');
    if ($expTime < $time ) {
      $self->invalidateSession($id);
    }
  }
  $dbs->do('pnpmisc','COMMIT');
}

sub invalidateSession {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           UPDATE api_session
                           SET valid = ?
                           WHERE session_id = ?
                           /);
  $sth->execute('0',$id) or die $DBI::errstr;

  return 1;
}

sub loadSessionByID {
  my $self = shift;
  my $id = shift;

  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           SELECT session_id,exp_time,multi_use,valid,username
                           FROM api_session
                           WHERE session_id = ?
                           /);
  $sth->execute($id) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $ids = {};

  #Turn rows into hash!
  foreach my $row (@{$rows}) {
    $ids->{$row->{'session_id'}}{'exp_time'} = $row->{'exp_time'};
    $ids->{$row->{'session_id'}}{'multi_use'} = $row->{'multi_use'};
    $ids->{$row->{'session_id'}}{'valid'} = $row->{'valid'};
    $ids->{$row->{'session_id'}}{'gatewayAccount'} = $row->{'username'};
  }

  return $ids;
}

sub setGatewayAccount {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'username'};
}

sub generateSessionID {
  my $self = shift;
  my $gatewayAccountName = shift;
  $self->setGatewayAccount($gatewayAccountName);

  my $sesID = new PlugNPay::Util::UniqueID();
  $self->{'session_id'} = $sesID->inHex();
  $self->saveSessionID();
  return $self->{'session_id'};
}

sub saveSessionID {
  my $self = shift;
  my $saved = 0;
  my $time = new PlugNPay::Sys::Time();
  my $dbs = new PlugNPay::DBConnection();
  $time->addHours(4);

  $dbs->do('pnpmisc','BEGIN');

  # start of transaction
  eval {
    unless (defined $self->getExpireTime()) {
      my $expTime = $time->inFormat('db_gm');
      $self->setExpireTime($expTime);
    }
    $saved = $self->_saveSessionIDWithExpTime();
    $self->_saveDomains();
  };
  # end of transaction

  if ($@) {
    $dbs->do('pnpmisc','ROLLBACK');
  } else {
    $dbs->do('pnpmisc','COMMIT');
  }

  return $saved;
}

sub _saveSessionIDWithExpTime {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           INSERT INTO api_session 
                           (session_id,exp_time,multi_use,valid,username)
                           VALUES (?,?,?,?,?)
                           /);
  $sth->execute($self->{'session_id'},$self->getExpireTime(),$self->{'multiUse'},1,$self->getGatewayAccount()) or die $DBI::errstr;
  return 1;
}

sub setExpireTime {
  my $self = shift;
  $self->{'exp_time'} = shift;
}

sub getExpireTime {
  my $self = shift;
  return $self->{'exp_time'};
}

sub checkTimeLeft {
  my $self = shift;
  my $sesID = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           SELECT exp_time
                           FROM api_session
                           WHERE session_id = ?
                           /);
  $sth->execute($sesID) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $exp = $rows->[0]{'exp_time'};
  my $time = new PlugNPay::Sys::Time();
  my $currentTime = $time->inFormat('unix');
  $time->fromFormat('db',$exp);
  my $expTime = $time->inFormat('unix');
  my $timeLeft = $expTime - $currentTime;
  if ($timeLeft < 1) {
    $self->invalidateSession($sesID);
    return {'status' => 'invalid', 'time_left' => 0};
  } else {
    return {'status' => 'valid','time_left' => $timeLeft};
  }
}

sub setMultiUse {
  my $self = shift;
  $self->{'multiUse'} = 1;
}

sub setSingleUse {
  my $self = shift;
  $self->{'multiUse'} = 0;
}

sub deleteInvalidSessions {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           DELETE FROM api_session
                           WHERE valid = ?
                           /);
  $sth->execute(0) or die $DBI::errstr;

  return 1;
}

sub _logBadSession {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           SELECT session_id 
                           FROM api_session
                           WHERE valid = ?
                           /);
  $sth->execute(0) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $logger = new PlugNPay::Logging::MessageLog();
  foreach my $row (@{$rows}) {
    $logger->log('Session Key ' . $row->{'session_id'} . ' was expired or does not exist.', {'vendor' => 'PlugNPay','context' => 'REST API'});
  }

  return 1;
}

sub setValidDomains {
  my $self = shift;
  $self->{'domains'} = shift;
}

sub getValidDomains {
  my $self = shift;
  my $id = shift;
  if (defined $id) {
    $self->{'domains'} = $self->loadDomains($id); 
  }
  
  return $self->{'domains'};
}

sub _saveDomains {
  my $self = shift;
  my $domains = $self->getValidDomains();
  my $session = $self->{'session_id'}; 

  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           INSERT INTO api_session_domains
                           (session_id,domain)
                           VALUES (?,?)
                           /);
  foreach my $domain (@{$domains}) {
    $domain =~ /^a-zA-Z0-9\.\-\_\/\:/;
    $sth->execute($session,$domain) or die $DBI::errstr;
  }
  $sth->finish();

  return 1;
}

sub loadDomains {
  my $self = shift;
  my $session = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                          SELECT domain
                          FROM api_session_domains
                          WHERE session_id = ?
                          /);
  $sth->execute($session) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my @domains = ();
  foreach my $row (@{$rows}) {
    push @domains, $row->{'domain'};
  }

  return \@domains;
}

###################################################################
# This function is currently used to check CORS preflight request #
# The session ID isn't checked due to the fact that this OPTIONS  #
# Request doesn't contain the X-Gateway-Session header            #
###################################################################
sub domainExists {
  my $self = shift;
  my $domain = shift;

  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           SELECT count(domain) AS 'exists'
                           FROM api_session_domains
                           WHERE domain = ?
                           /);
  $sth->execute($domain);
  my $rows = $sth->fetchall_arrayref({});
  my $exists = $rows->[0]{'exists'} > 0;

  return $exists;
}

1;
