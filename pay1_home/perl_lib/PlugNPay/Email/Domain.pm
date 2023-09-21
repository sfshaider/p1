package PlugNPay::Email::Domain;

use strict;
use Net::DNS;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

sub validate {
  my $self = shift;
  my $email = shift;
  my ($user,$domain) = split('@',$email);

  # da base case(s)
  return 0 if !defined $domain;
  return 0 if $domain eq '';

  my $valid = $domain eq 'plugnpay.com' || 0;
  unless ($valid) {
    my $resolver = new Net::DNS::Resolver();
    my @recordList = ();

    $resolver->udp_timeout(5);
    $resolver->tcp_timeout(5);

    my $packet = $resolver->send($domain,'TXT','IN');
    if (defined $packet) {
      @recordList = $packet->answer();
    }
    
    foreach my $record (@recordList) {
      if ($record->txtdata() =~ /^v=spf/ && $record->txtdata() =~ /plugnpay\.com/i) { 
        $valid = 1;
        last;
      }
    }
  }

  return $valid;
}

1;
