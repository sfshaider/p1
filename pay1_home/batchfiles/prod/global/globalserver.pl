#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use IO::Socket;
use Socket;

#require 'sys/ipc.ph';
#require 'sys/msg.ph';
#use SHA;
use rsautils;

#use Convert::EBCDIC (ascii2ebcdic, ebcdic2ascii);
use PlugNPay::CreditCard;

$test    = "no";
$devprod = "logs";

$keepalive    = 0;
$getrespflag  = 1;
$tsequencenum = 0;
$numtrans     = 0;    # used only for throughput checks

$nullmessage = pack "H6A3nA8H2", "010103", "   ", "0008", "POLL RSP", "03";

$host = "processor-host";    # Source IP address

$primaryipaddress = '64.69.201.195';    # primary server sandy springs
$primaryport      = '14133';            # primary server
$primaryhost      = "$host";            # Source IP address

$ipaddress1 = '64.27.243.6';            # secondary server atlanta
$port1      = '14133';                  # secondary server
$host1      = "$host";                  # Source IP address

## 20140908  Port 18582 disconnected as per global.  IP change to 64.27.243.6  for backup
#$ipaddress1 = '64.69.203.195';			# secondary server
#$port1 = '18582';				# secondary server
#$host1 = "$host";				# Source IP address

## 20140908 Only 1 backup now.
#$ipaddress2 = '64.69.203.195';			# secondary server
#$port2 = '14133';				# secondary server
#$host2 = "$host";			# Source IP address

$testipaddress = '64.69.205.190';    # test server
$testport      = '18582';            # test server
$testhost      = "$host";            # Source IP address

$ipaddress = $primaryipaddress;
$port      = $primaryport;

&checksecondary();

&socketopen( $ipaddress, $port );

# delete rows older than 2 minutes
my $now      = time();
my $deltime  = &miscutils::timetostr( $now - 600 );
my $printstr = "deltime: $deltime\n";
&procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

my $dbquerystr = <<"dbEOM";
        delete from processormsg
        where trans_time<?
          or trans_time is NULL
          or trans_time=''
dbEOM
my @dbvalues = ("$deltime");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

while (1) {
  $temptime   = time();
  $outfilestr = "";
  $outfilestr .= "$temptime\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "accesstime.txt", "write", "", $outfilestr );

  if ( ( -e "/home/pay1/batchfiles/$devprod/global/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {

    sleep 1;
    exit;
  }

  &checksecondary();

  &check();

  if ( $getrespflag == 0 ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime getrespflag = 0, closing socket\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );

    $socketopenflag = 0;
    $getrespflag    = 1;
    system('sleep 2');
    &socketopen( $ipaddress, $port );
  }

  system("sleep 1");

  #system("usleep 200000");
  $keepalive++;

  if ( $keepalive >= 60 ) {

    $socketopenflag = 0;

    #$message = pack "H12", "000000000000";

    #&socketwrite($message);
    $keepalive = 0;

  }
}

