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

$ipname    = "MAIN";
$ipnamesav = $ipname;

$test    = "no";
$devprod = "logs";

$host = "processor-host";    # Source IP address

$primaryipaddress = "10.150.48.37";    # primary server
$primaryport      = "9002";            # primary server

$secondaryipaddress = "10.150.48.37";  # secondary server  there is no secondary server
$secondaryport      = "9002";          # secondary server

$tertiaryipaddress = "10.150.48.37";   # tertiary server   DRS   don't use
$tertiaryipaddress = "10.150.48.37";   # tertiary server   IP change as per NCB 20120512 - Changeover to DRS
$tertiaryport      = "9002";           # tertiary server

#$serverarray{"MOSELLE"} = "10.150.48.59";
#$serverarray{"AMBER"} = "10.150.48.144";
#$serverarray{"HARLEY"} = "10.150.48.223";
#$serverarray{"DRSATIN"} = "10.150.48.59";
#$serverarray{"NELLIE"} = "10.150.57.12";
#$serverarray{"DIVA"} = "10.150.16.81";

$msgwritetime = time();

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;

$nullmessage1 = "00040000";
$nullmessage2 = "00040000";

# xxxx
if ( $test eq "yes" ) {
  $ipaddress = "10.160.3.13";    # test server
  $port      = "9002";           # test server  ## Was 5700
} elsif ( -e "/home/pay1/batchfiles/$devprod/ncb/secondary.txt" ) {
  my @tmpfilestrarray = &procutils::flagread( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "secondary.txt" );
  $secondary = $tmpfilestrarray[0];

  chop $secondary;

  if ( ( $secondary eq "2" ) && ( $ipaddress ne $tertiaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to tertiary socket\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
    $ipaddress = $tertiaryipaddress;
    $port      = $tertiaryport;
  } elsif ( ( $secondary ne "2" ) && ( $ipaddress ne $secondaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to secondary socket\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
    $ipaddress = $secondaryipaddress;
    $port      = $secondaryport;
  }
} elsif ( !( -e "/home/pay1/batchfiles/$devprod/ncb/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to primary socket\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $primaryipaddress;
  $port      = $primaryport;
}

$connectcount = 0;
while ( $socketopenflag != 1 ) {
  $port = &checkport("$port");
  &socketopen( "$ipaddress", "$port", "$ipname" );
  select undef, undef, undef, 2.00;
  $connectcount++;
  if ( $connectcount == 3 ) {
    &sendemail();
  }
}

# delete rows older than 2 minutes
my $now      = time();
my $deltime  = &miscutils::timetostr( $now - 120 );
my $printstr = "deltime: $deltime\n";
&procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

if (0) {

  my $dbquerystr = <<"dbEOM";
        delete from processormsg
        where (trans_time<?
          or trans_time is NULL
          or trans_time='')
          and processor='ncb'
dbEOM
  my @dbvalues = ("$deltime");
  &procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

}

while (1) {
  $temptime   = time();
  $outfilestr = "";
  $outfilestr .= "$temptime\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "accesstime.txt", "write", "", $outfilestr );

  if ( ( -e "/home/pay1/batchfiles/$devprod/ncb/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {

    sleep 1;
    exit;
  }

  # close after 5 minutes of inactivity so VPN doesn't get hung
  $timesincelastwrite = time() - $msgwritetime;

  #if (($socketopenflag == 1) && ($timesincelastwrite > 300)) {
  #  &socketclose("5 minute timeout");
  #}

  $keepalivecnt++;
  if ( ( $keepalivecnt >= 60 ) && ( $socketopenflag == 1 ) ) {
    my $printstr = "keepalivecnt = $keepalivecnt\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
    $keepalivecnt = 0;

    my $message = &networkmessage();
    $message = &prepmessage($message);
    &socketwrite($message);
    $mydelay = 2.0;
    &socketread($transcnt);

    $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
    if ( $socketcnt < 1 ) {
      my $printstr = "socketcnt < 1\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
      shutdown SOCK, 2;

      $socketopenflag = 0;
      if ( $socketopenflag != 1 ) {
        $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
        $mytime     = gmtime( time() );
        $logfilestr = "";
        $logfilestr .= "$mytime No ESTABLISHED\n";
        $logfilestr .= "$sockaddrport\n";
        $logfilestr .= "$sockettmp\n\n";
        &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
      }
      while ( $socketopenflag != 1 ) {
        $port = &checkport("$port");
        &socketopen( "$ipaddress", "$port", "$ipname" );
      }
      $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
      $logfilestr = "";
      $logfilestr .= "socket reopened\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
    }
  }

  #&checksecondary();

  &check();
  if ( $getrespflag == 0 ) {
    &socketclose();
  }

  #if ($socketopenflag == 1) {
  #  &socketclose("close after each transaction");
  #}
  select undef, undef, undef, 1.00;
}

exit;

sub checkport {
  if ( $test eq "yes" ) {
    return "$port";
  }

  my $tmpfilestr = &procutils::fileread( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "ports.txt" );
  my @tmpfilestrarray = split( /\n/, $tmpfilestr );

  my $portlist   = $tmpfilestrarray[0];
  my $activeport = $tmpfilestrarray[1];

  my ( $firstport, $lastport ) = split( /\-/, $portlist );
  $activeport++;
  if ( ( $activeport > $lastport ) || ( $activeport < $firstport ) ) {
    $activeport = $firstport;
  }
  $tmpfilestr = "";
  $tmpfilestr .= "$portlist\n";
  $tmpfilestr .= "$activeport\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "ports.txt", "write", "", $tmpfilestr );

  return $activeport;
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

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='ncb'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sthmsgvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthmsgvalarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage ) = @sthmsgvalarray[ $vali .. $vali + 4 ];

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $ipname = substr( $message, 0, 12 );
    $ipname =~ s/ //g;
    $message = substr( $message, 12 );

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and processor='ncb'
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    #while (1) {}

    $username =~ s/[^0-9a-zA-Z_]//g;
    $orderid =~ s/[^0-9a-zA-Z_]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;
    $ipname =~ s/[^0-9A-Z]//g;

    #$ipaddress = $serverarray{"$ipname"};
    #if ($ipname ne $ipnamesav) {
    #  close(SOCK);
    #  &socketopen("$ipaddress","$port","$ipname");
    #  $ipnamesav = $ipname;
    #}

    my $printstr = "$mytime msgrcv $username $orderid\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

    # send back failure if more than 60 seconds has passed
    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {

      #&mysqlmsgsnd($dbhmisc,$processid,"failure","","failure: message timeout");
      &procutils::updateprocmsg( $processid, "ncb", "failure", "", "failure: message timeout" );

      next;
    }

    $message = &prepmessage($message);

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;
    $sinvoicenum{"$sequencenum"} = $invoicenum;

    $getrespflag  = 0;
    $msgwritetime = time();
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "accesstime.txt", "write", "", $outfilestr );

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt > 6 ) {
      last;
    }
  }

  if ( $transcnt > 0 ) {
    $numtrans = $transcnt;
    $mydelay  = 30.0;
    &socketread($transcnt);
  }

  foreach $rsequencenum ( keys %susername ) {

    #print "$rsequencenum  retries: $sretries{$rsequencenum}\n";
    if ( $sstatus{"$rsequencenum"} ne "done" ) {
      $sretries{"$rsequencenum"}++;
      my $now    = time();
      my $mytime = &miscutils::strtotime( $strans_time{"$rsequencenum"} );
      my $delta  = $now - $mytime;

      #if ($sretries{"$rsequencenum"} > 2) {}
      # xxxxxxxx should be 120
      if ( $delta > 120 ) {
        $message    = $smessage{"$rsequencenum"};
        $newmessage = "";

        if ( $message =~ /^....0100/ ) {

          if (1) {

            # new stuff
            my ( $rlen, $messtype, $bitmap1, $bitmap2 ) = unpack "A4A4A16A16", $message;

            &decodebitmap($message);

            my @transaction = ();
            my $cardnum     = $msgvalues[2];
            my $cdatalen    = substr( "00" . length($cardnum), -2, 2 );
            $transaction[2] = $cdatalen . $cardnum;
            $transaction[3] = $msgvalues[3];
            $transaction[4] = $msgvalues[4];

            my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
            $lyear = substr( $lyear, -2, 2 );
            my $ltrandate = sprintf( "%02d%02d%02d%02d%02d", $lmonth + 1, $lday, $lhour, $lmin, $lsec );
            $transaction[7] = $ltrandate;

            my $tracenum = $msgvalues[11];
            $transaction[11] = $tracenum;
            if ( $cardnum =~ /^4/ ) {

              #$transaction[14] = $msgvalues[14];
              $transaction[18] = $msgvalues[18];
              $transaction[19] = $msgvalues[19];
              $transaction[22] = $msgvalues[22];
              $transaction[25] = $msgvalues[25];
            } else {
              $transaction[22] = $msgvalues[22];

              my $addtldata = $msgvalues[48];
              my $datalen = substr( "000" . length($addtldata), -3, 3 );
              if ( $datalen > 0 ) {
                $transaction[48] = $datalen . $addtldata;
              }

              #my $posdata = $msgvalues[61];
              #$datalen = substr("000" . length($posdata),-3,3);
              #if ($datalen > 0) {
              #  $transaction[61] = $datalen . $posdata;
              #}
            }

            $acqid           = $msgvalues[32];
            $adatalen        = substr( "00" . length($acqid), -2, 2 );
            $transaction[32] = $adatalen . $acqid;

            $transaction[37] = $msgvalues[37];
            $transaction[41] = $msgvalues[41];
            $transaction[42] = $msgvalues[42];
            $transaction[49] = $msgvalues[49];

            my $datetime = $msgvalues[7];
            if ( $cardnum =~ /^4/ ) {
              $transaction[90] = $messtype . $tracenum . $datetime . "0" x 22;
            }

            $newmessage = "";

            foreach my $var (@transaction) {
              $newmessage = $newmessage . $var;
            }

            my ( $bitmap1, $bitmap2 ) = &generatebitmap(@transaction);
            $newmessage = '0420' . $bitmap1 . $bitmap2 . $newmessage;

            my $len = length($newmessage) + 0;
            $len = substr( "0000" . $len, -4, 4 );
            $newmessage = $len . $newmessage;

            # end new stuff
          }

          #$message = &prepmessage($newmessage);
          $message = $newmessage;

          $getrespflag = 0;
          $logfilestr  = "";
          $temptime    = gmtime( time() );
          $logfilestr .= "$susername{$rsequencenum}  $sorderid{$rsequencenum}  sending void\n";
          &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

          &socketwrite($message);
          $transcnt++;
          $mydelay = 30.0;
          &socketread($transcnt);
        }

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

sub socketopen {
  my ( $addr, $port, $ipname ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  shutdown SOCK, 2;

  select undef, undef, undef, 1.00;

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen attempt $addr $port $ipname\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  #$iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(SOCK, $sockaddr)    || die "bind: $!\n";
  $errflag = 0;
  connect( SOCK, $paddr ) or $errflag = &mydie("connect: $addr $port $!");
  if ( $errflag == 0 ) {
    $socketopenflag = 1;
  }

  $sockaddr    = getsockname(SOCK);
  $sockaddrlen = length($sockaddr);
  if ( ( $socketopenflag == 1 ) && ( $sockaddrlen == 16 ) ) {
    ($sockaddrport) = unpack_sockaddr_in($sockaddr);
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$mytime socketopen successful\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
    $getrespflag = 1;
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }
}

sub mydie {
  my ($msg) = @_;

  my $printstr = "$msg\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  $logfilestr = "";
  $logfilestr .= "$msg\n\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

  return 1;

  #exit;
}

sub socketwrite {
  my ($message) = @_;
  my $printstr = "in socketwrite\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  if ( $message !~ /^....080/ ) {
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
    }

    if ( $msgvalues[48] ne "" ) {    # cvv data
      $datalen = length( $msgvalues[48] );
      $dataidx = $msgvaluesidx[48];
      my $temp = $msgvalues[48];
      for ( my $newidx = 1 ; $newidx < $datalen ; ) {
        my $tag     = substr( $temp, $newidx + 0, 2 );
        my $taglen  = substr( $temp, $newidx + 2, 2 );
        my $tagdata = substr( $temp, $newidx + 4, $taglen );
        if ( $tag eq "92" ) {
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

    if ( $msgvalues[126] ne "" ) {    # cvv data
      $cvvdata    = $msgvalues[126];
      $cvvdataidx = $msgvaluesidx[126];
      my $cvvlen = length($cvvdata);
      $cvv = substr( $cvvdata, 2, 4 );
      $messagestr = substr( $messagestr, 0, $cvvdataidx + ( $cvvlen - 4 ) ) . 'xxxx' . substr( $messagestr, $cvvdataidx + 4 + ( $cvvlen - 4 ) );
    }

    $shacardnumber = "";
    if ( ( length($cardnum) >= 13 ) && ( length($cardnum) < 20 ) ) {
      $cardnumber = $cardnum;

      #$sha1->reset;
      #$sha1->add($cardnumber);
      #$shacardnumber = $sha1->hexdigest();
      my $cc = new PlugNPay::CreditCard($cardnumber);
      $shacardnumber = $cc->getCardHash();
    }

    $logfilestr   = "";
    $checkmessage = $messagestr;
    $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $temptime = gmtime( time() );

    #$tempstr = unpack "H*", $message;
    my $mylen = length($message);
    $logfilestr .= "$username  $orderid\n";
    $logfilestr .= "$temptime send: $mylen $checkmessage  $shacardnumber\n\n";
    $logfilestr .= "sequencenum: $sequencenum retries: $retries\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

    my $printstr = "$temptime send: $mylen $checkmessage\n\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  }

  if ( $socketopenflag != 1 ) {
    $logfilestr = "";
    $logfilestr .= "socketopenflag = 0, in socketwrite\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
  }
  &checksecondary();
  $connectcount = 0;
  while ( $socketopenflag != 1 ) {
    $port = &checkport("$port");
    &socketopen( "$ipaddress", "$port", "$ipname" );
    if ( $socketopenflag != 1 ) {
      &miscutils::mysleep(2.0);
      $connectcount++;
      if ( $connectcount == 3 ) {
        &sendemail();
      }
    }
  }
  $numbytes = send( SOCK, $message, 0, $paddr );

  #$numbytes = send(SOCK, $message . "\x00" x 400, 0, $paddr);

  #$checkmessage = $message;
  #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  #print "bbbb $username $numbytes $checkmessage\n\n";

  #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsg.txt");
  #print logfile "$username $message\n\n";
  #close(logfile);
}

sub socketread {
  my ($numtries) = @_;

  my $printstr = "in socketread\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

  $temp11 = time();
  vec( $rin, fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $respdata = "";
  while ( $count && select( $rout = $rin, undef, undef, $mydelay ) ) {
    $mydelay = 2.0;
    my $printstr = "in while\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
    $logfilestr = "";
    $logfilestr .= "in while\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
    recv( SOCK, $response, 2048, 0 );

    #if ($response !~ /^....0810/) {
    #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsg.txt");
    #$mytime = gmtime(time());
    #$checkmessage = $response;
    #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    #print logfile "$mytime recva: $checkmessage\n";
    #print "recva: $mytime $checkmessage\n";
    #print logfile "recvc: $response\n";
    #close(logfile);
    #}

    $respdata = $respdata . $response;

    #$resplength = unpack "n", substr($respdata,0);
    $resplength = substr( $respdata, 0, 4 );
    $resplength = $resplength + 4;
    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $nullresp = substr( $respdata, 0, 8 );
      if ( $nullresp =~ /^....0810/ ) {
        $transcnt--;
        if ( $transcnt == 0 ) {
          $getrespflag = 1;
        }
        $mytime     = gmtime( time() );
        $logfilestr = "";
        $logfilestr .= "null message found $mytime\n\n";
        &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
      } else {
        $transcnt--;

        #if ($transcnt == 0) {
        #  $getrespflag = 1;
        #}
        if ( $resplength == 4 ) {
        } elsif ( $respdata =~ /^....0420/ ) {
          $getrespflag = 1;
        } else {
          $getrespflag = 1;
          $response = substr( $respdata, 0, $resplength );
          &updatencb();
          delete $writearray{$rsequencenum};
        }
      }
      if ( !%writearray ) {
        $donereadingflag = 1;
      }
      $respdata = substr( $respdata, $resplength );

      #$resplength = unpack "n", substr($respdata,4);
      $resplength = substr( $respdata, 0, 4 );
      $resplength = $resplength + 4;
      $rlen       = length($respdata);

      $temptime   = time();
      $outfilestr = "";
      $outfilestr .= "$temptime\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "accesstime.txt", "write", "", $outfilestr );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $delta      = time() - $temp11;
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt delta: $delta\n\n\n\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

}

sub updatencb {
  $addlen = 0;
  $char = substr( $response, 8, 2 );
  if ( $char eq "F2" ) {
    $addlen = 16;

    #$addlen = 8;
  }

  if ( $response =~ /^..0510/ ) {

    #$invoiceloc = 48;
  } elsif ( $response =~ /^....0110/ ) {
    $cardlen = substr( $response, 24 + $addlen, 2 );
    $invoiceloc = 24 + 2 + $addlen + $cardlen + 28;
  } else {
    $cardlen = substr( $response, 24 + $addlen, 2 );
    $invoiceloc = 24 + 2 + $addlen + $cardlen + 28;
  }

  my $printstr = "cardlen: $cardlen\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "invoiceloc: $invoiceloc\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  $rsequencenum = substr( $response, $invoiceloc, 6 );

  $logfilestr = "";
  $logfilestr .= "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

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
  $checkmessage = $messagestr;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime   = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$temptime recv: $checkmessage\n";
  my $printstr = "$temptime recv: $checkmessage\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb",  "miscdebug.txt",    "append", "misc", $printstr );
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "",     $logfilestr );

  $sstatus{"$rsequencenum"} = "done";

  $processid = $sprocessid{"$rsequencenum"};

  #if (&mysqlmsgsnd($dbhmisc,$processid,"success","$sinvoicenum{$rsequencenum}","$response") == NULL) {}
  &procutils::updateprocmsg( $processid, "ncb", "success", "$sinvoicenum{$rsequencenum}", "$response" );

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
  my ($reason) = @_;

  if ( $reason eq "" ) {
    $reason = "no response";
  }

  $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
  $logfilestr = "";
  $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
  ( $d1, $d2, $temp ) = &miscutils::genorderid();
  $logfilestr .= "before socket is closed because of $reason $temp\n$sockaddrport\n$sockettmp\n\n";

  shutdown SOCK, 2;

  $socketopenflag = 0;
  $getrespflag    = 1;

  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() );

  if ( ( $reason eq "no response" ) && ( $min % 10 == 0 ) ) {
    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: cprice\@plugnpay.com\n";
    print MAIL "From: dprice\@plugnpay.com\n";
    print MAIL "Subject: ncb - no response to authorization\n";
    print MAIL "\n";

    $mytime = gmtime( time() );
    print MAIL "$mytime\n";
    print MAIL "ncb socket is being closed, then reopened because no response was\n\n";
    print MAIL "received to an authorization request.\n";

    close(MAIL);
  }

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  $tmpi      = 0;
  while ( $socketcnt >= 1 ) {
    $tmpi++;
    if ( $tmpi > 4 ) {
      $logfilestr .= "exiting program because socket couldn't be closed\n\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
      exit;
    }
    shutdown SOCK, 2;

    select( undef, undef, undef, 0.5 );
    $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  }

  shutdown SOCK, 2;

  $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
  ( $d1, $d2, $temp ) = &miscutils::genorderid();
  $logfilestr .= "socket closed because of $reason $temp\n$sockaddrport\n$sockettmp\n\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
}

sub sendemail {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime sending email to jncb\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

  open( MAIL, "| /usr/lib/sendmail -t" );
  print MAIL "To: computeroperators\@jncb.com\n";
  print MAIL "From: cprice\@plugnpay.com\n";
  print MAIL "Bcc: cprice\@plugnpay.com\n";
  print MAIL "Bcc: dprice\@plugnpay.com\n";
  print MAIL "Subject: Plug \& Pay Technologies - JNCB - cannot connect\n";
  print MAIL "\n";
  print MAIL "Plug \& Pay Technologies cannot connect. Can you reset the application?\n";
  print MAIL "\n";
  print MAIL "\n";
  print MAIL "Thank you,\n";
  print MAIL "Carol Price\n";
  print MAIL "Plug \& Pay Technologies, Inc.\n";
  print MAIL "cprice\@plugnpay.com\n";
  print MAIL "970-532-0607\n";
  close(MAIL);

}

sub prepmessage {
  my ($message) = @_;

  $transcnt++;

  #$sequencenum = ($sequencenum + 1) % 255;
  #$sequencenum = sprintf("%012d", $sequencenum);
  #$message = substr($message,0,6) . $sequencenum . substr($message,18);
  #$message = substr($message,0,2) . $sequencenum . substr($message,14);

  $username =~ s/[^0-9a-zA-Z_]//g;
  %datainfo = ( "username", "$username" );
  my $dbquerystr = <<"dbEOM";
          select username,invoicenum
          from ncb
          where username='ncb'
dbEOM
  my @dbvalues = ();
  ( $chkusername, $sequencenum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  $sequencenum = ( $sequencenum % 900000 ) + 1;

  if ( $chkusername eq "" ) {
    my $dbquerystr = <<"dbEOM";
            insert into ncb
            (username,invoicenum)
            values (?,?)
dbEOM

    my %inserthash = ( "username", "ncb", "invoicenum", "$sequencenum" );
    &procutils::dbinsert( $username, $orderid, "pnpmisc", "ncb", %inserthash );

  } else {
    my $dbquerystr = <<"dbEOM";
            update ncb set invoicenum=?
            where username='ncb'
dbEOM
    my @dbvalues = ("$sequencenum");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  }

  $sequencenum = sprintf( "%06d", $sequencenum + .0001 );
  my $printstr = "sequencenum: $sequencenum\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  ($invoiceloc) = &decodebitmap( $message, 11 );

  #($refnumloc) = &decodebitmap($message,37);
  ( my $refnumloc, my $refnum ) = &decodebitmap( $message, 37 );

  #my $refnum = $msgvalues[37];
  #my $refnumloc = $msgvaluesidx[37];

  if ( ( $refnumloc > 0 ) && ( $refnum eq "000000000000" ) ) {
    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() );
    $yday = substr( "000" . $yday + 1, -3, 3 );
    $year = substr( "0" . $year,       -1, 1 );
    my $julianday = sprintf( "%01d%03d", $year, $yday );
    $refnum = $julianday . substr( "0" x 8 . $sequencenum, -8, 8 );
    $message = substr( $message, 0, $refnumloc ) . $refnum . substr( $message, $refnumloc + 12 );
  }

  $message = substr( $message, 0, $invoiceloc ) . $sequencenum . substr( $message, $invoiceloc + 6 );

  return $message;
}

sub networkmessage {
  @transaction    = ();
  $transaction[0] = '0800';                # message id (4n)
  $transaction[1] = "8220000100000000";    # primary bit map (8n)
  $transaction[2] = "0400000000000000";    # secondary bit map (8n) 1

  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
  $lyear = substr( $lyear, -2, 2 );
  my $ltrandate = sprintf( "%02d%02d", $lmonth + 1, $lday );
  my $ltrantime = sprintf( "%02d%02d%02d", $lhour, $lmin, $lsec );
  $transaction[3] = $ltrandate . $ltrantime;    # transmission date/time (10n) 7
  $transaction[4] = '000000';                   # system trace number (6n) 11

  $transaction[5] = "06" . "019995";            # acquiring institution id -  bank id(12n) LLVAR 32
  $transaction[6] = '301';                      # network management code (3n) 70

  my $message = "";
  foreach $var (@transaction) {
    $message = $message . $var;
  }

  my $len = length($message) + 0;
  $len = substr( "0000" . $len, -4, 4 );
  $message = $len . $message;

  return $message;
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
  $bitlenarray[44]  = "LLLVARa";
  $bitlenarray[45]  = "LLVARa";
  $bitlenarray[48]  = "LLLVARa";
  $bitlenarray[49]  = 3;
  $bitlenarray[51]  = 3;
  $bitlenarray[53]  = "LLVARa";
  $bitlenarray[54]  = "LLLVARa";
  $bitlenarray[57]  = "3a";
  $bitlenarray[58]  = "LLLVARa";
  $bitlenarray[59]  = "LLLVARa";
  $bitlenarray[60]  = "LLVARa";
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

  my $idxstart = 8;                              # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 16 );
  $bitmap1 = pack "H16", $bitmap1;
  my $bitmap = unpack "H16", $bitmap1;

  #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsg.txt");
  #print logfile "\n\nbitmap1: $bitmap\n";
  $idx = $idx + 16;

  my $end = 1;
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 16 );
    $bitmap2 = pack "H16", $bitmap2;
    $bitmap = unpack "H16", $bitmap2;

    #print logfile "bitmap2: $bitmap\n";

    my $removebit = pack "H*", "7fffffffffffffff";
    $bitmap1 = $bitmap1 & $removebit;

    $end = 2;
    $idx = $idx + 16;
  }

  @msgvalues    = ();
  @msgvaluesidx = ();
  my $myk           = 0;
  my $myi           = 0;
  my $bitnum        = 0;
  my $bigbitmaphalf = $bitmap1;
  my $wordflag      = 3;
  for ( $myj = 1 ; $myj <= $end ; $myj++ ) {

    #print logfile "myj: $myj\n";
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

        #$bit = ($bitmaphalf >> (128 - $bitnum)) % 2;
        $bit = ( $bitmaphalf >> ( 128 - ( $wordflag * 32 ) - $bitnum ) ) % 2;
        $bitnum++;

        #$bitmaphalfstr = pack "N", $bitmaphalf;
        #$bitmaphalfstr = unpack "H*", $bitmaphalfstr;
        #print logfile "aaaa $bit  $bitnum  $bitmaphalfstr\n";
        if ( $bitnum == 64 ) {
          last;
        }
      }
      if ( ( ( $bitnum == 64 ) || ( $bitnum == 128 ) ) && ( $bit == 0 ) ) {
        last;
      }

      my $tempstr = substr( $message, $idx, 8 );
      $tempstr = unpack "H*", $tempstr;

      #$bitmaphalfstr = pack "N", $bitmaphalf;
      #$bitmaphalfstr = unpack "H*", $bitmaphalfstr;
      #print logfile "aaaa $tempstr    $bitmaphalfstr\n";

      my $idxold = $idx;

      my $idxlen1 = $bitlenarray[ $bitnum - 1 ];
      my $idxlen  = $idxlen1;
      if ( $idxlen1 eq "LLVAR" ) {
        $idxlen = substr( $message, $idx, 2 );

        #$idxlen = unpack "H2", $idxlen;
        #$idxlen = int(($idxlen / 2) + .5);
        $idx = $idx + 2;
      } elsif ( $idxlen1 eq "LLVARa" ) {
        $idxlen = substr( $message, $idx, 2 );

        #$idxlen = unpack "H2", $idxlen;
        $idx = $idx + 2;
      } elsif ( $idxlen1 eq "LLLVAR" ) {
        $idxlen = substr( $message, $idx, 3 );

        #$idxlen = unpack "H4", $idxlen;
        #$idxlen = int(($idxlen / 2) + .5);
        $idx = $idx + 3;
      } elsif ( $idxlen1 eq "LLLVARa" ) {
        $idxlen = substr( $message, $idx, 3 );

        #$idxlen = unpack "H4", $idxlen;
        $idx = $idx + 3;
      } elsif ( $idxlen1 =~ /a/ ) {
        $idxlen =~ s/a//g;
      } else {

        #$idxlen = int(($idxlen / 2) + .5);
      }
      my $value = substr( $message, $idx, $idxlen );

      #if ($idxlen1 !~ /a/) {
      #  $value = unpack "H*",$value;
      #}
      #else {
      #$value = &ebcdic2ascii($value);
      #}
      $tmpbit = $bitnum - 1;

      #print logfile "bit: $idxold  $tmpbit  $idxlen1 $idxlen  $value\n";

      $msgvalues[$tmpbit]    = "$value";
      $msgvaluesidx[$tmpbit] = "$idx";

      $myk++;
      if ( $myk > 26 ) {
        return -1, "";

        #exit;
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
       #print logfile "\n";

  #my $tempstr = unpack "H*",$message;
  #print logfile "$tempstr\n\n";

  #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsg.txt");
  #for (my $i=0; $i<=$#msgvalues; $i++) {
  #  if ($msgvalues[$i] ne "") {
  #    print logfile "$i  $msgvalues[$i]\n";
  #  }
  #}
  #close(logfile);

  return -1, "";
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

  $bitmap1 =~ tr/a-z/A-Z/;
  $bitmap2 =~ tr/a-z/A-Z/;

  return $bitmap1, $bitmap2;
}

sub checksecondary {

  # xxxx
  if ( $test eq "yes" ) {
    $ipaddress = "10.160.3.13";    # test server
    $port      = "9002";           # test server    # was 5700
  } elsif ( -e "/home/pay1/batchfiles/$devprod/ncb/secondary.txt" ) {
    my @tmpfilestrarray = &procutils::flagread( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "secondary.txt" );
    $secondary = $tmpfilestrarray[0];

    chop $secondary;

    if ( ( $secondary eq "2" ) && ( $ipaddress ne $tertiaryipaddress ) ) {
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime switching to tertiary socket\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
      $ipaddress = $tertiaryipaddress;
      $port      = $tertiaryport;

      $socketopenflag = 0;
      while ( $socketopenflag != 1 ) {
        $port = &checkport("$port");
        &socketopen( "$ipaddress", "$port", "$ipname" );
      }
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime secondary socket opened\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
    } elsif ( ( $secondary ne "2" ) && ( $ipaddress ne $secondaryipaddress ) ) {
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime switching to secondary socket\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
      $ipaddress = $secondaryipaddress;
      $port      = $secondaryport;

      $socketopenflag = 0;
      while ( $socketopenflag != 1 ) {
        $port = &checkport("$port");
        &socketopen( "$ipaddress", "$port", "$ipname" );
      }
      $mytime     = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$mytime secondary socket opened\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
    }

    #$mytime = gmtime(time());
    #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsg.txt");
    #print logfile "$mytime switching to secondary socket\n";
    #print logfile "$sockaddrport\n";
    #print logfile "$sockettmp\n\n";
    #close(logfile);
    #close(SOCK);
    #$socketopenflag = 0;
    #$ipaddress = $secondaryipaddress;
    #$port = $secondaryport;
    #while ($socketopenflag != 1) {
    #  &socketopen("$ipaddress","$port");
    #}
    #$mytime = gmtime(time());
    #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsg.txt");
    #print logfile "$mytime secondary socket opened\n";
    #print logfile "$sockaddrport\n";
    #print logfile "$sockettmp\n\n";
    #close(logfile);
  } elsif ( !( -e "/home/pay1/batchfiles/$devprod/ncb/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );

    $socketopenflag = 0;
    $ipaddress      = $primaryipaddress;
    $port           = $primaryport;
    while ( $socketopenflag != 1 ) {
      $port = &checkport("$port");
      &socketopen( "$ipaddress", "$port", "$ipname" );
    }
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime primary socket opened\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsg.txt", "append", "", $logfilestr );
  }
}

