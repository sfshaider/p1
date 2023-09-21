package PlugNPay::Membership::Report;

use strict;
use PlugNPay::Merchant::Proxy;
use PlugNPay::Membership::Profile;
use PlugNPay::Merchant::Customer::Link;
use PlugNPay::Membership::Profile::Status;

##########################################
# Module: PlugNPay::Membership::Report
# ----------------------------------------
# Description: 
#   Module for returning information
#   about merchants' membership data.
#   IMPORTANT: Always pass merchant into
#   constructor.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $merchant = shift;
  if ($merchant) {
    if (ref($merchant) =~ /^PlugNPay::Merchant::Proxy/) {
      $self->{'merchantDB'} = $merchant;
    } else {
      $self->{'merchantDB'} = new PlugNPay::Merchant::Proxy($merchant);
    }
  }

  return $self;
}

####################################
# Subroutine: loadMembershipReport 
# ----------------------------------
# Description:
#   Returns membership information 
#   given a merchant account.
sub loadMembershipReport {
  my $self = shift;
  my $merchant = $self->{'merchantDB'};

  my $customerStatus = {};
  if ($merchant) {
    $customerStatus = $self->loadStatusOfCustomers($merchant);
  }

  return {
    'customerStatus' => $customerStatus
  };
}

######################################
# Subroutine: loadStatusOfCustomers
# ------------------------------------
# Description:
#   Returns a hash of the number of
#   billing profiles for each status.
sub loadStatusOfCustomers {
  my $self = shift;
  my $merchant = shift;

  my $profileStatus = new PlugNPay::Membership::Profile::Status();
  my $profileStatuses = $profileStatus->loadAllStatuses();
  my %statusCount = map { $_ => 0 } @{$profileStatuses};

  # load all the merchant customers
  my $merchantCustomer = new PlugNPay::Merchant::Customer::Link();
  my $customers = $merchantCustomer->loadMerchantCustomers($merchant);

  if (@{$customers} > 0) {
    foreach my $customerLink (@{$customers}) {
      # load all profiles
      my $profile = new PlugNPay::Membership::Profile();
      my $billingProfiles = $profile->loadBillingProfiles($customerLink->getMerchantCustomerLinkID());
      foreach my $billingProfile (@{$billingProfiles}) {
        $profileStatus->loadStatus($billingProfile->getStatusID());
        $statusCount{$profileStatus->getStatus()} += 1;
      }
    }
  }

  return \%statusCount;
}

1;
