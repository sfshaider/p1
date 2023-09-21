#!/usr/local/bin/perl

package magensa;

require 5.001;

use strict;

sub decrypt {
  my $testmode = 0;
  my $keytype = "";
  my %query = ();
  my %data = ();
  my %results = ();
  my ($msg);

  my ($encmag,$input) = @_;

  if ($encmag =~ /^\%25/) {
    $encmag =~ s/%(..)/pack('c',hex($1))/eg;
  }
  my $keyedflag = 0;

  my @magstripe = split(/\|/,$encmag);

  if ($$input{'swipedevice'} =~ /^(ipad)$/i) {
    my $maskedtrack = $magstripe[0];
    $query{'ReaderEncStatus-'} = $magstripe[1];### Reader Encryption Status - Not Used
    $query{'Track1'} = $magstripe[18];         ### Non-Encrypted Fake Track 1
    $query{'EncTrack1'} = $magstripe[21];      ### Encrypted Track1
    $query{'EncTrack2'} = $magstripe[22];      ### Encrypted Track2
    $query{'EncTrack3'} = $magstripe[23];      ### Encrypted Track3
    $query{'EncMP'} = $magstripe[24];          ### Encrypted MagnePrint Data
    $query{'KSN'} = $magstripe[25];            ### DUKPT serial number/counter
    $query{'DeviceSN'} = $$input{'devicesn'};       ### Device Serial Number
    $query{'ClearTextCRC-'} = $magstripe[0];  ### Clear Text CRC  - Not Used
    $query{'EncryptedCRC-'} = $magstripe[0];  ### Encrypted CRC - Not Used
    $query{'FormatCode'} = $magstripe[0];    ### Format Code 
    $query{'MPStatus'} = $magstripe[26];       ### MagnePrint Status
    $query{'EncSessID-'} = $magstripe[0];      ### Encrypted Session ID - Not Used

    if (($query{'EncMP'} eq "") && ($query{'Track1'} =~ /^\%M/i)) {
      $keyedflag = 1;
      $query{'EncMP'} = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
      $query{'MPStatus'} = "209875";
    }

  }
  else {
    my $maskedtrack = $magstripe[0];
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
  }

  if ($$input{'magensatestmode'} == 1) {
    $testmode = 1;
  }

  ## Hard Coded   ??????
  #$query{'orderID'} = substr($$input{'orderID'},-16);
  $query{'orderID'} = 1;

  if ($query{'KSN'} !~ /^[0-9a-zA-Z]{9}/) {  ### Bad KSN
    $keytype = 'invalid';
  }
  elsif ($query{'KSN'} =~ /^(9010010B0|950003000)/) {  ### Magensa Test Key
    $query{'HostID'} = "MAG926167141";   ### Test
    $query{'HostPwd'} = 's4!Ce0@Nt1FyLd';
    $query{'OutputFormatCode'} = "103";
    $query{'CardType'} = "1";
    $query{'EncryptionBlockType'} = "1";
    $query{'RegisteredBy'} = "TestUser";
    $query{'FutureInput'} = "";
    $testmode = 1;
    $keytype = 'magtest';
  }
  elsif ($query{'KSN'} =~ /^(9012510B0)/) {
    $keytype = 'pnpprod';
  }
  else {
    $query{'HostID'} = "MAG130369704";   ### Production
    $query{'HostPwd'} = 'j0!Fs5$Jq4PbNp';
    $query{'OutputFormatCode'} = "103";
    $query{'CardType'} = "1";
    $query{'EncryptionBlockType'} = "1";
    $query{'RegisteredBy'} = "TestUser";
    $query{'FutureInput'} = "";
    $keytype = 'magprod';
  }

  #if ($query{'EncMP'} eq "") && ({
  #  $query{'EncMP'} = "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
  #  $query{'MPStatus'} = "209875";
  #}

  open (DEBUG,">>/home/p/pay1/database/debug/magensa_debug.txt");
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
  print DEBUG "DATE:$now, UN:$$input{'publisher-name'}, TESTMODE:$testmode, KEYTYPE:$keytype, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, IP:$ENV{'REMOTE_ADDR'}, PID:$$, ENCCARD:$encmag, ";
  foreach my $key (sort keys %query) {
    print DEBUG "$key:$query{$key}, ";
  }
  print DEBUG "\n\n";

  if ($keytype eq "invalid") {
    print DEBUG "KSN INVALID\n\n";
  }
  elsif ($keytype eq "pnpprod") {
    require dukpt;
    %results = &dukpt::magtekdecrypt("$encmag");
    $results{'PAN'} = $results{'card-number'};

    print DEBUG "DECRYPTED INTERNALLY\n\n";
  }
  else {
    my $msg = &build_XML_10(\%query);
    %results = &sendXML("$msg","$testmode");

    print DEBUG "REQUEST:$msg\n\n";

  }

  close(DEBUG);

  if (($keyedflag == 1) && ($results{'StatusCode'} =~ /^(Y093|Y094|Y095|Y096)$/)) {
    $results{'StatusCode'} = "1000";
  }

  if ($keyedflag == 1) {
    $results{'Track1'} =~ /\%M\d+\^MANUAL ENTRY\/\^(\d{4})\d{6}(\d{3,4})\d{6}\?$/;
    my $expdate = $1;
    $results{'card-cvv'} = $2;
    $results{'card-exp'} = substr($expdate,-2) ."/" .  substr($expdate,0,2);
    $results{'card-name'} = "MANUAL ENTRY";
  }

  return %results;

}


