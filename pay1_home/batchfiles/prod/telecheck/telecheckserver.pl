#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use IO::Socket;
use Socket;

#require 'sys/ipc.ph';
#require 'sys/msg.ph';
use rsautils;
use PlugNPay::CreditCard;

$test    = "no";
$devprod = "logs";

$host = "processor-host";    # Source IP address

$testipaddress = "204.194.128.17";    # test server

#$testipaddress = "204.194.128.18";  	# cert server
#$testport = "28315";			# face to face
$testport = "28316";    # non face to face

$primaryipaddress = "204.194.126.19";    # primary production server AZ

#$primaryport = "28315";			# primary production server face to face
$primaryport = "28316";                  # primary production server

$secondaryipaddress = "204.194.128.115"; # secondary production server NE

#$secondaryport = "28315";		# secondary production server face to face
$secondaryport = "28316";                # secondary production server

#$ipaddress = $secondaryipaddress;
#$port = $secondaryport;

$keepalive   = 0;
$respflag    = 1;
$getrespflag = 1;
$sequencenum = 0;

$nullmessage1 = "NB0015HART_BEAT";
$nullmessage2 = "0004ECHO";

# xxxx
if ( $test eq "yes" ) {
  $ipaddress = $testipaddress;    # test server
  $port      = $testport;         # test server
} elsif ( ( -e "/home/pay1/batchfiles/$devprod/telecheck/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to secondary socket\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $secondaryipaddress;
  $port      = $secondaryport;
} elsif ( !( -e "/home/pay1/batchfiles/$devprod/telecheck/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to primary socket\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $primaryipaddress;
  $port      = $primaryport;
}

while ( $socketopenflag != 1 ) {
  &socketopenalarm();

  #&socketopen("$ipaddress","$port");
}
&socketread("");

# delete rows older than 2 minutes
my $now      = time();
my $deltime  = &miscutils::timetostr( $now - 120 );
my $printstr = "deltime: $deltime\n";
&procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

my $dbquerystr = <<"dbEOM";
        delete from processormsg
        where trans_time<?
          or trans_time is NULL
          or trans_time=''
dbEOM
my @dbvalues = ("$deltime");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

$temptime   = time();
$outfilestr = "";
$outfilestr .= "$temptime\n";
&procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "accesstime.txt", "write", "", $outfilestr );

while (1) {
  $temptime   = time();
  $outfilestr = "";
  $outfilestr .= "$temptime\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "accesstime.txt", "write", "", $outfilestr );

  if ( ( -e "/home/pay1/batchfiles/$devprod/telecheck/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {

    sleep 1;
    exit;
  }

  # xxxx
  if (0) {
    if ( $test eq "yes" ) {
      $ipaddress = $testipaddress;    # test server
      $port      = $testport;         # test server
    } elsif ( ( -e "/home/pay1/batchfiles/$devprod/telecheck/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime switching to secondary socket\n";
      &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );

      $socketopenflag = 0;
      $ipaddress      = $secondaryipaddress;
      $port           = $secondaryport;
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime secondary socket opened\n";
      &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );
    } elsif ( !( -e "/home/pay1/batchfiles/$devprod/telecheck/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime switching to primary socket\n";
      &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );

      $socketopenflag = 0;
      $ipaddress      = $primaryipaddress;
      $port           = $primaryport;
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime primary socket opened\n";
      &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );
    }
  }

  &check();
  if ( $getrespflag == 0 ) {
    $logfilestr = "";
    my ( $d1, $d2, $temp ) = &miscutils::genorderid();
    $logfilestr .= "before socket is closed because of no response $temp\n\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );

    $getrespflag = 1;
  }
  select( undef, undef, undef, 1.0 );
  $keepalive++;

  # xxxx temporary, while the dialup connection is used
  #if ($keepalive >= 30) {
  #  close(SOCK);
  #  $socketopenflag = 0;
  #  $keepalive = 0;
  #}

  $keepalivecnt++;
  if ( $keepalivecnt >= 120 ) {
    $keepalivecnt = 0;

    $message = "0004ECHO";
    my $printstr = "keepalive\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
    &socketwrite($message);
    &socketread(1);
  }
}