sub check {
  $todayseconds = time();
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - ( 60 * 2 ) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  foreach $key ( keys %writearray ) {
    if ( $writearray{$key} < $ttime1 ) {
      delete $writearray{$key};
    } else {

      #open(tempfile,">>/home/pay1/batchfiles/$devprod/global/temp.txt");
      #print tempfile "$ttime1 $writearray{$key}\n";
      #close(tempfile);
    }
  }

  #&timecheck("before selecting");
  $timecheckend3   = time();
  $timecheckdelta3 = $timecheckend3 - $timecheckstart3;
  $timecheckstart3 = $timecheckend3;
  if ( $numtrans == 4 ) {

    #open(tempfile,">>/home/pay1/batchfiles/$devprod/global/time.txt");
    #print tempfile "$numtrans	writing: $timecheckdelta1	reading: $timecheckdelta2	round trip: $timecheckdelta3\n";
    $numtranscnt++;
    $totaltime = $totaltime + $timecheckdelta3;
    if ( $numtranscnt >= 10 ) {
      $tempstr = sprintf( "Average Round Trip: %.1f", $totaltime / 10 );

      #print tempfile "$tempstr\n";
      $numtranscnt = 0;
      $totaltime   = 0;
    }

    #close(tempfile);
  }

  $transcnt            = 0;
  $timecheckfirstflag  = 1;
  $timecheckfirstflag2 = 1;

  #$logfilestr = "";
  #$logfilestr .= "aaaa select from processormsg\n";
  #&procutils::filewrite("$username","global","/home/pay1/batchfiles/$devprod/global","serverlogmsg.txt","append","",$logfilestr);

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='global'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sthmsgvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthmsgvalarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage ) = @sthmsgvalarray[ $vali .. $vali + 4 ];

    if ( ( -e "/home/pay1/batchfiles/$devprod/global/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {

      sleep 1;
      exit;
    }

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and processor='global'
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    #while (1) {}

    $username =~ s/[^0-9a-zA-Z_]//g;
    $orderid =~ s/[^0-9]//g;

    #print "type: $type\n";
    my $printstr = "\n\nprocessid: $processid\n";
    $printstr .= "username: $username\n";
    $printstr .= "orderid: $orderid\n";
    $printstr .= "trans_time: $trans_time\n";
    $printstr .= "message: $message\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &procutils::updateprocmsg( $processid, "global", "failure", "", "failure: message timeout" );

      next;
    }

    #&timecheck("get next valid orderid");

    $transcnt++;

    $tsequencenum = ( $tsequencenum % 998 ) + 1;
    $tsequencenum = substr( "000000" . $tsequencenum, -6, 6 );

    @msgvalues   = &decodebitmap("$message");
    $seqindx     = $msgvaluesidx[11];
    $sequencenum = $msgvalues[11];
    if ( $sequencenum eq "000000" ) {
      $sequencenum = $tsequencenum;
    }

    #$sequencenum = ($sequencenum % 998) + 1;
    #$sequencenum = substr("000000" . $sequencenum,-6,6);
    my $printstr = "sequencenum: $sequencenum\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

    $hseqnum = pack "H6", $sequencenum;
    $message = substr( $message, 0, $seqindx ) . $hseqnum . substr( $message, $seqindx + 3 );

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;

    if ( $timecheckfirstflag == 1 ) {
      $timecheckstart1    = time();
      $timecheckfirstflag = 0;
    }

    #open(logfile,">>/home/pay1/batchfiles/$devprod/global/serverlogmsg.txt");
    #print logfile "sequencenum: $sequencenum retries: $retries\n";
    #close(logfile);

    $timecheckend1   = time();
    $timecheckdelta1 = $timecheckend1 - $timecheckstart1;

    # xxxx
    ( $d1, $d2, $temptime ) = &miscutils::genorderid();
    $checkmessage = $message;
    $checkmessage =~ s/\x1c/\[1c\]/g;
    $checkmessage =~ s/\x1e/\[1e\]/g;

    #open(tempfile,">>/home/pay1/batchfiles/$devprod/global/serverlog.txt");
    #print tempfile "$temptime $checkmessage\n";
    #close(tempfile);

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "accesstime.txt", "write", "", $outfilestr );

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt >= 10 ) {
      last;
    }
  }

  if ( $transcnt > 0 ) {
    $numtrans = $transcnt;
    &socketread($transcnt);
  }

  foreach $rsequencenum ( keys %susername ) {
    if ( $sstatus{"$rsequencenum"} ne "done" ) {

      my $now    = time();
      my $mytime = &miscutils::strtotime( $strans_time{$rsequencenum} );
      my $delta  = $now - $mytime;
      $sretries{"$rsequencenum"}++;
      if ( $delta > 60 ) {

        #if ($smessage{$rsequencenum} =~ /^.{9}12/) {    # void HCS 12xx messages only
        #  $message = &sendvoid($smessage{$rsequencenum});
        #  &decodebitmap($message);

        #$checkmessage = $message;
        #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
        #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
        #$temptime = gmtime(time());
        #open(logfile,">>/home/pay1/batchfiles/$devprod/global/serverlogmsg.txt");
        #print logfile "\n$username $orderid\n";
        #print logfile "$temptime send: $checkmessage\n";
        #print "$temptime send: $checkmessage\n";
        #close(logfile);

        #  $transcnt++;
        #  &socketwrite($message);
        #  &socketread(4);
        #  $keepalive = 0;
        #}
        #else {
        delete $susername{$rsequencenum};
        delete $strans_time{$rsequencenum};
        delete $smessage{$rsequencenum};
        delete $sretries{$rsequencenum};
        delete $sorderid{$rsequencenum};
        delete $sprocessid{$rsequencenum};
        delete $svoidmessage{$rsequencenum};

        #}
      }
    }
  }

}

