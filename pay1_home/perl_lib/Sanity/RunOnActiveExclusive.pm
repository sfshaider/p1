#!/usr/bin/perl -w

use strict;
use Sys::Hostname;
use Sanity::RunOneProcessNFS;

package Sanity::RunOnActiveExclusive;


sub new {
  my ($self,$scriptName) = @_;
  $scriptName =~ s/[^A-z0-9\.]//g;
  my %hash;
  $self = \%hash;

  bless $self,'Sanity::RunOnActiveExclusive';

  $self->{'hostname'} = main::hostname;
  $self->{'procInfoDirectory'} = '/home/p/pay1/run';
  my $logFile = '/home/p/pay1/logs/RunOnOneMachine.' . $self->{'hostname'} . '.log';

  $self->{'procInfoFile'} = $self->{'procInfoDirectory'} . '/' . $scriptName . '.' . $self->{'hostname'} . '.procinfo';

  # open log file
  open($self->{'logfile'},'>>', $logFile);

  # append pid to procinfo file
  open(PROCINFOFILE,'>>' . $self->{'procInfoFile'});
  print PROCINFOFILE $$ . ' ' . $self->amIOnAnActiveNode() . "\n";
  close(PROCINFOFILE);


  # sleep a few seconds to make sure the i/o flushes to the nfs server
  select(undef,undef,undef,2.0);

  $self->{'status'} = 0;

  opendir(PROCINFODIR,$self->{'procInfoDirectory'});
  my @procInfoFiles = grep { /$scriptName\.[A-z0-9]+\.procinfo/ } readdir(PROCINFODIR);
  closedir(PROCINFODIR);

  # sleep a few more seconds to make sure procinfo file stays there for a process on another machine to see
  select(undef,undef,undef,2.0);

  my $activeProcInfoFileCount = 0;

  # check for more than one system saying it's active
  foreach my $procInfoFile (@procInfoFiles) {
    #$self->_log('opening ' . $procInfoFile);
    open(PROCINFOFILECHECK,$self->{'procInfoDirectory'} . '/' . $procInfoFile) or die('procinfo file open failed');
    my $firstLine = <PROCINFOFILECHECK>;# or die('procinfo file read failed');
    close(PROCINFOFILECHECK);

    chomp $firstLine;
    #$self->_log('fl1 ' . $firstLine);
    if ($firstLine =~ /^\d+ 1$/) {
      $activeProcInfoFileCount++;
    }
  }

  #$self->_log('ac ' . $activeProcInfoFileCount);
  # if one machine is active, check to see if it is the correct machine with the correct pid
  if ($activeProcInfoFileCount == 1) {
    open(MYPROCINFOFILE,$self->{'procInfoDirectory'} . '/' . $scriptName . '.' . $self->{'hostname'} . '.procinfo');
    my $firstLine = <MYPROCINFOFILE>;
    close(MYPROCINFOFILE);

    chomp $firstLine;
    #$self->_log('fl2 ' . $firstLine);
    if ($firstLine =~ /^$$ 1$/) {
      my $runOneProcess = new Sanity::RunOneProcessNFS($scriptName);
      if ($runOneProcess->{'status'} == 1) {
        $self->{'status'} = 1;
      }
    }
  }

  if ($self->{'status'} != 1) {
    die('Mutex Fault: activeProcInfoFileCount = ' . $activeProcInfoFileCount . ', scriptName = ' . $scriptName . ', hostname = ' . $self->{'hostname'});
  }

  return $self;
}

sub status {
  my ($self) = shift;
  return $self->{'status'};
}

sub amIOnAnActiveNode {
  my ($self) = @_;
  # get state of node with hostname running this script
  my $hostname = $self->{'hostname'};
 
  # sanitize host name, just to be safe
  $hostname =~ s/[^A-z0-9]//;

  my $nodeState = `/usr/cluster/bin/clresourcegroup status Apache-IPC | grep $hostname | sed "s/Apache-IPC//"`;
  chomp $nodeState;

  # remove leading spaces from $nodeState
  $nodeState =~ s/^\s+//;

  my @nodeStateArray = split(/\s+/,$nodeState);
  $nodeState = $nodeStateArray[2];
  if ($nodeState =~ /^Online$/) {
    return 1;
  } 
  return 0;
}

# for debugging...
sub _log {
  my ($self,$message) = @_;
  chomp $message;
  my $fh = $self->{'logfile'};

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
  my $timestamp = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec;
  print $fh '[' . $timestamp . '] [' . $self->{'hostname'} . '|' . $$ . '] ' . $message . "\n";
}



sub DESTROY {
  my ($self) = shift;
  unlink $self->{'procInfoFile'};
  close($self->{'logfile'});
}


1;
