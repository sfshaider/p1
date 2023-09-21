package PlugNPay::GatewayAccount::Services;

use strict;
use PlugNPay::DBConnection;

use PlugNPay::GatewayAccount::Services::Requested;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $gatewayAccount = shift;
  if (defined $gatewayAccount) {
    $self->setGatewayAccount($gatewayAccount);
    $self->load();
  }

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  $self->_setAccountData('username',shift);
}

sub getGatewayAccount {
  my $self = shift;
  return $self->_getAccountData('username');
}

sub load {
  my $self = shift;

  my $dbconn = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbconn->prepare(q/
                              SELECT autobatch,fraudtrack,affiliate,coupon,fulfillment,wireless,
                                     easycart,download,softcart,shopcart,chkautobatch,billpay,membership,
                                     chkrecurbatch,recurbatch,installbilling,ach,recurbill,pnptype,hosting,
                                     refresh,email_choice,username,submit_date,ftphost,ftpun,ftppw,fromemail,
                                     lookahead,recnotifemail,recmessage,recversion,max_username_length
                              FROM pnpsetups
                              WHERE username = ?
                              /);
  $sth->execute($self->getGatewayAccount());
  my $loaded = $sth->fetchrow_hashref;
  my @keys = keys %{$loaded};

  if (@keys) {
    foreach my $key (@keys) {
      $self->_setAccountData($key,$loaded->{$key});
    }
  }

  $sth->finish();
}

sub save {
  my $self = shift;

  my @fields = sort keys %{$self->{'rawAccountData'}};
  my @fieldValues = map { $self->_getAccountData($_) } @fields;

  my $fieldNameString = join(',',map { $_ } @fields);
  my $insertPlaceholdersString = join(',',map { '?' } @fields);
  my $updateString = join(',',map { $_ . ' = ?' } @fields);

  my $dbconn = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbconn->prepare(q/
                              INSERT INTO pnpsetups (/ . $fieldNameString . q/) VALUES (/ . $insertPlaceholdersString . q/)
                              ON DUPLICATE KEY UPDATE / . $updateString );
  $sth->execute(@fieldValues,@fieldValues) or die $DBI::errstr;
}

sub delete {
  # MUST be called statically
  my $username = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpmisc',q/
    DELETE FROM pnpsetups WHERE username = ?
  /, [$username]);
}

# getServices():
# --------------
# retrieve the services set up or requested for the gateway account
# there are some quirks to this, as the old service is recurring, and the recurring service
# has a subservice of password management.  when the password management service is set up, the
# pnpsetups table has a value of membership for the "membership" column.  this does *not* imply the
# membership service is used.
# takes no input, returns a hashref of services and their state for the account
# empty strings in the db are converted to undef for consistency
sub getServices {
  my $self = shift;
  my $data = $self->{'rawAccountData'};

  my $gatewayAccountUsername = $self->getGatewayAccount();
  my $ga = new PlugNPay::GatewayAccount($gatewayAccountUsername);
  my $requestedServices = new PlugNPay::GatewayAccount::Services::Requested({ gatewayAccount => $ga });

  my $recurringFilter = {
    recurring => 'recurring',
    membership => 'membership'
  };

  my $recurring;
  my $membership;
  my $billpay;
  my $passwordmanagement;

  # first, set pending statuses, which may be overridden by active setups.
  my $pending = $requestedServices->getRequested();
  if ($pending->{'recurring'}) {
    $recurring = 'pending';
  }

  if ($pending->{'passwordmanagement'}) {
    $passwordmanagement = 'pending';
  }

  if ($pending->{'membership'}) {
    $membership = 'pending';
  }

  if ($pending->{'billpay'}) {
    $billpay = 'pending';
  }

  # now check actual statuses
  if ($requestedServices->{'membership'} eq 'recurring') {
    $recurring = 'enabled';
  }

  if ($requestedServices->{'membership'} eq 'membership') {
    $recurring = 'enabled';
    $passwordmanagement = 'enabled';
  }

  if ($requestedServices->{'membership'} eq 'membership' && $data->{'recversion'} eq 2) {
    $membership = 'enabled';
    # unset recurring because it is not used if membership is used.
    $recurring = undef;
    $passwordmanagement = undef;
  }

  if ($requestedServices->{'billpay'}) {
    $billpay = 'enabled';
  }

  my $services = {
    fraudtrak2 => $data->{'fraudtrack'} ? 'enabled' : undef,
    membership => $membership || undef,                 # new membership service
    recurring => $recurring || undef,                   # recurring service
    passwordmanagement => $passwordmanagement || undef, # recurring service with password management
    billpay => $billpay || undef
  };

  return $services;
}

