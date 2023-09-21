package PlugNPay::PayScreens::Timer;

use strict;

use PlugNPay::GatewayAccount;
use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $settings = shift;

  $self->setGatewayAccount(lc $settings->{'username'});
  $self->setSessionID($settings->{'sessionID'});
  $self->setNewStartTime();
  $self->setNewTimeDuration($settings->{'timeDuration'});
  $self->setExists();
  if (defined $self->getGatewayAccount() && defined $self->getSessionID() && defined $self->getNewTimeDuration()) {
    if (!$self->getExists()) {
      $self->startSession();
    }
  }
  return $self;
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

sub setSessionID {
  my $self = shift;
  my $sessionID = shift;
  $self->{'sessionID'} = $sessionID;
}

sub getSessionID {
  my $self = shift;
  return $self->{'sessionID'};
}

sub setNewStartTime {
  my $self = shift;
  my $newStartTime = new PlugNPay::Sys::Time()->nowInFormat('db_gm');
  $self->{'newStartTime'} = $newStartTime;
}

sub getNewStartTime {
  my $self = shift;
  return $self->{'newStartTime'};
}

sub setNewTimeDuration {
  my $self = shift;
  my $timeDuration = shift;
  my $timeFormat;

  if ($timeDuration =~ /(\D+)/) {
    $timeFormat = $1;
    $timeDuration =~ s/\D//g;
  }
  if ($timeFormat eq 's') { #seconds
    $timeDuration = $timeDuration * 1000;
  }
  elsif ($timeFormat eq 'm') { #minutes
    $timeDuration = $timeDuration * 60000;
  }

  $self->{'timeDuration'} = $timeDuration;
}

sub getNewTimeDuration {
  my $self = shift;
  return $self->{'timeDuration'};
}

sub setExists {
  my $self = shift;
  $self->{'exists'} = 0;

  my $sessionId = $self->getSessionID();

  my $timerData = $self->getTimerData();
  my $userData = $timerData->{$sessionId};

  if ($userData) { 
    $self->{'exists'} = 1;
  }
}

sub getExists {
  my $self = shift;
  return $self->{'exists'};
}

sub getStartTime {
  my $self = shift;
  my $timerData = $self->getTimerData();

  return $timerData->{'start_time'};
}

sub getTimeDuration {
  my $self = shift;
  my $timerData = $self->getTimerData();

  return $timerData->{'time_duration'};
}

sub startSession {
  my $self = shift;
  my $username = $self->getGatewayAccount();
  my $sessionId = $self->getSessionID(); 
  my $newStartTime = $self->getNewStartTime(); 
  my $timeDuration = $self->getNewTimeDuration(); 

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    INSERT IGNORE INTO ui_payscreens_timer
      (username,pb_remote_session,start_time,time_duration)
    VALUES
      (?,?,?,?)
  /);
  $sth->execute($username,$sessionId,$newStartTime,$timeDuration) or die "Can't execute: $DBI::errstr";
}

sub getTimerData {
  my $self = shift;
  my $username = $self->getGatewayAccount();
  my $sessionId = $self->getSessionID();

  if (!defined $self->{'timer_results'}) {
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

    my $sth = $dbh->prepare(q{
      SELECT username,pb_remote_session,start_time,time_duration 
      FROM ui_payscreens_timer 
      WHERE username = ? AND pb_remote_session = ?
    });
    $sth->execute($username,$sessionId);

    my $results = $sth->fetchall_arrayref({}); 
    
    if (defined $results->[0]) {
      $self->{'timer_results'} = $results->[0];
    }
  }

  return $self->{'timer_results'};
}

sub getTimeRemaining {
  my $self = shift;
  my $startTime = $self->getStartTime(); 
  if (defined $startTime) {
    $startTime = new PlugNPay::Sys::Time('db_gm',$startTime)->inFormat('unix') * 1000;
  }
  my $currentTime = new PlugNPay::Sys::Time()->nowInFormat('unix') * 1000; 
  my $timeDuration = $self->getTimeDuration();

  my $timeRemaining = (($startTime + $timeDuration) - $currentTime);

  return $timeRemaining > 0 ? $timeRemaining : 0;
}

1;
