package PlugNPay::GatewayAccount::LinkedAccounts;

use strict;
use warnings FATAL => 'all';

use PlugNPay::Features;
use PlugNPay::GatewayAccount::LinkedAccounts::File;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $gatewayAccount = shift;
  my $login = shift;

  if ($gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
  }
  if ($login) {
    $self->setLogin($login);
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  if (defined $gatewayAccount) {
    $gatewayAccount = lc($gatewayAccount);

    $gatewayAccount =~ s/[^a-z0-9]//;

    if (!defined $self->{'gatewayAccount'} || $self->{'gatewayAccount'} ne $gatewayAccount) {
      $self->{'gatewayAccount'} = $gatewayAccount;
      $self->_setNeedsRefresh();
    }
  }
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setLogin {
  my $self = shift;
  my $login = shift;

  if (defined $login) {
    $login = lc($login);
    $login =~ s/[^a-z0-9]//g;

    if (!defined $self->{'login'} || $self->{'login'} ne $login) {
      $self->{'login'} = $login;
      $self->_setNeedsRefresh();
    }
  }
}

sub getLogin {
  my $self = shift;
  return $self->{"login"};
}

sub _setNeedsRefresh {
  my $self = shift;
  $self->{"_needs_refresh_"} = 1;
}

sub _refresh {
  my $self = shift;
  if ($self->{"_needs_refresh_"}) {
    $self->_load();
    $self->{"_needs_refresh_"} = 0;
  }
}

sub setMaster {
  my $self = shift;
  $self->{'master'} = 1;
}

sub unsetMaster {
  my $self = shift;
  delete $self->{'master'};
}

sub isMaster {
  my $self = shift;
  return $self->{'master'};
}

sub addAccount {
  my $self = shift;
  my $account = shift;

  return if !defined $account;

  $account = lc($account);
  $self->addAccounts([$account]);
}

sub addAccounts {
  my $self = shift;
  $self->_refresh();

  my $addAccounts = shift;

  my %accounts = map { $_ => 1 } @{$self->{'accounts'}};

  foreach my $account (@{$addAccounts}) {
    $account =  lc $account;
    $account =~ s/[^a-z0-9]//g;
    $accounts{$account} = 1;
  }

  my @accounts = keys %accounts;
  $self->{'accounts'} = \@accounts;
}


sub removeAccount {
  my $self = shift;
  my $account = shift;
  if (defined $account) {
    $account = lc($account);
    $self->removeAccounts([$account]);
  }
}

sub removeAccounts {
  my $self = shift;
  $self->_refresh();

  my $removeAccounts = shift;

  my %accounts = map { $_ => 1 } @{$self->{'accounts'}};

  foreach my $account (@{$removeAccounts}) {
    $account =  lc $account;
    $account =~ s/[^a-z0-9]//g;
    delete $accounts{$account};
  }

  my @accounts = keys %accounts;
  $self->{'accounts'} = \@accounts;
}

sub isLinkedTo {
  my $self = shift;
  $self->_refresh();

  my $account = shift;

  if (!defined $account) {
    return 0;
  }

  $account = lc($account);
  my %accounts = map { $_ => 1 } @{$self->{'accounts'}};

  return defined $accounts{$account};
}

sub getLinkedAccounts {
  my $self = shift;
  $self->_refresh();

  if (!defined $self->{'accounts'}) {
    $self->_load();
  }

  return $self->{'accounts'};
}

sub _load {
  my $self = shift;

  my $gatewayAccount = $self->getGatewayAccount();
  my $features = new PlugNPay::Features($gatewayAccount,'general');
  my %list = ($self->getGatewayAccount() => 1);

  my $linkedAccountData = $self->_loadFromLinkedListFeature($features);
  if (!defined $linkedAccountData || keys %{$linkedAccountData} == 0) {
    $linkedAccountData = $self->_loadFromLinkedAccountFeature($features);
  }

  %list = (%list, %{$linkedAccountData});
  
  # Handle master data, then remove from %list
  if ($list{'MASTER'}) {
    $self->setMaster();
    delete $list{'MASTER'};
  }

  my @accounts = keys %list;
  $self->{'accounts'} = \@accounts;

  return;
}

sub _loadFromLinkedListFeature {
  my $self = shift;
  my $features = shift;

  my $login = $self->getLogin();
  my $loginFeatures = new PlugNPay::Features($login,'sublogin');

  my $accountLinkedListFeature = $features->get('linked_list');
  my $loginLinkedListFeature = $loginFeatures->get('linked_list');
 
  # set $linkedListValue only if the account has it set, using the setting on the login if it exists.
  my $linkedListValue = '';
  if (defined $loginLinkedListFeature && $loginLinkedListFeature ne '') {
    $linkedListValue = $loginLinkedListFeature;
  } elsif (defined $accountLinkedListFeature) {
    $linkedListValue = $accountLinkedListFeature;
  }

  # the linked accounts as a hash to avoid duplicates, start with the account doing the loading
  my %list = ();
  my @definitions = ();

  #bypass if linkedList is empty
  my $linkedAccountGroup = $features->get('linked_account_group');
  my $groupLinked = (defined $linkedAccountGroup ? $linkedAccountGroup ne '' : 0);

  my $cobrandFeatures = (defined $features->get('cobrand') ? $features->get('cobrand') : '');
  my $cobrandLinked = ($cobrandFeatures =~ /\w/ && $linkedListValue =~ /^(yes|all)$/);
  
  # the groups used to generate the hash
  if ($cobrandLinked) {
    @definitions = ($cobrandFeatures);
  } elsif ($groupLinked) {
    @definitions = split('\|',$linkedAccountGroup);
  }

  # definitions for linked list
  if (@definitions > 0) {
    foreach my $definition (@definitions) {
      foreach my $link (@{PlugNPay::GatewayAccount::LinkedAccounts::File::linkedAccounts({
        gatewayAccount => $self->getGatewayAccount(),
        login => $login,
        linkedAccountDefinition => $definition,
        linkedListFeatureValue => $linkedListValue,
      })}) {
        $list{$link} = 1;
      }
    }
    $list{'MASTER'} = 1;
  } 

  return \%list
}

sub _loadFromLinkedAccountFeature {
  my $self = shift;
  my $features = shift;
  my %list = ();
  my $linkedAccountFeatures = $features->get('linked_accts');
  if (defined $linkedAccountFeatures) {
    my @splitLinkedAccounts = (split '\|', $linkedAccountFeatures);
    %list = map { $_ => 1 } @splitLinkedAccounts;
  }

  return \%list;
}

sub save {
  my $self = shift;

  my $features = new PlugNPay::Features($self->getGatewayAccount(),'general');

  my $featureValue = '';

  if ($self->isMaster()) {
    $featureValue = 'MASTER|';
  }

  $featureValue .= join('|',@{$self->{'accounts'}});

  $features->set('linked_accts', $featureValue);
  $features->saveContext();
}


1;
