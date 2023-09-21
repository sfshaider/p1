package PlugNPay::API::REST::Format;

use strict;
use PlugNPay::DBConnection;
use JSON::XS qw(encode_json decode_json);
use XML::Simple qw(:strict);
use PlugNPay::Util::Clone;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::StackTrace;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setData {
  my $self = shift;
  my $dataRef = shift;
  $self->{'data'} = $dataRef;
  return $self;
}

sub getData {
  my $self = shift;
  return $self->{'data'};
}

sub setSettings {
  my $self = shift;
  my $settings = shift;
  $self->{'settings'} = $settings;
}

sub getSettings {
  my $self = shift;
  return $self->{'settings'} || {};
}

sub setJSON {
  my $self = shift;
  my $jsonString = shift;

  my $dataRef;

  eval {
    $dataRef = decode_json($jsonString);
  };

  if ($@) {
    $self->setError('Invalid JSON Format.');
  }

  if ($dataRef) {
    $self->{'data'} = $dataRef;
  }

  return $self;
}

sub setXML {
  my $self = shift;
  my $xmlString = shift;

  my $dataRef;

  eval {
    my $xmlParser = new XML::Simple(RootName => 'data', KeyAttr => {},ForceArray => 0, XMLDecl => 1, NoAttr => 1, ForceArray => qr/_list$/);
    $dataRef = $xmlParser->XMLin($xmlString);
  };

  if ($@) {
    $self->setError('Invalid XML Format.');
  }

  if ($dataRef) {
    $self->{'data'} = $dataRef;
  }

  return $self;
}

sub getJSON {
  my $self = shift;

  return encode_json($self->{'data'});
}

sub getXML {
  my $self = shift;
  my $options = shift;

  my $xmlBuilder;

  if ($options->{'pretty'} ne 1) {
    $xmlBuilder = XML::Simple->new(RootName => 'data', XMLDecl => 1, NoAttr => 1, ForceArray => qr/_list$/, NoIndent => 1);
  } else {
    $xmlBuilder = XML::Simple->new(RootName => 'data', XMLDecl => 1, NoAttr => 1, ForceArray => qr/_list$/);
  }


  return $xmlBuilder->XMLout($self->{'data'}, KeyAttr => {});
}

sub setSchemaName {
  my $self = shift;
  my $schemaName = shift;
  $self->{'schemaName'} = $schemaName;
}

sub getSchemaName {
  my $self = shift;
  return $self->{'schemaName'};
}

sub setSchema {
  my $self = shift;
  my $schema = shift;
  $self->{'schema'} = $schema;
}

sub getSchema {
  my $self = shift;
  if (!$self->{'schema'}) {
    $self->loadSchema();
  }
  return $self->{'schema'};
}

sub setSchemaMode {
  my $self = shift;
  my $mode = shift;
  $self->{'schemaMode'} = $mode;
}

sub getSchemaMode {
  my $self = shift;
  return $self->{'schemaMode'};
}

sub loadSchema {
  my $self = shift;
  my $schemaName = $self->getSchemaName();
  my $schemaMode = $self->getSchemaMode();

  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
    SELECT `schema` FROM api_schema WHERE schema_name = ? and mode = ?
  /);

  $sth->execute($schemaName,$schemaMode);

  my $results = $sth->fetchall_arrayref({});

  if ($results && $results->[0]) {
    my $rawSchema = $results->[0]{'schema'};
    my $schema;
    eval {
      $schema = decode_json($rawSchema);
    };
    if ($schema) {
      $self->setSchemaName($schemaName);
      $self->setSchema($schema);
    }
  } else {
    die('Invalid schema: ' . $schemaName);
  }
}

sub validateData {
  my $self = shift;
  my $originalData = shift || $self->getData();
  my $schema = shift || $self->getSchema();
  my $settings = shift || $self->getSettings();
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'responder'});
  my $cloner = new PlugNPay::Util::Clone();
  my $data = $cloner->deepClone($originalData,{maxDepth => 40});

  my $status = $self->validateDataRecursive($data,$schema,'','root',$data,$settings);
  if (!$status) {
    my $logs = $self->getLogs();
    $self->setError('Data validation error: ' . join('\|',map { $_ . ' : ' . join(';',@{$logs->{$_}}) } keys %{$logs}));
  }

  if (!$status) {
    $logger->log({'requestUsername' => $settings->{'username'},
                  'schemaEnforced'  => $settings->{'enforced'},
                  'isValid'         => $status,
                  'uri'             => $settings->{'uri'},
                  'schemaName'      => $self->getSchemaName(),
                  'schemaMode'      => $self->getSchemaMode(),
                  'responder'       => $settings->{'responderName'}
                 });
  }

  return $status;
}

