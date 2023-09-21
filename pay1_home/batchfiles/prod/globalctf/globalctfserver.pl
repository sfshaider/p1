#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib '/home/p/pay1/perl_lib';
use miscutils;
use IO::Socket;
use Socket;

#require 'sys/ipc.ph';
#require 'sys/msg.ph';
use SHA;

#use Convert::EBCDIC (ascii2ebcdic, ebcdic2ascii);

$test    = "no";
$devprod = "prod";

$sha1 = new SHA;

$keepalive   = 0;
$getrespflag = 1;
$sequencenum = 0;
$numtrans    = 0;    # used only for throughput checks

$nullmessage = pack "H6A3SA8H2", "010103", "   ", "0008", "POLL RSP", "03";

$host = "processor-host";    # Source IP address

$primaryipaddress = '64.69.201.195';    # primary server
$primaryport      = '18695';            # primary server
$primaryhost      = "$host";            # Source IP address

$ipaddress1 = '64.27.243.6';            # secondary server
$host1      = "$host";                  # Source IP address
$port1      = '18695';

$ipaddress2 = '64.27.243.6';            # secondary server
$host2      = "$host";                  # Source IP address
$port2      = '18695';

$testipaddress = '64.69.205.190';       # test server
$testport      = '18695';               # test server
$testhost      = "$host";               # Source IP address

$ipaddress = $primaryipaddress;
$port      = $primaryport;

&checksecondary();

&socketopen( $ipaddress, $port );

while (1) {
  $temptime = time();
  open( outfile, ">/home/p/pay1/batchfiles/$devprod/globalctf/accesstime.txt" );
  print outfile "$temptime\n";
  close(outfile);

  if ( -e "/home/p/pay1/batchfiles/$devprod/globalctf/stopserver.txt" ) {
    close(SOCK);
    exit;
  }

  &checksecondary();

  &check();

  if ( $getrespflag == 0 ) {
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
    print logfile "$mytime getrespflag = 0, closing socket\n";
    close(logfile);
    close(SOCK);
    $socketopenflag = 0;
    $getrespflag    = 1;
    system('sleep 2');
    &socketopen( $ipaddress, $port );
  }

  system("sleep 1");

  #system("usleep 200000");
  $keepalive++;

  if ( $keepalive >= 60 ) {
    close(SOCK);
    $socketopenflag = 0;

    #$message = pack "H12", "000000000000";

    #&socketwrite($message);
    $keepalive = 0;

  }
}

