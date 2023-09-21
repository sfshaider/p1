#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use IO::Socket;
use Socket;
use rsautils;
use PlugNPay::CreditCard;

#old Hagerstown 8  host 206.201.50.48 ports 16924, 16925
#old Denver 5 host  206.201.53.72 ports 16935, 16936.

# keya keyb 5578 5579 netb uses these ipc addresses

$test    = "no";
$devprod = "logs";

$host = "processor-host";    # Source IP address

$primaryipaddress   = "167.16.0.54";     # primary production server
$primaryport        = "30056";           # primary production server
$secondaryipaddress = "167.16.0.154";    # secondary production server
$secondaryport      = "30056";           # secondary production server

$port = $primaryport;

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;

$nullmessage1 = "aa77000d0011";
$nullmessage2 = "aa550d001100";

if ( $test eq "yes" ) {

  $ipaddress = "167.16.0.125";    # test server
  $port      = "23219";           # test server
} elsif ( ( -e "/home/pay1/batchfiles/$devprod/fdmsintl/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to secondary socket\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $secondaryipaddress;
  $port      = $secondaryport;
} elsif ( !( -e "/home/pay1/batchfiles/$devprod/fdmsintl/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to primary socket\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $primaryipaddress;
  $port      = $primaryport;
}

while ( $socketopenflag != 1 ) {
  &socketopenalarm();
}
&socketread(0);

# delete rows older than 2 minutes
my $now     = time();
my $deltime = &miscutils::timetostr( $now - 120 );

my $dbquerystr = <<"dbEOM";
        delete from processormsg
        where trans_time<?
          or trans_time is NULL or trans_time=''
        and processor='fdmsintl'
dbEOM
my @dbvalues = ("$deltime");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

while (1) {
  $temptime   = time();
  $outfilestr = "";
  $outfilestr .= "$temptime\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "accesstime.txt", "write", "", $outfilestr );

  if ( ( -e "/home/pay1/batchfiles/$devprod/fdmsintl/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
    close(SOCK);
    sleep 1;
    exit;
  }

  $keepalivecnt++;
  if ( $keepalivecnt >= 60 ) {
    my $printstr = "keepalivecnt = $keepalivecnt\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
    $keepalivecnt = 0;

    &checksocket();

  }

  while ( $socketopenflag != 1 ) {
    &socketopenalarm();
  }

  &check();
  if ( $getrespflag == 0 ) {
    &socketclose();

    &checksocket();

  }
  select undef, undef, undef, 1.00;
}

exit;

sub check {
  $todayseconds = time();
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - ( 60 * 2 ) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  if ( ( -e "/home/pay1/batchfiles/$devprod/fdmsintl/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
    close(SOCK);
    sleep 1;
    exit;
  }

  foreach $key ( keys %writearray ) {
    if ( $writearray{$key} < $ttime1 ) {
      delete $writearray{$key};
    }
  }

  $transcnt = 0;

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message,response,status
        from processormsg
        where processor='fdmsintl'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sth1valarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sth1valarray) ; $vali = $vali + 7 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage, $encmsgresponse, $processormsgstatus ) = @sth1valarray[ $vali .. $vali + 6 ];

    my $printstr = "$orderid $processormsgstatus\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    $message     = &rsautils::rsa_decrypt_file( $encmessage,     "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );
    $msgresponse = &rsautils::rsa_decrypt_file( $encmsgresponse, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    # void if transaction never finished after 45 seconds
    if ( $processormsgstatus eq "success" ) {
      my $now    = time();
      my $mytime = &miscutils::strtotime($trans_time);
      my $delta  = $now - $mytime;

      if ( $delta > 45 ) {
        my $messtype = substr( $message, 6, 2 );
        $messtype = unpack "H*", $messtype;

        if ( $messtype eq "0100" ) {

          my $dbquerystr = <<"dbEOM";
                delete from processormsg
                where username=?
                and orderid=?
                and processor='fdmsintl'
dbEOM
          my @dbvalues = ( "$username", "$orderid" );
          &procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

          $logfilestr = "";
          $logfilestr .= "delete from processormsg $username $orderid\n";
          &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
        }
      }
      next;
    }

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $username =~ s/[^0-9a-zA-Z_]//g;
    $trans_time =~ s/[^0-9]//g;
    $orderid =~ s/[^0-9]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;

    my $printstr = "$mytime msgrcv $username $orderid\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &procutils::updateprocmsg( $processid, "fdmsintl", "failure", "", "failure: message timeout" );

      next;
    }

    $transcnt++;

    &decodebitmap($message);

    if ( $msgvalues[11] ne "000000" ) {
      $sequencenum = $msgvalues[11];
      $refnum      = $msgvalues[37];
    } else {
      $mainsequencenum = ( $mainsequencenum + 1 ) % 99999;
      $sequencenum     = sprintf( "%06d", $mainsequencenum );
      $newsequencenum  = pack "H6", $sequencenum;
      $message         = substr( $message, 0, $msgvaluesidx[11] ) . $newsequencenum . substr( $message, $msgvaluesidx[11] + 3 );

      $refnum = substr( "0" x 12 . $sequencenum, -12, 12 );
      $message = substr( $message, 0, $msgvaluesidx[37] ) . $refnum . substr( $message, $msgvaluesidx[37] + 12 );
    }

    &decodebitmap( $message, "", "yes" );

    $username =~ s/[^0-9a-zA-Z_]//g;

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;
    $sreason{"$sequencenum"}     = "";
    $sinvoicenum{"$sequencenum"} = $invoicenum;

    &logmessage($message);

    $writearray{$sequencenum} = $trans_time;

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "accesstime.txt", "write", "", $outfilestr );

    if ( $transcnt > 6 ) {
      last;
    }
  }

  if ( $transcnt > 0 ) {
    $numtrans = $transcnt;
    &socketread($transcnt);
  }

  foreach $rsequencenum ( keys %susername ) {
    my $messtype = substr( $smessage{"$rsequencenum"}, 6, 2 );
    $messtype = unpack "H*", $messtype;
    my $printstr = "bbbbbbbbb $messtype\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    if ( $messtype ne "0100" ) {
      next;
    }
    if ( $sstatus{"$rsequencenum"} ne "done" ) {
      my $printstr = "ccccccc\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
      my $now    = time();
      my $mytime = &miscutils::strtotime( $strans_time{$rsequencenum} );
      my $delta  = $now - $mytime;
      if ( $delta > 40 ) {
        my $printstr = "delta > 40\n";
        &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

        my $tmpstr = $smessage{$rsequencenum};
        $tmpstr = unpack "H*", $tmpstr;
        my $tmpstr2 = substr( $tmpstr, 0, 160 );

        if ( (0) && ( $delta < 180 ) && ( $messtype eq "0100" ) ) {    # void all messages
          if (
            ( ( $delta > 40 ) && ( $sretries{"$rsequencenum"} < 2 ) )    # 40
            || ( ( $delta > 80 )  && ( $sretries{"$rsequencenum"} < 3 ) )    # 80
            || ( ( $delta > 120 ) && ( $sretries{"$rsequencenum"} < 4 ) )
            ) {                                                              # 120
            $sretries{"$rsequencenum"}++;
            my $printstr = "comparison passed\n";
            &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
            $respfield63 = "";
            $message = &voidmessage( $smessage{$rsequencenum}, $susername{$rsequencenum}, $rsequencenum );

            &decodebitmap( $message, "", "yes" );

            $checkmessage = $message;

            $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
            $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

            $temptime = gmtime( time() );

            &logmessage($message);

            $transcnt++;
            &socketwrite($message);
            &socketread(4);
            $keepalive = 0;
          }
        } else {
          delete $susername{$rsequencenum};
          delete $strans_time{$rsequencenum};
          delete $smessage{$rsequencenum};
          delete $sretries{$rsequencenum};
          delete $sorderid{$rsequencenum};
          delete $sreason{$rsequencenum};
          delete $sprocessid{$rsequencenum};
          delete $sinvoicenum{$rsequencenum};
          delete $scardtype{$rsequencenum};
          delete $sdatetime{$sequencenum};
          delete $sldatetime{$sequencenum};
        }
      }
    }
  }

}

