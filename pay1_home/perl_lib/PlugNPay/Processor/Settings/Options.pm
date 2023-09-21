package PlugNPay::Processor::Settings::Options;

use strict;

use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;

our $_optionsCache;
our $_subsettingsCache;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!defined $_optionsCache) {
    $_optionsCache = new PlugNPay::Util::Cache::LRUCache(40);
  }
  if (!defined $_subsettingsCache) {
    $_subsettingsCache = new PlugNPay::Util::Cache::LRUCache(40);
  }
  return $self;
}

sub setSettingID {
  my $self = shift;
  my $id = shift;
  $self->{'settingID'} = $id;
}

sub getSettingID {
  my $self = shift;
  return $self->{'settingID'};
}

sub getOptions {
  my $self = shift;
  my $id = $self->getSettingID();

  my $options = [];
  if ($_optionsCache->contains($id)) {
    $options = $_optionsCache->get($id);
  } else {
    $self->load();
    $options = $_optionsCache->get($id);
  }
  return $options;
}

# this loads all sibling setting options as well to reduce database hits.
sub load {
  my $self = shift;
  $self->_loadOptions();
}

sub _loadOptions {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT id,setting_id, `option`,display FROM processor_setting_option WHERE setting_id in (
      SELECT s.id FROM processor_setting s 
        LEFT JOIN processor_setting s2 
               ON s2.id = ?
     WHERE s.processor_id = s2.processor_id)
  /);

  $sth->execute($self->getSettingID());

  my $results = $sth->fetchall_arrayref({});

  my @optionIDs;
  my %options;

  if ($results) {
    my %settings;
    foreach my $row (@{$results}) {
      my $id = $row->{'id'};
      my $settingID = $row->{'setting_id'};
      my $option = $row->{'option'};
      my $display = $row->{'display'};
      if (!defined $settings{$settingID}) {
        $settings{$settingID} = [];
      }

      # save the option in a hash so we can add subsettings to it later
      $options{$id} = {option => $option, display => $display};
      push @{$settings{$settingID}},$options{$id};
      push @optionIDs,$id;
    }

    my $subsettings = $self->_loadSubsettings(\@optionIDs);
    foreach my $optionID (keys %{$subsettings}) {
      $options{$optionID}{'subsettings'} = $subsettings->{$optionID};
    }

    # populate the cache
    foreach my $settingID (keys %settings) {
      $_optionsCache->set($settingID,$settings{$settingID});
    }
  }
  return \@optionIDs;
}

sub _loadSubsettings {
  my $self = shift;
  my $optionIDs = shift;

  my $placeholders = join(',',map { '?' } @{$optionIDs});
  
  my %subsettings;
  if ($placeholders ne '') {
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT parent_setting_option_id, subsetting_id FROM processor_subsetting WHERE parent_setting_option_id in (/ . $placeholders . q/)
    /);
  
    $sth->execute(@{$optionIDs});
  
    my $results = $sth->fetchall_arrayref({});
  
    if ($results) {
      foreach my $row (@{$results}) {
        my $optionID = $row->{'parent_setting_option_id'};
        my $subsettingID = $row->{'subsetting_id'};
        if (!defined $subsettings{$optionID}) {
          $subsettings{$optionID} = [];
        }
        push @{$subsettings{$optionID}},$subsettingID;
      }
    }
  }
  return \%subsettings;
}

1;
