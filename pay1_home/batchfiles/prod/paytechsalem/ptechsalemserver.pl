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

$test    = "no";
$devprod = "logs";

if ( -e "/home/pay1/batchfiles/$devprod/paytechsalem/failover.txt" ) {
  exit;
}

$temptime   = time();
$outfilestr = "";
$outfilestr .= "$temptime\n";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "accesstime.txt", "write", "", $outfilestr );

$keepalive   = time();
$getrespflag = 1;
$sequencenum = 0;
$numtrans    = 0;        # used only for throughput checks

$primaryhost = "processor-host";    # Source IP address

## New Salem Host Address
$primaryipaddress = "206.253.180.113";    # primary server

$primaryport = "4558";                    ### Port when routing via IN.

$ipaddress1 = "206.253.184.65";           # secondary server
$port1      = "4623";
$host1      = "$primaryhost";             ### DCP 20100527  Src when routing vi IN

$ipaddress2 = $ipaddress1;                # secondary server
$port2      = $port1;
$host2      = $host1;                     # Source IP address

$testipaddress = "206.253.180.137";       # test server

$testport = "8526";                       # test server	# which one?

$host      = $primaryhost;
$ipaddress = $primaryipaddress;
$port      = $primaryport;

&checksecondary();
&socketopen( "$ipaddress", "$port" );

# delete rows older than 2 minutes
my $now      = time();
my $deltime  = &miscutils::timetostr( $now - 600 );
my $printstr = "deltime: $deltime\n";
&procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

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
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "accesstime.txt", "write", "", $outfilestr );

  if ( ( -e "/home/pay1/batchfiles/$devprod/paytechsalem/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
    close(SOCK);
    exit;
  }

  &check();

  if ( $getrespflag == 0 ) {
    $temptime   = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$temptime    getrespflag = 0, closing socket\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );

    close(SOCK);
    $socketopenflag = 0;
    $getrespflag    = 1;
    &checksecondary();
    &socketopen( "$ipaddress", "$port" );    # primary server
  }

  system("sleep 1");

  $mytime  = time();
  $mydelta = $mytime - $keepalive;
  if ( $mytime - $keepalive >= 130 ) {
    my $printstr = "time - keepalive:  $mytime  $keepalive  $mydelta\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
    &socketread(0);

    if ( ( $mytime - $keepalive >= 370 ) && ( $keepalive > 0 ) ) {
      $temptime   = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$temptime    no heartbeat, closing socket\n";
      &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );

      close(SOCK);
      $socketopenflag = 0;
      $keepalive      = time();
      $getrespflag    = 1;
      &checksecondary();
      &socketopen( "$ipaddress", "$port" );    # primary server
    }
  }
}

exit;

