#!/usr/bin/perl
# Class to validate input parameters for a given context
use strict;
use JSON::XS;
use miscutils;

package InputValidator;


###### Functions you want to use
##
##  $iv->changeContext('a context');     -  loads the ruleset for a context, from file if possible, if not, from database.
## 
##  @array = $iv->unknownFields(%hash);  -  returns an array of fields that are unknown to the input validator.
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
  my %s;
  $self = \%s;
  bless $self,'InputValidator';

  $self->{'debug'} = 0;

  if (!defined $dontLoadFromFile) {
    $dontLoadFromFile = 0;
  } else {
    $dontLoadFromFile = 1;
  }

  # set the log directory
  $self->{'logDirectory'} = '/home/p/pay1/logs/InputValidator';
  $self->{'caller'} = join(' ',caller()) . ' : new()';


  # create contexts hash
  my (%contexts,%characterSets,%parameterTypes);
  $self->{'contexts'} = \%contexts;
  $self->{'characterSets'} = \%characterSets;
  $self->{'parameterTypes'} = \%parameterTypes;

  # set the file for all of the above
  $self->{'allFile'} = '/home/p/pay1/etc/InputValidator/combined';

  $self->{'parameterTypesAndCharacterSetsLoaded'} = 0;

  # load the contexts file if preload did not work
  if (!$dontLoadFromFile) {
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


sub DESTROY {
  my ($self) = @_;
  $self->__closeLog();
}


sub setDebug {
  my ($self) = @_;
  $self->{'debug'} = 1;
}

sub unsetDebug {
  my ($self) = @_;
  $self->{'debug'} = 0;
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
  my ($self) = @_;
  printf '| %-20s | %25s | %40s | %30s | %30s | %20s | %s', 
         'Parameter Name',
         'Parameter Type',
         'Regex',
         'Filter',
         'Sieve',
         'Multiple',
         "\n";
  print '----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------' . "\n";

  my $counter = 0;
  foreach my $parameter (sort keys %{$self->{'parameters'}}) {
    $counter++;
    printf '| %-20s | %25s | %40s | %30s | %30s | %20s | %s', 
           $parameter, 
           $self->{'parameters'}{$parameter}{'type'},
           $self->{'parameters'}{$parameter}{'regex'},
           $self->__getRegexForParameterForMode($parameter,'filter'),
           $self->__getRegexForParameterForMode($parameter,'sieve'),
           $self->{'parameters'}{$parameter}{'multiple'},
           "\n";
    if ($counter % 5 == 0) {
      print '----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------' . "\n";
    }

    #print '------------------------------------------------------------' . "\n";
    #print '                    Type : ' . $self->{'parameters'}{$parameter}{'type'} . "\n";
    #print '                   Regex : ' . $self->{'parameters'}{$parameter}{'regex'} . "\n";
    #print '                  Filter : ' . $self->__getRegexForParameterForMode($parameter,'filter') . "\n";
    #print '                   Sieve : ' . $self->__getRegexForParameterForMode($parameter,'sieve') . "\n";
    #print '    Multiple Appearances : ' . $self->{'parameters'}{$parameter}{'multiple'} . "\n";
    #print "\n\n";
  }
  print '----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------' . "\n";

  print "\n\n";
  
  print '------------------------------ Parameter Types ------------------------------' . "\n";
  foreach my $parameterType (sort keys %{$self->{'parameterTypes'}}) {
    #print $parameterType . ' : ' . $self->{'parameterTypes'}{$parameterType} . "\n";
    printf '%30s : %s' . "\n",$parameterType,$self->{'parameterTypes'}{$parameterType};
  }
  print "\n\n";
  
  print '------------------------------ Character Sets  ------------------------------' . "\n";
  foreach my $characterSet (sort keys %{$self->{'characterSets'}}) {
    #print $characterSet . ' : "' . $self->{'characterSets'}{$characterSet} . "\"\n";
    printf '%30s : %s' . "\n",$characterSet,$self->{'characterSets'}{$characterSet};
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
  $self->__closeLog();
}

# Method: loadContextFromDatabase($newContext);
# -----------------------------------
# Loads $newContext from the database if the current context is not already $newContext
#
sub loadContextFromDatabase {
  my ($self,$context) = @_;
  $self->{'context'} = $context;
  $self->{'parameters'} = {};
  $self->{'parameterTypes'} = {};
  $self->{'characterSets'} = {};

  
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
    #load the parameter types
    my $typesSTH = $dbh->prepare('select type, regex from inputValidatorParameterTypes');
    $typesSTH->execute();
    while (my $row = $typesSTH->fetchrow_hashref()) {
      my %row = %{$row};
      $self->__addParameterType($row{'type'},$row{'regex'});
    }
    $typesSTH->finish();
    
   
    # load the character sets
    my $characterSetsSTH = $dbh->prepare('select characterSetName, characterSet from inputValidatorCharacterSets');
    $characterSetsSTH->execute();
    while (my $row = $characterSetsSTH->fetchrow_hashref()) {
      my %row = %{$row};
      $self->__addCharacterSet($row{'characterSetName'},$row{'characterSet'});
    }
    $characterSetsSTH->finish();

    
    #load the parameters, their types, and their regexps for the given context
    my $parametersSTH = $dbh->prepare('select parameterName, type, regex, multiple from inputValidatorParameters where context = ?');
    $parametersSTH->execute($context);
    while (my $row = $parametersSTH->fetchrow_hashref()) {
      my %row = %{$row};
      $self->__addParameter($row{'parameterName'},$row{'type'},$row{'regex'},$row{'multiple'});
    }
    $parametersSTH->finish();
    
    
    #load the filter lists for the parameters
    my $parameterFiltersSTH = $dbh->prepare('select parameterName, characterSetName, context, mode from inputValidatorParameterFilters where context = ?');
    $parameterFiltersSTH->execute($context);
    while (my $row = $parameterFiltersSTH->fetchrow_hashref()) {
      my %row = %{$row};
     $self->__addFilterForParameter($row{'parameterName'},$row{'mode'},$row{'characterSetName'});
    }
    $parameterFiltersSTH->finish();
  }
  $self->{'contexts'}{$context} = $self->{'parameters'};
  $dbh->disconnect();
}


# Method: filter($parameter,$value);
# ----------------------------------
# Sanitizes a value based on the rules for the inputted parameter for the current contxt.
# Calls __filter($parameter,$value);
#
sub filter {
  my ($self,$parameter,$value) = @_;
  $self->{'caller'} = join(':',caller() . ' : filter()');
  if ($self->{'debug'} == 1) {
    $self->__logWrite();
  }
  return $self->__filter($parameter,$value);
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

  if ($self->{'debug'} == 1) {
    $self->__log('Filtering \'' . $parameter . '\' with :');
  }

  # if it is a multiple parameter (i.e. item1, item2, etc.) strip out the number and compare against the base parameter type
  if ($self->__isMultiple($parameter)) {
    $parameter = $self->__multipleBase($parameter);
  }

  my $origvalue = $value;
    
  my $filterExists = 0;
  if ($self->__validateParameter($parameter,'filter')) { 
    $filterExists = 1;
    my $regex = $self->__getRegexForParameterForMode($parameter,'filter');
    if ($self->{'debug'} == 1) { $self->__log('  F: /' . $regex . '/'); }
    $value =~ s/$regex//g;
  }

  my $sieveExists = 0;
  if ($self->__validateParameter($parameter,'sieve')) { 
    $sieveExists = 1;
    my $regex = $self->__getRegexForParameterForMode($parameter,'sieve');
    if ($self->{'debug'} == 1) { $self->__log('  S: /' . $regex . '/'); }
    $value =~ s/$regex//g;
  }

  if ($self->{'debug'} == 1 && $origvalue ne $value) { 
    $self->__log('  Translating: \'' . $origvalue . '\' to \'' . $value . '\''); 
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
    $hash{$key} = $self->__filter($key,$hash{$key});
  }
  if ($self->{'debug'} == 1) {
    $self->__logWrite();
  }
  return %hash;
}

# Method: unknownParameters();
# ----------------------------
# Returns a list of parameters that were passed in that are unknown for the current context
#
sub unknownParameters {
  my ($self,%hash) = @_;
  $self->{'caller'} = join(':',caller() . ' : unknownFields()');
  my @unknownFields;
  foreach my $key (keys %hash) {
    # check to see if it's a multiple paramater, such as item1, item2, etc.
    if ($self->__isMultiple($key)) {
      $key = $self->__multipleBase($key);
    }
    if (!$self->__validateParameter($key)) {
      push @unknownFields,$key;
    }
  }
  if ($self->{'debug'} == 1) {
    $self->__logWrite();
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
  if ($self->{'debug'} == 1) {
    $self->__logWrite();
  }
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
print 'regex is ' . $regex . "\n";
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
  if ($self->{'debug'} == 1) {
    $self->__logWrite();
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
    $self->{'caller'} .= ' -> ' . join(':',caller()) . ' : isOfType()';
  } else {
    $self->{'caller'} = join(':',caller()) . ' : isOfType()';
  }

  $parameter =~ s/-/_/g;
  my $premode = $mode;
  $mode =~ s/[^a-z]//g;
  if ($mode ne $premode) {
    die('Invalid mode passed to __validateParameter()');
  }
    
  if (exists($self->{'parameters'}{$parameter})) {
    if (defined $mode && $mode !~ /^validate$/) {
      if (exists($self->{'parameters'}{$parameter}{$mode})) {
        return 1;
      } else {
        return 0;
      }
    } 
    return 1;
  } else {
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

  if ($self->__validateParameter($self->__multipleBase($parameter))) {
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

sub __addCharacterSet{
  my ($self,$characterSetName,$characterSet) = @_;
  $self->{'characterSets'}{$characterSetName} = $characterSet;
}

sub __addParameterType {
  my ($self,$type,$regex) = @_;
  $self->{'parameterTypes'}{$type} = $regex;
}

sub __getRegexForParameterForMode {
  my ($self,$parameter,$mode) = @_;
  if (!exists($self->{'parameters'}{$parameter}{$mode})) { 
    return ''; 
  }
  my $regex = '';
  foreach my $characterSetName (@{$self->{'parameters'}{$parameter}{$mode}}) {
    #if ($self->{'debug'} == 1) {
    #  $self->__log('building regex with : \'' . $characterSetName . '\' (' . $self->{'characterSets'}{$characterSetName} . ')');
    #}

    $regex .= $self->{'characterSets'}{$characterSetName};
  }
  my $not = '';
  if ($mode =~ /^sieve$/) {
    $not = '^';
  }
  $regex = '[' . $not . $regex . ']+';
  return $regex;
}

sub __openLog {
  my ($self) = @_;
  if ($self->{'INPUTVALIDATORLOG'}) { return 1; }
  if (!exists $self->{'context'}) {
    open($self->{'INPUTVALIDATORLOG'},'>>' . $self->{'logDirectory'} . '/' . $self->__date() . '.InputValidator.Context.log');
  } else {
    open($self->{'INPUTVALIDATORLOG'},'>>' . $self->{'logDirectory'} . '/' . $self->__date() . '.' . $self->{'context'} . '.Context.log');
  }
}

sub __closeLog {
  my ($self) = @_;
  if ($self->{'INPUTVALIDATORLOG'}) { 
    close($self->{'INPUTVALIDATORLOG'});
  }
}

sub __log {
  my ($self,$message) = @_;
  chomp $message;
  $self->{'logbuffer'} .= $self->__timestamp() . ' : PID ' . $$ . ' : ' .  $message . "\n";
}

sub __logWrite {
  my ($self) = @_;
  $self->__openLog();
  my $filehandle = $self->{'INPUTVALIDATORLOG'};
  print $filehandle $self->{'logbuffer'};
  $self->{'logbuffer'} = '';
}

sub __timestamp {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year += 1900;
  $mon += 1;
  return sprintf "%4d-%02d-%02d %02d:%02d:%02d", $year,$mon,$mday,$hour,$min,$sec;
}

sub __date {
  my ($self) = @_;
  my $date = $self->__timestamp();
  $date =~ s/\s+.*//;
  return $date;
}

1;

