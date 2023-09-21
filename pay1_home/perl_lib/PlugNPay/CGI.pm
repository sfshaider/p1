use CGI;

package PlugNPay::CGI;

# only ever create one CGI object
our $singleton; 

# variable to store the status of redefining CGI::new
our $redefined;

# Only redefine the CGI::new subroutine once.
if (!$redefined) {
  *CGI::originalNew = \&CGI::new;
  *CGI::new = sub { 
    shift @_; # strip off the package name
    # pass all arguments to the newPreserve subroutine.
    PlugNPay::CGI::newPreserve(@_) 
  }; 
  $redefined = 1;
}

sub new {
  if (defined $singleton) {
    return $singleton;
  }

  my $class = shift;
  my $self = {};
  bless $self,$class;

  # we have to clear $singleton for every request in mod_perl
  if (!exists $self->{'handlerSet'} && exists $ENV{'MOD_PERL'}) {
    require Apache2::RequestUtil;
    my $r;

    eval {
      $r = Apache2::RequestUtil->request;
    };

    if ($r) {
      if (defined $r->connection()->keepalive) {
        $r->connection()->keepalive($Apache2::Const::CONN_CLOSE);
      }
      $r->push_handlers(PerlCleanupHandler => sub {&cleanup()});
      $self->{'handlerSet'} = 1;
    }
  }


  # if there are no arguments, initialize CGI from query string or STDIN
  # otherwise init with arguments
  if (!@_) {
    if ($ENV{'CONTENT_TYPE'} =~ /multipart\/form-data/) {
      $self->{'cgi'} = originalNew CGI();
    }else{
      my $data;
      if ((uc $ENV{'REQUEST_METHOD'}) eq 'GET') {
        $data = $ENV{'QUERY_STRING'};
      } else {
        my $contentLength = $ENV{'CONTENT_LENGTH'} || 0;
        read(STDIN,$data,$contentLength,0);
      }
  
      $self->{'raw'} = $data;
 
      # pass all arguments to the old CGI::new method.
      $self->{'cgi'} = originalNew CGI($data);
    }
  } else {
    $self->{'cgi'} = originalNew CGI(@_);
  }

  $singleton = $self;

  return $self;
}

sub clearCGI {
  my $self = shift;
  delete $self->{'cgi'};
}

# forward all subroutine calls meant for CGI to the CGI object.
sub AUTOLOAD {
  my $self = shift;
  my $sub = $AUTOLOAD;
  $sub =~ s/.*:://g;
  return $self->{'cgi'}->$sub(@_);
}

sub getRaw {
  my $self = shift;
  return $self->{'raw'};
}

sub newPreserve {
  # forward all arguments to the CGI::Preserve object
  return new PlugNPay::CGI(@_);
}

sub DESTROY {
  my $self = shift;
  $self->{'cgi'} = undef;
}

END {
  cleanup();
}

sub cleanup {
  if (defined $singleton && ref($singleton) eq 'PlugNPay::CGI') {
    $singleton->clearCGI();
  }
  $singleton = undef;
}

1;
