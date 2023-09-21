#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use Data::Dumper;

use lib $ENV{'PNP_PERL_LIB'};

require_ok('PlugNPay::DBConnection'); # test that we can load the module!

TestFetchallOrDieMock();
TestGetColumnsFromTable();
TestFetchrowOrDieMock();


sub TestFetchallOrDieMock {
  my $test = {
    input => {
      mockRows => [{
        columnA => 1,
        columnB => 'string'
      }]
    },
    result => {
      columnA => 1,
      columnB => 'string'
    }
  };

  my $dbs = new PlugNPay::DBConnection();
  $dbs->fetchallOrDie('_test_','_test_',[],{},{ callback => sub {
    my $row = shift;
    isnt($row,undef);
    foreach my $key (keys %{$row}) {
      is($row->{$key},$test->{'result'}{$key});
    }
  }, mockRows => $test->{'input'}{'mockRows'}});
}

sub TestGetColumnsFromTable {
  my $dbs = new PlugNPay::DBConnection();
  my $columnInfo = $dbs->getColumnsForTable({ database => 'pnpdata', table => 'operation_log' });
  
  my $lowerColInfo = $dbs->getColumnsForTable({ database => 'pnpdata', table => 'operation_log', 'format' => 'lower'});
  my $lowerString = join('', keys %{$lowerColInfo});
  my $isLower = $lowerString =~ /^[a-z\_\-0-9]*$/;
  is($isLower,1);

  my $upperColInfo = $dbs->getColumnsForTable({ database => 'pnpdata', table => 'operation_log', 'format' => 'upper'});
  my $upperString = join('', keys %{$upperColInfo});
  my $isUpper = $upperString =~ /^[A-Z\_\-0-9]*$/;
  is($isUpper,1);

  print Dumper($columnInfo);
}

sub TestFetchrowOrDieMock {
  my $test = {
    input => {
      mockRows => [{
        columnA => 1,
        columnB => 'string'
      },
      {
        columnA => 2,
        columnB => 'stringy dingy'
      },
      {
        columnA => 2,
        columnB => 'stringy dingy dingy'
      }]
    }
  };

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchrowOrDie('pnpmisc',q/
    SELECT * FROM customers
  /,[],{});
  my $next = $result->{'next'};
  while (my $row = &{$next}()) {
    print $row->{'username'} . "\n";
  }
  &{$result->{'finished'}}();
}
