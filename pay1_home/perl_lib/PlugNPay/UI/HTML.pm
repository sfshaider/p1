package PlugNPay::UI::HTML;

use strict;
use HTML::Entities;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub selectOptions {
  my $self = shift;
  my $options = shift;

  my $firstOption = $options->{'first'};

  my @keys = keys %{$options->{'selectOptions'}};

  # remove firstOption from the keys to be sorted
  if (defined $firstOption) {
    @keys = grep { $_ ne $firstOption } @keys;
  }

  sub getCompareValue {
    my $options = shift;
    my $key = shift;

    my $value;

    if (ref($options->{'selectOptions'}) eq 'HASH') {
      $value = $key;
    } else {
      $value = $options->{'selectOptions'}{$key};
    }

    return $value;
  }

  if (!$options->{'unsorted'}) {
    @keys = sort { getCompareValue($options,$a) cmp getCompareValue($options,$b) } @keys;
  }

  # put the first option back on the list of keys in the first position
  if (defined $firstOption) {
    unshift @keys,$firstOption;
  }

  my $output;

  foreach my $key (@keys) {
    my $selectedIndicator = '';
    my $disabledIndicator = '';

    if ($options->{'selected'} eq $key) {
      $selectedIndicator = 'selected';
    } 

    if (grep { $_ eq $key } @{$options->{'disabled'}}) {
      $disabledIndicator = 'disabled';
    }

    # if the value is a hash, create an optgroup
    if (ref($options->{'selectOptions'}{$key}) eq 'HASH') {
      my $label = encode_entities($key);
      $output .= '<optgroup label=\'' . $label . '\'>';
      $output .= $self->selectOptions({ unsorted => $options->{'unsorted'}, selectOptions => $options->{'selectOptions'}{$key}, selected => $options->{'selected'} });
      $output .= '</optgroup>';
    } else {
      my $value = encode_entities($options->{'selectOptions'}{$key});
      $key = encode_entities($key);
      $output .= '<option value=\'' . $key . '\' ' . $selectedIndicator . ' ' . $disabledIndicator . '>' . $value . '</option>';
    }
  }

  return $output;
}

sub buildTable {
  my $self = shift;
  my $options = shift;

  # $columns is an array of hashes, the hashes keys are "type" and "name" 
  my $columns = $options->{'columns'};

  # $data is an array of arrays
  my $data = $options->{'data'};
  my $tableID = $options->{'id'};
  my $tableClass = $options->{'class'};

  my $tableHTML = '<table id="' . $tableID . '" class="' . $tableClass . '">';

  # build the header row
  $tableHTML .= '<tr class="header">';
  foreach my $column (@{$columns}) {
    $tableHTML .= '<th class="' . $column->{'type'} . '">' . $column->{'name'} . '</th>';
  }
  $tableHTML .= '</tr>';

  # build the data rows
  foreach my $row (@{$data}) {
    $tableHTML .= '<tr class="data">';
    my $columnNumber = 0;
    foreach my $column (@{$row}) {
      my $valueString = '';
      if ($columns->[$columnNumber]{'type'} eq 'number') {
        my $value = $column;
        $value =~ s/[^\d\.]//g;
        $valueString = ' value="' . $value . '"';
      }
      $tableHTML .= '<td' . $valueString . '>' . $column . '</td>';
      $columnNumber += 1;
    }
    $tableHTML .= '</tr>';
  }
  $tableHTML .= '</table>';

  return $tableHTML;
}

1;
