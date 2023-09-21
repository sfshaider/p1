package PlugNPay::Transaction::Adjustment::GlobalSettings;

use strict;
use PlugNPay::Die;
use PlugNPay::DBConnection;

our $_settings;

sub new {
    my $class = shift;
    my $self = {};
    bless $self,$class;

    if (!defined $_settings) {
        $self->_loadGlobalSettings();
    }
    
    return $self;
}

sub getSettings {
    my $self = shift;
    

    my %copy = %{$_settings};
    return \%copy;
}

sub getHost {
  my $self = shift;
  my $version = shift;

  my $versionHost = undef;
  if (defined $version) {
      $versionHost = $_settings->{'host_v' . $version};
  }

  return $versionHost || $_settings->{'host'};
}

sub getPort {
  my $self = shift;
  return $_settings->{'port'};
}

sub getProtocol {
  my $self = shift;
  return $_settings->{'protocol'};
}

sub getCalculationUrl {
  my $self = shift;
  return $_settings->{'resource'};
}

sub getCardLength {
  my $self = shift;
  my $version = shift;

  my $versionLength = undef;
  if (defined $version) {
      $versionLength = $_settings->{'card_length_v' . $version};
  }
  return $versionLength || $_settings->{'card_length'};
}

sub _loadGlobalSettings {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $res = $dbs->fetchallOrDie('pnpmisc',q/
    SELECT setting_name,setting_value FROM adjustment_coaremote_global_setting
  /,[],{});

  my $rows = $res->{'rows'};

  my %settings;

  foreach my $row (@{$rows}) {
    $settings{$row->{'setting_name'}} = $row->{'setting_value'};
  }

  $_settings = \%settings;
}

1;