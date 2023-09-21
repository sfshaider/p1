#############################################################################
# Notes
#############################################################################
# New can be called with no arguments, a gateway account name, or a username 
# and a settings hash.
#
# If it is called with a username, when getConvenienceFees is called
# it checks to see if the settings and buckets exist.  If they
# are not loaded, they are then loaded.  Subsequent calls will not
# reload the settings and buckets.
# 
# Calling setGatewayAccount with a different account name than the one
# already loaded will cause the settings and buckets to be deleted and
# reloaded with the account's settings.

use strict;

package PlugNPay::ConvenienceFee;
use PlugNPay::DBConnection;
use PlugNPay::Features;

#############################################################################

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self, $class;

  my $gatewayAccount = shift;
  my $settings = shift;

  if (defined $gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
    if (defined $settings and ref($settings) eq 'HASH') {
      foreach my $key (keys %{$settings}) {
        $self->{'settings'}{$key} = $settings->{$key};
      }
    }
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $account = lc shift;

  $account =~ s/[^a-z0-9]//;

  if ($account ne $self->{'account'}) {
    delete $self->{'settings'};
    delete $self->{'buckets'};
  }

  $self->{'account'} = $account;

  $self->load();
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'account'};
}

sub getEnabled {
  my $self = shift;

  if (!exists $self->{'enabled'}) {
    my $features = new PlugNPay::Features($self->getGatewayAccount(),'general');
    my $enabled = ($features->get('convfee') ? 1 : 0);
    $self->{'enabled'} = $enabled;
  }
  return $self->{'enabled'};
}

sub cloneTo {
  my $self = shift;
  my $toAccount = shift;

  my $originalToAccount = $toAccount;
  $toAccount =~ s/[^a-z0-9]//;
  if ($originalToAccount ne $toAccount) {
    return undef;
  } 

  # if settings are not loaded, return undef
  if (!defined $self->{'settings'}) {
    return undef;
  }

  # copy these settings to a new hash
  my %settings = %{$self->{'settings'}};

  # create the new convenience fee object, save the settings, and return it
  my $cf = new PlugNPay::ConvenienceFee($toAccount,\%settings);

  # copy the buckets over
  my %buckets = %{$self->{'buckets'}};
  $cf->{'buckets'} = \%buckets;

  # if $self->{'account'} is the same as $self->{'chargeAccount'}, then we want to have do the same for the cloned account
  if ($self->{'account'} eq $self->{'settings'}{'chargeAccount'}) {
    $cf->{'settings'}{'chargeAccount'} = $cf->{'account'};
  }
  return $cf;
}

sub setAuthorizationType {
  my $self= shift;
  my $value= shift;
  $self->{'settings'}{'authorizationType'} = $value;
}

sub getAuthorizationType {
  my $self= shift;
  return $self->{'settings'}{'authorizationType'};
}

sub setFailureRule {
  my $self = shift;
  my $value = shift;
  $self->{'settings'}{'failureMode'} = $value;
}

sub setFailureMode {
  my $self = shift;
  my $value = shift;
  $self->setFailureRule($value);
}

sub setChargeAccount {
  my $self= shift;
  my $value = shift;
  $self->{'settings'}{'chargeAccount'} = $value;
}

sub setApplicationMode {
  my $self= shift;
  my $value = shift;
  $self->{'settings'}{'applicationMode'} = $value;
}

sub setDefaultCategory {
  my $self = shift;
  my $value = shift;
  $self->{'settings'}{'defaultCategory'} = $value;
}

sub getDefaultCategory {
  my $self = shift;
  return $self->{'settings'}{'defaultCategory'};
}

sub setSurcharge {
  my $self = shift;
  my $isSurcharge = shift;
  $self->{'settings'}{'isSurcharge'} = ($isSurcharge ? 1 : 0);
}

sub getSurcharge {
  my $self = shift;
  return ($self->{'settings'}{'isSurcharge'} ? 1 : 0);
}

sub getMode {
  my $self = shift;
  return ($self->getSurcharge() ? 'surcharge' : 'separate');
}

sub getBuckets {
  my $self = shift;
  return $self->{'buckets'} || {};
}

sub setError {
  my $self = shift;
  my $message = shift;

  $self->{'response'}{'error'} = 1;
  $self->{'response'}{'error_message'} = $message;
}

sub load {
  my $self = shift;
  $self->loadSettings();
  $self->loadBuckets();
}

sub isSurcharge {
  my $self = shift;

  return $self->getSurcharge();
}

sub save {
  my $self = shift;
  $self->saveSettings();
  $self->saveBuckets();
}

