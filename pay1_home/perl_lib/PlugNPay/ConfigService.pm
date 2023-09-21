package PlugNPay::ConfigService;

# this is a copy of PlugNPay::Config from another branch
# i like the name ConfigService more...
# the other branch can be changed to use ConfigService once this is merged
# (this will be merged before the other one...pretty sure anyway, since this affects being able
#  to work in dev..)

use strict;
use PlugNPay::ResponseLink;


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub getConfigServer {
  return $ENV{'PNP_CONFIG_SERVER'} || 'config.local';
}

sub getConfig {
  my $self = shift;
  my $input = shift;
  my $configAPIVersion = $input->{'apiVersion'};

  if (!defined $configAPIVersion) {
    die('call to getConfig with no api version defined');
  }

  if ($configAPIVersion eq '1') {
    return $self->v1($input);
  } else {
    die('unsupported api version');
  }
}

sub v1 {
  my $self = shift;
  my $input = shift;
  my $configName = $input->{'name'};
  my $configPath = $input->{'path'} || '';
  my $configFormatVersion = $input->{'formatVersion'};

  if (!defined $configName) {
    die('configuration name is not defined');
  } elsif ($configName =~ /[^a-zA-Z0-9\-]/) {
    die('invalid characters in configuration name');
  }

  if (!defined $configFormatVersion) {
    die('configuration format version is not defined');
  } elsif ($configFormatVersion =~ /[^0-9]/) {
    die('configuration format version must be an integer')
  }

  my $configServer = getConfigServer();
  my $url = sprintf('https://%s/v1/json/%s/%s/%s',$configServer,$configName,$configFormatVersion,$configPath);

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setMethod('GET');

  $ms->doRequest();

  my $config = $ms->getDecodedResponse();
  return $config;
}

1;
