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

#Hagerstown 8  ports 16924, 16925
#Denver 5  ports 16935, 16936.

$test    = "no";
$devprod = "logs";

$host               = "processor-host";    # Source IP address
$primaryipaddress   = "167.16.0.52";       # primary server
$primaryport        = "16925";             # primary server
$secondaryipaddress = "167.16.0.154";      # secondary server
$secondaryport      = "16936";             # secondary server
$testipaddress      = "167.16.0.125";      # test server
$testport           = "11166";             # test server

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;
$sendfailurecnt = 0;

$nullmessage1 = "aa77000d0011";
$nullmessage2 = "aa550d001100";

if ( $test eq "yes" ) {
  $ipaddress = $testipaddress;             # test server
  $port      = $testport;                  # test server
} elsif ( ( -e "/home/pay1/batchfiles/$devprod/fdms/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to secondary socket\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $secondaryipaddress;
  $port      = $secondaryport;
} elsif ( !( -e "/home/pay1/batchfiles/$devprod/fdms/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to primary socket\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
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
&procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );

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
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "baccesstime.txt", "write", "", $outfilestr );

  if ( ( -e "/home/pay1/batchfiles/$devprod/fdms/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
    close(SOCK);
    sleep 1;
    exit;
  }

  $keepalivecnt++;
  if ( $keepalivecnt >= 60 ) {
    my $printstr = "keepalivecnt = $keepalivecnt\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );
    $keepalivecnt = 0;
    $socketcnt    = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
    if ( $socketcnt < 1 ) {
      my $printstr = "socketcnt < 1\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );
      shutdown SOCK, 2;
      close(SOCK);

      $socketopenflag = 0;
      if ( $socketopenflag != 1 ) {
        $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
        ( $d1, $d2, $tmptime ) = &miscutils::genorderid();
        $logfilestr = "";
        $logfilestr .= "No ESTABLISHED $tmptime\n";
        $logfilestr .= "$sockaddrport\n";
        $logfilestr .= "$sockettmp\n\n";
        &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
      }
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }
      $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
      $logfilestr = "";
      $logfilestr .= "socket reopened\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
    }
  }

  if ( $test eq "yes" ) {
    $ipaddress = $testipaddress;    # test server
    $port      = $testport;         # test server
  } elsif ( ( -e "/home/pay1/batchfiles/$devprod/fdms/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to secondary socket\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
    close(SOCK);
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
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
  } elsif ( !( -e "/home/pay1/batchfiles/$devprod/fdms/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
    close(SOCK);
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
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
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
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - (90) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  if ( ( -e "/home/pay1/batchfiles/$devprod/fdms/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
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
        where processor='fdmsb'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sthmsgvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthmsgvalarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage ) = @sthmsgvalarray[ $vali .. $vali + 4 ];

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and processor='fdmsb'
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $username =~ s/[^0-9a-zA-Z_]//g;
    $trans_time =~ s/[^0-9]//g;
    $orderid =~ s/[^0-9]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;

    my $printstr = "$mytime msgrcv $username $orderid\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );

    # send back failure if more than 60 seconds has passed
    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {

      &procutils::updateprocmsg( $processid, "fdmsb", "failure", "", "failure: message timeout" );

      next;
    }

    # $message "invoicenum" is for forces and credits that need an invoice number for settlement
    if ( $message ne "invoicenum" ) {
      $transcnt++;

      $sequencenum = ( $sequencenum + 1 ) % 255;
      $sequencenum = sprintf( "%012d", $sequencenum );
      $message     = substr( $message, 0, 6 ) . $sequencenum . substr( $message, 18 );
    }

    $username =~ s/[^0-9a-zA-Z_]//g;

    # settlement does not edit invoicenum
    if (0) {
      %datainfo = ( "username", "$username" );
      my $dbquerystr = <<"dbEOM";
          select username,invoicenum
          from fdms
          where username=?
dbEOM
      my @dbvalues = ("$username");
      ( $chkusername, $invoicenum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      $invoicenum = ( $invoicenum % 10000000 ) + 1;

      if ( $chkusername eq "" ) {
        my $dbquerystr = <<"dbEOM";
            insert into fdms
            (username,invoicenum)
            values (?,?)
dbEOM

        my %inserthash = ( "username", "$username", "invoicenum", "$invoicenum" );
        &procutils::dbinsert( $username, $orderid, "pnpmisc", "fdms", %inserthash );

      } else {
        my $dbquerystr = <<"dbEOM";
            update fdms set invoicenum=?
            where username=?
dbEOM
        my @dbvalues = ( "$invoicenum", "$username" );
        &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      }

      $chkinvoicenum = substr( $message, 87, 10 );
      if ( $message eq "invoicenum" ) {
        $invoicenum = sprintf( "%010d", $invoicenum + .0001 );
      } elsif ( $chkinvoicenum eq "0000000000" ) {
        $invoicenum = sprintf( "%010d", $invoicenum + .0001 );
        $message = substr( $message, 0, 87 ) . $invoicenum . substr( $message, 97 );
      } else {
        $invoicenum = $chkinvoicenum;
      }
    }

    # yyyy
    my $printstr = "aaaa $processid $invoicenum $message bbbb\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );
    if ( $message eq "invoicenum" ) {
      my $printstr = "aaaa $processid $invoicenum\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );

      &procutils::updateprocmsg( $processid, "fdmsb", "success", "$invoicenum", "invoicenum" );

      next;
    }

    my $printstr = "cccc $orderid  $invoicenum\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;
    $sinvoicenum{"$sequencenum"} = $invoicenum;

    $cardnum = substr( $message, 57, 19 );
    $cardnum =~ s/ //g;
    $xs         = "x" x length($cardnum);
    $xs2        = "x" x ( length($cardnum) + 12 );
    $messagestr = $message;
    $messagestr =~ s/B$cardnum.{12}/B$xs2/g;
    $messagestr =~ s/$cardnum/$xs/g;

    if ( $messagestr =~ /B$xs(.*)?\?/ ) {
      $mag = $1;
      $xs3 = "x" x length($mag);
      $messagestr =~ s/B$xs(.*)?\?/B$xs$xs3\?/;
    }

    if ( $messagestr =~ / {15}2$xs(.*)?\?/ ) {
      $mag = $1;
      $xs3 = "x" x length($mag);
      $messagestr =~ s/ {15}2$xs(.*)?\?/ {15}2$xs$xs3\?/;
    }

    if ( $messagestr =~ /\#0131([0-9]{3,4})[ \#\@]/ ) {
      $cvv = $1;
      $cvv =~ s/ //;
      $xs = "x" x length($cvv);
      $messagestr =~ s/\#0131$cvv/\#0131$xs/;
    } elsif ( $messagestr =~ /\@0131([0-9]{3,4})[ \#\@]/ ) {
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
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "baccesstime.txt", "write", "", $outfilestr );

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt > 12 ) {
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

  $logfilestr = "";
  $logfilestr .= "socketopen attempt $addr $port\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );

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
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
    $getrespflag = 1;
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }
}

sub socketwrite {
  my ($message) = @_;
  my $printstr = "in socketwrite\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );

  if ( $socketopenflag != 1 ) {
    $logfilestr = "";
    $logfilestr .= "socketopenflag = 0, in socketwrite\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
  }
  while ( $socketopenflag != 1 ) {
    &socketopen( "$ipaddress", "$port" );
  }
  send( SOCK, $message, 0, $paddr );
}

sub socketread {
  my ($numtries) = @_;

  my $printstr = "in socketread\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );
  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );

  $temp11 = time();
  vec( $rin, fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $respdata = "";
  $mydelay  = 30.0;
  while ( $count && select( $rout = $rin, undef, undef, $mydelay ) ) {
    my $printstr = "in while\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/devlogs/fdms", "miscdebug.txt", "append,debug", "misc", $printstr );
    $mydelay    = 1.0;
    $logfilestr = "";
    $logfilestr .= "while\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
    recv( SOCK, $response, 2048, 0 );

    $respdata = $respdata . $response;

    $resplength = unpack "n", substr( $respdata, 4 );
    $resplength = $resplength + 10;
    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $transcnt--;

      $getrespflag = 1;

      $response = substr( $respdata, 0, $resplength );
      &updatefdms();
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
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "baccesstime.txt", "write", "", $outfilestr );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $delta      = time() - $temp11;
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt delta: $delta\n\n\n\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );

}

sub updatefdms {
  $rsequencenum = substr( $response, 6, 12 );

  $logfilestr = "";
  $logfilestr .= "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
  $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime   = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$temptime recv: $checkmessage\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );

  $sstatus{"$rsequencenum"} = "done";

  $processid = $sprocessid{"$rsequencenum"};

  &procutils::updateprocmsg( $processid, "fdmsb", "success", "$sinvoicenum{$rsequencenum}", "$response" );

  my $mytime = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime snd success $checktime\n";
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );

  # yyyy

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
  print MAIL "Subject: fdms - no response to authorization\n";
  print MAIL "\n";

  print MAIL "fdms socket is being closed, then reopened because no response was\n\n";
  print MAIL "received to an authorization request.\n";

  close(MAIL);

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  $tmpi      = 0;
  while ( $socketcnt >= 1 ) {
    $tmpi++;
    if ( $tmpi > 4 ) {
      $logfilestr .= "exiting program because socket couldn't be closed\n\n";
      &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
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
  &procutils::filewrite( "$username", "fdms", "/home/pay1/batchfiles/$devprod/fdms", "bserverlogmsg.txt", "append", "", $logfilestr );
}

