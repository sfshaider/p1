package PlugNPay::Features;

use strict;
use PlugNPay::InputValidator;
use PlugNPay::DBConnection;
use PlugNPay::Authentication::Login;
use PlugNPay::Util::Memcached;
use JSON::XS;

use overload '""' => 'getFeatureString';


# access and update features
# usage example:
#
#  my $features = new PlugNPay::Features($ENV{'REMOTE_USER'},'general');
#  if ($features->get('decryptFlag')) { # merchant has decrypt flag set
#    ...
#  };
#

our $_metadata;


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  $self->{'memcached'} = new PlugNPay::Util::Memcached("Features");

  if (!defined $_metadata) {
    $self->_loadFeatureMetadata();
  }

  my ($selector, $context) = @_;
  if ($selector && !$context) {
    $context = $selector;
    $selector = undef;
  }

  $context = $context || 'general';


  if ($context) {
    $self->setContext($context);
  }

  if ($selector) {
    $self->setSelector($selector);
  }

  if ($selector && $context) {
    $self->loadContext($context);
  }

  return $self;
}

## sets the value to lookup against (most of the time will be the username, sometimes will be login)
sub setSelector {
  my $self = shift;
  my $selector = shift;
  my $iv = new PlugNPay::InputValidator();
  $iv->changeContext('global');
  $selector = $iv->filter('selector',$selector);
  $self->{'selector'} = $selector;
}

sub getSelector {
  my $self = shift;
  return $self->{'selector'};
}

sub setContext {
  my $self = shift;
  my $context = shift;

  $context =~ s/[^A-Za-z_]//g;
  $self->{'context'} = $context;
}

sub getContext {
  my $self = shift;
  return $self->{'context'};
}

# return a COPY
sub getFeatures {
  my $self = shift;
  my $features = $self->{'features'} || {};
  my %return = %{$features} ;
  return \%return;
}

## load a feature context
sub loadContext {
  my $self = shift;
  my ($context) = @_;

  $self->setContext($context);
  $self->load();
}


sub load {
  my $self = shift;
  my $context = $self->getContext();
  my $selector = $self->getSelector();

  my $cacheKey = $selector . '-' . $context;

  my $cachedFeatures = $self->{'memcached'}->get($cacheKey);

  if ($cachedFeatures) {
    $self->{'features'} = $cachedFeatures;
    return;
  }

  my $featureContextMapData = $self->getFeatureContextMapData();

  if ($featureContextMapData) {
    if ($featureContextMapData->{'use_db'}) {
      # not yet implemented

    } else {
      # use the old features storage
      $self->{'database'} = $featureContextMapData->{'database_name'};
      $self->{'table'} = $featureContextMapData->{'table_name'};
      $self->{'column'} = $featureContextMapData->{'column_name'};
      $self->{'selector_column'} = $featureContextMapData->{'selector_column'};
      $self->__loadContextFromFeatureString($self->{'database'},$self->{'table'},$self->{'column'},$self->{'selector_column'});
    }
    $self->{'useDB'} = $featureContextMapData->{'use_db'};
  } else {
    die('Invalid feature context');
  }

  if (defined $self->{'features'}) {
    $self->{'memcached'}->set($cacheKey, $self->{'features'},300);
  }
}


##
## save the feature context
##
sub saveContext {
  my $self = shift;
  my $context = $self->getContext();
  my $selector = $self->getSelector();

  my $featureContextMapData = $self->getFeatureContextMapData();

  if ($featureContextMapData) {
    if ($self->{'useDB'}) {
      # not yet implemented
    } else {
      # use the old features storage
      $self->{'database'} = $featureContextMapData->{'database_name'};
      $self->{'table'} = $featureContextMapData->{'table_name'};
      $self->{'column'} = $featureContextMapData->{'column_name'};
      $self->{'selector_column'} = $featureContextMapData->{'selector_column'};
      $self->__saveContextToFeatureString($self->{'database'},$self->{'table'},$self->{'column'},$self->{'selector_column'});
    }

    my $cacheKey = $self->getSelector() . '-' . $self->getContext();
    $self->{'memcached'}->set($cacheKey, $self->{'features'},300);
  }
}

