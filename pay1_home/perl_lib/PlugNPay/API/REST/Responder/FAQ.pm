package PlugNPay::API::REST::Responder::FAQ;

use strict;

use PlugNPay::Reseller::FAQ;
use URI::Escape;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;
  my $data = {};
  my $options = $self->getResourceOptions(); 
  if (!defined $self->getResourceData()->{'faq'}){
    return $self->_readAll($options);
  } else {
    return $self->_read();
  }
}

sub _read {
  my $self = shift;
  my $FAQ = new PlugNPay::Reseller::FAQ();
  my $issue = $FAQ->get($self->getResourceData()->{'faq'});

  $self->setResponseCode(200);

  return { 'faq' => $issue };
}

sub _readAll {
  my $self = shift;
  my $options = uri_unescape(shift);
  
  my $FAQ = new PlugNPay::Reseller::FAQ();
  my @response = ();
  my $issues = $FAQ->searchKeywords($options->{'keywords'},$options->{'category'} || 'all');

  foreach my $issueID (keys %{$issues}) {
    my @infoArray = ();
    my $info = $issues->{$issueID};
    push @infoArray, $info->{'sectionTitle'};
    push @infoArray, $info->{'issueID'};
    push @infoArray, $info->{'shortQuestion'};
    push @response, \@infoArray;
  }
  $self->setResponseCode('200');
  return { 'response' => \@response, 'id' => $options->{'id'} };
}

1;