sub check {
  $todayseconds = time();
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - ( 60 * 2 ) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  if ( ( -e "/home/pay1/batchfiles/$devprod/telecheck/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {

    sleep 1;
    exit;
  }

  foreach $key ( keys %writearray ) {
    if ( $writearray{$key} < $ttime1 ) {
      delete $writearray{$key};
    } else {

      #open(tempfile,">>/home/pay1/batchfiles/$devprod/telecheck/temp.txt");
      #print tempfile "$ttime1 delete $writearray{$key}\n";
      #close(tempfile);
    }
  }

  #&timecheck("before selecting");
  $timecheckend3   = time();
  $timecheckdelta3 = $timecheckend3 - $timecheckstart3;
  $timecheckstart3 = $timecheckend3;
  if ( $numtrans == 4 ) {
    $tempfilestr = "";
    $tempfilestr .= "$numtrans   writing: $timecheckdelta1       reading: $timecheckdelta2       round trip: $timecheckdelta3\n";
    $numtranscnt++;
    $totaltime = $totaltime + $timecheckdelta3;
    if ( $numtranscnt >= 10 ) {
      $tempstr = sprintf( "Average Round Trip: %.1f", $totaltime / 10 );
      $tempfilestr .= "$tempstr\n";
      $numtranscnt = 0;
      $totaltime   = 0;
    }
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "time.txt", "append", "", $tempfilestr );
  }

  $transcnt            = 0;
  $timecheckfirstflag  = 1;
  $timecheckfirstflag2 = 1;

  # retry
  #foreach $rsequencenum (keys %susername) {
  #  &logfile("retry: $sretries{$rsequencenum} $smessage{$rsequencenum}\n");
  #  &socketwrite($smessage{$rsequencenum});
  #  $transcnt++;
  #}

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='telecheck'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sth1valarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sth1valarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage ) = @sth1valarray[ $vali .. $vali + 4 ];

    #while (1) {}
    #print "msgrcv: $trans_time $processid $username $orderid $message\n";

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and status='pending'
          and orderid=?
dbEOM
    my @dbvalues = ( "$processid", "$orderid" );
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $username =~ s/[^a-zA-Z_0-9]//g;
    $orderid =~ s/[^0-9]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;

    my $printstr = "type: $type\n";
    $printstr .= "processid: $processid\n";
    $printstr .= "username: $username\n";
    $printstr .= "orderid: $orderid\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

    #print "trans_time: $trans_time\n";
    #print "message: $message\n";

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &procutils::updateprocmsg( $processid, "telecheck", "failure", "", "failure: message timeout" );

    }

    #&timecheck("get next valid orderid");

    $transcnt++;
    &logfile("transcnt: $transcnt\n");

    #$sequencenum = ($sequencenum % 9998) + 1;
    #$sequencenum = substr("0000" . $sequencenum,-4,4);
    # zzzz
    #$message = substr($message,0,49) . $sequencenum . substr($message,53);
    #$message = substr($message,0,55) . $sequencenum . substr($message,59);
    $sequencenum = $orderid;
    my $printstr = "seq: $sequencenum pid: $processid\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

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

    &logfile("sequencenum: $sequencenum retries: $retries\n");

    $timecheckend1   = time();
    $timecheckdelta1 = $timecheckend1 - $timecheckstart1;

    $getrespflag = 0;
    &socketwrite($message);
    if ( $response eq "" ) {
      $respflag = 0;
    } else {
      $respflag = 1;
    }

    if ( ( $response eq "" ) && ( $retries == 2 ) ) {
      $response = "failure";
    }

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "accesstime.txt", "write", "", $outfilestr );

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
          delete $sretries{$rsequencenum};
          delete $sorderid{$rsequencenum};
          delete $sprocessid{$rsequencenum};
        }
      }
    }
  }

}

