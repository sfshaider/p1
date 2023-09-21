package PlugNPay::API::REST::Documentation::JSON;

use strict;

use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $path = shift; 
  if(defined $path) { 
    $self->setResourcePath($path);
  } 

  return $self;
}

sub getSchemaSpecs {
  my $self = shift;
  my $schema = shift;
  my $lastKey = shift;
  my $opacity = shift || 0.1;
  my $skipOptional = shift;
  my $spec = '';
  $opacity = ($opacity <= 1.0 ? $opacity : 1.0);
  my $style = 'background-color:rgba(192,192,192,' . $opacity . '); display:inline-block; padding:10px; margin:2px;';

  my $status = 1;
  if (ref $schema eq 'HASH') {
    if (!$skipOptional && defined $schema->{'__optional'} && $schema->{'__optional'} eq 'true') {
      $spec .= '<div class="max">Optional Section</div>';
    }
    foreach my $key (keys %{$schema}) {
      my $close = '';
      my $currentElement = $schema->{$key};
      my $typeDefKey = '__typedef';
      $style .= ($opacity > 0.10 ? ' width:99%;' : '');

      if ((ref $schema->{$key} eq 'HASH') && !defined $currentElement->{$typeDefKey} )  {
        $spec .='<br><span style="' . $style . '"><div class="elementName">' . $key . ": \{</div>" unless substr($key,0,2) eq '__';
        $close = "\}";
      } elsif (ref $schema->{$key} eq 'ARRAY') {
        $close = "\]";
        $spec .='<br><span style="' . $style . '"><div class="elementName">' . $key . ": \[</div>" unless substr($key,0,2) eq '__';
      } else {
        $spec .= '<br><span style="' . $style . '"><div class="elementName">' . $key . ":</div>" unless substr($key,0,2) eq '__';
      }
  
      my $optional = ($skipOptional ? 1 : 0);
      if ($key eq '__typedef') {
        my $typeDef = $schema->{$key};
        $spec .= '<div class="type">Type: ' . $typeDef->{'type'} . '</div>' . '';
  
        if (defined $typeDef->{'options'}) {
          my $values = '';
          if (ref($typeDef->{'options'}) eq 'ARRAY') {
            foreach my $opt (@{$typeDef->{'options'}}) {
              $values .= ' ' . $opt . ',';
            }
          } elsif (ref($typeDef->{'options'}) eq 'HASH') {
            foreach my $optKey (keys %{$typeDef->{'options'}}) {
              my $optHash = $typeDef->{'options'};
              if ($optHash->{$optKey} eq 'deprecated') {
                $values .= ' <deprecated title="This value has been deprecated">' . $optKey . '</deprecated>,';
              } else {
                $values .= ' ' . $optKey . ',';
              }
            }
          }
          chop($values);
          $spec .= '<div class="other">Values:' . $values . "</div>";
        }

        if ($typeDef->{'requiredIf'}) {
          my %keys;
          if (ref($typeDef->{'requiredIf'}) eq 'ARRAY') {
            foreach my $keyValuePair (@{$typeDef->{'requiredIf'}}) {
              push @{$keys{$keyValuePair->{'key'}}},$keyValuePair->{'value'};
            }
          }
          foreach my $key (keys %keys) {
            my $values = join(', ',@{$keys{$key}});
            $spec .= '<div class="other">Required if ' . $key . ' is: ' . $values . "</div>";
          }
        }

        if ($typeDef->{'requiredIfNot'}) {
          my %keys;
          if (ref($typeDef->{'requiredIfNot'}) eq 'ARRAY') {
            foreach my $keyValuePair (@{$typeDef->{'requiredIfNot'}}) {
              push @{$keys{$keyValuePair->{'key'}}},$keyValuePair->{'value'};
            }
          }
          foreach my $key (keys %keys) {
            my $values = join(', ',@{$keys{$key}});
            $spec .= '<div class="other">Required if ' . $key . ' is not: ' . $values . "</div>";
          }
        }

        if ($typeDef->{'isSensitive'} eq 'yes') {
          $spec .= '<div class="sensitive">Sensitive information</div>';
        }

        if ( defined $typeDef->{'optional'} && $typeDef->{'optional'} eq 'true') {
          $optional = 1;
        }

        if (defined $typeDef->{'regex'}) {
          $spec .= '<div class="max">Format (regex): /' . $typeDef->{'regex'} . '/</div>';
        }

        if (defined $typeDef->{'maxLength'}) {
          $spec .= '<div class="max">Maximum length: ' . $typeDef->{'maxLength'} . '</div>';
        }

        if (defined $typeDef->{'minLength'}) {
          $spec .= '<div class="min">Minimum length: ' . $typeDef->{'minLength'} . '</div>';
        }
        if (defined $typeDef->{'min'}) {
          $spec .= "<div class=\"min\">Minimum value: " . $typeDef->{'min'} . '</div>';
        }

        if (defined $typeDef->{'max'}) {
          $spec .= "<div class=\"max\">Maximum value: " . $typeDef->{'max'} . '</div>';
        }
      
        unless($optional) {
          $spec .= "<div class=\"optional\">Required</div>";
        }
      } elsif (substr($key,0,2) ne '__') {
        $spec .= '<div style class="paddingWrap">' . $self->getSchemaSpecs($schema->{$key},$key,$opacity + 0.05) . "</div><div>" . $close . "</div></span>";
      }
    }
  # if the value is an array, loop through the array elements and validate them.
  } elsif (ref $schema eq 'ARRAY') {
      $spec .= '<div class="type">Type: Array </div>';

      my $index = 0;
      $spec .= '<div class="min">Minimum array size: ' .  ($schema->[0]{'__min_count'} || 0) . '</div>';
      if (defined $schema->[0]{'__optional'} && $schema->[0]{'__optional'} eq 'true') {
        $spec .= '<div class="max">Optional</div>';
      }
      $spec .= "<div class=\"arrayElements\">Elements: </div>";
      $style .= ($opacity > 0.10 ? ' width:95%;' : '');
      $spec .= "<span style=\"" . $style . "\">";
      #foreach my $item (@{$schema}) {
      $spec .= '  <div class="paddingWrap">' . $self->getSchemaSpecs($schema->[0],$lastKey,$opacity ,'skip-optional') . '</div>';
      #}
      $spec .= '</span>';
  }
   return $spec;
}

sub getTestData {
  my $self = shift;
  my $action = shift;
  my $schema = shift;
  my $data = "No example JSON data available";

  eval {
    my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
    my $sth = $dbs->prepare(q/
                              SELECT test_json
                              FROM api_schema
                              WHERE schema_name = ? AND mode = ?
                            /);
    $sth->execute($schema,$action) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    if (defined $rows->[0]{'test_json'}) {
      $data = $rows->[0]{'test_json'};
    }
  };
 
  return $data;
}

1;