sub voidmessage {
  my ( $message, $usernm, $rsequencenum ) = @_;

  my $printstr = "in voidmessage\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

  &decodebitmap($message);

  $time = time();
  local ( $sec,  $min,  $hour,  $day,  $month,  $year,  $wday, $yday, $isdst ) = gmtime($time);
  local ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime($time);

  my @transaction = ();

  my $cnum    = "";
  my $expdate = "";
  if ( $msgvalues[2] ne "" ) {
    $cnum = $msgvalues[2];
  } elsif ( $msgvalues[35] ne "" ) {
    my ( $val1, $val2 ) = split( /=/, $msgvalues[35] );
    my $year  = substr( $val2, 0, 2 );
    my $month = substr( $val2, 2, 2 );
    $cnum    = $val1;
    $expdate = "$year$month";
  } elsif ( $msgvalues[45] ne "" ) {
    my ( $val1, $val2, $val3 ) = split( /\^/, $msgvalues[45] );
    my $year  = substr( $val3, 0, 2 );
    my $month = substr( $val3, 2, 2 );
    $val1 =~ s/B//;
    $cnum    = $val1;
    $expdate = "$year$month";
  }
  my $len = length($cnum);
  $len = substr( "00" . $len, -2, 2 );
  $transaction[2] = pack "H2H$len", $len, $cnum;    # primary acct number (19n) 2

  $transaction[3] = pack "H6", $msgvalues[3];       # processing code (6a) 3

  my $amt = substr( "0" x 12 . $msgvalues[4], -12, 12 );
  $transaction[4] = pack "H12", $amt;               # transaction amount (12n) 4

  my $tracenum = substr( "0" x 6 . $msgvalues[11], -6, 6 );
  $transaction[11] = pack "H6", $tracenum;          # system trace number (6n) 11

  my $authtime = substr( "0" x 6 . $msgvalues[12], -6, 6 );
  $transaction[12] = pack "H6", $authtime;          # local time(6n) HHMMSS 12

  my $tdate = substr( "0" x 4 . $msgvalues[13], -4, 4 );
  $transaction[13] = pack "H4", $tdate;             # local date (4n) MMDD 13

  if ( $msgvalues[14] ne "" ) {
    $expdate = substr( "0000" . $msgvalues[14], -4, 4 );
  } else {
    $expdate = substr( "0000" . $expdate, -4, 4 );
  }
  $transaction[14] = pack "H4", $expdate;           # expiration date YYMM (4n)

  my $categorycode = substr( "0000" . $msgvalues[18], -4, 4 );
  $transaction[18] = pack "H4", "$categorycode";    # merchant category code - placeholder only (4n) 18

  my $posentry = substr( "0000" . $msgvalues[22], -4, 4 );
  $transaction[22] = pack "H4", $posentry;          # POS entry mode (3n) 22

  $transaction[24] = pack "H4", "0001";             # network international id (3n) 24

  my $poscond = substr( "00" . $msgvalues[25], -2, 2 );
  $transaction[25] = pack "H2", $poscond;           # POS condition code - ecommerce (2n) 25

  $transaction[37] = $msgvalues[37];                # retrieval reference number (12a) 37

  $transaction[41] = $msgvalues[41];                # card acceptor terminal id (8a) 41

  $transaction[42] = $msgvalues[42];                # card acceptor id code - terminal/merchant id (15a) 42

  my $curr = substr( "0000" . $msgvalues[49], -4, 4 );
  $transaction[49] = pack "H4", $curr;              # currency code (3n) 49

  my $zip = $msgvalues[59];
  $zip =~ s/ //g;
  if ( $curr ne "0840" ) {
    $zip = substr( $zip . " " x 9, 0, 9 );
  } else {
    $zip = substr( $zip . "0" x 9, 0, 9 );
  }
  $transaction[59] = pack "H2A9", "09", $zip;       # merchant zip/postal code (9a) 59

  if ( $msgvalues[60] ne "" ) {
    my $posinfo = substr( "00" . $msgvalues[60], -2, 2 );
    $transaction[60] = pack "H2", "$posinfo";       # additional pos information (2n) 60
  }

  my $addtldata = "";
  if ( $msgvalues[63] ne "" ) {

    # bit 63
    my $newidx  = 0;
    my $data    = $msgvalues[63];
    my $datalen = length($data);
    for ( my $newidx = 0 ; $newidx < $datalen ; ) {
      my $taglen = substr( $data, $newidx + 0, 2 );
      $taglen = unpack "H4", $taglen;
      my $tag     = substr( $data, $newidx + 2, 2 );
      my $tagdata = substr( $data, $newidx + 4, $taglen - 2 );
      $newidx = $newidx + 2 + $taglen;

      if ( $tag eq "14" ) {
        $addtldata = $addtldata . pack "H4A2A46", "0048", "14", "$tagdata";
      }
    }

    if ( $addtldata ne "" ) {
      my $datalen = length($addtldata);
      $datalen = substr( "0000" . $datalen, -4, 4 );
      $transaction[63] = pack "H4A$datalen", $datalen, $addtldata;    # additional data (private) (LLLVAR) 63
    }
  }

  my ( $bitmap1, $bitmap2 ) = &fdmsintl::generatebitmap(@transaction);

  $bitmap1 = pack "H16", $bitmap1;
  if ( $bitmap2 ne "" ) {
    $bitmap2 = pack "H16", $bitmap2;
  }

  my $message = "";

  my $mcode = pack "H4", "0400";

  $message = $message . $mcode . $bitmap1 . $bitmap2;

  foreach my $var (@transaction) {
    $message = $message . $var;
  }

  my $head = pack "H8", "02464402";
  my $tail = pack "H8", "03464403";
  my $length = length($message) + 0;

  my $tcpheader = pack "n", $length;
  $message = $head . $tcpheader . $message . $tail;

  return $message;

}

