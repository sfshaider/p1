package PlugNPay::Util::Encryption::Random;

use strict;
use POSIX qw(ceil);

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub random {
  my $self = shift;
  my $length = shift || $self;

  if (!$length) {
    die('Invalid length for random bytes.');
  }

  my $key;

  # try Bytes::Random::Secure, then Crypt::Random if Bytes::Random::Secure is not installed.

  eval {
    require Bytes::Random::Secure;
    $key = Bytes::Random::Secure->new( 
      Bits => (32 * ceil($length/4) ),
      NonBlocking => 1
    )->bytes($length);
  };

  if ($@) {
    eval {
      require Crypt::Random;
      $key = Crypt::Random::makerandom_octet(Length => $length,Strength => 1);
    };
  }

  if ($key) {
    return $key;
  } else {
    die('Could not generate random bytes.');
  }
}

1;
