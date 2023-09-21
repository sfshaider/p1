package PlugNPay::InputValidator;

# Class to validate input parameters for a given context
$|=1;

use strict;
use CGI;
use JSON::XS;
use miscutils;
use Time::HiRes;
use PlugNPay::Util::UniqueID;
use PlugNPay::Util::StackTrace;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Memcached;

# function for a one liner for getting filtered inputs for a context

sub filteredQuery
{
  my ($context,$debug) = @_;
  my $iv = new PlugNPay::InputValidator();
  if ($debug) {
    $iv->setDebug();
  }
  $iv->changeContext($context);

  my $q = new CGI;

  my %params;
  foreach my $param ($q->param()) {
    my @multi = $q->param($param);
    if (@multi > 1) {
      $params{$param} = \@multi;
    } else {
      $params{$param} = $q->param($param);
    }
  }

  return $iv->filterHash(%params);
}

###### Functions you want to use
##
##  $iv->changeContext('a context');     -  loads the ruleset for a context, from file if possible, if not, from database.
##
##  @array = $iv->unknownParameters(%hash);  -  returns an array of fields that are unknown to the input validator.
##
##  %hash = $iv->filterHash(%hash);      -  returns a hash of sanitized fields based on the rules of the input validator
##
##  %hash = $iv->validateHash(%hash);    -  returns a hash of fields (key) and whether or not they conform to the type defined
##
##  In additon, there are the following functions that work on an individual parameter:
##
##  $sanitizedValue = $iv->filter('parameterName',$parameterValue);
##  $boolean = $iv->validate('parameterName',$parameterValue);
##
##  Any value can be checked to see if it conforms to a specific type of string using the following:
##
##  $boolean = $iv->isOfType('type',$value);
##
##

my $preloadedContexts = '';
my $preloadFile = '/home/p/pay1/etc/InputValidator/combined';
if (-e $preloadFile) {
  open(PRELOAD,$preloadFile);
  $preloadedContexts = <PRELOAD>;
  close(PRELOAD);
}

sub new {
  my ($self,$context,$dontLoadFromFile) = @_;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  $self->{'memcached'} = new PlugNPay::Util::Memcached("inputvalidator");

  $self->{'debug'} = 0;

  if (!defined $dontLoadFromFile) {
    $dontLoadFromFile = 0;
  } else {
    $dontLoadFromFile = 1;
  }

  # set the log directory
  $self->{'logDirectory'} = '/home/p/pay1/logs/InputValidator';
  $self->{'caller'} = join(' ',caller()) . ' : new()';

  # create a session identifier
  my $sessionGenerator = new PlugNPay::Util::UniqueID;
  $sessionGenerator->generate();
  $self->{'session'} = $sessionGenerator->inHex();

  # create contexts hash
  my (%contexts);
  $self->{'contexts'} = \%contexts;

  my $characterSets = {};
  my $parameterTypes = {};

  $self->{'parameterTypesAndCharacterSetsLoaded'} = 0;
  if (keys %{$characterSets} == 0 || keys %{$parameterTypes} == 0) {
    ($characterSets, $parameterTypes) = $self->__loadInputValidatorMetaData();
    $self->{'parameterTypesAndCharacterSetsLoaded'} = 1;
  }

  $self->{'characterSets'} = $characterSets;
  $self->{'parameterTypes'} = $parameterTypes;

  # set the file for all of the above
  $self->{'allFile'} = '/home/p/pay1/etc/InputValidator/combined';

  # load the contexts file if preload did not work
  if (!$dontLoadFromFile && $self->{'parameterTypesAndCharacterSetsLoaded'} == 0) {
    if ($preloadedContexts ne '') {
      $self->deserializeAll('all',$preloadedContexts);
    } else {
      $self->__loadSerializedDataFromFile();
    }
    $self->{'parameterTypesAndCharacterSetsLoaded'} = 1;
  }

  # load context if inputted
  if (defined $context && $context != '') {
    $self->changeContext($context);
  }

  return $self;
}

