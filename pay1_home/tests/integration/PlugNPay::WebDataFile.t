#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );

use lib $ENV{'PNP_PERL_LIB'};


require_ok('PlugNPay::WebDataFile'); # test that we can load the module!
testCleanPathMultipleSlashes();
testCleanPathEndSlash();
testLoadFile();
testBadFileNames();
testSubPrefix();
testBadSubPrefix();
testBadStorageKey();

#############
# THE TESTS #
#############
sub testCleanPathMultipleSlashes {
  my $path = '/home//pay1/webtxt////templates/index.html'; # doesn't really exist, checking for multiple slashes normalization
  $path = PlugNPay::WebDataFile::_cleanPath($path);
  is($path,'/home/pay1/webtxt/templates/index.html');
}

sub testCleanPathEndSlash {
  my $path = '/home/pay1/webtxt/templates//'; # doesn't really exist, checking for end slashes removal
  $path = PlugNPay::WebDataFile::_cleanPath($path);
  is($path,'/home/pay1/webtxt/templates');
}

sub testLoadFile {
  my $webDataFile = new PlugNPay::WebDataFile();
  eval {
    $webDataFile->readFile({ fileName => 'chrisincco.txt', storageKey => 'linkedAccounts' });
  };
  is($@,'');
}

sub testBadFileNames {
  # bad filename test
  eval {
    my $webDataFile = new PlugNPay::WebDataFile();
    $webDataFile->readFile({ fileName => '../../../../etc/passwd', storageKey => 'linkedAccounts' });
  };
  isnt($@,'');
}

sub testSubPrefix {
  # bad filename test
  eval {
    my $webDataFile = new PlugNPay::WebDataFile();
    $webDataFile->readFile({ fileName => 'chrisincco.txt', storageKey => 'linkedAccounts', subPrefix => 'subdir_for_tests' });
  };
  is($@,'');
}

sub testBadSubPrefix {
  # bad filename test
  eval {
    my $webDataFile = new PlugNPay::WebDataFile();
    $webDataFile->readFile({ fileName => 'chrisincco.txt', storageKey => 'linkedAccounts', subPrefix => '../' });
  };
  isnt($@,'');
}

sub testBadStorageKey {
  # bad filename test
  eval {
    my $webDataFile = new PlugNPay::WebDataFile();
    $webDataFile->readFile({ fileName => 'chrisincco.txt', storageKey => 'gobledygook', subPrefix => '../' });
  };
  isnt($@,'');
}
