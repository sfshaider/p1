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

$devprod = "logs";

$keepalive    = 0;
$getrespflag  = 1;
$sequencenum  = 0;
$nullrecvflag = 0;

$host = "processor-host";    # Source IP address

#$ipaddress = "204.194.125.43";                  # test server
#$port = "7735";                                 # test server
$ipaddress = "204.194.125.9";    # production server
$port      = "7735";             # production server
&socketopen( "$ipaddress", "$port" );

# delete rows older than 2 minutes
my $now     = time();
my $deltime = &miscutils::timetostr( $now - 120 );

my $dbquerystr = <<"dbEOM";
        delete from processormsg
        where (trans_time<?
          or trans_time is NULL
          or trans_time='')
        and processor='buypass'
dbEOM
my @dbvalues = ("$deltime");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

&sendnullmsg();

while (1) {
  $temptime   = time();
  $outfilestr = "";
  $outfilestr .= "$temptime\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "accesstime.txt", "write", "", $outfilestr );

  if ( ( -e "/home/pay1/batchfiles/$devprod/buypass/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {

    sleep 1;
    exit;
  }

  &check();

  if ( $getrespflag == 0 ) {
    $logfilestr = "";
    $logfilestr .= "getrespflag = 0, closing socket\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

    $socketopenflag = 0;
    $getrespflag    = 1;
    &socketopen( "$ipaddress", "$port" );
    &sendnullmsg();
    while ( $nullrecvflag != 1 ) {

      $logfilestr = "";
      $logfilestr .= "nullrecvflag = 0, closing socket\n";
      &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

      $socketopenflag = 0;
      $getrespflag    = 1;
      &socketopen( "$ipaddress", "$port" );
      system('sleep 5');
      &sendnullmsg();
    }
  }

  system("sleep 1");

  $keepalive++;

  if ( $keepalive >= 300 ) {
    &sendnullmsg();
  }
  while ( ( $keepalive >= 300 ) && ( $nullrecvflag != 1 ) ) {

    $socketopenflag = 0;
    $getrespflag    = 1;
    &socketopen( "$ipaddress", "$port" );
    &sendnullmsg();
    if ( $nullrecvflag == 1 ) {
      $keepalive = 0;
    }
  }
}

sub check {

  $todayseconds = time();
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - ( 60 * 2 ) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  foreach $key ( keys %writearray ) {
    if ( $writearray{$key} < $ttime1 ) {
      delete $writearray{$key};
    }
  }

  $transcnt = 0;

  $timea = time();

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='buypass'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sthmsgvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $timeb = time();

  for ( my $vali = 0 ; $vali < scalar(@sthmsgvalarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage ) = @sthmsgvalarray[ $vali .. $vali + 4 ];

    if ( ( -e "/home/pay1/batchfiles/$devprod/buypass/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {

      sleep 1;
      exit;
    }

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and processor='buypass'
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $timec = time();

    $username =~ s/[^a-zA-Z0-9]//g;
    $orderid =~ s/[^a-zA-Z0-9]//g;

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &procutils::updateprocmsg( $processid, "buypass", "failure", "", "failure: message timeout" );

      next;
    }

    $transcnt++;

    $sequencenum = ( $sequencenum % 998 ) + 1;
    $sequencenum = substr( "000000" . $sequencenum, -6, 6 );

    $indx = substr( $message, 27, 2 );
    $seqindx = 27 + $indx + 2 + 28;

    $message = substr( $message, 0, $seqindx ) . $sequencenum . substr( $message, $seqindx + 6 );

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;

    $temptime   = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$temptime $username $orderid\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );
    $getrespflag = 0;
    &socketwrite( $message, "mssg" );

    $timed = time();

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "accesstime.txt", "write", "", $outfilestr );

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt >= 10 ) {
      last;
    }
  }

  if ( $transcnt > 0 ) {
    &socketread($transcnt);

    foreach $rsequencenum ( keys %susername ) {
      if ( $sstatus{"$rsequencenum"} ne "done" ) {
        $sretries{"$rsequencenum"}++;
        if ( $sretries{"$rsequencenum"} > 1 ) {
          &procutils::updateprocmsg( $processid, "buypass", "failure", "", "failure: $rsequencenum no response received" );

          delete $susername{$rsequencenum};
          delete $strans_time{$rsequencenum};
          delete $smessage{$rsequencenum};
          delete $sretries{$rsequencenum};
          delete $sorderid{$rsequencenum};
          delete $sprocessid{$rsequencenum};
        }
      }
    }
  }

  $timee  = time();
  $deltab = $timeb - $timea;
  $deltac = $timec - $timea;
  $deltad = $timed - $timea;
  $deltae = $timee - $timea;
  if ( $deltae > 30 ) {
    $mytime     = gmtime( time() );
    $logfilestr = "$mytime delta high $deltab $deltac $deltad $deltae\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );
  }

}

