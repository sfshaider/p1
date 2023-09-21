package PlugNPay::Membership::PasswordManagement;

use strict;
use MIME::Base64;
use PlugNPay::Merchant;
use PlugNPay::Sys::Time;
use PlugNPay::Util::Status;
use PlugNPay::ResponseLink;
use PlugNPay::Merchant::Host;
use PlugNPay::AWS::S3::Object;
use PlugNPay::Membership::Plan;
use PlugNPay::Membership::Group;
use PlugNPay::Membership::Profile;
use PlugNPay::AWS::ParameterStore;
use PlugNPay::Merchant::Credential;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::Merchant::HostConnection;
use PlugNPay::Membership::Plan::Settings;
use PlugNPay::Membership::Profile::Status;
use PlugNPay::Membership::Plan::FileTransfer;
use PlugNPay::Merchant::HostConnection::Protocol;
use PlugNPay::Membership::Plan::FileTransfer::Link;
use PlugNPay::Membership::PasswordManagement::Manager;

our $PNP_MEMBERSHIP_BUCKET;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  if (!defined $PNP_MEMBERSHIP_BUCKET) {
    &PlugNPay::Membership::PasswordManagement::loadParameters();
  }

  return $self;
}

sub loadParameters {
  $PNP_MEMBERSHIP_BUCKET = &PlugNPay::AWS::ParameterStore::getParameter('/PAY1/MEMBERSHIP/BUCKET');
}

##########################################################
# Subroutine: manageCustomer 
# ---------------------------------------
# Description:
#  Inputs a billing profile ID and based on the status 
#  will perform a request to the remote server. This 
#  subroutine does not care about returning a status
#  because if by some reason the remote server is 
#  unreachable, but the customer was added to our system
#  in which they paid the sign up fee up front, don't fail
#  if it cannot add them to the remote site, just LOG.
#
#  = NEW = 
#  Add customer to remote server (You almost always 
#  want to call this as this won't append the username if
#  it exists on the remote server.)
#
#  = ADD =
#  Adds a customer to the remote server.
#
#  = DELETE = 
#  Removes a customer to the remote server.
sub manageCustomer {
  my $self = shift;
  my $profile = shift;

  if (ref($profile) !~ /^PlugNPay::Membership::Profile/) {
    # load the profile
    my $profileFromID = new PlugNPay::Membership::Profile();
    $profileFromID->loadBillingProfile($profile);
    $profile = $profileFromID;
  }

  # get the current status of the profile
  my $profileStatus = new PlugNPay::Membership::Profile::Status();
  $profileStatus->loadStatus($profile->getStatusID());

  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
  $merchantCustomer->loadMerchantCustomer($profile->getMerchantCustomerLinkID());

  my $merchant = new PlugNPay::Merchant($merchantCustomer->getMerchantID())->getMerchantUsername();
  if ($profileStatus->getStatus() =~ /active/i) {
    my $today = new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd');
    my $endDate = new PlugNPay::Sys::Time('iso', $profile->getCurrentCycleEndDate())->inFormat('yyyymmdd');

    # if todays date is or passed the end date, don't add them.
    if ($today ge $endDate) {
      return;
    }

    # get necessary data for add
    my $username = $merchantCustomer->getUsername();
    my $password = encode_base64($merchantCustomer->getHashedPassword(), '');

    # plan settings
    my $planSettings = new PlugNPay::Membership::Plan::Settings();
    $planSettings->loadPlanSettings($profile->getPlanSettingsID());

    # payment plan
    my $plan = new PlugNPay::Membership::Plan();
    $plan->loadPaymentPlan($planSettings->getPlanID());

    # group data for htaccess groups
    my $group = new PlugNPay::Membership::Group();
    my $planGroups    = $group->loadPlanGroups($plan->getPlanID());
    my $profileGroups = $group->loadProfileGroups($profile->getBillingProfileID());
    my @groups = map { $_->getGroupName() } (@{$planGroups}, @{$profileGroups});
    my $groupString = join('|', @groups);

    # activation urls
    my $activationURLs = $self->_getActivationURLs($plan->getPlanID());

    my $pwManager = new PlugNPay::Membership::PasswordManagement::Manager();
    $pwManager->newCustomer({
      'username'       => $username,
      'password'       => $password,
      'endDate'        => $endDate,
      'groups'         => $groupString,
      'activationURLs' => $activationURLs
    });
  } else {
    # get necessary data for delete
    my $username = $merchantCustomer->getUsername();

    # plan settings
    my $planSettings = new PlugNPay::Membership::Plan::Settings();
    $planSettings->loadPlanSettings($profile->getPlanSettingsID());

    # takes care of logging in subroutine
    $self->removeCustomer($username,
                          $planSettings->getPlanID());
  }
}

