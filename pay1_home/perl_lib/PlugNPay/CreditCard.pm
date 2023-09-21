package PlugNPay::CreditCard;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Util::Cache::LRUCache;
use PlugNPay::Util::Temp;
use PlugNPay::CreditCard::Encryption;
use PlugNPay::CreditCard::Brand;
use PlugNPay::ResponseLink;
use PlugNPay::Token;
use JSON::XS;
use magensa;
use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;
use PlugNPay::Util::Hash;
use PlugNPay::Logging::DataLog;
use PlugNPay::COA::Server;
use PlugNPay::Util::Status;
use PlugNPay::AWS::Lambda;
use PlugNPay::AWS::ParameterStore;
use MIME::Base64 qw(decode_base64);

our $cardTypeCache;
our $cardBrandCache;
our $pgpLambda;



sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self, $class;

  my $cardNumberOrMagstripe = shift;
  if (length($cardNumberOrMagstripe) <= 19) {
    $self->setNumber($cardNumberOrMagstripe);
  } else {
    $self->setMagstripe($cardNumberOrMagstripe);
  }

  if (!defined $cardBrandCache) {
    $cardBrandCache = new PlugNPay::Util::Cache::LRUCache(20);
  }

  if (!defined $cardTypeCache) {
    $cardTypeCache = new PlugNPay::Util::Cache::LRUCache(10);
  }

  $self->{'coaInfo'} = {};

  return $self;
}

sub setNumber {
  my $self = shift;
  my $cardNumber = shift;
  $cardNumber =~ s/[^0-9]//g;

  if ($cardNumber ne $self->{'cardNumber'}) {
    $self->_retrieveToken($cardNumber);
  }

  $self->{'cardNumber'} = $cardNumber;
}

sub getNumber {
  my $self = shift;
  return $self->{'cardNumber'};
}

sub setMaskedNumber {
  my $self = shift;
  my $masked = shift;

  $self->{'maskedNumber'} = $masked;
}

sub getMaskedNumber {
  my $self = shift;
  my $first = shift;
  my $last = shift;
  my $mask = shift;
  my $maskLength = shift;

  # set default mask if not supplied
  if (!defined $first) { $first = 6;   }
  if (!defined $last)  { $last  = 4;   }
  if (!defined $mask)  { $mask  = '*'; }

  # don't allow greater than first 6 last 4
  if ($first > 6) { $first = 6; }
  if ($last > 4)  { $last = 4; }

  my $number = $self->getNumber() || $self->{'maskedNumber'};

  $maskLength = (defined $maskLength ? $maskLength : length($number) - $first - $last);

  $mask = $mask x $maskLength;

  $number =~ s/^(\d{$first})\d+?(\d{$last})$/$1$mask$2/g;
  return $number;
}



sub setSecurityCode {
  my $self = shift;
  my $securityCode = shift;
  $securityCode =~ s/[^0-9]//g;
  $self->{'securityCode'} = $securityCode;
}

sub getSecurityCode {
  my $self = shift;
  return $self->{'securityCode'};
}


sub setName {
  my $self = shift;
  my $name = shift;
  # remove trailing whitespace
  $name =~ s/\s+$//;
  $self->{'name'} = $name;
}

sub getName {
  my $self = shift;
  return $self->{'name'};
}

# No longer used, left for compatability
sub setBusinessCard {
  my $self = shift;
  $self->{'businessCardType'} = 'business';
}

sub isBusinessCard {
  my $self = shift;
  my $coaResponse = $self->getCOAInfo();

  return $coaResponse->{'isBusiness'};
}

sub setExpirationMonth {
  my $self = shift;
  my $month = shift;
  $month =~ s/[^0-9]//g;
  if (!($month >= 1 && $month <= 12)) {
    $month = undef;
  }
  $self->{'expirationMonth'} = $month;
}

sub getExpirationMonth {
  my $self = shift;
  return $self->{'expirationMonth'};
}

sub setExpirationYear {
  my $self = shift;
  my $year = shift;
  $year =~ s/[^0-9]//g;
  $year = substr("0" . $year,-2,2);
  $self->{'expirationYear'} = $year;
}

sub getExpirationYear {
  my $self = shift;
  return $self->{'expirationYear'};
}