sub check {
  $todayseconds = time();
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - ( 60 * 2 ) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  foreach $key ( keys %writearray ) {
    if ( $writearray{$key} < $ttime1 ) {
      delete $writearray{$key};
    } else {
      $tempfilestr = "";
      $tempfilestr .= "$ttime1 $writearray{$key}\n";
      &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "temp.txt", "append", "", $tempfilestr );
    }
  }

  $timecheckend3   = time();
  $timecheckdelta3 = $timecheckend3 - $timecheckstart3;
  $timecheckstart3 = $timecheckend3;
  if ( $numtrans == 4 ) {
    $tempfilestr = "";
    $tempfilestr .= "$numtrans	writing: $timecheckdelta1	reading: $timecheckdelta2	round trip: $timecheckdelta3\n";
    $numtranscnt++;
    $totaltime = $totaltime + $timecheckdelta3;
    if ( $numtranscnt >= 10 ) {
      $tempstr = sprintf( "Average Round Trip: %.1f", $totaltime / 10 );
      $tempfilestr .= "$tempstr\n";
      $numtranscnt = 0;
      $totaltime   = 0;
    }
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "time.txt", "append", "", $tempfilestr );
  }

  $transcnt            = 0;
  $timecheckfirstflag  = 1;
  $timecheckfirstflag2 = 1;

  # retry
  foreach $rsequencenum ( keys %susername ) {
    $logfilestr = "";
    $logfilestr .= "retry: $sretries{$rsequencenum} $smessagestr{$rsequencenum}\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );
    &socketwrite( $smessage{$rsequencenum} );
    $transcnt++;
  }

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='paytechsalem'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sthmsgvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthmsgvalarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage ) = @sthmsgvalarray[ $vali .. $vali + 4 ];

    if ( ( -e "/home/pay1/batchfiles/$devprod/paytechsalem/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
      close(SOCK);
      sleep 1;
      exit;
    }

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and processor='paytechsalem'
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $username =~ s/[^0-9a-zA-Z_]//g;
    $orderid =~ s/[^0-9]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;

    my $printstr = "processid: $processid\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &procutils::updateprocmsg( $processid, "paytechsalem", "failure", "", "failure: message timeout" );

      next;
    }

    $transcnt++;
    $logfilestr = "";
    $logfilestr .= "transcnt: $transcnt\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );

    %datainfo = ( "username", "$username" );
    my $dbquerystr = <<"dbEOM";
          select username,invoicenum
          from paytechsalem
          where username=?
dbEOM
    my @dbvalues = ("$username");
    ( $chkusername, $invoicenum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $invoicenum = ( $invoicenum % 10000000 ) + 1;

    if ( $chkusername eq "" ) {
      my $dbquerystr = <<"dbEOM";
            insert into paytechsalem 
            (username,invoicenum) 
            values (?,?) 
dbEOM

      my %inserthash = ( "username", "$username", "invoicenum", "$invoicenum" );
      &procutils::dbinsert( $username, $orderid, "pnpmisc", "paytechsalem", %inserthash );

    } else {
      my $dbquerystr = <<"dbEOM";
            update paytechsalem set invoicenum=? 
            where username=? 
dbEOM
      my @dbvalues = ( "$invoicenum", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    }

    $invoicenum = substr( "0" x 8 . $invoicenum,  -8, 8 );
    $invoicenum = substr( $invoicenum . "0" x 22, 0,  22 );
    $sequencenum = $invoicenum;

    $message = substr( $message, 0, 4 ) . $invoicenum . substr( $message, 26 );

    my $printstr = "sequencenum: $sequencenum\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;
    $sinvoicenum{"$sequencenum"} = $sequencenum;

    $cardnum = substr( $message, 28, 19 );
    $cardnum =~ s/[^0-9]//g;
    $xs         = "x" x length($cardnum);
    $messagestr = $message;
    $messagestr =~ s/$cardnum/$xs/g;

    $extradata = substr( $message, 84 );
    $datalen   = length($extradata);
    $dataidx   = 84;
    my $temp   = $extradata;
    my $newidx = 0;
    for ( my $newidx = 0 ; $newidx < $datalen ; ) {
      $tag = substr( $temp, $newidx + 0, 2 );
      if ( $tag eq "EC" ) {
        $taglen = 11;
      } elsif ( $tag eq "AB" ) {
        $taglen = 139;
      } elsif ( $tag eq "FR" ) {
        $taglen = 7;
      } else {
        last;
      }
      if ( $tag eq "FR" ) {
        $cvv = substr( $temp, $newidx + 3, 4 );
        if ( $cvv =~ /[0-9]{3} / ) {
          $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 3 ) . 'xxx ' . substr( $messagestr, $dataidx + $newidx + 3 + 4 );
        } elsif ( $cvv =~ /[0-9]{4}/ ) {
          $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 3 ) . 'xxxx' . substr( $messagestr, $dataidx + $newidx + 3 + 4 );
        }
      }
      $newidx = $newidx + $taglen;
    }

    $cardnumber = $cardnum;

    my $cc = new PlugNPay::CreditCard($cardnumber);
    $shacardnumber = $cc->getCardHash();

    $mytime       = gmtime( time() );
    $checkmessage = $messagestr;
    $checkmessage =~ s/\x1c/\[1c\]/g;
    $checkmessage =~ s/\x1e/\[1e\]/g;
    $checkmessage =~ s/\x0d/\[0d\]/g;
    $logfilestr = "";
    $logfilestr .= "\n$username $orderid\n";
    $logfilestr .= "$mytime send: $checkmessage  $shacardnumber\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );
    $smessagestr{"$sequencenum"} = $checkmessage;

    if ( $timecheckfirstflag == 1 ) {
      $timecheckstart1    = time();
      $timecheckfirstflag = 0;
    }

    $timecheckend1   = time();
    $timecheckdelta1 = $timecheckend1 - $timecheckstart1;

    $getrespflag = 0;
    &socketwrite($message);

    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "accesstime.txt", "write", "", $outfilestr );

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt >= 8 ) {
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
          delete $smessagestr{$rsequencenum};
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

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen attempt $addr $port\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";
  my $printstr = "addr: $addr   port: $port\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

  connect( SOCK, $paddr ) || die "connect: $!";
  my $printstr = "after connect\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

  $socketopenflag = 1;
  $logfilestr     = "";
  $logfilestr .= "socketopen successful\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );
}