sub socketopen {
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  my $mytime = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen attempt $addr $port\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) or die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) or die "socket: $!";

  #$iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(SOCK, $sockaddr)    or die "bind: $!\n";
  connect( SOCK, $paddr ) or die "connect: $!";

  $socketopenflag = 1;

  $logfilestr = "";
  $logfilestr .= "socketopen successful\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
}

sub socketwrite {
  my ($message) = @_;

  if ( $socketopenflag != 1 ) {
    &socketopen( $ipaddress, $port );
  }
  if ( $socketopenflag != 1 ) {
    $logfilestr = "";
    $logfilestr .= "socketopenflag = 0, exiting\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
    exit;
  }

  $messagestr = $message;
  @msgvalues  = &decodebitmap( "$message", "", "yes" );
  $cardnum    = "";
  $xs         = "";

  $messagestr =~ s/[0-9]{3,4}\x03/xxx\x03/;

  if ( $msgvalues[126] ne "" ) {    # cvv  doesn't work
    $cvvdata    = $msgvalues[126];
    $cvvdataidx = $msgvaluesidx[126];
    $datalen    = length($cvvdata);
    if ( $datalen == 14 ) {
      $cvvidx = $cvvdataidx + 10;
      $cvv = substr( $cvvdata, 10, 4 );
    } elsif ( $datalen == 54 ) {
      $cvvidx = $cvvdataidx + 50;
      $cvv = substr( $cvvdata, 50, 4 );
    }
    if ( $cvvdataidx > 0 ) {
      if ( $cvv =~ / [0-9]{3}/ ) {
        $messagestr = substr( $messagestr, 0, $cvvidx ) . ' xxx' . substr( $messagestr, $cvvidx + 4 );
      } elsif ( $cvv =~ /[0-9]{4}/ ) {
        $messagestr = substr( $messagestr, 0, $cvvidx ) . 'xxxx' . substr( $messagestr, $cvvidx + 4 );
      }
    }
  }

  if ( $msgvalues[2] ne "" ) {
    $cardnum    = $msgvalues[2];
    $cardnumidx = $msgvaluesidx[2];
    $cardnum =~ s/[^0-9]//g;
    $len        = length($cardnum);
    $len        = substr( "00" . $len, -2, 2 );
    $newcardnum = pack "H$len", $cardnum;
    $xs         = "x" x length($newcardnum);
    if ( $cardnumidx > 0 ) {
      $messagestr = substr( $messagestr, 0, $cardnumidx ) . $xs . substr( $messagestr, $cardnumidx + ( $len / 2 ) );
    }
  } elsif ( $msgvalues[45] ne "" ) {    # track 1
    $cardnum    = $msgvalues[45];
    $xlen       = length($cardnum) - 2;
    $cardnumidx = $msgvaluesidx[45];
    $cardnum =~ s/^.//;
    ($cardnum) = split( /\^/, $cardnum );
    $cardnum =~ s/[^0-9]//g;
    $len = length($cardnum) + 16;
    if ( ( $xlen > 20 ) && ( $xlen < 79 ) ) {
      $len = $xlen;
    }
    $xs = "x" x $len;

    #$messagestr =~ s/$cardnum/$xs/g;
    if ( $cardnumidx > 0 ) {
      $messagestr = substr( $messagestr, 0, $cardnumidx + 1 ) . $xs . substr( $messagestr, $cardnumidx + $len + 1 );
    }
  } elsif ( $msgvalues[35] ne "" ) {    # track 2
    $cardnum    = $msgvalues[35];
    $xlen       = ( length($cardnum) / 2 );
    $cardnumidx = $msgvaluesidx[35];
    ($cardnum) = split( /\xd/, $cardnum );
    $cardnum =~ s/[^0-9]//g;
    if ( ( $xlen > 10 ) && ( $xlen < 20 ) ) {
      $len = $xlen;
    } else {
      $len = ( length($cardnum) / 2 ) + 4;
    }
    $xs = "x" x $len;
    if ( $cardnumidx > 0 ) {
      $messagestr = substr( $messagestr, 0, $cardnumidx ) . $xs . substr( $messagestr, $cardnumidx + $len );
    }
  }

  #($dummy,$bitmap1) = unpack "A12H16", $message;
  #if ($bitmap1 =~ /^(8|9|a|b|c|d|e|f)/) {
  #  ($dummy,$bitmap1,$bitmap2,$clen) = unpack "A12H16H16H2", $message;
  #  ($dummy,$bitmap1,$bitmap2,$clen,$cardnumber) = unpack "A12H16H16H2H$clen", $message;
  #}
  #else {
  #  ($dummy,$bitmap1,$clen) = unpack "A12H16H2", $message;
  #  ($dummy,$bitmap1,$clen,$cardnumber) = unpack "A12H16H2H$clen", $message;
  #}

  #$cardnum = substr($message,57,19);
  $cardnum =~ s/[^0-9]//g;
  $shacardnumber = "";
  if ( ( length($cardnum) >= 13 ) && ( length($cardnum) < 20 ) ) {
    $cardnumber = $cardnum;

    #$sha1->reset;
    #$sha1->add($cardnumber);
    #$shacardnumber = $sha1->hexdigest();
    my $cc = new PlugNPay::CreditCard($cardnumber);
    $shacardnumber = $cc->getCardHash();
  }

  $mytime   = gmtime( time() );
  $message2 = $messagestr;
  $message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $logfilestr = "";
  $logfilestr .= "$username $orderid\n";
  if ( $secondary ne "" ) {
    $logfilestr .= "secondary $secondary\n";
  }
  $logfilestr .= "$mytime send: $message2  $shacardnumber\n";

  #$message2 = unpack "H*", $messagestr;
  #print logfile "send2: $message2\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );

  send( SOCK, $message, 0, $paddr );

}

