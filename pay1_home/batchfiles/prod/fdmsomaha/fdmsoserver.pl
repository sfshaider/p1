#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use IO::Socket;
use Socket;
use Encode qw(is_utf8 encode decode);
use rsautils;
use PlugNPay::CreditCard;

$test    = "no";
$devprod = "logs";

$host = "processor-host";

# 206.201.52.205 5020 for ZPP1 5021 for ZPP4
# 206.201.59.20 5020 for ZPP0 5021 for ZPP3

$primaryipaddress = "206.201.52.205";    # fdsmoserver

#$primaryipaddress = "206.201.59.20";	# fdsmobserver
$primaryport = "5020";                   # ZPP1 both ports are good

$secondaryipaddress = $primaryipaddress;
$secondaryport      = $primaryport;

$testipaddress = "204.194.126.179";      # test server zpp2
$testport      = "5020";                 # test server

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;

$nullmessage = pack "n", "0000";

# xxxx
if ( $test eq "yes" ) {
  $ipaddress = $testipaddress;           # test server zpp2
  $port      = $testport;                # test server
} elsif ( ( -e "/home/pay1/batchfiles/$devprod/fdmsomaha/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "\n$mytime switching to secondary socket\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $secondaryipaddress;
  $port      = $secondaryport;
} elsif ( !( -e "/home/pay1/batchfiles/$devprod/fdmsomaha/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "\n$mytime switching to primary socket  $ipaddress  $primaryipaddress\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $primaryipaddress;
  $port      = $primaryport;
}

while ( $socketopenflag != 1 ) {
  &socketopen( "$ipaddress", "$port" );
  select undef, undef, undef, 2.00;
}

# delete rows older than 5 minutes
my $now      = time();
my $deltime  = &miscutils::timetostr( $now - 300 );
my $printstr = "deltime: $deltime\n";
&procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "accesstime.txt", "write", "", $outfilestr );

  if ( ( -e "/home/pay1/batchfiles/$devprod/fdmsomaha/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {

    sleep 1;
    exit;
  }

  $keepalivecnt++;
  if ( $keepalivecnt >= 60 ) {
    my $printstr = "keepalivecnt = $keepalivecnt\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
    $keepalivecnt = 0;

    $temptime   = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$temptime send: null message\n\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

    $message = pack "n", "0000";
    &socketwrite($message);
    &socketread($transcnt);

    $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
    if ( $socketcnt < 1 ) {
      my $printstr = "socketcnt < 1\n";
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
      shutdown SOCK, 2;

      $socketopenflag = 0;
      if ( $socketopenflag != 1 ) {
        $sockettmp = `netstat -n | grep $port`;
        ( $d1, $d2, $tmptime ) = &miscutils::genorderid();
        $logfilestr = "";
        $logfilestr .= "No ESTABLISHED $tmptime\n";
        $logfilestr .= "$sockaddrport\n";
        $logfilestr .= "$sockettmp\n\n";
        &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
      }
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }
      $sockettmp  = `netstat -n | grep $port`;
      $logfilestr = "";
      $logfilestr .= "socket reopened\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
    }
  }

  # xxxx
  if ( $test eq "yes" ) {
    $ipaddress = $testipaddress;    # test server zpp2
    $port      = $testport;         # test server
  } elsif ( ( -e "/home/pay1/batchfiles/$devprod/fdmsomaha/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "\n$mytime switching to secondary socket\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

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
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
  } elsif ( !( -e "/home/pay1/batchfiles/$devprod/fdmsomaha/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "\n$mytime switching to primary socket  $ipaddress  $primaryipaddress\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

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
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
  }

  &check();
  if ( $getrespflag == 0 ) {
    $chktcode = substr( $lastmessage, 2, 4 );

    if ( $chktcode ne "AR26" ) {
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime getrespflag = 0, closing socket\n";
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

      &socketclose();
    } else {
      $transcnt--;
    }
  }
  select undef, undef, undef, 1.00;
}

exit;

sub check {
  $todayseconds = time();
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - ( 60 * 2 ) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  if ( ( -e "/home/pay1/batchfiles/$devprod/fdmsomaha/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {

    sleep 1;
    exit;
  }

  foreach $key ( keys %writearray ) {
    if ( $writearray{$key} < $ttime1 ) {
      delete $writearray{$key};
    }

    else {    # debug code
      if ( $transcnt > 0 ) {
        $logfilestr = "";
        $logfilestr .= "bbbb  $key  $writearray{$key}\n";
        &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
      }
    }

  }

  $transcnt = 0;

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='fdmsomaha'
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
          and processor='fdmsomaha'
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $username =~ s/[^0-9a-zA-Z_]//g;
    $orderid =~ s/[^0-9]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;
    $trans_time =~ s/[^0-9]//g;

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &procutils::updateprocmsg( $processid, "fdmsomaha", "failure", "", "failure: message timeout" );
      next;
    }

    $transcnt++;

    %datainfo = ( "username", "$username" );
    my $dbquerystr = <<"dbEOM";
          select username,invoicenum
          from fdmsomaha
          where username='testfdmso'
dbEOM
    my @dbvalues = ();
    ( $chkusername, $invoicenum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $invoicenum = ( $invoicenum % 100000 ) + 1;

    my $dbquerystr = <<"dbEOM";
            update fdmsomaha set invoicenum=?
            where username='testfdmso'
dbEOM
    my @dbvalues = ("$invoicenum");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $sequencenum = sprintf( "%06d", $invoicenum + .0001 );
    my $printstr = "invoicenum: $invoicenum\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );
    $message = substr( $message, 0, 6 ) . $sequencenum . substr( $message, 12 );
    $lastmessage = $message;

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;
    $sinvoicenum{"$sequencenum"} = $invoicenum;

    $cardnum = substr( $message, 52, 16 );
    $cardnum =~ s/[^0-9]//g;
    $mylen      = length($cardnum);
    $messagestr = $message;
    if ( ( $mylen > 12 ) && ( $mylen < 20 ) ) {
      $xs = "x" x $mylen;
      $messagestr =~ s/$cardnum/$xs/g;
    }

    $cvv = substr( $message, 105, 4 );
    if ( $cvv =~ /^[0-9]{3} / ) {
      $messagestr = substr( $messagestr, 0, 105 ) . "xxx " . substr( $messagestr, 93 );
    } elsif ( $cvv =~ /^[0-9]{4}/ ) {
      $messagestr = substr( $messagestr, 0, 105 ) . "xxxx" . substr( $messagestr, 93 );
    }

    $cardnumber = $cardnum;

    my $cc = new PlugNPay::CreditCard($cardnumber);
    $shacardnumber = $cc->getCardHash();

    $logfilestr = "";
    $checkmessage = substr( $messagestr, 0, 2 );
    $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $checkmessage = $checkmessage . substr( $messagestr, 2 );
    $temptime = gmtime( time() );

    $mylen = length($message);
    $logfilestr .= "$username  $orderid\n";
    $logfilestr .= "$temptime send: $mylen $checkmessage  $shacardnumber\n\n";
    $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

    $oldmessage = substr( $message, 2 );

    $newmessage = &encode( "cp1047", $oldmessage );    # posix-bc  cp37  cp1047

    $message = substr( $message, 0, 2 ) . $newmessage;

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "accesstime.txt", "write", "", $outfilestr );

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt > 6 ) {
      last;
    }
  }

  if ( $transcnt > 0 ) {
    $numtrans = $transcnt;
    &socketread($transcnt);

    foreach $rsequencenum ( keys %susername ) {
      $chktcode = substr( $smessage{$rsequencenum}, 2, 4 );
      if ( ( $sstatus{"$rsequencenum"} ne "done" ) && ( $chktcode eq "AR26" ) ) {
        $response = "00AR22" . $rsequencenum . "00000000A";
        &updatefdmsomaha();
      }
      if ( $sstatus{"$rsequencenum"} ne "done" ) {
        $sretries{"$rsequencenum"}++;

        my $now    = time();
        my $mytime = &miscutils::strtotime( $strans_time{$rsequencenum} );
        my $delta  = $now - $mytime;
        if ( $delta > 60 ) {

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

  select undef, undef, undef, 1.00;

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen attempt $addr $port\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

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
    if ( $sockaddrport > 0 ) {
      $socketcnt  = `netstat -an | grep $sockaddrport`;
      $logfilestr = "";
      $logfilestr .= "aaaa $socketcnt\n";
      $logfilestr .= "sockaddrport: $sockaddrport\n";
      $logfilestr .= "socketopen successful\n";
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

      $getrespflag = 1;

      $temptime   = time();
      $outfilestr = "";
      $outfilestr .= "$temptime\n";
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "accesstime.txt", "write", "", $outfilestr );
    } else {
      $socketopenflag = 0;
      select undef, undef, undef, 5.00;
    }
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }
}

sub socketwrite {
  my ($message) = @_;
  my $printstr = "in socketwrite\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );

  if ( $socketopenflag != 1 ) {
    $logfilestr = "";
    $logfilestr .= "socketopenflag = 0, in socketwrite\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
  }
  while ( $socketopenflag != 1 ) {
    &socketopen( "$ipaddress", "$port" );
  }
  send( SOCK, $message, 0, $paddr );

}

sub socketread {
  my ($numtries) = @_;

  my $printstr = "in socketread\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );

  $donereadingflag = 0;

  $logfilestr = "";
  $logfilestr .= "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

  $temp11 = time();
  vec( $rin, fileno(SOCK), 1 ) = 1;

  $count = $numtries + 2;

  $mlen     = length($message);
  $respdata = "";
  $mydelay  = 30.0;
  while ( $count && select( $rout = $rin, undef, undef, $mydelay ) ) {
    my $printstr = "in while\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/devlogs/fdmsomaha", "miscdebug.txt", "append", "misc", $printstr );

    $mydelay = 5.0;

    $logfilestr = "";
    $logfilestr .= "while\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

    recv( SOCK, $response, 2048, 0 );

    $respdata = $respdata . $response;

    $resplength = unpack "n", substr( $respdata, 0 );
    $resplength = $resplength;
    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      ($nullresp) = substr( $respdata, 0, 2 );
      if ( $nullresp eq $nullmessage ) {
        $respdata = substr( $respdata, 2 );

        $mytime     = gmtime( time() );
        $logfilestr = "";
        $logfilestr .= "null message found $mytime\n\n";
        &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

      } else {
        $transcnt--;

        $getrespflag = 1;

        $response = substr( $respdata, 0, $resplength );

        $oldmessage = substr( $response, 2 );

        my $tmpold = unpack "H*", $oldmessage;

        $newmessage = &decode( "cp1047", $oldmessage );    # posix-bc  cp37  cp1047
                                                           #$newmessage = $oldmessage;

        my $tmpnew = unpack "H*", $newmessage;
        $tmpfilestr = "";

        &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $tmpfilestr );

        $response = substr( $response, 0, 2 ) . $newmessage;

        &updatefdmsomaha();
        delete $writearray{$rsequencenum};
        if ( !%writearray ) {
          $donereadingflag = 1;
        }
        $respdata = substr( $respdata, $resplength );
      }
      $resplength = unpack "n", substr( $respdata, 4 );
      $resplength = $resplength + 10;
      $rlen       = length($respdata);

      $temptime   = time();
      $outfilestr = "";
      $outfilestr .= "$temptime\n";
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "accesstime.txt", "write", "", $outfilestr );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $delta      = time() - $temp11;
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime end loop $transcnt delta: $delta\n\n\n\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

}