sub getFeatureContextMapData {
  my $self = shift;

  my $cacheKey = 'featureContextMapData-' . $self->{'context'};

  my $data = $self->{'memcached'}->get($cacheKey);

  if ($data) {
    return $data;
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');

  my $sth = $dbh->prepare(q/ SELECT database_name,table_name,column_name,selector_column,use_db
                             FROM featureContextMap
                             WHERE context = ?
                           /);

  $sth->execute($self->{'context'});

  $data = $sth->fetchrow_hashref;
  $self->{'memcached'}->set($cacheKey, $data);

  return $data;
}


##
## load context from database format
##
sub __loadContextFromFeaturesTable {
   # stub for future
}


##
## loads the feature context from the old way they are stored, in the customers table under columns, fraud_config, in acl_login, etc.
##
sub __loadContextFromFeatureString {
  my $self = shift;
  my ($database,$table,$column,$selector_column) = @_;

  # use service to load features instead of calling login database directly
  if ($database eq 'logindb' && $table eq 'acl_login' && $column eq 'features') {
    my $loginClient = new PlugNPay::Authentication::Login({
      login => $self->{'selector'}
    });
    $loginClient->setRealm('PNPADMINID');
    my $result = $loginClient->getLoginInfo();
    if (!$result) {
      die('failed to load features for login');
    }

    my $loginInfo = $result->get('loginInfo');
    my $featuresMap = $loginInfo->{'features'};
    my $featuresString = $loginClient->featuresMapToString($featuresMap);
    $self->parseFeatureString($featuresString);
  } else {
    $self->__loadContextFromFeatureStringFromDatabase(@_);
  }
}

sub __loadContextFromFeatureStringFromDatabase {
  my $self = shift;
  my ($database,$table,$column,$selector_column) = @_;

  my $featureString = '';

  # quick sanity check, not user input, but still want to make sure it wasn't entered incorrectly, so not using inputvalidator
  $database =~ s/[^_A-Za-z0-9]//g;
  $table    =~ s/[^_A-Za-z0-9]//g;
  $column   =~ s/[^_A-Za-z0-9]//g;
  $selector_column   =~ s/[^_A-Za-z0-9]//g;

  my $query = 'SELECT ' . $column . ' FROM ' . $table . ' WHERE ' . $selector_column . ' = ?';

  my $dbh;

  $dbh = PlugNPay::DBConnection::connections()->getHandleFor($database);

  my $sth = $dbh->prepare($query);
  $sth->execute($self->{'selector'});

  if (my $row = $sth->fetchrow_hashref) {
    $featureString = $row->{$column};
  }

  $sth->finish;

  if ($database ne 'pnpmisc') {
    $dbh->disconnect;
  }

  $self->parseFeatureString($featureString);
}


## Parses a feature string into this object
sub parseFeatureString {
  my $self = shift;
  my $featureString = shift;

  my @pairs = split(/,/,$featureString);
  # clear currently set features
  $self->{'features'} = {};
  foreach my $pair (@pairs) {
    my ($key,$value) = split(/=/,$pair);
    $self->{'features'}->{$key} = $value;
  }
  return $self->getFeatures();
}



##
## saves the feature context in the old way, in the customers table, etc
##
sub __saveContextToFeatureString {
  my $self = shift;
  my ($database,$table,$column,$selector_column) = @_;

  my $featureString = $self->getFeatureString();

  # quick sanity check, not user input, but still want to make sure it wasn't entered incorrectly, so not using inputvalidator
  $database =~ s/[^_A-Za-z0-9]//g;
  $table    =~ s/[^_A-Za-z0-9]//g;
  $column   =~ s/[^_A-Za-z0-9]//g;
  $selector_column   =~ s/[^_A-Za-z0-9]//g;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($database);

  my $query = 'UPDATE ' . $table . ' SET ' . $column . ' = ? WHERE ' . $selector_column . ' = ?';

  my $sth = $dbh->prepare($query);
  $sth->execute($featureString,$self->{'selector'});
  $sth->finish;

  if ($database ne 'pnpmisc') {
    $dbh->disconnect;
  }
}

##
## save the features to the new database format.
##
sub saveContextToFeaturesTable {
  # stub for future use
}

##
## get a list of features
##
sub getSetFeatures {
  my $self = shift;
  my @values = keys %{$self->{'features'}};
  return \@values;
}

##
## get a feature value
##
sub get {
  my $self = shift;
  my $key = shift;
  my $value;
  my $testJSON = $self->{'features'}->{$key};
  $testJSON =~ s/^\s+//g;
  $testJSON =~ s/\s+$//g;

  if ($testJSON =~ /^[\[|\{].*[\]|\}]$/) {
    $testJSON =~ s/\|/\,/g;
    $testJSON =~ s/\&quot\;/\"/g;
    eval {
      $value = JSON::XS->new->utf8->decode($testJSON);
    };
  }
  if (!defined $value) {
    $value = $self->{'features'}->{$key};
  }
  return $value;
}

sub _loadFeatureMetadata {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT feature_name, inheritable, for_gateway_account, for_reseller_account
      FROM feature
  /);

  $sth->execute();

  my %featureMetadata;

  my $results = $sth->fetchall_arrayref({});
  if ($results) {
    foreach my $row (@{$results}) {
      my $featureName = $row->{'feature_name'};

      my %featureInfo;
      $featureInfo{'inheritable'} = $row->{'inheritable'};

      $featureMetadata{$featureName} = \%featureInfo;
    }
    $_metadata = \%featureMetadata;
  }
}

