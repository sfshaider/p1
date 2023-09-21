#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use IO::Socket;
use Socket;
use PlugNPay::CreditCard;
use rsautils;

$test    = "no";
$devprod = "logs";

if ( -e "/home/pay1/batchfiles/$devprod/paytechtampa2/failover.txt" ) {
  exit;
}

my $logProc = 'paytechtampa2';

$keepalive       = 0;
$getrespflag     = 1;
$mainsequencenum = 0;
$numtrans        = 0;    # used only for throughput checks

$nullmessage = "000000000000";

$primaryhost      = "processor-host";    # Source IP address
$primaryipaddress = "206.253.180.20";    # primary server
$primaryport      = "16100";             # primary server

$secondaryhost      = "processor-host";  # Source IP address
$secondaryipaddress = "206.253.184.20";  # secondary server
$secondaryport      = "16100";           # secondary server

$testhost      = "processor-host";       # test Source IP address
$testipaddress = "206.253.184.250";      # test server
$testport      = "12000";                # test server

#$testport = "14000";			# test server

$host      = $primaryhost;
$ipaddress = $primaryipaddress;
$port      = $primaryport;

&checksecondary();
&socketopen( "$ipaddress", "$port" );

# delete rows older than 5 minutes
my $now     = time();
my $deltime = &miscutils::timetostr( $now - 600 );

my $dbquerystr = <<"dbEOM";
        delete from processormsg
        where trans_time<?
          or trans_time is NULL
          or trans_time=''
dbEOM
my @dbvalues = ("$deltime");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

