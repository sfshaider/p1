package PlugNPay::Password;

use strict;
use PlugNPay::Username;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setOldPassword {
  my $self = shift;
  my $password = shift;
  $self->{'oldPassword'} = $password;
}

sub getOldPassword {
  my $self = shift;
  return $self->{'oldPassword'};
}


sub setNewPassword {
  my $self = shift;
  my $password = shift;
  $self->{'newPassword'} = $password;
}

sub getNewPassword {
  my $self = shift;
  return $self->{'newPassword'};
}

sub qualityCheck {
  my $self = shift;
  
  my %failures;

  $failures{'lowercase'} = 1 if $self->getNewPassword() !~ /[a-z]/;
  $failures{'uppercase'} = 1 if $self->getNewPassword() !~ /[A-Z]/;
  $failures{'numeric'}   = 1 if $self->getNewPassword() !~ /[0-9]/;

  if (defined $self->getOldPassword()) {
    $failures{'oldpassword'} = 1 if $self->containsMatchingSubstrings($self->getOldPassword(),$self->getNewPassword());
  }

  $failures{'username'} = 1 if $self->containsMatchingSubstrings($self->getNewPassword(),$self->getUsername(),{caseInsensitive => 1, substringLength => 5});
  my $reversedUsername = reverse $self->getUsername();
  $failures{'username'} = 1 if $self->containsMatchingSubstrings($self->getNewPassword(),$reversedUsername,{caseInsensitive => 1, substringLength => 5});

  $failures{'repeating'} = 1 if $self->containsRepeatingCharacters($self->getNewPassword());

  $failures{'length'} = 1 if (length($self->getNewPassword()) < 10);

  # look for alphabetic and numeric sequences
  my $abc = 'abcdefghijklmnopqrstuvwxyzab';
  my $abcReversed = reverse $abc;

  $failures{'alphabeticsequence'} = 1 if $self->containsMatchingSubstrings($abc,$self->getNewPassword(),{caseInsensitive => 1});
  $failures{'alphabeticsequence'} = 1 if $self->containsMatchingSubstrings($abcReversed,$self->getNewPassword(),{caseInsensitive => 1});

  my $onetwothree = '012345678901';
  my $onetwothreeReversed = reverse $onetwothree;

  $failures{'numericsequence'}    = 1 if $self->containsMatchingSubstrings($onetwothree,$self->getNewPassword());
  $failures{'numericsequence'}    = 1 if $self->containsMatchingSubstrings($onetwothreeReversed,$self->getNewPassword());

  return keys %failures;
}

sub containsMatchingSubstrings {
  my $self = shift;
  my $string1 = shift;
  my $string2 = shift;
  my $settings = shift;

  my $substringLength = 3;

  if (ref $settings eq 'HASH') {
    $substringLength = $settings->{'substringLength'} || $substringLength;

    if ($settings->{'caseInsensitive'} == 1) {
      $string1 = lc $string1;
      $string2 = lc $string2;
    }
  }

  if (length $string2 >= $substringLength) {
    for (my $i = 0; $i < (length($string1) - $substringLength - 1); $i++) {
      my $substring = substr($string1,$i,$substringLength);
      return (index($string2,$substring) >= 0);
    } 
  }
 
  # substring of old password was not found in new password
  return 0;
}

sub containsRepeatingCharacters {
  my $self = shift;
  my $string = shift;

  my %characters = map { $_ => 1 } split(//,$string);

  foreach my $character (keys %characters) {
    $character = $character x 3;
    return (index($string,$character) >= 0);
  }

  return 0;
}

1;
