use strict;
use warnings;
use diagnostics;
use Test::More qw( no_plan );
use lib $ENV{'PNP_PERL_LIB'};

sub getStr {
  my $str = shift;
  return $str;
}

sub addTwoNumbers {
  my $num1 = shift;
  my $num2 = shift;
  return $num1 + $num2;
}

sub lowerCaseStr {
  my $str = shift;
  return lc($str);
}

sub thisShouldFail {
  my $num = 0;
  return $num;
}

is(&getStr('cat'), 'cat', 'getStr() passed, return param passed in');
is(&addTwoNumbers(2,2), 4, 'addTwoNumbers() passed, returned 4');
is(&lowerCaseStr('BOB'), 'bob', 'lowerCaseStr() passed, returned bob');
is(&thisShouldFail(), '1', 'thisShouldFail() failed, returned 0');
