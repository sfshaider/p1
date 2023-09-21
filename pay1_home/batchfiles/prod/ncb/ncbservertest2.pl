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
use rsautils;

$devprod = "logs";

$test = "no";

$host = "processor-host";    # Source IP address

$ipname = "NOAH";

my $logfilestr = &procutils::fileread( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "testserver.txt" );
my @logfilestrarray = split( /\n/, $logfilestr );

$line = $logfilestrarray[0];
chop $line;

( $chkipname, $chktime ) = split( / /, $line, 2 );
my $printstr = "$chktime $ipname\n";
&procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

if ( $chkipname ne "" ) {
  $ipname = $chkipname;
}

$ipnamesav = $ipname;

#$primaryipaddress = "10.150.48.59";     # Test Host Moselle -  20050818
#$primaryport = "9002";                 # primary server
$primaryipaddress = "10.150.48.223";    # Test Host Harley -  20050818
$primaryport      = "9002";             # primary server

#$secondaryipaddress = "10.150.48.59";      # secondary server
#$secondaryport = "9002";                        # secondary server
$secondaryipaddress = "10.150.48.223";    # secondary server
$secondaryport      = "9002";             # secondary server

$port = $primaryport;

#$serverarray{"MOSELLE"} = "10.150.48.59";
#$serverarray{"AMBER"} = "10.150.48.144";
#$serverarray{"HARLEY"} = "10.150.48.223";
#$serverarray{"DRSATIN"} = "10.150.48.59";
#$serverarray{"NELLIE"} = "10.150.57.12";
#$serverarray{"DIVA"} = "10.150.16.81";

$msgwritetime = time();

## Clean up as per Craig  20170323
#$serverarray{"MIDAS"} = "10.150.35.20";  ### As per Richard Arnold 20110720
$serverarray{"MIRO"}   = "10.150.35.5";     ### As per Daimion Reece 20140415
$serverarray{"NOAH"}   = "10.150.35.76";
$serverarray{"FELL"}   = "10.170.64.117";
$serverarray{"DAMON"}  = "10.170.64.129";
$serverarray{"SINDY"}  = "10.170.64.98";
$serverarray{'LUC'}    = "10.150.77.167";
$serverarray{'LEON'}   = "10.150.48.188";
$serverarray{'LESYA1'} = "10.150.16.253";
$serverarray{'LESYA2'} = "10.150.16.254";
$serverarray{'ZONA1'}  = "10.150.48.252";
$serverarray{'ZONA2'}  = "10.150.48.253";
$serverarray{'LARA1'}  = "10.150.48.187";
$serverarray{'LARA2'}  = "10.150.77.218";
$serverarray{'PALLAS'} = "10.170.67.95";

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;
$firstwriteflag = 0;    # set to 1 first time a write is done

$nullmessage1 = "00040000";
$nullmessage2 = "00040000";

#$connectcount = 0;
#while ($socketopenflag != 1) {
#  &socketopen("$ipaddress","$port","$ipname");
#  select undef, undef, undef, 2.00;
#  $connectcount++;
#  if ($connectcount == 3) {
#    &sendemail();
#  }
#}

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
        and processor='ncbtest2'
dbEOM
  my @dbvalues = ("$deltime");
  &procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

}

while (1) {
  $temptime   = time();
  $outfilestr = "";
  $outfilestr .= "$temptime\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "accesstime2.txt", "write", "", $outfilestr );

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
  if ( ( $firstwriteflag == 1 ) && ( $keepalivecnt >= 60 ) ) {
    my $printstr = "keepalivecnt = $keepalivecnt\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
    $keepalivecnt = 0;

    #my $message = &networkmessage();
    #$message = &prepmessage($message);
    #&socketwrite($message);
    #$mydelay = 2.0;
    #&socketread($transcnt);

    if (0) {
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
          &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );
        }
        while ( $socketopenflag != 1 ) {
          &socketopen( "$ipaddress", "$port", "$ipname" );
        }
        $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
        $logfilestr = "";
        $logfilestr .= "socket reopened\n";
        $logfilestr .= "$sockaddrport\n";
        $logfilestr .= "$sockettmp\n\n";
        &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );
      }
    }
  }

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
        where processor='ncbtest2'
        and status='pending'