sub __loadInputValidatorMetaData {
  my $self = shift;

  my $characterSetsLoaded = 0;
  my $parameterTypesLoaded = 0;

  my $characterSets = {};
  my $parameterTypes = {};

  # try to get from memcached
  $characterSets = $self->{'memcached'}->get('characterSets');
  $parameterTypes = $self->{'memcached'}->get('parameterTypes');

  if ($characterSets) {
    $characterSetsLoaded = 1;
  }

  if ($parameterTypes) {
    $parameterTypesLoaded = 1;
  }

  if ($characterSetsLoaded && $parameterTypesLoaded) {
    return ($characterSets, $parameterTypes);
  }

  my $dbh = &miscutils::dbhconnect('pnpsecurity');

  if (!$characterSetsLoaded) {
    my $characterSetsSTH = $dbh->prepare('select characterSetName, characterSet from inputValidatorCharacterSets');
    $characterSetsSTH->execute();
    my $characterSetsRows = $characterSetsSTH->fetchall_arrayref({});
    foreach my $charSetRow (@{$characterSetsRows}) {
      $characterSets->{$charSetRow->{'characterSetName'}} = $charSetRow->{'characterSet'};
    }
    $self->{'memcached'}->set('characterSets', $characterSets);
  }

  if (!$parameterTypesLoaded) {
    my $typesSTH = $dbh->prepare('select type, regex from inputValidatorParameterTypes');
    $typesSTH->execute();
    my $parameterTypesRows = $typesSTH->fetchall_arrayref({});
    foreach my $typeRow (@{$parameterTypesRows}) {
      $parameterTypes->{$typeRow->{'type'}} = $typeRow->{'regex'};
    }
    $self->{'memcached'}->set('parameterTypes', $parameterTypes);
  }

  return ($characterSets, $parameterTypes);
}

sub DESTROY {
  my ($self) = @_;
}

sub setDebug {
  my $self = shift;
  $self->{'debug'} = 1;
}

sub unsetDebug {
  my $self = shift;
  $self->{'debug'} = 0;
}

sub setRemoteUser {
  my $self = shift;
  my $remoteUser = lc shift;
  $remoteUser =~ s/[^a-z0-9_]//g;
  $self->{'remoteUser'} = $remoteUser;
}

sub session {
  my ($self) = @_;
  return $self->{'session'};
}

# Method: serializeAll($what);
# -------------------------------
# Takes entire contents of %contexts hash and produces a serialized output
#
sub serializeAll {
  my ($self,$what) = @_;
  if (!defined $what) {
    $what = 'all';
  }
  if ($what =~ /^(contexts|characterSets|parameterTypes)$/) {
    return JSON::XS->new->utf8->encode($self->{$what});
  } elsif ($what =~ /^all$/) {
    my %tmpHash;
    $tmpHash{'contexts'} = $self->{'contexts'};
    $tmpHash{'characterSets'} = $self->{'characterSets'};
    $tmpHash{'parameterTypes'} = $self->{'parameterTypes'};
    return JSON::XS->new->utf8->encode(\%tmpHash);
  }
}

# Method: deserializeAll($what,$serializedData);
# ----------------------------------------------------
# Takes serialized context input and loads the %contexts hash from it
#
sub deserializeAll {
  my ($self,$what,$serializedData) = @_;
  if ($what =~ /^(contexts|characterSets|parameterTypes)$/) {
    $self->{$what} = JSON::XS->new->utf8->decode($serializedData);
  }else {
    my $tmpHash = JSON::XS->new->utf8->decode($serializedData);
    $self->{'contexts'} = $tmpHash->{'contexts'};
    $self->{'characterSets'} = $tmpHash->{'characterSets'};
    $self->{'parameterTypes'} = $tmpHash->{'parameterTypes'};
  }
}

# Method: __loadSerializedDataFromFile();
# -------------------------------------------
# Loads serialized contexts from /home/p/pay1/etc/InputValidator/$whatFile
#
sub __loadSerializedDataFromFile {
  my ($self,$what,$file) = @_;
  if (!defined $what) {
    $what = 'all';
  }

  if ($what !~ /^(all)$/) { return 0; }

  if (defined $file) {
    $self->{$what . 'File'} = $file;
  }
  if (-e $self->{$what . 'File'}) {
    open(IVDATA,$self->{$what . 'File'});
    my $serializedData = <IVDATA>;
    $self->deserializeAll($what,$serializedData);
    close(IVDATA);
  }
}