sub socketread {
  ($numtries) = @_;

  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );

  #foreach $key (keys %sprocessid) {
  #print "       $key\n";
  #  $response = "0" x 32 . $key . "0" x 12;
  #  &update();
  #  $getrespflag = 1;
  #}
  #return;

  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count     = $numtries + 2;
  $mlen      = length($message);
  $response  = "";
  $respdata  = "";
  $delaytime = 25.0;
  while ( $count && select( $rout = $rin, undef, undef, $delaytime ) ) {
    $delaytime  = 5.0;
    $logfilestr = "";
    ( $d1, $d2, $temptime ) = &miscutils::genorderid();
    $logfilestr .= "while $temptime\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
    recv( SOCK, $response, 2048, 0 );

    $respdata = $respdata . $response;

    ( $d1, $d2, $resplength ) = unpack "H4A4A4", $respdata;
    $resplength = $resplength + 11;

    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );

    my $printstr = "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      ($nullresp) = unpack "H12", $respdata;
      if ( $resplength > 17 ) {
        $transcnt--;

        # xxxx see if this works
        #if ($transcnt == 0) {}
        #if ($transcnt <= 1) {
        $getrespflag = 1;

        #}
        $response = substr( $respdata, 0, $resplength );
        &update();
        delete $writearray{$rsequencenum};
        if ( !%writearray ) {
          $donereadingflag = 1;
        }
      } else {
        $logfilestr = "";
        $logfilestr .= "null message found\n\n";
        &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
      }
      $respdata = substr( $respdata, $resplength );

      ( $d1, $d2, $resplength ) = unpack "H4A4A4", $respdata;
      $resplength = $resplength + 11;
      $rlen       = length($respdata);

      $logfilestr = "";
      $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
      my $printstr = "rlen: $rlen, resplength: $resplength\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global",  "miscdebug.txt",    "append", "misc", $printstr );
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "",     $logfilestr );

      #$mytime = gmtime(time());
      #$message2 = $respdata;
      #$message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
      #$message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
      #open(logfile,">>/home/pay1/batchfiles/$devprod/global/serverlogmsg.txt");
      #print logfile "$mytime recvaaaa: $message2\n";
      #$message2 = unpack "H*", $respdata;
      #print logfile "response2aaaa: $message2\n";
      #close(logfile);

      $temptime   = time();
      $outfilestr = "";
      $outfilestr .= "$temptime\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "accesstime.txt", "write", "", $outfilestr );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime end loop $transcnt\n\n\n\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );

}

