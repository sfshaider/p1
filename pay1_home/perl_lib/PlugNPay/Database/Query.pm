package PlugNPay::Database::Query;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Recurring::Profile;
use PlugNPay::Recurring::PaymentSource;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub queryTable {
  my $self = shift;
  my $input = shift || {};

  # Die if no database specified
  if (!$input->{'database'}) {
    die('No source database specified.');
  }
  my $database = $input->{'database'};

  # Die if no table specified
  if (!$input->{'table'}) {
    die('No source table specified.');
  }
  my $table = $input->{'table'};

  # Die if columns option doesn't exist, is not an array ref, or contains zero column names
  if (!$input->{'columns'} || ref($input->{'columns'} ne 'ARRAY') || length(@{$input->{'columns'}}) == 0) {
    die('No columns specified');
  }
  my $columns = $input->{'columns'};

  my $searchCriteria = $input->{'searchCriteria'} || {};
  my $queryDetails = $input->{'queryDetails'} || {};
  my $options = $input->{'options'} || {};

  # note that the columns option isn't super useful unless you specify a callback
  if (ref($options->{'columns'}) eq 'ARRAY') {
    my @filteredColumns = grep { inArray($_,$columns) } @{$options->{'columns'}};
    $columns = \@filteredColumns;
  }

  my $gatewayAccounts = [];
  if (ref($searchCriteria ne 'HASH')) {
    return $gatewayAccounts;
  }

  my $dbs = new PlugNPay::DBConnection();

  my $whereClause = '';
  my @whereData = ();
  my @whereClauseData = ();
  if (keys %{$searchCriteria} > 0) {
    foreach my $field (keys %{$searchCriteria}) {
      $whereClause = 'WHERE ' if $whereClause eq '';
      if (grep { /^$field$/ } @{$columns}) {
        if (ref($searchCriteria->{$field}) eq 'HASH') {
          if (uc($searchCriteria->{$field}{'operator'}) =~ /^(NOT )?IN$/) {
            # build the parameters based off the number of values
            push (@whereClauseData, $field . ' ' . $searchCriteria->{$field}{'operator'} . ' (' . join(',', map { '?' } @{$searchCriteria->{$field}{'values'}}) . ')' );
            push (@whereData, @{$searchCriteria->{$field}{'values'}});
          } elsif (uc($searchCriteria->{$field}{'operator'}) =~ /^(NOT\s+)?(RLIKE|LIKE)$/) {
            if ($searchCriteria->{$field}{'function'}) {
              my $function = $searchCriteria->{$field}{'function'};
              push (@whereClauseData, $function . '(' . $field . ') ' . $searchCriteria->{$field}{'operator'} . ' ' . $function . '(?)');
            } else {
              push (@whereClauseData, $field . ' ' . $searchCriteria->{$field}{'operator'} . ' ?');
            }

            push (@whereData, $searchCriteria->{$field}{'value'});
          } elsif ($searchCriteria->{$field}{'operator'} =~ /^([<=>]|<>)$/) { # check for <, >, =, and <>
            push (@whereClauseData, $field . ' ' . $searchCriteria->{$field}{'operator'} . ' ?');
            push (@whereData, $searchCriteria->{$field}{'value'});
          } elsif (uc($searchCriteria->{$field}{'operator'}) =~ /^IS( NOT)?$/ && !defined $searchCriteria->{$field}{'value'}) { # check for IS NULL or IS NOT NULL
            push (@whereClauseData, $field . ' ' . $searchCriteria->{$field}{'operator'} . ' NULL');
          } else {
            die ('Invalid operator');
          }
        } else { # if the value for the field is a string then just do a normal equality check
          if (defined $searchCriteria->{$field}) {
            push (@whereClauseData, $field . ' = ' . '?');
            push (@whereData, $searchCriteria->{$field});
          } else {
            push (@whereClauseData, $field . ' IS NULL');
          }
        }
      } else {
        die(sprintf('Invalid column specified for operation "%s": "%s"', $searchCriteria->{$field}{'operator'}, $field));
      }
    }

    $whereClause .= join(' AND ', @whereClauseData);
  }

  my $groupBy = '';
  if ($queryDetails->{'group'}) {
    $groupBy = $queryDetails->{'group'};
    $groupBy =~ s/\s+//g; # be lenient with spaces on this one...
    $groupBy =~ s/,$//;   # and strip off a trailing comma if present
    my @groupCols = split(/,/,$groupBy);

    # check to see if the column is valid
    foreach my $column (@groupCols) {
      if (!grep { /^$column$/ } keys %{$columns}) {
        die(sprintf('Invalid column specified in GROUP BY statement: "%s"', $column));
      }
    }
  }

  my $orderBy = '';
  if ($queryDetails->{'order'}) {
    $orderBy = $queryDetails->{'order'};
    my $spaceIndex = index($orderBy,' '); # find the index of the space, if any, in order to get column name
    my $column = substr($orderBy,0,($spaceIndex >= 0 ? $spaceIndex : length($orderBy)));
    if (!grep { /^$column$/ } @{$columns}) {
      die(sprintf('Invalid column specified in ORDER BY statement: "%s"', $column));
    }

    if (uc($orderBy) !~ /^\w+( DESC)?$/) { # only supporting a single column right now, sorry!
      die(sprintf('Invalid ORDER BY statement: "%s"',$orderBy));
    }
  }

  my $limit = '';
  if ($queryDetails->{'limit'}) {
    $limit = $queryDetails->{'limit'};
    die(sprintf('Invalid limit statement: "%s"',$limit)) if $limit !~ /^\d+(,\d+)?$/;
  }

  my $columnString = join(', ', @{$columns});
  my $sql = 'SELECT ' . $columnString . ' FROM ' . $table . ' ';

  if (exists $searchCriteria->{'useIndex'}) {
    my $index = $searchCriteria->{'useIndex'};
    $index =~ s/[^a-zA-Z0-9_]//g;
    $sql .= ' FORCE INDEX(' . $index . ') ';
  }
  $sql .= $whereClause;

  if ($groupBy) {
    $sql .= ' GROUP BY ' . $groupBy;
  }

  if ($orderBy) {
    $sql .= ' ORDER BY ' . $orderBy;
  }

  if ($limit) {
    $sql .= ' LIMIT ' . $limit;
  }

  my $response;
  my $rows;

  if ($options->{'callback'} && ref($options->{'callback'}) eq 'CODE') {
    if ($options->{'callbackMode'} eq 'row') {
      $response = $dbs->fetchrowOrDie($database, $sql, \@whereData, {});
      my $next = $response->{'next'};
      my $finished = $response->{'finished'};
      while (my $row = &{$next}()) {
        $options->{'callback'}($row);
      }
      &{$finished}();
      return;
    } else {
      $response = $dbs->fetchallOrDie($database, $sql, \@whereData, {});
      $rows = $response->{'result'} || [];
      $options->{'callback'}($rows);
      return;
    }
  }

  $response = $dbs->fetchallOrDie($database, $sql, \@whereData, {});
  $rows = $response->{'result'} || [];

  return $rows;
}

1;
