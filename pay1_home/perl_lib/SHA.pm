package SHA;

# Compatibility wrapper.  Wraps PlugNPay::Util::Hash to look like old SHA library.
# Logs calls to SHA so that they can be updated to use PlugNPay::Util::Hash

use PlugNPay::Util::Hash;
use PlugNPay::Sys::Time;


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  $self->{'pnphash'} = new PlugNPay::Util::Hash();

  return $self;
}

sub add {
  my $self = shift;
  my $data = shift;
  $self->{'pnphash'}->add($data);
}

sub reset {
  my $self = shift;
  $self->{'pnphash'}->reset();
}

sub hexhash {
  my $self = shift;
  my $data = shift;

  $self->reset();
  $self->add($data);
  return $self->hexdigest();
}

sub hexdigest {
  my $self = shift;
  my $hash = $self->{'pnphash'}->sha1('0x');

  my $t = new PlugNPay::Sys::Time();
  my $timeStamp = $t->nowInFormat('log_local');

  # we only want the date portion of the timestamp and we want to turn
  # slashes (/) into dashes (-)
  $timeStamp =~ s/\//\-/g;
  $timeStamp =~ s/\s.*//;

  open(SHAMODULELOG,'>>/home/p/pay1/logs/sha_module_log.' . $timeStamp . '.log');
  print SHAMODULELOG 'SHA.pm called from: ' . join(' : ', caller()) . "\n";
  close(SHAMODULELOG);

  # SHA.pm returns a hash with a space after every 8 characters
  # so we go through the returned hash and replicate this.

  my $spacedHash = '';
  for (my $i = 7; $i < length($hash); $i += 8) {
    $spacedHash .= substr($hash,$i - 7, 8) . ' ';
  }

  # remove trailing spaces
  $spacedHash =~ s/\s+$//;

  return $spacedHash;
}


1;

