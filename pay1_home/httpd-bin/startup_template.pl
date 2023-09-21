#!/bin/env perl
use lib '/home/p/pay1/perl_lib';
use Apache2::Const;
use Apache2::Connection;
use Apache2::RequestRec;
use LWP::UserAgent;
use Net::SSLeay qw(get_https post_https sslcat make_headers make_form);
use MIME::Base64;
use Math::BigInt;
use Time::Local;
use IO::Socket;
use Socket;

#<USEMODULESHERE>#

sub My::PostReadRequestHandler ($) {
  my $r = shift;

  # Fix "remote address"
  # we'll only look at the X-Forwarded-For header if the requests
  # comes from our proxy at localhost
  my ($ip);
  if ( ($r->connection->client_ip =~ /^(10\.160\.)/) && (($r->headers_in->{'X-Forwarded-For'}) || ($r->headers_in->{'X-REMOTE-ADDR'})) ){
    # Select last value in the chain -- original client's ip
    # oops, on new server it's the first
    if (($ip) = $r->headers_in->{'X-Forwarded-For'} =~ /^([^,\s]+)/) {
      $r->connection->client_ip($ip);
    }
    elsif (($ip) = $r->headers_in->{'X-REMOTE-ADDR'} =~ /^([^,\s]+)/) {
      $r->connection->client_ip($ip);
    }
  }

  # Filter referrer
  $r->headers_in->{'Referer'} =~ s/\?.*/\?querystringremoved/;

  return Apache2::Const::OK;
}

1;
