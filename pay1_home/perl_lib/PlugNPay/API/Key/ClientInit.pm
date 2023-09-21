package PlugNPay::API::Key::ClientInit;

use strict;
use PlugNPay::Util::Encryption::Random;
use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;
use PlugNPay::API::Key;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  my $gatewayAccount = $self->{'gatewayAccount'};
  if (!defined $gatewayAccount) {
    die('Gateway account not set.');
  }
  return $gatewayAccount;
}

sub setKeyName {
  my $self = shift;
  my $keyName = shift;
  $self->{'keyName'} = $keyName;
}

sub getKeyName {
  my $self = shift;
  my $keyName = $self->{'keyName'};
  if (!defined $keyName) {
    die('Key name not set.');
  }
  return $keyName;
}

sub useLink {
  my $self = shift;
  my $identifier = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnpmisc');
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT username,key_name
    FROM api_clientinit_link
    WHERE identifier = ?
    FOR UPDATE
  /); 

  $sth->execute($identifier);

  my $rows = $sth->fetchall_arrayref({});

  if (!@{$rows}) {
    return {keyName => undef, key => undef, gatewayAccount => undef};
  }

  $sth = $dbs->prepare('pnpmisc',q/
    DELETE FROM api_clientinit_link
    WHERE identifier = ?
  /);

  $sth->execute($identifier);

  $dbs->commit('pnpmisc');

  my $linkInfo = $rows->[0];

  my $gatewayAccount = $linkInfo->{'username'};
  my $keyName = $linkInfo->{'key_name'};

  my $keyInfo = new PlugNPay::API::Key({ gatewayAccount => $gatewayAccount, keyName => $keyName});
  my $key = $keyInfo->generate();
  $keyInfo->expireKey($keyInfo->getKeyName(), $keyInfo->getRevision()); # this is done so that key is unusable until unexpired by the merchant
  return {keyName => $keyName, key => $key, gatewayAccount => $gatewayAccount};
}

sub getLinkInfo {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT identifier,key_name
    FROM api_clientinit_link
    WHERE username = ?
  /);

  $sth->execute($self->getGatewayAccount());

  my $rows = $sth->fetchall_arrayref({});
  my %links = map { $_->{'key_name'} => $_->{'identifier'} } @{$rows};
  return \%links;
}

sub createLink {
  my $self = shift;
  
  my $successful;
  my $identifier;

  my $expireTime = new PlugNPay::Sys::Time('unix',time() + 900);
  my $expires = $expireTime->inFormat('db');

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('pnpmisc');

    my $existingIdentifiers = $self->getExistingLinkIdentifiers();

    do {
      $identifier = $self->randomAlphaNumLower(12);
    } while (grep { /^$identifier$/ } @{$existingIdentifiers});

    my $sth = $dbs->prepare('pnpmisc',q/
      INSERT INTO api_clientinit_link 
        (identifier,username,key_name,expires)
      VALUES
        (?,?,?,?)
      ON DUPLICATE KEY UPDATE
        identifier = VALUES(identifier),
        expires = VALUES(expires)
    /) or die('Could not insert link identifier into database. (prepare): ' . $DBI::errstr);

    $sth->execute($identifier,
                  $self->getGatewayAccount(),
                  $self->getKeyName(),
                  $expires) or die('Failed to insert link identifier into database. (execute): ' . $DBI::errstr);

  };

  if (!$@) {
    $successful = 1;
    $dbs->commit('pnpmisc');
  } else {
    $dbs->rollback('pnpmisc');
    die($@);
  }

  return $identifier;
}

sub getExistingLinkIdentifiers {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT identifier FROM api_clientinit_link
  /);

  $sth->execute();

  my $rows = $sth->fetchall_arrayref({});
  my @identifiers = map { $_{'identifier'} } @{$rows};
  return \@identifiers;
}

sub randomAlphaNumLower {
  my $self = shift;
  my $length = shift;
  
  my @chars = ('a'..'z','0'..'9');
  my @output;

  for (my $i = $length; $i > 0; $i--) {
    my $pos = rand(@chars);
    push @output,$chars[$pos];
  }

  return join('',@output);
}

1;
