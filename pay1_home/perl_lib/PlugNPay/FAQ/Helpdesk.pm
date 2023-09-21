package PlugNPay::FAQ::Helpdesk;

use strict;
use base 'PlugNPay::FAQ';

sub _getFAQRelativePath {
  return 'admin/wizards/faq_data/';
}

sub log {
  my $self = shift;
  my $logData = shift;

  new PlugNPay::Logging::DataLog({'collection' => 'helpdesk'})->log($logData);
  return;
}


1;
