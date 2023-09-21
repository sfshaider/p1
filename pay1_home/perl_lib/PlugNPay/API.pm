package PlugNPay::API;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::InputValidator;


our $_parameterData;

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $context = shift;
  my $parametersRef = shift;

  if (defined $context) {
    $self->setContext($context);
  }

  if (defined $parametersRef) {
    $self->setParameters($parametersRef);
  } else {
    my %query = PlugNPay::InputValidator::filteredQuery($context);
    $self->setParameters(\%query);
  }

  if (!defined $_parameterData) {
    $self->_loadSettingsFromDatabase();
  }

  return $self;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->parameter('pt_gateway_account');
}

sub setContext {
  my $self = shift;
  my $context = lc shift;
  $context =~ s/[^a-z0-9_]//g;
  $self->{'current_context'} = $context;
}


sub setParameters {
  my $self = shift;
  my $parameterHashRef = shift;

  if (ref $parameterHashRef ne 'HASH') {
    return;
  }

  foreach my $key (keys %{$parameterHashRef}) {
    if (!defined $parameterHashRef->{$key} || $parameterHashRef->{$key} eq '') {
      delete $parameterHashRef->{$key};
    }
  }

  $self->{'data'} = $parameterHashRef;
}

sub clearParameters {
  my $self = shift;
  delete $self->{'data'};
}

sub setLegacyParameters {
  my $self = shift;
  my $legacyParameterHashRef = shift;

  if (defined $legacyParameterHashRef) {
    $self->{'data'} = $self->convertLegacyParameters($legacyParameterHashRef);
  }
}

sub _loadSettingsFromDatabase {
  my %parameterData;

  #######################
  # Load the parameters #
  #######################

  my $dbh = PlugNPay::DBConnection::database('pnpmisc');
  my $sth = $dbh->prepare(q{
    SELECT parameter, legacy_parameter, legacy_preserve_underscores, multiple, parameter_category
    FROM api_parameter
    WHERE enabled = 1
  });
  $sth->execute();

  my $arrayRef = $sth->fetchall_arrayref({});
  $sth->finish();

  foreach my $row (@{$arrayRef}) {
    my $name = $row->{'parameter'};

    $parameterData{'parameters'}{$name}{'legacy_name'} = $row->{'legacy_parameter'};
    $parameterData{'parameters'}{$name}{'multiple'} = $row->{'multiple'};

    # save wether the legacy parameter should be converted to underscores or not.  we save the legacy parameter name so we don't have to do multiple hash lookups.
    $parameterData{'legacyInfo'}{$row->{'legacy_parameter'}}{'legacy_preserve_underscores'} = $row->{'legacy_preserve_underscores'};

    push @{$parameterData{'parameter_categories'}{lc $row->{'parameter_category'}}}, $name;
  }

  ##############################
  # Load the multiple mappings #
  ##############################
  #!# NOTE: Multiple maps are not reversible #!#

  $sth = $dbh->prepare(q{
    SELECT parameter, legacy_parameter
    FROM api_parameter_multiple_map
    WHERE enabled = 1
  });
  $sth->execute();
  $arrayRef = $sth->fetchall_arrayref({});

  foreach my $row (@{$arrayRef}) {
    my $name = $row->{'parameter'};
    push @{$parameterData{'parameter_multiple_mappings'}{$name}},$row->{'legacy_parameter'};
  }

  ############################################
  # Load the legacy parameter value mappings #
  ############################################

  $sth = $dbh->prepare(q{
    SELECT parameter, value, legacy_value
    FROM api_parameter_legacy_value_map
    WHERE enabled = '1'
  });
  $sth->execute();

  $arrayRef = $sth->fetchall_arrayref({});

  foreach my $row (@{$arrayRef}) {
    my $parameter = $row->{'parameter'};
    $parameterData{'legacy_value_mappings'}{$parameter}{$row->{'value'}} = $row->{'legacy_value'};
  }

  #########################
  # Load transflag Fields #
  #########################

  $sth = $dbh->prepare(q{
    SELECT parameter
    FROM api_parameter_transflags
  });
  $sth->execute();

  my @transflagParameters;
  $arrayRef = $sth->fetchall_arrayref({});
  foreach my $row (@{$arrayRef}) {
    push @transflagParameters,$row->{'parameter'};
  }

  $parameterData{'transflag_parameters'} = \@transflagParameters;

  ###############################
  # Load the parameter contexts #
  ###############################

  $sth = $dbh->prepare(q{
    SELECT parameter, context, deprecated
    FROM api_parameter_context
  });
  $sth->execute();

  $arrayRef = $sth->fetchall_arrayref({});

  foreach my $row (@{$arrayRef}) {
    push(@{$parameterData{'parameter_contexts'}{$row->{'context'}}}, $row->{'parameter'});
  }

  ############################################
  # Generate reverse mappings for parameters #
  ############################################
  foreach my $parameter (keys %{$parameterData{'parameters'}}) {
    my $legacyParameter = $parameterData{'parameters'}{$parameter}{'legacy_name'};
    $parameterData{'reverse_parameter_mappings'}{$legacyParameter} = $parameter;
  }

  ##################################################
  # Generate reverse mappings for parameter values #
  ##################################################
  foreach my $parameter (keys %{$parameterData{'legacy_value_mappings'}}) {
    foreach my $value (keys %{$parameterData{'legacy_value_mappings'}{$parameter}}) {
      $parameterData{'reverse_value_mappings'}{$parameter}{$parameterData{'legacy_value_mappings'}{$parameter}{$value}} = $value;
    }
  }

  #########################
  # Store the loaded data #
  #########################

  $_parameterData = \%parameterData;
}