sub socketopen {
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen attempt\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  connect( SOCK, $paddr ) || die "connect: $!";

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen successful\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );
  $socketopenflag = 1;
}

sub socketwrite {
  my ( $message, $nullflag ) = @_;

  if ( $socketopenflag != 1 ) {
    &socketopen( "$ipaddress", "$port" );
  }
  if ( $socketopenflag != 1 ) {
    $logfilestr = "";
    $logfilestr .= "socketopenflag = 0, exiting\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );
    exit;
  }

  if ( $nullflag eq "mssg" ) {
    &decodebitmap("$message");
    $messagestr = $message;
    $cardnum    = "";
    $xs         = "";
    if ( $msgvalues[2] ne "" ) {
      $cardnum    = $msgvalues[2];
      $cardnumidx = $msgvaluesidx[2];
      $cardnum =~ s/[^0-9]//g;
      $cardnumlen = length($cardnum);
      $xs         = "x" x $cardnumlen;
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $message, 0, $cardnumidx ) . $xs . substr( $message, $cardnumidx + $cardnumlen );
      }
    } elsif ( $msgvalues[45] ne "" ) {    # track 1
      $cardnum    = $msgvalues[45];
      $cardnumidx = $msgvaluesidx[45];
      $cardnumlen = length($cardnum);
      $xs         = "x" x $cardnumlen;
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $message, 0, $cardnumidx ) . $xs . substr( $message, $cardnumidx + $cardnumlen );
      }
      $cardnum =~ s/^.//;
      ($cardnum) = split( /\^/, $cardnum );
    } elsif ( $msgvalues[35] ne "" ) {    # track 2
      $cardnum    = $msgvalues[35];
      $cardnumidx = $msgvaluesidx[35];
      $cardnumlen = length($cardnum);
      $xs         = "x" x $cardnumlen;
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $message, 0, $cardnumidx ) . $xs . substr( $message, $cardnumidx + $cardnumlen );
      }
      ($cardnum) = split( /=/, $cardnum );
    }

    if ( $msgvalues[127] ne "" ) {        # cvv data
      $datalen = length( $msgvalues[127] );
      $dataidx = $msgvaluesidx[127];
      my $temp   = $msgvalues[127];
      my $newidx = 0;
      for ( my $newidx = 0 ; $newidx < $datalen ; ) {
        my $tag     = substr( $temp, $newidx + 0, 2 );
        my $taglen  = substr( $temp, $newidx + 2, 3 );
        my $tagdata = substr( $temp, $newidx + 5, $taglen );
        if ( $tag eq "10" ) {
          $cvv = $tagdata;
          if ( $cvv =~ /[0-9]{3} / ) {
            $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 5 ) . 'xxx ' . substr( $messagestr, $dataidx + $newidx + 5 + 4 );
          } elsif ( $cvv =~ /[0-9]{4}/ ) {
            $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 5 ) . 'xxxx' . substr( $messagestr, $dataidx + $newidx + 5 + 4 );
          }
        }
        $newidx = $newidx + 5 + $taglen;
      }
    }

    $cardnum =~ s/[^0-9]//g;
    $shacardnumber = "";
    if ( ( length($cardnum) >= 13 ) && ( length($cardnum) < 20 ) ) {
      $cardnumber = $cardnum;

      my $cc = new PlugNPay::CreditCard($cardnumber);
      $shacardnumber = $cc->getCardHash();
    }

    $temptime = gmtime( time() );
    $message2 = $messagestr;
    $message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $logfilestr = "";
    $logfilestr .= "\n$susername{$sequencenum} $sorderid{$sequencenum}\n";
    $logfilestr .= "$ipaddress $port";
    $logfilestr .= "$temptime send: $message2  $shacardnumber\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

  } else {
    $temptime = gmtime( time() );
    $message2 = $message;
    $message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $logfilestr = "null message $ipaddress $port\n";
    $logfilestr .= "$temptime send: $message2\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );
  }

  send( SOCK, $message, 0, $paddr );

}

