package PlugNPay::Membership::Group;

use strict;
use PlugNPay::Merchant;
use PlugNPay::Util::Status;
use PlugNPay::DBConnection;
use PlugNPay::Merchant::Proxy;
use PlugNPay::Logging::DataLog;
use PlugNPay::Membership::Plan;
use PlugNPay::Membership::Profile;
use PlugNPay::Membership::Plan::Settings;

###########################################
# Module: Group
# -----------------------------------------
# Description:
#   Groups refer to the type of plan the 
#   customer belongs to. Profile and plans
#   can contain a different combination
#   of groups, nonetheless, the customer
#   belongs to the combination of groups.

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  my $merchant = shift;
  if ($merchant) {
    if (ref($merchant) =~ /^PlugNPay::Merchant::Proxy/) {
      $self->{'merchantDB'} = $merchant;
    } else {
      $self->setMerchantID($merchant);
      $self->{'merchantDB'} = new PlugNPay::Merchant::Proxy($merchant);
    }
  }

  return $self;
}

sub setMerchantID {
  my $self = shift;
  my $merchant = shift;
  
  if ($merchant !~ /^[0-9]+$/) {
    $merchant = new PlugNPay::Merchant($merchant)->getMerchantID();
  }

  $self->{'merchantID'} = $merchant;
}

sub getMerchantID {
  my $self = shift;
  return $self->{'merchantID'};
}

sub setGroupID {
  my $self = shift;
  my $groupID = shift;
  $self->{'groupID'} = $groupID;
}

sub getGroupID {
  my $self = shift;
  return $self->{'groupID'};
}

sub setGroupName {
  my $self = shift;
  my $groupName = shift;
  $self->{'groupName'} = $groupName;
}

sub getGroupName {
  my $self = shift;
  return $self->{'groupName'};
}

######################################
# Subroutine: loadGroupsForMerchant
# ------------------------------------
# Description:
#   Loads all the merchant's groups.
sub loadGroupsForMerchant {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $groups = [];

  my @values = ();
  my $sql = q/SELECT id,
                     name,
                     merchant_id
              FROM recurring1_group
              WHERE merchant_id = ?
              ORDER BY id ASC/;
  push (@values, $merchantDB);

  my $limit = '';
  if ( (defined $self->{'limitData'}{'limit'}) && (defined $self->{'limitData'}{'offset'}) ) {
    $limit = ' LIMIT ?,? ';
    push (@values, $self->{'limitData'}{'offset'});
    push (@values, $self->{'limitData'}{'limit'});
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust', $sql . $limit, \@values, {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $group = new PlugNPay::Membership::Group();
        $group->_setGroupDataFromRow($row);
        push (@{$groups}, $group);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadGroupsForMerchant'
    });
  }

  return $groups;
}

#############################
# Subroutine: loadGroup
# ---------------------------
# Description:
#   Loads group info given 
#   the id of the table row.
sub loadGroup {
  my $self = shift;
  my $groupID = shift;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               name,
               merchant_id
        FROM recurring1_group
        WHERE id = ?/, [$groupID], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setGroupDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadGroup'
    });
  }
}

sub _setGroupDataFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'groupID'}    = $row->{'id'};
  $self->{'groupName'}  = $row->{'name'};
  $self->{'merchantID'} = $row->{'merchant_id'};
}

sub saveMerchantGroup {
  my $self = shift;
  my $groupName = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $merchantDB = $self->{'merchantDB'};
  if (!$merchantDB->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  } 

  if ($self->doesGroupNameExist($groupName)) {
    push (@errorMsg, 'Group name already exists.');
  }

  if (@errorMsg == 0) {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/INSERT INTO recurring1_group
          ( merchant_id,
            name ) 
          VALUES (?,?)/, [$merchantDB, $groupName]);
    };
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'     => $@,
        'function'  => 'saveMerchantGroup',
        'groupName' => $groupName
      });

      push (@errorMsg, 'Error while attempting to save group.');
    }

    $status->setFalse();
    $status->setError(join(' ' , @errorMsg));
  }

  return $status;
}

