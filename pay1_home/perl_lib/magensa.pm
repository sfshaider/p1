#!/usr/local/bin/perl

package magensa;

require 5.001;

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Client::Magensa;
use PlugNPay::Client::Bluefin;
use dukpt;
use strict;
use smpsutils;
use PlugNPay::Metrics;

sub decrypt {
  my $fullSwipe = shift; # string
  my $input = shift;  # hashref
  my $gatewayAccount = $input->{'gatewayAccount'};

  # check to see if it's pgp encrypted
  # call pgp decrypt function if it is
  if ($fullSwipe =~ /^pgpdata:/i) {
    return &decryptPGP($fullSwipe,$input);
  }

  # put the full swipe into the input
  $input->{'encryptedSwipe'} = $fullSwipe;

  my $preparedData = prepareDataForDecrypt($input);
  my $results = doDecrypt($gatewayAccount, $preparedData);

  return %{$results};
}

sub prepareDataForDecrypt {
  my $input = shift;  # hashref

  my $encmag = $input->{'encryptedSwipe'};

  my %query;
  my %data;
  my %results;


  my $org_encmag = "";
  if ($encmag =~ /^\%25/) {
    $org_encmag = "$encmag";
    $encmag =~ s/%(..)/pack('c',hex($1))/eg;
  }

  # set full swipe value on query
  $query{'FullSwipe'} = $encmag;

  my @magstripe = split(/\|/,$encmag);

  $query{'SwipeDevice'} = $$input{'swipedevice'};

  if ($$input{'magensatestmode'} == 1) {
    $query{'testmode'} = 1;
  }

  my %variantHash = ('6299499' => 'dataenc1');

  if ($$input{'swipedevice'} =~ /^(ipad)$/i) {
    my $data = magtekIpadDataFromSwipe($encmag);
    # add serial number to data
    $data->{'DeviceSN'} = $input->{'devicesn'};
    $data->{'DetectedType'} = 'magtekIpad';
    %query = (%query,%{$data});
  } elsif ($$input{'swipedevice'} =~ /^(ipad2)$/i) {
    my $data = magtekIpad2DataFromInput($input);
    $data->{'DetectedType'} = 'magtekIpad2';
    %query = (%query,%{$data});
  } elsif ($$input{'swipedevice'} =~ /^(idtechkybrd)$/i) { ## ID TECH Swipe Data Original Encryption Output Format
    my $data = idTechKeyboardDataFromSwipe($encmag);
    $data->{'DetectedType'} = 'idTechKeyboard';
    %query = (%query,%{$data});
  } elsif ($$input{'swipedevice'} =~ /^(idtechsredkey)$/i) { ## ID TECH Swipe Data Original Encryption Output Format
    my $data = idTechSRedKeyDataFromSwipe($encmag);
    $data->{'DetectedType'} = 'idTechSRedKey';
    %query = (%query,%{$data});
  } elsif (($$input{'devicesn'} ne "") && ($$input{'KSN'} ne "")) {
    my $data = magtekFieldDataFromInput($input);
    $data->{'DetectedType'} = 'magtekFieldData';
    %query = (%query,%{$data});
  } elsif (defined $encmag && $encmag ne '') {
    my $data = defaultSwipeParsing($encmag);
    $data->{'DetectedType'} = 'defaultSwipe';
    %query = (%query,%{$data});
  } else {
    my $data = defaultIndividualFieldInput($input);
    $data->{'DetectedType'} = 'defaultField';
    %query = (%query,%{$data});
  }

  ## Hard Coded   ??????
  #$query{'orderID'} = substr($$input{'orderID'},-16);
  $query{'orderID'} = 1;

  my $ksidData = {};

  # set key type and variant before doing "KSN" checks
  # ignore errors for loading key type here, so $@ is not checked
  eval {
    my $ksid = dukpt::ksidFromKsn($query{'KSN'});
    $ksidData = dukpt::loadKsidData($ksid);
    $query{'keytype'} = $ksidData->{'key_type'};
    $query{'variant'} = $ksidData->{'key_variant'};
  };

  if (!defined $query{'keytype'} || $query{'keytype'} eq '') {
    if ($query{'KSN'} !~ /^[0-9a-zA-Z]{20}$/) {  ### Bad KSN
      $query{'keytype'} = 'invalid';
      $results{'StatusCode'} = "Y091";
      $results{'StatusMsg'} = "Invalid KSID";
    } elsif ($query{'KSN'} =~ /^(9010010B0|950003000)/) {  ### Magensa test Key
      $query{'customerCode'} = "ZJ33208348";   ### customer codes, username and password  provided by Magtek Jan 2017
      $query{'username'} = "MAG201690883";
      $query{'password'} = "ku0!cA#DczOLK2";
      $query{'keyType'} = "Pin";      # Enum values: Pin | Data  -need to verify this
      $query{'magnePrint'} = $query{'EncMP'};
      $query{'magnePrintStatus'} = $query{'MPStatus'};
      $query{'devicesn'} = $query{'DeviceSN'};    
    } elsif ($query{'KSN'} =~ /^(9012510|9501260|6299499)/) {
      $query{'keytype'} = 'pnpprod';
      if (exists $variantHash{$1}) {
        $query{'variant'} = $variantHash{$1};
      }
    } else {
      #Note: The 3 lines below are to hard code Magensa PROD code
      $query{'customerCode'} = 'UD99084788';   ### Production
      $query{'username'} = 'MAG201690884';
      $query{'password'} ='aEd!D14@Q2b#tv';
      $query{'keyType'} = 'Pin';
    }
  }

  return \%query;
}