dbEOM
  my @dbvalues = ();
  my @sthmsgvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sthmsgvalarray) ; $vali = $vali + 5 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage ) = @sthmsgvalarray[ $vali .. $vali + 4 ];

    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    $ipname = substr( $message, 0, 12 );
    $message = substr( $message, 12 );

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and processor='ncbtest2'
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    #while (1) {}
    #if (0) {
    #if ((-e "/home/pay1/batchfiles/$devprod/ncb/stopserver.txt") || (-e "/home/pay1/stopfiles/stop_processors")) {
    #  close(SOCK);
    #  sleep 1;
    #  exit;
    #}

    #if (msgrcv($msqida, $newmsg, 2048, 1, &IPC_NOWAIT) == NULL) {
    #  if ($! !~ /No message of desired type/) {
    #    open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsgtest2.txt");
    #    print logfile "a: rcv failure $!\n";
    #    close(logfile);
    #  }
    #  last;
    #}
    #else {
    #  $mytime = gmtime(time());
    #  open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsgtest2.txt");
    #  print logfile "$mytime a: rcv success\n";
    #  close(logfile);
    #}

    #($type,$processid,$username,$orderid,$trans_time) = unpack "La6a12a24a14", $newmsg;
    #$message = substr($newmsg,60);

    #($type,$processid,$username,$orderid,$trans_time,$ipname) = unpack "La6a12a24a14a12", $newmsg;
    #$message = substr($newmsg,72);
    #if ($ipname =~ /^[0-9]{4}/) {
    #  $ipname = "";
    #  $message = substr($newmsg,60);
    #}
    #}

    $username =~ s/[^0-9a-zA-Z_]//g;
    $orderid =~ s/[^0-9a-zA-Z_]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;
    $ipname =~ s/[^0-9A-Z]//g;

    if ( $ipname eq "" ) {
      $ipname = "NOAH";
    }

    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime $username $orderid $ipname\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

    $ipaddress = $serverarray{"$ipname"};
    if ( $ipname ne $ipnamesav ) {

      $logfilestr = "";
      $logfilestr .= "IPNAME:$ipname TIME:$mytime, IP:$ipaddress\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "testserver.txt", "write", "", $logfilestr );
      $socketopenflag = 0;
      $myi            = 0;
      while ( $socketopenflag != 1 ) {
        $myi++;
        if ( $myi > 4 ) {
          last;
        }
        &socketopen( "$ipaddress", "$port", "$ipname" );
      }

      #&socketopen("$ipaddress","$port","$ipname");
      $ipnamesav = $ipname;
    }

    my $printstr = "$mytime msgrcv $username $orderid $ipname\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

    #$ipaddress = $serverarray{"$ipname"};
    #if ($ipname ne $ipnamesav) {
    #  close(SOCK);
    #  &socketopen("$ipaddress","$port","$ipname");
    #  $ipnamesav = $ipname;
    #}

    my $printstr = "$mytime msgrcv $username $orderid\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;

    $message = &prepmessage($message);

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sprocessid{"$sequencenum"}  = $processid;
    $sinvoicenum{"$sequencenum"} = $invoicenum;

    $getrespflag    = 0;
    $firstwriteflag = 1;
    $msgwritetime   = time();
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "accesstime2.txt", "write", "", $outfilestr );

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

          # void message

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
            $newmessage = '0400' . $bitmap1 . $bitmap2 . $newmessage;

            my $len = length($newmessage) + 0;
            $len = substr( "0000" . $len, -4, 4 );
            $newmessage = $len . $newmessage;

            # end new stuff
          }

          # old stuff
          if (0) {
            if ( $message =~ /^....0100.2246481/ ) {    # visa
              my ( $rlen, $messtype, $bitmap1, $bitmap2 ) = unpack "A4A4A16A16", $message;

              my $addlen = 0;
              my $char = substr( $message, 8, 2 );
              if ( $char eq "F2" ) {
                $addlen = 16;
              }

              my $idx     = 24 + $addlen;
              my $datalen = "";

              $cdatalen = substr( $message, $idx, 2 );
              my $cardnum = substr( $message, $idx + 2, $cdatalen );
              $idx = $idx + 2 + $cdatalen;

              my $restofdata = substr( $message, $idx );

              ( $pcode, $amt, $datetime, $tracenum, $exp, $merchtype, $acqcountry, $posentry, $poscond ) = unpack "A6A12A10A6A4A4A3A3A2", $restofdata;
              $idx = 50;

              $adatalen = substr( $restofdata, $idx, 2 );
              my $acqid = substr( $restofdata, $idx + 2, $adatalen );
              $idx = $idx + 2 + $adatalen;

              my $restofdata = substr( $restofdata, $idx );

              ( $refnum, $tid, $cardacceptid, $company, $currency, $addtlinfo ) = unpack "A12A8A15A40A3A6", $restofdata;
              $idx = 50;

              my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
              $lyear = substr( $lyear, -2, 2 );
              my $ltrandate = sprintf( "%02d%02d%02d%02d%02d", $lmonth + 1, $lday, $lhour, $lmin, $lsec );

              $newmessage = "0420" . "F220608108808000" . "0000004000000000";
              $newmessage = $newmessage . $cdatalen . $cardnum;
              $newmessage = $newmessage . $pcode . $amt . $ltrandate . $tracenum . $merchtype . $acqcountry . $poscond . $adatalen . $acqid;
              $newmessage = $newmessage . $refnum . $tid . $currency;
              $newmessage = $newmessage . $messtype . $tracenum . $datetime . "0" x 22;

              $len        = length($newmessage) + 0;
              $len        = substr( "0000" . $len, -4, 4 );
              $newmessage = $len . $newmessage;

            } elsif ( $message =~ /^....010072244401/ ) {    # mastercard

              my ( $rlen, $messtype, $bitmap1, $bitmap2 ) = unpack "A4A4A16A16", $message;

              my $addlen = 0;
              my $char = substr( $message, 8, 2 );
              if ( $char eq "F2" ) {
                $addlen = 16;
              }

              my $idx     = 24 + $addlen;
              my $datalen = "";

              $cdatalen = substr( $message, $idx, 2 );
              my $cardnum = substr( $message, $idx + 2, $cdatalen );
              $idx = $idx + 2 + $cdatalen;

              my $restofdata = substr( $message, $idx );

              ( $pcode, $amt, $datetime, $tracenum, $exp, $merchtype, $posentry ) = unpack "A6A12A10A6A4A4A3", $restofdata;
              $idx = 45;

              $adatalen = substr( $restofdata, $idx, 2 );
              my $acqid = substr( $restofdata, $idx + 2, $adatalen );
              $idx = $idx + 2 + $adatalen;

              my $restofdata = substr( $restofdata, $idx );

              ( $refnum, $tid, $cardacceptid, $company ) = unpack "A12A8A15A40", $restofdata;
              $idx = 75;

              my $restofdata = substr( $restofdata, $idx );
              $idx = 0;

              $pdatalen = substr( $restofdata, $idx, 3 );
              my $privdata = substr( $restofdata, $idx + 3, $pdatalen );
              $idx = $idx + 3 + $pdatalen;

              my $restofdata = substr( $restofdata, $idx );

              ($currency) = unpack "A3", $restofdata;
              $idx = 3;

              my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime( time() );
              $lyear = substr( $lyear, -2, 2 );
              my $ltrandate = sprintf( "%02d%02d%02d%02d%02d", $lmonth + 1, $lday, $lhour, $lmin, $lsec );

              $newmessage = "0420" . "7220000108808000";
              $newmessage = $newmessage . $cdatalen . $cardnum;
              $newmessage = $newmessage . $pcode . $amt . $ltrandate . $tracenum . $adatalen . $acqid;
              $newmessage = $newmessage . $refnum . $tid . $currency;

              $len        = length($newmessage) + 0;
              $len        = substr( "0000" . $len, -4, 4 );
              $newmessage = $len . $newmessage;

            }
          }

          #$message = &prepmessage($newmessage);
          $message = $newmessage;

          $getrespflag = 0;
          $logfilestr  = "";
          $temptime    = gmtime( time() );
          $logfilestr .= "$susername{$rsequencenum}  $sorderid{$rsequencenum}  sending void\n";
          &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

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
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

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
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );
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
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

  return 1;

  #exit;
}

