package PlugNPay::Token::Request;

# HISTORY
# 2013/05/03 - Added functions to request tokens.  Redeem functions still need to be added.
# 2015/08/13 - Couldn't find missing redeem functions?? 

use strict;
use JSON::XS;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  return $self;
}

sub dataTypeIsValid {
  my $self = shift;
  my $type = shift;

  return ($type =~ /^(CARD_NUMBER|CREDENTIAL)$/);
}

sub setRequestType {
  my $self = shift;
  my $requestType = shift;

  if ($requestType !~ /^(REQUEST_TOKENS|REDEEM_TOKENS)$/) {
    $requestType = undef;
  }

  $self->{'requestType'} = $requestType;
}

sub getRequestType {
  my $self = shift;

  return $self->{'requestType'};
}

sub setRedeemMode {
  my $self = shift;
  my $redeemMode = shift;

  if ($redeemMode !~ /^(PROCESSING|REPORTING)$/) {
    $redeemMode = undef;
  }

  $self->{'redeemMode'} = $redeemMode;
}

sub getRedeemMode { 
  my $self = shift;
  return $self->{'redeemMode'};
}

sub reset {
  my $self = shift;
  $self->setRequestType();
  $self->setRedeemMode();
  delete $self->{'requestData'};
}

sub addValue {
  my $self = shift;
  my ($identifier,$data,$lifetime,$dataType) = @_;
  if (uc($dataType) eq 'CARD_NUMBER') {
    $self->addCardNumber($identifier,$data,$lifetime);
  } elsif (uc($dataType) eq 'CREDENTIAL') {
    $self->addCredential($identifier,$data);
  }
}

sub addCardNumber {
  my $self = shift;
  my ($identifier,$data,$lifetime) = @_;

  if ($self->getRequestType() eq 'REQUEST_TOKENS') {
    $self->{'requestData'}{'REQUEST_TOKENS'}{$identifier} = {value => $data,dataType => 'CARD_NUMBER',lifetime => $lifetime, identifier => $identifier};
  }
}

sub addCredential {
  my $self = shift;
  my ($identifier,$data) = @_;

  if ($self->getRequestType() eq 'REQUEST_TOKENS') {
    $self->{'requestData'}{'REQUEST_TOKENS'}{$identifier} = {value => $data,dataType => 'CREDENTIAL',lifetime => 25, identifier => $identifier};
  }
}

sub addToken {
  my $self = shift;
  my ($identifier,$token,$lifetime) = @_;

  if ($self->getRequestType() eq 'REDEEM_TOKENS') {
    $self->{'requestData'}{'REDEEM_TOKENS'}{$identifier} = {token => $token, lifetime => $lifetime, redeemMode => $self->getRedeemMode(), identifier => $identifier};
  }
}

sub getTokens {
  my $self = shift;
  return $self->{'requestData'};
}

sub getRequestData {
  my $self = shift;

  my $data = $self->getRequestDataRef();
  return encode_json($data);
}

sub getRequestDataRef {
  my $self = shift;
  my $requestData = $self->getTokens();

  my $requests =  $requestData->{'REQUEST_TOKENS'};
  $requests = {} if (ref($requests) ne 'HASH' || !defined $requests);
  
  my $redeems = $requestData->{'REDEEM_TOKENS'};
  $redeems = {} if (ref($redeems) ne 'HASH' || !defined $redeems);

  my $data = { 
    'requests' => $requests,
    'redeems'  => $redeems
  };
  
  return $data;
}

1;
