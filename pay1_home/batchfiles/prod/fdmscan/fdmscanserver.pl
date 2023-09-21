#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib '/home/p/pay1/perl_lib';

use miscutils;
use IO::Socket;
use Socket;
use SHA;
use rsautils;

#Hagerstown 8  host 206.201.50.48 ports 16924, 16925
#Denver 5 host  206.201.53.72 ports 16935, 16936.

$sha1 = new SHA;

$test    = "yes";
$devprod = "dev";

$host               = "processor-host";    # Source IP address
$primaryipaddress   = "206.201.53.50";     # primary server
$primaryport        = "30398";             # primary server
$secondaryipaddress = "206.201.52.50";     # secondary server
$secondaryport      = "30398";             # secondary server
$testipaddress      = "167.16.0.125";      # test server
$testport           = "22833";             # test server

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;

$nullmessage1 = "aa77000d0011";
$nullmessage2 = "aa550d001100";

if ( $test eq "yes" ) {
  $ipaddress = $testipaddress;             # test server
  $port      = $testport;                  # test server
} elsif ( ( -e "/home/p/pay1/batchfiles/$devprod/fdmscan/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
  print logfile "$mytime switching to secondary socket\n";
  print logfile "$sockaddrport\n";
  print logfile "$sockettmp\n\n";
  close(logfile);
  $ipaddress = $secondaryipaddress;
  $port      = $secondaryport;
} elsif ( !( -e "/home/p/pay1/batchfiles/$devprod/fdmscan/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
  print logfile "$mytime switching to primary socket\n";
  print logfile "$sockaddrport\n";
  print logfile "$sockettmp\n\n";
  close(logfile);
  $ipaddress = $primaryipaddress;
  $port      = $primaryport;
}

while ( $socketopenflag != 1 ) {
  &socketopen( "$ipaddress", "$port" );
  select undef, undef, undef, 2.00;
}

# delete rows older than 2 minutes
my $now     = time();
my $deltime = &miscutils::timetostr( $now - 120 );
print "deltime: $deltime\n";

my $dbhmisc = &miscutils::dbhconnect("pnpmisc");

my $sth = $dbhmisc->prepare(
  qq{
        delete from processormsg
        where trans_time<'$deltime'
          or trans_time is NULL
          or trans_time=''
        and processor='fdmscan'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sth->execute()
  or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sth->finish;

$dbhmisc->disconnect;

while (1) {
  $temptime = time();
  open( outfile, ">/home/p/pay1/batchfiles/$devprod/fdmscan/accesstime.txt" );
  print outfile "$temptime\n";
  close(outfile);

  if ( ( -e "/home/p/pay1/batchfiles/$devprod/fdmscan/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
    close(SOCK);
    sleep 1;
    exit;
  }

  $keepalivecnt++;
  if ( $keepalivecnt >= 60 ) {
    print "keepalivecnt = $keepalivecnt\n";
    $keepalivecnt = 0;
    $socketcnt    = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
    if ( $socketcnt < 1 ) {
      print "socketcnt < 1\n";
      shutdown SOCK, 2;
      close(SOCK);
      $socketopenflag = 0;
      if ( $socketopenflag != 1 ) {
        $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
        ( $d1, $d2, $tmptime ) = &miscutils::genorderid();
        open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
        print logfile "No ESTABLISHED $tmptime\n";
        print logfile "$sockaddrport\n";
        print logfile "$sockettmp\n\n";
        close(logfile);
      }
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }
      $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
      print logfile "socket reopened\n";
      print logfile "$sockaddrport\n";
      print logfile "$sockettmp\n\n";
      close(logfile);
    }
  }

  if ( $test eq "yes" ) {
    $ipaddress = $testipaddress;    # test server
    $port      = $testport;         # test server
  } elsif ( ( -e "/home/p/pay1/batchfiles/$devprod/fdmscan/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "$mytime switching to secondary socket\n";
    print logfile "$sockaddrport\n";
    print logfile "$sockettmp\n\n";
    close(logfile);
    close(SOCK);
    $socketopenflag = 0;
    $ipaddress      = $secondaryipaddress;
    $port           = $secondaryport;

    while ( $socketopenflag != 1 ) {
      &socketopen( "$ipaddress", "$port" );
    }
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "$mytime secondary socket opened\n";
    print logfile "$sockaddrport\n";
    print logfile "$sockettmp\n\n";
    close(logfile);
  } elsif ( !( -e "/home/p/pay1/batchfiles/$devprod/fdmscan/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "$mytime switching to primary socket\n";
    print logfile "$sockaddrport\n";
    print logfile "$sockettmp\n\n";
    close(logfile);
    close(SOCK);
    $socketopenflag = 0;
    $ipaddress      = $primaryipaddress;
    $port           = $primaryport;

    while ( $socketopenflag != 1 ) {
      &socketopen( "$ipaddress", "$port" );
    }
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "$mytime primary socket opened\n";
    print logfile "$sockaddrport\n";
    print logfile "$sockettmp\n\n";
    close(logfile);
  }

  &check();
  if ( $getrespflag == 0 ) {
    &socketclose();
  }
  select undef, undef, undef, 1.00;
}

exit;

sub check {
  $todayseconds = time();
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - ( 60 * 2 ) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  if ( ( -e "/home/p/pay1/batchfiles/$devprod/fdmscan/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
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

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");

  my $sth1 = $dbhmisc->prepare(
    qq{
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='fdmscan'
        and status='pending'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth1->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth1->bind_columns( undef, \( $trans_time, $processid, $username, $orderid, $encmessage ) );

  while ( $sth1->fetch ) {
    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

    my $sth = $dbhmisc->prepare(
      qq{
          update processormsg set status='locked'
          where processid='$processid'
          and status='pending'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute()
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sth->finish;

    $username =~ s/[^0-9a-zA-Z_]//g;
    $trans_time =~ s/[^0-9]//g;
    $orderid =~ s/[^0-9]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;

    print "$mytime msgrcv $username $orderid\n";

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &mysqlmsgsnd( $dbhmisc, $processid, "failure", "", "failure: message timeout" );

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

    &decodebitmap($message);

    $username =~ s/[^0-9a-zA-Z_]//g;

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;
    $sinvoicenum{"$sequencenum"} = $invoicenum;

    $cardnum = $msgvalues[2];
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

    $messagestr = $message;
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

    if ( $messagestr =~ /\#0131(.*)?\#/ ) {
      $cvv = $1;
      $cvv =~ s/ //;
      $xs = "x" x length($cvv);
      $messagestr =~ s/\#0131$cvv/\#0131$xs/;
    } elsif ( $messagestr =~ /\@0131(.*)?\#/ ) {
      $cvv = $1;
      $cvv =~ s/ //;
      $xs = "x" x length($cvv);
      $messagestr =~ s/\@0131$cvv/\@0131$xs/;
    }

    $cardnumber = $cardnum;
    $sha1->reset;
    $sha1->add($cardnumber);
    $shacardnumber = $sha1->hexdigest();

    $checkmessage = $messagestr;
    $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $temptime = gmtime( time() );

    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "$username  $orderid\n";
    print logfile "$temptime send: $checkmessage  $shacardnumber\n\n";
    print logfile "sequencenum: $sequencenum retries: $retries\n";
    close(logfile);

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime = time();
    open( outfile, ">/home/p/pay1/batchfiles/$devprod/fdmscan/accesstime.txt" );
    print outfile "$temptime\n";
    close(outfile);

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt > 6 ) {
      last;
    }
  }

  if ( $transcnt > 0 ) {
    $numtrans = $transcnt;
    &socketread($transcnt);

    foreach $rsequencenum ( keys %susername ) {
      if ( $sstatus{"$rsequencenum"} ne "done" ) {
        $sretries{"$rsequencenum"}++;
        if ( $sretries{"$rsequencenum"} > 2 ) {
          delete $susername{$rsequencenum};
          delete $strans_time{$rsequencenum};
          delete $smessage{$rsequencenum};
          delete $sretries{$rsequencenum};
          delete $sorderid{$rsequencenum};
          delete $sprocessid{$rsequencenum};
          delete $sinvoicenum{$rsequencenum};
        }
      }
    }
  }

}

sub socketopen {
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  shutdown SOCK, 2;
  close(SOCK);
  select undef, undef, undef, 1.00;

  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
  print logfile "$mytime socketopen attempt $addr $port\n";
  close(logfile);

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  connect( SOCK, $paddr ) || die "connect: $addr $port $!";
  $socketopenflag = 1;

  $sockaddr    = getsockname(SOCK);
  $sockaddrlen = length($sockaddr);
  if ( $sockaddrlen == 16 ) {
    ($sockaddrport) = unpack_sockaddr_in($sockaddr);
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "$sockaddrport\n";
    print logfile "socketopen successful\n";
    close(logfile);
    $getrespflag = 1;
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }
}

sub socketwrite {
  my ($message) = @_;
  print "in socketwrite\n";

  if ( $socketopenflag != 1 ) {
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "socketopenflag = 0, in socketwrite\n";
    close(logfile);
  }
  while ( $socketopenflag != 1 ) {
    &socketopen( "$ipaddress", "$port" );
  }
  send( SOCK, $message, 0, $paddr );
}

sub socketread {
  my ($numtries) = @_;

  print "in socketread\n";
  $donereadingflag = 0;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
  print logfile "socketread: $transcnt\n";
  close(logfile);

  $temp11 = time();
  vec( $rin, fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $respdata = "";
  $mydelay  = 30.0;
  while ( $count && select( $rout = $rin, undef, undef, $mydelay ) ) {
    print "in while\n";
    $mydelay = 5.0;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "while\n";
    close(logfile);
    recv( SOCK, $response, 2048, 0 );
    $tempstr = unpack "H*", $response;
    print "aaaa $tempstr\n";

    $respdata = $respdata . $response;

    $resplength = unpack "S", substr( $respdata, 4 );
    $resplength = $resplength + 10;
    $rlen       = length($respdata);
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "rlen: $rlen, resplength: $resplength\n";
    close(logfile);

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $transcnt--;

      $getrespflag = 1;

      $response = substr( $respdata, 0, $resplength );
      &updatefdmscan();
      delete $writearray{$rsequencenum};
      if ( !%writearray ) {
        $donereadingflag = 1;
      }
      $respdata = substr( $respdata, $resplength );
      $resplength = unpack "S", substr( $respdata, 4 );
      $resplength = $resplength + 10;
      $rlen       = length($respdata);

      $temptime = time();
      open( outfile, ">/home/p/pay1/batchfiles/$devprod/fdmscan/accesstime.txt" );
      print outfile "$temptime\n";
      close(outfile);
    }

    if ( $donereadingflag == 1 ) {
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
      print logfile "donereadingflag = 1\n";
      close(logfile);
      last;
    }

    $count--;
  }
  $delta = time() - $temp11;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
  print logfile "end loop $transcnt delta: $delta\n\n\n\n";
  close(logfile);

}

sub updatefdmscan {

  &decodebitmap($response);

  $rsequencenum = $msgvalues[11];

  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
  print logfile "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  close(logfile);
  $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
  print logfile "$temptime recv: $checkmessage\n";
  close(logfile);

  $sstatus{"$rsequencenum"} = "done";

  # yyyy
  $msg = pack "L", $sprocessid{"$rsequencenum"} + 0;

  $msg = $msg . $response;

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");
  $processid = $sprocessid{"$rsequencenum"};
  if ( &mysqlmsgsnd( $dbhmisc, $processid, "success", "", "$response" ) == NULL ) { }
  $dbhmisc->disconnect;

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sprocessid{$rsequencenum};
  delete $sinvoicenum{$rsequencenum};

}

sub socketclose {
  $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
  $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
  ( $d1, $d2, $temp ) = &miscutils::genorderid();
  print logfile "before socket is closed because of no response $temp\n$sockaddrport\n$sockettmp\n\n";

  shutdown SOCK, 2;
  close(SOCK);
  $socketopenflag = 0;
  $getrespflag    = 1;

  open( MAIL, "| /usr/lib/sendmail -t" );
  print MAIL "To: cprice\@plugnpay.com\n";
  print MAIL "From: dprice\@plugnpay.com\n";
  print MAIL "Subject: fdmscan - no response to authorization\n";
  print MAIL "\n";

  print MAIL "fdmscan socket is being closed, then reopened because no response was\n\n";
  print MAIL "received to an authorization request.\n";

  close(MAIL);

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  $tmpi      = 0;
  while ( $socketcnt >= 1 ) {
    $tmpi++;
    if ( $tmpi > 4 ) {
      print logfile "exiting program because socket couldn't be closed\n\n";
      close(logfile);
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
  print logfile "socket closed because of no response $temp\n$sockaddrport\n$sockettmp\n\n";
  close(logfile);
}

sub decodebitmap {
  my ( $message, $findbit ) = @_;
  my $chkmessage = $message;
  $chkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $chkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

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
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "\n\nbitmap1: $bitmap\n";
    close(logfile);
  }
  $idx = $idx + 8;

  my $end     = 1;
  my $bitmap2 = "";
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;

    if ( ( $findbit ne "" ) && ( $bitmap1 ne "" ) ) {
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
      print logfile "bitmap2: $bitmap\n";
      close(logfile);
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
        print "myk 24\n";
        exit;
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

  if (0) {
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmscan/serverlogmsgtest.txt" );
    print logfile "\n\n";
    my $bitmap1str = unpack "H*", $bitmap1;
    my $bitmap2str = unpack "H*", $bitmap2;
    print logfile "bitmap1: $bitmap1str\n";
    print logfile "bitmap2: $bitmap2str\n";
    print "bitmap1: $bitmap1str\n";
    print "bitmap2: $bitmap2str\n";

    for ( my $i = 0 ; $i <= $#msgvalues ; $i++ ) {
      if ( $msgvalues[$i] ne "" ) {
        my $chkmessage = $msgvalues[$i];
        $chkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
        $chkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

        print logfile "$i  $chkmessage\n";
        if ( $msgvalues[$i] =~ /[^0-9a-zA-Z _\-\.]/ ) {
          print "$i  $chkmessage\n";
        } else {
          print "$i  $msgvalues[$i]\n";
        }
      }
    }
    close(logfile);
  }

  return @msgvalues;
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
        and status='locked'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute( "$status", "$invoicenum" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth->finish;

}

