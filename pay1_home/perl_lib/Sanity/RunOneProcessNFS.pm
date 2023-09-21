#!/usr/bin/perl -w

use strict;
use Sys::Hostname;

package Sanity::RunOneProcessNFS;


sub new {
  my ($self,$scriptName) = @_;
  $scriptName =~ s/[^A-z0-9\.]//g;
  my %hash;
  $self = \%hash;

  bless $self,'Sanity::RunOneProcessNFS';

  $self->{'procInfoDirectory'} = '/home/p/pay1/run';

  $self->{'procInfoFile'} = $self->{'procInfoDirectory'} . '/' . $scriptName . '.procinfo';

  my $rand = int(rand(65535));

  # append pid to procinfo file
  open(PROCINFOFILE,'>>' . $self->{'procInfoFile'});
  print PROCINFOFILE $$ . ' ' . $rand . "\n";
  close(PROCINFOFILE);


  # sleep a few seconds to make sure the i/o flushes to the nfs server
  select(undef,undef,undef,2.0);

  $self->{'status'} = 0;

  if (-e $self->{'procInfoFile'}) {
    open(PROCINFOFILE,$self->{'procInfoFile'});
    my $firstLine = <PROCINFOFILE>;
    close(PROCINFOFILE);

    chomp $firstLine;
    if ($firstLine == $$ . ' ' . $rand) {
      $self->{'status'} = 1; 
    }
  }

  if ($self->{'status'} != 1) {
    die('Another ' . $scriptName . ' process is already running.');
  }

  # if this process is the winner, sleep to make sure another process can check the file before possibly ending script execution and thereby removing the procinfo file
  select(undef,undef,undef,2.0);

  return $self;
}

sub status {
  my ($self) = shift;
  return $self->{'status'};
}



sub DESTROY {
  my ($self) = shift;
  if ($self->{'status'}) { unlink $self->{'procInfoFile'} };
}


1;
