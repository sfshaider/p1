package PlugNPay::MobileClient;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::IP;
use PlugNPay::GatewayAccount;
use PlugNPay::Username;
use PlugNPay::Util::RandomString;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $gatewayAccount = shift;

  if ($gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
    $self->load();
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;

  if (PlugNPay::GatewayAccount::exists($gatewayAccount)) {
    $self->{'gatewayAccount'} = $gatewayAccount;
  }
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'}; 
}

sub setMobileClientUsername {
  my $self = shift;
  my $mobileClientUsername = shift;
  $self->{'mobileClientUsername'} = $mobileClientUsername;
}

sub getMobileClientUsername {
  my $self = shift;
  return $self->{'mobileClientUsername'};
}

sub addPermittedNetworkAddress {
  my $self = shift;
  my $ip = shift;
  my $netmask = shift;

  $netmask =~ s/[^\d]//g;
  if ($netmask < 0 || $netmask > 31) {
    die('Unsupported Netmask.');
  }

  my $ipUtil = new PlugNPay::Util::IP();

  if (!$ipUtil->validateIPv4Address($ip)) {
    return 0;
  }

  $self->_getPermittedList()->{$ip} = $netmask;
}

sub removePermittedNetworkAddress {
  my $self = shift;
  my $ip = shift;

  my $ipUtil = new PlugNPay::Util::IP();

  if (!$ipUtil->validateIPv4Address($ip)) {
    return 0;
  }

  delete $self->_getPermittedList()->{$ip};
}

sub ipAddressIsPermitted {
  return 1; # until further notice
}  

sub _getPermittedList {
  my $self = shift;

  if (!defined $self->{'permittedNetworkAddresses'}) {
    $self->{'permittedNetworkAddresses'} = {};
  }

  return $self->{'permittedNetworkAddresses'};
}

sub getPermittedNetworkAddresses {
  my $self = shift;
  return $self->_getPermittedList();
}

sub save {
  my $self = shift;
  $self->_savePermittedNetworkAddresses;
}

sub _savePermittedNetworkAddresses {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();

  # run queries in eval to catch errors.
  eval {
    $dbs->begin('pnpmisc');

    # clear existing addresses
    my $query = 'DELETE FROM ipaddress WHERE username = ?';
    $dbs->executeOrDie('pnpmisc', $query, [$self->getGatewayAccount()]);

    # if keys exist
    if (keys %{$self->_getPermittedList()} > 0) {
      my @placeholders;
      my @values;

      # prepare the placeholders and values
      foreach my $ipAddress (keys %{$self->_getPermittedList()}) {
        push @placeholders,'(?,?,?)';
        push @values,($self->getGatewayAccount(),$ipAddress,$self->_getPermittedList()->{$ipAddress});
      }

      $query = q/INSERT INTO ipaddress
                             (`username`, `ipaddress`, `netmask`)
                      VALUES / . join(',',@placeholders);
      $dbs->executeOrDie('pnpmisc', $query, \@values);
    }
  };

  # only commit if there were no errors.
  if (!$@) {
    $dbs->commit('pnpmisc');
  } else {
    $dbs->rollback('pnpmisc');
    die('Unable to save Mobile Client { username: ' . $self->getGatewayAccount() . '}');
  }
}

sub load {
  my $self = shift;
  $self->_loadPermittedNetworkAddresses;
}

sub _loadPermittedNetworkAddresses {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('pnpmisc','SELECT ipaddress,netmask FROM ipaddress WHERE username = ?');
  $sth->execute($self->getGatewayAccount());

  my $results = $sth->fetchall_arrayref({});
  if ($results) {
    foreach my $row (@{$results}) {
      $self->_getPermittedList()->{$row->{'ipaddress'}} = $row->{'netmask'};
    }
  }
}

sub manageMobileClientAccount {
  my $self = shift;
  my $password = shift;
  my $username = shift || $self->getMobileClientUsername();
  my $gatewayAccount = shift || $self->getGatewayAccount();

  if (!defined $username) {
    if (!defined $gatewayAccount) {
      die "No account data sent\n";
    } else {
      $username = 'mobi_' . $gatewayAccount;
    }
  } elsif ($username !~ /^mobi_/) {
    $username = 'mobi_' . $username;
  }
 
  my $success = 0;
  my $accountManager = new PlugNPay::Username($username);
  $accountManager->setSecurityLevel('14');
  if ($accountManager->getGatewayAccount()) {
    if ($gatewayAccount eq $accountManager->getGatewayAccount() || !defined $gatewayAccount) {
      $success = $accountManager->setPassword($password);  
    }
  } elsif (defined $gatewayAccount) {
    $accountManager->setGatewayAccount($gatewayAccount);
    $success = $accountManager->setPassword($password);
  }

  return $success;
}

1;