# Method: displaySelf();
# ----------------------
# used for debugging only
#
sub displaySelf {
  my ($self,$extended) = @_;
  printf STDERR '| %-20s | %25s | %40s | %30s | %30s | %20s | %s',
         'Parameter Name',
         'Parameter Type',
         'Regex',
         'NegativeFilter',
         'PositiveFilter',
         'Multiple',
         "\n";
  print STDERR '----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------' . "\n";

  my $counter = 0;
  foreach my $parameter (sort keys %{$self->{'parameters'}}) {
    $counter++;
    printf STDERR '| %-20s | %25s | %40s | %30s | %30s | %20s | %s',
           $parameter,
           $self->{'parameters'}{$parameter}{'type'},
           $self->{'parameters'}{$parameter}{'regex'},
           $self->__getRegexForParameterForMode($parameter,'negativeFilter'),
           $self->__getRegexForParameterForMode($parameter,'positiveFilter'),
           $self->{'parameters'}{$parameter}{'multiple'},
           "\n";
    if ($counter % 5 == 0) {
      print STDERR '----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------' . "\n";
    }
  }
  print STDERR '----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------' . "\n";

  print STDERR "\n\n";

  if ($extended) {
    print STDERR '------------------------------ Parameter Types ------------------------------' . "\n";
    foreach my $parameterType (sort keys %{$self->{'parameterTypes'}}) {
      #print $parameterType . ' : ' . $self->{'parameterTypes'}{$parameterType} . "\n";
      printf STDERR '%30s : %s' . "\n",$parameterType,$self->{'parameterTypes'}{$parameterType};
    }
    print STDERR "\n\n";

    print STDERR '------------------------------ Character Sets  ------------------------------' . "\n";
    foreach my $characterSet (sort keys %{$self->{'characterSets'}}) {
      #print $characterSet . ' : "' . $self->{'characterSets'}{$characterSet} . "\"\n";
      printf STDERR '%30s : %s' . "\n",$characterSet,$self->{'characterSets'}{$characterSet};
    }
  }
}

# Method: changeContext($newContext);
# -----------------------------------
# Loads $newContext from the %contexts hash
#
sub changeContext {
  my ($self,$context) = @_;

  if (!defined $self->{'contexts'}{$context}) {
    if ($self->{'debug'}) {
      # log that context was not found in cache, loading from db
    }

    $self->loadContextFromDatabase($context);
  } else {
    if ($self->{'debug'}) {
      # log that context was found in cache
    }

    $self->{'parameters'}  = $self->{'contexts'}{$context};
  }

  $self->{'context'} = $context;
}

# Method: loadContextFromDatabase($newContext);
# -----------------------------------
# Loads $newContext from the database if the current context is not already $newContext
#
sub loadContextFromDatabase {
  my ($self,$context) = @_;
  $self->{'context'} = $context;
  $self->{'parameters'} = {};


  my $memcachedContextKey = "context-$context";
  my $parameterData = $self->{'memcached'}->get($memcachedContextKey);

  if ($parameterData) {
    $self->{'parameters'} = $parameterData;
    $self->{'contexts'}{$context} = $parameterData;
    return;
  }

  my $dbh = &miscutils::dbhconnect('pnpsecurity');

  # load valid contexts...
  my %validContexts;

  # load valid contexts from parameters table
  my $parameterContextSTH = $dbh->prepare('select context from inputValidatorParameters group by context');
  $parameterContextSTH->execute();
  while (my $row = $parameterContextSTH->fetchrow_hashref()) {
    $validContexts{$row->{'context'}} = 1;
  }
  $parameterContextSTH->finish();

  # load valid contexts from parameter filters table
  my $parameterFilterContextSTH = $dbh->prepare('select context from inputValidatorParameterFilters group by context');
  $parameterFilterContextSTH->execute();
  while (my $row = $parameterFilterContextSTH->fetchrow_hashref()) {
    $validContexts{$row->{'context'}} = 1;
  }
  $parameterContextSTH->finish();

  # check to see if the inputted context is a valid context
  if ($validContexts{$context} == 1) {
    #load the parameters, their types, and their regexps for the given context
    my $parametersSTH = $dbh->prepare('select parameterName, type, regex, multiple from inputValidatorParameters where context = ?');
    $parametersSTH->execute($context);
    my $parametersRows = $parametersSTH->fetchall_arrayref({});
    foreach my $paramRow (@{$parametersRows}) {
      $self->__addParameter($paramRow->{'parameterName'}, $paramRow->{'type'}, $paramRow->{'regex'}, $paramRow->{'multiple'});
    }
    $parametersSTH->finish();

    #load the filter lists for the parameters
    my $parameterFiltersSTH = $dbh->prepare('select parameterName, characterSetName, context, mode from inputValidatorParameterFilters where context = ?');
    $parameterFiltersSTH->execute($context);
    my $parameterFilters = $parameterFiltersSTH->fetchall_arrayref({});
    foreach my $paramFilterRow (@{$parameterFilters}) {
      $self->__addFilterForParameter($paramFilterRow->{'parameterName'}, $paramFilterRow->{'mode'}, $paramFilterRow->{'characterSetName'});
    }
    $parameterFiltersSTH->finish();

    $self->{'memcached'}->set($memcachedContextKey, $self->{'parameters'});
    $self->{'contexts'}{$context} = $self->{'parameters'};
  } else {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'inputvalidator' });
    my $logInfo = {
      'context' => $context,
      'message' => 'InputValidator called with invalid context [ ' . $context .' ]',
      'stackTrace' => new PlugNPay::Util::StackTrace()->string()
    };
    $logger->log($logInfo);
  }

  $dbh->breakConnection();
}