sub build_XML_12 {
  my($query) = @_;
  my (%result,%req,%error,$res,$pairs,$message,$resp,$header);
  #my $url = "https://ws.magensa.net/wsmagensa/service.asmx?op=DecryptRSV201"; 
  my $url = "https://ws.magensa.net/wsmagensa/service.asmx";
  my $host = "http://www.magensa.net/";
  my $output = "";
  my $agent = "SOAP::Lite/Perl/v0.710.8";
  my $contype = "application/soap+xml";

  require XML::Simple;
  require XML::Writer;
  require LWP::UserAgent;

  my $xml_request = XML::Writer->new(OUTPUT => \$output, NEWLINES => 0);

  $xml_request->xmlDecl("UTF-8");
  $xml_request->startTag('soap12:Envelope',
              'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
              #'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/',  ####?
              'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema',
              #'soap:encodingStyle' => 'http://schemas.xmlsoap.org/soap/encoding/',  ####?
              'xmlns:soap12' => 'http://www.w3.org/2003/05/soap-envelope');

  $xml_request->startTag('soap12:Body');

  $xml_request->startTag('DecryptRSV201','xmlns' => "$host");

  $xml_request->startTag('DecryptRSV201_Input');

  ## EncTrack1
  $xml_request->startTag('EncTrack1');
  $xml_request->characters("$$query{'EncTrack1'}");
  $xml_request->endTag('EncTrack1');

  ## EncTrack2
  $xml_request->startTag('EncTrack2');
  $xml_request->characters("$$query{'EncTrack2'}");
  $xml_request->endTag('EncTrack2');

  ## EncTrack3
  $xml_request->startTag('EncTrack3');
  $xml_request->characters("$$query{'EncTrack3'}");
  $xml_request->endTag('EncTrack3');

  if ($$query{'EncMP'} ne "") {
    ## EncMP
    $xml_request->startTag('EncMP');
    $xml_request->characters("$$query{'EncMP'}");
    $xml_request->endTag('EncMP');
  }

  ## KSN
  $xml_request->startTag('KSN');
  $xml_request->characters("$$query{'KSN'}");
  $xml_request->endTag('KSN');

  ## DeviceSN
  $xml_request->startTag('DeviceSN');
  $xml_request->characters("$$query{'DeviceSN'}");
  $xml_request->endTag('DeviceSN');

  ## MPStatus
  $xml_request->startTag('MPStatus');
  $xml_request->characters("$$query{'MPStatus'}");
  $xml_request->endTag('MPStatus');

  ## CustTranID
  $xml_request->startTag('CustTranID');
  $xml_request->characters("$$query{'orderID'}");
  $xml_request->endTag('CustTranID');

  ## HostID
  $xml_request->startTag('HostID');
  $xml_request->characters("$$query{'HostID'}");
  $xml_request->endTag('HostID');

  ## HostPwd
  $xml_request->startTag('HostPwd');
  $xml_request->characters("$$query{'HostPwd'}");
  $xml_request->endTag('HostPwd');

  ## OutputFormatCode
  $xml_request->startTag('OutputFormatCode');
  $xml_request->characters("$$query{'OutputFormatCode'}");
  $xml_request->endTag('OutputFormatCode');

  ## CardType
  $xml_request->startTag('CardType');
  $xml_request->characters("$$query{'CardType'}");
  $xml_request->endTag('CardType');

  ## EncryptionBlockType
  $xml_request->startTag('EncryptionBlockType');
  $xml_request->characters("$$query{'EncryptionBlockType'}");
  $xml_request->endTag('EncryptionBlockType');

  ## RegisteredBy
  $xml_request->startTag('RegisteredBy');
  $xml_request->characters("$$query{'RegisteredBy'}");
  $xml_request->endTag('RegisteredBy');

  ## FutureInput
  $xml_request->startTag('FutureInput');
  $xml_request->characters("$$query{'FutureInput'}");
  $xml_request->endTag('FutureInput');

  $xml_request->endTag('DecryptRSV201_Input');

  $xml_request->endTag('DecryptRSV201');

  $xml_request->endTag('soap12:Body');

  $xml_request->endTag('soap12:Envelope');
  $xml_request->end;

  

  #print "$output\n\n";

  return "$output";

}