sub update {
  my $printstr = "in update\n\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  &decodebitmap( $response, "", "yes" );
  $rsequencenum = $msgvalues[11];

  $mytime   = gmtime( time() );
  $message2 = $response;
  $message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $logfilestr = "";
  $logfilestr .= "$mytime recv: $message2\n";
  $message2 = unpack "H*", $response;

  #print logfile "response2: $message2\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
  my $printstr = "$mytime recv: $message2\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "miscdebug.txt", "append", "misc", $printstr );

  #open(logfile,">>/home/pay1/batchfiles/$devprod/global/serverlogmsg.txt");
  #print logfile "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  #close(logfile);
  $checkmessage = $response;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/\x1e/\[1e\]/g;

  #open(logfile,">>/home/pay1/batchfiles/$devprod/global/serverlogmsg.txt");
  #print logfile "response: $checkmessage\n";
  #close(logfile);

  #&timecheck("before update");
  if ( $timecheckfirstflag2 == 1 ) {
    $timecheckstart2     = time();
    $timecheckfirstflag2 = 0;
  }

  $sstatus{"$rsequencenum"} = "done";

  $processid = $sprocessid{"$rsequencenum"};
  &procutils::updateprocmsg( $processid, "global", "success", "$sinvoicenum{$rsequencenum}", "$response" );

  my $mytime = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime snd success $checktime\n";
  &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );

  # yyyy

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sprocessid{$rsequencenum};
  delete $svoidmessage{$rsequencenum};

  $timecheckend2   = time();
  $timecheckdelta2 = $timecheckend2 - $timecheckstart2;

  ( $d1, $d2, $temptime ) = &miscutils::genorderid();
  $checkmessage = $response;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/\x1e/\[1e\]/g;

  #open(tempfile,">>/home/pay1/batchfiles/$devprod/global/serverlog.txt");
  #print tempfile "$temptime $checkmessage\n";
  #close(tempfile);
}

sub decodebitmap {
  my ( $message, $findbit, $logflag ) = @_;

  @msgvalues    = ();
  @msgvalueslen = ();
  @msgvaluesidx = ();
  my @bitlenarray = ();

  $bitlenarray[2]   = "LLVAR";
  $bitlenarray[3]   = 6;
  $bitlenarray[4]   = 12;
  $bitlenarray[7]   = 14;
  $bitlenarray[11]  = 6;
  $bitlenarray[12]  = 12;
  $bitlenarray[13]  = 8;
  $bitlenarray[14]  = 4;
  $bitlenarray[18]  = 4;
  $bitlenarray[22]  = "12a";
  $bitlenarray[25]  = 2;
  $bitlenarray[31]  = "LLVARa";
  $bitlenarray[32]  = "LLVAR";
  $bitlenarray[35]  = "LLVAR";
  $bitlenarray[37]  = "12a";
  $bitlenarray[38]  = "6a";
  $bitlenarray[39]  = "3a";
  $bitlenarray[41]  = "8a";
  $bitlenarray[42]  = "15a";
  $bitlenarray[44]  = "LLVARa";
  $bitlenarray[45]  = "LLVARa";
  $bitlenarray[48]  = "LLLVARa";
  $bitlenarray[49]  = 3;
  $bitlenarray[52]  = 16;
  $bitlenarray[53]  = "LLVARa";
  $bitlenarray[54]  = "LLLVARa";
  $bitlenarray[56]  = "LLVARa";
  $bitlenarray[59]  = "LLLVARa";
  $bitlenarray[60]  = "LLLVAR";
  $bitlenarray[61]  = "LLLVARa";
  $bitlenarray[62]  = "LLLVARa";
  $bitlenarray[63]  = "LLLVARa";
  $bitlenarray[64]  = "8a";
  $bitlenarray[70]  = 3;
  $bitlenarray[126] = "LLLVARa";

  if ( $message eq "" ) {
    return @msgvalues;
  }

  my $idxstart = 12;                            # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 8 );
  my $bitmap   = unpack "H16", $bitmap1;
  if ( ( $logflag eq "yes" ) && ( $findbit eq "" ) ) {
    my $logfilestr = "\n\nbitmap1: $bitmap\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "serverlogmsg.txt", "append", "misc", $logfilestr );
  }
  $idx = $idx + 8;

  my $end     = 1;
  my $bitmap2 = "";
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;
    if ( ( $logflag eq "yes" ) && ( $findbit eq "" ) ) {
      my $logfilestr = "\n\nbitmap2: $bitmap\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "serverlogmsg.txt", "append", "misc", $logfilestr );
    }
    $end = 2;
    $idx = $idx + 8;
  } else {
    $bitmap2 = pack "H*", "0000000000000000";
  }

  my $bitnum2   = 0;
  my $bigbitmap = $bitmap1 . $bitmap2;

  for ( $wordflag = 3 ; $wordflag >= 0 ; $wordflag-- ) {
    my $bitmaphalfb = substr( $bigbitmap, ( 3 - $wordflag ) * 4, 4 );
    my $bitmaphalf = unpack "N", $bitmaphalfb;

    for ( $bitnum = 31 ; $bitnum >= 0 ; $bitnum-- ) {
      if ( $idx + 1 >= length($message) ) {
        last;    # +1 is for etx
      }
      $bitnum2++;

      $bit = ( $bitmaphalf >> $bitnum ) % 2;
      if ( $bit == 0 ) {
        next;    # no data in this bit
      }

      my $idxlen1 = $bitlenarray[$bitnum2];
      $idxlen = $idxlen1;
      if ( $idxlen1 eq "LLVAR" ) {

        #$idxlen = substr($message,$idx,2);
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

      #if ($findbit ne "") {
      #  print "bit: $bitnum2  $idxlen  $value\n";
      #}

      $msgvalues[$bitnum2]    = $value;
      $msgvaluesidx[$bitnum2] = $idx;
      $msgvalueslen[$bitnum2] = $idxlen;

      if ( $findbit == $bitnum2 ) {

        #return $idx, $value;
      }
      $idx = $idx + $idxlen;

    }
  }

  if ( ( $logflag eq "yes" ) && ( $findbit eq "" ) ) {
    my $logfilestr = "\n";
    for ( my $i = 0 ; $i <= $#msgvalues ; $i++ ) {
      if ( $msgvalues[$i] ne "" ) {
        if ( ( $i == 2 ) || ( $i == 35 ) || ( $i == 45 ) ) {
          my $tmpvalue = $msgvalues[$i];
          $tmpvalue =~ s/./x/g;
          $logfilestr .= "$i  $bitlenarray[$i]  $msgvalueslen[$i]  $tmpvalue\n";
        } else {
          my $tmpvalue = $msgvalues[$i];
          $tmpvalue =~ s/([^0-9A-Za-z \=])/\[$1\]/g;
          $tmpvalue =~ s/([^0-9A-Za-z\=\[\] ])/unpack("H2",$1)/ge;
          $logfilestr .= "$i  $bitlenarray[$i]  $msgvalueslen[$i]  $tmpvalue\n";
        }
      }
    }
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/devlogs/global", "serverlogmsg.txt", "append", "misc", $logfilestr );
  }

  return @msgvalues;
}