sub magtekIpadDataFromSwipe {
  my $swipe = shift;

  my @magstripe = split(/\|/,$swipe);

  my %query;

  $query{'ReaderEncStatus-'} = $magstripe[1];### Reader Encryption Status - Not Used
  $query{'Track1'} = $magstripe[18];         ### Non-Encrypted Fake Track 1
  $query{'EncTrack1'} = $magstripe[21];      ### Encrypted Track1
  $query{'EncTrack2'} = $magstripe[22];      ### Encrypted Track2
  $query{'EncTrack3'} = $magstripe[23];      ### Encrypted Track3
  $query{'EncMP'} = $magstripe[24];          ### Encrypted MagnePrint Data
  $query{'KSN'} = $magstripe[25];            ### DUKPT serial number/counter
  $query{'ClearTextCRC-'} = $magstripe[0];  ### Clear Text CRC  - Not Used
  $query{'EncryptedCRC-'} = $magstripe[0];  ### Encrypted CRC - Not Used
  $query{'FormatCode'} = $magstripe[0];    ### Format Code 
  $query{'MPStatus'} = $magstripe[26];       ### MagnePrint Status
  $query{'EncSessID-'} = $magstripe[0];      ### Encrypted Session ID - Not Used

  if (($query{'EncMP'} eq "") && ($query{'Track1'} =~ /^\%M/i)) {
    $query{'Keyed'} = 1;
    $query{'EncMP'} = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    $query{'MPStatus'} = "209875";
  }

  return \%query;
}

sub magtekIpad2DataFromInput {
  my $input = shift;

  my %query;

  $query{'Track1'} = $$input{'Track1'};;              ### Non-Encrypted Fake Track 1
  $query{'EncTrack1'} = $$input{'EncTrack1'};         ### Encrypted Track1
  $query{'EncTrack2'} = $$input{'EncTrack2'};         ### Encrypted Track2
  $query{'EncTrack3'} = $$input{'EncTrack3'};;        ### Encrypted Track3
  $query{'EncPostalCode'} = $$input{'EncPostalCode'}; ### Encrypted PostalCode
  $query{'EncPostalKSN'} = $$input{'EncPostalKSN'};   ### Encrypted PostalKSN
  $query{'EncMP'} = $$input{'EncMP'};                 ### Encrypted MagnePrint Data
  $query{'KSN'} = $$input{'KSN'};                     ### DUKPT serial number/counter
  $query{'DeviceSN'} = $$input{'devicesn'};           ### Device Serial Number
  $query{'MPStatus'} = $$input{'MPStatus'};           ### MagnePrint Status

  if (($query{'EncMP'} eq "") && ($query{'Track1'} =~ /^\%M/i)) {
    $query{'Keyed'} = 1;
    $query{'EncMP'} = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    $query{'MPStatus'} = "209875";
  }

  return \%query;
}

