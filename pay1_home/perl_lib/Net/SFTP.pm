
package Net::SFTP;
use strict;
use Net::SFTP::Foreign::Compat;

sub new {
  shift; # remove object reference
  my $host = shift;
  my (%args) = @_; # the rest
  delete $args{'Debug'};

  foreach my $key (sort keys %args) {
    my $val = $args{$key};
    if ($key eq 'password') {
      $val = 'X' x length($val);
    }
    print "K:$key:$val\n";
  }

  if (exists $args{'Timeout'}) {
    $args{'timeout'} = $args{'Timeout'};
    delete $args{'Timeout'};
  }

  return Net::SFTP::Foreign::Compat->new($host, %args);
}
1;


