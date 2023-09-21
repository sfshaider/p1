#!/usr/bin/perl
  
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use Test::More qw( no_plan );
use PlugNPay::Partners::AuthVia::Conversation;
our $convoID;
my $merchant = $ARGV[0] || 'dylaninc';
sub createConversation {
  my $c = new PlugNPay::Partners::AuthVia::Conversation();
  $c->setPartner('dylaninc');
  $c->setGatewayAccount($merchant);
  my $response = $c->create({
      'phoneNumber' => '+16317451352',
      'name'        => 'Dylan Manitta',
      'contextData' => {'description' => 'test', 'amount' => '1.00'},
      'topic'       => 'payment',
      'deadline'    => '15m'
    });
  

  $convoID = $response->{'authViaId'};
  return $response->{'status'};
}

sub resolveConversation {
  my $c = new PlugNPay::Partners::AuthVia::Conversation();
  $c->setPartner('dylaninc');
  $c->setGatewayAccount($merchant);
  my $response = $c->update($convoID, {'status' => 'resolved'});
  return $response->{'status'};
}

sub updateConversation {
  my $c = new PlugNPay::Partners::AuthVia::Conversation();
  $c->setPartner('dylaninc');
  $c->setGatewayAccount($merchant);
  my $response = $c->read($convoID);
  return $response->{'status'};
}

is(&createConversation(), 'in-progress', 'Create Conversation test');
is(&resolveConversation(), 'resolved', 'Resolve Conversation test');
is(&updateConversation(), 'resolved', 'Update Conversation test');