sub getNonInheritableFeatureNames {
  my $self = shift;
  my @list;

  foreach my $feature (keys %{$_metadata}) {
    if (!$_metadata->{$feature}{'inheritable'}) {
      push @list,$feature;
    }
  }

  return \@list;
}

##
## set a feature value
##
sub set {
  my $self = shift;
  my ($key,$value) = @_;

  my $isJSON;
  # test if value is JSON, if it is, substitute quotes and commas
  # first see if it starts and ends like a JSON object.
  if ($value =~ /^\s*?[\[|\{].*[\]|\}]\s*?$/) {
    # then try and decode it
    # if decoded, set isJSON to 1
    eval {
      decode_json($value);
      $isJSON = 1; # this will not get called if the decode fails
    };
  } elsif (ref($value)) {  # test if value is an object, if so, make JSON
    $value = JSON::XS->new->utf8->encode($value);
    $isJSON = 1;
  }

  if ($isJSON) {
    # turn commas into pipes, and quotes into &quot;
    $value =~ s/,/\|/g;
    $value =~ s/\"/\&quot\;/g;
  }

  $key =~ s/[,=]//g;   # key definitely cannot contain commas or equals
  $value =~ s/[,=]//g; # value definitely cannot contain commas or equals

  # inputvalidator could actually be used here
  my $iv = new PlugNPay::InputValidator();
  $iv->changeContext('features');
  $value = $iv->filter($key,$value);

  $self->{'features'}->{$key} = $value;
}

##
## get an array of feature values
##
sub getFeatureValues {
  my $self = shift;
  my ($key) = @_;

  $key =~ s/[,=]//g;

  my @values = split(/\|/,$self->{'features'}->{$key});

  return \@values;
}

##
## set a feature from an array of values
##
sub setFeatureValues {
  my $self = shift;
  my $key = shift;
  my $arrayRef = shift;

  $key =~ s/[,=]//g;

  $self->{'features'}->{$key} = join('|',@{$arrayRef});
}

##
## add a feature value to a feature that is a pipe delimited list of values
##
sub appendValueToFeature {
  my $self = shift;
  my ($key,$value) = @_;

  $value =~ s/[^A-Za-z0-9_]//g;

  my %values = map { $_ => 1 } $self->getFeatureValues($key);
  $values{$value} = 1;
  $self->{'features'}->{$key} = $self->setFeatureValues(keys %values);
}


##
## remove a feature value from a feature that is a pipe delimited list of values
##
sub removeValueFromFeature {
  my $self = shift;
  my ($key,$value) = @_;

  $value =~ s/[^A-Za-z0-9_]//g;

  my %values = map { $_ => 1 } $self->getFeatureValues($key);
  delete $values{$value};
  $self->{'features'}->{$key} = $self->setFeatureValues($key,keys %values);
}


##
## returns true or false, true if the feature list contains the value, false if otherwise
##
sub featureContains {
  my $self = shift;
  my ($key,$containsString) = @_;

  my %contains;
  map { $contains{$_} = 1; } split(/\|/,$self->{'features'}->{$key});

  return ($contains{$containsString} ? 1 : 0);
}