sub socketwrite {
  my ($message) = @_;

  if ( $socketopenflag != 1 ) {
    my $printstr = "reopening socket\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
    &checksecondary();
    &socketopen( "$ipaddress", "$port" );    # test server
  }
  if ( $socketopenflag != 1 ) {
    $outfilestr = "";
    $outfilestr .= "dddd\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "temp.txt", "write", "", $outfilestr );
    exit;
  }
  $templen = length($message);
  my $printstr = "send: $templen $message";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
  send( SOCK, $message, 0, $paddr );

}

sub socketread {
  ($numtries) = @_;

  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  my $printstr = "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem",  "miscdebug.txt",    "append", "misc", $printstr );
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "",     $logfilestr );

  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $response = "";
  $respdata = "";
  while ( $count && select( $rout = $rin, undef, undef, 7.0 ) ) {
    $logfilestr = "";
    $logfilestr .= "while\n";
    my $printstr = "while\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem",  "miscdebug.txt",    "append", "misc", $printstr );
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "",     $logfilestr );
    recv( SOCK, $response, 2048, 0 );
    my $printstr = "resp: $response\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

    $respdata = $respdata . $response;

    $resplength = index( $respdata, "\x0d" );
    $resplength = $resplength + 1;

    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    my $printstr = "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem",  "miscdebug.txt",    "append", "misc", $printstr );
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "",     $logfilestr );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $nullresp = substr( $respdata, 0, 3 );
      if ( $nullresp ne "HO1" ) {
        $response     = substr( $respdata, 0, $resplength );
        $rsequencenum = substr( $response, 4, 22 );
        my $printstr = "rsequencenum: $rsequencenum\n";
        &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
        if ( $susername{$rsequencenum} ne "" ) {
          $transcnt--;
          if ( $transcnt == 0 ) {
            $getrespflag = 1;
            $logfilestr  = "";
            $logfilestr .= "getrespflag = 1\n";
            &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );
          }
          &updatepaytech();
          delete $writearray{$rsequencenum};
        }

        if ( !%writearray ) {
          $donereadingflag = 1;
        }
      } else {
        my $printstr = "keepalive\n";
        &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );
        $keepalive = time();
        ( $d1, $d2, $newtime ) = &miscutils::genorderid();
        $newtime = substr( $newtime, 6, 8 );
        $nullmessage = "HI1" . substr( $response, 3, 8 ) . $newtime . "\x0d";
        &socketwrite($nullmessage);
        $mytime     = gmtime( time() );
        $logfilestr = "";
        $logfilestr .= "null message found $mytime\n\n";
        &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );
        $getrespflag = 1;
      }
      $respdata = substr( $respdata, $resplength );

      $resplength = index( $respdata, "\x0d" );
      $resplength = $resplength + 1;
      $rlen       = length($respdata);

      $temptime   = time();
      $outfilestr = "";
      $outfilestr .= "$temptime\n";
      &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "accesstime.txt", "write", "", $outfilestr );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt\n\n\n\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );
  $transcnt = 0;
}

