package MD5;

# Compatibility Wrapper around Digest::MD5 for use by plugnpay.
# typical usage:
#     my $md5 = new MD5;
#     $md5->add("$data");
#     my $data_md5 = $md5->hexdigest();

use strict;
use Digest::MD5 qw(md5 md5_hex md5_base64);


sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'data'} = undef;

  return $self;
}

sub add {
  my $self = shift;
  my $data = shift;

  $self->{'data'} .= $data;
}

sub hexdigest {
  my $self = shift;

  return md5_hex($self->{'data'});
}

sub reset {
  my $self = shift;
  $self->{'data'} = undef;
}

1;