sub socketread {
  ($numtries) = @_;

  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $response = "";
  $respdata = "";
  while ( $count && select( $rout = $rin, undef, undef, 25.0 ) ) {

    recv( SOCK, $response, 2048, 0 );

    $respdata = $respdata . $response;

    ($resplength) = unpack "n", $respdata;
    $resplength = $resplength + 2;

    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $keepalive = 0;
      $nullresp = substr( $respdata, 7, 4 );

      if ( $nullresp ne '0810' ) {
        $transcnt--;
        if ( $transcnt == 0 ) {
          $getrespflag = 1;
        }
        $response = substr( $respdata, 0, $resplength );

        $logfilestr = "";
        $logfilestr .= "transcnt: $transcnt\n";
        &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

        &update();
        delete $writearray{$rsequencenum};
        if ( !%writearray ) {
          $donereadingflag = 1;
        } else {
          $logfilestr = "";
          $logfilestr .= "cccc ";
          $logfilestr .= %writearray;
          $logfilestr .= "\n\n";
          &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );
        }
      } else {
        $nullrecvflag = 1;
        $mytime       = gmtime( time() );
        $logfilestr   = "";
        $logfilestr .= "$mytime null message found\n\n";
        &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

      }
      $respdata = substr( $respdata, $resplength );

      $resplength = unpack "n", $respdata;
      $resplength = $resplength + 6;
      $rlen       = length($respdata);

      $temptime   = time();
      $outfilestr = "";
      $outfilestr .= "$temptime\n";
      &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "accesstime.txt", "write", "", $outfilestr );

    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt\n\n\n\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

}

sub update {
  &decodebitmap("$response");
  $messagestr = $response;
  $cardnum    = "";
  $xs         = "";
  if ( $msgvalues[2] ne "" ) {
    $cardnum    = $msgvalues[2];
    $cardnumidx = $msgvaluesidx[2];
    $cardnum =~ s/[^0-9]//g;
    $cardnumlen = length($cardnum);
    $xs         = "x" x $cardnumlen;
    if ( $cardnumidx > 0 ) {
      $messagestr = substr( $response, 0, $cardnumidx ) . $xs . substr( $response, $cardnumidx + $cardnumlen );
    }
  }

  $temptime = gmtime( time() );
  $message2 = $messagestr;
  $message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $logfilestr = "";
  $logfilestr .= "$temptime recv: $message2\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

  $bitmap = substr( $response, 11, 8 );
  $bitmap = unpack "H16", $bitmap;
  $bitmap2 = substr( $response, 19, 8 );
  $bitmap2 = unpack "H16", $bitmap2;

  if ( $bitmap =~ /^f/ ) {
    $cardlen = substr( $response, 27, 2 );
    $idx = 27 + 2 + $cardlen;
  } else {
    $idx = 27;
  }

  $idx          = $idx + 2 + 26;
  $rsequencenum = substr( $response, $idx, 6 );
  $checkmessage = $response;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/\x1e/\[1e\]/g;

  $sstatus{"$rsequencenum"} = "done";

  $processid = $sprocessid{"$rsequencenum"};
  &procutils::updateprocmsg( $processid, "buypass", "success", "$sinvoicenum{$rsequencenum}", "$response" );

  my $mytime = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime snd success $checktime\n";
  &procutils::filewrite( "$username", "buypass", "/home/pay1/batchfiles/$devprod/buypass", "serverlogmsg.txt", "append", "", $logfilestr );

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sprocessid{$rsequencenum};

  ( $d1, $d2, $temptime ) = &miscutils::genorderid();
  $checkmessage = $response;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/\x1e/\[1e\]/g;

}

sub sendnullmsg {
  $nullrecvflag = 0;

  ( $d1, $d2, $tdate ) = &miscutils::genorderid();
  $tdate = substr( $tdate, 4, 10 );
  $message = pack "A4H16H16A10A6A8A3", '0800', '8220000000800000', '0400000000000000', "$tdate", '000000', '00870701', '301';
  $len     = length($message) + 5;
  $len     = substr( "0000" . $len, -4, 4 );
  $header  = pack "nH2H8", $len, "60", "00000000";
  $message = $header . $message;

  $sequencenum = ( $sequencenum % 998 ) + 1;
  $sequencenum = substr( "000000" . $sequencenum, -6, 6 );

  $message = substr( $message, 0, 37 ) . $sequencenum . substr( $message, 43 );

  &socketwrite( $message, "null" );
  &socketread(1);
}

