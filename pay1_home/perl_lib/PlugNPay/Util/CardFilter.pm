package PlugNPay::Util::CardFilter;

# Purpose: Use to filter card numbers from variables, either by explicit card number matching or generic match luhn10 values.

use PlugNPay::CreditCard;
use strict;


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $card_number = shift;
  if ($self->setCardNumber($card_number)) {
    $self->_genFilteredCc();
  }

  return $self;
}

#####################
# Setters & Getters #
#####################

sub setCardNumber {
  my $self = shift;
  my $cardNumber = shift; # full card to explicitly match against

  if (($cardNumber >= 12) && ($cardNumber =~ /(\d{12,19})/)) {
    $self->{'cardNumber'} = $cardNumber;
    return 1;
  }
  return 0;
}

sub getCardNumber {
  my $self = shift;
  return $self->{'cardNumber'};
}


sub setFilteredCc {
  my $self = shift;
  my $filteredCc = shift;  # filtered card number to use in substitutions

  if ($filteredCc =~ /X\d{4}$/) {
    $self->{'filteredCc'} = $filteredCc;
    return 1;
  }
  return 0;
}

sub getFilteredCc {
  my $self = shift;
  return $self->{'filteredCc'};
}


#############
# Functions #
#############

sub _genFilteredCc {
  my $self = shift;
  my $cardNumber = $self->getCardNumber();

  $cardNumber =~ s/[^0-9]//g;
  $cardNumber = substr($cardNumber,0,20);
  if ($cardNumber =~ /(\d{12,19})/) {
    my $filteredCc = ('X' x (length($cardNumber))) . substr($cardNumber,-4,4);
    $self->setFilteredCc($filteredCc);
    return 1;
  }
  return 0;
}

sub filterSingle {
  my $self = shift;
  my $val = shift;    # some value you want card number filtered
  my $force = shift;  # when set, will use generic luhn10 like matching (forcing bypass of card number specific filtering)

  if (($val =~ /$self->getCardNumber()/) && (!$force)) {
    # filter based upon explict card number defined
    $val =~ s/$self->getCardNumber()/$self->getFilteredCc()/ge;
  }
  else {
    # filter based upon luhn10 like match, when no card number is defined
    if ($val =~ /(\d{12,19})/) {
      $val =~ s/(\d{12,19})/&_cardFilter_sub($1)/ge;
    }
  }

  return ($val);
}

sub filterPair {
  my $self = shift;
  my $key = shift;   # name of given field
  my $val = shift;   # value of given field
  my $force = shift; # when set, will use generic luhn10 like matching (forcing bypass of card number specific filtering)

  $key =~ s/[^0-9a-zA-Z\_\-]//g;

  if ($key =~ /(card.*num|accountnum|acct_num|ccno)/i) {
    $val = substr($val,0,6) . ('X' x (length($val)-8)) . substr($val,-2); # Format: first6, X's, last2
  }
  elsif ($key =~ /(TrakData|magstripe|track|magensacc)/i) {
    $val = "Data Present:" . substr($val,0,6) . "****" . "0000" . ", ";
  }
  elsif ($key eq "cvvresp") {
    $val =~ s/[^0-9a-zA-Z]//g;
  }
  elsif ($key =~ /(cvv|pass.*w.*d|x_tran_key|card.code|password|cvv)/i) {
    $val =~ s/./X/g;
  }
  elsif ($key =~ /^(ssnum|ssnum4)$/i) {
    $val  = ('X' x (length($val)-4)) . substr($val,-4,4);
  }
  elsif ($key eq "auth-code") {
    $val = substr($val,0,6);
  }
  else {
    $key = $self->filterSingle($key,$force);
    $val = $self->filterSingle($val,$force);
  }
  return ($key, $val);
}

sub filterArray {
  my $self = shift;
  my $arrayRef = shift;  # some array you want card number filtered
  my $force = shift;     # when set, will use generic luhn10 like matching (forcing bypass of card number specific filtering)

  my $filteredArrayRef;

  foreach my $val (\@$arrayRef) {
    push(@$filteredArrayRef, $self->filterSingle($val,$force));
  }

  return $filteredArrayRef;
}

sub filterHash {
  my $self = shift;
  my $hashRef = shift;  # some hash you want card number filtered
  my $force = shift;    # when set, will use generic luhn10 like matching (forcing bypass of card number specific filtering)

  my $filteredHashRef;

  foreach my $key (\%$hashRef) {
    my ($field_name, $field_value) = $self->filterPair($key, $hashRef->{$key}, $force);
    $filteredHashRef->{$field_name} = $field_value;
  }

  return $filteredHashRef;
}

sub _cardFilter_sub {
  my ($stuff) = @_;
  # used by 'filterSingle' sub-function for luhn10 match filtering

  my $cc = new PlugNPay::CreditCard($stuff);
  if ($cc->verifyLuhn10()) {
    $stuff = $cc->getMaskedNumber(6,4,'X',length($stuff)); # first 4, last 4, X's in-between
  }

  return $stuff;
}


1;