sub logmessage {
  my ($mymsg) = @_;

  my $cardnum = $msgvalues[2];
  if ( $cardnum eq "" ) {
    $cardnum = $msgvalues[35];
    $cardnum = substr( $cardnum, 0, 15 );
  }
  if ( $cardnum eq "" ) {
    $cardnum = $msgvalues[45];
    $cardnum = substr( $cardnum, 0, 15 );
  }

  $xs = "x" x length($cardnum);
  $xs2 = "x" x ( length($cardnum) + 11 );

  $messagestr = $mymsg;
  $messagestr =~ s/B$cardnum.{11}/B$xs2/g;
  $messagestr =~ s/$cardnum/$xs/g;

  if ( $cardnum ne "" ) {
    $cardnumbin = pack "H*", $cardnum;
    $myidx = index( $messagestr, $cardnumbin );
    if ( $myidx > 0 ) {
      $xs3        = "x" x length($cardnumbin);
      $len3       = length($cardnumbin);
      $messagestr = substr( $messagestr, 0, $myidx ) . $xs3 . substr( $messagestr, $myidx + $len3 );
    }
  }

  if ( $messagestr =~ /B$xs(.*)?\?/ ) {
    $mag = $1;
    $xs3 = "x" x length($mag);
    $messagestr =~ s/B$xs(.*)?\?/B$xs$xs3\?/g;
  }
  $messagestr =~ s/B[0-9]{15}/Bxxxxxxxxxxxxxxx/g;

  if ( $messagestr =~ /\x00\x07491 (...)/ ) {
    $cvv = $1;
    $xs  = "x" x length($cvv);
    $messagestr =~ s/\x00\x07491 $cvv/\x00\x07491 $xs/;
  } elsif ( $messagestr =~ /\[00\]\[07\]491(....)/ ) {
    $cvv = $1;
    $xs  = "x" x length($cvv);
    $messagestr =~ s/\x00\x07491$cvv/\x00\x07491$xs/;
  }

  $cardnumber = $cardnum;

  my $cc = new PlugNPay::CreditCard($cardnumber);
  $shacardnumber = $cc->getCardHash();

  $checkmessage = $messagestr;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime   = gmtime( time() );
  $tempstr    = unpack "H*", $mymsg;
  $logfilestr = "";
  $logfilestr .= "$username  $orderid\n";
  $logfilestr .= "$temptime send: $checkmessage  $shacardnumber\n\n";
  $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
}

