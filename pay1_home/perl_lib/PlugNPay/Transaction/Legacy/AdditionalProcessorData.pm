package PlugNPay::Transaction::Legacy::AdditionalProcessorData;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Processor::Network;
use PlugNPay::Die;

# Usage examples
#
# Create auth code string:
#
# my $authCode = new PlugNPay::Transaction::Legacy::AdditionalProcessorData({ 'processorId' => '142' });
# $authCode->setField('appcode', $approvalNumber);
# $authCode->setField('nettransid', $networkTransactionId);
# my $authCodeString = $authCode->getAdditionalDataString();
#
# Get data from auth code string:
#
# my $authCode = new PlugNPay::Transaction::Legacy::AdditionalProcessorData({ 'processorId' => '142' });
# $authCode->setAdditionalDataString($authCodeString);
# my $appcode = $authCode->getField('appcode');

our $cache = {};

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $settings = shift;
  if (ref($settings) eq 'HASH') {
    my $processorId = $settings->{'processorId'};

    if ($processorId) { # preferred
      $self->setProcessorId($processorId);
    }
  }

  return $self;
}

sub setProcessorId {
  my $self = shift;
  my $processorId = shift;
  $processorId =~ s/[^0-9]//g;

  $self->{'processorId'} = $processorId;
}

sub getProcessorId {
  my $self = shift;
  if (!defined $self->{'processorId'}) {
    die('Processor Id not set!');
  }

  return $self->{'processorId'};
}

sub setAdditionalDataString {
  my $self = shift;
  my $additionalDataString = shift;
  $self->{'additionalDataString'} = $additionalDataString;
}

sub getAdditionalDataString {
  my $self = shift;
  if (!defined $self->{'additionalDataString'}) {
    die('Additional data string is undefined.');
  }

  return $self->{'additionalDataString'};
}

sub setField {
  my $self = shift;
  my $fieldName = shift;
  my $fieldValue = shift;

  my $fieldInfo = $self->getFieldInfo($fieldName);

  if (!defined $fieldInfo) {
    return
  }

  my $start = $fieldInfo->{'start'};
  my $length = $fieldInfo->{'length'};
  my $pad = $fieldInfo->{'pad'};
  my $padLocation = $fieldInfo->{'padLocation'};
  my $value;

  # check if value is too long
  if (length($fieldValue) > $length) {
    die('Field value is too long.');
  }

  # add field padding
  if ($padLocation eq 'L') {
    $value = substr($pad x ($length - length($fieldValue)) . $fieldValue, 0, $length);
  } elsif ($padLocation eq 'R') {
    $value = substr($fieldValue . $pad x $length, 0, $length);
  }

  # add string padding if necessary
  my $stringLength = length($self->{'additionalDataString'});
  if ($stringLength < $start) {
    my $paddingLength = $start - $stringLength;
    substr($self->{'additionalDataString'}, $stringLength, $paddingLength) = " " x $paddingLength, 0;
  }

  substr($self->{'additionalDataString'},$start,$length) = $value;
}

sub hasField {
  my $self = shift;
  my $fieldName = shift;

  my $has = 0;
  eval {
    my $fieldInfo = $self->getFieldInfo($fieldName);
    $has = 1;
  };

  return $has;
}

sub getField {
  my $self = shift;
  my $fieldName = shift;

  my $dataString = $self->getAdditionalDataString();
  my $fieldInfo = $self->getFieldInfo($fieldName);

  my $start = $fieldInfo->{'start'};
  my $length = $fieldInfo->{'length'};
  my $value = substr($dataString, $start, $length);

  my $pad = $fieldInfo->{'pad'};
  my $padLocation = $fieldInfo->{'padLocation'};

  if ($pad ne '') {
    # remove pad
    if ($padLocation eq 'L') {
      $value =~ s/^$pad+//;
    } elsif ($padLocation eq 'R') {
      $value =~ s/$pad+$//;
    }
  }

  if (lc($fieldName) eq 'processed_network_id') {
    my $mapper = new PlugNPay::Processor::Network({'processor' => $self->getProcessorId()});
    $value = $mapper->getNetworkName($value, $self->getProcessorId());
  }

  return $value;
}

sub getFieldInfo {
  my $self = shift;
  my $fieldName = shift;

  if (!defined $fieldName) {
    die('Field name not specified!');
  }

  my $processorId = $self->getProcessorId();
  if (!defined $cache->{$processorId}) {
    $self->loadFieldInfo();
  }

  my $specificFieldInfo = $cache->{$processorId}{$fieldName};

  if (!defined $specificFieldInfo) {
    die('Field information is not defined.');
  }

  return $specificFieldInfo;
}

sub hasFieldInfo {
  my $self = shift;
  my $processorId = $self->getProcessorId();

  if (!defined $cache->{$processorId}) {
    $self->loadFieldInfo();
  }

  my $fieldInfo = $cache->{$processorId};
  return (defined $fieldInfo);
}

sub loadFieldInfo {
  my $self = shift;
  my $processorId = $self->getProcessorId();

  my $dbs = new PlugNPay::DBConnection();
  my $result = undef;

  eval { # don't log error here...that will be taken care of once PlugNPay::Die gets written :D
    $result = $dbs->fetchallOrDie('pnpmisc',q/
      SELECT `field_name`, `order`, `length`,`pad`,`pad_location`
        FROM processor_legacy_additional_data_map
       WHERE processor_id = ?
       ORDER BY `order`
    /,[$processorId],{});
  };

  my $processedFieldInfo = undef;

  if ($result) {
    my $translatedNames = $self->_loadMappedNames($processorId);
    $processedFieldInfo = {};
    my $index = 0;
    foreach my $fieldInfoRow (@{$result->{'result'}}) {
      my $order = $fieldInfoRow->{'order'};
      my $processorFieldName = $fieldInfoRow->{'field_name'};
      my $fieldName = $translatedNames->{$processorFieldName} || $processorFieldName;
      my $length = $fieldInfoRow->{'length'};
      my $start = $index;
      my $end = $index + $length - 1;
      my $pad = $fieldInfoRow->{'pad'};
      my $padLocation = $fieldInfoRow->{'pad_location'};
      
      $processedFieldInfo->{$fieldName} = {
          fieldName => $fieldName,
             length => $length,
              start => $start, 
                end => $end,
              order => $order,
                pad => $pad,
        padLocation => $padLocation
      };
      $index = $end + 1;
    }

    $cache->{$processorId} = $processedFieldInfo;
  } else {
    die('Failed to load field info for processorId[' . $processorId . ']');
  }
}

sub _loadMappedNames {
  my $self = shift;
  my $processorId = shift || $self->getProcessorId();
  
  my $select = q/
    SELECT processor_field_name, field_name, processor_id
      FROM processor_legacy_data_field_name_map
     WHERE processor_id = ?
  /;

  my $map = {};
  eval {
    my $dbs = new PlugNPay::DBConnection();
    my $rows = $dbs->fetchallOrDie('pnpmisc', $select, [$processorId], {})->{'result'};
    foreach my $row (@{$rows}) {
      $map->{$row->{'processor_field_name'}} = $row->{'field_name'};
    }
  };

  #Log to PNPDie or whatever

  return $map;
}

1;
