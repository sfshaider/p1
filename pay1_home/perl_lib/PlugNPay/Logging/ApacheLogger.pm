package PlugNPay::Logging::ApacheLogger;

use strict;
use Exporter;
use JSON::XS;
use PlugNPay::Sys::Time;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(log);
our @EXPORT = qw(log);

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;


  return $self;
}

#Simple wrapper for apache2/STDERR logging 
sub log {
  my ($self,$message) = @_;
  
  if (!defined $message) {
    $message = $self;
  }

  my $time = new PlugNPay::Sys::Time();

  eval{ 
    if (ref($message) eq 'HASH' || ref($message) eq 'ARRAY') {
      $message = encode_json($message);
    }
  };

  eval {
    Apache2::ServerRec::warn($time->nowInFormat('db_gm') . ' - ' . $message);
  };

  print STDERR $time->nowInFormat('db_gm') . ' - ' . $message . "\n" if $@;
  
  return 1;
}

1;
