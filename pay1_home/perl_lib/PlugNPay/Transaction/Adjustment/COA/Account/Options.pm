package PlugNPay::Transaction::Adjustment::COA::Account::Options;

use strict;
use JSON::XS;

use PlugNPay::ResponseLink;
use PlugNPay::Transaction::Adjustment::GlobalSettings;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub getCalculationRules {
  my $self = shift;

  if (!$self->loaded()) {
    $self->load();
  }

  return $self->{'options'}{'calculationRules'};
}

sub getProcessors {
  my $self = shift;
  
  if (!$self->loaded()) {
    $self->load();
  }

  return $self->{'options'}{'processors'};
}

sub getProcessorAccountTypes {
  my $self = shift;
  
  if (!$self->loaded()) {
    $self->load();
  }

  return $self->{'options'}{'processorAccountTypes'};
}


sub loaded {
  my $self = shift;
  return defined $self->{'options'}; 
}

sub load {
  my $self = shift;

  $self->callAPI();
}

sub callAPI {
  my $self = shift;

  my $gs = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $host = $gs->getHost();

  my $url = sprintf('http://%s/private/options.cgi',$host);

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL($url);
  $rl->setRequestMethod('post');
  $rl->setRequestData({});
  $rl->setRequestMode('DIRECT');

  $rl->doRequest();

  if (!$rl->requestFailed) {
    my $data = decode_json($rl->getResponseContent());
    if (ref $data eq 'HASH') {
      $self->{'options'} = $data;
    }
  }
}



1;
