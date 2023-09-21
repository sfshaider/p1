package PlugNPay::Security::Password;

use strict;

use PlugNPay::Util::Encryption::Random;
use PlugNPay::Util::Hash;
use PlugNPay::DBConnection;

our $_algorithms;
our $_defaults;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_defaults) {
    $self->_initializeDefaults();
  }

  $self->initializeAlgorithms();

  return $self;
}

sub _initializeDefaults {
  my $self = shift;

  # hard coding to remove dependency on login database.  this will not change.
  # future changes will actually use an authentication service
  if (ref($_defaults) ne 'HASH') {
    $_defaults = {
      algorithm => 'shapnpv1',
      rounds => 1
    };
  }
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setPassword {
  my $self = shift;
  my $password = shift;
  $self->{'password'} = $password;
}

sub getPassword {
  my $self = shift;
  return $self->{'password'};
}

sub setRounds {
  my $self = shift;
  my $rounds = shift;
  if ($rounds =~ /^\d+$/) {
    $self->{'rounds'} = $rounds;
  }
}

sub getRounds {
  my $self = shift;
  return $self->{'rounds'} || $self->getDefaultRounds();
}

sub getDefaultRounds {
  my $self = shift;
  return $_defaults->{'rounds'};
}

sub setAlgorithm {
  my $self = shift;
  my $algorithm = shift;
  if (!defined $_algorithms->{$algorithm}) {
    return 0;
  }
  return $self->{'algorithm'} = $algorithm;
}

sub getAlgorithm {
  my $self = shift;
  return $self->{'algorithm'} || $self->getDefaultAlgorithm();
}

sub getDefaultAlgorithm {
  my $self = shift;
  return $_defaults->{'algorithm'};
}

sub algorithmUsesRounds {
  my $self = shift;
  my $algorithm = shift;

  if ($algorithm eq 'shapnpv1' || $algorithm eq 'sha1') {
    return 0;
  }
  return 1;
}

sub setType {
  my $self = shift;
  my $type = shift;
  my ($algorithm,$rounds) = split / +/,$type;

  if ($self->setAlgorithm($algorithm)) {
    $self->setRounds($rounds);
    return 1;
  }
}

sub getType {
  my $self = shift;

  return $self->getTypeString($self->getAlgorithm());
}

sub getDefaultType {
  my $self = shift;

  return $self->getTypeString($self->getDefaultAlgorithm());
}

sub getTypeString {
  my $self = shift;

  my $algorithm = $self->getAlgorithm();

  if ($self->algorithmUsesRounds($algorithm)) {
    return $algorithm . ' ' . $self->getRounds();
  } else {
    return $algorithm;
  }
}

sub setBinarySalt {
  my $self = shift;
  my $salt = shift;
  $self->{'salt'} = $salt;
}

sub setHexSalt {
  my $self = shift;
  my $salt = shift;
  $self->{'salt'} = pack('H*',$salt);
}

sub getBinarySalt {
  my $self = shift;
  my $size = shift || 32;

  if (!defined $self->{'salt'}) {
    $self->{'salt'} = $self->generateRandomBytes($size);
  }

  return $self->{'salt'};
}

sub getHexSalt {
  my $self = shift;
  return unpack('H*',$self->getBinarySalt());
}

sub verifyPassword {
  my $self = shift;
  my $settings = shift;

  my $ref = ref($self);
  my $verifier = eval "new $ref()";

  $verifier->setUsername($settings->{'username'});
  $verifier->setPassword($settings->{'password'});
  $verifier->setHexSalt($settings->{'salt'});
  $verifier->setType($settings->{'type'});

  my $computedHash = $verifier->getHash();

  my $hash = $settings->{'hash'};

  $hash =~ s/\s+//g;
  $computedHash =~ s/\s+//g;

  return ($computedHash eq $hash);
}


sub getHash {
  my $self = shift;

  my $hashInfo = $self->getHashInfo();
  if (defined $hashInfo) {
    return $hashInfo->{'hash'};
  }
}

sub getHashInfo {
  my $self = shift;

  my $algorithm = $self->getAlgorithm();

  if (!defined $_algorithms->{$algorithm}) {
    die('Algorithm not defined: ' . $algorithm);
    return '';
  }

  my $passwordHash = &{$_algorithms->{$algorithm}}($self);

  return {hash => $passwordHash, salt => $self->getHexSalt(), type => $self->getType(), rounds => $self->getRounds(), algorithm => $self->getAlgorithm()};
}

sub initializeAlgorithms {
  my $self = shift;
  if (!defined $_algorithms) {
    my %initAlgorithms;
    $initAlgorithms{'sha1'} = \&algorithm_SHA1;
    $initAlgorithms{'shapnpv1'} = \&algorithm_SHAPNPV1;
    $initAlgorithms{'sha256_salted_concat'} = \&algorithm_SHA256_SALTED_CONCAT;

    $_algorithms = \%initAlgorithms;
  }
}

# Note: Not supporting rounds with SHA1 as it should not be used going forward
sub algorithm_SHA1 {
  my $self = shift;

  my $password = $self->getPassword();

  my $hasher = new PlugNPay::Util::Hash();
  $hasher->add($password);
  my $unformatted = $hasher->sha1();
  my @sections = ($unformatted =~ /(\w{8})/g);
  return join(' ',@sections);
}

# Note: Not supporting rounds with SHAPNPV1 as it should not be used going forward
sub algorithm_SHAPNPV1 {
  my $self = shift;

  my $username = $self->getUsername();
  my $password = $self->getPassword();

  if (!defined $username) {
    $self->dieForUsernameFailure();
  }

  my $hasher = new PlugNPay::Util::Hash();
  $hasher->add('#% ' . $username . $password . ' %#');
  my $unformatted =  $hasher->sha1();
  my @sections = ($unformatted =~ /(\w{8})/g);
  return join(' ',@sections);
}


# Purpose:
# Generates hashes for the number of rounds set.
#
# Each round is a hash of the previous result prepended with the salt
# Once all rounds are generated, they are concatenated and then hashed
# one final time.
#
# Notes:  
#   The number of rounds increases CPU resources and Memory resources
#   required to compute the hash. (Linear)
#
#   Each round requires 32 bytes of RAM.
#   32768 rounds = 1 Megabyte.
#
sub algorithm_SHA256_SALTED_CONCAT {
  my $self = shift;

  my $username = $self->getUsername();
  my $password = $self->getPassword();

  if (!defined $username) {
    $self->dieForUsernameFailure();
  }

  my $salt = $self->getBinarySalt();
  my $rounds = $self->getRounds();

  my $hasher = new PlugNPay::Util::Hash();

  my @rounds;

  for (my $i = 0; $i < $rounds; $i++) {
    $password = $salt . $username . $password;

    $hasher->reset();
    $hasher->add($password);

    $password = $hasher->sha256('0b');
    push @rounds,$password;
  }

  $hasher->reset();
  $hasher->add(join('',@rounds));
  $password = $hasher->sha256();

  return $password;
}

sub generateRandomBytes {
  my $self = shift;
  my $size = shift;

  return PlugNPay::Util::Encryption::Random::random($size);
}

sub dieForUsernameFailure {
  my $self = shift;
  die('Username required for algorithm: ' . $self->getAlgorithm());
}


1;
