package PlugNPay::Security::Redirection;

use strict;
use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->loadRedirects();
  $self->{'directoryUpdate'} = {};
  return $self;
} 

###################
# Setters/Getters #
###################

sub setDirectory {
  my $self = shift;
  my $directory = shift;
  $self->{'directory'} = $directory;
}
    
sub getDirectory {
  my $self = shift;
  return $self->{'directory'};
}

sub clearError {
  my $self = shift;
  $self->setError(undef);
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

sub getValidRedirects {
  my $self = shift;
  my $data = $self->{'validDirectories'};
  my @keys = keys %{$data};

  if (@keys == 0) {
    $data = $self->loadRedirects();
  }

  return $data;
}

###########
# Workers #
###########

sub loadRedirects {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $sth = $dbs->prepare('pnpmisc',q/
            SELECT `directory`, `valid`
            FROM `valid_redirection`
  /);
  $sth->execute() or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $data = {};
  foreach my $row (@{$rows}) {
    my $isValid = $row->{'valid'} || 0;
    $data->{$row->{'directory'}} = $isValid;
  }
  $self->{'validDirectories'} = $data;
  return $data;
}

sub filterRedirection {
  my $self = shift;
  my $dirString = shift || $self->getDirectory();
  my $data = $self->getValidRedirects();
  unless ($data->{$dirString}) {
    my @dirs = split('/',$dirString);
    my $newDirList = [];
    my $longestValidDir = '';
    foreach my $dir (@dirs) {
      push (@{$newDirList}, $dir);
      my $tempStr = join('/',@{$newDirList});
      if ($data->{$tempStr}) {
        $longestValidDir = $tempStr;
      }
    }
    return $longestValidDir;
  } else {
    return $dirString;
  }
}

###################
# Admin Functions #
###################
sub addDirectoryToUpdate {
  my $self = shift;
  my $dir = shift;
  my $valid = shift;
  $self->{'directoryUpdate'}{$dir} = $valid;
}

sub getDirectoriesToUpdate {
  my $self = shift;
  return $self->{'directoryUpdate'};
}

sub updateRedirects {
  my $self = shift;
  my $data = $self->getDirectoriesToUpdate();
  my @keys = keys %{$data};

  if (@keys > 0) {
    my @params = ();
    my @values = ();
    foreach my $key (@keys) {
      push @values,$key;
      push @values,$data->{$key};
      push @params,'(?,?)';
    }

    my $dbs = new PlugNPay::DBConnection();
    $dbs->begin('pnpmisc');
    eval {
      my $sth = $dbs->prepare('pnpmisc',q/
                INSERT INTO valid_redirection
                (`directory`,`valid`)
                VALUES / . join(',',@params) . q/
                ON DUPLICATE KEY UPDATE valid = VALUES(valid)/);
      $sth->execute(@values) or die $DBI::errstr;
    };

    if ($@) {
      $self->setError($@); 
      $dbs->rollback('pnpmisc');
      return 0;
    } else {
      $self->clearError();
      $dbs->commit('pnpmisc');
      return 1;
    }
  } else {
    $self->setError('No directories to update');
    return 0;
  }
}

1;