sub sendvoid {
  @transaction = ();

  $cardnumber = $msgvalues[2];
  if ( $cardnumber ne "" ) {
    $len = length($cardnumber);
    $len = substr( "00" . $len, -2, 2 );
    $transaction[2] = pack "H2H$len", $len, $cardnumber;    # primary acct number (19n) LLVAR 2
  }

  $proc2 = substr( $msgvalues[3], 2, 2 );

  #print "proc_code: $msgvalues[3]\n";
  $newproc = 'A4' . $proc2 . '30';                          # processing code
  $transaction[3] = pack "H6", $newproc;                    # processing code (6a) 3

  $amount = $msgvalues[4];
  $amount = substr( "0" x 12 . $amount, -12, 12 );
  $transaction[4] = pack "H12", $amount;                    # transaction amount (12n) 4

  $tracenum = $msgvalues[11];
  $transaction[11] = pack "H6", $tracenum;                  # system trace number (6n) 11

  #$datetime = $msgvalues[12];
  #$transaction[12] = pack "H12",$datetime;                     # local trans date and time (12n) 12

  $posentry = $msgvalues[22];
  $transaction[22] = $posentry;    # pos entry (12n) 22

  $transaction[25] = '4021';    # reversal reason code (4a) 25

  $mid = $msgvalues[42];
  $transaction[42] = $mid;    # card acceptor id code - terminal/merchant id (15a) 42

  if ( $msgvalues[53] ne "" ) {
    $datalen = length( $msgvalues[53] );
    $datalen = substr( "00" . $datalen, -2, 2 );
    $transaction[53] = pack "H2A$datalen", $datalen, $msgvalues[53];    # debit card dukpt data (16a) LLVAR 53
  }

  $datalen = length( $msgvalues[63] );
  $datalen = substr( "0000" . $datalen, -4, 4 );
  $transaction[63] = pack "H4A$datalen", $datalen, $msgvalues[63];      # global ecom addtl data (ANS999) LLLVAR 63

  #$message = "";
  my $voidmessage = pack "H4", '1400';                                  # message id (4n)

  my ( $bitmap1, $bitmap2 ) = &generatebitmap(@transaction);
  $bitmap1 = pack "H16", $bitmap1;
  if ( $bitmap2 ne "" ) {
    $bitmap2 = pack "H16", $bitmap2;
  }
  $voidmessage = $voidmessage . $bitmap1 . $bitmap2;
  foreach $var (@transaction) {
    $voidmessage = $voidmessage . $var;
  }

  $len     = length($voidmessage);
  $len     = substr( "0000" . $len, -4, 4 );
  $header  = pack "H4A4A4", "0101", "    ", $len;
  $trailer = pack "H2", "03";

  $voidmessage = $header . $voidmessage . $trailer;

  if ( $username eq "testglobal" ) {

    #print "<font size=-1>\n";
    #print "<pre>\n";
    $message2 = $voidmessage;
    $message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

    #print "uu$message2" . "uu<br>\n";
    ($message2) = unpack "H*", $voidmessage;

    #print "vv$message2<br>\n";
  }

  return $voidmessage;
}

