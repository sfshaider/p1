package PlugNPay::Fraud::Abstract;
######################### NOTE ###########################
# THIS IS AN ABSTRACT MODULE                             #
# USE THIS AS "base" FOR FRAUD MODULES                   #
# CAN BE USED FOR ANY TABLE THAT IS "username" : "entry" #
##########################################################

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $username = shift;
  if ($username) {
    $self->setGatewayAccount();
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

sub _setLoadedEntries {
  my $self = shift;
  my $loadedEntries = shift;
  $self->{'loadedEntries'} = $loadedEntries;
}

sub _getLoadedEntries {
  my $self = shift;
  return $self->{'loadedEntries'};
}

sub save {
  my @caller = caller();

  die 'Failed to override load function in ' . join(/::/,@caller) . "\n";
}  

sub _save {
  my $self = shift;
  my $insert = shift;
  my $values = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status(1);
  eval {
    $dbs->executeOrDie('fraudtrack', $insert, $values);
  };

  if ($@) {
    $status->setFalse(); 
    $status->setError('Failed to save fraud data');
    $status->setErrorDetails($@);
    $self->log($@,$values);
  }

  return $status;
}

sub load {
  my @caller = caller();
  
  die 'Failed to override load function in ' . join(/::/,@caller) . "\n";
}

sub _load {
  my $self = shift;
  my $select = shift;
  my $params = shift;
  my $validCharacters = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $rows = [];
  eval {
    $rows = $dbs->fetchallOrDie('fraudtrack', $select, $params, {})->{'result'};
  };

  if ($@) {
    $self->log($@, $params);
  }

  my $results = {};
  foreach my $row (@{$rows}) {
    my $entry = $row->{'entry'};
    if (defined $validCharacters) {
      $entry =~ s/[^$validCharacters]//g;
    }

    $results->{$entry} = 1;
  }

  $self->_setLoadedEntries($results);
}

sub _isInEntriesMap {
  my $self = shift;
  my $valuesForSearch = shift;
  my $validCharacters = shift;

  if (ref($valuesForSearch) ne 'ARRAY') {
    die "Failed to pass in valid data in _isInEntriesMap\n";
  }
 
  my $loaded = $self->_getLoadedEntries();
  if (!defined $loaded) {
    die "No data was loaded to search!\n";
  }

  my @matchedEntries = ();
  foreach my $value (@{$valuesForSearch}) {
     if (defined $validCharacters) {
       $value =~ s/[^$validCharacters]//g;
     }

     if ($loaded->{$value}) {
       push @matchedEntries, $value;
     }  
  }

  return \@matchedEntries;
}

sub _log {
  my $self = shift;
  my $error = shift;
  my $data = shift;
  new PlugNPay::Logging::DataLog({'collection' => 'fraudtrack'})->log({
    'error'  => $error,
    'data'   => $data,
    'module' => ref($self)
  });
}

1;
