package PlugNPay::Security;

use strict;
use PlugNPay::Util::UniqueID();


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $sessionGenerator = new PlugNPay::Util::UniqueID();
  $sessionGenerator->generate();
  $self->{'session'} = $sessionGenerator->inHex();

  $self->{'bypass_included'} = 0;

  return $self;
}

sub bypassPrint {
  my $self = shift;
  my $string = shift;

  # filter ouput so nothing nasty happens accidently
  $string =~ s/[^A-Za-z0-9]//g;

  # get left and right parts
  my @parts = unpack('(A4)*',$string);

  return join('<span></span>',@parts);
}

sub postOnly {
  #############################################
  # Check the request method, only allow POST #
  #############################################
  if ($ENV{'REQUEST_METHOD'} ne 'POST') {
    print 'Content-type: text/plain' . "\n\n";
    print $ENV{'REQUEST_METHOD'} . ' is not allowed.' . "\n";
    exit(0);
  }
}

sub bypassSetValue {
  my $self = shift;
 
  my $type = shift;
  my $name = shift;
  my $string = shift;

  $name =~ s/[^A-Za-z0-9_]//g;

  # filter ouput so nothing nasty happens accidently
  $string =~ s/[^A-Za-z0-9]//g;

  # get left and right parts
  my @parts = unpack('(A4)*',$string);

  if ($type eq 'input') {
    return 'jQuery("document").ready(function() { Security.bypassSetInputValue("' . $name . '",["' . join('","',@parts) . '"]); });';
  } elsif ($type eq 'select') {
    return 'jQuery("document").ready(function() { Security.bypassSetSelectValue("' . $name . '",["' . join('","',@parts) . '"]); });';
  }
}
  

sub DESTROY
{
  my $self = shift;
}

1;