sub parameters {
  my $self = shift;

  if (!defined $self->{'filteredParameters'}) {
    $self->{'filteredParameters'} = $self->_parameters();
  }

  return $self->{'filteredParameters'};
}

sub _parameters {
  my $self = shift;

  my $currentContext = $self->{'current_context'};

  my %contextParameters = map { $_ => 1 } $self->_contextParameters($currentContext);

  my %parameters;
  foreach my $parameter (keys %{$self->{'data'}}) {
    my $singleParameter = $parameter;
    $singleParameter =~ s/\d+$//;
    if (exists $contextParameters{$parameter} || exists $contextParameters{$singleParameter}) {
      $parameters{$parameter} = $self->{'data'}{$parameter};
    }
  }

  return \%parameters;
}

sub getTransflagParameterNames {
  my $self = shift;
  if (exists $_parameterData->{'transflag_parameters'}) {
    return @{$_parameterData->{'transflag_parameters'}};
  }
  return ();
}

sub allParameters {
  my $self = shift;
  my @contextParameters = $self->_contextParameters($self->{'current_context'});
  return @contextParameters;
}

sub _customFieldNames {
  my $self = shift;
  return grep {/^pt_custom_(name|value)_\d+$/} keys %{$self->{'data'}};
}

sub getCustomFields {
  my $self = shift;
  return $self->getCustomParameters();
}

sub getCustomParameters {
  my $self = shift;
  my @customParameters = $self->_customFieldNames();

  my %customParametersHash = map { $_ => $self->{'data'}{$_} } @customParameters;
  return \%customParametersHash;
}

sub _itemFieldNames {
  my $self = shift;
  return grep {/^pt_item_/} keys %{$self->{'data'}};
}

sub getItemFields {
  my $self = shift;
  return $self->getItemParameters();
}

sub getItemParameters {
  my $self = shift;
  my @itemParameters = $self->_itemFieldNames();

  my %itemParametersHash = map { $_ => $self->{'data'}{$_} } @itemParameters;
  return \%itemParametersHash;
}

sub parametersForCategory {
  my $self = shift;
  my $category = lc shift;

  my %categoryParameters;
  if (exists $_parameterData->{'parameter_categories'}{$category}) {
    my %in_context = map { $_ => 1 } $self->_contextParameters($self->{'current_context'});
    my %in_category = map { $_ => 1 } @{$_parameterData->{'parameter_categories'}{$category}};
    foreach my $parameter (keys %{$self->{'data'}}) {
      my $singleParameter = $parameter;
      $singleParameter =~ s/\d+$//;
      if ((exists $in_context{$parameter}  || exists $in_context{$singleParameter}) &&
          (exists $in_category{$parameter} || exists $in_category{$singleParameter})) {
        $categoryParameters{$parameter} = $self->{'data'}{$parameter};
      }
    }
  }

  return \%categoryParameters;
}

sub _contextParameters {
  my $self = shift;
  my $context = lc shift;

  my @contextParameters;
  if (exists $_parameterData->{'parameter_contexts'}{$context}) {
    @contextParameters = @{$_parameterData->{'parameter_contexts'}{$context}};
  }

  return @contextParameters;
}



sub parameter {
  my $self = shift;
  my $parameter = shift;
  $parameter =~ s/[^a-z0-9_]//;
  return $self->{'data'}{$parameter};
}

sub transactionFlags {
  my $self = shift;
  my @transflagParameterNames = $self->getTransflagParameterNames();

  my @transflags;
  foreach my $parameter (@transflagParameterNames) {
    if ($self->parameter($parameter) ne '') {
      push @transflags,$self->_getLegacyValue($parameter,$self->parameter($parameter));
    }
  }

  return join(',',@transflags);
}


sub getLegacyHyphenated {
  my $self = shift;

  # get the results from _getLegacy()
  my $data = $self->_getLegacy();

  # go through all of the parameters and convert underscores to hyphens
  foreach my $parameter (keys %{$data}) {
    my $convertedParameter = $parameter;

    # check to see if we keep the underscores as is for the legacy parameter
    if (!$_parameterData->{'legacyInfo'}{$parameter}{'legacy_preserve_underscores'}) {
      $convertedParameter =~ s/_/\-/g;
    }


    if ($convertedParameter ne $parameter) {
      $data->{$convertedParameter} = $data->{$parameter};
      delete $data->{$parameter};
    }
  }

  return $data;
}


