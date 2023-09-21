package PlugNPay::UI::StaticContentServer;

use overload '""' => 'randomStaticServer';

use strict;

use Time::HiRes;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub randomStaticServer {
  my $self = shift;
  my $resource = shift;
  my $int;

  if ($resource) { # use a seed to generate the same number every time for the same resource, caching friendly
    $int = _stringToInteger($resource);
  } else {
    $int = _randomInt();
  }
  return sprintf('www%d.static%s.gateway-assets.com', $int, _devString());
}

sub _devString {
  return $ENV{'DEVELOPMENT'} ? '.dev' : '';
}

sub _randomInt {
  srand(Time::HiRes::time());
  return int(rand(10));
}

sub _stringToInteger {
  my $input = shift;
  my @characters = split(//,$input);
  my $value = 0;
  for my $char (@characters) {
    $value += ord($char);
  }
  return $value % 10;
}

1;
