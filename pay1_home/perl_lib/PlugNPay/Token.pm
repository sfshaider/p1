package PlugNPay::Token;
use strict;
use PlugNPay::Token::Client;
use PlugNPay::Token::Response;
use PlugNPay::Token::Request;
use PlugNPay::Util::Memcached;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->{'memcached'} = new PlugNPay::Util::Memcached('PlugNPayToken');

  return $self;
}

sub inHex {
  my $self = shift;
  return $self->{'id'};
}

# takes a hex representation of a unique id and stores it internally to be analyzed with the other object methods
sub fromHex {
  my $self = shift;
  my $hex = shift || undef;

  if (!defined $hex) {
    return undef;
  }

  $hex =~ tr/a-z/A-Z/;
  $self->{'id'} = $hex;
}

# returns a binary representation of the unique id
sub inBinary {
  my $self = shift;
  return pack('h*',$self->{'id'});
}

# takes a binary representation of a unique id and stores it internally to be analyzed with the other object methods
sub fromBinary {
  my $self = shift;
  my $binary = shift || undef;

  if (!defined $binary) {
    return undef;
  }
  my $hex = unpack('h*',$binary);
  $self->fromHex($hex);
}

#Request/Redeem functions for ease of use
sub getToken {
  my $self = shift;
  my $value = shift;
  my $dataType = uc shift || 'CARD_NUMBER';

  my $cachedToken = $self->{'memcached'}->get($value);
  if ($cachedToken ne '') {
    return $cachedToken;
  }

  my $req = new PlugNPay::Token::Request();
  $req->setRequestType('REQUEST_TOKENS');
  if ($dataType eq 'CARD_NUMBER') {
    $req->addCardNumber('value1',$value,25);
  } else {
    $req->addCredential('value1',$value,25);
  }

  my $client = new PlugNPay::Token::Client();
  $client->setRequest($req);
  
  my $token = 'unavailable';
  eval {
    my $resp = $client->getResponse();
    $token = $resp->get('value1');
  };

  if ($token ne '' && $token ne 'unavailable') {
    $self->cacheToken($token,$value);
  }

  return $token;
}

sub fromToken {
  my $self = shift;
  my $token = shift;
  my $redeem = uc shift;

  #Need to check token format
  if ($token !~ /^[a-fA-F0-9]+$/) {
    $self->fromBinary($token);
    $token = $self->inHex();
  }

  my $cachedValue = $self->{'memcached'}->get($token);
  if ($cachedValue ne '') {
    return $cachedValue;
  }

  my $mode = ($redeem =~ /^(PROCESSING|REPORTING)$/ ? $redeem : 'PROCESSING');
  my $req = new PlugNPay::Token::Request();
  $req->setRequestType('REDEEM_TOKENS');
  $req->setRedeemMode($mode);
  $req->addToken('value1',$token,25);

  my $client = new PlugNPay::Token::Client();
  $client->setRequest($req);

  my $value = 'unavailable';
  eval {
    my $resp = $client->getResponse();
    $value =  $resp->get('value1');
  };

  if ($value ne '' && $value ne 'unavailable') {
    $self->cacheToken($token,$value);
  }

  return $value;
}

sub cacheToken {
  my $self = shift;
  my $token = shift;
  my $value = shift;

  $self->{'memcached'}->set($token,$value,300);
  $self->{'memcached'}->set($value,$token,300);
}

1;
