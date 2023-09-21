#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::DBConnection;
use PlugNPay::CardData;
use PlugNPay::CreditCard;
use PlugNPay::Logging::DataLog;
use PlugNPay::Sys::Time;
use Data::Dumper;


my $commit = $ENV{'PNP_SCRUB_RECURRING_COMMIT'} || 0;
my $copy = $ENV{'PNP_SCRUB_RECURRING_COPY'} || 0;
my $countOption = $ENV{'PNP_SCRUB_RECURRING_COUNT_OPTION'} || 0;
my $specificDB = $ENV{'PNP_SCRUB_RECURRING_SPECIFIC_DB'} || undef;

my $modeCount = 0;

foreach my $arg (@ARGV) {
  if ($arg =~ /^--commit$/) {
    $commit ||= 1;
    $modeCount++;
  }

  if ($arg =~ /^--copy$/) {
    $copy ||= 1;
    $modeCount++;
  }

  if ($arg =~ /^--count=/) {
    my $val = $arg;
    $val =~ s/^--count=//;
    $countOption = $val;
    if ($countOption !~ /^(all|enccardnumber)$/) {
      $countOption = undef;
    } else {
      $modeCount++;
    }
  }

  if ($arg =~ /^--db=/) {
    my $val = $arg;
    $val =~ s/^--db=//;
    $specificDB = $val;
  }
}

if ($modeCount == 0) {
  print "No mode specified, available modes are --count, --copy, and --commit\n";
  exit(1);
} elsif ($modeCount > 1) {
  print "Only one mode may be specified.\n";
  exit(1);
}

if ($commit) {
  print "WARNING: data will be removed from customer table entries.\n";
  print "Sleeping 1 minute to allow for cancellation.\n";
  sleep 60;
}

if ($copy) {
  print "Data will be copied to carddata service if it does not exist in the carddata service.\n";
}

my $dbNames;
if ($specificDB) {
  $dbNames = [$specificDB];
} else {
  $dbNames = getDatabases();
}

foreach my $dbName (@{$dbNames}) {
  if ($countOption) {
    eval {
      countdb($dbName);
    };
  } elsif ($copy || $commit) {
    eval {
      scrubdb($dbName);
    };
  }

  if ($@) {
    chomp $@;
    print $@ . "\n";
  }
  PlugNPay::DBConnection::cleanup();
  sleep(1);
}

sub getDatabases {
  my $dbs = new PlugNPay::DBConnection();

  my $data = $dbs->fetchallOrDie('dbinfo',q/
    SELECT group_db.db_name as db FROM group_db,`group` WHERE `group`.id = group_db.group_id and `group`.name = 'recurring'
  /,undef, {});

  my @dbNames = map { $_->{'db'} } @{$data->{'result'}};
  return \@dbNames;
}

sub countdb {
  my $dbName = shift;

  my $dbs = new PlugNPay::DBConnection();
   
  my $countQuery = q/ SELECT count(*) as `count` FROM customer /;

  if ($countOption eq 'enccardnumber') {
    $countQuery .= " WHERE enccardnumber <> ''";
  }
  my $countResult = $dbs->fetchallOrDie($dbName,$countQuery, undef, {});
  my $count = $countResult->{'result'}[0]{'count'};
  logSTDOUT("Database $dbName has $count records.\n"); 
}

sub scrubdb {
  my $dbName = shift;

  my $dbs = new PlugNPay::DBConnection();

  # load 1000 customers at a time;
  my $offset = 0;
  my $limit = 1000;

  my $batchResult = $dbs->fetchallOrDie($dbName,q/ SELECT * FROM customer LIMIT / . $offset . ',' . $limit , undef, {});
  while (@{$batchResult->{'result'}} > 0) {
    cleanBatch($dbName,$batchResult->{'result'});
    $offset = $offset + $limit;
    $batchResult = $dbs->fetchallOrDie($dbName,q/ SELECT * FROM customer LIMIT / . $offset . ',' . $limit , undef, {});
  }
}

