package PlugNPay::Util::IP::Address;

use strict;
use Math::BigInt;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  return $self;
}

#IP Address, fromIP will determine IPAddress for itself.
sub fromIP {
  my $self = shift;
  my $ip = shift;

  my $int = $self->_IPToInteger($ip);
  $self->fromInteger($int);
}

sub toIP { 
  my $self = shift;
  my $version = shift; #integerToIP defaults version to IPv4
  
  return $self->_integerToIP($self->{'integer'},$version);
}

#Integer
sub toInteger {
  my $self = shift;
  return $self->{'integer'};
}

sub fromInteger {
  my $self = shift;
  my $integer = shift;

  $self->{'integer'} = $integer;
}

#Binary String
sub toBinaryString {
  my $self = shift;
  my $version = shift; #Defaults to IPv4
  
  return $self->_integerToBinary($self->{'integer'},$version);
}

sub fromBinaryString {
  my $self = shift;
  my $binary = shift;

  my $int = $self->_binaryToInteger($binary);
  $self->fromInteger($int);
}

#Binary - Should use I* for unsigned ints
sub toBinary {
  my $self = shift;

  return pack('I*', $self->{'integer'});
}

sub fromBinary {
  my $self = shift;
  my $binary = shift;
  my $int = unpack('I*',$binary);

  $self->fromInteger($int);
}

## Conversion Functions ##
sub convertIPVersions {
  my $self = shift;
  my $ip = shift;
  my $version = $self->getIPVersion($ip);
  $self->fromIP($ip);

  if ($version == 4) {
    return $self->toIP(6);
  } else {
    return $self->toIP(4);
  }
}

sub _IPToInteger {
  my $self = shift;
  my $ip = shift;
  my $version = $self->getIPVersion($ip);

  if (!defined $ip || $ip eq '') {
    $self->addError('Empty IP Address');
    return;
  }

    my $bin = $self->_ipToBinary($ip);
    my $int = $self->_binaryToInteger($bin);

    if (!defined $int || $int eq '' ) {
      $self->addError('No integer value returned');
    }

    return $int;
}

sub _integerToIP {
  my $self = shift;
  my $int = shift;
  my $version = shift;

  if (!defined $int || $int eq '') {
    $self->addError('Null Integer value');
    return;
  }

  my $bin = $self->_integerToBinary($int,$version);
  my $ip = $self->_binaryToIP($bin,$version);

  if (!defined $ip || $ip eq '') {
    $self->addError('No IP Address returned');
  }

  return $ip;
}

sub _ipToBinary {
  my $self = shift;
  my $ip = shift;
  my $version = $self->getIPVersion($ip);

  # v4 -> return 32-bit array
  if ($version == 4) {
    return unpack('B32', pack('C4C4C4C4', split(/\./, $ip)));
  }

  # Strip ':'
  $ip =~ s/://g;

  # v6 -> return 128-bit array
  return unpack('B128',pack('H32', $ip));
}

sub _binaryToIP {
  my $self = shift;
  my $binip = shift;
  my $version = shift;

  # Define normal size for address
  my $len = $self->getIPLength($version);

  if ($len < length($binip)) {
    $self->addError("Invalid IP length for binary IP");
    return;
  }

  # Prepend 0s if address is less than normal size
  $binip = '0' x ($len - length($binip)) . $binip;

  if ($version == 4) {
    # IPv4
    return join('.',unpack('C4C4C4C4',pack('B32', $binip)));
  } else {
    # IPv6
    return join(':',unpack('H4H4H4H4H4H4H4H4',pack('B128', $binip)));
  }
}

sub _binaryToInteger {
  my $self = shift;
  my $binip = shift;

  # $n is the increment, $dec is the returned value
  my $num = new Math::BigInt(1); 
  my $dec = new Math::BigInt(0);


  # Reverse the bit string
  foreach my $val (reverse(split('',$binip))) {
    # If the nth bit is 1, add 2**n to $dec
    $val and $dec += $num;
    $num *= 2;
  }

    # Strip leading + sign
  $dec =~ s/^\+//;
  return $dec;
}