sub setSubmitDate {
  my $self = shift;
  $self->_setAccountData('submit_date',shift);
}

sub getSubmitDate {
  my $self = shift;
  return $self->_getAccountData('submit_date');
}

sub setPNPType {
  my $self = shift;
  $self->_setAccountData('pnptype',shift);
}

sub getPNPType {
  my $self = shift;
  return $self->_getAccountData('pnptype');
}

sub setHosting {
  my $self = shift;
  $self->_setAccountData('hosting',shift);
}

sub getHosting {
  my $self = shift;
  return $self->_getAccountData('hosting');
}

sub setACH {
  my $self = shift;
  $self->_setAccountData('ach',shift);
}

sub getACH {
  my $self = shift;
  return $self->_getAccountData('ach');
}

sub setRefresh {
  my $self = shift;
  $self->_setAccountData('refresh',shift);
}

sub getRefresh {
  my $self = shift;
  return $self->_getAccountData('refresh');
}

sub setEmailChoice {
  my $self = shift;
  $self->_setAccountData('email_choice',shift);
}

sub getEmailChoice {
  my $self = shift;
  return $self->_getAccountData('email_choice');
}

sub setRecurBilling {
  my $self = shift;
  $self->_setAccountData('recurbill',shift);
}

sub getRecurBilling {
  my $self = shift;
  return $self->_getAccountData('recurbill');
}

sub setCheckRecurringBatch {
  my $self = shift;
  $self->_setAccountData('chkrecurbatch',shift);
}

sub getCheckRecurringBatch {
  my $self = shift;
  return $self->_getAccountData('chkrecurbatch');
}

sub setRecurBatch {
  my $self = shift;
  $self->_setAccountData('recurbatch',shift);
}

sub getRecurBatch {
  my $self = shift;
  return $self->_getAccountData('recurbatch');
}

sub setInstallmentBilling {
  my $self = shift;
  $self->_setAccountData('installbilling',shift);
}

sub getInstallmentBilling {
  my $self = shift;
  return $self->_getAccountData('installbilling');
}

sub setShopCart {
  my $self = shift;
  $self->_setAccountData('shopcart',shift);
}

sub getShopCart {
  my $self = shift;
  return $self->_getAccountData('shoptcart');
}

sub setCheckAutoBatch {
  my $self = shift;
  $self->_setAccountData('chkautobatch', shift);
}

sub getCheckAutoBatch {
  my $self = shift;
  return $self->_getAccountData('chkautobatch');
}

sub setBillPay {
  my $self = shift;
  $self->_setAccountData('billpay',shift);
}

sub getBillPay {
  my $self = shift;
  return $self->_getAccountData('billpay');
}

sub setMembership {
  my $self = shift;
  $self->_setAccountData('membership', shift);
}

sub getMembership {
  my $self = shift;
  return $self->_getAccountData('membership');
}

sub setDownload {
  my $self = shift;
  $self->_setAccountData('download',shift);
}

sub getDownload {
  my $self = shift;
  return $self->_getAccountData('download');
}

sub setSoftCart {
  my $self = shift;
  $self->_setAccountData('softcart',shift);
}

sub getSoftCart {
  my $self = shift;
  return $self->_getAccountData('softcart');
}

sub setEasyCart {
  my $self = shift;
  $self->_setAccountData('easycart',shift);
}