##
## returns a string in the format used in the old storage method
##
sub getFeatureString {
  my $self = shift;

  my $string = '';

  my @pairs;
  foreach my $key (sort keys %{$self->{'features'}}) {
    push @pairs, $key . '=' . $self->{'features'}->{$key};
  }

  $string = join(',',@pairs);

  return $string;
}

##
## removes a feature
##
sub remove {
  my $self = shift;
  my $key = shift;

  delete $self->{'features'}{$key};
}

# old, inconsistent, name
sub removeFeature {
 my $self = shift;
 $self->remove(@_);
}

sub search {
  my $self = shift;
  my $feature = shift;
  my $value = shift;
  my $context = $self->getContext();
  my $selector = $self->getSelector();

  if (!defined $feature) {
    die('Feature name not specified in feature search');
  }

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('pnpmisc',q/ SELECT database_name,table_name,column_name,selector_column,use_db
                             FROM featureContextMap
                             WHERE context = ?
                           /);

  $sth->execute($self->{'context'});

  my $data = {};
  if (my $row = $sth->fetchrow_hashref) {
    if ($row->{'use_db'}) {
      # not yet implemented

    } else {
      # use the old features storage
      $self->{'database'} = $row->{'database_name'};
      $self->{'table'} = $row->{'table_name'};
      $self->{'column'} = $row->{'column_name'};
      $self->{'selector_column'} = $row->{'selector_column'};
      $data = $self->__getSelectorsWithFeatureSet($self->{'database'},$self->{'table'},$self->{'column'},$self->{'selector_column'},$feature);
    }
    $self->{'useDB'} = $row->{'use_db'};
  } else {
    die('Invalid feature context');
  }

  if ($value) { # if a value is specified, only return selectors who has the feature with a matching value
    # modify value for regex search
    # escape any regex metacharacters
    $value =~ s/([\^\$\.\*\+\?\|\(\)\[\]\{\}\\])/\\$1/g;

    # translate % sign at beginning to match anything before the string
    if ($value !~ /^%/) {
      $value = '^' . $value;
    } else {
      $value = substr $value,1;
    }

    # searching in middle not supported, too much of a PITA!

    # translate % sign at end to match anything before the string, unless preceeded by a backslash (doubled due to escaping earlier)
    if ($value !~ /[^\\]{2}%$/) {
      $value =~ s/\\\\%$/%\$/;
    } else {
      $value =~ s/\\\\%$//;
    }

    my $filteredData = {};
    foreach my $selector (keys %{$data}) {
      my $selectorFeatures = $data->{$selector};
      if ($selectorFeatures->get($feature) =~ /$value/) {
        $filteredData->{$selector} = $data->{$selector};
      }
    }
    $data = $filteredData;
  }
  return $data;
}

sub __getSelectorsWithFeatureSet {
  my $self = shift;
  my ($database,$table,$column,$selector_column,$feature) = @_;

  # going to do a like because....features.
  my $featureFirst = $feature . '=%';
  my $featureNotFirst = '%,' . $feature . '=%';

  my $featureString = '';

  # quick sanity check, not user input, but still want to make sure it wasn't entered incorrectly, so not using inputvalidator
  $database =~ s/[^_A-Za-z0-9]//g;
  $table    =~ s/[^_A-Za-z0-9]//g;
  $column   =~ s/[^_A-Za-z0-9]//g;
  $selector_column   =~ s/[^_A-Za-z0-9]//g;

  my $query = 'SELECT ' . $selector_column . ',' . $column . ' FROM ' . $table . ' WHERE ' . $column . ' LIKE ? OR ' . $column . ' LIKE ?';

  my $dbs = new PlugNPay::DBConnection();
  my $data = $dbs->fetchallOrDie($database,$query,[$featureFirst,$featureNotFirst],{});
  my $rows = $data->{'result'};

  my %selectors = map {
    # create a features object without hitting the database...
    my $theFeatures = new PlugNPay::Features();
    $theFeatures->setContext($self->getContext());
    $theFeatures->setSelector($_->{$selector_column});
    $theFeatures->parseFeatureString($_->{$column});

    # then return the hash tuple
    $_->{$selector_column} => $theFeatures
  } @{$rows}; #  end of map

  return \%selectors;
}

1;