sub magtekFieldDataFromInput {
  my $input = shift;

  my %query;

  $query{'Track1'} = $$input{'Track1'};;       ### Non-Encrypted Fake Track 1
  $query{'EncTrack1'} = $$input{'EncTrack1'};  ### Encrypted Track1
  $query{'EncTrack2'} = $$input{'EncTrack2'};  ### Encrypted Track2
  $query{'EncTrack3'} = $$input{'EncTrack2'};  ### Encrypted Track3
  $query{'EncMP'} = $$input{'EncMP'};          ### Encrypted MagnePrint Data
  $query{'KSN'} = $$input{'KSN'};              ### DUKPT serial number/counter
  $query{'DeviceSN'} = $$input{'devicesn'};    ### Device Serial Number
  $query{'MPStatus'} = $$input{'MPStatus'};    ### MagnePrint Status

  if (($query{'EncMP'} eq "") && ($query{'Track1'} =~ /^\%M/i)) {
    $query{'Keyed'} = 1;
    $query{'EncMP'} = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    $query{'MPStatus'} = "209875";
  }

  return \%query;
}

sub idTechKeyboardDataFromSwipe {
  my $swipe = shift;

  # Field Field Description
  #0 STX (02)
  #1 Data Length low byte
  #2 Data Length high byte
  #3 Card Encode Type (note 1 page 29 paragraph 9.4.1)
  #4 Track 1-3 Status (note 2 page 29 paragraph 9.4.2)
  #5 T1 data length
  #6 T2 data length
  #7 T3 data length
  #8 T1 clear/mask data - (Track 1 data)
  #9 T2 clear/mask data - (Track 2 data)
  #10 T3 clear data - (Track 3 data)
  #11 T1and T2 encrypted data
  #12 T1 hashed (20 bytes each) (if encrypted and hash tk1 allowed)
  #13 T2 hashed (20 bytes each) (if encrypted and hash tk2 allowed)
  #14 KSN (10 bytes)
  #15 CheckLRC
  #16 CheckSum
  #17 ETX (03)

  my %query;

  my (undef,undef,undef,undef,undef,$t1len,$t2len,$t3len) = unpack "A2A2A2A2A2A2A2A2", $swipe;
  $t1len = hex($t1len);
  $t2len = hex($t2len);
  $t3len = hex($t3len);
  my $firstdatalen = 16 + $t1len + $t2len + $t3len;
  my $firstdata = substr($swipe,0,$firstdatalen);
  my $lastdatalen = 40 + 40 + 20 + 2 + 2 + 2;
  $query{'EncTrack1'} = substr($swipe,$firstdatalen,length($swipe)-$lastdatalen-$firstdatalen);
  my $lastdata = substr($swipe,-$lastdatalen);
  $query{'KSN'} = substr($lastdata,80,20);

  return \%query;
}

sub idTechSRedKeyDataFromSwipe {
  my $swipe = shift;

  my %query;

  # Field Field Description
  #0 STX (02)
  #1 Data Length low byte
  #2 Data Length high byte
  #3 Card Encode Type (note 1 page 29 paragraph 9.4.1)
  #4 Track 1-3 Status (note 2 page 29 paragraph 9.4.2)
  #5 T1 data length
  #6 T2 data length
  #7 T3 data length
  #8 T1 clear/mask data - (Track 1 data)
  #9 T2 clear/mask data - (Track 2 data)
  #10 T3 clear data - (Track 3 data)
  #11 T1and T2 encrypted data
  #12 T1 hashed (20 bytes each) (if encrypted and hash tk1 allowed)
  #13 T2 hashed (20 bytes each) (if encrypted and hash tk2 allowed)
  #14 KSN (10 bytes)
  #15 CheckLRC
  #16 CheckSum
  #17 ETX (03)

  my (undef,undef,undef,undef,undef,$t1len,$t2len,$t3len) = unpack "A2A2A2A2A2A2A2A2", $swipe;
  $t1len = hex($t1len);
  $t2len = hex($t2len);
  $t3len = hex($t3len);
  my $subval = -126;
  if ($t1len == 0) {
      $subval = -86;
  }
  $query{'EncTrack1'} = substr($swipe,20+$t1len+$t2len+$t3len,$subval);
  my $lastdata = substr($swipe,-106);
  $query{'KSN'} = substr($lastdata,80,20);

  return \%query;
}

