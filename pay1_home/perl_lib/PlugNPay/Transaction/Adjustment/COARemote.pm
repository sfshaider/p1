package PlugNPay::Transaction::Adjustment::COARemote;

use strict;
use URI::Escape;

use PlugNPay::ResponseLink;
use PlugNPay::DBConnection;
use PlugNPay::Transaction::Adjustment::COARemote::Response;
use PlugNPay::Transaction::Adjustment::GlobalSettings;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

sub setAccountNumber {
  my $self = shift;
  my $accountNumber = shift;
  $self->{'accountNumber'} = $accountNumber;
}

sub getAccountNumber {
  my $self = shift;
  return $self->{'accountNumber'};
}

sub setAccountIdentifier {
  my $self = shift;
  my $accountIdentifier = shift;
  $self->{'accountIdentifier'} = $accountIdentifier;
}

sub getAccountIdentifier {
  my $self = shift;
  return $self->{'accountIdentifier'};
}

sub setCardNumber {
  my $self = shift;
  my $cardNumber = shift;
  $cardNumber =~ s/[^\d]//g;

  my $length = $self->getCardLength();
  $cardNumber = reverse sprintf('%0' . $length . 's',scalar reverse $cardNumber);
  $cardNumber = substr($cardNumber,0,$length);

  $self->{'cardNumber'} = $cardNumber;
}

sub getCardNumber {
  my $self = shift;
  return $self->{'cardNumber'};
}

sub setTransactionAmount {
  my $self = shift;
  my $amount = shift;
  $self->{'amount'} = $amount;
}

sub getTransactionAmount {
  my $self = shift;
  return $self->{'amount'};
}

sub setTransactionIdentifier {
  my $self = shift;
  my $transactionID = shift;
  $self->{'transactionID'} = $transactionID;
}

sub getTransactionIdentifier {
  my $self = shift;
  return $self->{'transactionID'};
}

sub setProtocol {
  my $self = shift;
  $self->setLocalSetting('protocol',shift);
}

sub getProtocol {
  my $self = shift;
  my $globalSettings = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $globalSettingsProtocol = $globalSettings->getProtocol();
  return $self->getLocalSetting('protocol') || $globalSettingsProtocol;
}

sub setHost {
  my $self = shift;
  $self->setLocalSetting('host',shift);
}

sub getHost {
  my $self = shift;
  my $version = $self->getAdjustmentVersion();
  my $globalSettings = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $globalSettingsHost = $globalSettings->getHost($version);
  return $self->getLocalSetting('host') || $globalSettingsHost;
}

sub setPort {
  my $self = shift;
  $self->setLocalSetting('port',shift);
}

sub getPort {
  my $self = shift;
  my $globalSettings = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $globalSettingsPort = $globalSettings->getPort();
  return $self->getLocalSetting('port') || $globalSettingsPort;
}

sub setAdjustmentVersion {
  my $self = shift;
  $self->setLocalSetting('version',shift);
}

sub getAdjustmentVersion {
  my $self = shift;
  return $self->getLocalSetting('version');
}

sub setResource {
  my $self = shift;
  $self->setLocalSetting('resource',shift);
}

sub getResource {
  my $self = shift;
  my $globalSettings = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $globalSettingsCalculationUrl = $globalSettings->getCalculationUrl();
  return $self->getLocalSetting('resource') || $globalSettingsCalculationUrl;
}

sub setCardLength {
  my $self = shift;
  my $length = shift;
  $self->setLocalSetting('cardLength',$length);
}

sub getCardLength {
  my $self = shift;
  my $version = $self->getAdjustmentVersion();
  my $globalSettings = new PlugNPay::Transaction::Adjustment::GlobalSettings();
  my $globalSettingsCardLength = $globalSettings->getCardLength($version);
  return $self->getLocalSetting('cardLength') || $globalSettingsCardLength;
}

sub setLocalSetting {
  my $self = shift;
  my $name = shift;
  my $value = shift;

  if (!defined $self->{'settings'}) {
    $self->{'settings'} = {};
  }

  $self->{'settings'}{$name} = $value;
}

sub getLocalSetting {
  my $self = shift;
  my $name = shift;

  if (ref($self->{'settings'}) eq 'HASH') {
    return $self->{'settings'}{$name};
  }

  return undef;
}

sub getResponse {
  my $self = shift;
  my $query = sprintf('account_number=%s&account_identifier=%s&bin=%s&transaction_amount=%s&transaction_identifier=%s',
                      uri_escape($self->getAccountNumber()),
                      uri_escape($self->getAccountIdentifier()),
                      uri_escape($self->getCardNumber()),
                      uri_escape($self->getTransactionAmount()),
                      uri_escape(($self->getTransactionIdentifier() || 'n/a')));

  if ($self->{'lastQuery'} != $query || !defined $self->{'rawResponse'}) {
    $self->{'lastQuery'} = $query;

    my $url = sprintf('%s://%s:%s/%s',
                      lc $self->getProtocol(),
                      $self->getHost(),
                      $self->getPort(),
                      $self->getResource());

    my $rl = new PlugNPay::ResponseLink();
    $rl->setRequestURL($url);
    $rl->setRequestData($query);
    $rl->setRequestMode('DIRECT');
    $rl->setResponseAPIType('json');

    $rl->doRequest();
    if ($rl->requestFailed()) {
      my $logger = new PlugNPay::Logging::DataLog({'collection' => 'adjustment_coa_remote'});
      $logger->log({
        message => 'call to COA failed',
        content => $rl->getResponseContent(),
        statusCode => $rl->getStatusCode()
      });
    }
    my %resultsHash = $rl->getResponseAPIData();
    chomp %resultsHash;
    $self->{'rawResponse'} = \%resultsHash;
  }

  if ($self->{'rawResponse'}) {
    my $response = new PlugNPay::Transaction::Adjustment::COARemote::Response();

    # set error
    $response->setError($self->{'rawResponse'}{'error'});

    # set card info
    $response->setCardBrand($self->{'rawResponse'}{'calculatedCOA'}{'brand'});
    $response->setCardType($self->{'rawResponse'}{'calculatedCOA'}{'type'});
    $response->setIsDebit($self->{'rawResponse'}{'calculatedCOA'}{'debit'});

    # set min and max card types
    $response->setMaxCardType($self->{'rawResponse'}{'calculatedCOA'}{'maxType'});
    $response->setMinCardType($self->{'rawResponse'}{'calculatedCOA'}{'minType'});

    # set adjustments
    $response->setAdjustment($self->{'rawResponse'}{'calculatedCOA'}{'minCOA'},'minimum');
    $response->setAdjustment($self->{'rawResponse'}{'calculatedCOA'}{'maxCOA'},'maximum');
    $response->setAdjustment($self->{'rawResponse'}{'calculatedCOA'}{'coa'},'calculated');
    $response->setAdjustment($self->{'rawResponse'}{'calculatedCOA'}{'achCOA'},'ach');
    $response->setAdjustment($self->{'rawResponse'}{'calculatedCOA'}{'regCOA'},'regulatedDebit'); # technically 'regulatedDebit' will get lowercased
                                                                                                  # but it's capitalized here for legibility

    $response->setRequestor($self);

    return $response;
  }
}

1;