sub updatefdmsomaha {
  $rsequencenum = substr( $response, 6, 6 );

  $cardnum = substr( $response, 60, 16 );
  $cardnum =~ s/[^0-9]//g;
  $xs         = "x" x length($cardnum);
  $messagestr = $response;
  $messagestr =~ s/$cardnum/$xs/g;

  $logfilestr = "";
  $logfilestr .= "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

  $checkmessage = substr( $messagestr, 0, 2 );
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $checkmessage = $checkmessage . substr( $messagestr, 2 );
  $temptime     = gmtime( time() );
  $logfilestr   = "";
  $logfilestr .= "$temptime recv: $checkmessage\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

  $sstatus{"$rsequencenum"} = "done";

  $processid = $sprocessid{"$rsequencenum"};

  $response = unpack "H*", $response;
  $response = pack "H*", $response;
  &procutils::updateprocmsg( $processid, "fdmsomaha", "success", "", "$response" );

  my $mytime = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime snd success $checktime\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );

  # yyyy
  if ( $sprocessid{"$rsequencenum"} ne "" ) {

    delete $susername{$rsequencenum};
    delete $strans_time{$rsequencenum};
    delete $smessage{$rsequencenum};
    delete $sretries{$rsequencenum};
    delete $sorderid{$rsequencenum};
    delete $sprocessid{$rsequencenum};
    delete $sinvoicenum{$rsequencenum};
  } else {
    $logfilestr = "";
    $logfilestr .= "no processid found for $rsequencenum\n";
    &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
  }

}

