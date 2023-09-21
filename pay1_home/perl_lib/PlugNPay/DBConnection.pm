package PlugNPay::DBConnection;

#  If PNP_DBINFO_DATABASE environmental variable is set, then the
#  required environmental variables need to be set for the dbinfo database:
#
#   PNP_DBINFO_USERNAME
#   PNP_DBINFO_PASSWORD
#   PNP_DBINFO_HOST
#   PNP_DBINFO_PORT
#
# For Apache, DO NOT PUT THESE IN .htaccess FILES!!!! Only
# in the main config.  At least only root can read the main
# config.

use strict;
use DBI;
use POSIX;
use Time::HiRes qw(gettimeofday);
use PlugNPay::Database::DBH;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::DBConnection::DBInfo;
use PlugNPay::Logging::Alert;
use PlugNPay::Util::StackTrace;
use PlugNPay::Logging::DataLog;

###
# Create only one instance of this object and serve it out over and over
#
our $singleton = '';

our %credentials;

sub new {
  my $self;
  if ($singleton eq '') {
    $self = {};
    $singleton = $self;
  } else {
    $self = $singleton;
  }

  bless $self,'PlugNPay::DBConnection';
  $self->_connections();
  return $self;
}

sub _pushTransaction {
  my $self = shift;
  my $database = shift;
  if (!defined $self->{'transaction'}{$database} || $self->{'transaction'}{$database} <= 0) {
    $self->{'transaction'}{$database} = 1;
  } else {
    $self->{'transaction'}{$database}++;
  }
  return $self->{'transaction'}{$database};
}

sub _popTransaction {
  my $self = shift;
  my $database = shift;
  if (!$self->{'transaction'}{$database}) {
    die('No transaction to pop');
  }
  my $transaction = $self->{'transaction'}{$database};
  $self->{'transaction'}{$database}--;
  return $transaction;
}

sub begin {
  my $self = shift;
  my $database = shift;
  my $transaction = $self->_pushTransaction($database);
  my $caller;
  {
    no warnings; # caller() returns undefined values
    $caller = sprintf('[%s|%s|%s]', caller());
  }

  if ($transaction == 1) {
    $self->do($database,'BEGIN');
    $self->log(sprintf('TX: Called BEGIN on %s, stack is %d, at %s',$database, $transaction, $caller));
  };

  if ($transaction) {
    $self->do($database,'SAVEPOINT transaction' . $transaction);
    $self->log(sprintf('TX: Called SAVEPOINT on %s, stack is %d, at %s',$database, $transaction, $caller));
  }

  return $transaction;
}

sub commit {
  my $self = shift;
  my $database = shift;
  my $transaction = $self->_popTransaction($database);

  my $caller;
  {
    no warnings; # caller() returns undefined values
    $caller = sprintf('[%s|%s|%s]', caller());
  }

  if ($transaction) {
    $self->do($database,'RELEASE SAVEPOINT transaction' . $transaction);
    $self->log(sprintf('TX: Called RELEASE SAVEPOINT on %s, stack is %d, at %s',$database, $transaction, $caller));
  }

  if ($transaction == 1) {
    $self->do($database,'COMMIT');
    $self->log(sprintf('TX: Called COMMIT on %s, stack is %d, at %s',$database, $transaction, $caller));
  }

  return 1;
}

sub rollback {
  my $self = shift;
  my $database = shift;
  my $transaction = $self->_popTransaction($database);

  my $caller;
  {
    no warnings; # caller() returns undefined values
    $caller = sprintf('[%s|%s|%s]', caller());
  }

  if ($transaction) {
    $self->do($database,'ROLLBACK TO transaction' . $transaction);
    $self->log(sprintf('TX: Called ROLLBACK TO on %s, stack is %d, at %s',$database, $transaction, $caller));
  }

  if ($transaction == 1) {
    $self->do($database,'ROLLBACK');
    $self->log(sprintf('TX: Called ROLLBACK on %s, stack is %d, at %s',$database, $transaction, $caller));
  }

  return 1;
}

sub prepare {
  my $self = shift;
  my $database = shift;
  my $query = shift;

  my $caller;
  {
    no warnings; # caller() returns undefined values
    $caller = sprintf('[%s|%s|%s]', caller());
  }

  if ((lc $query) =~ /^(begin|commit|rollback) /) {
    my $action = $1;
    $self->log(sprintf('WARNING, manual %s called at %s', (uc $action), $caller));
  }

  return $self->getHandleFor($database)->prepare($query);
}

