package PlugNPay::Database::DBH;

use strict;
use PlugNPay::DBConnection();

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $options = shift;

  if (defined $options && ref($options) eq 'HASH' &&  defined $options->{'dbh'}) {
    $self->setDBH($options->{'dbh'});

    if (defined $options->{'databaseName'} ) {
      $self->setDatabaseName($options->{'databaseName'});
    }

    if (defined $options->{'enableLogging'}) {
      $self->setLogging($options->{'enableLogging'});
    }

  } else {
    my ($package,$module,$line) = caller();
    die "No DBH passed from: $module on line $line";
  }

  return $self;
}

sub setDBH {
  my $self = shift;
  my $DBH = shift;
  $self->{'dbh'} = $DBH;
}

sub getDBH {
  my $self = shift;
  return $self->{'dbh'};
}

sub setDatabaseName {
  my $self = shift;
  my $databaseName = shift;
  $self->{'databaseName'} = $databaseName;
}

sub getDatabaseName {
  my $self = shift;
  return $self->{'databaseName'};
}

sub setLogging {
  my $self = shift;
  my $logFlag = shift;
  $self->{'errorLogging'} = $logFlag;
}

sub getLogging {
  my $self = shift;

  return $self->{'errorLogging'} || 0;
}

sub disconnect {
  my $self = shift;
  if ($self->getLogging()) {
    my ($package,$module,$line) = caller();
    my $databaseName = $self->getDatabaseName() || 'database';
    my $message = 'DBH: Attempted to disconnect from `' . $databaseName . '` in module ' . $module . ' on line ' . $line;
    eval {
      Apache2::ServerRec::warn($message);
    };
    if ($@) {
      print STDERR $message . "\n";
    }
  }
}

sub disconnect_all {
  my $self = shift;
  if ($self->getLogging()) {
    my ($package,$module,$line) = caller();
    my $message = 'Attempted to disconnect_all in module ' . $module . ' on line ' . $line;
    eval {
      Apache2::ServerRec::warn($message);
    };
    if ($@) {
      print STDERR $message . "\n";
    }
  }
}

sub breakConnection {
  my $self = shift;
  $self->{'dbh'}->disconnect(@_);
}

sub breakAllConnections {
  my $self = shift;
  $self->{'dbh'}->disconnect_all(@_);
}

sub prepare {
  my $self = shift;
  my ($caller,$package,$file,$lineNumber,$subroutine);
  {
    no warnings; # caller() returns undefined values
    my $i = 0;
    while ($package eq '' || $package eq 'PlugNPay::DBConnection') {
      ($package,$file,$lineNumber,$subroutine) = caller($i);
      $i++;
    }
    $caller = sprintf('[%s|%s|%s]', $package,$file,$lineNumber);
  }
  my $testQuery = lc $_[0];
  $testQuery =~ s/^\s+\/\*.*?\*\///; # remove any leading comment from query
  if ($testQuery =~ /^(begin|commit|rollback) /) {
    my $action = $1;

    if ($package != 'PlugNPay::DBConnection') {
      my $dbs = new PlugNPay::DBConnection();
      $dbs->log('WARNING: manual %s called at %s', (uc $action), $caller);
    }
  }
  # add comment showing caller to the query
  my @input = @_;
  $input[0] = sprintf('/* CALLER:%s */ %s', $caller, $_[0]);
  chomp $input[0];
  if ($ENV{'DEBUG_DB_PREPARE'} eq 'TRUE') {
    print STDERR "PREPARED:" . $input[0] . "\n";
  }
  $self->{'dbh'}->prepare(@input);
}

sub AUTOLOAD {
  my $self = shift;
  our $AUTOLOAD; # to allow 'use strict;'
  my $sub = $AUTOLOAD;
  $sub =~ s/.*:://g;
  return $self->{'dbh'}->$sub(@_);
}

1;