sub validateDataRecursive {
  my $self = shift;
  my $data   = shift;
  my $schema = shift;
  my $lastKey = shift;
  my $keyPath = shift || '';
  my $parent = shift;
  my $settings = shift;

  my $parentKeyPath = $keyPath;

  my $status = 1;

  if (ref $schema eq 'HASH') {
    if (defined $schema->{'__optional'} && $schema->{'__optional'} eq 'true') {
      if (!defined $data) {
        return 1;
      }
    }

    foreach my $key (keys %{$schema}) {
      $keyPath = $parentKeyPath . ':' . $key unless substr($key,0,2) eq '__';

      if ($key eq '__typedef') {
        # validate data
        my $typeDef = $schema->{$key};
        my $value = $data;

        # error if we expected a value and it was a data structure (hash or array)
        if (ref $value) {
          $self->log($keyPath . ' : Unexpected ' . ref($value) . ' found at key: ' . $key . '  ' . encode_json($data),'error');
          return 0;
        }

        my $maskedValue = $value;
        if ($typeDef->{'isSensitive'} eq 'yes' && defined $value) {
          $maskedValue =~ s/./\*/g;
          $parent->{$lastKey} = $maskedValue;
        }

        # get the definition for the value
        my $type = (ref($typeDef->{'type'}) eq "SCALAR" ? ${$typeDef->{'type'}} : $typeDef->{'type'});
        # TODO: code validation for the following types: Integer, Decimal, String

        # error if value is undefined and required if a sibling has a certain value
        if (!defined $value || $value eq '') {
          if (defined $typeDef->{'requiredIf'} || defined $typeDef->{'requiredIfNot'}) {
            if (ref($typeDef->{'requiredIf'}) eq 'ARRAY') {
              #loop through possible sibling keys to find values that make this value required
              foreach my $keyValuePair (@{$typeDef->{'requiredIf'}}) {
                if (ref($keyValuePair) eq 'HASH') {
                  my $siblingKey = $keyValuePair->{'key'};
                  my $siblingValue = $keyValuePair->{'value'};
                  # if the siblings value matches then return false
                  if ($parent->{$siblingKey} eq $siblingValue) {
                    $self->log($keyPath . ' : Required key/value missing when [' . $siblingKey . '] is [' . $siblingValue . ']','error');
                    return 0;
                  }
                }
              }
            }

            if (ref($typeDef->{'requiredIfNot'}) eq 'ARRAY') {
              #loop through possible sibling keys to find values that make this value required
              my $isOneOfEm = 0;
              my $matchKey;
              my $matchValue;
              foreach my $keyValuePair (@{$typeDef->{'requiredIfNot'}}) {
                if (ref($keyValuePair) eq 'HASH') {
                  my $siblingKey = $keyValuePair->{'key'};
                  my $siblingValue = $keyValuePair->{'value'};
                  if ($parent->{$siblingKey} eq $siblingValue) {
                    $matchKey = $siblingKey;
                    $matchValue = $siblingValue;
                    $isOneOfEm ||= ($parent->{$siblingKey} eq $siblingValue);
                    last if $isOneOfEm;
                  }
                }
              }

              if (!$isOneOfEm) { # in other words, one of them was found
                $self->log($keyPath . ' : Required key/value missing when [' . $matchKey . '] is [' . $matchValue . ']','error');
                return 0;
              }
            }
          } elsif ($typeDef->{'optional'} ne 'true' || (ref($settings) eq 'HASH' && $settings->{'everythingOptional'})) {
            # error if value is undefined and not optional, or if everything should be treated as optional (i.e. updating)
            $self->log($keyPath . ' : Required key/value missing.','error');
            return 0;
          }
        } elsif (defined $value) { # value is defined, validate the value
          # check if values are limited to a specific set of inputs
          if (defined $typeDef->{'possibleValues'}) {
            # TODO
            my $matchFound = 0;
            if (ref $typeDef->{'possibleValues'} eq 'ARRAY') {
              foreach my $possibleValue (@{$typeDef->{'possibleValues'}}) {
                if ($possibleValue eq $value) {
                  $matchFound = 1;
                }
              }
            }
            if (!$matchFound) {
              $self->log($keyPath . ' : Invalid value: [' . $value . ']','error');
            }
          }

          # check regex
          if (defined $typeDef->{'regex'}) {
            my $regex = $typeDef->{'regex'};
            if ($value !~ /$regex/) {
              $self->log($keyPath . ' : Value of key does not match the correct format: ' . $typeDef->{'regex'},'error');
              return 0;
            }
          }

          # check max length
          if ($typeDef->{'maxLength'}) {
            if (length($value) > $typeDef->{'maxLength'}) {
              $self->log($keyPath . ' : Value of key exceeds max length: ' . $typeDef->{'maxLength'},'error');
              return 0;
            }
          }

          if ($typeDef->{'minLength'}) {
            if (length($value) < $typeDef->{'minLength'}) {
              $self->log($keyPath . ' : Value of key does not meet minimum length: ' . $typeDef->{'minLength'} . ', actual: ' . $maskedValue . ':' . length($value),'error');
              return 0;
            }
          }


          if ($type eq 'Boolean') {
            if (!($value eq 'true' || $value eq 'false') && !($value != 0 || $value != 1)) {
              $self->log($keyPath . ' : Non-boolean value found: ' . $maskedValue,'error');
              return 0;
            }
          }

          if (defined $typeDef->{'options'}) {
            if (ref($typeDef->{'options'}) eq 'ARRAY') {
              my $exists = 0;
              if ($type eq 'Integer') {
                $exists = grep($_ == $value, @{$typeDef->{'options'}});
              } else {
                $exists = grep($_ eq $value, @{$typeDef->{'options'}});
              }

              unless($exists) {
                $self->log($keyPath . ' : Invalid value found: ' . $maskedValue,'error');
                return 0;
              }
            } elsif (ref($typeDef->{'options'}) eq 'HASH') {
              my $options = $typeDef->{'options'};
              if (!defined $options->{lc($value)}){
                $self->log($keyPath . ' : Invalid value found: ' . $maskedValue,'error');
                return 0;
              } elsif ($options->{lc($value)} eq 'deprecated') {
                $self->log($keyPath . ' : Deprecated value found: ' . $maskedValue,'warning');
                $self->addWarning($keyPath . ' : Deprecated value found: ' . $maskedValue);
                return 1;
              }
            }
          }
        }
      } elsif (substr($key,0,2) ne '__') {
        # Tab? I can't give you a tab unless you order something.
        $status &= $self->validateDataRecursive($data->{$key},$schema->{$key},$key,$keyPath,$data);
      }
    }
  # if the value is an array, loop through the array elements and validate them.
  } elsif (ref $schema eq 'ARRAY') {
    my $optional = ($schema->[0]{'__optional'} eq 'true') || 0;
    if (ref $data eq undef && $optional) {
      return 1;
    } elsif (ref $data eq 'ARRAY') {
      my $index = 0;
      my $minCount = $schema->[0]{'__min_count'} || 1;
      if (@{$data} < $minCount) {
        $self->log($keyPath . ' : ARRAY requires at least '. $minCount . ' elements.','error');
      }
      foreach my $item (@{$data}) {
        # You want a Pepsi, pal, you're gonna pay for it.
        $status &= $self->validateDataRecursive($item,$schema->[0],$lastKey,$keyPath . '['.$index.']', $data);
        $index++;
      }
    # error if array was expected but not found
    } else {
      $self->log($keyPath . ' : Expected ARRAY','error');
      return 0;
    }
  }

  return $status;
}

