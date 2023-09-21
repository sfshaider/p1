package PlugNPay::Security::GlobalSettings;

use strict;
use PlugNPay::DBConnection();

our $_cache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  $self->_init();
  return $self;
}

sub _init {
  my $self = shift;
  if (!defined $_cache) {
    $self->_loadSettings();
  }
}

sub get {
  my $self = shift;
  my $settingName = shift;

  if (!defined $_cache->{$settingName}) {
    die('Invalid security setting: ' . $settingName);
  } else {
    return $_cache->{$settingName};
  }
}

sub _loadSettings {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT name, value from security_global_settings
  /);

  $sth->execute();

  my $results = $sth->fetchall_arrayref({});

  if ($results) {
    my %settings = map {$_->{'name'} => $_->{'value'} } @{$results};

    $_cache = \%settings;
  }
}

1;
