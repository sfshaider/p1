package PlugNPay::Legacy::Transflags;
#
# Object for storing transflags. Acts as a sorted comma separated string when necessary.
# 
# concatenation preserves the object, however direct assignment and regex operations convert the object to a string
# ex: 
#   $transflags =~ s/(,bar|bar,)//; 
# will result in $transflags becoming a string instead of an object.
#
#   $tranfglags = 'baz';
# will result in $transflags becoming the string 'baz' even if it was previously an object
# 
# Allows for transflag storage as a bitmap and conversion to a string

use strict;
use PlugNPay::ConfigService;

use overload 'failback' => 0,
  '""' => 'toLegacyString',
  'eq' => 'toLegacyString',
  'ne' => 'toLegacyString',
  '~~' => 'toLegacyString',
  'qr' => 'toLegacyString',
  '.' => 'addLegacyStringFlagAndReturn',
  '.=' => 'addLegacyStringFlagAndReturn',
  'nomethod' => 'overloadCatchall'
;

our $transflagSettings;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'flags'} = {};
  return $self;
}

sub addFlag {
  my $self = shift;
  my @flags = @_;
  $self->_addFlag(@flags);
  $self->_fixFlags();
}

sub _addFlag {
  my $self = shift;
  my @flags = @_;

  my $settings = getSettings();

  foreach my $flag (@flags) {
    next if !defined $flag || $flag eq '';
    $flag =~ s/[^a-zA-Z0-9]//g; # remove non alpha-numeric characters
    next if !defined $settings->{'flags'}{$flag};
    $self->{'flags'}{$flag} = 1;
  }
}

sub addLegacyStringFlag {
  my $self = shift;
  my $string = shift;
  $self->addFlag(split(',',$string));
}

sub fromLegacyString {
  my $self = shift;
  my $string = shift;
  $self->removeAllFlags();
  $self->addLegacyStringFlag($string);
}

sub addLegacyStringFlagAndReturn {
  my $self = shift;
  my $string = shift;
  $self->addLegacyStringFlag($string);
  return $self;
}

sub removeFlag {
  my $self = shift;
  my @flags = @_;
  foreach my $flag (@flags) {
    delete $self->{'flags'}{$flag};
  }
}

sub removeAllFlags {
  my $self = shift;
  $self->{'flags'} = {};
}

# returns first flag in array that matches if any input flags are set
sub hasFlag {
  my $self = shift;
  my @flags = @_;

  my $settings = getSettings();

  foreach my $flag (@flags) {
    if (!defined $settings->{'flags'}{$flag}) {
      die('check for invalid transflag: ' . $flag);
    }
    return $flag if $self->{'flags'}{$flag};
  }

  return undef
}

sub getFlags {
  my $self = shift;
  my @flags = keys %{$self->{'flags'} || {}};
  return \@flags;
}

sub getValidFlags {
  my $settings = getSettings();
  my @flags = sort keys %{$settings->{'flags'}};
  return \@flags;
}

sub _fixFlags {
  my $self = shift;
  if ( $self->hasFlag('recinitial') || $self->hasFlag('recinit') ) {
    $self->removeFlag('recinitial','recinit');
    $self->_addFlag('init','recurring');
  }
  if ($self->hasFlag('recur')) {
    $self->removeFlag('recur');
    $self->_addFlag('recurring');
  }
}

sub fromString {
  my $self = shift;
  my $string = shift;

  if ($string =~ /^0x/) {
    $self->fromHexString($string);
  } else {
    $self->fromLegacyString($string);
  }
}

sub fromHexString {
  my $self = shift;
  my $hex = shift;

  $hex =~ s/^0x//; # remove leading hex indicator
  my $val = hex($hex);

  my $mapping = $self->getIntToFlagMapping();

  my $i = 0;
  my @flagInts;

  while ($val > 0) {
    if ($val & 0b1 == 0b1) {
      my $flag = $mapping->{$i};
      $self->addFlag($flag);
    }

    $val = $val >> 1;
    $i++;
  }
}

sub toString {
  my $self = shift;

  if (hexEnabled()) {
    return $self->toHexString();
  }

  return $self->toLegacyString();
}

sub toHexString {
  my $self = shift;
  my $mapping = $self->getFlagToIntMapping();

  my $bitmap = 0;
  foreach my $flag (keys %{$self->{'flags'}}) {
    my $offset = $mapping->{$flag};
    $bitmap = $bitmap | 0b1 << $offset; # there's a star wars joke here somewhere
  }

  return sprintf('0x%X',$bitmap)
}

sub toLegacyString {
  my $self = shift;
  return join(',',sort keys %{$self->{'flags'}});
}

sub getFlagToIntMapping {
  my $settings = getSettings();
  return $settings->{'flags'};
}

sub getIntToFlagMapping {
  my $settings = getSettings();
  my %reversed = map { $settings->{'flags'}{$_} => $_ } keys %{$settings->{'flags'}};
  return \%reversed;
}

sub hexEnabled {
  my $settings = getSettings();
  return $settings->{'hexFormatEnabled'} ? 1 : 0;
}

sub getSettings {
  if (!defined $transflagSettings) {
    my $cs = new PlugNPay::ConfigService();
    my $config = $cs->getConfig({
      apiVersion => 1,
      name => 'globals',
      formatVersion => 1,
      path => 'transaction/transflags'
    });
    $transflagSettings = $config;
  }

  my %settings = %{$transflagSettings}; # create a copy so settings don't get mutated
  return \%settings;
}

sub overloadCatchall {
  my $self = shift;
  my $value = shift;
  my $something = shift;
  my $operation = shift;

  if ($operation eq '=') {
    return $self;
  }

  die("undefined operation on transflags: operation=($operation), value=($value), something=($something)");
}

1;