sub setMagstripe {
  my $self = shift;
  my $magstripe = shift;
  $self->_parseMagstripe($magstripe);
  $self->{'magstripe'} = $magstripe;
}

sub getMagstripe {
  my $self = shift;
  return $self->{'magstripe'};
}

sub getBIN {
  my $self = shift;

  return substr($self->getNumber(),0,6);
}

## Don't use this, just here for compatibility until all calls to it are removed.
sub getCardCategory {
  my $self = shift;
  return $self->getCategory();
}

sub getCategory {
  my $self = shift;
  my $coaResponse = $self->getCOAInfo();

  #If error in getCOACategory check then coaResponse is assigned false,
  #leading to getFraudTrackCategory to be called.
  if($coaResponse && $coaResponse->{'generalTier'}){
    return $coaResponse->{'generalTier'};
  } else{
    return $self->getFraudTrackCategory();
  }

}

sub getCOAInfo {
  my $self = shift;

  my $number = $self->getNumber();

  if (defined $self->{'coaInfo'}{$number}) {
    return $self->{'coaInfo'}{$number};
  }

  my $rl = new PlugNPay::ResponseLink();
  my $coaServer = PlugNPay::COA::Server::getServer();
  $coaServer =~ s/\/$//; # remove trailing slash if there is one
  $rl->setRequestURL($coaServer . '/bininfo.cgi');
  $rl->setRequestData({bin => $self->getBIN()});
  $rl->setRequestMethod('POST');
  $rl->setRequestTimeout(5);
  $rl->setRequestMode('DIRECT');

  $rl->doRequest();

  my $responseContent=$rl->getResponseContent();

  my $data;
  eval{
    $data=JSON::XS::decode_json($responseContent);
  };

  if ($@) {
    $self->log({ message => 'Error attempting to load card info', error => $@ });
  } else {
    if($data) {
      $self->{'coaInfo'}{$number} = $data;
      return $data;
    }
  }

  #Returning undef still provides the "false" response
  #But avoids the 500 when calling it has a hash
  return undef;
}

##Used for failback of getCategory() if COA check fails,
##Shouldn't be called directly, use getCategory().
sub getFraudTrackCategory {
  my $self = shift;

  if (!defined $self->{'cardCategory'}) {
    my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('fraudtrack');
    my $sth = $dbh->prepare(q/
                            SELECT card_category
                            FROM (
                                 SELECT startbin,endbin,card_category
                                 FROM ardef
                                 UNION ALL
                                 SELECT startbin,endbin,card_category
                                 FROM icaxrf
                                 ) all_cards
                            WHERE RPAD(startbin,20,'0') <= RPAD(?,20,'0') && RPAD(endbin,20,'0') >= RPAD(?,20,'0') LIMIT 1
                            /);

    $sth->execute($self->getNumber(),$self->getNumber());
    my $rows = $sth->fetchall_arrayref({});

    $self->{'cardCategory'} = $rows->[0]{'card_category'};
  }

  return $self->{'cardCategory'};
}

sub getBrand {
  my $self = shift;
  my $settings = shift;

  my $code;

  my $coaResponse = $self->getCOAInfo();

  if ($coaResponse) {
    my $brandName = $coaResponse->{'brand'};
    my $brand = new PlugNPay::CreditCard::Brand();
    if ($settings->{'legacy'} == 1) {
      $code = $brand->getLegacyCharacter($brandName);
    } else {
      $code = $brand->getFourCharacter($brandName);
    }
  }

  return $code;
}

sub getBrandName {
  my $self = shift;
  my $settings = shift;

  my $name;

  my $coaResponse = $self->getCOAInfo();
  if ($coaResponse) {
    my $brandName = $coaResponse->{'brand'};
    my $brand = new PlugNPay::CreditCard::Brand();
    $name = $brand->getName($brandName);
  }

  return $name;
}

sub getType {
  my $self = shift;

  my $coaResponse = $self->getCOAInfo();

  my $type;

  if ($coaResponse) {
    $type = lc $coaResponse->{'type'};
    $type =~ s/\s.*//g;
  }

  if ($self->isDebit() && $self->isBusinessCard()) {
    $type = 'debit';
  }

  return $type;
}

