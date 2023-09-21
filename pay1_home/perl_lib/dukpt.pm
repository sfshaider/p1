#!/usr/local/bin/perl

package dukpt;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use rsautils;
use smpsutils;
use Crypt::CBC;
use Crypt::DES;
use PlugNPay::Client::Magensa;
use PlugNPay::Email;
use strict;

# call Magensa Processor's decrypt function
sub magensaProcessorDecrypt {
  #my ($query,$variant,$debug) = @_;
  my ($query, $debug) = @_;

  my $debugLine = "$$query{'KSN'}";

  if ($$query{'EncTrack2'} eq ";E\?") {
    $$query{'EncTrack2'} = "";
  }

  my %result = ();

  # invalid EncTrack1 format H176
  if ($$query{'EncTrack1'} =~ /[^0-9a-zA-Z]/) {
    $result{'StatusCode'} = "H176";
    $result{'StatusMsg'} = "Invalid EncTrack1 format";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid EncTrack1 length H177
  if (length($$query{'EncTrack1'}) % 8 != 0) {
    $result{'StatusCode'} = "H177";
    $result{'StatusMsg'} = "Invalid EncTrack1 length";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid EncTrack2 format H178
  if ($$query{'EncTrack2'} =~ /[^0-9a-zA-Z]/) {
    $result{'StatusCode'} = "H178";
    $result{'StatusMsg'} = "Invalid EncTrack2 format";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid EncTrack2 length H179
  if (length($$query{'EncTrack2'}) % 8 != 0) {
    $result{'StatusCode'} = "H179";
    $result{'StatusMsg'} = "Invalid EncTrack2 length";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid KSN format H186
  if ($$query{'KSN'} =~ /[^0-9a-zA-Z]/) {
    $result{'StatusCode'} = "H186";
    $result{'StatusMsg'} = "Invalid KSN format";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid KSN length H187
  if (length($$query{'KSN'}) != 20) {
    $result{'StatusCode'} = "H187";
    $result{'StatusMsg'} = "Invalid KSN length";
     my $len = length($$query{'KSN'});
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $len $debugLine\n");
    return %result;
  }

  my ($track1,$track2,$postalCode,$status,$msg);
  
  my $processor = new PlugNPay::Client::Magensa();
  my $responses = $processor->runRequest(\%$query);
  my %procesor_results = %{$responses};
    
  my $track1 = $procesor_results{'Track1'};
  my $track2 = $procesor_results{'Track2'};
  
  if ($track1 !~ /^\%M/) {
    $result{'magstripe'} = $track1 . $track2;
  }
  $result{'Track1'} = $track1;
  $result{'Track2'} = $track2;

  # invalid card type H206  leave out
  # no PAN in track 2 data Y001 leave out

  my ($magstripetrack,$magstripe,$cardnum,$expdate) = &smpsutils::checkmagstripe("$track1$track2");

  $result{'card-number'} = $cardnum;
  $result{'card-exp'} = $expdate;
  if ($postalCode ne "") {
    $result{'card-zip'} = $postalCode;
  }
  if ($magstripetrack =~ /1|2/) {
    $result{'StatusCode'} = "1000";
  }
  elsif ($status ne "1000") {
    $result{'StatusCode'} = $status;
    $result{'StatusMsg'} = $msg;
  }
  else {
    $result{'StatusCode'} = "Y098";
    $result{'StatusMsg'} = "Problem decrypting data";
  }

  &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
  return %result;
}


sub magtekdecrypt {
  my ($query,$inputVariant,$debug) = @_;

  my $debugLine = "$$query{'KSN'}";

  if ($$query{'EncTrack2'} eq ";E\?") {
    $$query{'EncTrack2'} = "";
  }

  my %result = ();

  # invalid EncTrack1 format H176
  if ($$query{'EncTrack1'} =~ /[^0-9a-zA-Z]/) {
    $result{'StatusCode'} = "H176";
    $result{'StatusMsg'} = "Invalid EncTrack1 format";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid EncTrack1 length H177
  if (length($$query{'EncTrack1'}) % 8 != 0) {
    $result{'StatusCode'} = "H177";
    $result{'StatusMsg'} = "Invalid EncTrack1 length";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid EncTrack2 format H178
  if ($$query{'EncTrack2'} =~ /[^0-9a-zA-Z]/) {
    $result{'StatusCode'} = "H178";
    $result{'StatusMsg'} = "Invalid EncTrack2 format";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid EncTrack2 length H179
  if (length($$query{'EncTrack2'}) % 8 != 0) {
    $result{'StatusCode'} = "H179";
    $result{'StatusMsg'} = "Invalid EncTrack2 length";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid KSN format H186
  if ($$query{'KSN'} =~ /[^0-9a-zA-Z]/) {
    $result{'StatusCode'} = "H186";
    $result{'StatusMsg'} = "Invalid KSN format";
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    return %result;
  }

  # invalid KSN length H187
  if (length($$query{'KSN'}) != 20) {
    $result{'StatusCode'} = "H187";
    $result{'StatusMsg'} = "Invalid KSN length";
     my $len = length($$query{'KSN'});
    &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $len $debugLine\n");
    return %result;
  }


  my $ksidData = {};
  eval {
    my $ksn = $query->{'KSN'};
    my $ksid = ksidFromKsn($ksn);
    my $ksidData = loadKsidData($ksn);
  };

  my $variant = $ksidData->{'key_variant'} || $inputVariant;

  if ($debug eq "") {
    # make sure ksn has not been used before Y097
    my $dbh = &miscutils::dbhconnect("pnpmisc");

    my $sth = $dbh->prepare(qq{
        select trans_date,ksn
        from dukptksn
        where ksn=?
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
    $sth->execute($$query{'KSN'}) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
    my ($trans_date,$chkksn) = $sth->fetchrow;
    $sth->finish;

    # if ($chkksn ne "") {
    #   $result{'StatusCode'} = "Y097";
    #   $result{'StatusMsg'} = "KSN used before";
    #   &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
    #   return %result;
    # }

    if ($chkksn eq "") {
      my ($trans_date) = &miscutils::gendatetime_only();
      my $sth = $dbh->prepare(q{
          insert into dukptksn
          (trans_date,ksn)
          values (?,?)
          }) or &miscutils::errmaildie(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%$query);
      $sth->execute($trans_date,$$query{'KSN'})
              or &miscutils::errmaildie(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%$query);
      $sth->finish;

      $dbh->disconnect;
    }
  }

  my ($track1,$track2,$postalCode,$status,$msg);
  if ($$query{'EncTrack1'} ne "") {
    ($track1) = &dukptdecrypt($$query{'KSN'},$$query{'EncTrack1'},$variant);
    if ($track1 =~ /[^\x00-\x7f]/) {
      $status = "Y098";
      $msg = "Problem decrypting track 1 data";
    }
    else {
      $track1 =~ s/\x00//g;
      $status = "1000";
    }
  }
  if ($$query{'EncTrack2'} ne "") {
    ($track2) = &dukptdecrypt($$query{'KSN'},$$query{'EncTrack2'},$variant);
    if ($track2 =~ /[^\x00-\x7f]/) {
      $status = "Y098";
      $msg = "Problem decrypting track 2 data";
    }
    else {
      $track2 =~ s/\x00//g;
      $status = "1000";
    }
    $track2 =~ s/\x00//g;
  }
  if ($$query{'EncPostalKSN'} ne "") {
    ($postalCode) = &dukptdecrypt($$query{'EncPostalKSN'},$$query{'EncPostalCode'},'dataenc1');
    $postalCode = unpack "H*", $postalCode;
    if ($postalCode =~ /[^\x00-\x7f]/) {
      $status = "Y098";
      $msg = "Problem decrypting data";
    }
    else {
      $postalCode  =~ s/\x00//g;
      $postalCode = substr($postalCode,2,5);
      $status = "1000";
    }
  }

  if ($track1 !~ /^\%M/) {
    $result{'magstripe'} = $track1 . $track2;
  }
  $result{'Track1'} = $track1;
  $result{'Track2'} = $track2;

  # invalid card type H206  leave out
  # no PAN in track 2 data Y001 leave out

  my ($magstripetrack,$magstripe,$cardnum,$expdate) = &smpsutils::checkmagstripe("$track1$track2");

  $result{'card-number'} = $cardnum;
  $result{'card-exp'} = $expdate;
  if ($postalCode ne "") {
    $result{'card-zip'} = $postalCode;
  }
  if ($magstripetrack =~ /1|2/) {
    $result{'StatusCode'} = "1000";
  }
  elsif ($status ne "1000") {
    $result{'StatusCode'} = $status;
    $result{'StatusMsg'} = $msg;
  }
  else {
    $result{'StatusCode'} = "Y098";
    $result{'StatusMsg'} = "Problem decrypting data";
  }

  &logmsg("$result{'StatusCode'}: $result{'StatusMsg'} $debugLine\n");
  return %result;
}


sub logmsg {
  my ($msg) = @_;

  my $mytime = gmtime(time());
  open(outfile,">>/home/p/pay1/batchfiles/magtek/serverlogmsg.txt");
  print outfile "$mytime $msg\n";
  close(outfile);
}


sub dukptdecrypt {
  my ($ksn,$encData,$variantstr) = @_;

  my $ksnpadded = substr("F" x 20 . $ksn,-20,20);
  $ksnpadded = pack "H*", $ksnpadded;
  $ksnpadded = $ksnpadded & pack "H*", "ffffffffffffffe00000";	# set rightmost 21 bits to 0
  my $ksnpad = unpack "H*", $ksnpadded;

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(qq{
        select encipek
        from dukpt
        where ksn='$ksnpad'
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  my ($encipek) = $sth->fetchrow;
  $sth->finish;

  my $injectstatus = "";

  if ($encipek eq "") {
    my %pwdHash;
    my $sth = $dbh->prepare(qq{
      select ksn,bdk_token
      from bdk_token
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
    my $bdkData = $sth->fetchall_arrayref({});
    $sth->finish;

    foreach my $data (@{$bdkData}) {
      $pwdHash{$data->{'ksn'}} = $data->{'bdk_token'};
    }

    my $shortksn = substr($ksnpad,0,7);
    $shortksn =~ tr/A-F/a-f/;

    my $tokenizedPwd = $pwdHash{$shortksn};
    my $cc = new PlugNPay::Token();
    my $redeemedPwd = $cc->fromToken($tokenizedPwd,'PROCESSING');
    $redeemedPwd  =~ s/%(..)/pack('c',hex($1))/eg;
    $redeemedPwd =~ s/\+/ /g;

    if ($redeemedPwd eq "") {
      my $now = gmtime(time());
      open(LOGFILE,">>/home/pay1/logfiles/magserverlogmsg.txt");
      print LOGFILE "$now, Token Server Failure\n";
      close(LOGFILE);
    }
    else {
      my ($bdk1,$bdk2) = split(/ /,$redeemedPwd);
      $injectstatus = &dukpt::injectipek1("$ksnpad","$bdk1");
      if ($injectstatus eq "success") {
        $injectstatus = &dukpt::injectipek("$ksnpad","$bdk2");
      }
      my $sth = $dbh->prepare(qq{
            select encipek
            from dukpt
            where ksn='$ksnpad'
            }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
      $sth->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
      ($encipek) = $sth->fetchrow;
      $sth->finish;
    }
  }

  $dbh->disconnect;

  if ($encipek eq "") {
    # invalid KSID Y091
    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setFormat('text');
    $emailObj->setTo('cprice@plugnpay.com');
    $emailObj->setCC('dprice@plugnpay.com');
    $emailObj->setFrom('dprice@plugnpay.com');
    $emailObj->setSubject('new ksid');

    my $message = '';
    $message .= "new ksid: $ksnpad\n";
    $message .= "injectstatus: $injectstatus\n";
 
    $emailObj->setContent($message);
    $emailObj->send();

    return "","","Y091","Invalid KSID";		# invalid KSID
  }

  my $ipek = &rsautils::rsa_decrypt_file($encipek,"64","print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");

  $ipek = pack "H*", $ipek;
  # ipek encrypts ksn several times to get transaction key

  my $ksnpacked = pack "H*", $ksn;
  my $transcnt = substr($ksnpacked,-4,4);
  $transcnt = $transcnt & pack "H*", "001fffff";	# get rightmost 21 bits

  my $ksnright64 = substr($ksn,-16,16);	# get rightmost 64 bits
  $ksnright64 = pack "H*", $ksnright64;

  my $key = $ipek;
  my $data = $ksnright64 & pack "H*", "ffffffffffe00000";

  for (my $i=20; $i>=0; $i--) {
    my $num = 2 ** $i;
    $num = pack "N", $num;

    my $sum = $transcnt & $num;

    my $numval = unpack "H*", $num;
    my $sumval = unpack "H*", $sum;

    if ($sumval == $numval) {

      my $newnum = "00000000" . $numval;
      $newnum = pack "H*", $newnum;

      # must keep these lines
      $data = unpack "H*", $data;
      $data = pack "H*", $data;
      $newnum = unpack "H*", $newnum;
      $newnum = pack "H*", $newnum;
      # must keep these lines

      $data = $data | $newnum;

      $key = &nonrevkeygen($data,$key);

    }
  }

  # xor the key with the variant for multiple keys
  #my $variant = "0000000000FF00000000000000FF0000";	# data encryption variant   used with ansi test
  #my $variant = "00000000000000000000000000000000";	# no encryption variant

  my $variant = "00000000000000FF00000000000000FF";	# pin encryption variant
  #$variant = "000000000000FF00000000000000FF00";	# message authentication encryption variant
  #$variant = "0000000000FF00000000000000FF0000";	# message authentication response encryption variant

  if ($variantstr eq "dataenc1") {
    $variant = "0000000000FF00000000000000FF0000";	# data encryption variant    do tdes on keys
  }
  #$variant = "000000FF00000000000000FF00000000";	# data encryption variant    do tdes on keys

  #my $variant = "00000000000000000000000000000000";       # no encryption variant
  #my $variant = "00000000000000FF00000000000000FF";       # pin encryption variant
  #my $variant = "000000000000FF00000000000000FF00";       # message authentication encryption variant
  #my $variant = "0000000000FF00000000000000FF0000";       # message authentication response encryption variant
  #my $variant = "00000000FF00000000000000FF000000";       # message authentication response encryption variant
  #my $variant = "000000FF00000000000000FF00000000";       # data encryption variant    do tdes on keys

  $variant = pack "H*", $variant;
  my $varkey = $key ^ $variant;

  if ($variantstr eq "dataenc1") {		# this area not used for pin or message authentication encryption
    my $varkeyleft = substr($varkey,0,8);
    my $varkeyright = substr($varkey,8,16);

    my $newkeyleft = &tdesencrypt($varkeyleft,$varkey);	# single DES
    my $newkeyright = &tdesencrypt($varkeyright,$varkey);	# single DES

    $varkey = $newkeyleft . $newkeyright;
  }

  # decrypt data

  my $clearData = "";
  if ($encData ne "") {
    $encData = pack "H*", $encData;
    $clearData = &tdesdecrypt($encData,$varkey);
  }

  return $clearData;
}

sub injectipek1 {
  my ($ksn,$bdk1) = @_;

  if ($bdk1 !~ /^[0-9a-fA-F]{32}$/) {
    return "error, bad bdk1";
  }

  if ($ksn !~ /^[0-9a-fA-F]{20}$/) {
    return "error, bad ksn";
  }

  my $ksnpad = ksidFromKsn($ksn);

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(qq{
        select trans_date,encipek
        from dukpt
        where ksn='$ksnpad'
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  my ($trans_date,$encipek) = $sth->fetchrow;
  $sth->finish;

  if ($encipek ne "") {
    #"error, ipek already injected $trans_date\n";
    return "success";
  }

  my ($encbdk1) = &rsautils::rsa_encrypt_card($bdk1,'/home/p/pay1/pwfiles/keys/key','');

  my ($trans_date) = &miscutils::gendatetime_only();

  my $sth = $dbh->prepare(q{
        insert into dukpt
        (trans_date,ksn,encipek,status)
        values (?,?,?,?)
        }) or &miscutils::errmaildie(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute("$trans_date","$ksnpad","$encbdk1","pending")
             or &miscutils::errmaildie(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  $sth->finish;

  $dbh->disconnect;

  return "success";

}


sub injectipek {
  my ($ksn,$bdk2) = @_;

  if ($bdk2 !~ /^[0-9a-fA-F]{32}$/) {
    return "error, bad bdk2";
  }

  if ($ksn !~ /^[0-9a-fA-F]{20}$/) {
    return "error, bad ksn";
  }

  my $ksnpad = ksidFromKsn($ksn);

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbh->prepare(qq{
        select encipek
        from dukpt
        where ksn='$ksnpad'
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  my ($encbdk1) = $sth->fetchrow;
  $sth->finish;

  my $bdk1 = &rsautils::rsa_decrypt_file($encbdk1,"64","print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");

  if ($bdk1 !~ /^[0-9a-fA-F]{32}$/) {
    return "error, bad bdk1";
  }

  my $bdk1 = pack 'H*', $bdk1;
  my $bdk2 = pack 'H*', $bdk2;
  my $bdk = $bdk1 ^ $bdk2;
  $bdk = unpack 'H*', $bdk;

  if (length($bdk) != 32) {
    return "error, bad bdk $bdk";
  }

  # unpack $ksnpad for manipulation
  my $ksnpadded = pack "H*", $ksnpad;

  my $left8ksn = substr($ksnpadded,0,8);
  my $right8ksn = substr($ksnpadded,8,16);

  my $bdkpacked = pack "H*", $bdk;
  my $ipekleft = &tdesencrypt($left8ksn,$bdkpacked); # double DES

  my $xor = pack "H*", "c0c0c0c000000000c0c0c0c000000000";
  my $bdkxor = $bdkpacked ^ $xor;

  my $ipekright = &tdesencrypt($left8ksn,$bdkxor);   # double DES

  my $ipek = $ipekleft . $ipekright;

  $ipek = unpack "H*", $ipek;

  my ($encipek) = &rsautils::rsa_encrypt_card($ipek,'/home/p/pay1/pwfiles/keys/key','');

  my $sth2 = $dbh->prepare(qq{
        update dukpt set encipek=?,status='done'
        where ksn='$ksnpad'
        }) or &miscutils::errmaildie(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth2->execute("$encipek")
             or &miscutils::errmaildie(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  $sth2->finish;

  $dbh->disconnect;

}


sub nonrevkeygen {
  my ($data, $key) = @_;

  # must keep these lines
  $data = unpack "H*", $data;
  $data = pack "H*", $data;
  $key = unpack "H*", $key;
  $key = pack "H*", $key;
  # must keep these lines

  my $keyleft = substr($key,0,8);
  my $keyright = substr($key,8,8);

  my $dataright = $data ^ $keyright;

  $dataright = &tdesencrypt($dataright,$keyleft);	# single DES
  $dataright = $dataright ^ $keyright;

  my $c0c0 = pack "H16", "c0c0c0c000000000";
  $keyleft = $keyleft ^ $c0c0;
  $keyright = $keyright ^ $c0c0;

  my $dataleft = $data ^ $keyright;
  $dataleft = &tdesencrypt($dataleft,$keyleft);	# single DES
  $dataleft = $dataleft ^ $keyright;

  return $dataleft . $dataright;
  
}


sub tdesencrypt {
  my ($data, $key) = @_;

  my $keyleft = substr($key,0,8);
  my $keymiddle = substr($key,8,8);
  my $keyright = substr($key,16,8);

  if ($keymiddle eq "") {
    $keymiddle = $keyleft;
    $keyright = $keyleft;
    #single des
  }
  elsif ($keyright eq "") {
    $keyright = $keyleft;
    #double des
  }
  else {
    #triple des
  }

  my $cipher1 = new Crypt::DES $keyleft;
  my $cipher2 = new Crypt::DES $keymiddle;
  my $cipher3 = new Crypt::DES $keyright;
  $data = $cipher1->encrypt($data);  # can only be 8 bytes
  $data = $cipher2->decrypt($data);  # can only be 8 bytes
  $data = $cipher3->encrypt($data);  # can only be 8 bytes

  return $data;
}


sub tdesdecrypt {
  my ($data, $key) = @_;

  my $keyleft = substr($key,0,8);
  my $keymiddle = substr($key,8,8);
  my $keyright = substr($key,16,8);

  if ($keymiddle eq "") {
    $keymiddle = $keyleft;
    $keyright = $keyleft;
    #single des
  }
  elsif ($keyright eq "") {
    $keyright = $keyleft;
    #double des
  }
  else {
    #triple des
  }

  my $cipher1 = new Crypt::DES $keyleft;
  my $cipher2 = new Crypt::DES $keymiddle;
  my $cipher3 = new Crypt::DES $keyright;

  my $result = "";
  my $cipher = pack "H*", "0000000000000000";
  for (my $idx=0; $idx<length($data); $idx=$idx+8) {
    my $encdata = substr($data,$idx,8);

    my $decdata = $cipher1->decrypt($encdata);  # can only be 8 bytes
    $decdata = $cipher2->encrypt($decdata);  # can only be 8 bytes
    $decdata = $cipher3->decrypt($decdata);  # can only be 8 bytes

    $decdata = $decdata ^ $cipher;

    $cipher = $encdata;

    $result = $result . $decdata;

  }


  return $result;
}

sub ksidFromKsn {
  my $ksn = shift;

  my $ksnpadded = substr("F" x 20 . $ksn,-20,20);
  $ksnpadded = pack "H*", $ksnpadded;

  my $ksidPadded = $ksnpadded & pack "H*", "ffffffffffffffe00000";	# set rightmost 21 bits to 0
  my $ksid = unpack "H*", $ksidPadded;

  return $ksid;
}

sub loadKsidData {
  my $ksid = shift;

  my $query = createDukptTableQuery();

  my $dbs = new PlugNPay::DBConnection();
  my %ksidData;
  my $result = $dbs->fetchallOrDie('pnpmisc',$query,[$ksid],{});
  my $rows = $result->{'rows'};
  if (defined $rows->[0]) {
    %ksidData = %{$rows->[0]};

    # populate default values for columns that may not exist
    $ksidData{'key_type'} ||= '';
    $ksidData{'key_variant'} ||= '';
    $ksidData{'username'} ||= '';
    $ksidData{'ksid'} = $ksidData{'ksn'}; # because it's the ksid
  }

  if ($ksidData{'ksn'} ne $ksid) {
    die('Failed to load data for ksid');
  }

  return \%ksidData;
}

sub createDukptTableQuery {
  my $dbs = new PlugNPay::DBConnection();
  my $columnInfo = $dbs->getColumnsForTable({
    database => 'pnpmisc',
    table => 'dukpt'
  });

  my @columnsToLoad = keys %{$columnInfo};

  my $query = sprintf('SELECT %s FROM dukpt WHERE ksn = ?',join(',',@columnsToLoad));

  return $query;
}

1;


