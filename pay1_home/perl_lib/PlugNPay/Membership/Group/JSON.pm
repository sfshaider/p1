package PlugNPay::Membership::Group::JSON;

use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub groupToJSON {
  my $self = shift;
  my $group = shift;

  return {
    'groupID'    => $group->getGroupID(),
    'groupName'  => $group->getGroupName(),
    'merchantID' => $group->getMerchantID()
  };
}

1;