# Method: filter($parameter,$value);
# ----------------------------------
# Sanitizes a value based on the rules for the inputted parameter for the current contxt.
# Calls __filter($parameter,$value);
#
sub filter {
  my ($self,$parameter,$value) = @_;
  $self->{'caller'} = join(':',caller() . ' : filter()');
  my $newValue = $self->__filter($parameter,$value);
  return $newValue;
}

# Method: __filter($parameter,$value);
# ------------------------------------
# Internal function.  Do not call externally.
# Filters $value based on the rules for $parameter in the current context;
#
sub __filter {
  my ($self,$parameter,$value) = @_;
  $parameter =~ s/-/_/g;

  if (!exists($self->{'context'})) {
    die('Context not set');
  }

  # if it is a multiple parameter (i.e. item1, item2, etc.) strip out the number and compare against the base parameter type
  if ($self->__isMultiple($parameter)) {
    print STDERR "parameter [$parameter] is a multiple parameter\n" if $self->{'debug'};
    my $baseParameter = $self->__multipleBase($parameter);
    $parameter = $baseParameter;
  } elsif ($self->{'debug'}) {
    print STDERR "parameter [$parameter] is NOT a multiple parameter\n" if $self->{'debug'};
  }


  my $origvalue = $value;

  my $filterRegex;
  my $sieveRegex;

  my $filterExists = 0;
  if ($self->__validateParameter($parameter,'positiveFilter')) {
    print STDERR "parameter [$parameter] has a positive filter\n" if $self->{'debug'};
    $filterExists = 1;
    my $regex = $self->__getRegexForParameterForMode($parameter,'positiveFilter');
    $filterRegex = $regex;
    $value =~ s/$regex//g;
  } elsif ($self->{'debug'}) {
    print STDERR "parameter [$parameter] DOES NOT have a positive filter\n";
  }

  my $sieveExists = 0;
  if ($self->__validateParameter($parameter,'negativeFilter')) {
    print STDERR "parameter [$parameter] has a negative filter\n" if $self->{'debug'};
    $sieveExists = 1;
    my $regex = $self->__getRegexForParameterForMode($parameter,'negativeFilter');
    $sieveRegex = $regex;
    $value =~ s/$regex//g;
  } elsif ($self->{'debug'}) {
    print STDERR "parameter [$parameter] DOES NOT have a negative filter\n";
  }

  if ($origvalue ne $value) {
    my %diff = ();
    foreach my $ltr (split(//, $origvalue)) {
      $diff{$ltr}++;
    }

    foreach my $ltr (split(//, $value)) {
      delete $diff{$ltr};
    }

    my %removedChars = map { sprintf('0x%X', unpack('C*', $_)) => $diff{$_} } keys %diff;
  }

  return $value;
}

# Method: filterHash(%hash);
# --------------------------
# Filters a hash using the keys as parameter names.  Filtering is done based on the rules for the parameter name in the current context
#
sub filterHash {
  my ($self,%hash) = @_;
  $self->{'caller'} = join(':',caller()) . ' : filterHash()';
  foreach my $key (keys %hash) {
    # handle arrays
    if (ref $hash{$key} eq 'ARRAY') {
      my @filteredVals;
      foreach my $val (@{$hash{$key}}) {
        my $filteredValue = $self->__filter($key,$val);
        push @filteredVals,$filteredValue;
      }
      $hash{$key} = \@filteredVals;
    } else {
      $hash{$key} = $self->__filter($key,$hash{$key});
    }
  }

  return %hash;
}

# Method: unknownParameters();
# ----------------------------
# Returns a list of parameters that were passed in that are unknown for the current context
#
sub unknownParameters {
  my ($self,%hash) = @_;
  $self->{'caller'} = join(':',caller() . ' : unknownParameters()');

  my @unknownFields;
  foreach my $key (keys %hash) {
    # check to see if it's a multiple paramater, such as item1, item2, etc.
    if ($self->__isMultiple($key)) {
      my $baseKey = $self->__multipleBase($key);
      if ($baseKey eq $key) {
        push @unknownFields,$key; # A multiple parameter without a multiple is invalid.
        next;
      }
      $key = $baseKey;
    }
    if (!$self->__validateParameter($key)) {
      push @unknownFields,$key;
    }
  }

  return @unknownFields;
}


# Method: validate($parameter,$value);
# ------------------------------------
# Checks to see if $value is an acceptable value for $parameter in the current context.
# Calls __validate($parameter,$value);
#
sub validate {
  my ($self,$parameter,$value) = @_;
  $parameter =~ s/-/_/g;
  $self->{'caller'} = join(':',caller()) . ' : validate()';

  return $self->__validate($parameter,$value);
}

# Method: __validate($parameter,$value);
# --------------------------------------
# Internal function.  Do not call externally.
# Checks to see if $value is an acceptable value for $parameter in the current context.
# Uses the type of parameter unless there is a regex to override it.
#
sub __validate {
  my ($self,$parameter,$value) = @_;
  $parameter =~ s/-/_/g;

  if (!exists($self->{'context'})) {
    die('Context not set');
  }

  # if it is a multiple parameter (i.e. item1, item2, etc.) strip out the number and compare against the base parameter type
  if ($self->__isMultiple($parameter)) {
    $parameter = $self->__multipleBase($parameter);
  }

  if (!$self->__validateParameter($parameter,'validate')) { return 0; }
  if ($self->__validateParameter($parameter,'regex')) {
    my $regex = $self->{'parameters'}{$parameter}{'regex'};
    if ($value =~ m/$regex/) { return 1; }
    else { return 0; }
  } else {
    my $type = $self->__getTypeForParameter($parameter);
    return $self->isOfType($value,$type);
  }
}


# Method: validateHash(%hash);
# --------------------------
# Validates a hash using the keys as parameter names.  Validation is done based on the rules for the parameter name in the current context
# Calls __validate($parameter,$value);
#
sub validateHash {
  my ($self,%hash) = @_;
  $self->{'caller'} = join(':',caller() . ' : validateHash()');
  my %validateHash;

  foreach my $key (keys %hash) {
    $validateHash{$key} = $self->__validate($key,$hash{$key});
  }

  return %validateHash;
}


# Method: isOfType($value,$type);
# -------------------------------
# Returns true or false based on wether or not $value is of type $type;
#
sub isOfType {
  my ($self,$value,$type) = @_;
  if ($self->{'caller'} =~ /InputValidator\.pm/) {
    $self->{'caller'} .= ' -> ' . join(':',caller()) . ' : isOfType()';
  } else {
    $self->{'caller'} = join(':',caller()) . ' : isOfType()';
  }
  if ($self->__validateType($type)) {
    my $typeRegex = $self->{'parameterTypes'}{$type};
    if ($value =~ m/$typeRegex/) { return 1; }
  }
  return 0;
}

# Method: __validateParameter($parameter,$mode);
# ----------------------------------------------
# Internal function, do not call externally.
#
# Validates one of the following in the current context:
#   1) If mode is not set, validates that a parameter with that name exists
#   2) If mode is 'filter', validates that a parameter with that name exists and has a filter regex
#   3) If mode is 'sieve', validates that a parameter with that name exists and has a sieve regex
#   4) If mode is 'regex', validates that a parameter with that name exists and has a regex
#
# The only valid options for $mode are 'filter' or 'sieve', otherwise do not pass it.
#
sub __validateParameter {
  my ($self,$parameter,$mode) = @_;

  if ($self->{'caller'} =~ /InputValidator\.pm/) {
    $self->{'caller'} .= ' -> ' . join(':',caller()) . ' : __validateParameter()';
  } else {
    $self->{'caller'} = join(':',caller()) . ' : __validateParameter()';
  }

  $parameter =~ s/-/_/g;
  my $premode = $mode;
  $mode =~ s/[^a-zA-Z]//g;
  if ($mode ne $premode) {
    die('Invalid mode passed to __validateParameter()');
  }

  if (exists($self->{'parameters'}{$parameter})) {
    if (defined $mode && $mode ne 'validate' && $mode ne 'multiplecheck') {
      if (exists($self->{'parameters'}{$parameter}{$mode})) {
        return 1;
      } else {
        return 0;
      }
    }
    return 1;
  } else {
    if (!exists($self->{'invalidatedParameters'}->{$parameter}) && $mode ne 'multiplecheck') {
      $self->{'invalidatedParameters'}->{$parameter} = 1;
    }
    return 0;
  }
}

# Method: __validateType($type);
# ------------------------------
# Internal function, do not call externally.
#
# Validates that a regex for $type exists in the current context.
sub __validateType {
  my ($self,$type) = @_;

  if (defined $self->{'parameterTypes'}{$type}) {
    return 1;
  }
  return 0;
}


# Method: __isMultiple($parameter);
# ---------------------------------
# Internal function, do not call externally.
#
# Takes a parameter name and determines if it is a parameter that may be followed by a number to allow multiple appearances
#
sub __isMultiple {
  my ($self,$parameter) = @_;

  if ($self->__validateParameter($self->__multipleBase($parameter),'multiplecheck')) {
    return $self->{'parameters'}{$self->__multipleBase($parameter)}{'multiple'};
  } else {
    return 0;
  }
}


# Method: __multipleBase($parameter);
# -----------------------------------
# Internal function, do not call externally.
#
# Takes a parameter name and strips off trailing digits.
#
sub __multipleBase {
  my ($self,$parameter) = @_;
  $parameter =~ s/\d+$//;
  return $parameter;
}

# Method: __addParameter($parameter,$type,$regex,$multiple);
# ----------------------------------------------------------
# Internal function. DO NOT CALL EXTERNALLY
#
# Adds a parameter to the object in the current context.
#
sub __addParameter {
  my ($self,$parameter,$type,$regex,$multiple) = @_;
  if (!defined $type) { $type = ''; }
  if (!defined $regex) { $regex = ''; }
  if (!exists($self->{'parameters'}{$parameter})) {
    my %h;
    $self->{'parameters'}{$parameter} = \%h;
    $self->{'parameters'}{$parameter}{'multiple'} = $multiple;
    $self->__setTypeForParameter($parameter,$type);
    $self->__setRegexForParameter($parameter,$regex);
    return 1;
  }
  return 0;
}

# Method: __setRegexForParameter($parameter,$regex);
# --------------------------------------------------
# Internal function. DO NOT CALL EXTERNALLY
#
# Sets the regex for the parameter in the current context.
#
sub __setRegexForParameter {
  my ($self,$parameter,$regex) = @_;
  if ($self->__validateParameter($parameter)) {
    $self->{'parameters'}{$parameter}{'regex'} = $regex;
    return 1;
  }
  return 0;
}



# Method: __setTypeForParameter($parameter,$type);
# --------------------------------------------------
# Internal function. DO NOT CALL EXTERNALLY
#
# Sets the type for the parameter in the current context.
#
sub __setTypeForParameter {
  my ($self,$parameter,$type) = @_;
  if ($self->__validateParameter($parameter) && $self->__validateType($type)) {
    $self->{'parameters'}{$parameter}{'type'} = $type;
    return 1;
  }
  return 0;
}

sub __getTypeForParameter {
  my ($self,$parameter) = @_;
  if($self->__validateParameter($parameter)) {
    return $self->{'parameters'}{$parameter}{'type'};
  }
}

sub __addFilterForParameter {
  my ($self,$parameter,$mode,$characterSetName) = @_;
  if ($self->__validateParameter($parameter)) {
    if (!exists $self->{'parameters'}{$parameter}{$mode}) {
      $self->{'parameters'}{$parameter}{$mode} = [];
    }
    push(@{$self->{'parameters'}{$parameter}{$mode}},$characterSetName);
    return 1;
  }
  return 0;
}

sub __getRegexForParameterForMode {
  my ($self,$parameter,$mode) = @_;
  if (!exists($self->{'parameters'}{$parameter}{$mode})) {
    return '';
  }
  my $regex = '';
  foreach my $characterSetName (@{$self->{'parameters'}{$parameter}{$mode}}) {
    $regex .= $self->{'characterSets'}{$characterSetName};
  }
  my $not = '';
  if ($mode =~ /^positiveFilter$/) {
    $not = '^';
  }
  $regex = '[' . $not . $regex . ']+';

  return $regex;
}

1;