sub getEasyCart {
  my $self = shift;
  return $self->_getAccountData('easycart');
}

sub setFulfillment {
  my $self = shift;
  $self->_setAccountData('fulfillment',shift);
}

sub getFulfillment {
  my $self = shift;
  return $self->_getAccountData('fulfillment');
}

sub setWireless {
  my $self = shift;
  $self->_setAccountData('wireless',shift);
}

sub getWireless {
  my $self = shift;
  return $self->_getAccountData('wireless');
}

sub setFraudTrack {
  my $self = shift;
  $self->_setAccountData('fraudtrack',shift);
}

sub getFraudTrack {
  my $self = shift;
  return $self->_getAccountData('fraudtrack');
}

sub setAutoBatch {
  my $self = shift;
  my $autoBatch = shift;
  # autobatch is only numeric or blank
  $autoBatch =~ s/[^0-9\-]//g;
  $autoBatch =~ s/([0-9]+)\-+/$1/g; # leave only leading hyphens

  if ($autoBatch > 7) {
    $autoBatch = 14;
  } elsif ($autoBatch < 0) {
    $autoBatch = '';
  }
  $self->_setAccountData('autobatch',$autoBatch);
}

sub getAutoBatch {
  my $self = shift;
  return $self->_getAccountData('autobatch');
}

sub setAffiliate {
  my $self = shift;
  $self->_setAccountData('affiliate',shift);
}

sub getAffiliate {
  my $self = shift;
  return $self->_getAccountData('affiliate');
}

sub setCoupon {
  my $self = shift;
  $self->_setAccountData('coupon',shift);
}

sub getCoupon {
  my $self = shift;
  return $self->_getAccountData('coupon');
}

sub setFTPHost {
  my $self = shift;
  $self->_setAccountData('ftphost',shift);
}

sub getFTPHost {
  my $self = shift;
  return $self->_getAccountData('ftphost')
}

sub setFTPUsername {
  my $self = shift;
  $self->_setAccountData('ftpun',shift);
}

sub getFTPUsername {
  my $self = shift;
  return $self->_getAccountData('ftpun')
}

sub setFTPPassword {
  my $self = shift;
  $self->_setAccountData('ftppw',shift);
}

sub getFTPPassword {
  my $self = shift;
  return $self->_getAccountData('ftppw')
}

sub setFromEmail {
  my $self = shift;
  $self->_setAccountData('fromemail',shift);
}

sub getFromEmail {
  my $self = shift;
  return $self->_getAccountData('fromemail');
}

sub setLookAhead {
  my $self = shift;
  $self->_setAccountData('lookahead',shift);
}

sub getLookAhead {
  my $self = shift;
  $self->_getAccountData('lookahead') || 3;
}

sub setRecurringNotificationEmail {
  my $self = shift;
  $self->_setAccountData('recnotifemail',shift);
}

sub getRecurringNotificationEmail {
  my $self = shift;
  return $self->_getAccountData('recnotifemail');
}

sub setFailedRecurringMessage {
  my $self = shift;
  $self->_setAccountData('recmessage',shift);
}

sub getFailedRecurringMessage {
  my $self = shift;
  return $self->_getAccountData('recmessage');
}

sub setMaxUsernameLength {
  my $self = shift;
  $self->_setAccountData('max_username_length', shift);
}

sub getMaxUsernameLength {
  my $self = shift;
  return $self->_getAccountData('max_username_length');
}

sub setRecurringVersion {
  my $self = shift;
  $self->_setAccountData('recversion', shift);
}

sub getRecurringVersion {
  my $self = shift;
  return $self->_getAccountData('recversion');
}

#########################
# For internal use only #
#########################
sub _setAccountData {
  my $self = shift;
  return if (ref($self) ne caller());
  my $key = shift;
  my $value = shift;
  $self->{'rawAccountData'}{$key} = $value;
}

sub _getAccountData {
  my $self = shift;
  return if (ref($self) ne caller());
  my $key = shift;
  return $self->{'rawAccountData'}{$key};
}



1;