sub generatebitmap {
  my (@msg) = @_;

  my $tempdata = "";
  my $message  = "";
  my $tempstr  = "";
  my $bitmap1  = "";
  my $bitmap2  = "";

  for ( my $i = 2 ; $i <= 128 ; $i++ ) {
    $tempdata = $tempdata << 1;
    if ( $msg[$i] ne "" ) {
      $tempdata = $tempdata | 1;
      $message  = $message . $msg[$i];
    } else {
    }
    $tempstr = pack "N", $tempdata;
    $tempstr = unpack "H32", $tempstr;

    #print "tempdata: $tempstr  $i\n";
    if ( $i == 32 ) {
      $bitmap1  = $tempstr;
      $tempdata = 0;
    } elsif ( $i == 64 ) {
      $bitmap1  = $bitmap1 . $tempstr;
      $tempdata = 0;
    } elsif ( $i == 96 ) {
      $bitmap2  = $tempstr;
      $tempdata = 0;
    } elsif ( $i == 128 ) {
      $bitmap2  = $bitmap2 . $tempstr;
      $tempdata = 0;
    }
  }
  if ( $bitmap2 ne "0000000000000000" ) {
    my $tempdata      = pack "H*", $bitmap1;
    my $marketdatabit = pack "H*", "8000000000000000";
    $bitmap1 = $tempdata | $marketdatabit;
    $bitmap1 = unpack "H64", $bitmap1;
  } else {
    $bitmap2 = "";
  }

  #print "bitmap1: $bitmap1\n";
  #print "bitmap2: $bitmap2\n";

  return $bitmap1, $bitmap2;
}

sub checksecondary {
  if ( $test eq "yes" ) {
    $ipaddress = $testipaddress;    # test server
    $port      = $testport;         # test server
    $host      = $testhost;
  } elsif ( -e "/home/pay1/batchfiles/$devprod/global/secondary.txt" ) {
    my @tmpfilestrarray = &procutils::flagread( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "secondary.txt" );
    $secondary = $tmpfilestrarray[0];

    chop $secondary;

    if ( ( ( $secondary eq "1" ) && ( $ipaddress ne $ipaddress1 ) ) || ( ( $secondary eq "2" ) && ( $ipaddress ne $ipaddress2 ) ) ) {
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime switching to secondary socket $secondary\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );

      if ( $secondary eq "1" ) {
        $ipaddress = $ipaddress1;
        $port      = $port1;
        $host      = $host1;
      } elsif ( $secondary eq "2" ) {
        $ipaddress = $ipaddress2;
        $port      = $port2;
        $host      = $host2;
      }

      $socketopenflag = 0;
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }

      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime secondary socket opened\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
    }
  } elsif ( !( -e "/home/pay1/batchfiles/$devprod/global/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $secondary  = "";
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    $logfilestr .= "$primaryipaddress  $primaryport\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );

    $ipaddress = $primaryipaddress;
    $port      = $primaryport;
    $host      = $primaryhost;

    $socketopenflag = 0;
    while ( $socketopenflag != 1 ) {
      &socketopen( "$ipaddress", "$port" );
    }

    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime primary socket opened\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "global", "/home/pay1/batchfiles/$devprod/global", "serverlogmsg.txt", "append", "", $logfilestr );
  }
}