sub socketclose {
  $sockettmp  = `netstat -n | grep $port`;
  $logfilestr = "";
  $sockettmp  = `netstat -n | grep $port`;
  ( $d1, $d2, $temp ) = &miscutils::genorderid();
  $logfilestr .= "before socket is closed because of no response $temp\n$sockaddrport\n$sockettmp\n\n";

  shutdown SOCK, 2;

  $socketopenflag = 0;
  $getrespflag    = 1;
  $transcnt       = 0;

  open( MAIL, "| /usr/lib/sendmail -t" );
  print MAIL "To: cprice\@plugnpay.com\n";
  print MAIL "From: dprice\@plugnpay.com\n";
  print MAIL "Subject: fdmsomaha - no response to authorization\n";
  print MAIL "\n";

  print MAIL "fdmsomaha socket is being closed, then reopened because no response was\n\n";
  print MAIL "received to an authorization request.\n";

  close(MAIL);

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  $tmpi      = 0;
  while ( $socketcnt >= 1 ) {
    $tmpi++;
    if ( $tmpi > 4 ) {
      $logfilestr .= "exiting program because socket couldn't be closed\n\n";
      &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
      exit;
    }
    shutdown SOCK, 2;

    select( undef, undef, undef, 0.5 );
    $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  }

  shutdown SOCK, 2;

  $sockettmp = `netstat -n | grep $port`;
  ( $d1, $d2, $temp ) = &miscutils::genorderid();
  $logfilestr .= "socket closed because of no response $temp\n$sockaddrport\n$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsomaha", "/home/pay1/batchfiles/$devprod/fdmsomaha", "serverlogmsg.txt", "append", "", $logfilestr );
}