sub cleanBatch {
  my ($dbName,$batch) = @_;
  my $cd = new PlugNPay::CardData();

  my $batchStart = Time::HiRes::time();
  my $batchSize = @{$batch};
  foreach my $entry (@{$batch}) {
    my $customer = $entry->{'username'};
    my $encryptedCardData = $cd->getRecurringCardData({ username => $dbName, customer => $customer, suppressAlert => 1, suppressError => 1 });

    my $update = 0;
    my $clean = 1;

    if ($entry->{'enccardnumber'}) {
      my $existsInCardData = 0;
      $clean = 0;

      if ($encryptedCardData) {
        $existsInCardData = 1;
      }

      $encryptedCardData ||= $entry->{'enccardnumber'};

      if ($encryptedCardData && !$existsInCardData) {
        if ($commit || $copy) {
          eval {
            $cd->insertRecurringCardData({ username => $dbName, customer => $customer, cardData => $encryptedCardData });
          };

          if ($@) {
            logCustomer($dbName,$customer,"failed to copy card data to carddata service.");
          } else {
            logCustomer($dbName,$customer,"copied card data to carddata service.");
            if (!$copy) {
              $entry->{'enccardnumber'} = undef; # remove the data from the entry.
              $update = 1;
            }
          }
        } else {
          logCustomer($dbName,$customer,"card data needs to be moved to carddata service.");
        }
      } elsif ($encryptedCardData) { # case where there is encrypted card data in the entry and card data DOES exist in carddata service
        $entry->{'enccardnumber'} = undef; # remove the data from the entry.
        logCustomer($dbName,$customer,"will remove card data from entry, already exists in carddata");
        $update = 1;
      }
    }

    my $cc = new PlugNPay::CreditCard();
    $cc->setNumberFromEncryptedNumber($encryptedCardData);
    my $cardNumber = $cc->getNumber();

    next if $cardNumber eq '';

    my @fieldsContainingCC;
    foreach my $key (keys %{$entry}) {
      if ($entry->{$key} =~ $cardNumber) {
        push @fieldsContainingCC,$key;
      }
    }

    if (@fieldsContainingCC) {
      logCustomer($dbName,$customer,'card data in fields: ' . join(',',@fieldsContainingCC) . "\n");
      foreach my $key (@fieldsContainingCC) {
        $entry->{$key} =~ s/$cardNumber//g;
      }
      $update = 1;
    }

    if ($update && $commit) {
      updateEntry($dbName,$entry);
    } else  {
      if (!$update) {
        if ($clean) {
          logCustomer($dbName,$customer,"customer record clean.");
        }
      }
    }
  }
  my $batchEnd = Time::HiRes::time();
  my $batchDuration = $batchEnd - $batchStart;
  my $cps = $batchDuration/$batchSize;
  logSTDOUT(sprintf("Batch Stats: %d records, %.2f seconds, %.2f seconds per record.\n", $batchSize, $batchDuration, $cps));
}

sub updateEntry {
  my ($dbName,$customerData) = @_;

  my $customer = $customerData->{'username'};
  delete $customerData->{'username'};

  my @fields = keys %{$customerData};
  my @values = values %{$customerData};

  push @values,$customer;

  my $updates = join (',', map { "$_ = ?" } @fields);

  my $query = 'UPDATE customer SET ' . $updates . ' WHERE username = ?';

  my $dbs = new PlugNPay::DBConnection();

  eval {
    $dbs->executeOrDie($dbName,$query,\@values);
    logCustomer($dbName,$customer,"customer record scrubbed.");
  };

  if ($@) {
    logCustomer($dbName,$customer,"customer record scrubbing failed.");
  }
}

sub logCustomer {
  my ($username,$customer,$message) = @_;
  $message =~ s/\n/ /g;
  logSTDOUT("[$username:$customer] $message");
  my $data = { username => $username, customer => $customer, message => $message };
  my $dl = new PlugNPay::Logging::DataLog({ collection => 'recurring_scrubbing' });
  $dl->log($data);
}

sub logSTDOUT {
  my $message = shift;
  $message =~ s/\n/ /g;

  my $timestamp = new PlugNPay::Sys::Time()->inFormat('log_gm');
  print "[$timestamp] $message\n";
}