sub loadSettings {
  my $self = shift;
  
  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
                          SELECT authorization_type,failure_mode,
                                 charge_account,surcharge,
                                 application_mode,default_category
                          FROM convenience_fee_settings
                          WHERE username = ?
                          /);

  if ($sth && $sth->execute($self->{'account'})) {
    my $row = $sth->fetchrow_hashref;
    
    if ($row) {
      $self->setAuthorizationType($row->{'authorization_type'});
      $self->setFailureMode($row->{'failure_mode'}); 
      $self->setChargeAccount($row->{'charge_account'});
      $self->setSurcharge($row->{'surcharge'});
      $self->setApplicationMode($row->{'application_mode'});
      $self->setDefaultCategory($row->{'default_category'});
    } else {
      $self->setError('No convenience fee settings for account: ' . $self->{'account'});
    }
  } else {
     $self->setError('Error loading convenience fee settings.');
  }

  $self->{'settingsLoaded'} = 1;
}

sub loadBuckets {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
                          SELECT category,subcategory,bucket,rate,fixed
                          FROM convenience_fee_buckets
                          WHERE username = ?
                          /);

  if ($sth && $sth->execute($self->{'account'})) {
    my $rows = $sth->fetchall_arrayref({});
    if ($rows) {
      foreach my $row (@{$rows}) {
        my $category = $row->{'category'};
        my $subcategory = $row->{'subcategory'};
        my $bucket = $row->{'bucket'};
        my $rate = $row->{'rate'};
        my $fixed = $row->{'fixed'};

        $self->{'buckets'}{$category}{$subcategory}{$bucket}{'rate'} = $rate;
        $self->{'buckets'}{$category}{$subcategory}{$bucket}{'fixed'} = $fixed;

      }
    }
  } else {
     $self->setError('Error loading convenience fee buckets.');
  }
}

sub saveBuckets {
  my $self = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
                          DELETE FROM convenience_fee_buckets
                          WHERE username = ?
                          /);

  $sth->execute($self->{'account'});

  $sth = $dbh->prepare(q/
                       INSERT INTO convenience_fee_buckets (username,category,subcategory,bucket,rate,fixed)
                       VALUES (?,?,?,?,?,?)
                       /);

  # do an execute on each bucket, loop through categories, then subcategories, then buckets
  foreach my $category (keys %{$self->{'buckets'}}) {
    foreach my $subcategory (keys %{$self->{'buckets'}{$category}}) {
      foreach my $bucket (keys %{$self->{'buckets'}{$category}{$subcategory}}) {
        my $rate  = $self->{'buckets'}{$category}{$subcategory}{$bucket}{'rate'};
        my $fixed = $self->{'buckets'}{$category}{$subcategory}{$bucket}{'fixed'};
        $sth->execute($self->{'account'},$category,$subcategory,$bucket,$rate,$fixed);
      }
    }
  }

}

sub getConvenienceFee {
  my $self = shift;
  my $amount = shift;
  my $type = shift;
  my $category = shift;
  my $precision = shift || 2;

  my %fees = $self->getConvenienceFees($amount,$precision);

  $type =~ s/^(ach|credit)$/$1/;
  $category =~ s/^(standard|debit|business|rewards|international)$/$1/;

  if (!defined $fees{'fees'}{$type}{$category}) {
    $category = $self->getDefaultCategory();
  }

  if ($type ne '') {
    return $fees{'fees'}{$type}{$category};
  }

  return 0;
}


sub getConvenienceFees {
  my $self = shift;
  my $amount = shift;
  my $precision = shift || 2;

  delete $self->{'response'}; 

  $amount =~ s/[^0-9\.]//g;

  if ($amount eq '') {
    $self->setError('Invalid amount.');
  } else {
    # load the buckets if they haven't been loaded yet.
    if (!defined $self->{'buckets'}) {
      $self->loadBuckets();
    }
    # load the settings if they haven't been loaded yet
    if (!defined $self->{'settingsLoaded'}) {
      $self->loadSettings();
    }

    # if there was no error loading the buckets
    # set the default category in the response
    $self->{'response'}{'defaultCategory'} = $self->getDefaultCategory();

    if (!$self->{'error'}) {
      # Loop through the categories
      my %bucketFees = map {
        my $category = $_;

        # Loop through the subcategories
        my %subCategories = map {
          my $subcategory = $_;

          # Loop through buckets
          my $fee = 0;


          # sort the buckets 
          foreach my $bucket (sort { $b <=> $a } keys %{$self->{'buckets'}{$category}{$subcategory}}) {
            my $rate = $self->{'buckets'}{$category}{$subcategory}{$bucket}{'rate'};
            my $fixed = $self->{'buckets'}{$category}{$subcategory}{$bucket}{'fixed'};

            my $bucketFee = 0;

            # calculate the fee for the bucket if the amount is in that bucket
            if ($amount >= $bucket) {
              # if the applicationMode is step, we add the bucket fee to the last fee
              if ($self->{'settings'}{'applicationMode'} eq 'step') {
                $fee += (($amount - $bucket) * $rate/100) + $fixed;
              } else {
                # only the highest bucket applies, so since we are reverse sorting, the first one to match $amount >= bucket will apply
                $fee = ($amount * $rate/100) + $fixed;
                last;
              }
            }
          }

          # apply preceision to fee
          # start by rounding
          my $format = '%.' . ($precision+1) . 'f';
          $fee = sprintf($format,$fee);
          my $lastDigit = chop $fee;
          if ($lastDigit >= 5) {
            $fee = ((($fee * (10**$precision)) + 1) / (10**$precision))
          }

          # apply final precision to fee
          $format = '%.' . $precision . 'f';
          $fee = sprintf($format,$fee);
          $subcategory => $fee;
        } keys %{$self->{'buckets'}{$category}};
        $category => \%subCategories;
      } keys %{$self->{'buckets'}};;
      $self->{'response'}{'fees'} = \%bucketFees; 
    }
  }

  return %{$self->{'response'}};
}

