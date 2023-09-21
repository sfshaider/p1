use strict;
use warnings;
use diagnostics;
use Test::More qw( no_plan );
use PlugNPay::Sys::Time;

use strict;

# db is just an alias for db_gm
# these tests need to be expanded...
my $conversions = [
  { 
    in => 'iso',
    from => '20181225T000000Z',
    to => [
      { format => 'iso', expect => '20181225T000000Z' },
      { format => 'log_gm', expect => '12/25/2018 00:00:00' },
    ]
  },{
    in => 'mm/yy',
    from => '12/18',
  },{
    in => 'mmyy',
    from => '1218',
  },{
    in => 'db_gm',
    from => '2018-12-18 08:40:33',
    options => {},
    to => [
      { format => 'iso', expect => '20181218T084033Z' },
      { format => 'db_gm', expect => '2018-12-18 08:40:33' },
      { format => 'db', expect => '2018-12-18 08:40:33' },
    ]
  },{
    in => 'unix',
    from => '1545013513',
    to => [
      { format => 'iso', expect => '20181217T022513Z' },
      { format => 'log_gm', expect => '12/17/2018 02:25:13' },
      { format => 'db_gm', expect => '2018-12-17 02:25:13' },
      { format => 'unix', expect => '1545013513' },
    ]
  },{
    in => 'yyyymmdd',
    from => '20181216',
    to => [
      { format => 'iso', expect => '20181216T000000Z' },
      { format => 'log_gm', expect => '12/16/2018 00:00:00' },
      { format => 'yyyymmdd', expect => '20181216' },
    ]
  }
];

my $tests = [
  'testDetections',
  'testConversions',
];

sub runTests {
  my $status = 1;

  foreach my $test (@{$tests}) {
print 'running test: ' . $test . "\n";
    eval "$test()";
  }
}

sub testDetections {
  foreach my $test (@{$conversions}) {
    my $time = new PlugNPay::Sys::Time();
    is($time->detectFormat($test->{'from'},$test->{'options'}),$test->{'in'},'detection of ' . $test->{'in'} . ' for ' . $test->{'from'});
  }
}

sub testConversions {
  foreach my $test (@{$conversions}) {
    my $time = new PlugNPay::Sys::Time();
    my $to = $test->{'to'} || [];
    foreach my $toItem (@{$to}) {
      my $toFormat = $toItem->{'format'} || $test->{'in'};
      my $expect = $toItem->{'expect'} || $test->{'from'};
      is(
        $time->inFormatDetectType($toFormat,$test->{'from'},$test->{'options'}),
        $expect,
        'conversion of ' . $test->{'from'} . ' from ' . $test->{'in'} . ' to ' . $toFormat
      );
    }
  }
}

runTests();
