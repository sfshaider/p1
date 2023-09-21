package PlugNPay::Transaction::TransId;

use strict;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Die;

sub getTransIdV1 {
  my $input = shift;
  my $username = $input->{'username'} || '';
  my $orderId = $input->{'orderId'} || '';     # only used for logging
  my $processor = $input->{'processor'} || ''; # only used for logging

  $username =~ s/[^a-z0-9]//g;
  $orderId =~ s/[^0-9]//g;
  $processor =~ s/[^a-z0-9]//g;

  my $url = 'http://microservice-transid.local/v1/' . $username . '/id';

  my $ms = new PlugNPay::ResponseLink::Microservice;
  $ms->setMethod('GET');
  $ms->setURL($url);
  my $success = $ms->doRequest();

  if (!$success) {
    die('Failed to get transaction id');
  }

  my $response = $ms->getDecodedResponse();
  if ($response->{'error'}) {
    die_metadata('Error from transid service: ' . $response->{'error'},{ 
      username => $username,
      orderId => $username,
      processor => $processor
    });
  } else {
    return $response->{'transId'};
  }
}

1;