sub socketopenalarm {
  eval {
    local ( $SIG{ALRM} ) = sub { &switchports(); &socketopen( "$ipaddress", "$port" ) };

    alarm 20;

    &socketopen( "$ipaddress", "$port" );

    alarm 0;
  };
  if ($@) {
    return "failure";
  }

  if ( $socketopenflag == 0 ) {
    &switchports();
    &socketopen( "$ipaddress", "$port" );
  }
}

sub switchports {

  # xxxx
  if ( $test eq "yes" ) {
    $ipaddress = $testipaddress;    # test server
    $port      = $testport;         # test server
  } elsif ( $ipaddress ne $secondaryipaddress ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to secondary socket\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );
    $ipaddress = $secondaryipaddress;
    $port      = $secondaryport;
  } elsif ( $ipaddress ne $primaryipaddress ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );
    $ipaddress = $primaryipaddress;
    $port      = $primaryport;
  }
}

sub socketopen {
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  $socketerrorflag = 0;

  select undef, undef, undef, 1.00;

  my $printstr = "socketopen attempt $addr $port\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen attempt $addr $port\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  #$iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(SOCK, $sockaddr)    || die "bind: $!\n";
  connect( SOCK, $paddr ) || &mydie("connect: $!");
  if ( $socketerrorflag == 1 ) {
    return;
  }
  $socketopenflag = 1;

  $sockaddr    = getsockname(SOCK);
  $sockaddrlen = length($sockaddr);
  if ( $sockaddrlen == 16 ) {

    #$line = `netstat -n | grep $port`;
    #print "$line\n";
    ($sockaddrport) = unpack_sockaddr_in($sockaddr);
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime socketopen successful $addr $port $sockaddrport\n";
    my $printstr = "socketopen successful $addr $port $sockaddrport\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck",  "miscdebug.txt",    "append", "misc", $printstr );
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "",     $logfilestr );
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
  my $printstr = "$errorstr\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck",  "miscdebug.txt",    "append", "misc", $printstr );
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "",     $logfilestr );

  $socketerrorflag = 1;
}

sub socketwrite {
  my ($message) = @_;

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  if ( $socketcnt < 1 ) {
    $line = `netstat -n | grep $port`;
    my $printstr = "$line\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

    $socketopenflag = 0;
    while ( $socketopenflag != 1 ) {
      &socketopenalarm();

      #&socketopen("$ipaddress","$port");
    }
    &logfile("socket reopened\n");
  }

  # xxxx temporary, for the dialup connection
  #$keepalive = 0;

  while ( $socketopenflag != 1 ) {
    &socketopenalarm();

    #&socketopen("$ipaddress","$port");
  }

  # xxxx
  #if ($respflag == 0) {
  #  close(SOCK);
  #  &socketopen("$fdmsaddr","$port");
  #}
  #if (!SOCK) {
  #  open(outfile,">/home/pay1/batchfiles/$devprod/telecheck/temp.txt");
  #  print outfile "dddd\n";
  #  close(outfile);
  #  exit;
  #}

  #$cardnum = substr($message,12,24);
  #$cardnum =~ s/^0+//g;
  #$xs = "x" x length($cardnum);
  $messagestr = $message;

  #$messagestr =~ s/$cardnum/$xs/g;

  #$cardnumber = $cardnum;
  #$sha1->reset;
  #$sha1->add($cardnumber);
  #$shacardnumber = $sha1->hexdigest();

  $checkmessage = $messagestr;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime = gmtime( time() );
  if ( $message !~ /0004ECHO/ ) {
    $logfilestr = "";
    $logfilestr .= "$username  $orderid\n";
    $logfilestr .= "$temptime send: $checkmessage  $shacardnumber\n";
    $logfilestr .= "sequencenum: $sequencenum retries: $retries\n\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );
  }

  my $printstr = "send: $checkmessage\n\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  send( SOCK, $message, 0, $paddr );
  &socketread($message);
}

