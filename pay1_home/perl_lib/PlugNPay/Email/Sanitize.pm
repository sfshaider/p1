package PlugNPay::Email::Sanitize;

use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub sanitize {
  my $self = shift;
  my $emailAddress = shift;

  if (ref($self) ne 'PlugNPay::Email::Sanitize' && !defined $emailAddress) {
    $emailAddress = $self;
  }

  if (!defined $emailAddress) {
    return;
  }

  # should only be one emailAddressaddress
  $emailAddress =~ s/(.*?)@(.*?),.*/$1\@$2/;

  # strip out characters not allowed in emails
  $emailAddress =~ s/[<>!\$\%\(\):;\\\`\|]//g;

  # strip out any non-allowed quotes in local part
  while ($emailAddress =~ /^(.).*".*(.)@/) {
    $emailAddress =~ s/^(..*?)"(.*.@)/$1$2/;
  }

  # strip out quotes in domain
  while ($emailAddress =~ /@.*"/) {
    $emailAddress =~ s/(@.*)"/$1/;
  }

  # remove commas, etc if not quoted before the @
  if ($emailAddress !~ /^".*?"@.*/) {
    $emailAddress =~ s/,//g;
  }

  return $emailAddress;
}

1;
