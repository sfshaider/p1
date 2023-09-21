package PlugNPay::Legacy::MckUtils::Links;

use strict;
use warnings FATAL => 'all';
use PlugNPay::Die;

sub generateLinksForSlashPay {
  my $inputData = shift;
  if (!defined $inputData || ref($inputData) ne 'HASH') {
    die 'Invalid input passed into link validation';
  }

  # if transaction input is not sent, we should die
  my $transactionParameterInput = $inputData->{'transactionParameterInput'};
  if (!defined $transactionParameterInput || ref($transactionParameterInput) ne 'HASH') {
    die 'Invalid transactionParameterInput passed into link validation';
  }

  # fields to set if they are blank
  my @linkFields;
  push @linkFields, 'badcard-link';
  push @linkFields, 'problem-link';

  # if we the fields have underscores, convert the hyphens in the linkFields array to underscores
  my $conversionFlag = $transactionParameterInput->{'convert'} || '';
  if (defined $conversionFlag && $conversionFlag eq 'underscores') {
    my $converted = convertLinkFieldNamesFromHyphensToUnderscores(\@linkFields);
    @linkFields = @{$converted};
  }

  # if any of the link fields are empty and force receipt is not "yes", then generate one
  foreach my $linkField (@linkFields) {
    my $shouldForceReceiptFlag = $transactionParameterInput->{'pb_force_receipt'} || '';
    my $transactionInputToCheck = {
      'transactionParameterInput' => $transactionParameterInput->{$linkField},
      'shouldForceReceipt' => $shouldForceReceiptFlag
    };

    if (shouldGenerateLinkForField($transactionInputToCheck)) {
      my $serverInputData = {
        'serverName' => $inputData->{'serverName'},
        'serverPort' => $inputData->{'serverPort'}
      };
      $transactionParameterInput->{$linkField} = getDefaultLinkForSlashPay($serverInputData);
    }
  }

  # return all input, including formatted or generated links
  return $transactionParameterInput;
}

sub shouldGenerateLinkForField {
  my $transactionInputToCheck = shift;
  if (!defined $transactionInputToCheck || ref($transactionInputToCheck) ne 'HASH') {
    die 'invalid transaction input sent to linkGeneration condition function';
  }

  my $transactionParameterInput = $transactionInputToCheck->{'transactionParameterInput'};
  my $shouldForceReceiptFlag = $transactionInputToCheck->{'shouldForceReceipt'};

  my $isNotDefinedOrIsFalse = !defined $transactionParameterInput || $transactionParameterInput eq '';
  my $shouldNotForceReceipt = $shouldForceReceiptFlag ne 'yes';
 
  return $isNotDefinedOrIsFalse && $shouldNotForceReceipt;
}

# Generates a default link to slash pay
sub getDefaultLinkForSlashPay {
  my $serverAndPortValueInput = shift;
  if (!defined($serverAndPortValueInput) || ref($serverAndPortValueInput) ne 'HASH') {
    die 'invalid data passed to link creation';
  }

  my $serverName = $serverAndPortValueInput->{'serverName'} || '';
  my $serverPort = $serverAndPortValueInput->{'serverPort'};

  my $link = '';
  if (!defined $serverPort || $serverPort == 443 || $serverPort eq '' ) {
    $link = 'https://' . $serverName . '/pay/';
  } else {
    $link = 'https://' . $serverName . ':' . $serverPort . '/pay/';
  }

  return $link;
}

#Converts hypens to underscores for link key in map, does not convert actual link
sub convertLinkFieldNamesFromHyphensToUnderscores {
  my $originalLinksArrayRef = shift;

  if (!defined($originalLinksArrayRef) || ref($originalLinksArrayRef) ne 'ARRAY') {
    die 'Invalid input passed into link hypen conversion';
  }
  
  my @convertedLinks = ();
  foreach my $link (@{$originalLinksArrayRef}) {
    $link =~ s/-/_/g;
    push @convertedLinks, $link;
  }

  return \@convertedLinks;
}

1;
