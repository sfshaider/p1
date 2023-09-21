#!/bin/env perl
BEGIN {
  $ENV{'DEBUG'} = undef; # ensure debug is off, it's ugly, and not needed for testing
}

use strict;
use Test::More qw( no_plan );
use Data::Dumper;

use lib $ENV{'PNP_PERL_LIB'};


require_ok('miscutils'); # test that we can load the module!

# TestLegacyCheckTransGetFlagsGenerateQuery();
# TestLegacyCheckTransDuplicateCheck();
TestLegacyCheckTrans();

# tests for _generateLegacyCheckTransGetFlagsQuery
# args:
#   my $username = $input->{'username'};
#   my $orderId = $input->{'orderId'};
#   my $startDate = $input->{'startDate'};
#   my $accountType = $input->{'accountType'};


#########
# TESTS #
#########
sub TestLegacyCheckTransGetFlagsGenerateQuery {
  my $tests = {
    credit => {
      input => {
        username => 'pnpdemo2',
        orderId  => '2020022312384500001',
        startDate => '20191120',
        accountType => 'credit'
      }
    }
  };

  use Data::Dumper;
  print Dumper($tests);
  foreach my $subtest (keys %{$tests}) {
    print "testing $subtest\n";
    my $testInput = $tests->{$subtest}{'input'};
    my $output = miscutils::_legacyCheckTransGetFlagsGenerateQuery($testInput);
    diag($output->{'query'} . " with values " . join(',',@{$output->{'values'}}));
    isnt($output,'');
  }
}

sub TestLegacyCheckTransDuplicateCheck {
  my $tests = {
    'duplicateAuth' => {
      input => {
        username => 'pnpdemo',
        orderId => '1234567890',
        operation => 'auth',
        allowMultipleReturns => 1,
        testData => {
          mockDuplicateRows => [{
            finalstatus => 'success',
            descr => 'success'
          }]
        }
      },
      result => {
        FinalStatus => 'success',
        MStatus => 'success',
        MErrMsg => 'Duplicate auth: success',
        Duplicate => 'yes'
      }
    },
    'non-duplicateAuth' => {
      input => {
        username => 'pnpdemo',
        orderId => '1234567890',
        operation => 'auth',
        allowMultipleReturns => 1,
        testData => {
          mockDuplicateRows => []
        }
      },
      result => {
      }
    },
    'postauthDuplicate' => {
      input => {
        username => 'pnpdemo',
        orderId => '1234567890',
        operation => 'postauth',
        allowMultipleReturns => 1,
        testData => {
          mockDuplicateRows => [{
            finalstatus => 'success',
            descr => 'success'
          }]
        }
      },
      result => {
        FinalStatus => 'success',
        MStatus => 'success',
        MErrMsg => 'Duplicate postauth: success',
        Duplicate => 'yes'
      }
    },
    'postauth' => {
      input => {
        username => 'pnpdemo',
        orderId => '1234567890',
        operation => 'postauth',
        allowMultipleReturns => 1,
        testData => {
          mockDuplicateRows => []
        }
      },
      result => undef
    }
  };

  foreach my $subtest (keys %{$tests}) {
    my $test = $tests->{$subtest};
    my $result = miscutils::_legacyCheckTransDuplicateCheck($test->{'input'});
    my $matches = 1;
    is(keys %{$result}, keys %{$test->{'result'}});
    my %allKeys = map { $_ => 1 } (keys %{$result}, keys %{$test->{'result'}});
    foreach my $key (keys %allKeys) {
      if ($result->{$key} ne $test->{'result'}{$key}) {
        $matches = 0;
        diag(sprintf('value missmatch for key %s; "%s" vs "%s"', $key, $result->{$key}, $test->{'result'}{$key}));
      }
    }
    ok($matches);
  }
}