sub decodebitmap {
  my ( $message, $findbit ) = @_;

  $bitlenarray[2]   = "LLVAR";
  $bitlenarray[3]   = 6;
  $bitlenarray[4]   = 12;
  $bitlenarray[6]   = 12;
  $bitlenarray[7]   = 10;
  $bitlenarray[10]  = 8;
  $bitlenarray[11]  = 6;
  $bitlenarray[12]  = 6;
  $bitlenarray[13]  = 4;
  $bitlenarray[14]  = 4;
  $bitlenarray[15]  = 4;
  $bitlenarray[18]  = 4;
  $bitlenarray[19]  = 3;
  $bitlenarray[21]  = 3;
  $bitlenarray[22]  = 3;
  $bitlenarray[25]  = 2;
  $bitlenarray[31]  = "LLVARa";
  $bitlenarray[32]  = "LLVAR";
  $bitlenarray[35]  = "LLVAR";
  $bitlenarray[37]  = "12a";
  $bitlenarray[38]  = 6;
  $bitlenarray[39]  = "2a";
  $bitlenarray[41]  = 8;
  $bitlenarray[42]  = 15;
  $bitlenarray[43]  = 40;
  $bitlenarray[44]  = "LLVARa";
  $bitlenarray[45]  = "LLVARa";
  $bitlenarray[48]  = "LLLVARa";
  $bitlenarray[49]  = 3;
  $bitlenarray[51]  = 3;
  $bitlenarray[53]  = "LLVARa";
  $bitlenarray[54]  = "LLLVARa";
  $bitlenarray[57]  = "3a";
  $bitlenarray[58]  = "LLLVARa";
  $bitlenarray[59]  = "LLLVARa";
  $bitlenarray[60]  = "LLLVARa";
  $bitlenarray[61]  = "LLLVARa";
  $bitlenarray[62]  = "LLLVARa";
  $bitlenarray[63]  = "LLLVARa";
  $bitlenarray[70]  = 3;
  $bitlenarray[90]  = 42;
  $bitlenarray[95]  = "42a";
  $bitlenarray[120] = "LLLVARa";
  $bitlenarray[123] = "LLLVARa";
  $bitlenarray[126] = "LLLVARa";
  $bitlenarray[127] = "LLLVARa";

  my $idxstart = 11;                            # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 8 );
  my $bitmap   = unpack "H16", $bitmap1;
  $idx = $idx + 8;

  my $end = 1;
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;

    my $removebit = pack "H*", "7fffffffffffffff";
    $bitmap1 = $bitmap1 & $removebit;

    $end = 2;
    $idx = $idx + 8;
  }

  @msgvalues    = ();
  @msgvaluesidx = ();
  my $myk           = 0;
  my $myi           = 0;
  my $bitnum        = 0;
  my $bigbitmaphalf = $bitmap1;
  my $wordflag      = 3;
  for ( $myj = 1 ; $myj <= $end ; $myj++ ) {
    my $bitmaphalfa = substr( $bigbitmaphalf, 0, 4 );
    my $bitmapa = unpack "N", $bitmaphalfa;

    my $bitmaphalfb = substr( $bigbitmaphalf, 4, 4 );
    my $bitmapb = unpack "N", $bitmaphalfb;

    my $bitmaphalf = $bitmapa;

    while ( $idx < length($message) ) {
      my $bit = 0;
      while ( ( $bit == 0 ) && ( $bitnum < 129 ) ) {
        if ( ( $bitnum == 33 ) || ( $bitnum == 97 ) ) {
          $bitmaphalf = $bitmapb;
        }
        if ( ( $bitnum == 33 ) || ( $bitnum == 65 ) || ( $bitnum == 97 ) ) {
          $wordflag--;
        }

        $bit = ( $bitmaphalf >> ( 128 - ( $wordflag * 32 ) - $bitnum ) ) % 2;
        $bitnum++;

        if ( $bitnum == 64 ) {
          last;
        }
      }
      if ( ( ( $bitnum == 64 ) || ( $bitnum == 128 ) ) && ( $bit == 0 ) ) {
        last;
      }

      my $tempstr = substr( $message, $idx, 8 );
      $tempstr = unpack "H*", $tempstr;

      my $idxold = $idx;

      my $idxlen1 = $bitlenarray[ $bitnum - 1 ];
      my $idxlen  = $idxlen1;
      if ( $idxlen1 eq "LLVAR" ) {
        $idxlen = substr( $message, $idx, 2 );

        $idx = $idx + 2;
      } elsif ( $idxlen1 eq "LLVARa" ) {
        $idxlen = substr( $message, $idx, 2 );

        $idx = $idx + 2;
      } elsif ( $idxlen1 eq "LLLVAR" ) {
        $idxlen = substr( $message, $idx, 3 );

        $idx = $idx + 3;
      } elsif ( $idxlen1 eq "LLLVARa" ) {
        $idxlen = substr( $message, $idx, 3 );

        $idx = $idx + 3;
      } elsif ( $idxlen1 =~ /a/ ) {
        $idxlen =~ s/a//g;
      }
      my $value = substr( $message, $idx, $idxlen );

      $tmpbit = $bitnum - 1;

      $msgvalues[$tmpbit]    = "$value";
      $msgvaluesidx[$tmpbit] = "$idx";

      $myk++;
      if ( $myk > 26 ) {
        return -1, "";
      }
      if ( ( $findbit ne "" ) && ( $findbit == $bitnum - 1 ) ) {
        return $idx, $value;
      }
      $idx = $idx + $idxlen;
      if ( ( $bitnum == 64 ) || ( $bitnum >= 128 ) ) {
        last;
      }
    }
    $bigbitmaphalf = $bitmap2;
  }    # end for

  return -1, "";
}