sub socketread {
  ($message) = @_;

  # xxxx
  #recv(SOCK,$response,2048,0);
  #print "$response\n";
  my $printstr = "bbbb\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count    = 4;
  $mlen     = length($message);
  $response = "";
  $delay    = 10.0;
  my $printstr = "cccc\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  while ( $count && select( $rout = $rin, undef, undef, $delay ) ) {
    $delay = 1;

    #print "while\n";
    recv( SOCK, $response, 2048, 0 );
    $rlen = length($response);
    my $printstr = "recv: $rlen tt$response" . "tt\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

    #print "$mlen $rlen\n";

    $messlength = substr( $response, 0, 4 ) + 4;
    $d1         = substr( $response, 0, $messlength );
    my $printstr = "aaaa$d1\n";
    &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

    while ( ( ( $d1 =~ /^$nullmessage1/ ) || ( $d1 =~ /^$nullmessage2/ ) ) && ( $rlen >= $messlength ) ) {
      $messlength = substr( $response, 0, 4 ) + 4;
      $d1         = substr( $response, 0, $messlength );
      my $printstr = "bbbb$d1\n";
      &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
      $response = substr( $response, $messlength );
      $rlen = length($response);
      my $printstr = "dddd$response $rlen $mlen\n";
      &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

      $temptime   = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$temptime null message found\n\n";
      &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );

      $getrespflag = 1;
    }

    if ( ( ( $mlen > 10 ) && ( $rlen > 10 ) ) || ( $mlen <= 10 ) ) {
      if ( $rlen > 10 ) {
        $getrespflag = 1;
        &update();
        $transcnt--;
      }
      last;
    }
    $count--;
  }
  my $printstr = "end loop $transcnt\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  return ($response);
}

sub update {
  $rsequencenum = $response;
  $rsequencenum =~ s/^.*?TR0014([0-9]+?)\|.*$/$1/;

  #$rsequencenum = substr($response,59,4);
  my $printstr = "in update $rsequencenum\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );

  #  &logfile("sequencenum: $rsequencenum, transcnt: $transcnt\n");
  #$checkmessage = $response;
  #$checkmessage =~ s/\x1c/\[1c\]/g;
  #$checkmessage =~ s/\x1e/\[1e\]/g;
  #  &logfile("recv: $checkmessage\n");

  $cardnum = substr( $response, 16, 24 );
  $cardnum =~ s/^0+//g;
  $xs         = "x" x length($cardnum);
  $messagestr = $response;
  $messagestr =~ s/$cardnum/$xs/g;

  $logfilestr   = "";
  $checkmessage = $messagestr;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime = gmtime( time() );
  $logfilestr .= "$username  $rsequencenum\n";

  #print logfile "recv: $response\n";
  $logfilestr .= "$temptime recv: $response\n";

  #print logfile "sequencenum: $rsequencenum transcnt: $transcnt\n\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "", $logfilestr );

  #&timecheck("before update");
  if ( $timecheckfirstflag2 == 1 ) {
    $timecheckstart2     = time();
    $timecheckfirstflag2 = 0;
  }

  $sstatus{"$rsequencenum"} = "done";

  # yyyy

  my $printstr = "rseq: $rsequencenum pid: $sprocessid{$rsequencenum}\n";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck", "miscdebug.txt", "append", "misc", $printstr );
  $msg = pack "N", $sprocessid{"$rsequencenum"} + 0;
  my $ipcinvoicenum = " " x 24;
  $msg = $msg . $ipcinvoicenum . $response;

  $processid = $sprocessid{"$rsequencenum"};
  &procutils::updateprocmsg( $processid, "telecheck", "success", "$rsequencenum", "$response" );

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sprocessid{$rsequencenum};

  $timecheckend2   = time();
  $timecheckdelta2 = $timecheckend2 - $timecheckstart2;
}

sub logfile {
  my ($mssg) = @_;

  $logfilestr = "";
  $logfilestr .= "$mssg";
  my $printstr = "$mssg";
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/devlogs/telecheck",  "miscdebug.txt",    "append", "misc", $printstr );
  &procutils::filewrite( "$username", "telecheck", "/home/pay1/batchfiles/$devprod/telecheck", "serverlogmsg.txt", "append", "",     $logfilestr );
}

