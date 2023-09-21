package PlugNPay::Merchant::VerificationHash::Digest;

use strict;
use PlugNPay::Sys::Time;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Util::Hash;
use PlugNPay::Util::Status;

# returns a PlugNPay::Util::Status object
sub validate {
  my $input = shift;

  my $type = $input->{'type'};
  my $settings = $input->{'settings'};
  my $sourceData = $input->{'sourceData'};
  my $digest = $input->{'digest'};
  my $hashTimeString = $input->{'hashTimeString'};
  my $digestType = $input->{'digestType'};
  my $startTime = $input->{'startTime'};
  my $endTime = $input->{'endTime'};


  my $inputStatus = checkInput($input);
  if (!$inputStatus) {
    return $inputStatus;
  }

  my $startTimeString = '';

  my $digestData = createDigestData({
    sortFields => $settings->{'sortFields'},
    fields => $settings->{'fields'},
    sourceData => $sourceData
  });

  if ($type eq 'inbound') {

    $startTimeString = $startTime->inFormat('gendatetime');

    my $expired = expired({
      timeout => $settings->{'timeout'},
      startTime => $startTime,
      endTime => $endTime
    });

    if ($expired) {
      my $status = new PlugNPay::Util::Status(0);
      $status->setError("digest created outside of allowed time window");
      return $status;
    }
  }

  my $digestedData = digest({
    secret => $settings->{'secret'},
    hashTimeString => $hashTimeString,
    digestData => $digestData
  });

  my $digestMatches = checkDigests({
    digestedData => $digestedData,
    digestType => $digestType,
    digest => $digest
  });

  return $digestMatches;
}

sub checkInput {
  my $input = shift;

  my $type = $input->{'type'};
  my $settings = $input->{'settings'};
  my $sourceData = $input->{'sourceData'};
  my $digest = $input->{'digest'};
  my $digestType = $input->{'digestType'};
  my $startTime = $input->{'startTime'};
  my $endTime = $input->{'endTime'};

  my $status = new PlugNPay::Util::Status(0);

  my $timeStatus = checkTimes({
    startTime => $startTime,
    endTime => $endTime
  });

  if (!$timeStatus) {
    return $timeStatus;
  }

  my $settingsStatus = checkSettings({
    type => $type,
    settings => $settings
  });

  if (!$settingsStatus) {
    return $settingsStatus;
  }

  $status->setTrue();
  return $status;
}

sub checkTimes {
  my $input = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $startTime = $input->{'startTime'};
  my $endTime = $input->{'endTime'};

  if (ref($startTime) ne 'PlugNPay::Sys::Time') { 
    $status->setFalse();
    $status->setError('startTime is of incorrect type');
    return $status;
  }

  if (ref($endTime) ne 'PlugNPay::Sys::Time') { 
    $status->setFalse();
    $status->setError('endTime is of incorrect type');
    return $status;
  }

  return $status;
}

sub checkSettings {
  my $input = shift;
  my $type = $input->{'type'};
  my $settings = $input->{'settings'};

  my $status = new PlugNPay::Util::Status(1);

  if (!inArray($type,['inbound','outbound'])) {
    $status->setFalse();
    $status->setError('invalid verification hash type');
    return $status;
  }

  my $fields = $settings->{'fields'};
  if (ref($fields) ne 'ARRAY') {
    $status->setFalse();
    $status->setError('bad fields input');
    return $status;
  }

  if (@{$fields} < 1) {
    $status->setFalse();
    $status->setError('invalid number of fields in settings');
    return $status;
  }

  if (length($settings->{'secret'}) < 8) {
    $status->setFalse();
    $status->setError('insufficient secret length');
    return $status;
  }

  if ($type eq 'inbound' && !validTimeout($settings->{'timeout'})) {
    $status->setFalse();
    $status->setError('invalid timeout/delay for verification window');
  }

  return $status;
}

sub expired {
  my $input = shift;

  my $timeout = $input->{'timeout'};

  die('timeout input is not defined') if !defined $timeout;

  my $startTime = new PlugNPay::Sys::Time();
  $startTime->copyFrom($input->{'startTime'});

  my $endTime = new PlugNPay::Sys::Time();
  $endTime->copyFrom($input->{'endTime'});

  my $expiresAt = $startTime;
  $expiresAt->addSeconds($timeout);

  # add one minute to end time to allow for clock differences
  $endTime->addSeconds(60);

  my $status = new PlugNPay::Util::Status(0);
  if ($expiresAt->isBefore($startTime)) {
    $status->setTrue();
    $status->setError('verification hash timestamp is before allowed window');
    return $status;
  }

  if ($expiresAt->isAfter($endTime)) {
    $status->setTrue();
    $status->setError('verification hash timestamp is after allowed window');
    return $status;
  }

  return $status;
}

sub validTimeout {
  my $timeout = shift;
  return (defined $timeout && $timeout > 0);
}

sub createDigestData {
  my $input = shift;

  my $fields = $input->{'fields'};
  my $sortFields = $input->{'sortFields'} ? 1 : 0;
  my $sourceData = $input->{'sourceData'};

  die('fields input is not defined') if !defined $fields;
  die('sourceData input is not defined') if !defined $sourceData;

  if ($sortFields) {
    my @sortedFields = sort @{$fields};
    $fields = \@sortedFields;
  }
  
  my $digestData = '';
  foreach my $field (@{$fields}) {
    my $data = $sourceData->{$field} || '';
    $digestData .= $data;
  }
  return $digestData;
}

sub digest {
  my $input = shift;

  my $secret = $input->{'secret'};
  my $hashTimeString = $input->{'hashTimeString'} || '';
  my $digestData = $input->{'digestData'};

  die('secret input is not defined') if !defined $secret;
  die('digestData input is not defined') if !defined $digestData;

  my $fullDigestData = $secret . $hashTimeString . $digestData;

  my $digestor = new PlugNPay::Util::Hash();
  $digestor->add($fullDigestData);

  my $result = {
    md5Sum => $digestor->MD5('0x'),
    sha256Sum => $digestor->sha256('0x')
  };

  return $result;
}

sub checkDigests {
  my $input = shift;

  my $digestedData = $input->{'digestedData'};
  my $digestType = $input->{'digestType'} || 'any';
  my $digest = $input->{'digest'};

  die('digestedData input is not defined') if !defined $digestedData;
  die('digest input is not defined') if !defined $digest;

  my $status = new PlugNPay::Util::Status(0);

  if (inArray($digestType,['md5Sum','any']) && $digest eq $digestedData->{'md5Sum'}) {
    $status->setTrue();
    return $status;
  }

  if (inArray($digestType,['sha256Sum','any']) && $digest eq $digestedData->{'sha256Sum'}) {
    $status->setTrue();
    return $status;
  }

  $status->setError('digest did not match any possible results');

  return $status;
}

1;