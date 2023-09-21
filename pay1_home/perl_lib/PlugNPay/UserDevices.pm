package PlugNPay::UserDevices;

use strict;
use POSIX;
use PlugNPay::Util::UniqueID;
use PlugNPay::DBConnection;


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $settings = shift;

  if ($settings) {
    $self->setID($settings->{'deviceID'});
    $self->setGatewayAccount($settings->{'gatewayAccount'});
  }

  my $sessionGenerator = new PlugNPay::Util::UniqueID();
  $sessionGenerator->generate();
  $self->{'session'} = $sessionGenerator->inHex();

  $self->{'dbh'} = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  return $self;
}

sub setID {
  my $self = shift;
  my $id = shift;
  $self->{'id'} = $id;
}

sub getID {
  my $self = shift;
  return $self->{'id'};
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  if (defined $gatewayAccount) {
    $self->{'gatewayAccount'} = $gatewayAccount . '';
  }
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub isApproved {
  my $self = shift;
  if (!defined $self->{'approved'}) {
    $self->{'approved'} = $self->deviceIsApprovedForUsername($self->getID(),$self->getGatewayAccount());
  }

  return $self->{'approved'}; 
}

sub approve {
  my $self = shift;

  if ($self->setApprovalForDeviceForUsername(1,$self->getID(),$self->getGatewayAccount())) {
    $self->{'approved'} = 1;
  }
}

sub revoke {
  my $self = shift;

  if ($self->setApprovalForDeviceForUsername(0,$self->getID(),$self->getGatewayAccount())) {
    $self->{'approved'} = 0;
  }
}

sub clearStatus {
  my $self = shift;
  delete $self->{'approved'};
}



# returns a hash, device id is key, approved (0 or 1) is the value
sub deviceIDListForUsername {
  my $self = shift;
  my $username = shift;

  $username = $self->filterUsername($username);

  my $sth = $self->{'dbh'}->prepare(q/ SELECT user_device_id,approved FROM user_device_ids
                                       WHERE username = ?
                                    /) or die($DBI::errstr);

  $sth->execute($username);

  my %results;

  while (my $row = $sth->fetchrow_hashref) {
    $results{$row->{'user_device_id'}} = $row->{'approved'};
  }

  return %results;
}


# get whether the user device is approved for a given username
sub deviceIsApprovedForUsername
{
  my $self = shift;
  my ($deviceID,$username) = @_;

  $username =~ s/[^A-z0-9]//g;
  $deviceID =~ s/[^A-z0-9\-]//g;

		# if the username exists in the database user_device_force_approve, return 'approved'
  if ($self->isUsernameForceApproved($username)) {
    return 1;
  } else {	# otherwise, check user_device_id for a valid username-deviceid pair 
    my $deviceInfo = $self->deviceInfoForUsername($deviceID,$username);
    return $deviceInfo->{'approved'};
  }
}

# returns a hash, with keys id_exists and approved, both with values of 0 or 1, reflecting true or false
sub deviceInfoForUsername
{
  my $self = shift;
  my ($deviceID,$username,$round) = @_;

  $username =~ s/[^A-z0-9]//g;
  $deviceID =~ s/[^A-z0-9\-]//g;

  
  my $results;
  $results->{'approved'} = 0;
  if ($deviceID eq '') {
    return undef;
  }
  my $sth = $self->{'dbh'}->prepare(q/ SELECT
                             CASE WHEN count(username) = 1 THEN 1 ELSE 0 END as id_exists,
                             approved as approved
                             FROM user_device_ids WHERE username = ? AND user_device_id = ?
                          /) or die "$DBI::errstr";
  $sth->execute($username,$deviceID) or die "$DBI::errstr";
  $results = $sth->fetchrow_hashref or die "$DBI::errstr";
  $sth->finish;

  if (!$results->{'id_exists'} && !$round)
  {
    $self->addDeviceForUsername($deviceID,$username);
    $results = $self->deviceInfoForUsername($deviceID,$username,1);
  }
  return $results;
}

sub addDeviceForUsername
{
  my $self = shift;
  my ($deviceID,$username) = @_;

  my $sth = $self->{'dbh'}->prepare(q/ INSERT INTO user_device_ids (username,user_device_id)
                                       VALUES (?,?)
                                       /) or die "$DBI::errstr";
  $sth->execute($username,$deviceID) or die "$DBI::errstr";
  $sth->finish();
}

# checks if the username gets force approved, meaning the username does not need to exist in user_device_ids, it returns approved regardless
sub isUsernameForceApproved {
  
  my $self = shift;
  my $username = shift;

  my $sth = $self->{'dbh'}->prepare(q/  SELECT username
					FROM user_device_force_approve
					WHERE username=?
				     /) or die "$DBI::errstr";
  $sth->execute($username) or die "$DBI::errstr";
  return $sth->fetch() ? 1 : 0;
}

# deletes a device id for a username
sub deleteDeviceForUsername
{
  my $self = shift;
  my ($deviceID,$username) = @_;

  $username =~ s/[^A-z0-9]//;
  $deviceID =~ s/[^A-z0-9\-]//g;


  my $sth = $self->{'dbh'}->prepare(q/ DELETE FROM user_device_ids
                             WHERE username = ? 
                             AND user_device_id = ?
                          /);

  $sth->execute($username,$deviceID);
  $sth->finish();
}

# sets a device as approved or not approved for a username, returns 0 if failed, 1 if successful
sub setApprovalForDeviceForUsername
{
  my $self = shift;
  my ($approval,$deviceID,$username) = @_;
  
  # set approval to 1 or 0;
  $approval = ($approval ? 1 : 0);
  $deviceID =~ s/[^A-z0-9\-]//g;
  $username =~ s/[^A-z0-9]//g;


  #if (!$self->usernameDeviceIsApprovedFor($deviceID)) {
  if ($self->deviceIsApprovedForUsername($deviceID, $username) == 0) {
    my $sth = $self->{'dbh'}->prepare(q/ UPDATE user_device_ids
                               SET approved = ?
                               WHERE user_device_id = ? 
                               AND username = ?
                            /);
    $sth->execute($approval,$deviceID,$username);
    $sth->finish();

    return 1;
  }
  return 0;
}

# This function is no longer used.
# returns the username that a device is approved for, undef if not approved
sub usernameDeviceIsApprovedFor
{
  my $self = shift;
  my $deviceID = shift @_;

  $deviceID =~ s/[^A-z0-9\-]//g;


  my $sth = $self->{'dbh'}->prepare(q/ SELECT username FROM user_device_ids
                             WHERE user_device_id = ?
                             AND approved = '1'
                          /);

  $sth->execute($deviceID);
  my $username = undef;
  my $result = $sth->fetchrow_hashref;
  if ($result != undef) {
    $username = $result->{'username'};
  }
  $sth->finish;
  return $username;
}

sub DESTROY
{
  my $self = shift;
  $self->{'dbh'}->disconnect();

  if ($self->{'deviceFileHandle'}) {
    close($self->{'deviceFileHandle'});
    delete $self->{'deviceFileHandle'};
  }
}

sub filterUsername {
  my $self = shift;
  my $username = shift;
  $username =~ s/[^A-z0-9]//g;
  return $username;
}

sub filterDeviceID {
  my $self = shift;
  my $deviceID = shift;
  $deviceID =~ s/[^A-z0-9\-]//g;
  return $deviceID;
}

1;