sub do {
  my $self = shift;
  my $database = shift;
  my $query = shift;

  my $caller;
  {
    no warnings; # caller() returns undefined values
    $caller = sprintf('[%s|%s|%s]', caller());
  }

  if ((lc $query) =~ /^begin /) {
    $self->log(sprintf('WARNING, manual BEGIN at %s', $caller));
  }

  if ($query) {
    return $self->getHandleFor($database)->do($query);
  }
}

# I'm tired of writing this crap over and over...
sub executeOrDie {
  my $self = shift;
  my $database = shift;
  my $query = shift;
  my $inputArrayRef = shift;
  my $sth;
  eval {
    $sth = $self->prepare($database,$query) or die(q/'/ . $DBI::errstr . q/' at '/ . new PlugNPay::Util::StackTrace()->string(', '));
    $sth->execute(@{$inputArrayRef}) or die(q/'/ . $DBI::errstr . q/' at '/ . new PlugNPay::Util::StackTrace()->string(', '));
  };
  if ($@) {
    my $logId = $self->logError($@);
    die("Query error, log id is: " . $logId);
  }
  return { sth => $sth };
}

sub fetchrowOrDie {
  my $self = shift;
  my $database = shift;
  my $query = shift;
  my $inputArrayRef = shift;
  my $fetchOption = shift;
  my $additionalOptions = shift;

  my $callback = $additionalOptions->{'callback'};
  my $result = $additionalOptions->{'mockRows'};
  my $sth;

  if (!defined $result) {
    my $executeResponse = $self->executeOrDie($database,$query,$inputArrayRef);
    $sth = $executeResponse->{'sth'};

    my $nextSub;
    if (ref($fetchOption) eq 'HASH') {
      $nextSub = sub {
        return $sth->fetchrow_hashref() or die(q/'/ . $DBI::errstr . q/' at '/ . new PlugNPay::Util::StackTrace()->string(', '));
      };
    } elsif (ref($fetchOption) eq 'ARRAY') {
      $nextSub = sub {
        return $sth->fetchrow_arrayref() or die(q/'/ . $DBI::errstr . q/' at '/ . new PlugNPay::Util::StackTrace()->string(', '));
      }
    } else {
      die "Invalid fetch option";
    }

    return {
      sth => $sth,
      next => $nextSub,
      finished => sub {
        return $sth->finish;
      }
    };
  } else {
    return {
      next => sub {
        return shift @{$result};
      },
      finished => sub {}
    };
  }
}

# And I'm tired of writing this too...
sub fetchallOrDie {
  my $self = shift;
  my $database = shift;
  my $query = shift;
  my $inputArrayRef = shift;
  my $fetchallOption = shift;
  my $additionalOptions = shift;

  my $callback = $additionalOptions->{'callback'};
  my $result = $additionalOptions->{'mockRows'};
  my $sth;

  if (!defined $result) {
    my $executeResponse = $self->executeOrDie($database,$query,$inputArrayRef);
    $sth = $executeResponse->{'sth'};
    $result = $sth->fetchall_arrayref($fetchallOption) or die(q/'/ . $DBI::errstr . q/' at '/ . new PlugNPay::Util::StackTrace()->string(', '));
  }

  if ($callback) {
    foreach my $row (@{$result}) {
      &{$callback}($row);
    }
  }
  return {
    rows => $result, # this makes more sense than 'result'
    result => $result,
    sth => $sth };
}

sub database {
  my $database = shift;
  return new PlugNPay::DBConnection()->getHandleFor($database);
}

sub connections {
  return new PlugNPay::DBConnection();
}

sub _connections {
  my $self = shift;

  if (!exists $self->{'handlerSet'} && exists $ENV{'MOD_PERL'}) {
    # get a request object
    eval "require Apache2::RequestUtil ()";
    
    my $r;
    eval {
      $r = Apache2::RequestUtil->request;

      # don't allow keepalive for requests that use DBConnection
      if (defined $r->connection()->keepalive) {
        $r->connection()->keepalive($Apache2::Const::CONN_CLOSE);
      }

      # add a call to the static method cleanup() as a PerlCleanupHandler
      my $selfType = ref($self);
      $r->push_handlers('PerlCleanupHandler' => \&PlugNPay::DBConnection::cleanup());

      # remember that we've done this as if we don't, the call will be pushed
      # to the array over and over, and that means it'll be called as many times
      # as there have been requests for that thread....that's bad.
      $self->{'handlerSet'} = 1;
    };
  }

  return $self;
}

sub getHandleFor {
  my $self = shift;
  my $database = shift;

  my $caller;
  {
    no warnings; # caller() returns undefined values
    $caller = sprintf('[%s|%s|%s]', caller());
  }

  if ((defined $self->{'handles'}{$database} && !$self->{'handles'}{$database}->ping()) || !defined $self->{'handles'}{$database}) {
    $self->log('Creating a new connection to [' . $database . '] ' . $caller);
    my $credentials = $self->getDBInfo($database);
    my $dbh = $self->_connectTo($credentials);
    $self->{'handles'}{$database} = $dbh;
  }  else {
    $self->log('Reusing existing connection to [' . $database . '] ' . $caller);
  }

  if (!defined $self->{'handles'}{$database}) {
    $self->setError('Can\'t get database handle for: ' . $database);
  }

  return $self->{'handles'}{$database};
}

sub _connectTo {
  my $self = shift;
  my $credentials = shift;

  my $database = $credentials->{'database'};

  my $dsn = sprintf('DBI:mysql:database=%s;host=%s;port=%s',$credentials->{'database'},$credentials->{'host'},$credentials->{'port'});
  my $dbh;
  my $retries = 0;
  my $db_status = 1;
  my @retryLog;

  do {
    #Create start time in readable format
    my @secondsArray = Time::HiRes::gettimeofday();
    my ($sec,$min,$hr,$day,$mon,$year) = gmtime($secondsArray[0]);
    $mon++;
    $mon = ($mon < 10 ? '0' . $mon : $mon);
    $day = ($day < 10 ? '0' . $day : $day);
    $hr = ($hr < 10 ? '0' . $hr : $hr);
    $min = ($min < 10 ? '0' . $min : $min);
    $sec = ($sec < 10 ? '0' . $sec : $sec);
    $year += 1900;
    my $startTime = $year. '-' . $mon . '-' . $day . 'T' . $hr . ':' . $min . ':' . $sec . ':' . $secondsArray[1] . 'Z';

    eval {
      local $SIG{ALRM} = sub { die 'DBI connect timeout: ' . "\n";};
      $db_status = 1;
      alarm 2;
      $dbh = DBI->connect($dsn, $credentials->{'username'}, $credentials->{'password'}, {'RaiseError' => 1, 'PrintError' => 0});
      alarm 0;
    };

    #calculate elapsed time
    my @timeArray2 = Time::HiRes::gettimeofday;
    my $elapsedTime = $timeArray2[0] - $secondsArray[0];
    my $elapsedMS;

    #Accounting for second rollover
    if ($timeArray2[1] < $secondsArray[1]) {
      $elapsedMS = (1000000 + $timeArray2[1]) - $secondsArray[1];
    } else {
      $elapsedMS = $timeArray2[1] - $secondsArray[1];
    }

    if ($@ || !$dbh) {
      $retries++;
      $db_status = 0;
      my $db_error = $@ || $DBI::errstr;
      push @retryLog, "Connection to $database started at $startTime, for $elapsedTime.$elapsedMS seconds for retry count: $retries. PID: $$, DBI Error: $db_error";
    }
  } while ($retries < 5 && (!$dbh || $db_status == 0));

  # log any errors
  foreach my $log (@retryLog) {
    eval {
      Apache2::ServerRec::warn($log);
    };
    if ($@) {
      print STDERR "$log\n";
    }

    $self->logError($log);
  }

  # log the stacktrace once if there are errors.
  if (@retryLog > 0) {
    eval {
      Apache2::ServerRec::warn(new PlugNPay::Util::StackTrace()->string(', ') . "\n");
    };
    if ($@) {
      print STDERR new PlugNPay::Util::StackTrace()->string(', ') . "\n";
    }
  }

  if (($retries >= 5 && $db_status == 0) || !$dbh) {
    eval {
      Apache2::ServerRec::warn("Failed to connect to database: $database");
      Apache2::ServerRec::warn($DBI::errstr);
    };

    if ($@) {
      print STDERR "Failed to connect to database: $database \n";
      print STDERR $DBI::errstr . "\n";
    }

    $self->setError($DBI::errstr);
  }

  #DBH wrapper
  $dbh = new PlugNPay::Database::DBH({'dbh' => $dbh, 'databaseName' => $database});

  return $dbh;
}

sub getDBInfo {
  my $self = shift;
  my $db = shift;

  my $response = {};

  if ($ENV{'PNP_SERVICE_NAME'}) {
    my $credsHash = {};
    eval {
      $credsHash = PlugNPay::DBConnection::DBInfo::getDBInfo();
    };

    if ($@) {
      print STDERR $@;
    }

    my $dbCreds = $credsHash->{$db};

    $response = {
      database => $dbCreds->{'database'},
      username => $dbCreds->{'username'},
      password => $dbCreds->{'password'},
      host => $dbCreds->{'host'},
      port => $dbCreds->{'port'}
    };
  }

  # failback to old method
  if (!defined $response->{'username'}) {
    $response = $self->getDBInfoFromDatabase($db);
    if (defined $response->{'username'}) { # if username is now defined...alert
      printf STDERR "Failed to load db info for '%s' from service, successfully loaded via database directly.\n", $db;
    } else {
      die(sprintf("Failed to load db info for '%s' via database directly.  Giving up.", $db));
    }
  }

  return $response;
}

sub getDBInfoFromDatabase {
  my $self = shift;
  my $db = shift;

  # This is also commented out temporarily
  #if (!defined $credentials{$db}) {
    # load the info from dbinfo
  #  $credentials{$db} = {};

    my $username = $ENV{'PNP_DBINFO_USERNAME'};
    my $password = $ENV{'PNP_DBINFO_PASSWORD'};
    my $host     = $ENV{'PNP_DBINFO_HOST'};
    my $port     = $ENV{'PNP_DBINFO_PORT'};
    my $database = $ENV{'PNP_DBINFO_DATABASE'};
    my $dbh = $self->_connectTo({username => $username,
                                 password => $password,
                                 database => $database,
                                 host => $host,
                                 port => $port}) or $self->log('Could not connect to dbinfo database.');
    my $result = {};
    if ($dbh) {
      my $sth = $dbh->prepare(q/
        SELECT username,password,host,port,COALESCE(`database`,db_name) as `database`
          FROM db_login
         WHERE db_name = ?
      /);

      if ($sth) {
        $sth->execute($db);

        $result = $sth->fetchrow_hashref;
        $sth->finish;

        if ($result->{'username'} && $result->{'password'}) {
          # Temporarily commented out caching
          #$credentials{$db} = $result;
        } else {
          $self->log('No login info found for database: ' . $db);
        }
      }
    }
  #}

  return $result; #$credentials{$db};
}

sub getColumnsForTable {
  my $self = shift;
  my $args = shift;
  my $database = $args->{'database'};
  my $table = $args->{'table'};

  my $rows = [];
  eval {
    my $sth = $self->prepare($database,q/
      SELECT column_name as `column`, data_type as `type`, character_maximum_length as `length`
      FROM information_schema.columns
      WHERE table_name = ? AND table_schema = ?
    /);
    $sth->execute($table,$database);
    $rows = $sth->fetchall_arrayref({});
  };

  my %columnData = ();
  if ($args->{'format'} eq 'lower') {
    %columnData = map { lc($_->{'column'}) => { type => $_->{'type'}, length => $_->{'length'} } } @{$rows};
  } elsif ($args->{'format'} eq 'upper') {
    %columnData = map { uc($_->{'column'}) => { type => $_->{'type'}, length => $_->{'length'} } } @{$rows};
  } else {
    %columnData = map { $_->{'column'} => { type => $_->{'type'}, length => $_->{'length'} } } @{$rows};
  }

  return \%columnData;
}

sub queryBuilder {
  my $self = shift;
  my $qb = new PlugNPay::Database::QueryBuilder();
  return $qb;
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

sub log {
  my $self = shift;
  my $message = shift;

  my $timestamp = POSIX::strftime('%m/%d/%Y %H:%M:%S', localtime);
  push(@{$self->{'log'}},$timestamp . ' ' . $message);
}

sub clearLog {
  my $self = shift;
  delete $self->{'log'};
}

sub getLog {
  my $self = shift;
  return @{$self->{'log'}};
}

sub cleanup {
  if (defined $singleton && ref($singleton) eq 'PlugNPay::DBConnection') {
    $singleton->log("cleaning up...");
    $singleton->closeConnections();
  }
}

sub closeConnections {
  my $self = shift;
  foreach my $handleName (keys %{$self->{'handles'}}) {
    my $handle = $self->{'handles'}{$handleName};
    $handle->breakConnection() if defined $handle;
    delete $self->{'handles'}{$handleName};
  }
}

END {
  cleanup();
}

sub DESTROY {
  my $self = shift;
  $self->closeConnections();
}

sub logError {
  my $self = shift;
  my $error = shift;
  my $logId;
  eval {
    my $logger = new PlugNPay::Logging::DataLog({ collection => 'database'});
    my $logData = {
      error => $error
    };
    (undef,$logId) = $logger->log($logData,{ stackTraceEnabled => 1 });
  };
  return $logId || "UNKNOWN";
}

1;