####################################
# Subroutine: _getActivationURLs
# ----------------------------------
# Description: 
# Returns an array of activation 
# urls based on plan ID.
sub _getActivationURLs {
  my $self = shift;
  my $planID = shift;

  my $fileTransferLink = new PlugNPay::Membership::Plan::FileTransfer::Link();
  my $fileTransferLinks = $fileTransferLink->loadPlanFileTransferSettings($planID);

  my $activationURLs = [];
  foreach my $link (@{$fileTransferLinks}) {
    my $fileTransfer = new PlugNPay::Membership::Plan::FileTransfer();
    $fileTransfer->loadFileTransferSettings($link->getFileTransferID());

    my $hostConnection = new PlugNPay::Merchant::HostConnection();
    $hostConnection->loadHostConnection($fileTransfer->getHostConnectionID());

    my $host = new PlugNPay::Merchant::Host();
    $host->loadMerchantHost($hostConnection->getHostID());
    push (@{$activationURLs}, $fileTransfer->getActivationURL());
  }

  return $activationURLs;
}

#########################################
# Subroutine: removeCustomer
# ---------------------------------------
# Description: 
#   Exists so if a billing profile is
#   deleted, it doesn't bother checking
#   the current status of the profile
sub removeCustomer {
  my $self = shift;
  my $username = shift;
  my $planID = shift;

  # payment plan
  my $plan = new PlugNPay::Membership::Plan();
  $plan->loadPaymentPlan($planID);

  # activation urls
  my $activationURLs = $self->_getActivationURLs($planID);

  my $pwManager = new PlugNPay::Membership::PasswordManagement::Manager();
  $pwManager->deleteCustomer({
    'username'       => $username,
    'activationURLs' => $activationURLs      
  });
}

###################################################
# Subroutine: refresh
# -------------------------------------------------
# Description:
#   Uploads an S3 object to a bucket that will
#   invoke an AWS lambda to perform refresh.
sub refresh {
  my $self = shift;
  my $merchant = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $errorMsg;
  eval {
    my $s3Object = $self->_createS3RefreshObject($merchant);
    if (@{$s3Object->{'plans'}} > 0) {
      my $s3Client = new PlugNPay::AWS::S3::Object($PNP_MEMBERSHIP_BUCKET);
      $s3Client->setObjectName('merchant-refresh/' . $merchant . '-pnppasswd.json');
      $s3Client->setContentType('application/json');
      $s3Client->setContent($s3Object);
      my $createStatus = $s3Client->createObject();
      if ($createStatus) {
        $errorMsg = $createStatus->getError();
      }
    }
  };

  if ($@ || $errorMsg) {
    if ($@) {
      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_password_remote' });
      $logger->log({
        'error'    => $@,
        'function' => 'refresh',
        'merchant' => $merchant
      });

      $errorMsg = 'Error while attempting to perform refresh.';
    }

    $status->setFalse();
    $status->setError($errorMsg);
  }

  return $status;
}