# addBucket()
##############################################################################
# %settings should be a hash with the following keys:
#   category: the type of payment, i.e. credit, ach, debit
#   subcategory: the type of account, i.e. standard, business, rewards, etc.
#   bucket: the value to start applying the fees at
#   rate: the percentage rate to apply as a fee
#   fixed: a fixed fee to add
# NOTE: rate and fixed are added together to calculate the total fee.
##############################################################################
sub addBucket {
  my $self = shift;
  my $settings = shift;

  # remove bucket if it already exists
  $self->removeBucket($settings);

  my $wasSuccessful = 0;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
                          INSERT INTO convenience_fee_buckets (username,category,subcategory,bucket,rate,fixed)
                          VALUES (?,?,?,?,?,?)
                          /);

  if ($sth && $sth->execute($self->{'account'}, $settings->{'category'}, $settings->{'subcategory'}, $settings->{'bucket'}, $settings->{'rate'}, $settings->{'fixed'})) {
    $wasSuccessful = 1;
  }

  return $wasSuccessful;
}

# removeBucket()
##############################################################################
# %settings should be a hash with the following keys:
#   category: the type of payment, i.e. credit, ach, debit
#   subcategory: the type of account, i.e. standard, business, rewards, etc.
#   bucket: the value to start applying the fees at
##############################################################################
sub removeBucket {
  my $self = shift;
  my $settings = shift;

  my $wasSuccessful = 0;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
                          DELETE FROM convenience_fee_buckets
                          WHERE username = ? AND category = ? AND subcategory = ? AND bucket = ?
                          /);

  if ($sth && $sth->execute($self->{'account'}, $settings->{'category'}, $settings->{'subcategory'}, $settings->{'bucket'})) {
    $wasSuccessful = 1;
  }

  return $wasSuccessful;
}

# saveSettings()
###############################################################################
# saves the current settings to the database
sub saveSettings() {
  my $self = shift;

  my $wasSuccessful = 1;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/
                          SELECT count(username) AS `exists`
                          FROM convenience_fee_settings
                          WHERE username = ?
                          /);

  my $saveMode = 'insert';

  if ($sth && $sth->execute($self->{'account'})) {
    my $row = $sth->fetchrow_hashref;
    if ($row->{'exists'}) {
      $saveMode = 'update';
    }
  }
      
  my $query;
  my @args;

  push @args,$self->{'account'};
  push @args,$self->{'settings'}{'authorizationType'};
  push @args,$self->{'settings'}{'failureMode'};
  push @args,$self->{'settings'}{'chargeAccount'};
  push @args,$self->getSurcharge();
  push @args,$self->{'settings'}{'applicationMode'};
  push @args,$self->{'settings'}{'defaultCategory'};

  if ($saveMode eq 'insert') {
    $query = q/
             INSERT INTO convenience_fee_settings (
               username,
               authorization_type,
               failure_mode,
               charge_account,
               surcharge,
               application_mode,
               default_category
             )
             VALUES (?,?,?,?,?,?,?)
             /;

  } elsif ($saveMode eq 'update') {
    $query = q/
             UPDATE convenience_fee_settings 
             SET
               authorization_type = ?,
               failure_mode = ?,
               charge_account = ?,
               surcharge = ?,
               application_mode = ?,
               default_category = ?
             WHERE username = ?
             /;
  
    # move the username to the end of the array for the where clause
    push (@args,shift @args);
  }

  $sth = $dbh->prepare($query) or $wasSuccessful = 0;
  if ($wasSuccessful) {
    $sth->execute(@args) or $wasSuccessful = 0;
  }

  return $wasSuccessful;
}


sub getFailureRule {
  my $self = shift;
  return $self->{'settings'}{'failureMode'};
}

sub getFailureMode {
  my $self= shift;
  return $self->getFailureRule();
}

sub getChargeAccount {
  my $self= shift;
  return $self->{'settings'}{'chargeAccount'};
}

1;
