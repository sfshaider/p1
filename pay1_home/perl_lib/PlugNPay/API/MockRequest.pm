package PlugNPay::API::MockRequest;

# emulates Apache::RequestUtil->request and adds content
use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setResource {
  my $self = shift;
  my $resource = shift;
  $self->{'resource'} = $resource;
}

sub setMethod {
  my $self = shift;
  my $method = uc shift;
  $self->{'method'} = $method;
}

sub setContent {
  my $self = shift;
  my $content = shift;
  $self->{'content'} = $content;
  $self->addHeaders({ 'content-length' => length($content) });
}

sub addHeaders {
  my $self = shift;
  my $input = shift;

  $self->{'headers'} = {} if !defined $self->{'headers'};

  foreach my $key (keys %{$input}) {
    $self->{'headers'}{lc $key} = $input->{$key};
  }
}

sub clearHeaders {
  my $self = shift;
  delete $self->{'headers'};
}

# the_request in Apache::RequestUtil->request returns the request string in the form of
#   <METHOD> <resource> <protocol>
# We really don't care about protocol or the method here.  the method is derived from the headers.
sub the_request {
  my $self = shift;
  return sprintf('%s %s x', $self->{'method'} || 'GET', $self->{'resource'});
}

# method in Apache::RequestUtil->request returns the method of the request
sub method {
  my $self = shift;
  return $self->{'method'} || 'GET';
}

# headers_in in Apache::RequestUtil->request returns a hash ref of the input headers for the request
# Important ones to have here are the authentication headers
sub headers_in {
  my $self = shift;
  return $self->{'headers'};
}

sub mockContent {
  my $self = shift;
  return $self->{'content'};
}


1;
