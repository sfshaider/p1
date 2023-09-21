package PlugNPay::Util::IP;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub validateIPv4Address {
  my $self = shift;
  my $address = shift;

  my $originalAddress = $address;
  $address =~ s/[^\d\.]//g;

  if ($originalAddress ne $address) {
    return 0;
  }

  my @parts = split(/\./,$address);
  
  if (@parts != 4) {
    return 0;
  }

  foreach my $part (@parts) {
    if ($part > 255) {
      return 0;
    }
  }

  # all tests passed.
  return 1;
}

1;