###################################
# Subroutine: updateMerchantGroup
# ---------------------------------
# Description:
#   Updates a row in the group 
#   table for a merchant. This
#   subroutine expects the group
#   object to be loaded.
sub updateMerchantGroup {
  my $self = shift;
  my $groupName = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  if (!$self->{'merchantDB'}->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  if ($groupName ne $self->{'groupName'}) {
    if ($self->doesGroupNameExist($groupName)) {
      push (@errorMsg, 'Group name already exists.');
    }
  }

  if (@errorMsg == 0) {
    eval {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->executeOrDie('merchant_cust',
        q/UPDATE recurring1_group
          SET name = ?
          WHERE id = ?/, [$groupName, $self->{'groupID'}]);
    };
  }
  
  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'     => $@,
        'function'  => 'updateMerchantGroup',
        'groupName' => $groupName
      });

      push (@errorMsg, 'Error while attempting to update group.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

##################################
# Subroutine: deleteMerchantGroup
# --------------------------------
# Description:
#   Deletes the merchant group
#   from the customer records.
sub deleteMerchantGroup {
  my $self = shift;
  my $groupID = shift || $self->{'groupID'};

  my $status = new PlugNPay::Util::Status(1);

  if (!$self->{'merchantDB'}->isMaster()) {
    $status->setFalse();
    $status->setError('Access denied.');
    return $status;
  }

  eval {
    my $dbs = new PlugNPay::DBConnection();
    $dbs->executeOrDie('merchant_cust',
      q/DELETE FROM recurring1_group
        WHERE id = ?/, [$groupID]);
  };

  if ($@) {
    $self->_log({
      'error'     => $@,
      'function'  => 'deleteMerchantGroup',
      'groupName' => $groupID
    });

    $status->setFalse();
    $status->setError('Error while attempting to delete group.');
  }

  return $status;
}

sub doesGroupNameExist {
  my $self = shift;
  my $groupName = lc shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $exists = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `exists`
        FROM recurring1_group
        WHERE LOWER(name) = ?
        AND merchant_id = ?/, [$groupName, $merchantDB], {})->{'result'};
    $exists = $rows->[0]{'exists'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'doesGroupNameExist'
    });
  }
  
  return $exists;
}

sub loadGroupByName {
  my $self = shift;
  my $groupName = lc shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT id,
               name,
               merchant_id
        FROM recurring1_group
        WHERE LOWER(name) = ?
        AND merchant_id = ?/, [$groupName, $merchantDB], {})->{'result'};
    if (@{$rows} > 0) {
      $self->_setGroupDataFromRow($rows->[0]);
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadGroupByName'
    });
  }
}

sub setLimitData {
  my $self = shift;
  my $limitData = shift;
  $self->{'limitData'} = $limitData;
}

sub getGroupListSize {
  my $self = shift;
  my $merchantDB = shift || $self->{'merchantDB'};

  my $count = 0;

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT COUNT(*) as `count`
        FROM recurring1_group
        WHERE merchant_id = ?/, [$merchantDB], {})->{'result'};
    $count = $rows->[0]{'count'};
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'getGroupListSize'
    });
  }

  return $count;
}

#######################################
# Subroutine: loadPlanGroups
# -------------------------------------
# Description:
#   Loads all the groups associated 
#   with a merchant plan.
sub loadPlanGroups {
  my $self = shift;
  my $planID = shift;

  my $groups = [];

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT group_id
        FROM recurring1_plan_group_link
        WHERE plan_id = ?/, [$planID], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $group = new PlugNPay::Membership::Group();
        $group->loadGroup($row->{'group_id'});
        push (@{$groups}, $group);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadPlanGroups'
    });
  }

  return $groups;
}

#######################################
# Subroutine: savePlanGroups
# -------------------------------------
# Description:
#   Saves groups to the group and plan
#   association table.
sub savePlanGroups {
  my $self = shift;
  my $planID = shift;
  my $groupData = shift;
  
  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  eval {
    if (ref($groupData) eq 'ARRAY') {
      if (@{$groupData} > 0) {
        my $IDs = [];
        my $params = [];

        my $existingGroupHash = {};
        my $existingGroups = $self->loadPlanGroups($planID);
        foreach my $group (@{$existingGroups}) {
          $existingGroupHash->{$group->getGroupID()} = 1;
        }

        my $sql = q/INSERT INTO recurring1_plan_group_link (plan_id, group_id)
                    VALUES /;

        foreach my $group (@{$groupData}) {
          my $groupObj = new PlugNPay::Membership::Group($self->{'merchantDB'});
          $groupObj->loadGroupByName($group);
          if (!$groupObj->getGroupID()) {
            push (@errorMsg, 'Invalid merchant group: ' . $group);
          } else {
            if (!exists $existingGroupHash->{$groupObj->getGroupID()}) {
              push (@{$IDs}, $planID, $groupObj->getGroupID());
              push (@{$params}, '(?,?)');
            }
          }
        }

        if (@errorMsg == 0) {
          if (@{$IDs} > 0) {
            my $dbs = new PlugNPay::DBConnection();
            $dbs->executeOrDie('merchant_cust', $sql . join(',', @{$params}), $IDs);
          }
        }
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'savePlanGroups',
        'planID'   => $planID
      });

      push (@errorMsg, 'Error while attempting to save groups to payment plan.');
    }

    $status->setFalse();
    $status->setError(join(' ' , @errorMsg));
  }

  return $status;
}

