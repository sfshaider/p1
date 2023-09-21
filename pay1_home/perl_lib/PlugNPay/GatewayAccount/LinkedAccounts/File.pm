package PlugNPay::GatewayAccount::LinkedAccounts::File;

use strict;

use PlugNPay::WebDataFile;
use PlugNPay::Util::Cache::TimerCache;

our $fileCache;

if (!defined $fileCache) {
  $fileCache = new PlugNPay::Util::Cache::TimerCache(900);
}

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub linkedAccounts {
  my $self = shift;
  my $input = shift || $self;
  my $gatewayAccount = $input->{'gatewayAccount'};
  my $login = $input->{'login'};
  my $definition  = $input->{'linkedAccountDefinition'};
  my $linkedListFeatureValue = lc $input->{'linkedListFeatureValue'};

  my %linked;
  $linked{"$gatewayAccount"} = 1; # quoted to enfoce string context

  my $contents;
  if (!($contents = $fileCache->get($definition))) {
    my $fileMigrator = new PlugNPay::WebDataFile();
    $contents = $fileMigrator->readFile({
      'fileName'   => $definition . '.txt',
      'storageKey'  => 'linkedAccounts',
    });
    $fileCache->set($definition,$contents);
  }

  foreach my $line (split("\n", $contents)) {
    my $lineInfo;
    $line =~ s/^\s+//;    # remove leading space
    $line =~ s/\s+#.*$//; # remove comments

    my $parseMode = '';
    if ($line =~ /^\s+$/) { # skip blank lines
      next;
    } elsif ($line =~ /\w,\w/) { # comma separated
      $parseMode = 'comma';
      $lineInfo = parseCommaFormat($line);
    } elsif ($line =~ /\w\s+\w/) { # space separated
      $parseMode = 'space';
      $lineInfo = parseSpaceFormat($line);
    } else { # in the middle of one night, miss clavel turned on the light and said "SOMETHING IS NOT RIGHT"
      next;
    }

    if ($linkedListFeatureValue eq 'all') {
      $linked{$lineInfo->{'canBeSeen'}} = 1;
      next;
    }

    if ($lineInfo->{'byLogin'} eq $login) { # do *not* check for the linked_list value to be "yes", if you don't want
      $linked{$lineInfo->{'canBeSeen'}} = 1;# the account to show up, remove it from the file.
      next;
    }

    if ($parseMode eq 'comma' && $lineInfo->{'byAccount'} eq $gatewayAccount && $lineInfo->{'byLogin'} eq '') {
      $linked{$lineInfo->{'canBeSeen'}} = 1;
      next;
    }
  }


  my @l = keys %linked;
  return \@l;
}

sub parseCommaFormat {
  my $line = shift; # array ref of lines
  my ($canBeSeen,$byAccount,$byLogin) = split(/,/,$line);
  return { canBeSeen => $canBeSeen, byAccount => $byAccount, byLogin => $byLogin };
}

sub parseSpaceFormat {
  my $line = shift;
  my ($canBeSeen,$byLogin) = split(/\s+/,$line);
  return { canBeSeen => $canBeSeen, byLogin => $byLogin };
}

1;
