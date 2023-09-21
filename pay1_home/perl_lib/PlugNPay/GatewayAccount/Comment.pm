package PlugNPay::GatewayAccount::Comment;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $username = shift;
  if ($username) {
    $self->setGatewayAccount($username);
    $self->load();
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

sub load {
  my $self = shift;
  my $username = shift || $self->getGatewayAccount();

  return $self->{'comments'}{$username} if ref($self->{'comments'}{$username}) eq 'HASH';

  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('pnpmisc', q/
      SELECT orderid, username,message as comment
      FROM comments
      WHERE username = ?
      ORDER BY orderid
  /,[$username], {})->{'result'};
  
  if ($rows > 0) {
    $self->{'comments'}{$username} = $rows->[0];
  }

  return $self->{'comments'}{$username};
}

sub loadMultiple {
  my $self = shift;
  my $usernames = shift || [$self->getGatewayAccount()];
  if (@{$usernames} < 1) {
    die "missing required load data: usernames\n";
  }

  my $dbs = new PlugNPay::DBConnection();
  my $rows = $dbs->fetchallOrDie('pnpmisc', q/
      SELECT orderid, username,message as comment
      FROM comments
      WHERE username IN (/ . join (',',map{'?'} @{$usernames}) . q/)
      ORDER BY orderid
  /,$usernames, {})->{'result'};

  return $rows;
}

sub save {
  my $self = shift;
  my $comment = shift;
  my $orderId = shift;
  my $username = shift || $self->getGatewayAccount();
  my $status = new PlugNPay::Util::Status(1);

  my @missing = ();

  push @missing, 'orderId' if !$orderId;
  push @missing, 'username' if !$username;
  push @missing, 'comment message' if !$comment;
  if (@missing > 0) {
    $status->setFalse();
    $status->setError('missing required data for comment save');
    $status->setErrorDetails('missing data: ' . join(', ', @missing));
    return $status;
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('pnpmisc', q/
      INSERT INTO comments
                  (orderid, username, message)
           VALUES (?,?,?)
      ON DUPLICATE KEY UPDATE message = VALUE(message)
    /, [$orderId, $username, $comment]);
  };

  if ($@) {
    $status->setFalse();
    $status->setError('failed to insert comment');
    $status->setErrorDetails($@);
  }

  return $status;
}

1;