sub clearLog {
  my $self = shift;
  $self->{'logs'} = {
    mode => $self->getSchemaMode(),
    warning => {},
    error => {}
  };
}

sub setError {
  my $self = shift;
  my $error = shift;
  $self->{'error'} = $error;
}

sub getError {
  my $self = shift;
  return $self->{'error'};
}

sub hasError {
  my $self = shift;
  return (defined $self->{'error'});
}

sub log {
  my $self = shift;
  my $message = shift;
  my $type = shift || 'error';
  my $keypath = shift || '';

  if (!defined $self->{'logs'}) {
    $self->clearLog();
  }

  if (!defined $self->{'logs'}{$type}{$keypath}) {
    $self->{'logs'}{$type}{$keypath} = [];
  }

  push @{$self->{'logs'}{$type}{$keypath}},$message;
}

sub getLogs {
  my $self = shift;
  my $type = shift || 'error';
  if (!defined $self->{'logs'}) {
    $self->clearLog();
  }
  return $self->{'logs'}{$type} || {};
}

sub addWarning {
  my $self = shift;
  my $warning = shift;
  if (defined $self->{'warning'} && ref($self->{'warning'}) eq 'ARRAY') {
    push @{$self->{'warning'}},$warning;
  } else {
    my @warnings = ($warning);
    $self->{'warning'} = \@warnings;
  }
}

sub clearWarnings {
  my $self = shift;
  $self->setWarnings(undef);
}

sub setWarnings {
  my $self = shift;
  my $warning = shift;
  $self->{'warning'} = $warning;
}

sub getWarnings {
  my $self = shift;
  return $self->{'warning'};
}


1;
