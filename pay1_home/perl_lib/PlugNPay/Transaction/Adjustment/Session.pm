package PlugNPay::Transaction::Adjustment::Session;

use strict;

use PlugNPay::DBConnection;
use PlugNPay::Util::UniqueID;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $options = shift;
  if ($options && $options->{'gatewayAccount'}) {
    $self->setGatewayAccount($options->{'gatewayAccount'});
  }
  if ($options && $options->{'session'}) {
    $self->setSession($options->{'session'});
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

sub setSession {
  my $self = shift;
  my $session = shift;
  $self->{'session'} = $session;
}

sub getSession {
  my $self = shift;
  return $self->{'session'};
}

sub start {
  my $self = shift;

  $self->cleanup();

  my $sessionID;
  # only create a session if username exists.
  if ($self->getGatewayAccount()) {
    $sessionID = new PlugNPay::Util::UniqueID()->inHex();

    # save the current session to the object so we can possibly save a few database queries later
    $self->setSession($sessionID);

    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

    my $sth = $dbh->prepare(q/
      INSERT INTO adjustment_session
        (session_id, session_start, username)
      VALUES (?,FROM_UNIXTIME(?),?)
    /);

    $sth->execute($sessionID,time(),$self->getGatewayAccount()) or die($DBI::errstr);
  }

  return $sessionID;
}

sub cleanup {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    DELETE FROM adjustment_session
          WHERE session_timestamp < (NOW() - INTERVAL 1 HOUR);
  /);

  $sth->execute();
}

sub verify {
  my $self = shift;
  my $sessionID = shift || $self->getSession();

  # save a couple queries to the database if the session being checked is the current session
  if (defined $self->getSession()) {
    if ($sessionID eq $self->getSession()) {
      return 1;
    }
  }

  # uniqueID's are validatable, so if it's not valid, return false
  my $uniqueID = new PlugNPay::Util::UniqueID();
  $uniqueID->fromHex($sessionID);
  if (!$uniqueID->validate()) {
    return 0;
  }

  $self->cleanup();

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
    SELECT count(session_id) AS `exists`
      FROM adjustment_session
     WHERE session_id = ?
  /);

  $sth->execute($sessionID);

  my $results = $sth->fetchrow_hashref;

  if ($results) {
    return $results->{'exists'};
  }

  return 0;
}

1;
