package PlugNPay::Util;

use strict;
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(string);
our @EXPORT_OK = qw(integerToBinary binaryToInteger integerToHex hexToInteger binaryToHex hexToBinary renibble);

# Misc simple functions that are useful in many contexts.

sub integerToBinary {
  my $integer = shift;
  return unpack('B32', pack('I',$integer));
}

sub binaryToInteger {
  my $binary = shift;
  return unpack('I',pack('B32',$binary));
}

sub integerToHex {
  my $integer = shift;
  return unpack('H*', pack('I',$integer));
}

sub hexToInteger {
  my $hex = shift;
  return unpack('I',pack('H*',$hex));
}

sub binaryToHex {
  my $binary = shift;
  my $hex = unpack('H*',$binary);
  $hex =~ tr/a-z/A-Z/;
  return $hex;
}

sub hexToBinary {
  my $hex = shift;
  $hex =~ tr/A-Z/a-z/;
  return pack('H*',$hex);
}

sub renibble {
  my $hex = shift;
  return unpack('H*',pack('h*',$hex));
}

# similar to int($x), converts input to a string.  helpful with overloaded '""'
sub string {
  my $input = shift;
  return "$input";
}

1;
