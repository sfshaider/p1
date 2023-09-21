package PlugNPay::Database;

################################################################################
# Note:                                                                        #
#   Remember, all functions that start with _ are private.  Do not use them.   #
################################################################################


use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;
use PlugNPay::Logging::MessageLog;


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  ###  Enter Code Here to decide if merchant is old/new
  $PlugNPay::Database::dataBase_version = 1;

  return $self;
}


sub databaseQuery {
  my $self = shift;
  my $database = shift;  ## Database to Query
  my $table = shift;     ## Table to Query
  my $requestedData = shift; ## ARRAY data requested
  my $params = shift;  ## ARRAY Search parameters
  my $orderby = shift;  ## ARRRAY order data to be returned in.
  my $groupby = shift;
  my @results = ();

  if ($PlugNPay::Database::dataBase_version == 2) {
    ## Direct Request to new code.
  }
  else {
    @results = &legacyQuery($self,$database,$table,$requestedData,$params,$orderby,$groupby);
  }
  return @results;
}


sub legacyQuery {
  my $self = shift;
  my $database = shift;  ## Database to Query
  my $table = shift;     ## Table to Query
  my $requestedData = shift; ## ARRAY data requested
  my $params = shift;  ## ARRAY Search parameters
  my $orderby = shift;  ## ARRRAY order data to be returned in.
  my $groupby = shift;

  my %queryOrder = ('trans_log',["trans_date","orderid","username"],'customers',["username"]);

  ###  Can we do a describe table at load and cache the primary keys to have the order auto determined?

  my $sqlstr = "";
  my @executeArray = ();
  my %queriedParams = ();
  my @results = ();

  $sqlstr = "select ";
  if ($$requestedData[0] eq "ALL") {
    $sqlstr .= "*";
  }
  else {
    foreach my $var (@$requestedData) {
      $sqlstr .= "$var,";
    }
    chop $sqlstr;
  }
  $sqlstr .= " FROM $table ";

  if (($params ne "") && (@{$params}>0)) { ###  Allow where statement to be left out on query
    $sqlstr .= "where " . &_parseWhere($params,\@executeArray);
  }

  if (($orderby ne "") && (@$orderby >0)) {
    $sqlstr .= "ORDER BY ";
    foreach my $field_name (@$orderby) {
      $sqlstr .= "$field_name,";
    }
    chop $sqlstr;
  }

  if (($groupby ne "") && (@$groupby >0)) {
    $sqlstr .= "GROUP BY ";
    foreach my $field_name (@$groupby) {
      $sqlstr .= "$field_name,";
    }
    chop $sqlstr;
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($database);

  $dbh->{FetchHashKeyName} = 'NAME_lc';

  my $sth = $dbh->prepare(qq{$sqlstr});
  $sth->execute(@executeArray) or die "Can't execute: $DBI::errstr";
  while (my $data = $sth->fetchrow_hashref) {
    $results[++$#results] = $data;
  }
  $sth->finish();

  return @results;

}

sub databaseInsert {
  my $self = shift;
  my $database = shift;  ## Database to Query
  my $table = shift;     ## Table to Query
  my $insertData = shift; ## HASHY data requested
  my @results = ();

  if ($PlugNPay::Database::dataBase_version == 2) {
    ## Direct Request to new code.
  }
  else {
    @results = &legacyInsert($self,$database,$table,$insertData);
  }
  return @results;
}

sub legacyInsert {
  my $self = shift;
  my $database = shift;  ## Database to Query
  my $table = shift;     ## Table to Query
  my $insertData = shift; ## HASHY data requested

  my @insertData = keys %$insertData;

  my $sqlstr = "";
  my @executeArray = ();
  my $qstr = "";
  my @results = ();

  $sqlstr = "insert into $table (";
  foreach my $field_name (@insertData) {
    $sqlstr .= "$field_name,";
    $qstr .= "?,";
    push (@executeArray,$$insertData{$field_name});
  }
  chop $sqlstr;
  chop $qstr;
  $sqlstr .= ") values ($qstr) ";

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($database);
  my $sth = $dbh->prepare(qq{$sqlstr});
  $sth->execute(@executeArray) or die "Can't execute: $DBI::errstr";
  $sth->finish();

  return;

}

sub databaseUpdate {
  my $self = shift;
  my $database = shift;  ## Database to Query
  my $table = shift;     ## Table to Query
  my $updateData = shift; ## ARRAY data requested
  my $params = shift;  ## ARRAY Search parameters
  my @results = ();

  if ($PlugNPay::Database::dataBase_version == 2) {
    ## Direct Request to new code.
  }
  else {
    @results = &legacyUpdate($self,$database,$table,$updateData,$params);
  }
  return @results;
}

sub legacyUpdate {
  my $self = shift;
  my $database = shift;  ## Database to Query
  my $table = shift;     ## Table to Query
  my $updateData = shift; ## HASHY data requested
  my $params = shift;  ## ARRAY Search parameters

  my @updateData = keys %$updateData;

  my $sqlstr = "";
  my @executeArray = ();
  my %queriedParams = ();
  my @results = ();

  my %required_fields = ('trans_log','username|orderid','operation_log','username|orderid','customers','username');

  my $missing_required_key_column ="";

  my %testHash = @$params;
  my @testArray = ('username');
  if ($required_fields{$table} ne "") {
    @testArray = split('\|',$required_fields{$table});
  }

  foreach my $test (@testArray) {
    if (! exists $testHash{$test}) {
      $missing_required_key_column = "$test";
      last;
    }
  }

  $sqlstr = "update $table set ";

  foreach my $field_name (@updateData) {
    $sqlstr .= "$field_name=?,";
    push (@executeArray,$$updateData{$field_name});
  }
  chop $sqlstr;

  $sqlstr .= " where " . &_parseWhere($params,\@executeArray);

  if ($missing_required_key_column ne "") {
    my @nullArray = ();
    $sqlstr = "Missing Key Fields, $missing_required_key_column, Exiting";
    $self->_log_sql($sqlstr,\@nullArray,__LINE__);
    exit;
  }
  else {
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor($database);
    my $sth = $dbh->prepare(qq{$sqlstr});
    $sth->execute(@executeArray) or die "Can't execute: $DBI::errstr";
    $sth->finish();
  }

  return;

}

sub _log_sql {
  my $self = shift;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
  my ($sqlstr,$executeArray,$linenum) = @_;
  my %logdata = ();

  ### Settings does not seem to work
  my %settings = ();
  $settings{'context'} = 'DatabasePM';
  $settings{'process'} = $ENV{'SCRIPT_NAME'};

  my @array_copy = ();
  if ($sqlstr =~ /enccardnumber/) {
    foreach my $var (@$executeArray) {
      if ($var =~ /aes256/) {
        push (@array_copy, 'DATA MASKED');
      }
      else {
        push (@array_copy, $var);
      }
    }
  }
  else {
    @array_copy = @$executeArray;
  }
  $logdata{'SQL'} = "$sqlstr";
  $logdata{'LineNum'} = $linenum;
  foreach my $var (@array_copy) {
    if ((ref($var) eq "ARRAY") && (@{$var}>0)) {
      foreach my $vvar (@{$var}) {
        $logdata{'ARRAY'} .= "$vvar,";
      }
    }
    $logdata{'ARRAY'} .= "$var,";
  }
  chop $logdata{'ARRAY'} ;
  my $logger = new PlugNPay::Logging::MessageLog();
  $logger->logMessage(\%logdata,\%settings);

}

sub _parseWhere {
  my ($params,$executeArray) = @_;
  my $sqlstr = "";

  for (my $i=0; $i<@$params; $i+=2) {
    my $field_name = $$params[$i];
    my $param_value = $$params[$i+1];
    my $op='';
    if ($param_value ne "") {
      if ($param_value =~ /^([\<\=\>]+)(.+)$/) {
        $op = $1;
        $sqlstr .= "$field_name$op? and ";
        push (@$executeArray,$2);
      }
      elsif ($param_value =~ /NOT NULL/i) {
        $sqlstr .= "($field_name is NOT NULL and $field_name<>\'\') and ";
      }
      elsif (($param_value =~ /NULL/i) || ((ref($param_value) eq "ARRAY") && (@{$param_value}[0] eq "NULL"))) {
        $sqlstr .= "($field_name is NULL or $field_name=\'\'";
        if ((ref($param_value) eq "ARRAY") && (@{$param_value}>0)) {
          shift @{$param_value}; ### chop off 'NULL' since already in where clause
          foreach my $value (@{$param_value}) { ## Loop through rest of paramters and add to where clause.
            $sqlstr .= " or $field_name=?";
            push (@$executeArray,$value);
          }
        }
        $sqlstr .= ") and ";
      }
      elsif ((ref($param_value) eq "ARRAY") && (@{$param_value}>0)) {
        my $op = "IN";
        my $op_test = ${$param_value}[0];
        if ($op_test eq "!") {
          $op = "NOT IN";
          shift @{$param_value};
        }
        $op .= " (";
        $op .= '?,' x @{$param_value};
        chop $op;
        push(@$executeArray, @{$param_value});
        $op .= ")";
        $sqlstr .= "$field_name $op and ";
      }
      elsif ($param_value =~ /\|/) {  #### Left in temporarily for backward compatibility.  Will remove shortly. DCP 20150127
        my @temparray = split(/\|/,$param_value);
        $op = "IN (";
        foreach my $val1 (@temparray) {
          $op .= "?,";
          push (@$executeArray,$val1);
        }
        chop $op;
        $op .= ")";
        $sqlstr .= "$field_name $op and ";
      }
      else {
        $sqlstr .= "$field_name=? and ";
        push (@$executeArray,$param_value);
      }
    }
  }
  $sqlstr = substr($sqlstr,0,-4);

  return $sqlstr;
}



1;
