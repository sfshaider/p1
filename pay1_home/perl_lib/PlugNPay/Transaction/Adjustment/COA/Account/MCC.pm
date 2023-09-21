package PlugNPay::Transaction::Adjustment::COA::Account::MCC;

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

sub setMCC {
  my $self = shift;
  my $mcc = shift;
  $self->{'mcc'} = $mcc;
}

sub getMCC {
  my $self = shift;
  return $self->{'mcc'};
}

sub isValid {
  my $self = shift;
  my $requestData = { mcc => $self->getMCC() };
  return $self->callAPI($requestData);
}

sub callAPI {
  my $self = shift;
  my $requestData = shift;

  my $gs = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $host = $gs->getHost();

  my $url = sprintf('http://%s/private/mcc.cgi',$host);

  my $rl = new PlugNPay::ResponseLink();

  $rl->setRequestURL($url);
  $rl->setRequestMethod('post');
  $rl->setRequestData($requestData);
  $rl->setRequestMode('DIRECT');

  $rl->doRequest();

  if (!$rl->requestFailed) {
    my $data = decode_json($rl->getResponseContent());
    if (ref $data eq 'HASH') {
      return $data->{'valid'};
    }
  }
}



1;