sub defaultSwipeParsing {
  my $swipe = shift;

  my @magstripe = split(/\|/,$swipe);

  my %query;

  $query{'ReaderEncStatus-'} = $magstripe[1];### Reader Encryption Status - Not Used
  $query{'EncTrack1'} = $magstripe[2];      ### Encrypted Track1
  $query{'EncTrack2'} = $magstripe[3];      ### Encrypted Track2
  $query{'EncTrack3'} = $magstripe[4];      ### Encrypted Track3
  $query{'MPStatus'} = $magstripe[5];       ### MagnePrint Status
  $query{'EncMP'} = $magstripe[6];          ### Encrypted MagnePrint Data
  $query{'DeviceSN'} = $magstripe[7];       ### Device Serial Number
  $query{'EncSessID-'} = $magstripe[8];      ### Encrypted Session ID - Not Used
  $query{'KSN'} = $magstripe[9];            ### DUKPT serial number/counter
  $query{'ClearTextCRC-'} = $magstripe[10];  ### Clear Text CRC  - Not Used
  $query{'EncryptedCRC-'} = $magstripe[11];  ### Encrypted CRC - Not Used
  $query{'FormatCode'} = $magstripe[12];    ### Format Code 

  return \%query;
}

sub defaultIndividualFieldInput {
  my $input = shift;

  my %query;

  $query{'EncTrack1'} = $input->{'EncTrack1'};
  $query{'EncTrack2'} = $input->{'EncTrack2'};
  $query{'EncTrack3'} = $input->{'EncTrack3'};
  $query{'KSN'} = $input->{'KSN'};

  return \%query;
}

