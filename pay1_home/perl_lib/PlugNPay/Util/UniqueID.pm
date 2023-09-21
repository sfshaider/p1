package PlugNPay::Util::UniqueID;

use strict;
use Data::UUID();
use Digest::MD5;
use PlugNPay::Sys::Time;
use PlugNPay::Die;


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  $self->{'generator'} = new Data::UUID;
  $self->{'time'} = new PlugNPay::Sys::Time();
  $self->generate();

  return $self;
}

# generates a unique id and stores it internally and also returns it as a string
sub generate {
  my $self = shift;

  my $uuid = $self->{'generator'}->create_str();
  $uuid =~ s/\-//g;

  #my $time = $self->{'time'}->nowInFormat('yyyymmdd');
  my $time = $self->{'time'}->nowInFormat('hex');
  $time = reverse $time;

  my $uniqueID = $time . $uuid;
  my $checksum = substr(Digest::MD5::md5_hex($uniqueID),0,3);
  $checksum =~ tr/a-z/A-Z/;
  $self->{'id'} = $uniqueID . $checksum;
  return $self->{'id'};
}


# returns a hex representation of the unique id
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

  $hex = uc $hex;
  $self->{'id'} = $hex;
}

# takes a hex representation of a unique id and returns it's binary value;
sub fromHexToBinary {
  my $self = shift;
  my $data = shift || $self;
  if ($data) {
    if (ref($data) ne '') {
      die('object input or undefined input to fromHexToBinary?');
    }
    if ($data =~ /[^a-fA-F0-9]/) {
      return $data;
    }

    my $uid = new PlugNPay::Util::UniqueID();
    $uid->fromHex($data);
    return $uid->inBinary();
  }
  return undef;
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
  chop $hex;
  $self->fromHex($hex);
}

# takes a binary representation of a unique id and returns it's hex value;
sub fromBinaryToHex {
  my $self = shift;
  my $data = shift || $self;
  if ($data) {
    if (ref($data) ne '') {
      die('object input or undefined input to fromBinaryToHex?');
    }

    if ($data =~ /^[a-zA-Z0-9]+$/) {
      return $data;
    }

    my $uid = new PlugNPay::Util::UniqueID();
    $uid->fromBinary($data);
    return $uid->inHex();
  }
  return undef;
}

# returns a binary string representation of a unique id.  warning: output is very long!
sub inBinaryString {
  my $self = shift;
  return unpack('b*',$self->{'id'});
}

# takes a binary string representation of a unique id and stores it internally to be analyzed with the other object methods
sub fromBinaryString {
  my $self = shift;
  my $binaryString = shift || undef;

  if (!defined $binaryString) {
    return undef;
  }

  $self->fromBinary(pack('b*',$binaryString));
}

# next two functions return the date/time as a PlugNPay::Sys::Time objectfrom the unique id
sub date {
  my $self = shift;
  return $self->time();
}
sub time {
  my $self = shift;
  return $self->_dateFromUniqueID($self->{'id'});
}

# internal method, returns the date from the unqiue id
sub _dateFromUniqueID {
  my $self = shift;

  my $uniqueID = shift || undef;

#  if (ref($self) != 'PlugNPay::Util::UniqueID') {
#    $uniqueID = $self;
#  }

  if (!defined $uniqueID) {
    return undef;
  }

  my $timeSection = substr($uniqueID,0,8);
  $timeSection = reverse $timeSection;
  my $date = new PlugNPay::Sys::Time('hex',$timeSection);
  return $date;
}

# checks a unique id to validate it's checksum is correct, used for fraud prevention, object method
sub validate {
  my $self = shift;
  return $self->validateUniqueID($self->inHex());
}

# checks a unique id to validate it's checksum is correct, used for fraud prevention
sub validateUniqueID {
  my $self = shift;
  my $uniqueID = shift || undef;
  my $fullUniqueID = $uniqueID;

  if (!defined $uniqueID) {
    return undef;
  }

  my $checksum = substr($uniqueID,-3,3);
  $uniqueID =~ s/^(.*).{3}/$1/;

  my $uniqueIDHash = substr(Digest::MD5::md5_hex($uniqueID),0,3);
  $uniqueIDHash =~ tr/a-z/A-Z/;

  return ($uniqueIDHash eq $checksum && length($fullUniqueID) > 25);
}

1;