# Some things noticed while creating tests that check trans should probably do that it doesn't:
#  1) the functions do not do duplicate checking on auths.
#  2) the functions do not check to see if an auth can be marked
#  3) a check on an auth comes back with the reauth_flag as 1, which in some cases may be true, but generally is not.
sub TestLegacyCheckTrans {
  diag('Running tests for TestLegacyCheckTrans');
  my $tests = {
    'postauth-duplicate' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'postauth', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockDuplicateRows => [{ finalstatus => 'success', descr => 'success' }],
      },
      result => {
        MStatus => 'success',
        FinalStatus => 'success',
        MErrMsg => 'Duplicate postauth: success',
        Duplicate => 'yes'
      }
    },
    'reauth-duplicate' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'reauth', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockDuplicateRows => [{ finalstatus => 'success', descr => 'success' }],
      },
      result => {
        MStatus => 'success',
        FinalStatus => 'success',
        MErrMsg => 'Duplicate reauth: success',
        Duplicate => 'yes'
      }
    },
    'newreturn-duplicate' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'newreturn', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockDuplicateRows => [{ finalstatus => 'success', descr => 'success' }],
      },
      result => {
        MStatus => 'success',
        FinalStatus => 'success',
        MErrMsg => 'Duplicate newreturn: success',
        Duplicate => 'yes'
      }
    },
    'return-duplicate-allowDuplicateReturns0' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'return', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        features => {
          allow_multret => 0
        },
        mockDuplicateRows => [{ finalstatus => 'success', descr => 'success' }],
      },
      result => {
        MStatus => 'success',
        FinalStatus => 'success',
        MErrMsg => 'Duplicate return: success',
        Duplicate => 'yes'
      }
    },
    'return-duplicate-allowDuplicateReturns1' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'return', amount => '2.34', cardName => 'Bobby Tables' },
      testData => {
        features => {
          allow_multret => 1
        },
        mockTransactionHistory => [
          { amount => 'usd 12.34', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'success', operation => 'auth', orderid => '123567890'},
          { amount => 'usd 1.34', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'success', operation => 'return', orderid => '123567890'}
        ]
      },
      result => {
        setlret_flag => 1,
        amount => 'usd 1.34',
        authamt => 'usd 12.34',
        orderId => '123567890',
        allow_mark => 1,
        allow_reauth => 1,
        auth_flag => 1,
        reauth_flag => 1
      }
    },
    'returnprev-duplicate' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'returnprev', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockDuplicateRows => [{ finalstatus => 'success', descr => 'success' }],
      },
      result => {
        MStatus => 'success',
        FinalStatus => 'success',
        MErrMsg => 'Duplicate returnprev: success',
        Duplicate => 'yes'
      }
    },
    'void-duplicate' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'void', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockDuplicateRows => [{ finalstatus => 'success', descr => 'success' }],
      },
      result => {
        MStatus => 'success',
        FinalStatus => 'success',
        MErrMsg => 'Duplicate void: success',
        Duplicate => 'yes'
      }
    },
    'mark-duplicate' => { # mark should get converted to postauth
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'mark', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockDuplicateRows => [{ finalstatus => 'success', descr => 'success' }],
      },
      result => {
        MStatus => 'success',
        FinalStatus => 'success',
        MErrMsg => 'Duplicate postauth: success', # mark shold be converted to postauth!!!
        Duplicate => 'yes'
      }
    },
    'authSuccess' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'auth', amount => '12.34', cardName => 'Bobby Tables'
      },
      testData => {
        mockTransactionHistory => [{ amount => 'usd 12.34', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'success', operation => 'auth', orderid => '123567890'}]
      },
      result => {
        allow_reauth => 1,
        amount => 'usd 12.34',
        orderId => '123567890',
        allow_mark => 1,
        allow_void => 1,
        auth_flag => 1,
        reauth_flag => 1,
        authamt => 'usd 12.34'
      }
    },
    'authProblem' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'auth', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockTransactionHistory => [{ amount => 'usd 12.34', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'problem', operation => 'auth', orderid => '123567890' }]
      },
      result => {
        amount => 'usd 12.34',
        orderId => '123567890',
        allow_void => 1,
        allow_reauth => 1,
        reauth_flag => 1
      }
    },
    'authVoided' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'auth', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockTransactionHistory => [{ amount => 'usd 12.34', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'success', operation => 'void', orderid => '123567890' }]
      },
      result => {
        amount => 'usd 12.34',
        void_flag => 1,
        orderId => '123567890',
        reauth_flag => 0
      }
    },
    'postauthSuccess' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'auth', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockTransactionHistory => [
          { amount => 'usd 12.34', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'success', operation => 'auth', orderid => '123567890' },
          { amount => 'usd 12.34', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'success', operation => 'postauth', orderid => '123567890' }
        ]
      },
      result => {
        amount => 'usd 12.34',
        auth_flag => 1,
        settled_flag => 1,
        orderId => '123567890',
        allow_return => 1,
        reauth_flag => 0,
        authamt => 'usd 12.34',
        allow_mark => 1 # this makes no sense but is apparently a bug in the old code
      }
    },
    'postauthProblem' => {
      input => { username => 'pnpdemo2', orderId => '123567890', accountType => 'credit', processor => 'testprocessor', operation => 'auth', amount => '12.34', cardName => 'Bobby Tables' },
      testData => {
        mockTransactionHistory => [
          { amount => 'usd 12.34', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'success', operation => 'auth', orderid => '123567890' },
          { amount => 'usd 12.34', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'problem', operation => 'postauth', orderid => '123567890' }
        ]
      },
      result => {
        allow_reauth => 1,
        amount => 'usd 12.34',
        orderId => '123567890',
        allow_mark => 1,
        allow_void => 1,
        auth_flag => 1,
        reauth_flag => 1,
        authamt => 'usd 12.34'
      }
    },
    'postauthBlankAcctType' => {
      input => { username => 'pnpdemo2', orderId => '20200201', accountType => '', processor => 'testprocessor', operation => 'postauth', amount => 'usd 104.00', cardName => 'Bobby Tables' },
      testData => {
        mockTransactionHistory => [
          { amount => 'usd 104.00', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'success', operation => 'auth', orderid => '20200201' }
        ]
      },
      result => {
        allow_reauth => 1,
        amount => 'usd 104.00',
        orderId => '20200201',
        allow_mark => 1,
        allow_void => 1,
        auth_flag => 1,
        reauth_flag => 1,
        authamt => 'usd 104.00'
      }
    },
    'postauthNullAcctType' => {
      input => { username => 'pnpdemo2', orderId => '20200201', accountType => undef, processor => 'testprocessor', operation => 'postauth', amount => 'usd 104.00', cardName => 'Bobby Tables' },
      testData => {
        mockTransactionHistory => [
          { amount => 'usd 104.00', trans_date => '20200201', trans_time => '20200201113400', finalstatus => 'success', operation => 'auth', orderid => '20200201' }
        ]
      },
      result => {
        allow_reauth => 1,
        amount => 'usd 104.00',
        orderId => '20200201',
        allow_mark => 1,
        allow_void => 1,
        auth_flag => 1,
        reauth_flag => 1,
        authamt => 'usd 104.00'
      }
    }
  };

  eval {
    foreach my $subtestName (keys %{$tests}) {
      my $subtest = $tests->{$subtestName};
      diag("running test $subtestName\n");
      my ($result) = miscutils::_legacyCheckTrans($subtest->{'input'}, $subtest->{'testData'});
      my $match = 1;

      if (!is(keys %{$result}, keys %{$subtest->{'result'}})) {
        $match = 0;
      }

      foreach my $key (keys %{$subtest->{'result'}}) {
        if (!is($result->{$key},$subtest->{'result'}{$key})) {
          $match = 0; # for diag.
        }
      }

      if (!$match) {
        diag("got:      " . Dumper($result));
        diag("expected: " . Dumper($subtest->{'result'}));
      }
    }
  };
  diag($@);
}