sub doDecrypt {
  my $gatewayAccount = shift;
  my $queryRef = shift;

  my $metrics = new PlugNPay::Metrics();
  $metrics->increment({
    metric => sprintf('dukpt.%s.attempt',$queryRef->{'DetectedType'} || 'UNKNOWN')
  });
  
  my %query = %{$queryRef};

  my $encmag = $query{'FullSwipe'};

  my %results; # output
  
  if ($query{'keytype'} eq "invalid") {
  }
  elsif ($query{'keytype'} eq "pnpprod") {
    my $debugflg = "";
    my $variant = $query{'variant'};
    delete $query{'variant'};
    %results = &dukpt::magtekdecrypt(\%query,$variant,$debugflg);
    $results{'PAN'} = $results{'card-number'};
  } elsif ($query{'SwipeDevice'} =~ /^(idtechsredkey)$/i) {
    # Decrypt using Bluefin
    chomp($encmag);
    my $bluefin = new PlugNPay::Client::Bluefin();
    $bluefin->setGatewayAccount($gatewayAccount);
    my $response = $bluefin->decryptSwipe($encmag);

    if ($response) {
      $results{'StatusCode'} = '1000';
      $results{'card-number'} = $bluefin->getCardNumber();
      $results{'card-exp'} = $bluefin->getExpirationMonth() . '/' . $bluefin->getExpirationYear();
      $results{'PAN'} = $bluefin->getCardNumber();
      $results{'Track1'} = $bluefin->getTrack1();
      $results{'Track2'} = $bluefin->getTrack2();
      $results{'magstripe'} = $bluefin->getTrack1() . $bluefin->getTrack2();
      $results{'card-cvv'} = $bluefin->getCVV();
      $results{'mode'} = $bluefin->getMode();
    } else {
      $results{'StatusCode'} = $response->getStatus();
      $results{'StatusMsg'} = $response->getError();
    }
  } else {
    my $debugflg = "";    
    %results = &dukpt::magensaProcessorDecrypt(\%query, $debugflg);
    $results{'PAN'} = $results{'card-number'};     
  }

  ### MagnePrint - "Magnetic Fingerprint of Magstripe.  - Should be non-fatal.  Possible used as an antifraud feature.
  if (($results{'StatusCode'} =~ /^(Y093|Y094|Y095|Y096)$/)) {
    $results{'StatusCode'} = "1000";
  }

  if ($query{'Keyed'} == 1) {
    $results{'Track1'} =~ /\%M\d+\^MANUAL ENTRY\/\^(\d{4})\d{6}(\d{3,4})\d{6}\?$/;
    my $expdate = $1;
    $results{'card-cvv'} = $2;
    $results{'card-exp'} = substr($expdate,-2) ."/" .  substr($expdate,0,2);
    $results{'card-name'} = "MANUAL ENTRY";
  }
  else {
    # clear magstripe as the second if below this comment was doubling up track 2
    $results{'magstripe'} = "";
    if ($results{'Track1'} =~ /^\%B.*\?/) {
      $results{'magstripe'} = $results{'Track1'};
      my ($stuff,$name,$data) = split(/\^/,$results{'magstripe'});
      $results{'card-exp'} = substr($data,2,2) . "/" . substr($data,0,2);
    }
    if ($results{'Track2'} =~ /^;\d+\=\d+\?/) {
      $results{'magstripe'} .= $results{'Track2'};
      my ($stuff,$data) = split(/=/,$results{'magstripe'});
      $results{'card-exp'} = substr($data,2,2) . "/" . substr($data,0,2);
    }
  }
  
  ###  DCP 20130311 
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);

  my %logData = ();
  my @logData = ('DateTime','Username','SwipeDevice','testmode','keytype','ScriptName','ServerName','ipAddress','PID','EncMag','KSN','DeviceSN','Message','StatusCode','StatusMsg','PAN');
  foreach my $var (@logData) {
    if ($query{$var} ne "") {
      $logData{$var} = $query{$var};
    }
  }
  $logData{'EncMag'} = $encmag;
  $logData{'ScriptName'} = $ENV{'SCRIPT_NAME'};
  $logData{'ServerName'} = $ENV{'SERVER_NAME'};
  $logData{'ipAddress'} = $ENV{'REMOTE_ADDR'};
  $logData{'PID'} = $$;
  $logData{'DateTime'} = $now;
  $logData{'Username'} = $gatewayAccount;
  $logData{'Message'} = "";
  $logData{'StatusCode'} = $results{'StatusCode'};
  $logData{'StatusMsg'} = $results{'StatusMsg'};
  $logData{'PAN'} = substr($results{'PAN'}, 0, 6) . "****" . substr($results{'PAN'}, -4);

  if ($logData{'keytype'} eq "invalid") {
    $logData{'Message'} = "KSN INVALID";
  }
  elsif ($logData{'keytype'} eq "pnpprod") {
    $logData{'Message'} = "DECRYPTED INTERNALLY";
  }

  foreach my $var (@logData) {
    my ($key1,$val) = &logfilter_in($var,$logData{$var});
    print DEBUG "$key1:$val, ";
  }

  print DEBUG "\n\n";

  close(DEBUG);

  $metrics->increment({
    metric => sprintf('dukpt.%s.success',$query{'DetectedType'} || 'UNKNOWN')
  });

  return \%results;
}

sub decryptPGP {
  my ($encmag,$input) = @_;

  require PlugNPay::CreditCard;
  my %result = %{$input};
  my $pgpData = substr($encmag,8);
  my $ccObject = new PlugNPay::CreditCard();

  my $status = $ccObject->decryptPGPData($pgpData);
  return %{$ccObject->formatPGPData($status)};
}


sub logfilter_in {
  my ($key, $val) = @_;

  if ($key =~ /([3-7]\d{13,19})/) {
    $key =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  if ($val =~ /([3-7]\d{12,19})/) {
    $val =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  return ($key,$val);
}

sub logfilter_sub {
  my ($data) = @_;

  my $luhntest = &miscutils::luhn10($data);
  if ($luhntest eq "success") {
    $data =~ s/./X/g;
  }

  return $data;
}


1;