sub checksocket {
  my $printstr = "in checksocket\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  my $socketcnt = 0;

  if ( $sockaddrport ne "" ) {
    $socketcnt = `netstat -n | grep $sockaddrport | grep ESTABLISHED | grep -c $sockaddrport`;
  }

  if ( $socketcnt < 1 ) {
    $line = `netstat -n | grep $sockaddrport`;
    my $printstr = "$line\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    my $sockettmp = `netstat -n | grep $sockaddrport | grep -v TIME_WAIT`;
    my ( $d1, $d2, $tmptime ) = &miscutils::genorderid();
    $logfilestr = "";
    $logfilestr .= "No ESTABLISHED $tmptime\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );

    $socketopenflag = 0;
    while ( $socketopenflag != 1 ) {
      &socketopenalarm();

    }
    $logfilestr = "";
    $logfilestr .= "socket reopened\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
  }

}

sub socketopenalarm {
  my $printstr = "in socketopenalarm\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  eval {
    local ( $SIG{ALRM} ) = sub { &switchports(); &socketopen( "$ipaddress", "$port" ) };

    alarm 20;

    &socketopen( "$ipaddress", "$port" );

    alarm 0;
  };
  if ($@) {
    &switchports();
    return "failure";
  }
  my $printstr = "socketopenflag: $socketopenflag\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

  if ( $socketopenflag == 0 ) {
    &switchports();

    my $printstr = "switchports $port\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    &socketopen( "$ipaddress", "$port" );

    my $printstr = "socketopenflagb: $socketopenflag\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
  }
}

