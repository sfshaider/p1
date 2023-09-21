package PlugNPay::Client::Bluefin;

use strict;
use warnings FATAL => 'all';
use Types::Serialiser;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::AWS::ParameterStore qw(getParameter);

our $_serviceUrl;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub getServiceEndpoint {
  if (!defined $_serviceUrl || $_serviceUrl eq '') {
    $_serviceUrl = PlugNPay::AWS::ParameterStore::getParameter('/SERVICE/BLUEFIN/URL');
  }

  return $_serviceUrl . '/decrypt';
}

#######################
# Merchant Username
# -----------------
sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

#############################
# General Data Subroutines
# ------------------------
sub getMessageID {
  my $self = shift;
  return $self->{'messageID'};
}

sub getReference {
  my $self = shift;
  return $self->{'reference'};
}

#############################
# Meta Data Subroutines
# ---------------------
sub getDevice {
  my $self = shift;
  return $self->{'device'};
}

sub getSerial {
  my $self = shift;
  return $self->{'serial'};
}

sub getMode {
  my $self = shift;
  return $self->{'mode'};
}

#############################
# Extracted Data subroutines
# --------------------------
sub getFirstName {
  my $self = shift;
  return $self->{'firstName'};
}

sub getSurname {
  my $self = shift;
  return $self->{'surname'};
}

sub getCardNumber {
  my $self = shift;
  return $self->{'cardNumber'};
}

sub getExpirationMonth {
  my $self = shift;
  return $self->{'expirationMonth'};
}

sub getExpirationYear {
  my $self = shift;
  return $self->{'expirationYear'};
}

sub getCVV {
  my $self = shift;
  return $self->{'cvv'};
}

sub getStreetNumber {
  my $self = shift;
  return $self->{'streetNumber'};
}

sub getPostalCode {
  my $self = shift;
  return $self->{'postalCode'};
}

sub getServiceCode {
  my $self = shift;
  return $self->{'serviceCode'};
}

sub getDiscretionary {
  my $self = shift;
  return $self->{'discretionary'};
}

#############################
# Track Data subroutines
# ----------------------
sub getTrack1 {
  my $self = shift;
  my $field = shift;
  my $trackData = $self->{'track1'};
  my $response = $self->getTrackResponse($trackData, $field);
  
  return $response;
}

sub getTrack2 {
  my $self = shift;
  my $field = shift;
  my $trackData = $self->{'track2'};
  my $response = $self->getTrackResponse($trackData, $field);
  
  return $response;
}

sub getTrack3 {
  my $self = shift;
  my $field = shift;
  my $trackData = $self->{'track3'};
  my $response = $self->getTrackResponse($trackData, $field);
  
  return $response;
}

sub getTLV {
  my $self = shift;
  my $field = 'decrypted'; #Currently, only possible field in TLV is decrypted, but is still a hash
  my $trackData = $self->{'tlv'};
  my $response = $self->getTrackResponse($trackData, $field);
  
  return $response;
}

sub getKeyed {
  my $self = shift;
  my $field = shift;
  my $trackData = $self->{'keyed'};
  my $response = $self->getTrackResponse($trackData, $field);
  
  return $response;
}

#This was not used previously, but added for completeness
sub getTrack2Equivalent {
  my $self = shift;
  my $field = shift;
  my $trackData = $self->{'track2Equivalent'};
  my $response = $self->getTrackResponse($trackData, $field);

  return $response;
}

# Gets proper field for track, keyed and TLV data
# Original java microservice returned ASCII field only, except for TLV. 
# New golang microservice returns full response hash, but we should maintain the current functionality by default
sub getTrackResponse {
  my $self = shift;
  my $inputHash = shift;
  my $specificKey = shift;

  if (ref($inputHash) ne 'HASH') {
    return '';
  }

  if (!defined $specificKey || !inArray($specificKey, ['masked', 'ascii', 'length', 'decrypted', 'encoding'])) {
    $specificKey = 'ascii'; # What existing code expected from Java MS, defaulting for backwards compatibility
  }

  return $inputHash->{$specificKey};
}

# Processing Functions
sub decryptSwipe {
  my $self = shift;
  my $deviceSwipe = shift;
  my $options = shift || {};

  my $status = new PlugNPay::Util::Status(1);

  # check the device swipe
  # less than 27 characters indicates a bad swipe and also
  # makes it unable to tell which KSID was used
  if (!$deviceSwipe || length($deviceSwipe) < 27) {
    $status->setFalse();
    $status->setError('invalid swipe');
    return $status;
  }

  # This is necessary for production/cert environments
  # since only one server is necessary to route between them.
  #
  # If the swipe data contains this string 26 characters from the back
  # it will go to the production endpoint
  my $productionKSID = 'FFFF135686';
  my $productionUnit = Types::Serialiser::false;
  if (substr($deviceSwipe, -26, 10) eq $productionKSID) {
    $productionUnit = Types::Serialiser::true;
  }

  my $swipeReference = $options->{'reference'};
  my $request = {
    'devicePayload'  => $deviceSwipe,
    'deviceType'     => 'idtech', # only device we support
    'reference'      => $swipeReference,
    'productionUnit' => $productionUnit
  };

  my $response = {};

  eval {
    my $ms = new PlugNPay::ResponseLink::Microservice();
    $ms->setMethod('POST');
    $ms->setContentType('application/json');
    $ms->setContent($request);
    $ms->setURL(getServiceEndpoint());
    $ms->doRequest();
    $response = $ms->getDecodedResponse();
  };

  if ($@ || $response->{'error'}) {
    $status->setFalse();
    if ($@) {
      $status->setError('An unknown error has occurred, please contact technical support.');

      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'bluefin' });
      $logger->log({
        'gatewayAccount' => $self->getGatewayAccount(),
        'error'          => $@
      });
    } else {
      $status->setError($response->{'errorMessage'});
    }
  } else {
    # if successful, parse response
    $self->_parseDecryptedResponse($response->{'rawResponse'});
  }

  return $status;
}

sub _parseDecryptedResponse {
  my $self = shift;
  my $response = shift;
  # Set fields from micrservice response

  # General Data
  $self->{'messageID'} = $response->{'messageId'};
  $self->{'reference'} = $response->{'reference'};

  # Meta Data
  my $metaData = $response->{'meta'};
  $self->{'device'} = $metaData->{'device'};
  $self->{'serial'} = $metaData->{'serial'};
  $self->{'mode'}   = $metaData->{'mode'};

  # Extracted/Decrypted Data
  my $extractedData = $response->{'extracted'};
  $self->{'firstName'}       = $extractedData->{'firstName'};
  $self->{'surname'}         = $extractedData->{'lastName'};
  $self->{'cardNumber'}      = $extractedData->{'cardNumber'};
  $self->{'expirationMonth'} = $extractedData->{'expirationMonth'};
  $self->{'expirationYear'}  = $extractedData->{'expirationYear'};
  $self->{'cvv'}             = $extractedData->{'cvv'};
  $self->{'postalCode'}      = $extractedData->{'postalCode'};
  $self->{'streetNumber'}    = $extractedData->{'streetNumber'};
  $self->{'serviceCode'}     = $extractedData->{'serviceCode'};
  $self->{'discretionary'}   = $extractedData->{'discretionary'};

  # Track Data
  $self->{'track1'} = $response->{'track1'};
  $self->{'track2'} = $response->{'track2'};
  $self->{'track3'} = $response->{'track3'};
  $self->{'track2Equivalent'} = $response->{'track2Equivalent'};
  $self->{'tlv'}    = $response->{'tlv'};
  $self->{'keyed'}  = $response->{'keyed'};
}

1;