sub build_XML_10 {
  my($query) = @_;
  my (%result,%req,%error,$res,$pairs,$message,$resp,$header);
  my $url = "https://ws.magensa.net/WSMagensa/Service.asmx";
  my $host = "http://www.magensa.net/";
  my $output = "";
  my $agent = "SOAP::Lite/Perl/v0.710.8";
  my $contype = "application/soap+xml";

  require XML::Simple;
  require XML::Writer;
  require LWP::UserAgent;

  my $xml_request = XML::Writer->new(OUTPUT => \$output, NEWLINES => 0);

  $xml_request->xmlDecl("UTF-8");
  $xml_request->startTag('soap:Envelope',
              'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
              #'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/',  ####?
              'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema',
              #'soap:encodingStyle' => 'http://schemas.xmlsoap.org/soap/encoding/',  ####?
              #'xmlns:soap' => 'http://www.w3.org/2003/05/soap-envelope');
              'xmlns:soap' => 'http://schemas.xmlsoap.org/soap/envelope/');

  $xml_request->startTag('soap:Body');

  $xml_request->startTag('DecryptRSV201','xmlns' => "$host");

  $xml_request->startTag('DecryptRSV201_Input');

  ## EncTrack1
  $xml_request->startTag('EncTrack1');
  $xml_request->characters("$$query{'EncTrack1'}");
  $xml_request->endTag('EncTrack1');

  ## EncTrack2
  $xml_request->startTag('EncTrack2');
  $xml_request->characters("$$query{'EncTrack2'}");
  $xml_request->endTag('EncTrack2');

  ## EncTrack3
  $xml_request->startTag('EncTrack3');
  $xml_request->characters("$$query{'EncTrack3'}");
  $xml_request->endTag('EncTrack3');

  ## EncMP
  $xml_request->startTag('EncMP');
  $xml_request->characters("$$query{'EncMP'}");
  $xml_request->endTag('EncMP');

  ## KSN
  $xml_request->startTag('KSN');
  $xml_request->characters("$$query{'KSN'}");
  $xml_request->endTag('KSN');

  ## DeviceSN
  $xml_request->startTag('DeviceSN');
  $xml_request->characters("$$query{'DeviceSN'}");
  $xml_request->endTag('DeviceSN');

  ## MPStatus
  $xml_request->startTag('MPStatus');
  $xml_request->characters("$$query{'MPStatus'}");
  $xml_request->endTag('MPStatus');

  ## CustTranID
  $xml_request->startTag('CustTranID');
  $xml_request->characters("$$query{'orderID'}");
  $xml_request->endTag('CustTranID');

  ## HostID
  $xml_request->startTag('HostID');
  $xml_request->characters("$$query{'HostID'}");
  $xml_request->endTag('HostID');

  ## HostPwd
  $xml_request->startTag('HostPwd');
  $xml_request->characters("$$query{'HostPwd'}");
  $xml_request->endTag('HostPwd');

  ## OutputFormatCode
  $xml_request->startTag('OutputFormatCode');
  $xml_request->characters("$$query{'OutputFormatCode'}");
  $xml_request->endTag('OutputFormatCode');

  ## CardType
  $xml_request->startTag('CardType');
  $xml_request->characters("$$query{'CardType'}");
  $xml_request->endTag('CardType');

  ## EncryptionBlockType
  $xml_request->startTag('EncryptionBlockType');
  $xml_request->characters("$$query{'EncryptionBlockType'}");
  $xml_request->endTag('EncryptionBlockType');

  ## RegisteredBy
  $xml_request->startTag('RegisteredBy');
  $xml_request->characters("$$query{'RegisteredBy'}");
  $xml_request->endTag('RegisteredBy');

  ## FutureInput
  $xml_request->startTag('FutureInput');
  $xml_request->characters("$$query{'FutureInput'}");
  $xml_request->endTag('FutureInput');

  $xml_request->endTag('DecryptRSV201_Input');

  $xml_request->endTag('DecryptRSV201');

  $xml_request->endTag('soap:Body');

  $xml_request->endTag('soap:Envelope');
  $xml_request->end;


  #print "$output\n\n";

  return "$output";

}