sub getCountryCode {
  my $self = shift;
  my $coaResponse = $self->getCOAInfo();
  my $countryCode;
  if ($coaResponse) {
    $countryCode = $coaResponse->{'countryCode'};
    $countryCode =~ s/[^0-9]//g;
  }
  return $countryCode;
}

sub isDebit {
  my $self = shift;
  my $coaResponse = $self->getCOAInfo();
  return $coaResponse->{'Debit'} || 0;
}

sub isRegulatedDebit {
  my $self = shift;

  my $coaResponse = $self->getCOAInfo();

  return $coaResponse->{'regulated'} || 0;
}

sub verifyLength {
  my $self = shift;
  my $number;

  # Check to see if self is an object, if not, this is being called staticly.
  if (ref($self) eq '') {
    $number = $self;
  }

  if (!$number) {
    $number = $self->getNumber();
  }

  return (length($number) >= 12 && length($number) <= 19);
}

sub setIgnoreLuhn10 {
  my $self = shift;
  if (shift) {
    $self->{'ignoreLuhn10'} = 1;
  }
}

sub getIgnoreLuhn10 {
  my $self = shift;
  return $self->{'ignoreLuhn10'};
}

sub requiresLuhn10 {
  my $self = shift;

  my $brand = $self->getBrand();
  if ($self->getBrand() eq '' || uc($self->getBrand()) eq 'WEX') {
    return 0;
  }

  return 1;
}