sub updatepaytech {
  $rsequencenum = substr( $response, 4, 22 );

  my $printstr = "recv sequencenum: $rsequencenum, transcnt: $transcnt\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem", "miscdebug.txt", "append", "misc", $printstr );

  $mytime       = gmtime( time() );
  $checkmessage = $response;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/\x1e/\[1e\]/g;
  $checkmessage =~ s/\x0d/\[0d\]/g;
  $checkmessage =~ /[^0-9]([0-9]{15,16}) /g;
  $num = $1;
  $xs  = $num;
  $xs =~ s/[0-9]/x/g;
  $checkmessage =~ s/$num/$xs/;
  $logfilestr = "";
  $logfilestr .= "$mytime recv: $checkmessage\n";
  my $printstr = "recv: $checkmessage\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/devlogs/paytechsalem",  "miscdebug.txt",    "append", "misc", $printstr );
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "",     $logfilestr );

  if ( $timecheckfirstflag2 == 1 ) {
    $timecheckstart2     = time();
    $timecheckfirstflag2 = 0;
  }

  $sstatus{"$rsequencenum"} = "done";

  $processid = $sprocessid{"$rsequencenum"};
  &procutils::updateprocmsg( $processid, "paytechsalem", "success", "$sinvoicenum{$rsequencenum}", "$response" );

  my $mytime = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime snd success $checktime\n";
  &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );

  # yyyy

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $smessagestr{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sprocessid{$rsequencenum};
  delete $sinvoicenum{$rsequencenum};

  $timecheckend2   = time();
  $timecheckdelta2 = $timecheckend2 - $timecheckstart2;

}

sub checksecondary {
  if ( $test eq "yes" ) {

    $ipaddress = "206.253.180.137";    # test server
                                       #$port = "8535";                        # test server
    $port      = "8526";               # test server	# which one?
    $host      = $primaryhost;
  } elsif ( -e "/home/pay1/batchfiles/$devprod/paytechsalem/secondary.txt" ) {
    my @tmpfilestrarray = &procutils::flagread( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "secondary.txt" );
    $secondary = $tmpfilestrarray[0];

    chop $secondary;

    $tmpfilestr = "";
    $tmpfilestr .= "secondary $secondary\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $tmpfilestr );

    my $delta = time() - $manualswitchtime;
    if ( ( ( $secondary eq "1" ) && ( $ipaddress ne $ipaddress1 ) ) || ( ( $secondary eq "2" ) && ( $ipaddress ne $ipaddress2 ) ) ) {
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime switching to secondary socket $secondary\n";
      &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );

      close(SOCK);
      $socketopenflag = 0;
    }

    if ( $secondary eq "1" ) {
      $ipaddress = $ipaddress1;
      $port      = $port1;
      $host      = $host1;
    } elsif ( $secondary eq "2" ) {
      $ipaddress = $ipaddress2;
      $port      = $port2;
      $host      = $host2;
    }
  } elsif ( !( -e "/home/pay1/batchfiles/$devprod/paytechsalem/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) && ( $delta > 3600 ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    $logfilestr .= "$primaryipaddress  $primaryport\n";
    &procutils::filewrite( "$username", "paytechsalem", "/home/pay1/batchfiles/$devprod/paytechsalem", "serverlogmsg.txt", "append", "", $logfilestr );

    $ipaddress = $primaryipaddress;
    $port      = $primaryport;
    $host      = $primaryhost;

    close(SOCK);
    $socketopenflag = 0;
  }
}