sub sendXML {
  my ($output,$testmode) = @_;


  if(1) {
    open (DEBUG,">>/home/p/pay1/database/debug/magensa_debug.txt");
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    print DEBUG "DATE:$now, TESTMODE:$testmode, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, IP:$ENV{'REMOTE_ADDR'}, PID:$$,\n";
    print DEBUG "RAW MSG:$output\n";
    close(DEBUG);
  }

  require LWP::UserAgent;
  my ($orig_cert,$orig_key,$url);
  my (%result,%req,%error,$res,$pairs,$message,$resp,$header);

  if ($testmode == 1) {
    $url = "https://ws.magensa.net/WSmagensatest/service.asmx";   ### TEST URL
  }
  else {
    if (exists $ENV{HTTPS_CERT_FILE}) {
      $orig_cert = $ENV{HTTPS_CERT_FILE};
    }
    if (exists $ENV{HTTPS_KEY_FILE}) {
      $orig_key = $ENV{HTTPS_KEY_FILE};
    }
    $ENV{'HTTPS_CERT_FILE'} = '/home/p/pay1/perl_lib/magensa_cert.pem';
    $ENV{'HTTPS_KEY_FILE'}  = '/home/p/pay1/perl_lib/magensa_key.pem';

    $url = "https://ns.magensa.net/WSMagensa/service.asmx";
    #$url = "https://ws.magensa.net/wsmagensa/service.asmx";  ### Prodution URL
  }

  my $agent = "SOAP::Lite/Perl/v0.710.8";
  my $contype = "text/xml; charset='utf-8'";


  #print "Output:$output\n";


  #if (1) {
  my $ua = new LWP::UserAgent;
  #$ua->agent($agent);
  $ua->timeout(5);

  my $req = new HTTP::Request POST => $url;
  $req->content_type($contype);
  $req->header( 'SOAPAction' => 'http://www.magensa.net/DecryptRSV201');
  $req->content($output);

  my $res = $ua->request($req);

  if ($res->is_success) {
     $resp =  $res->content;
  }
  elsif ($res->is_error) {
    $resp = $res->error_as_HTML;
  }
  else {
    $resp = "Blank";
    # handle a bad post here??
  }



  if ($testmode == 1) {
    ## Do Nothing
  }
  else {
    if ($orig_cert ne "") {
      $ENV{HTTPS_CERT_FILE} = $orig_cert;
    }
    else {
      delete $ENV{HTTPS_CERT_FILE};
    }
    if ($orig_key ne "") {
      $ENV{HTTPS_KEY_FILE} = $orig_key;
    }
    else {
      delete $ENV{HTTPS_KEY_FILE};
    }
  }

  #my $response = $res->is_success;

  #print "RESP:$resp\n\n";
  #}

  if(1) {
    my $logresp = $resp;
    $logresp =~ s/<PAN>(\d{4})\d+(\d{2})<\/PAN>/<PAN>$1*****$2<\/PAN>/;
    open (DEBUG,">>/home/p/pay1/database/debug/magensa_debug.txt");
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    print DEBUG "DATE:$now, TESTMODE:$testmode, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$$, TESTMODE:$testmode, URL:$url\n";
    print DEBUG "RAW RESPONSE:$logresp\n\n";
    close(DEBUG);
  }

  #if (1) {
  if ($resp =~ /xml version/i) {
    require XML::Simple;
    my $parser = XML::Simple->new();
    my $xmldoc = $parser->XMLin($resp);

    $result{'MagensaID'} = $xmldoc->{'soap:Body'}->{'DecryptRSV201Response'}->{'DecryptRSV201Result'}->{'MagensaID'};
    $result{'StatusMsg'} = $xmldoc->{'soap:Body'}->{'DecryptRSV201Response'}->{'DecryptRSV201Result'}->{'StatusMsg'};
    $result{'StatusCode'} = $xmldoc->{'soap:Body'}->{'DecryptRSV201Response'}->{'DecryptRSV201Result'}->{'StatusCode'};
    $result{'Track1'} = $xmldoc->{'soap:Body'}->{'DecryptRSV201Response'}->{'DecryptRSV201Result'}->{'Track1'};
    $result{'Track2'} = $xmldoc->{'soap:Body'}->{'DecryptRSV201Response'}->{'DecryptRSV201Result'}->{'Track2'};
    $result{'Track3'} = $xmldoc->{'soap:Body'}->{'DecryptRSV201Response'}->{'DecryptRSV201Result'}->{'Track3'};
    $result{'PAN'} = $xmldoc->{'soap:Body'}->{'DecryptRSV201Response'}->{'DecryptRSV201Result'}->{'PAN'};
    $result{'Score'} = $xmldoc->{'soap:Body'}->{'DecryptRSV201Response'}->{'DecryptRSV201Result'}->{'Score'};
    $result{'FutureOutput'} = $xmldoc->{'soap:Body'}->{'DecryptRSV201Response'}->{'DecryptRSV201Result'}->{'FutureOutput'};
  }
  #}

  if (1) {
    open (DEBUG,">>/home/p/pay1/database/debug/magensa_debug.txt");
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    print DEBUG "PARSED RESPONSE DATE:$now, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$$, ";
    foreach my $key (sort keys %result) {
      #if ($testmode == 1) {
      #  print DEBUG "$key:$result{$key}, ";
      #}
      #els
      if ($key eq "PAN") {
        print DEBUG "$key:********, ";
      }
      else {
        print DEBUG "$key:$result{$key}, ";
      }
    }
    print DEBUG "\n\n\n";
    close(DEBUG);
  }

  #foreach my $key (sort keys %result) {
  #  print "KA:$key:$result{$key}\n";
  #}

  return %result;
}


1;