sub getLegacyUnderscored {
  my $self = shift;

  # this just returns the raw results from _getLegacy()
  my $data = $self->_getLegacy() ;
  $data->{'convert'} = 'underscores';

  return $data;
}

sub _getLegacy {
  my $self = shift;

  my $currentContext = $self->{'current_context'};

  my %contextParameters = map { $_ => 1 } $self->_contextParameters($currentContext);
  my %data;
  foreach my $parameter (keys %{$self->{'data'}}) {
    my $singleParameter = $parameter;
    $singleParameter =~ s/(\d*)$//;
    my $number = $1;

    my $value = $self->_getLegacyValue($parameter,$self->{'data'}{$parameter});
    if (exists $contextParameters{$parameter}) {
      my $legacyName = $_parameterData->{'parameters'}{$parameter}{'legacy_name'};
      $data{$legacyName} = $value;
    }
    elsif (exists $contextParameters{$singleParameter}) {
      my $legacyName = $_parameterData->{'parameters'}{$singleParameter}{'legacy_name'} . $number;
      $data{$legacyName} = $value;
    }
  }

  # do multiple mappings
  foreach my $parameter (keys %{$self->{'data'}}) {
    if (exists $_parameterData->{'parameter_multiple_mappings'}{$parameter}) {
      my $value = $self->_getLegacyValue($parameter,$self->{'data'}{$parameter});
      foreach my $mapping (@{$_parameterData->{'parameter_multiple_mappings'}{$parameter}}) {
        if (!exists $data{$mapping}) {
          $data{$mapping} = $value;
        }
      }
    }
  }

  # get transflags
  $data{'transflags'} = $self->transactionFlags();

  return \%data;
}

sub _getLegacyValue {
  my $self = shift;
  my $parameter = shift;
  my $value = shift;

  my $singleParameter = $parameter;
  $singleParameter =~ s/\d+$//;

  if (exists $_parameterData->{'legacy_value_mappings'}{$parameter}) {
    $value = $_parameterData->{'legacy_value_mappings'}{$parameter}{$value};
  }
  elsif (exists $_parameterData->{'legacy_value_mappings'}{$singleParameter}) {
    $value = $_parameterData->{'legacy_value_mappings'}{$singleParameter}{$value};
  }
  return $value;
}

sub deMultipleParameter {
  my $self = shift;
  my $parameter = shift;

  if (!exists $self->{'parameters'}{$parameter}) {
    $parameter =~ s/\d+$//;
    if (exists $self->{'parameters'}{$parameter}) {
      return $parameter;
    }
  }
  return $parameter;
}

sub convertLegacyParameters {
  my $self = shift;
  my $inputHashRef = shift;

  my %output;

  $inputHashRef = $self->fixLegacyAmount($inputHashRef);

  foreach my $legacyParameter (keys %{$inputHashRef}) {
    # convert hyphens to underscores for conversion
    my $legacyParameterUnderscored = $legacyParameter;
    $legacyParameterUnderscored =~ s/-/_/g;

    # get the single parameter
    my $singleLegacyParameterUnderscored = $legacyParameterUnderscored;
    $singleLegacyParameterUnderscored =~ s/(\d+)$//;
    my $x = $1 || '';

    my $parameter;

    my $isMultiple = 0;

    if (exists $_parameterData->{'reverse_parameter_mappings'}{$legacyParameterUnderscored}) {
      $parameter = $_parameterData->{'reverse_parameter_mappings'}{$legacyParameterUnderscored};
      # append number to parameter (appends empty string if there was no number
    } elsif (exists $_parameterData->{'reverse_parameter_mappings'}{$singleLegacyParameterUnderscored}) {
      $parameter = $_parameterData->{'reverse_parameter_mappings'}{$singleLegacyParameterUnderscored};
      $isMultiple = 1;
    } else {
      next;
    }

    my $legacyValue = $inputHashRef->{$legacyParameter};
    my $value = $legacyValue;

    if (defined $_parameterData->{'reverse_value_mappings'}{$parameter}) {
      $value = $_parameterData->{'reverse_value_mappings'}{$parameter}{$legacyValue};
    }

    if ($isMultiple) {
      $parameter .= $x;
    }

    $output{$parameter} = $value;
  }

  return \%output;
}

sub fixLegacyAmount {
  my $self = shift;
  my $inputHashRef = shift;

  # make a copy of the input so we don't have any side effects
  my %inputHashRefCopy = %{$inputHashRef};
  $inputHashRef = \%inputHashRefCopy;

  if (defined $inputHashRef->{'amount'}) {
    ($inputHashRef->{'currency'},$inputHashRef->{'card_amount'}) = split(' ',$inputHashRef->{'amount'});
  }

  return $inputHashRef;
}


1;
