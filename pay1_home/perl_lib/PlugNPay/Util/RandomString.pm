package PlugNPay::Util::RandomString;

use strict;
use Time::HiRes qw/time/;

our $seeded = 0;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!$seeded) {
    srand(time());
    $seeded = 1;
  } 

  return $self;
}

## Helper Sub-Function: Generate random alphanumeric string
sub randomAlphaNumeric {
  my $self = shift;
  my $length = shift;
  my $unambiguous = shift || 1; # default to not allow visually ambiguous characters such as 1 vs l vs I

  my ($pass, $letter, $asciicode);
  while ($length > 0) {
    $asciicode = int(rand 1 * 123);
    if ( ( $asciicode > 48 && $asciicode < 58 ) ||
         ( $asciicode > 64 && $asciicode < 91 ) ||
         ( $asciicode > 96 && $asciicode < 123) ) {
      $letter = chr($asciicode);
      if ($unambiguous && $letter !~ /[Iijyvl10Oo]/) {
        $length--;
        $pass .= $letter;
      }
    }
  }
  return $pass;
}

1;
