package PlugNPay::Util::Hash;
# Wrapper for hashing algorithms to ensure future compatibility.
#
# Unless you have a REALLY good reason for it, you should use this
# module for all of your hashing needs.
#
# If this module doesn't do what you need it to....add the
# functionaility to it....in a sane and consistent way.
use strict;

use Digest;
use Digest::SHA qw(hmac_sha256 sha256_hex hmac_sha256_base64);
use Digest::MD5;
use Digest::HMAC_SHA1;
use PlugNPay::Util::Encryption::Random;
use Crypt::Eksblowfish::Bcrypt qw(en_base64);

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  return $self;
}


# Add data to be hashed.  Can be called multiple times to append data to be hashed.
sub add {
  my $self = shift;
  my $data = shift;

  if (exists $self->{'data'}) {
    $self->{'data'} .= $data;
  } else {
    $self->{'data'} = $data;
  }
}

sub getData {
  my $self = shift;
  return $self->{'data'};
}

# reset the object to it's initial state (clear all unhashed data)
sub reset {
  my $self = shift;

  if (exists $self->{'data'}) {
    delete $self->{'data'};
  }
}

sub _sha {
  my $self = shift;
  my $mode = shift;
  my $size = shift;

  if (!defined $self->{'sha'}{$size}) {
    $self->{'sha'}{$size} = new Digest::SHA($size);
  }

  if (!exists $self->{data}) {
    return undef;
  }

  $self->{'sha'}{$size}->reset();
  $self->{'sha'}{$size}->add($self->getData());

  if (!defined $mode || $mode eq '0x') {
    return $self->{'sha'}{$size}->hexdigest;
  } elsif ($mode eq '0b') {
    return $self->{'sha'}{$size}->digest;
  }
}

sub _hmac {
  my $self = shift;
  my $size = shift;
  my $key = shift;
  my $data = $self->getData();

  my $digest;
  if ($size == 1) {
    my $hmac = new Digest::HMAC_SHA1($key);
    $hmac->add($data);
    $digest = $hmac->digest();
  } elsif ($size == 256) {
    $digest = hmac_sha256($data, $key);
  }

  return $digest;
}

sub hmac {
  my $self = shift;
  my $key = shift;
  return $self->_hmac(1, $key);
}

sub hmac_256 {
  my $self = shift;
  my $key = shift;
  return $self->_hmac(256, $key);
}

sub hmacSHA256Base64 {
  my $self = shift;
  my $key = shift;
  my $withPadding = shift;
  my $data = $self->getData();
  my $digested = hmac_sha256_base64($data, $key);

  #hmac_sha256_base64 does not pad apparently, which is dumb
  if ($withPadding) {
    if (length($digested) % 4 > 0) {
      my $equalsNeeded = 4 - (length($digested) % 4);
      $digested .= '=' x $equalsNeeded;
    }
  }

  return $digested;
}

sub sha256 {
  my $self = shift;
  my $mode = shift;

  return $self->_sha($mode,'256');
}

sub sha1 {
  my $self = shift;
  my $mode = shift;

  return $self->_sha($mode,'1');
}

sub MD5 {
  my $self = shift;
  my $mode = shift;
  return $self->_md5($mode);
}

sub _md5 {
  my $self = shift;
  my $mode = shift;

  if (!defined $self->{'md5'}) {
    $self->{'md5'} = new Digest::MD5();
  }

  $self->{'md5'}->reset();
  $self->{'md5'}->add($self->getData());
  if (!defined $mode || $mode eq '0x') {
    return $self->{'md5'}->hexdigest();
  } else {
    return $self->{'md5'}->digest();
  }
}

sub bcrypt {
  my $self = shift;
  my $mode = shift;
  return $self->_bcrypt($mode);
}

sub _bcrypt {
  my $self = shift;
  my $mode = shift;

  my $enc_random = new PlugNPay::Util::Encryption::Random();
  my $salt = $enc_random->random(16);
  return '$2a$10$' . en_base64($salt) . en_base64(Crypt::Eksblowfish::Bcrypt::bcrypt_hash({
    key_nul => 1,
    cost => 10,
    salt => $salt
  },$self->getData()));
}

sub setRounds {
  my $self = shift;
  my $rounds = shift || 10;
  if ($rounds =~ /^\d+$/) {
    $self->{'rounds'} = $rounds;
  }
}

sub getRounds {
  my $self = shift;
  if (!defined $self->{'rounds'}) {
    $self->setRounds();
  }
  return $self->{'rounds'};
}


1;