sub mysqlmsgsnd {
  my ( $dbhhandle, $processid, $status, $invoicenum, $msg ) = @_;

  my ($encmsg) = &rsautils::rsa_encrypt_card( $msg, '/home/p/pay1/pwfiles/keys/key', 'log' );

  %datainfo = ( "processid", "$processid", "status", "$status", "invoicenum", "$invoicenum", "msg", "$encmsg" );

  my $sthsens = $dbhhandle->prepare(
    q{
          SET @sensitivedata = ?
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthsens->execute("$encmsg")
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

  my $sth = $dbhhandle->prepare(
    qq{
        update processormsg set status=?,invoicenum=?,message=\@sensitivedata
        where processid='$processid'
        and processor='globalctf'
        and status='locked'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute( "$status", "$invoicenum" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth->finish;

}

sub check {
  $todayseconds = time();
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - ( 60 * 2 ) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  foreach $key ( keys %writearray ) {
    if ( $writearray{$key} < $ttime1 ) {
      delete $writearray{$key};
    } else {

      #open(tempfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/temp.txt");
      #print tempfile "$ttime1 $writearray{$key}\n";
      #close(tempfile);
    }
  }

  #&timecheck("before selecting");
  $timecheckend3   = time();
  $timecheckdelta3 = $timecheckend3 - $timecheckstart3;
  $timecheckstart3 = $timecheckend3;
  if ( $numtrans == 4 ) {

    #open(tempfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/time.txt");
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

  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
  print logfile "aaaa select from processormsg\n";
  close(logfile);

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");

  my $sthmsg = $dbhmisc->prepare(
    qq{
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='globalctf'
        and status='pending'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $globalctf::DBI::errstr", %datainfo );
  $sthmsg->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $globalctf::DBI::errstr", %datainfo );
  $sthmsg->bind_columns( undef, \( $trans_time, $processid, $username, $orderid, $encmessage ) );

  while ( $sthmsg->fetch ) {
    if ( ( -e "/home/p/pay1/batchfiles/$devprod/globalctf/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
      close(SOCK);
      sleep 1;
      exit;
    }

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

    my $sth = $dbhmisc->prepare(
      qq{
          update processormsg set status='locked'
          where processid='$processid'
          and processor='globalctf'
          and status='pending'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $global::DBI::errstr", %datainfo );
    $sth->execute()
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $global::DBI::errstr", %datainfo );
    $sth->finish;

    while (1) { }

    $username =~ s/[^0-9a-zA-Z_]//g;
    $orderid =~ s/[^0-9]//g;

    #print "type: $type\n";
    print "processid: $processid\n";
    print "username: $username\n";
    print "orderid: $orderid\n";
    print "trans_time: $trans_time\n";
    print "message: $message\n";

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &mysqlmsgsnd( $dbhmisc, $processid, "failure", "", "failure: message timeout" );

      next;
    }

    #&timecheck("get next valid orderid");

    $transcnt++;

    $sequencenum = ( $sequencenum % 998 ) + 1;
    $sequencenum = substr( "000000" . $sequencenum, -6, 6 );

    print "$sequencenum\n";

    $message =~ s/\x1cmxxxxxx/\x1cm$sequencenum/;

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

    #open(logfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt");
    #print logfile "sequencenum: $sequencenum retries: $retries\n";
    #close(logfile);

    $timecheckend1   = time();
    $timecheckdelta1 = $timecheckend1 - $timecheckstart1;

    # xxxx
    ( $d1, $d2, $temptime ) = &miscutils::genorderid();
    $checkmessage = $message;
    $checkmessage =~ s/\x02/\[02\]/g;
    $checkmessage =~ s/\x03/\[03\]/g;
    $checkmessage =~ s/\x1c/\[1c\]/g;
    $checkmessage =~ s/\x1e/\[1e\]/g;

    #open(tempfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlog.txt");
    #print tempfile "$temptime $checkmessage\n";
    print "$temptime $checkmessage\n";

    #close(tempfile);

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime = time();
    open( outfile, ">/home/p/pay1/batchfiles/$devprod/globalctf/accesstime.txt" );
    print outfile "$temptime\n";
    close(outfile);

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
        #open(logfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt");
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

  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
  print logfile "$mytime socketopen attempt $addr $port\n";
  close(logfile);

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

  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
  print logfile "socketopen successful\n";
  close(logfile);
}

sub socketwrite {
  my ($message) = @_;

  if ( $socketopenflag != 1 ) {
    &socketopen( $ipaddress, $port );
  }
  if ( $socketopenflag != 1 ) {
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
    print logfile "socketopenflag = 0, exiting\n";
    close(logfile);
    exit;
  }

  $messagestr = $message;

  #@msgvalues = &decodebitmap("$message");
  $cardnum = "";
  $xs      = "";
  if (0) {
    if ( $msgvalues[2] ne "" ) {
      $cardnum    = $msgvalues[2];
      $cardnumidx = $msgvaluesidx[2];
      $cardnum =~ s/[^0-9]//g;
      $len        = length($cardnum);
      $len        = substr( "00" . $len, -2, 2 );
      $newcardnum = pack "H$len", $cardnum;
      $xs         = "x" x length($newcardnum);
      $messagestr = $message;

      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $message, 0, $cardnumidx ) . $xs . substr( $message, $cardnumidx + ( $len / 2 ) );
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
      $xs         = "x" x $len;
      $messagestr = $message;

      #$messagestr =~ s/$cardnum/$xs/g;
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $message, 0, $cardnumidx + 1 ) . $xs . substr( $message, $cardnumidx + $len + 1 );
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
      $xs         = "x" x $len;
      $messagestr = $message;
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $message, 0, $cardnumidx ) . $xs . substr( $message, $cardnumidx + $len );
      }
    }

    if ( $msgvalues[126] ne "" ) {    # cvv
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
  #$cardnum =~ s/[^0-9]//g;
  #$shacardnumber = "";
  #if ((length($cardnum) >= 13) && (length($cardnum) < 20)) {
  #  $cardnumber = $cardnum;
  #  $sha1->reset;
  #  $sha1->add($cardnumber);
  #  $shacardnumber = $sha1->hexdigest();
  #}

  $mytime   = gmtime( time() );
  $message2 = $messagestr;
  $message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  if ( $message2 =~ /\[1c\]c(.+?)\[1c\]f/ ) {
    $cardnum = $1;
    $len     = length($cardnum);
    $xs      = "x" x $len;
    $message2 =~ s/\[1c\]c(.+?)\[1c\]f/\[1c\]c$xs\[1c\]f/;
  }
  if ( $message2 =~ /\[1c\]ca(.+?)\[1c\]/ ) {
    $cvv = $1;
    $len = length($cvv);
    $xs  = "x" x $len;
    $message2 =~ s/\[1c\]ca(.+?)\[1c\]/\[1c\]ca$xs\[1c\]/;
  }
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
  print logfile "$username $orderid\n";
  if ( $secondary ne "" ) {
    print logfile "secondary $secondary\n";
  }
  print logfile "$mytime send: $message2  $shacardnumber\n";
  close(logfile);

  send( SOCK, $message, 0, $paddr );

}

sub socketread {
  ($numtries) = @_;

  $donereadingflag = 0;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
  print logfile "socketread: $transcnt\n";
  close(logfile);

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
    $delaytime = 5.0;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
    ( $d1, $d2, $temptime ) = &miscutils::genorderid();
    print logfile "while $temptime\n";
    close(logfile);
    recv( SOCK, $response, 2048, 0 );

    $respdata = $respdata . $response;

    ( $d1, $d2, $resplength ) = unpack "H4A4A4", $respdata;
    $resplength = $resplength + 11;

    $rlen = length($respdata);
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
    print logfile "rlen: $rlen, resplength: $resplength\n";
    print "rlen: $rlen, resplength: $resplength\n";
    close(logfile);

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
        open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
        print logfile "null message found\n\n";
        close(logfile);
      }
      $respdata = substr( $respdata, $resplength );

      ( $d1, $d2, $resplength ) = unpack "H4A4A4", $respdata;
      $resplength = $resplength + 11;
      $rlen       = length($respdata);

      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
      print logfile "rlen: $rlen, resplength: $resplength\n";
      print "rlen: $rlen, resplength: $resplength\n";
      close(logfile);

      #$mytime = gmtime(time());
      #$message2 = $respdata;
      #$message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
      #$message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
      #open(logfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt");
      #print logfile "$mytime recvaaaa: $message2\n";
      #$message2 = unpack "H*", $respdata;
      #print logfile "response2aaaa: $message2\n";
      #close(logfile);

      $temptime = time();
      open( outfile, ">/home/p/pay1/batchfiles/$devprod/globalctf/accesstime.txt" );
      print outfile "$temptime\n";
      close(outfile);
    }

    if ( $donereadingflag == 1 ) {
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
      print logfile "donereadingflag = 1\n";
      close(logfile);
      last;
    }

    $count--;
  }
  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
  print logfile "$mytime end loop $transcnt\n\n\n\n";
  close(logfile);

}

sub update {

  $mytime   = gmtime( time() );
  $message2 = $response;
  $message2 =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $message2 =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
  print logfile "$mytime recv: $message2\n";
  close(logfile);
  print "$mytime recv: $message2\n";

  $header  = substr( $response, 0,  11 );
  $trailer = substr( $response, -1, 1 );
  $tmpstr = unpack "H*", $header;
  print "header: $tmpstr\n";
  $tmpstr = unpack "H*", $trailer;
  print "trailer: $tmpstr\n";
  if ( ( $header !~ /^.*\x02$/ ) || ( $trailer ne "\x03" ) ) {
    print "code does not have stx or etx\n";
    $tmpstr = unpack "H*", $header;
    print "header: $tmpstr\n";
    $tmpstr = unpack "H*", $trailer;
    print "trailer: $tmpstr\n";
    exit;
  }

  $chkresponse = $response;
  $chkresponse =~ s/^.*\x02//;
  $chkresponse =~ s/\x03$//;
  (@fields) = split( /\x1c/, $chkresponse );
  foreach $var (@fields) {
    my $tag = substr( $var, 0, 1 );
    my $data = substr( $var, 1 );
    $temparray{$tag} = $data;
  }

  foreach $key ( sort keys %temparray ) {
    print "aa $key $temparray{$key}\n";
  }

  $rsequencenum = $temparray{'M'};

  if ( $rsequencenum eq "" ) {
    return;
  }
  if ( length($rsequencenum) > 6 ) {
    return;
  }

  #$temp = unpack "H*", $tempmsg;
  #$cnumlen = unpack "H2", $tempmsg;
  #$cnum = substr($temp,2,$cnumlen);
  #$pcode = substr($temp,2+$cnumlen,6);
  #$seqindx = $idx + 4 + 6 + ($cnumlen/2);
  #$sseq = unpack "H6", substr($message,$seqindx,6);
  #print "temp: $temp\ncnumlen: $cnumlen\ncnum: $cnum\npcode: $pcode\nsseq: $sseq\n";
  #print "$sequencenum\n";

  #open(logfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt");
  #print logfile "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  #close(logfile);
  $checkmessage = $response;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/\x1e/\[1e\]/g;

  #open(logfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt");
  #print logfile "response: $checkmessage\n";
  #close(logfile);

  #&timecheck("before update");
  if ( $timecheckfirstflag2 == 1 ) {
    $timecheckstart2     = time();
    $timecheckfirstflag2 = 0;
  }

  $sstatus{"$rsequencenum"} = "done";

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");
  $processid = $sprocessid{"$rsequencenum"};
  if ( &mysqlmsgsnd( $dbhmisc, $processid, "success", "$sinvoicenum{$rsequencenum}", "$response" ) == NULL ) { }
  $dbhmisc->disconnect;

  my $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
  print logfile "$mytime snd success $checktime\n";
  close(logfile);

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

  #open(tempfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlog.txt");
  #print tempfile "$temptime $checkmessage\n";
  #close(tempfile);
}

sub decodebitmap {
  my ( $message, $findbit ) = @_;

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
  $bitlenarray[41]  = 3;
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

  my $idxstart = 12;                            # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 8 );
  my $bitmap   = unpack "H16", $bitmap1;

  #print "\n\nbitmap1: $bitmap\n";
  #if ($findbit eq "") {
  #  open(logfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt");
  #  print logfile "\n\nbitmap1: $bitmap\n";
  #  close(logfile);
  #}
  $idx = $idx + 8;

  my $end     = 1;
  my $bitmap2 = "";
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;

    #print "bitmap2: $bitmap\n";
    #if ($findbit eq "") {
    #  open(logfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt");
    #  print logfile "bitmap2: $bitmap\n";
    #  close(logfile);
    #}
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
    my $bitmapa = unpack "L", $bitmaphalfa;

    my $bitmaphalfb = substr( $bitmaphalf, 4, 4 );
    my $bitmapb = unpack "L", $bitmaphalfb;

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

        #$bit = ($bitmaphalf >> (128 - $bitnum)) % 2;
        $bit = ( $bitmaphalf >> ( 128 - ( $wordflag * 32 ) - $bitnum ) ) % 2;
        $bitnum++;
        $bitnum2++;
      }
      if ( $bitnum == 65 ) {
        last;
      }

      my $idxlen1 = $bitlenarray[ $bitnum2 - 1 ];
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

      my $tmpbit = $bitnum2 - 1;

      #if ($findbit ne "") {
      #print "bit: $tmpbit  $idxlen  $value\n";
      #}
      $msgvalues[$tmpbit]    = $value;
      $msgvaluesidx[$tmpbit] = $idx;
      $msgvalueslen[$tmpbit] = $idxlen;
      $myk++;
      if ( $myk > 20 ) {
        print "myk 20\n";
        exit;
      }
      if ( $findbit == $bitnum - 1 ) {

        #return $idx, $value;
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
       #print "\n";
       #return "-1", "";

  #open(logfile,">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt");
  #print logfile "\n\n";
  #for (my $i=0; $i<=$#msgvalues; $i++) {
  #  if ($msgvalues[$i] ne "") {
  #    print logfile "$i  $bitlenarray[$i]  $msgvalueslen[$i]  $msgvalues[$i]\n";
  #  }
  #}
  #close(logfile);

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
  $transaction[63] = pack "H4A$datalen", $datalen, $msgvalues[63];      # globalctf ecom addtl data (ANS999) LLLVAR 63

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

  if ( $username eq "testglobalctf" ) {

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
    $tempstr = pack "L", $tempdata;
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
  } elsif ( -e "/home/p/pay1/batchfiles/$devprod/globalctf/secondary.txt" ) {
    open( tmpfile, "/home/p/pay1/batchfiles/$devprod/globalctf/secondary.txt" );
    $secondary = <tmpfile>;
    close(tmpfile);
    chop $secondary;

    if ( ( ( $secondary eq "1" ) && ( $ipaddress ne $ipaddress1 ) ) || ( ( $secondary eq "2" ) && ( $ipaddress ne $ipaddress2 ) ) ) {
      $mytime = gmtime( time() );
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
      print logfile "$mytime switching to secondary socket $secondary\n";
      close(logfile);

      if ( $secondary eq "1" ) {
        $ipaddress = $ipaddress1;
        $port      = $port1;
        $host      = $host1;
      } elsif ( $secondary eq "2" ) {
        $ipaddress = $ipaddress2;
        $port      = $port2;
        $host      = $host2;
      }

      close(SOCK);
      $socketopenflag = 0;
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }

      $mytime = gmtime( time() );
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctfrverlogmsg.txt" );
      print logfile "$mytime secondary socket opened\n";
      print logfile "$sockaddrport\n";
      print logfile "$sockettmp\n\n";
      close(logfile);
    }
  } elsif ( !( -e "/home/p/pay1/batchfiles/$devprod/globalctf/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctf/serverlogmsg.txt" );
    print logfile "$mytime switching to primary socket\n";
    print logfile "$primaryipaddress  $primaryport\n";
    close(logfile);

    $ipaddress = $primaryipaddress;
    $port      = $primaryport;
    $host      = $primaryhost;

    close(SOCK);
    $socketopenflag = 0;
    while ( $socketopenflag != 1 ) {
      &socketopen( "$ipaddress", "$port" );
    }

    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/globalctfrverlogmsg.txt" );
    print logfile "$mytime primary socket opened\n";
    print logfile "$sockaddrport\n";
    print logfile "$sockettmp\n\n";
    close(logfile);
  }
}