#####################################
# Subroutine: updatePlanGroups
# -----------------------------------
# Description:
#   Updates the plans groups.
sub updatePlanGroups {
  my $self = shift;
  my $planID = shift;
  my $groupData = shift || [];

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    # insert new ids
    my @newGroupParams = ();
    my @newGroupValues = ();
    my @newGroupIDs    = (); # for profile update

    my $existingGroups = $self->loadPlanGroups($planID);
    my $existingGroupHash = {};

    foreach my $group (@{$existingGroups}) {
      $existingGroupHash->{$group->getGroupID()} = 1;
    }

    foreach my $updateGroup (@{$groupData}) {
      my $group = new PlugNPay::Membership::Group($self->{'merchantDB'});
      $group->loadGroupByName($updateGroup);
      if (!$group->getGroupID()) {
        push (@errorMsg, 'Invalid merchant group: ' . $updateGroup);
      } else {
        if (exists $existingGroupHash->{$group->getGroupID()}) {
          delete $existingGroupHash->{$group->getGroupID()};
        } else {
          push (@newGroupIDs, $group->getGroupID());
          push (@newGroupValues, $planID, $group->getGroupID());
          push (@newGroupParams, '(?,?)');
        }
      }
    }

    if (@errorMsg == 0) {
      # if need to insert new groups
      if (@newGroupParams > 0) {
        $dbs->executeOrDie('merchant_cust',
          q/INSERT INTO recurring1_plan_group_link 
            ( plan_id, 
              group_id )
            VALUES / . join(',', @newGroupParams), \@newGroupValues);
      }

      # remaining groups are going to be removed.
      if (keys %{$existingGroupHash} > 0) {
        my @removeGroupParams = ();
        my @removeGroupValues = ();

        my $sql = q/DELETE FROM recurring1_plan_group_link
                    WHERE plan_id = ?
                    AND group_id IN (/;
        push (@removeGroupValues, $planID);
        foreach my $groupID (keys %{$existingGroupHash}) {
          push (@removeGroupValues, $groupID);
          push (@removeGroupParams, '?');
        }

        $dbs->executeOrDie('merchant_cust', $sql . join(',', @removeGroupParams) . ')', \@removeGroupValues);
      }

      foreach my $groupID (@newGroupIDs) {
        $self->_updateProfileGroupsFromPlanUpdate($planID, $groupID);
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'updatePlanGroups'
      });

      push (@errorMsg, 'Error while attempting to update groups for payment plan.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

sub _updateProfileGroupsFromPlanUpdate {
  my $self = shift;
  my $planID = shift;
  my $groupID = shift;

  my $plan = new PlugNPay::Membership::Plan::Settings();
  my $settingIDs = $plan->loadSettingsVariationIDs($planID);

  if (@{$settingIDs} > 0) {
    my $profile = new PlugNPay::Membership::Profile();
    my $profileIDs = $profile->loadPlanProfiles($settingIDs);
    if (@{$profileIDs} > 0) {
      my $dbs = new PlugNPay::DBConnection();
      my $sql = q/DELETE FROM recurring1_profile_group_link
                  WHERE group_id = ?
                  AND profile_id IN (/;
      my @placeholders = map {'?'} @{$profileIDs};
      $dbs->executeOrDie('merchant_cust', $sql . join (',', @placeholders) . ')', [$groupID, @{$profileIDs}]);
    }
  }
}

#############################################
# Subroutine: loadProfileGroups
# -------------------------------------------
# Description:
#   Loads all the groups associated with a
#   billing profile.
sub loadProfileGroups {
  my $self = shift;
  my $billingProfileID = shift;

  my $groups = [];

  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('merchant_cust',
      q/SELECT group_id
        FROM recurring1_profile_group_link
        WHERE profile_id = ?/, [$billingProfileID], {})->{'result'};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        my $group = new PlugNPay::Membership::Group();
        $group->loadGroup($row->{'group_id'});
        push (@{$groups}, $group);
      }
    }
  };

  if ($@) {
    $self->_log({
      'error'    => $@,
      'function' => 'loadProfileGroups'
    });
  }

  return $groups;
}

##########################################
# Subroutine: saveProfileGroups
# ----------------------------------------
# Description:
#   Saves groups to a billing profile.
sub saveProfileGroups {
  my $self = shift;
  my $billingProfileID = shift;
  my $groupData = shift;

  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  if (ref($groupData) eq 'ARRAY') {
    if (@{$groupData} > 0) {
      my @IDs = ();
      my @placeholders = ();

      my $existingProfileGroups = $self->loadProfileGroups($billingProfileID);
      my $existingGroupHash = {};
      foreach my $group (@{$existingProfileGroups}) {
        $existingGroupHash->{$group->getGroupID()} = 1;
      }

      my $sql = q/INSERT INTO recurring1_profile_group_link 
                  ( group_id,
                    profile_id )
                  VALUES /;
      foreach my $group (@{$groupData}) {
        my $groupObj = new PlugNPay::Membership::Group($self->{'merchantDB'});
        $groupObj->loadGroupByName($group);
        my $groupID = $groupObj->getGroupID();
        if (!$groupID) {
          push (@errorMsg, 'Invalid merchant group: ' . $group);
        } else {
          if (!exists $existingGroupHash->{$groupID}) {
            push (@placeholders, '(?,?)');   
            push (@IDs, $groupID, $billingProfileID);
          }
        }
      }

      if (@errorMsg == 0) {
        if (@IDs > 0) {
          my $dbs = new PlugNPay::DBConnection();
          $dbs->executeOrDie('merchant_cust', $sql . join (',', @placeholders), \@IDs);
        }
      }
    }
  }

  if ($@ || @errorMsg > 0) {
    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'saveProfileGroups'
      });

      push (@errorMsg, 'Error while attempting to save groups to profile.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  }

  return $status;
}

###################################
# Subroutine: updateProfileGroups
# ---------------------------------
# Description:
#   Updates the groups associated 
#   with a billing profile.
sub updateProfileGroups {
  my $self = shift;
  my $billingProfileID = shift;
  my $groupData = shift;
 
  my $status = new PlugNPay::Util::Status(1);
  my @errorMsg;

  my $dbs = new PlugNPay::DBConnection();
  eval {
    $dbs->begin('merchant_cust');

    my $profile = new PlugNPay::Membership::Profile();
    $profile->loadBillingProfile($billingProfileID);

    my $planSettings = new PlugNPay::Membership::Plan::Settings();
    $planSettings->loadPlanSettings($profile->getPlanSettingsID());

    my $existingPlanGroups = $self->loadPlanGroups($planSettings->getPlanID());
    my $existingProfileGroups = $self->loadProfileGroups($billingProfileID);

    my $existingGroupHash = {};
    foreach my $group (@{$existingPlanGroups}) {
      $existingGroupHash->{$group->getGroupID()} = 1;
    }

    foreach my $group (@{$existingProfileGroups}) {
      $existingGroupHash->{$group->getGroupID()} = 1;
    }

    my @newGroupParams = ();
    my @newGroupValues = ();
    foreach my $updateGroup (@{$groupData}) {
      my $group = new PlugNPay::Membership::Group($self->{'merchantDB'});
      $group->loadGroupByName($updateGroup);
      if (!$group->getGroupID()) {
        push (@errorMsg, 'Invalid merchant group: ' . $updateGroup);
      } else {
        if (exists $existingGroupHash->{$group->getGroupID()}) {
          delete $existingGroupHash->{$group->getGroupID()};
        } else {
          push (@newGroupParams, '(?,?)');
          push (@newGroupValues, $billingProfileID, $group->getGroupID());
        }
      }
    }

    if (@errorMsg == 0) {
      if (@newGroupValues > 0) {
        $dbs->executeOrDie('merchant_cust',
          q/INSERT INTO recurring1_profile_group_link
            ( profile_id, 
              group_id )
            VALUES / . join(',', @newGroupParams), \@newGroupValues);
      }

      if (keys %{$existingGroupHash} > 0) {
        my @removeGroupParams = ();
        my @removeGroupValues = ();
        my $sql = q/DELETE FROM recurring1_profile_group_link
                    WHERE profile_id = ?
                    AND group_id IN (/;
        push (@removeGroupValues, $billingProfileID);
        foreach my $groupID (keys %{$existingGroupHash}) {
          push (@removeGroupParams, '?');
          push (@removeGroupValues, $groupID);
        }

        $dbs->executeOrDie('merchant_cust', $sql . join(',', @removeGroupParams) . ')', \@removeGroupValues);
      }
    }
  };

  if ($@ || @errorMsg > 0) {
    $dbs->rollback('merchant_cust');
    if ($@) {
      $self->_log({
        'error'    => $@,
        'function' => 'updateProfileGroups'
      });
 
      push (@errorMsg, 'Error while attempting to update profile groups.');
    }

    $status->setFalse();
    $status->setError(join(' ', @errorMsg));
  } else {
    $dbs->commit('merchant_cust');
  }

  return $status;
}

sub _log {
  my $self = shift;
  my $logInfo = shift;

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'membership_group' });
  $logger->log($logInfo);
}

1;