sub socketwrite {
  my ($message) = @_;
  my $printstr = "in socketwrite\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  if ( $message !~ /^....0800/ ) {
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

    #if ((length($cardnum) >= 13) && (length($cardnum) < 20)) {
    #  $cardnumber = $cardnum;
    #  $sha1->reset;
    #  $sha1->add($cardnumber);
    #  $shacardnumber = $sha1->hexdigest();
    #}

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
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

    my $printstr = "$temptime send: $mylen $checkmessage\n\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  }

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $ipaddress`;
  if ( $socketcnt < 1 ) {
    my $printstr = "socketcnt < 1\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );
    shutdown SOCK, 2;

    $socketopenflag = 0;
    $sockettmp      = `netstat -n | grep $port | grep -v TIME_WAIT`;
    $mytime         = gmtime( time() );
    $logfilestr     = "";
    $logfilestr .= "$mytime No ESTABLISHED\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );
  }

  if ( $socketopenflag != 1 ) {
    $logfilestr = "";
    $logfilestr .= "socketopenflag = 0, in socketwrite\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );
  }
  $connectcount = 0;
  while ( $socketopenflag != 1 ) {
    &socketopen( "$ipaddress", "$port", "$ipname" );

    #if ($socketopenflag != 1) {
    #  &miscutils::mysleep(2.0);
    #  $connectcount ++;
    #  if ($connectcount == 3) {
    #    &sendemail();
    #  }
    #}
  }
  $numbytes = send( SOCK, $message, 0, $paddr );

  #$numbytes = send(SOCK, $message . "\x00" x 400, 0, $paddr);

  #$checkmessage = $message;
  #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  #print "bbbb $username $numbytes $checkmessage\n\n";

  #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsgtest2.txt");
  #print logfile "$username $message\n\n";
  #close(logfile);
}

sub socketread {
  my ($numtries) = @_;

  my $printstr = "in socketread\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  $donereadingflag = 0;

  $logfilestr = "";
  $logfilestr .= "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

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
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

    recv( SOCK, $response, 2048, 0 );

    #if ($response !~ /^....0810/) {
    #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsgtest2.txt");
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

    #$resplength = unpack "S", substr($respdata,0);
    $resplength = substr( $respdata, 0, 4 );
    $resplength = $resplength + 4;
    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

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
        &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );
      } else {
        $transcnt--;

        #if ($transcnt == 0) {
        #  $getrespflag = 1;
        #}
        if ( $resplength == 4 ) {
        } elsif ( $respdata =~ /^....0400/ ) {
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

      #$resplength = unpack "S", substr($respdata,4);
      $resplength = substr( $respdata, 0, 4 );
      $resplength = $resplength + 4;
      $rlen       = length($respdata);

      $temptime   = time();
      $outfilestr = "";
      $outfilestr .= "$temptime\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "accesstime2.txt", "write", "", $outfilestr );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $delta      = time() - $temp11;
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt delta: $delta\n\n\n\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

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
  $printstr .= "invoiceloc: $invoiceloc\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  $rsequencenum = substr( $response, $invoiceloc, 6 );

  $logfilestr = "";
  $logfilestr .= "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

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
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );

  my $printstr = "$temptime recv: $checkmessage\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/devlogs/ncb", "miscdebug.txt", "append", "misc", $printstr );

  $sstatus{"$rsequencenum"} = "done";

  $processid = $sprocessid{"$rsequencenum"};

  #if (&mysqlmsgsnd($dbhmisc,$processid,"success","$sinvoicenum{$rsequencenum}","$response") == NULL) {}
  &procutils::updateprocmsg( $processid, "ncbtest2", "success", "$sinvoicenum{$rsequencenum}", "$response" );

  # yyyy
  #if (0) {
  #print "bbbb $rsequencenum   $sprocessid{$rsequencenum}\n";
  #$msg = pack "L", $sprocessid{"$rsequencenum"} + 0;
  #$msg = $msg . $sinvoicenum{$rsequencenum} . $response;

  #if (msgsnd($msqidb, $msg, &IPC_NOWAIT) == NULL) {
  #  open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsgtest2.txt");
  #  print logfile "a: snd failure $!\n";
  #  close(logfile);
  #  #exit;
  #}
  #else {
  #  $mytime = gmtime(time());
  #  open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsgtest2.txt");
  #  print logfile "$mytime a: snd success response $sprocessid{$rsequencenum}\n";
  #  close(logfile);
  #print "msgsnd $username $orderid\n";
  #}
  #}

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

  #if ($reason eq "no response") {
  #  open(MAIL,"| /usr/lib/sendmail -t");
  #  print MAIL "To: cprice\@plugnpay.com\n";
  #  print MAIL "From: dprice\@plugnpay.com\n";
  #  print MAIL "Subject: ncb - no response to authorization\n";
  #  print MAIL "\n";

  #  $mytime = gmtime(time());
  #  print MAIL "$mytime\n";
  #  print MAIL "ncb socket is being closed, then reopened because no response was\n\n";
  #  print MAIL "received to an authorization request.\n";

  #  close(MAIL);
  #}

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  $tmpi      = 0;
  while ( $socketcnt >= 1 ) {
    $tmpi++;
    if ( $tmpi > 4 ) {
      $logfilestr .= "exiting program because socket couldn't be closed\n\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );
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
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/$devprod/ncb", "serverlogmsgtest2.txt", "append", "", $logfilestr );
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

  #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsgtest2.txt");
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

        #$bitmaphalfstr = pack "L", $bitmaphalf;
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

      #$bitmaphalfstr = pack "L", $bitmaphalf;
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

  #open(logfile,">>/home/pay1/batchfiles/$devprod/ncb/serverlogmsgtest2.txt");
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

sub mysqlmsgsnd {
  my ( $dbhhandle, $processid, $status, $invoicenum, $msg ) = @_;

  my ($encmsg) = &rsautils::rsa_encrypt_card( $msg, '/home/pay1/pwfiles/keys/key', 'log' );

  %datainfo = ( "processid", "$processid", "status", "$status", "invoicenum", "$invoicenum", "msg", "$encmsg" );
  my $dbquerystr = <<"dbEOM";
        update processormsg set status=?,invoicenum=?,message=?
        where processid=?
        and processor='ncbtest2'
        and status='locked'
dbEOM
  my @dbvalues = ( "$status", "$invoicenum", "$encmsg", "$processid" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

}