sub switchports {
  my $printstr = "in socketopenalarm $ipaddress\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

  # xxxx
  if ( $test eq "yes" ) {

    $ipaddress = "167.16.0.125";    # test server
    $port      = "23219";           # test server
  } elsif ( $ipaddress ne $secondaryipaddress ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to secondary socket\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
    $ipaddress = $secondaryipaddress;
    $port      = $secondaryport;
  } elsif ( $ipaddress ne $primaryipaddress ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
    $ipaddress = $primaryipaddress;
    $port      = $primaryport;
  }
  my $printstr = "        new $ipaddress\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
}

sub socketopen {
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  shutdown SOCK, 2;
  close(SOCK);
  select undef, undef, undef, 1.00;

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen attempt $addr $port\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  $errorflag = 0;    # added 9/19/2017 because auto secondary did not work
  connect( SOCK, $paddr ) || ( $errorflag = 1 );
  if ( $errorflag == 1 ) {
    return;
  }

  $socketopenflag = 1;

  $sockaddr    = getsockname(SOCK);
  $sockaddrlen = length($sockaddr);
  if ( $sockaddrlen == 16 ) {
    ($sockaddrport) = unpack_sockaddr_in($sockaddr);
    $logfilestr = "";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "socketopen successful\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
    $getrespflag = 1;
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }
}

sub mydie {
  my ($errorstr) = @_;

  $logfilestr = "";
  $logfilestr .= "$errorstr\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );

  my $printstr = "$errorstr\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

  $socketerrorflag = 1;
}

sub socketwrite {
  my ($message) = @_;

  &checksocket();

  while ( $socketopenflag != 1 ) {
    &socketopenalarm();

  }

  send( SOCK, $message, 0, $paddr );
  &socketread(1);
}