while (1) {
  $temptime = time();
  my $outfilestr = "";
  $outfilestr .= "$temptime\n";
  my $logData = { 'temptime' => "$temptime", 'msg' => "$outfilestr" };
  # &procutils::filewrite( "ptechserver", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "ptech.txt", "write", "", $outfilestr );
  &procutils::writeDataLog( 'ptechserver', $logProc, "ptech", $logData );

  if ( ( -e "/home/pay1/batchfiles/$devprod/paytechtampa2/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
    close(SOCK);
    sleep 1;
    exit;
  }

  if ( -e "/home/pay1/batchfiles/$devprod/paytechtampa2/failover.txt" ) {
    close(SOCK);
    exit;
  }

  &check();

  if ( $getrespflag == 0 ) {
    $temptime   = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$temptime getrespflag = 0, closing socket\n";
    my $logData = { 'temptime' => "$temptime", 'getrespflag' => "$getrespflag", 'msg' => "$logfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, "serverlogmsg", $logData );

    close(SOCK);
    $socketopenflag = 0;

    system('sleep 1');
    &checksecondary();
    &socketopen( "$ipaddress", "$port" );
    $getrespflag = 1;
  }

  system("sleep 1");
  $keepalive++;

  if ( $keepalive >= 60 ) {
    $message = &networkmessage();

    &decodebitmap($message);

    $checkmessage = $message;
    $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

    $temptime   = gmtime( time() );
    $logfilestr = "";

    $logfilestr .= "$temptime send: null message\n";
    my $logData = { 'temptime' => "$temptime", 'msg' => "$logfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

    $getrespflag = 0;
    &socketwrite($message);

    &socketread(4);
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
      $tempfilestr = "";
      $tempfilestr .= "$ttime1 $writearray{$key}   $key\n";
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "temp.txt", "append", "", $tempfilestr );
      my $logData = { 'ttime1' => "$ttime1", 'key' => "$key", "$key" => $writearray{$key}, 'msg' => "$tempfilestr" };
      &procutils::writeDataLog( $username, $logProc, "temp", $logData );
    }
  }

  $timecheckend3   = time();
  $timecheckdelta3 = $timecheckend3 - $timecheckstart3;
  $timecheckstart3 = $timecheckend3;
  if ( $numtrans == 4 ) {
    $tempfilestr = "";
    $tempfilestr .= "$numtrans	writing: $timecheckdelta1	reading: $timecheckdelta2	round trip: $timecheckdelta3\n";
    $numtranscnt++;
    $totaltime = $totaltime + $timecheckdelta3; # <--- check if we should log totaltime KZ
    if ( $numtranscnt >= 10 ) {
      $tempstr = sprintf( "Average Round Trip: %.1f", $totaltime / 10 );
      $tempfilestr .= "$tempstr\n";
      $numtranscnt = 0;
      $totaltime   = 0;
    }
    my $logData = { 'numtrans' => "$numtrans", 'writing' => "$timecheckdelta1", 'reading' => "$timecheckdelta2", 'roundTrip' => "$timecheckdelta3", 'averageRoundTrip' => $totaltime / 10, 'msg' => "$tempfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "time.txt", "append", "", $tempfilestr );
    &procutils::writeDataLog( $username, $logProc, "time", $logData );
  }

  $transcnt            = 0;
  $timecheckfirstflag  = 1;
  $timecheckfirstflag2 = 1;

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='paytechtampa2'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sthmsgvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthmsgvalarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage ) = @sthmsgvalarray[ $vali .. $vali + 4 ];

    if ( ( -e "/home/pay1/batchfiles/$devprod/paytechtampa2/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
      close(SOCK);
      sleep 1;
      exit;
    }

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    my $temptime   = gmtime( time() );
    my $logfilestr = "";
    $logfilestr .= "\naaaa $temptime $username $orderid select from processormsg\n";

    my $logData = { 'temptime' => "$temptime", 'username' => "$username", 'orderid' => "$orderid", 'msg' => "$logfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, "serverlogmsg", $logData );

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and processor='paytechtampa2'
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $username =~ s/[^0-9a-zA-Z_]//g;
    $trans_time =~ s/[^0-9]//g;
    $orderid =~ s/[^0-9]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &procutils::updateprocmsg( $processid, "paytechtampa2", "failure", "", "failure: message timeout" );

      next;
    }

    $transcnt++;

    $mainsequencenum = ( $mainsequencenum % 999998 ) + 1;
    $sequencenum = substr( "0" x 12 . $mainsequencenum, -12, 12 );

    ($idx) = &decodebitmap( $message, 37 );

    if ( $message =~ /^.{26}14(0|2)0/ ) {
      $sequencenum = substr( $message, $idx, 12 );
    } else {
      $message = substr( $message, 0, $idx ) . $sequencenum . substr( $message, $idx + 12 );
    }

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $svoidflag{$sequencenum}     = 0;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;

    &decodebitmap($message);
    $mid     = $msgvalues[42];
    $tid     = $msgvalues[41];
    $cardnum = $msgvalues[2];

    $messagestr = $message;

    if ( $msgvalues[2] ne "" ) {
      $cardnum    = $msgvalues[2];
      $cardnumidx = $msgvaluesidx[2];
      $cardnum =~ s/[^0-9]//g;
      $cardnumlen = length($cardnum);
      $xs         = "x" x $cardnumlen;
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $message, 0, $cardnumidx ) . $xs . substr( $message, $cardnumidx + $cardnumlen );
      }
    }
    if ( $msgvalues[45] ne "" ) {    # track 1
      $cardnum    = $msgvalues[45];
      $cardnumidx = $msgvaluesidx[45];
      $cardnumlen = length($cardnum);
      $xs         = "x" x $cardnumlen;
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $messagestr, 0, $cardnumidx ) . $xs . substr( $messagestr, $cardnumidx + $cardnumlen );
      }
      $cardnum =~ s/^.//;
      ($cardnum) = split( /\^/, $cardnum );
    } elsif ( $msgvalues[35] ne "" ) {    # track 2
      $cardnum    = $msgvalues[35];
      $cardnumidx = $msgvaluesidx[35];
      $cardnumlen = length($cardnum);
      $xs         = "x" x $cardnumlen;
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $messagestr, 0, $cardnumidx ) . $xs . substr( $messagestr, $cardnumidx + $cardnumlen );
      }
      ($cardnum) = split( /=/, $cardnum );
    }

    if ( $msgvalues[48] ne "" ) {         # cvv data
      $datalen = length( $msgvalues[48] );
      $dataidx = $msgvaluesidx[48];
      my $temp   = $msgvalues[48];
      my $newidx = 0;
      for ( my $newidx = 0 ; $newidx < $datalen ; ) {
        my $tag     = substr( $temp, $newidx + 0, 2 );
        my $taglen  = substr( $temp, $newidx + 2, 2 );
        my $tagdata = substr( $temp, $newidx + 4, $taglen );
        if ( $tag eq "C1" ) {
          $cvv = $tagdata;
          if ( $taglen == 3 ) {
            $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 4 ) . 'xxx' . substr( $messagestr, $dataidx + $newidx + 4 + 3 );
          } elsif ( $taglen == 4 ) {
            $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 4 ) . 'xxxx' . substr( $messagestr, $dataidx + $newidx + 4 + 4 );
          }
        }
        $newidx = $newidx + 4 + $taglen;
      }
    }

    $cardnum =~ s/ //g;

    $cardnumber = $cardnum;
    my $cc = new PlugNPay::CreditCard($cardnumber);
    $shacardnumber = $cc->getCardHash();

    $checkmessage = $messagestr;
    $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $temptime   = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "\n$username $orderid\n";
    $logfilestr .= "$temptime send: $checkmessage  $shacardnumber\n";

    my $logData = { 'username' => "$username", 'orderid' => "$orderid", 'temptime' => "$temptime", 'checkmessage' => "$checkmessage", 'shacardnumber' => "$shacardnumber", 'msg' => "$logfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

    if ( $timecheckfirstflag == 1 ) {
      $timecheckstart1    = time();
      $timecheckfirstflag = 0;
    }

    $logfilestr = "";
    $temptime   = gmtime( time() );
    $logfilestr .= "$temptime sequencenum: $sequencenum retries: $retries\n";
    my $logData = { 'temptime' => "$temptime", 'sequencenum' => "$sequencenum", 'retries' => "$retries", 'msg' => "$logfilestr"};
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

    $timecheckend1   = time();
    $timecheckdelta1 = $timecheckend1 - $timecheckstart1;

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $logfilestr = "";
    $temptime   = gmtime( time() );
    $logfilestr .= "$temptime before flagwrite\n";
    my $logData = { 'temptime' => "$temptime", 'msg' => "$logfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    my $logData = { 'temptime' => "$temptime", 'msg' => "$outfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "ptech.txt", "write", "", $outfilestr );
    &procutils::writeDataLog( $username, $logProc, 'ptech', $logData );

    $logfilestr = "";
    $temptime   = gmtime( time() );
    $logfilestr .= "$temptime after flagwrite\n";
    my $logData = { 'temptime' => "$temptime", 'msg' => "$logfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt >= 8 ) {
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
      if ( $delta > 40 ) {
        my $tmpstr = substr( $smessage{$rsequencenum}, 6 );

        if ( ( $delta < 240 ) && ( $tmpstr =~ /^[LK].{19}1[12]/ ) ) {    # void all messages
          $message = &voidmessage( $smessage{$rsequencenum} );
          $svoidflag{$rsequencenum} = 1;

          &decodebitmap($message);

          $checkmessage = $message;
          $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
          $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
          $temptime   = gmtime( time() );
          $logfilestr = "";
          $logfilestr .= "\nvoid message\n";
          $logfilestr .= "$temptime send: $checkmessage\n";
          my $logData = { 'temptime' => "$temptime", 'checkmessage' => "$checkmessage", 'msg' => "$logfilestr" };
          # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
          &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

          $transcnt++;
          &socketwrite($message);
          &socketread(4);
          $keepalive = 0;
        } else {
          delete $susername{$rsequencenum};
          delete $strans_time{$rsequencenum};
          delete $smessage{$rsequencenum};
          delete $svoidflag{$rsequencenum};
          delete $sretries{$rsequencenum};
          delete $sorderid{$rsequencenum};
          delete $sprocessid{$rsequencenum};
        }
      }
    }
  }

}

