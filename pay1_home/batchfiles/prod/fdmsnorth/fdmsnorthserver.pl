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

# keya keyb 5578 5579 netb uses these ipc addresses

$test    = "no";
$devprod = "logs";

$host               = "processor-host";    # Source IP address
$primaryipaddress   = "167.16.0.60";       # primary server
$primaryipaddress   = "206.201.52.50";     # primary server old one
$primaryport        = "31004";             # primary server
$secondaryipaddress = "167.16.0.150";      # secondary server
$secondaryport      = "31004";             # secondary server
$testipaddress      = "167.16.0.125";      # test server
$testport           = "22263";             # test server

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;

$nullmessage1 = "aa77000d0011";
$nullmessage2 = "aa550d001100";

if ( $test eq "yes" ) {
  $ipaddress = $testipaddress;             # test server
  $port      = $testport;                  # test server
} elsif ( ( -e "/home/pay1/batchfiles/$devprod/fdmsnorth/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to secondary socket\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $secondaryipaddress;
  $port      = $secondaryport;
} elsif ( !( -e "/home/pay1/batchfiles/$devprod/fdmsnorth/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to primary socket\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $primaryipaddress;
  $port      = $primaryport;
}

while ( $socketopenflag != 1 ) {
  &socketopen( "$ipaddress", "$port" );
  select undef, undef, undef, 2.00;
}

# delete rows older than 2 minutes
my $now      = time();
my $deltime  = &miscutils::timetostr( $now - 120 );
my $printstr = "deltime: $deltime\n";
&procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "accesstime.txt", "write", "", $outfilestr );

  if ( ( -e "/home/pay1/batchfiles/$devprod/fdmsnorth/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
    close(SOCK);
    sleep 1;
    exit;
  }

  $keepalivecnt++;
  if ( $keepalivecnt >= 60 ) {
    my $printstr = "keepalivecnt = $keepalivecnt\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
    $keepalivecnt = 0;
    $socketcnt    = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
    if ( $socketcnt < 1 ) {
      my $printstr = "socketcnt < 1\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
      shutdown SOCK, 2;

      $socketopenflag = 0;
      if ( $socketopenflag != 1 ) {
        $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
        ( $d1, $d2, $tmptime ) = &miscutils::genorderid();
        $logfilestr = "";
        $logfilestr .= "No ESTABLISHED $tmptime\n";
        $logfilestr .= "$sockaddrport\n";
        $logfilestr .= "$sockettmp\n\n";
        &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
      }
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }
      $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
      $logfilestr = "";
      $logfilestr .= "socket reopened\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
    }
  }

  if ( $test eq "yes" ) {
    $ipaddress = $testipaddress;    # test server
    $port      = $testport;         # test server
  } elsif ( ( -e "/home/pay1/batchfiles/$devprod/fdmsnorth/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to secondary socket\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );

    $socketopenflag = 0;
    $ipaddress      = $secondaryipaddress;
    $port           = $secondaryport;
    while ( $socketopenflag != 1 ) {
      &socketopen( "$ipaddress", "$port" );
    }
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime secondary socket opened\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
  } elsif ( !( -e "/home/pay1/batchfiles/$devprod/fdmsnorth/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );

    $socketopenflag = 0;
    $ipaddress      = $primaryipaddress;
    $port           = $primaryport;
    while ( $socketopenflag != 1 ) {
      &socketopen( "$ipaddress", "$port" );
    }
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime primary socket opened\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
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

  if ( ( -e "/home/pay1/batchfiles/$devprod/fdmsnorth/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
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
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='fdmsnorth'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sth1valarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sth1valarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage ) = @sth1valarray[ $vali .. $vali + 4 ];

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

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
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &procutils::updateprocmsg( $processid, "fdmsnorth", "failure", "", "failure: message timeout" );

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

    my $cc = new PlugNPay::CreditCard($cardnumber);
    $shacardnumber = $cc->getCardHash();

    $checkmessage = $messagestr;
    $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $temptime = gmtime( time() );

    $logfilestr = "";
    $logfilestr .= "$username  $orderid\n";
    $logfilestr .= "$temptime send: $checkmessage  $shacardnumber\n\n";
    $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "accesstime.txt", "write", "", $outfilestr );

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

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen attempt $addr $port\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );

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
    $logfilestr = "";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "socketopen successful\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
    $getrespflag = 1;
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }
}

sub socketwrite {
  my ($message) = @_;
  my $printstr = "in socketwrite\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

  if ( $socketopenflag != 1 ) {
    $logfilestr = "";
    $logfilestr .= "socketopenflag = 0, in socketwrite\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
  }
  while ( $socketopenflag != 1 ) {
    &socketopen( "$ipaddress", "$port" );
  }
  send( SOCK, $message, 0, $paddr );

}

sub socketread {
  my ($numtries) = @_;

  my $printstr = "in socketread\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );

  $temp11 = time();
  vec( $rin, fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $respdata = "";
  $mydelay  = 30.0;
  while ( $count && select( $rout = $rin, undef, undef, $mydelay ) ) {
    my $printstr = "in while\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
    $mydelay    = 5.0;
    $logfilestr = "";
    $logfilestr .= "while\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
    recv( SOCK, $response, 2048, 0 );
    $tempstr = unpack "H*", $response;
    my $printstr = "aaaa $tempstr\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

    $respdata = $respdata . $response;

    $resplength = unpack "n", substr( $respdata, 4 );
    $resplength = $resplength + 10;
    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $transcnt--;

      $getrespflag = 1;

      $response = substr( $respdata, 0, $resplength );
      &updatefdmsnorth();
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
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "accesstime.txt", "write", "", $outfilestr );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $delta      = time() - $temp11;
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt delta: $delta\n\n\n\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );

}

sub updatefdmsnorth {

  &decodebitmap($response);

  $rsequencenum = $msgvalues[11];

  $logfilestr = "";
  $logfilestr .= "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
  $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime   = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$temptime recv: $checkmessage\n";
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );

  $sstatus{"$rsequencenum"} = "done";

  # yyyy
  $msg = pack "N", $sprocessid{"$rsequencenum"} + 0;

  $msg = $msg . $response;

  $processid = $sprocessid{"$rsequencenum"};
  &procutils::updateprocmsg( $processid, "fdmsnorth", "success", "", "$response" );

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
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
  print MAIL "Subject: fdmsnorth - no response to authorization\n";
  print MAIL "\n";

  print MAIL "fdmsnorth socket is being closed, then reopened because no response was\n\n";
  print MAIL "received to an authorization request.\n";

  close(MAIL);

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  $tmpi      = 0;
  while ( $socketcnt >= 1 ) {
    $tmpi++;
    if ( $tmpi > 4 ) {
      $logfilestr .= "exiting program because socket couldn't be closed\n\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
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
  &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
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
    $logfilestr = "";
    $logfilestr .= "\n\nbitmap1: $bitmap\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
  }
  $idx = $idx + 8;

  my $end     = 1;
  my $bitmap2 = "";
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;

    if ( ( $findbit ne "" ) && ( $bitmap1 ne "" ) ) {
      $logfilestr = "";
      $logfilestr .= "bitmap2: $bitmap\n";
      &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
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
        &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
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
  if (0) {
    $logfilestr = "";
    $logfilestr .= "\n\n";
    my $bitmap1str = unpack "H*", $bitmap1;
    my $bitmap2str = unpack "H*", $bitmap2;
    $logfilestr .= "bitmap1: $bitmap1str\n";
    $logfilestr .= "bitmap2: $bitmap2str\n";
    my $printstr = "bitmap1: $bitmap1str\n";
    $printstr .= "bitmap2: $bitmap2str\n";
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );

    for ( my $i = 0 ; $i <= $#msgvalues ; $i++ ) {
      if ( $msgvalues[$i] ne "" ) {
        my $chkmessage = $msgvalues[$i];
        $chkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
        $chkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

        $logfilestr .= "$i  $chkmessage\n";
        if ( $msgvalues[$i] =~ /[^0-9a-zA-Z _\-\.]/ ) {
          my $printstr = "$i  $chkmessage\n";
          &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
        } else {
          my $printstr = "$i  $msgvalues[$i]\n";
          &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/devlogs/fdmsnorth", "miscdebug.txt", "append", "misc", $printstr );
        }
      }
    }
    &procutils::filewrite( "$username", "fdmsnorth", "/home/pay1/batchfiles/$devprod/fdmsnorth", "serverlogmsg.txt", "append", "", $logfilestr );
  }

  return @msgvalues;
}