sub socketread {
  my ($numtries) = @_;

  my $printstr = "in socketread\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );

  $temp11 = time();
  vec( $rin, fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $respdata = "";
  if ( $numtries == 0 ) {
    $mydelay = 3.0;
  } else {
    $mydelay = 30.0;
  }
  while ( $count && select( $rout = $rin, undef, undef, $mydelay ) ) {
    my $printstr = "in while\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    $mydelay    = 5.0;
    $logfilestr = "";
    $logfilestr .= "while\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
    recv( SOCK, $response, 2048, 0 );

    $respdata = $respdata . $response;

    $resplength = unpack "n", substr( $respdata, 4 );
    $resplength = $resplength + 10;
    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $transcnt--;

      $getrespflag = 1;

      $response = substr( $respdata, 0, $resplength );
      &updatefdmsintl();
      delete $writearray{$rsequencenum};
      if ( !%writearray ) {
        $donereadingflag = 1;
      }
      $respdata = substr( $respdata, $resplength );
      $resplength = unpack "n", substr( $respdata, 4 );
      $resplength = $resplength + 10;
      $rlen       = length($respdata);

      $temptime   = time();
      $outfilestr = "";
      $outfilestr .= "$temptime\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "accesstime.txt", "write", "", $outfilestr );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $delta      = time() - $temp11;
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt delta: $delta\n\n\n\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );

}

sub updatefdmsintl {

  &decodebitmap($response);

  $rsequencenum = $msgvalues[11];

  my $resptype = substr( $response, 6, 2 );
  $resptype = unpack "H*", $resptype;
  my $printstr = "resptype: $resptype\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

  if ( $resptype eq "0410" ) {
    my $printstr = "void response found\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    my $username = $susername{$rsequencenum};
    my $orderid  = $sorderid{$rsequencenum};
    my $reason   = $sreason{$rsequencenum};

    if ( ( $username ne "" ) && ( $orderid ne "" ) && ( $reason eq "timeout" ) ) {

      my $dbquerystr = <<"dbEOM";
              update trans_log
              set finalstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and operation='auth'
              and finalstatus='success'
dbEOM
      my @dbvalues = ( "$orderid", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      my $dbquerystr = <<"dbEOM";
              update operation_log
              set authstatus='problem',lastopstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and lastop='auth'
              and lastopstatus='success'
dbEOM
      my @dbvalues = ( "$orderid", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    }

  }

  $logfilestr = "";
  $logfilestr .= "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
  $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime   = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$temptime recv: $checkmessage\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );

  $sstatus{"$rsequencenum"} = "done";

  # yyyy
  $msg = pack "N", $sprocessid{"$rsequencenum"} + 0;

  $msg = $msg . $response;

  $processid = $sprocessid{"$rsequencenum"};
  &procutils::updateprocmsg( $processid, "fdmsintl", "success", "", "$response" );

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sreason{$rsequencenum};
  delete $sprocessid{$rsequencenum};
  delete $sinvoicenum{$rsequencenum};

}

sub socketclose {
  $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
  $logfilestr = "";
  $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
  ( $d1, $d2, $temp ) = &miscutils::genorderid();
  $logfilestr .= "before socket is closed because of no response $temp\n$sockaddrport\n$sockettmp\n\n";

  shutdown SOCK, 2;
  close(SOCK);
  $socketopenflag = 0;
  $getrespflag    = 1;

  open( MAIL, "| /usr/lib/sendmail -t" );
  print MAIL "To: cprice\@plugnpay.com\n";
  print MAIL "From: dprice\@plugnpay.com\n";
  print MAIL "Subject: fdmsintl - no response to authorization\n";
  print MAIL "\n";

  print MAIL "fdmsintl socket is being closed, then reopened because no response was\n\n";
  print MAIL "received to an authorization request.\n";

  close(MAIL);

  my $socketcnt = 0;
  if ( $sockaddrport ne "" ) {
    $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  }
  $tmpi = 0;
  while ( $socketcnt >= 1 ) {
    $tmpi++;
    if ( $tmpi > 4 ) {
      $logfilestr .= "exiting program because socket couldn't be closed\n\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
      exit;
    }
    shutdown SOCK, 2;
    close(SOCK);
    select( undef, undef, undef, 0.5 );
    $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  }

  shutdown SOCK, 2;
  close(SOCK);

  $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
  ( $d1, $d2, $temp ) = &miscutils::genorderid();
  $logfilestr .= "socket closed because of no response $temp\n$sockaddrport\n$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
}

sub decodebitmap {
  my ( $message, $findbit, $logflag ) = @_;
  my $chkmessage = $message;
  $chkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $chkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  my $printstr = "message: $chkmessage\n";
  &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

  @msgvalues    = ();
  @msgvalueslen = ();
  @msgvaluesidx = ();
  my @bitlenarray = ();

  $bitlenarray[2]   = "LLVAR";
  $bitlenarray[3]   = 6;
  $bitlenarray[4]   = 12;
  $bitlenarray[7]   = 10;
  $bitlenarray[11]  = 6;
  $bitlenarray[12]  = 6;
  $bitlenarray[13]  = 4;
  $bitlenarray[14]  = 4;
  $bitlenarray[18]  = 4;
  $bitlenarray[22]  = 4;
  $bitlenarray[24]  = 4;
  $bitlenarray[25]  = 2;
  $bitlenarray[31]  = "LLVARa";
  $bitlenarray[32]  = "LLVAR";
  $bitlenarray[35]  = "LLVAR";
  $bitlenarray[37]  = "12a";
  $bitlenarray[38]  = "6a";
  $bitlenarray[39]  = "2a";
  $bitlenarray[41]  = "8a";
  $bitlenarray[42]  = "15a";
  $bitlenarray[44]  = "LLLVARa";
  $bitlenarray[45]  = "LLVARa";
  $bitlenarray[48]  = "LLLVARa";
  $bitlenarray[49]  = 3;
  $bitlenarray[52]  = 16;
  $bitlenarray[53]  = "LLVARa";
  $bitlenarray[54]  = "LLLVARa";
  $bitlenarray[56]  = "LLVARa";
  $bitlenarray[59]  = "LLVARa";
  $bitlenarray[60]  = 1;
  $bitlenarray[61]  = "LLLVARa";
  $bitlenarray[62]  = "LLLVARa";
  $bitlenarray[63]  = "LLLVARa";
  $bitlenarray[64]  = "8a";
  $bitlenarray[70]  = 3;
  $bitlenarray[126] = "LLLVARa";

  my $idxstart = 8;                             # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 8 );
  my $bitmap   = unpack "H16", $bitmap1;

  if ( ( $findbit ne "" ) && ( $bitmap1 ne "" ) ) {
    $logfilestr = "";
    $logfilestr .= "\n\nbitmap1: $bitmap\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
  }
  $idx = $idx + 8;

  my $end     = 1;
  my $bitmap2 = "";
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;
    my $printstr = "bitmap2: $bitmap\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    if ( ( $findbit ne "" ) && ( $bitmap1 ne "" ) ) {
      $logfilestr = "";
      $logfilestr .= "bitmap2: $bitmap\n";
      &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
    }
    $end = 2;
    $idx = $idx + 8;
  }

  my $myk        = 0;
  my $myj        = 0;
  my $bitnum     = 0;
  my $bitnum2    = 0;
  my $bitmaphalf = $bitmap1;
  my $wordflag   = 3;
  for ( $myj = 1 ; $myj <= $end ; $myj++ ) {
    my $bitmaphalfa = substr( $bitmaphalf, 0, 4 );
    my $bitmapa = unpack "N", $bitmaphalfa;

    my $bitmaphalfb = substr( $bitmaphalf, 4, 4 );
    my $bitmapb = unpack "N", $bitmaphalfb;

    $bitmaphalf = $bitmapa;

    while ( $idx < length($message) ) {
      my $bit = 0;
      while ( ( $bit == 0 ) && ( $bitnum <= 64 ) ) {
        if ( ( $bitnum == 33 ) || ( $bitnum == 97 ) ) {
          $bitmaphalf = $bitmapb;
        }
        if ( ( $bitnum == 33 ) || ( $bitnum == 65 ) || ( $bitnum == 97 ) ) {
          $wordflag--;
        }

        $bit = ( $bitmaphalf >> ( 128 - ( $wordflag * 32 ) - $bitnum ) ) % 2;
        $bitnum++;
        $bitnum2++;
      }
      if ( $bitnum == 65 ) {
        last;
      }

      my $idxlen1 = $bitlenarray[ $bitnum2 - 1 ];
      my $idxlen  = $idxlen1;
      if ( $idxlen1 eq "LLVAR" ) {

        $idxlen = substr( $message, $idx, 1 );
        $idxlen = unpack "H2", $idxlen;
        $idxlen = int( ( $idxlen / 2 ) + .5 );
        $idx = $idx + 1;
      } elsif ( $idxlen1 eq "LLVARa" ) {
        $idxlen = substr( $message, $idx, 1 );
        $idxlen = unpack "H2", $idxlen;
        $idx = $idx + 1;

      } elsif ( $idxlen1 eq "LLLVAR" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idxlen = unpack "H4", $idxlen;
        $idxlen = int( ( $idxlen / 2 ) + .5 );
        $idx = $idx + 2;
      } elsif ( $idxlen1 eq "LLLVARa" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idxlen = unpack "H4", $idxlen;
        $idx = $idx + 2;
      } elsif ( $idxlen1 =~ /a/ ) {
        $idxlen =~ s/a//g;
      } else {
        $idxlen = int( ( $idxlen / 2 ) + .5 );
      }

      my $value = substr( $message, $idx, $idxlen );
      if ( $idxlen1 !~ /a/ ) {
        $value = unpack "H*", $value;
      }

      my $tmpbit = $bitnum2 - 1;

      $msgvalues[$tmpbit]    = $value;
      $msgvaluesidx[$tmpbit] = $idx;
      $msgvalueslen[$tmpbit] = $idxlen;

      $myk++;
      if ( $myk > 24 ) {
        my $printstr = "myk 24\n";
        &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
        exit;
      }
      if ( $findbit == $bitnum - 1 ) {

      }
      $idx = $idx + $idxlen;
      if ( $bitnum == 65 ) {
        last;
      }
    }
    $bitnum     = 0;
    $bitnum2    = $bitnum2 - 1;
    $bitmaphalf = $bitmap2;
  }    # end for

  if ( $logflag eq "yes" ) {
    $logfilestr = "";
    $logfilestr .= "\n\n";
    my $bitmap1str = unpack "H*", $bitmap1;
    my $bitmap2str = unpack "H*", $bitmap2;
    $logfilestr .= "bitmap1: $bitmap1str\n";
    $logfilestr .= "bitmap2: $bitmap2str\n";
    my $printstr = "bitmap1: $bitmap1str\n";
    $printstr .= "bitmap2: $bitmap2str\n";
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );

    for ( my $i = 0 ; $i <= $#msgvalues ; $i++ ) {
      if ( $msgvalues[$i] ne "" ) {
        my $chkmessage = $msgvalues[$i];
        $chkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
        $chkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

        if ( $msgvalues[$i] =~ /[^0-9a-zA-Z _\-\.]/ ) {
          if ( ( $i == 2 ) || ( $i == 35 ) || ( $i == 45 ) ) {
            $chkmessage =~ s/[0-9a-zA-Z]/x/g;
          } elsif ( $i == 63 ) {
            $chkmessage =~ s/491..../491xxxx/g;
          }
        } else {
          $chkmessage = $msgvalues[$i];
          if ( ( $i == 2 ) || ( $i == 35 ) || ( $i == 45 ) ) {
            $chkmessage =~ s/[0-9a-zA-Z]/x/g;
          } elsif ( $i == 63 ) {
            $chkmessage =~ s/491..../491xxxx/g;
          }
        }
        my $printstr = "$i  $chkmessage\n";
        &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/devlogs/fdmsintl", "miscdebug.txt", "append", "misc", $printstr );
        $logfilestr .= "$i  $chkmessage\n";
      }
    }
    &procutils::filewrite( "$username", "fdmsintl", "/home/pay1/batchfiles/$devprod/fdmsintl", "serverlogmsg.txt", "append", "", $logfilestr );
  }

  return @msgvalues;
}