###################################################
# Subroutine: _createS3RefreshObject
# -------------------------------------------------
# Description:
#   Remote server refresh process:
#     1. Get all the merchant's customers.
#     2. Get all profiles for those customers.
#     3. Segregate profiles based on the merchant
#        plan ID.
#     4. Create a file to upload into S3 where an
#        AWS Lambda will trigger to parse it.
#     ( Lambdas don't typically run for long;
#       process all that is available server side
#       before invoking the lambda. )
#   Returns a hash of data to be uploaded.
sub _createS3RefreshObject {
  my $self = shift;
  my $merchant = shift;
  my $merchantID = new PlugNPay::Merchant($merchant)->getMerchantID();

  # load list of all the merchant's customers.
  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
  my $customers = $merchantCustomer->loadMerchantCustomers($merchantID);

  # need to get list of profiles that are active AND not past end cycle
  my $today = new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd');

  my $activeProfiles = [];
  foreach my $customer (@{$customers}) {
    # load all the merchant's profiles
    my $profileObj = new PlugNPay::Membership::Profile($merchant);
    my $profiles = $profileObj->loadBillingProfiles($customer->getMerchantCustomerLinkID());
    foreach my $profile (@{$profiles}) {
      my $endDate = new PlugNPay::Sys::Time('iso', $profile->getCurrentCycleEndDate());
      my $profileStatus = new PlugNPay::Membership::Profile::Status();
      $profileStatus->loadStatus($profile->getStatusID());
      
      # if today is or before the end date of the profile AND active status
      if ( ($today le $endDate->inFormat('yyyymmdd')) && ($profileStatus->getStatus() =~ /active/i) ) {
        push (@{$activeProfiles}, $profile);
      }
    }
  }

  # now, we need to segregate them by planID
  my $planProfiles = {};
  foreach my $profile (@{$activeProfiles}) {
    my $planSettings = new PlugNPay::Membership::Plan::Settings($merchant);
    $planSettings->loadPlanSettings($profile->getPlanSettingsID());

    # needs to push onto array
    if (!exists $planProfiles->{$planSettings->getPlanID()}) {
      $planProfiles->{$planSettings->getPlanID()} = [];
    }

    push (@{$planProfiles->{$planSettings->getPlanID()}}, $profile);
  }

  # now create json file to upload to S3.
  my $s3 = {
    'plans' => []
  };

  foreach my $planID (keys %{$planProfiles}) {
    my $planObject = {};
    
    # load payment plan
    my $plan = new PlugNPay::Membership::Plan($merchant);
    $plan->loadPaymentPlan($planID);
    $planObject->{'merchantPlanID'} = $plan->getMerchantPlanID();

    my $htpasswdFile = [];
    my $planProfileMap = $planProfiles->{$planID};
    foreach my $planProfile (@{$planProfileMap}) {
      my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
      $merchantCustomer->loadMerchantCustomer($planProfile->getMerchantCustomerLinkID());

      # username and password
      my $username = $merchantCustomer->getUsername();
      if (!$merchantCustomer->getHashedPassword()) {
        next;  # if no password, skip for refresh
      }
      my $password = encode_base64($merchantCustomer->getHashedPassword(), '');

      # end date
      my $endDate = new PlugNPay::Sys::Time('iso', $planProfile->getCurrentCycleEndDate())->inFormat('yyyymmdd');

      # group data for htaccess groups
      my $group = new PlugNPay::Membership::Group();
      my $planGroups    = $group->loadPlanGroups($plan->getPlanID());
      my $profileGroups = $group->loadProfileGroups($planProfile->getBillingProfileID());
      my @groups = map { $_->getGroupName() } (@{$planGroups}, @{$profileGroups});
      my $groupString = join('|', @groups);

      push (@{$htpasswdFile}, {
        'username'   => $username,
        'password'   => $password,
        'endDate'    => $endDate,
        'groups'     => $groupString
      });
    }

    # this is the file that will contain all the customer data for the current plan.
    $planObject->{'htpasswd'} = $htpasswdFile;

    # need to load the server information for the given plan.
    $planObject->{'servers'} = [];
    my $fileTransferLink = new PlugNPay::Membership::Plan::FileTransfer::Link();
    my $fileTransferLinks = $fileTransferLink->loadPlanFileTransferSettings($plan->getPlanID());

    foreach my $fileTransferSettings (@{$fileTransferLinks}) {
      my $transferSettings = new PlugNPay::Membership::Plan::FileTransfer($merchant);
      $transferSettings->loadFileTransferSettings($fileTransferSettings->getFileTransferID());

      my $hostConnection = new PlugNPay::Merchant::HostConnection();
      $hostConnection->loadHostConnection($transferSettings->getHostConnectionID());

      my $protocol = new PlugNPay::Merchant::HostConnection::Protocol();
      $protocol->loadProtocol($hostConnection->getProtocolID());

      my $credentials = new PlugNPay::Merchant::Credential();
      $credentials->loadMerchantCredential($hostConnection->getCredentialID());

      my $host = new PlugNPay::Merchant::Host();
      $host->loadMerchantHost($hostConnection->getHostID());

      push (@{$planObject->{'servers'}}, {
        'activationURL' => $transferSettings->getActivationURL(),
        'renameSuffix'  => $transferSettings->getRenamePreviousSuffix(),
        'protocol'      => $protocol->getProtocol(),
        'path'          => $hostConnection->getPath(),
        'destination'   => $host->getIPAddress(),
        'port'          => $hostConnection->getPort(),
        'credentials'   => {
          'username'      => $credentials->getUsername(),
          'password'      => $credentials->getPasswordToken(),
          'certificate'   => $credentials->getCertificate()
        }
      });
    }

    if (@{$planObject->{'servers'}} > 0) {
      push (@{$s3->{'plans'}}, $planObject);
    }
  }

  return $s3;
}

1;