sub _integerToBinary {
  my $self = shift;
  my $int = shift; 
  my $version = shift || 4;

  my $dec = new Math::BigInt($int);

  #use BigInt funciton to set to binary
  my $binip = $dec->as_bin();
  $binip =~ s/^0b//;

  # Define normal size for address
  my $len = $self->getIPLength($version);
  
  # Prepend 0s if result is less than normal size
  $binip = '0' x ($len - length($binip)) . $binip;
  
  return $binip;
}

#Get Max address lengths
sub getIPLength {
  my $self = shift;
  my $version = shift;

  if ($version == 4) {
    return 32;
  } elsif ($version == 6) {
    return 128;
  } else {
    return undef;
  }
}

sub setErrors {
  my $self = shift;
  my $errors = shift;
  $self->{'errors'} = $errors;
}

sub getErrors {
  my $self = shift;
  return $self->{'errors'};
}

sub addError {
  my $self = shift;   
  my $error = shift;
  
  if (!defined $self->getErrors() || ref($self->getErrors()) ne 'ARRAY') {
    my @array = ($error);
    $self->setErrors(\@array);
  } else {
    push @{$self->{'errors'}},$error;
  }
}

sub getIPVersion {
  my $self = shift;
  my $ip = shift;

  if ($ip !~ /:/ && $self->isIPv4($ip)) {
    return '4';
  } elsif ($ip !~ /./ && $self->isIPv6($ip)) {
    return '6';
  } else { 
    $self->addError('Invalid IP address: ' . $ip);
    return; 
  }
}

sub isIPv4 {
  my $self = shift;
  my $ip = shift;

  # Check for invalid chars
  unless ($ip =~ /^[\d\.]+$/) {
    $self->addError( "Invalid characters in IP");
    return 0;
  }

  if ($ip =~ /^\./) {
    $self->addError("Invalid IP - starts with a dot");
    return 0;
  }

  if ($ip =~ /\.$/) {
    $self->addError("Invalid IP - ends with a dot");
    return 0;
  }

  # Single Numbers are considered to be IPv4
  if ($ip =~ /^(\d+)$/ && $1 < 256) { 
    return 1;
  }

  # Count quads
  my $num = ($ip =~ tr/\./\./); 

  # IPv4 must have from 1 to 4 quads
  unless ($num >= 0 && $num < 4) {
    $self->addError("Invalid IP address, bad number of quads");
    return 0;
  }

    # Check for empty quads
  if ($ip =~ /\.\./) {
    $self->addError("Empty quad in IP address, empty quad");
    return 0;
  }

  foreach my $quad (split(/\./,$ip)) {
    # Check for invalid quads
    unless ($quad >= 0 && $quad < 256) {
      $self->addError("Invalid quad in IP address - $quad");
      return 0;
    }
  }

  #If you made it here then YAY! You have an IPV4 address
  return 1;
}

sub isIPv6 {
  my $self = shift;
  my $ip = lc shift;

  # Count octets
  my $num = ($ip =~ tr/:/:/);
  unless ($num > 0 && $num < 8) {
    $self->addError('Invalid address');
    return 0;
  }

  my $count;
  
  # Does the IP address start with : ?
  if ($ip =~ m/^:[^:]/) {
    $self->addError("Invalid address (starts with :)");
    return 0;
  }

  # Does the IP address finish with : ?
  if ($ip =~ m/[^:]:$/) {
    $self->addError("Invalid address (ends with :)");
    return 0;
  }

  # Does the IP address have more than one '::' pattern ?
  if (split(/::/,$ip) > 2) {
    $self->addError("Invalid address (More than one :: pattern)");
    return 0;
  }

  my $filteredIP = ($ip =~ s/::/:/);
  foreach my $octet (split(/:/,$filteredIP)) {
    $count++;

    # Empty octet ?
    if ($octet eq '') {
      $self->addError("Invalid IP address, empty octet");
      return 0;
    }

    # Normal v6 octet ?
    if (/^[a-f\d]{1,4}$/i){
      $self->addError("Invalid IP address, bad characters in octet");
      return 0;
    }

    # Last octet - is it IPv4 ?
    if (($count == $num + 1) && $self->isIPv4($octet) ) {
      $self->addError("Invalid IP address $ip");
      $num++; # ipv4 is two octets
      return 0;
    }
  }

  # number of octets
  if ($ip !~ /::/ && $num != 7) {
    $self->addError("Invalid number of octets: " . ($num + 1));
    return 0;
  }    

  # valid IPv6 address
  return 1;
}

1;