sub verifyLuhn10 {
  my $self = shift;
  my $number;

  # Check to see if self is an object, if not, this is being called staticly.
  if (ref($self) eq '') {
    $number = $self;
  } else {
    # return a passing value if this object is set to ignore luhn 10
    if ($self->getIgnoreLuhn10()) { return 1; }

    # get the card number from the object
    $number = $self->getNumber();
  }

  if ($number eq '') { return 0; }

  # Do the luhn10 check
  my ($sum, $even) = (shift, 0, 0);
  for my $digit ( reverse(split //, $number )) {
    $sum += $_ for split //, $digit * (1 + $even);
    $even = not $even;
  }
  return ($sum % 10) == 0;
}

sub isExpired() {
  my $self = shift;

  my @time = gmtime();
  my $currentMonth = $time[4] + 1;
  my $currentYear = (substr($time[5],-2,2)) + 0;

  my $cardMonth = $self->getExpirationMonth();
  my $cardYear = $self->getExpirationYear();

  my $expired = 1;  #initial value
  if (defined $cardMonth && defined $cardYear) {
     #re evaluate only if cardMonth and cardYear are defined
     $expired = (($cardYear < $currentYear) || ($cardYear == $currentYear && $cardMonth < $currentMonth));
  }

  return ($expired ? 1 : 0);
}

sub _parseMagstripe {
  my $self = shift;
  my $magstripe = shift;

  # Track 1
  if ($magstripe =~ /.*\%\b(.*)?\?\;?(.*)\??/i) {
    my @data = split(/[\%\^]/,$1);
    $self->setNumber($data[0]);
    $self->setName($data[1]);
    $self->setExpirationMonth(substr($data[2],2,2));
    $self->setExpirationYear(substr($data[2],0,2));
  # Track 2 (swiped or keyed)
  } elsif ($magstripe =~ /^\;(.*)\?.?$/) {
    my @data = split(/[\=\:]/,$1);
    $self->setNumber($data[0]);
    $self->setName('');
    $self->setExpirationMonth(substr($data[1],2,2));
    $self->setExpirationYear(substr($data[1],0,2));
  }
}

sub fromDukpt {
  my $self = shift;
  my $input = shift;

  my $ksn = $input->{'ksn'};
  my $track1 = $input->{'track1'};
  my $track2 = $input->{'track2'};
  my $track3 = $input->{'track3'};

  my %magensaModuleDecryptData = (
    EncTrack1 => $track1,
    EncTrack2 => $track2,
    EncTrack3 => $track3,
    KSN => lc($ksn)
  );

  my %result;
  eval {
    %result = magensa::decrypt(undef,\%magensaModuleDecryptData);
    $self->setMagstripe($result{'magstripe'});
  };

  if ($@) {
    $self->log({
      message => 'failed to decrypt dukpt',
      error => $@
    });
    return 0;
  }

  return 1;
}

sub decryptMagensa {
  my $self = shift;
  my $magensaSwipe = shift;
  my $gatewayAccount = shift;
  my $decryptedData;
  if ($magensaSwipe =~ /^pgpdata:/i) {
    my $status = $self->decryptPGPData(substr($magensaSwipe,8));
    return $self->formatPGPData($status);
  }

  my $ksn = $self->getKSNFromSwipeData($magensaSwipe,$self->getSwipeDevice());
  my $insertedKsn = $self->insertKsnOnly($ksn);

  if ($insertedKsn) {
    $decryptedData = $self->decryptMagensaSwipeData($magensaSwipe, $gatewayAccount);
    # Save decrypted data to the db if successfully decrypted
    if (defined $decryptedData->{'magstripe'} && $decryptedData->{'magstripe'} ne '') {
      $self->saveMagensaSwipeData($ksn,$decryptedData);
    } else {
      $decryptedData->{'error'} = "1";
      $decryptedData->{'errorMessage'} = "$decryptedData->{'StatusCode'}, $decryptedData->{'StatusMsg'}.";
      $self->deleteMagensaSwipeData($ksn);
    }
  }
  else {
    for (my $i=1; $i<=30; $i++) {
      if ($self->magensaSwipeExists($ksn)) {
        # Get stored magensa swipe data
        my $storedMagensaData = $self->getStoredMagensaData($ksn);
        $decryptedData = $self->formatStoredMagensaData($storedMagensaData);
        last;
      } else {
        sleep(0.10);
      }
    }
  }
  return $decryptedData;
}

sub setAccountFromEncryptedNumber {
  my $self = shift;
  return $self->setNumberFromEncryptedNumber(@_);
}

sub setNumberFromEncryptedNumber {
  my $self = shift;
  my $encryptedCardNumber = shift;

  my $cardCrypt = new PlugNPay::CreditCard::Encryption();

  my $number;
  eval {
    $number = $cardCrypt->decrypt($encryptedCardNumber);
    $self->setNumber($number);
  };
  return $self->getMaskedNumber();
}

sub getYearMonthEncryptedNumber {
  my $self = shift;
  my $encryptedCardNumber;

  my $cardCrypt = new PlugNPay::CreditCard::Encryption();
  eval {
    $encryptedCardNumber = $cardCrypt->encrypt($self->getNumber());
  };

  return $encryptedCardNumber;
}

sub getPerpetualEncryptedNumber {
  my $self = shift;
  my $encryptedCardNumber;

  my $cardCrypt = new PlugNPay::CreditCard::Encryption();
  eval {
    $encryptedCardNumber = $cardCrypt->encrypt($self->getNumber(),1);
  };

  return $encryptedCardNumber;
}

sub getToken {
  my $self = shift;
  my $cardNumber = shift;
  $cardNumber =~ s/[^\d]//g;
  if ($cardNumber) {
    $self->setNumber($cardNumber);
  }

  return $self->{'cardToken'};
}

sub _retrieveToken {
  my $self = shift;
  my $cardNum = shift;
  if (!defined $cardNum) {
    $cardNum = $self->getNumber();
  }

  my $requester = new PlugNPay::Token();

  my $token = $requester->getToken($cardNum);
  $self->{'cardToken'} = $token;
  return $token;
}

sub fromToken {
  my $self = shift;
  my $token = shift;
  my $redeem = uc shift || "PROCESSING";
  my $redeemer = new PlugNPay::Token();

  my $cc = $redeemer->fromToken($token,$redeem);

  if ($token =~ /^[a-fA-F0-9]+$/i && $cc) {
    $self->{'cardToken'} = $token;
    $self->{'cardNumber'} = $cc;
  }

  return $cc;
}

sub getSha1Hash {
  my $self = shift;
  my $cardNumber = $self->getNumber();

  my $sha1Token = "Sha1Token";
  my $sha = new SHA;
  $sha->reset;
  $sha->add($cardNumber);
  $sha1Token = $sha->hexdigest();

  return $sha1Token;
}

sub setCommCardType {
  my $self = shift;
  my $commCardType = shift;
  $self->{'commCardType'} = $commCardType;
}

sub getCommCardType {
  my $self = shift;
  return $self->{'commCardType'};
}

sub getEncryptedInfo {
  my $self = shift;
  my $cardNumber = $self->getNumber();

  my ($enccardnumber,$encryptedDataLen) = &rsautils::rsa_encrypt_card($cardNumber,"/home/p/pay1/pwfiles/keys/key");
  return { 'enccardnumber' => $enccardnumber, 'length' => $encryptedDataLen };
}

sub getEncHash {
  my $self = shift;
  my $cardNumber = $self->getNumber();

  my $encToken = "encToken";
  my $encCardInfo = $self->getEncryptedInfo();

  my $sha = new SHA;
  $sha->reset;
  $sha->add($encCardInfo->{'enccardnumber'});
  $encToken = $sha->hexdigest();

  return $encToken;
}

sub getCardHashHash {
  my $self = shift;

  my %cardHashHash = ();
  $cardHashHash{'sha1Hash'} = $self->getSha1Hash();
  $cardHashHash{'encShaHash'} = $self->getEncHash();
  $cardHashHash{'token'} = $self->getToken();

  return %cardHashHash;
}

sub getCardHashArray {
  my $self = shift;

  my @cardHashArray = ();
  if ($self->getSha1Hash() ne "") {
    push (@cardHashArray , $self->getSha1Hash());
  }
  if ($self->getEncHash() ne "") {
    push (@cardHashArray , $self->getEncHash());
  }
  if ($self->getToken ne "") {
    push (@cardHashArray , $self->getToken());
  }

  return @cardHashArray;
}

sub getCardHash {
  ## Return Preferred Method
  my $self = shift;
  #return $self->getSha1Hash();
  return $self->getEncHash();
  #return $self->getToken();
}

sub compareHash {
  my $self = shift;
  my $chkHashNumber = shift;
  my @cardArray = $self->getCardHashArray();
  my $match = 0;

  foreach my $var (@cardArray) {
    if ($var eq $chkHashNumber) {
      $match++;
      last;
    }
  }
  return $match;
}

sub setMagensa {
  my $self = shift;
  my $magensa = shift;
  $self->{'magensa'} = $magensa;
}

sub getMagensa {
  my $self = shift;
  return $self->{'magensa'};
}

sub setSwipeDevice {
  my $self = shift;
  my $swipeDevice = shift;
  $self->{'swipeDevice'} = $swipeDevice;
}

sub getSwipeDevice {
  my $self = shift;
  return $self->{'swipeDevice'};
}

sub _saveEncryptedSwipe {
  my $self = shift;
  my $ksn = shift;
  my $decryptedMagstripe = shift;
  my $statusCode = shift;
  my $statusMessage = shift;

  my $newEncryption = new PlugNPay::CreditCard::Encryption();
  my $reEncryptedSwipe = $newEncryption->encryptMagstripe($decryptedMagstripe);

  my $temp = new PlugNPay::Util::Temp();
  $temp->setKey('encswipe-' . $ksn);
  $temp->setValue({
    'reEncryptedSwipe' => $reEncryptedSwipe,
    'statusCode'       => $statusCode,
    'statusMessage'    => $statusMessage
  });

  $temp->setExpirationTime(1);
  $temp->setPassword('encryptedSwipe');
  my $status = $temp->store();
  if (!$status) {
    $self->log({ 'error' => $status->getError(), 'message' => 'failed to store encrypted swipe.' });
    # if it doesn't store, die like execute did
    die('failed to store encrypted swipe');
  }
}

sub _loadEncryptedSwipe {
  my $self = shift;
  my $ksn = shift;

  my %results = ();

  my $temp = new PlugNPay::Util::Temp();
  $temp->setKey('encswipe-' . $ksn);
  $temp->setPassword('encryptedSwipe');
  my $status = $temp->fetch();
  if (!$status) {
    $self->log({ 'error' => $status->getError(), 'message' => 'failed to retrieve encrypted swipe' });
  } else {
    my $value = $temp->getValue();
    $results{'ksn'} = $ksn;
    $results{'re_encrypted_data'} = $value->{'reEncryptedSwipe'};
    $results{'status_code'}       = $value->{'statusCode'};
    $results{'status_message'}    = $value->{'statusMessage'};
  }

  return \%results;
}

sub _deleteEncryptedSwipe {
  my $self = shift;
  my $ksn = shift;

  my $temp = new PlugNPay::Util::Temp();
  $temp->setKey('encswipe-' . $ksn);
  $temp->setPassword('encryptedSwipe');
  my $status = $temp->delete();
  if (!$status) {
    $self->log({ 'error' => $status->getError(), 'message' => 'failed to delete encrypted swipe' });
  }
}

sub magensaSwipeExists {
  my $self = shift;
  my $ksn = shift;

  my $swipeData = $self->_loadEncryptedSwipe($ksn);

  if ($ksn eq $swipeData->{'ksn'} && $swipeData->{'re_encrypted_data'} ne "") {
    return 1;
  }
  return 0;
}

sub convertToHash {
  my $self = shift;
  my $data = shift;

  my $hash = new PlugNPay::Util::Hash();
  $hash->add($data);

  return $hash->sha256();
}

sub getStoredMagensaData {
  my $self = shift;
  my $ksn = shift;
  my %storedMagensaData;

  my $data = $self->_loadEncryptedSwipe($ksn);
  my $reEncryptedData = $data->{'re_encrypted_data'};
  my $encryption = new PlugNPay::CreditCard::Encryption();
  $storedMagensaData{'decryptedSwipe'} = $encryption->decryptMagstripe($reEncryptedData);
  $storedMagensaData{'statusCode'} = $data->{'status_code'};
  $storedMagensaData{'statusMessage'} = $data->{'status_message'};

  return \%storedMagensaData;
}

sub deleteMagensaSwipeData {
  my $self = shift;
  my $ksn = shift;

  $self->_deleteEncryptedSwipe($ksn);
}

sub insertKsnOnly {
  my $self = shift;
  my $ksn = shift;

  my $dbs = PlugNPay::DBConnection::connections();
  my $sth = $dbs->getHandleFor('pnpmisc')->prepare(q/
    INSERT INTO encrypted_swipe_data
    (ksn)
    VALUES (?)
  /);

  eval{
    $sth->execute($ksn) or die($DBI::errstr);
  };

  unless($@){
    return 1;
  } else {
    return 0;
  }
}

sub decryptPGPData {
  my $self = shift;
  my $payload = shift;

  if ($payload =~ /^pgpdata:/i) {
    $payload = substr($payload,8);
    new PlugNPay::Logger::DataLog({'collection' => 'refactor_me'})->log({
      'message' => 'PGP DECRYPTION CALLED WITH INVALID PREFIX "pgp_data:"'
    });
  }

  $payload =~ s/[^a-zA-Z0-9\+\/=]//g;
  my $response;

  eval {
    if (!defined $pgpLambda) {
       $pgpLambda = &PlugNPay::AWS::ParameterStore::getParameter('/LAMBDA/PGP/DECRYPTION');
    }

    $response = &PlugNPay::AWS::Lambda::invoke({
      'lambda' => $pgpLambda,
      'invocationType' => 'RequestResponse',
      'data' => {
        'payload' => $payload
      }
    });
  };

  my $status = new PlugNPay::Util::Status(1);
  if (!defined $response || !$response->{'payload'} || !$response->{'status'} || $@) {
    my $error =  $@ || $response->{'error'} || 'invalid response from pgp lambda';
    $status->setFalse();
    $status->setError('failed to decrypt PGP data');
    $status->setErrorDetails($@ || $response->{'error'} || 'invalid response from pgp lambda');
    $self->log({
      'message' => 'failed to parse PGP data',
      'error'   => $error
    });
  } else {
    my $decodedJSON = decode_base64($response->{'payload'});
    eval {
      my $decryptedData = decode_json($decodedJSON);
      $self->setMagstripe($decryptedData->{'magstripeData'}) if $decryptedData->{'magstripeData'};
      $self->setNumber($decryptedData->{'cardNumber'});
      $self->setName($decryptedData->{'cardName'}) if $decryptedData->{'cardName'};
      $self->setExpirationMonth($decryptedData->{'expirationMonth'}) if $decryptedData->{'expirationMonth'};
      $self->setExpirationYear($decryptedData->{'expirationYear'}) if $decryptedData->{'expirationYear'};
      $self->setSecurityCode($decryptedData->{'securityCode'}) if $decryptedData->{'securityCode'};

      if (!$self->verifyLength() || !$self->verifyLuhn10() || $self->isExpired()) {
        my $message = $self->isExpired() ? 'decrypted card is expired' : 'decrypted card failed number validation';
        $status->setFalse();
        $status->setError('decrypted card data is invalid');
        $status->setErrorDetails($message);
        $self->log({
          'message' => 'decrypted card data is invalid',
          'error'   => $message
        });
      }
    };

    if ($@) {
      my $error = $@;
      $status->setFalse();
      $status->setError('Error parsing PGP decryption response');
      $status->setErrorDetails($error);
      $self->log({
        'message' => 'Error parsing PGP decryption response',
        'error'   => $error
      });
    }
  }

  return $status;
}

sub formatPGPData {
  my $self = shift;
  my $status = shift;
  my $result = {};

  if (ref($status) ne 'PlugNPay::Util::Status') {
    $result->{'FinalStatus'} = 'problem';
    $result->{'StatusCode'} = 'Y098';
    $result->{'StatusMsg'} = 'Problem decrpyting message';
    $result->{'MErrMsg'} = "Decryption problem";
  } elsif ($status) {
    $result->{'StatusCode'} = '1000';
    $result->{'card-number'} = $self->getNumber();
    $result->{'card-exp'} = $self->getExpirationMonth() . '/' . $self->getExpirationYear();
    $result->{'PAN'} = $self->getNumber();
    $result->{'magstripe'} = $self->getMagstripe();
    $result->{'card-cvv'} = $self->getSecurityCode();
    $result->{'FinalStatus'} = 'success';
  } else {
    $result->{'FinalStatus'} = 'problem';
    $result->{'StatusCode'} = 'Y098';
    $result->{'StatusMsg'} = 'Problem decrpyting message: ' . $status->getError();
    $result->{'MErrMsg'} = "Decryption problem";
  }

  return $result;
}

sub decryptMagensaSwipeData {
  my $self = shift;
  my $magensaSwipe = shift;
  my $gatewayAccount = shift;

  my %input;
  $input{'swipedevice'} = $self->getSwipeDevice();
  $input{'gatewayAccount'} = $gatewayAccount;

  # Use magensa module to decrypt
  my %decryptedData = &magensa::decrypt($magensaSwipe,\%input);

  return \%decryptedData;
}

sub saveMagensaSwipeData {
  my $self = shift;
  my $ksn = shift;
  my $decryptedData = shift;

  my $decryptedMagstripe = $decryptedData->{'magstripe'};
  my $statusCode = $decryptedData->{'StatusCode'};
  my $statusMessage = $decryptedData->{'StatusMsg'};
  $self->_saveEncryptedSwipe($ksn,$decryptedMagstripe,$statusCode,$statusMessage);
}

sub formatStoredMagensaData {
  my $self = shift;
  my $storedMagensaData = shift;
  my %decryptedData;

  $decryptedData{'magstripe'} = $storedMagensaData->{'decryptedSwipe'};
  $decryptedData{'StatusCode'} = $storedMagensaData->{'statusCode'};
  $decryptedData{'StatusMsg'} = $storedMagensaData->{'statusMessage'};

  # Parse the magstripe data
  $self->setMagstripe($decryptedData{'magstripe'});

  # Add parsed data
  my $cardMonth = $self->getExpirationMonth();
  my $cardYear = $self->getExpirationYear();
  $decryptedData{'card-exp'} = "$cardMonth/$cardYear";
  $decryptedData{'card-number'} = $self->getNumber();
  $decryptedData{'PAN'} = $self->getNumber();
  $decryptedData{'card-cvv'} = $self->getSecurityCode();

  # Add additional data
  $decryptedData{'previously_decrypted'} = 1;

  return \%decryptedData;
}

sub getKSNFromSwipeData {
  my $self = shift;
  my $swipeData = shift;
  my $swipeDevice = shift;
  my $ksn;

  if ($swipeDevice eq 'idtechsredkey') {
    $ksn = substr($swipeData,-26,20);
  } else {
    my @swipe = split(/\|/,$swipeData);
    $ksn = $swipe[9];
  }

  return $ksn;
}

sub getVehicleType {
  return 'card';
}

sub log {
  my $self = shift;
  my $data = shift;

  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'credit_card'});
  my @caller = caller();
  $logger->log({'caller' => \@caller, 'data' => $data},{ stackTraceEnabled => 1 });
}

1;