sub socketopen {
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  $logfilestr = "";
  $logfilestr .= "socketopen attempt $addr\n";
  my $logData = { 'addr' => "$addr",'msg' => "$logfilestr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  connect( SOCK, $paddr ) || &socketopen2( $secondaryipaddress, $secondaryport, $secondaryhost, "connect: $!" );

  $sockaddr    = getsockname(SOCK);
  $sockaddrlen = length($sockaddr);
  if ( $sockaddrlen == 16 ) {
    ($sockaddrport) = unpack_sockaddr_in($sockaddr);
  }

  $logfilestr = "";
  $logfilestr .= "socketopen successful\n";
  my $logData = { 'msg' => "$logfilestr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  $socketopenflag = 1;
}

sub socketopen2 {
  my ( $addr, $port, $host, $errmsg ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  $logfilestr = "";
  $logfilestr .= "socketopen failed  $errmsg\n";
  $logfilestr .= "socketopen attempt secondary $addr\n";
  my $logData = { 'errmsg' => "$errmsg", 'addr' => "$addr", 'msg' => "$logfilestr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  connect( SOCK, $paddr ) || &printerror("connect: $!");

  $logfilestr = "";
  $logfilestr .= "socketopen successful secondary\n";
  my $logData = { 'msg' => "$logfilestr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  $socketopenflag = 1;
}

sub printerror {
  my ($errmsg) = @_;

  $logfilestr = "";
  $logfilestr .= "socketopen failed secondary  $errmsg\n";
  my $logData = { 'errmsg' => "$errmsg", 'msg' => "$logfilestr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  die "connect: $!";
}

sub socketwrite {
  my ($message) = @_;

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  if ( $socketcnt < 1 ) {
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
      my $logData = { 'tmptime' => "$tmptime", 'sockaddrport' => "$sockaddrport", 'sockettmp' => "$sockettmp", 'msg' => "$logfilestr" };
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
      &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
    }
  }

  if ( $socketopenflag != 1 ) {
    &checksecondary();
    &socketopen( "$ipaddress", "$port" );
  }
  if ( $socketopenflag != 1 ) {
    my $outfilestr = "";
    $outfilestr .= "socket closed, exiting\n";
    my $logData = { 'msg' => "$outfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "write", "", $outfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
    exit;
  }

  send( SOCK, $message, 0, $paddr );

}

sub socketread {
  ($numtries) = @_;

  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  my $logData = { 'transcnt' => "$transcnt", 'msg' => "$logfilestr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $response = "";
  $respdata = "";
  &miscutils::mysleep(1);
  my $mydelay = 20.0;
  while ( $count && select( $rout = $rin, undef, undef, $mydelay ) ) {
    $mydelay    = 1.0;
    $logfilestr = "";
    $logfilestr .= "in while\n";
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );

    recv( SOCK, $response, 2048, 0 );

    $respdata = $respdata . $response;

    $resplength = unpack "n", $respdata;
    $resplength = $resplength + 6;
    $rlen       = length($respdata);
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    my $logData = { 'rlen' => "$rlen", 'resplength' => "$resplength", 'msg' => "$logfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      ($nullresp) = substr( $respdata, 0, 40 );
      if ( $nullresp !~ /PTIISOYN          1810/ ) {
        $transcnt--;
        $getrespflag = 1;
        $response = substr( $respdata, 0, $resplength );
        &updatepaytech();

        delete $writearray{$rsequencenum};
        if ( !%writearray ) {
          $donereadingflag = 1;
        } elsif ( $transcnt == 0 ) {
          foreach $key ( keys %writearray ) {
            my $tempfilestr = "";
            $tempfilestr .= "ffff $key  $writearray{$key}\n";
            my $logData = { 'key' => "$key", "$key" => $writearray{$key}, 'msg' => "$tempfilestr" };
            # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $tempfilestr );
            &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
          }
        }
      } else {
        $getrespflag = 1;

        $temptime   = gmtime( time() );
        $logfilestr = "";
        $logfilestr .= "$temptime null message found\n\n";
        my $logData = { 'temptime' => "$temptime", 'msg' => "$logfilestr" };
        # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
        &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
      }
      $respdata = substr( $respdata, $resplength );

      $resplength = unpack "n", $respdata;
      $resplength = $resplength + 6;
      $rlen       = length($respdata);

      $temptime = time();
      my $outfilestr = "";
      $outfilestr .= "$temptime\n";
      my $logData = { 'temptime' => "$temptime", 'msg' => "$outfilestr" };
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "ptech.txt", "write", "", $outfilestr );
      &procutils::writeDataLog( $username, $logProc, 'ptech', $logData );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      my $logData = { 'donereadingflag' => "$donereadingflag", 'msg' => "$logfilestr" };
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
      &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
      last;
    }

    $count--;
  }
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt\n\n\n\n";
  my $logData = { 'transcnt' => "$transcnt", 'msg' => "$logfilestr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

}

sub updatepaytech {
  ($idx) = &decodebitmap( $response, 37 );

  $rsequencenum = substr( $response, $idx, 12 );

  &decodebitmap($response);

  $logfilestr = "";
  $logfilestr .= "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  

  $checkmessage = $response;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime   = gmtime( time() );
  $logfilestr .= "$temptime recv: $checkmessage\n";
  my $logData = { 'temptime' => "$temptime", 'sequencenum' => "$sequencenum", 'transcnt' => "$transcnt", 'checkmessage' => "$checkmessage", 'msg' => "$logfilestr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  my $tmpstr = substr( $response, 26, 4 );
  if ( $response =~ /^.{26}1810/ ) {
    my $printstr = "network message found\n";
    my $logData = { 'msg' => "$printstr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "serverlogmsg.txt", "append", "misc", $printstr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
    return;
  }
  if ( $response =~ /^.{26}0000/ ) {
    my $printstr = "0000 message found\n";
    my $logData = { 'msg' => "$printstr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "serverlogmsg.txt", "append", "misc", $printstr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
    return;
  }
  if ( $response =~ /^.{26}1430/ ) {
    my $printstr = "void response found\n";
    my $logData = { 'msg' => "$printstr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "serverlogmsg.txt", "append", "misc", $printstr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
  }
  if ( ( $svoidflag{$rsequencenum} == 1 ) && ( $response =~ /^.{26}1[12]/ ) ) {

    $logfilestr = "$tmpstr  auth response to voided message, discarded\n";
    my $logData = { '$tmpstr' => "$tmpstr", 'msg' => "$logfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
    return;
  }

  if ( $timecheckfirstflag2 == 1 ) {
    $timecheckstart2     = time();
    $timecheckfirstflag2 = 0;
  }

  $sstatus{"$rsequencenum"} = "done";

  $processid = $sprocessid{"$rsequencenum"};
  &procutils::updateprocmsg( $processid, "paytechtampa2", "success", "$sinvoicenum{$rsequencenum}", "$response" );

  my $mytime = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime snd success $checktime\n";
  my $logData = { 'mytime' => "$mytime", 'checktime' => "$checktime", 'msg' => "$logfilestr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  # yyyy

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $svoidflag{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sprocessid{$rsequencenum};

  $timecheckend2   = time();
  $timecheckdelta2 = $timecheckend2 - $timecheckstart2;

}

sub decodebitmap {
  my ( $message, $findbit ) = @_;

  $bitlenarray[2]  = "LLVAR";
  $bitlenarray[3]  = 6;
  $bitlenarray[4]  = 12;
  $bitlenarray[7]  = 14;
  $bitlenarray[8]  = 12;
  $bitlenarray[11] = 6;
  $bitlenarray[12] = 6;
  $bitlenarray[13] = 8;
  $bitlenarray[14] = 4;
  $bitlenarray[18] = 4;
  $bitlenarray[22] = 3;
  $bitlenarray[25] = 2;
  $bitlenarray[35] = "LLVAR";
  $bitlenarray[37] = 12;
  $bitlenarray[38] = 6;
  $bitlenarray[39] = 2;
  $bitlenarray[41] = 3;
  $bitlenarray[42] = 12;
  $bitlenarray[45] = "LLVAR";
  $bitlenarray[48] = "LLLVAR";
  $bitlenarray[49] = 3;
  $bitlenarray[54] = 12;
  $bitlenarray[60] = "LLLVAR";
  $bitlenarray[62] = "LLLVAR";
  $bitlenarray[63] = "LLLVAR";
  $bitlenarray[64] = "LLLVAR";
  $bitlenarray[70] = 3;
  $bitlenarray[90] = 46;

  my $idxstart = 30;                            # bitmap start point
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

  @msgvalues = ();
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
      if ( $bitnum == 64 ) {
        last;
      }

      my $tempstr = substr( $message, $idx, 8 );
      $tempstr = unpack "H*", $tempstr;

      my $idxlen = $bitlenarray[ $bitnum - 1 ];
      if ( $idxlen eq "LLVAR" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idx = $idx + 2;
      } elsif ( $idxlen eq "LLLVAR" ) {
        $idxlen = substr( $message, $idx, 3 );
        $idx = $idx + 3;
      }
      my $value = substr( $message, $idx, $idxlen );
      $tmpbit = $bitnum - 1;

      $msgvalues[$tmpbit]    = "$value";
      $msgvaluesidx[$tmpbit] = $idx;

      $myk++;
      if ( $myk > 30 ) {
        my $logfilestr = "";
        $logfilestr .= "myk > 30\n";
        my $logData = { 'msg' => "$logfilestr" };
        # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
        &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );
        exit;
      }
      if ( ( $findbit ne "" ) && ( $findbit == $bitnum - 1 ) ) {
        return $idx, $value;
      }
      $idx = $idx + $idxlen;
    }
    $bigbitmaphalf = $bitmap2;
  }    # end for

  my $tempstr = unpack "H*", $message;

  for ( my $i = 0 ; $i <= $#msgvalues ; $i++ ) {
    if ( $msgvalues[$i] ne "" ) {
      if ( ( $i == 2 ) || ( $i == 35 ) || ( $i == 45 ) ) {
        my $tmpval = $msgvalues[$i];
      } elsif ( $i == 120 ) {
        my $data    = $msgvalues[$i];
        my $datalen = length($data);
        for ( my $newidx = 0 ; $newidx < $datalen ; ) {
          my $tag = substr( $data, $newidx + 0, 2 );
          my $taglen = 0;
          if ( $tag eq "AV" ) {
            $taglen = 29;
          } elsif ( $tag eq "C2" ) {
            $taglen = 8;
          } else {
            last;
          }
          my $tagdata = substr( $data, $newidx + 2, $taglen );
          if ( $tag eq "C2" ) {
            $cvv = $tagdata;
          }
          $newidx = $newidx + 2 + $taglen;
        }
      }
    }
  }

  return -1, "";
}

sub voidmessage {
  my ($message) = @_;

  my $routingind = substr( $message, 6, 1 );

  my $printstr = "in voidmessage\n";
  my $logData = { 'msg' => "$printstr" };
  # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/devlogs/paytechtampa2", "serverlogmsg.txt", "append", "misc", $printstr );
  &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

  $time = time();
  local ( $sec,  $min,  $hour,  $day,  $month,  $year,  $wday, $yday, $isdst ) = gmtime($time);
  local ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime($time);

  &decodebitmap($message);

  @transaction = ();

  $data            = $msgvalues[2];
  $datalen         = length($data);
  $datalen         = substr( "00" . $datalen, -2, 2 );
  $transaction[2]  = "$datalen$data";
  $transaction[3]  = $msgvalues[3];
  $transaction[4]  = $msgvalues[4];
  $transaction[12] = $msgvalues[12];
  $transaction[13] = $msgvalues[13];

  if ( $msgvalues[14] eq "" ) {
    if ( $msgvalues[35] ne "" ) {
      my ( $val1, $val2 ) = split( /=/, $msgvalues[35] );
      my $month = substr( $val2, 2, 2 );
      my $year  = substr( $val2, 0, 2 );
      $transaction[14] = $year . $month;
    } elsif ( $msgvalues[45] ne "" ) {
      my ( $val1, $val2, $val3 ) = split( /\^/, $msgvalues[45] );
      my $month = substr( $val3, 2, 2 );
      my $year  = substr( $val3, 0, 2 );
      $transaction[14] = $year . $month;
    }
  } else {
    $transaction[14] = $msgvalues[14];
  }

  my $posentry = $msgvalues[22];
  if ( $posentry eq "902" ) {
    $posentry = "012";
  }
  $transaction[22] = $posentry;
  $transaction[25] = $msgvalues[25];
  $transaction[37] = $msgvalues[37];
  $transaction[41] = $msgvalues[41];
  $transaction[42] = $msgvalues[42];

  $dataentry = "D10202";

  $data            = $msgvalues[48];
  $data            = $data . $dataentry . "R3010";        # reversal reason code
  $datalen         = length($data);
  $datalen         = substr( "000" . $datalen, -3, 3 );
  $transaction[48] = "$datalen$data";

  $data            = $msgvalues[60];
  $datalen         = length($data);
  $datalen         = substr( "000" . $datalen, -3, 3 );
  $transaction[60] = "$datalen$data";

  $data    = $msgvalues[62];
  $datalen = length($data);
  if ( $datalen > 0 ) {
    $datalen = substr( "000" . $datalen, -3, 3 );
    $transaction[62] = "$datalen$data";
  }

  $origmesstype = substr( $message, 26, 4 );

  if ( $origmesstype eq "1100" ) {
    my $addtldata = "";

    $origmesstype = substr( $origmesstype . " " x 4, 0, 4 );
    $addtldata = "$origmesstype" . "        " . "000000000000" . " " x 22;

    if ( $addtldata ne "" ) {
      $transaction[90] = "$addtldata";    # orig data elements (LLLVAR) 90
    }
  }

  my $message = "";

  foreach $var (@transaction) {
    $message = $message . $var;
  }

  my ( $bitmap1, $bitmap2 ) = &generatebitmap(@transaction);

  $bitmap1 = pack "H16", $bitmap1;
  if ( $bitmap2 ne "" ) {
    $bitmap2 = pack "H16", $bitmap2;
  }

  $message = '1420' . $bitmap1 . $bitmap2 . $message;

  if ( $routingind eq "L" ) {
    $header = "L.PTIISOYN          ";
  } else {
    $header = "K.PTIISOYN          ";
  }

  $message = $header . $message;
  $len     = length($message);
  $len     = pack "n", $len;
  my $zero = pack "H2", "00";
  $message = $len . ( $zero x 4 ) . $message;

  return $message;
}

sub networkmessage {
  @transaction = ();
  $transaction[0] = '1800';    # message id (4n)
  $transaction[1] = pack "H16", "8018000008C00004";    # primary bit map (8n)
  $transaction[2] = pack "H16", "0400000000000000";    # secondary bit map (8n) 1

  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  my $ltrandate = sprintf( "%02d%02d%04d", $lmonth + 1, $lday, $lyear + 1900 );
  my $ltrantime = sprintf( "%02d%02d%02d", $lhour,      $lmin, $lsec );
  $transaction[3] = $ltrantime . $ltrandate;           # transmission date/time hhmmssMMDDYYYY (10n) 12, 13

  $mainsequencenum = ( $mainsequencenum % 999998 ) + 1;
  $sequencenum     = substr( "0" x 12 . $mainsequencenum, -12, 12 );
  $transaction[4]  = $sequencenum;                                     # retrieval reference number (12a) 37

  $tid = substr( $tid . " " x 3, 0, 3 );
  if ( $tid eq "   " ) {
    $tid = "001";
  }
  $transaction[5] = $tid;                                              # card acceptor terminal id (3a) 41

  if ( $mid eq "" ) {
    $mid = "700000000064";
  }
  $mid = substr( $mid . " " x 12, 0, 12 );
  $transaction[6] = $mid;                                              # card acceptor id code - terminal/merchant id (12a) 42

  my $addtldata = "";
  $addtldata = $addtldata . "T1026DIRLINK   042513VERSION3.4";

  my $len = length($addtldata);
  $len = substr( "000" . $len, -3, 3 );
  $transaction[7] = "$len$addtldata";                                  # reserved private data (LLLVAR) 62

  $transaction[8] = '301';                                             # network management code (3n) 70

  my $message = "";
  foreach $var (@transaction) {
    $message = $message . $var;
  }

  $header  = "K.PTIISOYN          ";
  $message = $header . $message;
  $len     = length($message);
  $len     = pack "n", $len;
  my $zero = pack "H2", "00";
  $message = $len . ( $zero x 4 ) . $message;

  return $message;
}

sub checksecondary {
  my @tmpfilestrarray = &procutils::fileread( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "secondary.txt" );
  $secondary = $tmpfilestrarray[0];

  if ( $test eq "yes" ) {
    $ipaddress = $testipaddress;    # test server
    $port      = $testport;         # test server
    $host      = $testhost;
  } elsif ( ( -e "/home/pay1/batchfiles/$devprod/paytechtampa2/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
    $tmpfilestr = "";
    $tmpfilestr .= "secondary $secondary\n";
    my $logData = { 'secondary' => "$secondary", 'msg' => "$tmpfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $tmpfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

    my $delta = time() - $manualswitchtime;
    if ( $ipaddress ne $secondaryipaddress ) {
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime switching to secondary socket $secondary\n";
      my $logData = { 'mytime' => "$mytime", 'secondary' => "$secondary", 'msg' => "$logfilestr" };
      # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
      &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

      close(SOCK);
      $socketopenflag = 0;
    }

    $ipaddress = $secondaryipaddress;
    $port      = $secondaryport;
    $host      = $secondaryhost;
  } elsif ( ( $secondary eq "" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    $logfilestr .= "$primaryipaddress  $primaryport\n";
    my $logData = { 'mytime' => "$mytime", 'primaryipaddress' => "$primaryipaddress", 'primaryport' => "$primaryport", 'msg' => "$logfilestr" };
    # &procutils::filewrite( "$username", "paytechtampa2", "/home/pay1/batchfiles/$devprod/paytechtampa2", "serverlogmsg.txt", "append", "", $logfilestr );
    &procutils::writeDataLog( $username, $logProc, 'serverlogmsg', $logData );

    $ipaddress = $primaryipaddress;
    $port      = $primaryport;
    $host      = $primaryhost;

    close(SOCK);
    $socketopenflag = 0;
  }
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

  return $bitmap1, $bitmap2;
}