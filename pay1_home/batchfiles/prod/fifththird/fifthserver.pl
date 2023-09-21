#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use IO::Socket;
use Socket;

#use Convert::EBCDIC (ascii2ebcdic, ebcdic2ascii);
use Encode qw(is_utf8 encode decode);

#require 'sys/ipc.ph';
#require 'sys/msg.ph';
use rsautils;
use PlugNPay::CreditCard;

$test    = "no";
$devprod = "logs";

$host = "processor-host";    # Source IP address

$testipaddress      = "192.152.100.99";     # test server
$testport           = "37901";              # test server
$primaryipaddress   = "192.152.100.119";    # primary server Cincinnati
$primaryport        = "11901";              # primary server
$secondaryipaddress = "204.90.6.117";       # secondary server Grand Rapids
$secondaryport      = "11701";              # secondary server

$primaryipaddress   = "64.57.148.119";      ## NEw Primary routed via IN 20100518
$secondaryipaddress = "204.90.2.117";       ## NEw Secondary routed via IN  20100518

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;

$nullmessage1 = "00040000";
$nullmessage2 = "00040000";

# xxxx
if ( $test eq "yes" ) {
  $ipaddress = $testipaddress;              # test server
  $port      = $testport;                   # test server
} elsif ( ( -e "/home/p/pay1/batchfiles/$devprod/fifththird/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
  print logfile "$mytime switching to secondary socket\n";
  close(logfile);
  $ipaddress = $secondaryipaddress;
  $port      = $secondaryport;
} elsif ( !( -e "/home/p/pay1/batchfiles/$devprod/fifththird/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
  print logfile "$mytime switching to primary socket\n";
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
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $fifththird::DBI::errstr", %datainfo );
$sth->execute()
  or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $fifththird::DBI::errstr", %datainfo );
$sth->finish;

$dbhmisc->disconnect;

# signon to fifththird
my $message = &networkmessage("001");
$message = &prepmessage($message);

&socketwrite($message);
&socketread($transcnt);

while (1) {
  $temptime = time();
  open( outfile, ">/home/p/pay1/batchfiles/$devprod/fifththird/accesstime.txt" );
  print outfile "$temptime\n";
  close(outfile);

  if ( ( -e "/home/p/pay1/batchfiles/$devprod/fifththird/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
    my $message = &networkmessage("002");
    $message = &prepmessage($message);
    &socketwrite($message);
    &socketread($transcnt);
    close(SOCK);
    sleep 1;
    exit;
  }

  $keepalivecnt++;
  if ( $keepalivecnt >= 240 ) {
    print "keepalivecnt = $keepalivecnt\n";
    $keepalivecnt = 0;

    my $message = &networkmessage("301");
    $message = &prepmessage($message);

    &socketwrite($message);
    &socketread($transcnt);

    $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
    if ( $socketcnt < 1 ) {
      print "socketcnt < 1\n";
      shutdown SOCK, 2;
      close(SOCK);
      $socketopenflag = 0;
      if ( $socketopenflag != 1 ) {
        $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
        $mytime    = gmtime( time() );
        open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
        print logfile "$mytime No ESTABLISHED\n";
        print logfile "$sockaddrport\n";
        print logfile "$sockettmp\n\n";
        close(logfile);
      }
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }
      $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
      print logfile "socket reopened\n";
      print logfile "$sockaddrport\n";
      print logfile "$sockettmp\n\n";
      close(logfile);
    }
  }

  # xxxx
  if ( $test eq "yes" ) {
    $ipaddress = $testipaddress;    # test server
    $port      = $testport;         # test server
  } elsif ( ( -e "/home/p/pay1/batchfiles/$devprod/fifththird/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
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
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
    print logfile "$mytime secondary socket opened\n";
    print logfile "$sockaddrport\n";
    print logfile "$sockettmp\n\n";
    close(logfile);
  } elsif ( !( -e "/home/p/pay1/batchfiles/$devprod/fifththird/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
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
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
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

  foreach $key ( keys %writearray ) {
    if ( $writearray{$key} < $ttime1 ) {
      delete $writearray{$key};
    }
  }

  $transcnt = 0;

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");

  my $sthmsg = $dbhmisc->prepare(
    qq{
        select trans_time,processid,username,orderid,message
        from processormsg
        where processor='fifththird'
        and status='pending'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $fifththird::DBI::errstr", %datainfo );
  $sthmsg->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $fifththird::DBI::errstr", %datainfo );
  $sthmsg->bind_columns( undef, \( $trans_time, $processid, $username, $orderid, $encmessage ) );

  while ( $sthmsg->fetch ) {
    $message = &rsautils::rsa_decrypt_file( $encmessage, "", "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

    if ( ( -e "/home/p/pay1/batchfiles/$devprod/fifththird/stopserver.txt" ) || ( -e "/home/pay1/stopfiles/stop_processors" ) ) {
      my $message = &networkmessage("002");
      $message = &prepmessage($message);
      &socketwrite($message);
      &socketread($transcnt);
      close(SOCK);
      sleep 1;
      exit;
    }

    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
    print logfile "aaaa $username $orderid select from processormsg\n";
    close(logfile);
    my $sth = $dbhmisc->prepare(
      qq{
          update processormsg set status='locked'
          where processid='$processid'
          and processor='fifththird'
          and status='pending'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $fifththird::DBI::errstr", %datainfo );
    $sth->execute()
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $fifththird::DBI::errstr", %datainfo );
    $sth->finish;

    #while (1) {}

    $username =~ s/[^0-9a-zA-Z_]//g;
    $orderid =~ s/[^0-9a-zA-Z_]//g;

    print "$mytime msgrcv $username $orderid\n";

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    $chkdelta = $now - $mytime;
    if ( $chkdelta > 60 ) {

      #  $msg = pack "N", $processid + 0;
      #  $msg = $msg . "failure: message timeout";
      #  &mysqlmsgsnd($dbhmisc,$processid,"failure","","failure: message timeout");
      #  if (msgsnd($msqidb, $msg, &IPC_NOWAIT) == NULL) {
      #    open(logfile,">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt");
      #    print logfile "a: snd failure $!\n";
      #    close(logfile);
      #    exit;
      #  }
      #  else {
      #    open(logfile,">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt");
      #    print logfile "a: snd success delta>60\n";
      #    close(logfile);
      #  }
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

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime = time();
    open( outfile, ">/home/p/pay1/batchfiles/$devprod/fifththird/accesstime.txt" );
    print outfile "$temptime\n";
    close(outfile);

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt > 12 ) {
      last;
    }
  }
  $sthmsg->finish;

  if ( $transcnt > 0 ) {
    $numtrans = $transcnt;
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
      if ( $delta > 120 ) {
        $message    = $smessage{"$rsequencenum"};
        $newmessage = "";

        if ( $message =~ /^....0100/ ) {
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

          #$message = &prepmessage($newmessage);
          $message = $newmessage;

          $getrespflag = 0;
          open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
          $temptime = gmtime( time() );
          print logfile "$susername{$rsequencenum}  $sorderid{$rsequencenum}  sending void\n";
          close(logfile);

          &socketwrite($message);
          $transcnt++;
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
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  shutdown SOCK, 2;
  close(SOCK);
  select undef, undef, undef, 1.00;

  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
  print logfile "socketopen attempt $addr $port\n";
  close(logfile);

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  #$iaddr = inet_aton($host);
  #my $sockaddr = sockaddr_in(0, $iaddr);
  #bind(SOCK, $sockaddr)    || die "bind: $!\n";
  connect( SOCK, $paddr ) || &mydie("connect: $addr $port $!");
  $socketopenflag = 1;

  $sockaddr    = getsockname(SOCK);
  $sockaddrlen = length($sockaddr);
  if ( $sockaddrlen == 16 ) {
    ($sockaddrport) = unpack_sockaddr_in($sockaddr);
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
    print logfile "$sockaddrport\n";
    print logfile "socketopen successful\n";
    close(logfile);
    $getrespflag = 1;
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }
}

sub mydie {
  my ($msg) = @_;

  print "$msg\n";
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
  print logfile "$msg\n\n";
  close(logfile);

  exit;
}

sub socketwrite {
  my ($message) = @_;
  print "in socketwrite\n";

  if ( $message !~ /^..\x08\x00/ ) {
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
      $xs = "x" x ( ( $cardnumlen + 1 ) / 2 );
      if ( $cardnumidx > 0 ) {
        $messagestr = substr( $message, 0, $cardnumidx ) . $xs . substr( $message, $cardnumidx + ( ( $cardnumlen + 1 ) / 2 ) );
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

    if ( $msgvalues[53] ne "" ) {         # ax cvv data
    }

    if ( $msgvalues[120] ne "" ) {        # cvv data
      $datalen = length( $msgvalues[120] );
      $dataidx = $msgvaluesidx[120];
      my $temp   = $msgvalues[120];
      my $newidx = 0;
      for ( my $newidx = 0 ; $newidx < $datalen ; ) {
        my $tag = substr( $temp, $newidx + 0, 2 );
        my $taglen = 0;
        if ( $tag eq "AV" ) {
          $taglen = 29;
        } elsif ( $tag eq "C2" ) {
          $taglen = 8;
        } else {
          last;
        }
        my $tagdata = substr( $temp, $newidx + 2, $taglen );
        if ( $tag eq "C2" ) {
          $cvv = $tagdata;
          if ( $tagdata =~ /^ [0-9]{3}1/ ) {
            $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 3 ) . 'xxx' . substr( $messagestr, $dataidx + $newidx + 3 + 3 );
          } elsif ( $tagdata =~ /^[0-9]{4}1/ ) {
            $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 2 ) . 'xxxx' . substr( $messagestr, $dataidx + $newidx + 2 + 4 );
          }
        }
        $newidx = $newidx + 2 + $taglen;
      }
    }

    $cardnum =~ s/ //g;

    #$xs = "x" x length($cardnum);
    #$messagestr = $message;
    #$messagestr =~ s/$cardnum/$xs/g;

    $cardnumber = $cardnum;

    #$sha1->reset;
    #$sha1->add($cardnumber);
    #$shacardnumber = $sha1->hexdigest();
    my $cc = new PlugNPay::CreditCard($cardnumber);
    $shacardnumber = $cc->getCardHash();

    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
    $checkmessage = $messagestr;
    $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
    $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
    $temptime = gmtime( time() );

    #$tempstr = unpack "H*", $message;
    my $mylen = length($message);
    if ( $ipaddress eq $primaryipaddress ) {
      print logfile "primary  $ipaddress $port\n";
    } else {
      print logfile "secondary  $ipaddress $port\n";
    }
    print logfile "$username  $orderid  $chkdelta\n";
    print logfile "$temptime send: $mylen $checkmessage  $shacardnumber\n\n";
    print "$temptime send: $mylen $checkmessage\n\n";
    print logfile "sequencenum: $sequencenum retries: $retries\n";
    close(logfile);
  }

  if ( $socketopenflag != 1 ) {
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
    print logfile "socketopenflag = 0, in socketwrite\n";
    close(logfile);
  }
  while ( $socketopenflag != 1 ) {
    &socketopen( "$ipaddress", "$port" );
  }
  $numbytes = send( SOCK, $message, 0, $paddr );

  #$numbytes = send(SOCK, $message . "\x00" x 400, 0, $paddr);

  #$checkmessage = $message;
  #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  #print "bbbb $username $numbytes $checkmessage\n\n";

  #open(logfile,">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt");
  #print logfile "$username $message\n\n";
  #close(logfile);
}

sub socketread {
  my ($numtries) = @_;

  print "in socketread\n";
  $donereadingflag = 0;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
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
    $mydelay = 1.0;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
    print logfile "in while\n";
    close(logfile);
    recv( SOCK, $response, 2048, 0 );

    if ( $response !~ /^....0810/ ) {

      #open(logfile,">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt");
      #$mytime = gmtime(time());
      #$checkmessage = $response;
      #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
      #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
      #print logfile "$mytime recva: $checkmessage\n";
      #print "recva: $mytime $checkmessage\n";
      #close(logfile);
    }

    $respdata = $respdata . $response;

    $resplength = unpack "n", substr( $respdata, 0 );

    #$resplength = substr($respdata,0,4);
    $resplength = $resplength + 2;
    $rlen       = length($respdata);
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
    print logfile "rlen: $rlen, resplength: $resplength\n";
    close(logfile);

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $nullresp = substr( $respdata, 2, 2 );
      $nullresp = unpack "H4", $nullresp;
      if ( $nullresp eq "0810" ) {
        $transcnt--;

        #if ($transcnt == 0) {
        $getrespflag = 1;

        #}
        $mytime = gmtime( time() );
        open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
        print logfile "null message found $mytime\n\n";
        print "null message found $mytime\n\n";
        close(logfile);
      } else {
        $transcnt--;

        #if ($transcnt == 0) {
        $getrespflag = 1;

        #}
        if ( $resplength == 4 ) {
        } elsif ( $respdata =~ /^....0420/ ) {
        } else {
          $response = substr( $respdata, 0, $resplength );
          &updatefifththird();
          delete $writearray{$rsequencenum};
        }
      }
      if ( !%writearray ) {
        $donereadingflag = 1;
      }
      $respdata = substr( $respdata, $resplength );
      $resplength = unpack "n", substr( $respdata, 0 );

      #$resplength = substr($respdata,0,4);
      $resplength = $resplength + 2;
      $rlen       = length($respdata);

      #my $tmpstr = unpack "H*", substr($respdata,0,20);
      #open(logfile,">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt");
      #print logfile "rlen: $rlen    resplength: $resplength    $tmpstr\n\n";
      #close(logfile);

      $temptime = time();
      open( outfile, ">/home/p/pay1/batchfiles/$devprod/fifththird/accesstime.txt" );
      print outfile "$temptime\n";
      close(outfile);
    }

    if ( $donereadingflag == 1 ) {
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
      print logfile "donereadingflag = 1\n";
      close(logfile);
      last;
    }

    $count--;
  }
  $delta = time() - $temp11;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
  print logfile "end loop $transcnt delta: $delta\n\n\n\n";
  close(logfile);

}

sub updatefifththird {
  ($invoiceloc) = &decodebitmap( $response, 11 );

  print "invoiceloc: $invoiceloc\n";

  $rsequencenum = substr( $response, $invoiceloc, 3 );
  $rsequencenum = unpack "H*", $rsequencenum;

  &decodebitmap($response);
  $messagestr = $response;
  if ( $msgvalues[2] ne "" ) {
    $cardnum    = $msgvalues[2];
    $cardnumidx = $msgvaluesidx[2];
    $cardnum =~ s/[^0-9]//g;
    $cardnumlen = length($cardnum);
    $xs = "x" x ( ( $cardnumlen + 1 ) / 2 );
    if ( $cardnumidx > 0 ) {
      $messagestr = substr( $messagestr, 0, $cardnumidx ) . $xs . substr( $messagestr, $cardnumidx + ( ( $cardnumlen + 1 ) / 2 ) );
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

  if ( $msgvalues[53] ne "" ) {         # ax cvv data
  }

  if ( $msgvalues[120] ne "" ) {        # cvv data
    $datalen = length( $msgvalues[120] );
    $dataidx = $msgvaluesidx[120];
    my $temp   = $msgvalues[120];
    my $newidx = 0;
    for ( my $newidx = 0 ; $newidx < $datalen ; ) {
      my $tag = substr( $temp, $newidx + 0, 2 );
      my $taglen = 0;
      if ( $tag eq "AV" ) {
        $taglen = 29;
      } elsif ( $tag eq "C2" ) {
        $taglen = 8;
      } else {
        last;
      }
      my $tagdata = substr( $temp, $newidx + 2, $taglen );
      if ( $tag eq "C2" ) {
        $cvv = $tagdata;
        if ( $tagdata =~ /^ [0-9]{3}1/ ) {
          $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 3 ) . 'xxx' . substr( $messagestr, $dataidx + $newidx + 3 + 3 );
        } elsif ( $tagdata =~ /^[0-9]{4}1/ ) {
          $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 2 ) . 'xxxx' . substr( $messagestr, $dataidx + $newidx + 2 + 4 );
        }
      }
      $newidx = $newidx + 2 + $taglen;
    }
  }

  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
  print logfile "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  close(logfile);
  my $mylen = length($response);
  $checkmessage = $messagestr;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  $temptime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
  print logfile "$temptime recv: $mylen $checkmessage\n";
  print "$temptime recv: $mylen $checkmessage\n";
  close(logfile);

  $sstatus{"$rsequencenum"} = "done";

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");
  $processid = $sprocessid{"$rsequencenum"};
  if ( &mysqlmsgsnd( $dbhmisc, $processid, "success", "$sinvoicenum{$rsequencenum}", "$response" ) == NULL ) { }
  $dbhmisc->disconnect;

  my $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
  print logfile "$mytime snd success $checktime\n";
  close(logfile);

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
  $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
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
  print MAIL "Subject: fifththird - no response to authorization\n";
  print MAIL "\n";

  print MAIL "fifththird socket is being closed, then reopened because no response was\n\n";
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

sub prepmessage {
  my ($message) = @_;

  $transcnt++;

  #$sequencenum = ($sequencenum + 1) % 255;
  #$sequencenum = sprintf("%012d", $sequencenum);
  #$message = substr($message,0,6) . $sequencenum . substr($message,18);
  #$message = substr($message,0,2) . $sequencenum . substr($message,14);

  $dbh = &miscutils::dbhconnect("pnpmisc");

  $username =~ s/[^0-9a-zA-Z_]//g;
  %datainfo = ( "username", "$username" );
  $sth1 = $dbh->prepare(
    qq{
          select username,invoicenum
          from fifththird
          where username='fifththird'
          }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth1->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $chkusername, $sequencenum ) = $sth1->fetchrow;
  $sth1->finish;

  $sequencenum = ( $sequencenum % 900000 ) + 1;

  if ( $chkusername eq "" ) {
    $sth = $dbh->prepare(
      qq{
            insert into fifththird
            (username,invoicenum)
            values (?,?)
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute( "fifththird", "$sequencenum" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sth->finish;
  } else {
    $sth = $dbh->prepare(
      qq{
            update fifththird set invoicenum=?
            where username='fifththird'
            }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute("$sequencenum") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sth->finish;
  }

  $dbh->disconnect;

  $sequencenum = sprintf( "%06d", $sequencenum + .0001 );
  print "sequencenum: $sequencenum\n";

  ($invoiceloc) = &decodebitmap( $message, 11 );

  print "invoiceloc: $invoiceloc\n";

  $sequencenum2 = pack "H6", $sequencenum;

  $message = substr( $message, 0, $invoiceloc ) . $sequencenum2 . substr( $message, $invoiceloc + 3 );

  return $message;
}

sub networkmessage {
  my ($mtype) = @_;

  @transaction = ();
  $transaction[0] = pack "H4",  '0800';                # message id (4n)
  $transaction[1] = pack "H16", "8220000000000000";    # primary bit map (8n)
  $transaction[2] = pack "H16", "0400000000000000";    # secondary bit map (8n) 1

  my ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = gmtime( time() );
  $lyear = substr( $lyear, -2, 2 );
  my $ltrandate = sprintf( "%02d%02d", $lmonth + 1, $lday );
  my $ltrantime = sprintf( "%02d%02d%02d", $lhour, $lmin, $lsec );
  $transaction[3] = pack "H4H6", $ltrandate, $ltrantime;    # transmission date/time (10n) 7
  $transaction[4] = pack "H6",   '000000';                  # system trace number (6n) 11
  $transaction[5] = pack "H4",   "0$mtype";                 # network management code 001=signon, 301=echo (3n) 70

  my $message = "";
  foreach $var (@transaction) {
    $message = $message . $var;
  }

  my $len = length($message);
  $len = pack "n", $len;
  $message = $len . $message;

  $checkmessage = $message;
  $checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
  print "$checkmessage\n";

  return $message;
}

sub decodebitmap {
  my ( $message, $findbit ) = @_;

  $bitlenarray[2]   = "LLVAR";
  $bitlenarray[3]   = 6;
  $bitlenarray[4]   = 12;
  $bitlenarray[5]   = 12;
  $bitlenarray[6]   = 12;
  $bitlenarray[7]   = 10;
  $bitlenarray[9]   = 8;
  $bitlenarray[10]  = 8;
  $bitlenarray[11]  = 6;
  $bitlenarray[12]  = 6;
  $bitlenarray[13]  = 4;
  $bitlenarray[14]  = 4;
  $bitlenarray[18]  = 4;
  $bitlenarray[19]  = 3;
  $bitlenarray[21]  = 3;
  $bitlenarray[22]  = 4;
  $bitlenarray[25]  = 2;
  $bitlenarray[32]  = "LLVAR";
  $bitlenarray[35]  = "LLVAR";
  $bitlenarray[37]  = "12a";
  $bitlenarray[38]  = "6a";
  $bitlenarray[39]  = "2a";
  $bitlenarray[41]  = "15a";
  $bitlenarray[42]  = "15a";
  $bitlenarray[43]  = "40a";
  $bitlenarray[44]  = "LLLVARa";
  $bitlenarray[45]  = "LLLVARa";
  $bitlenarray[48]  = "LLLVARa";
  $bitlenarray[49]  = 3;
  $bitlenarray[50]  = 3;
  $bitlenarray[51]  = 3;
  $bitlenarray[53]  = "LLVARa";
  $bitlenarray[54]  = "LLLVARa";
  $bitlenarray[57]  = "3a";
  $bitlenarray[59]  = "LLLVARa";
  $bitlenarray[60]  = "LLLVARa";
  $bitlenarray[61]  = "LLLVARa";
  $bitlenarray[62]  = "LLLVARa";
  $bitlenarray[63]  = "2a";
  $bitlenarray[70]  = 3;
  $bitlenarray[90]  = 42;
  $bitlenarray[95]  = "42a";
  $bitlenarray[120] = "LLLVARa";
  $bitlenarray[126] = "LLLVARa";

  my $idxstart = 4;                             # bitmap start point
  my $idx      = $idxstart;
  my $bitmap1  = substr( $message, $idx, 8 );
  my $bitmap   = unpack "H16", $bitmap1;
  print "\n\nbitmap1: $bitmap\n";
  $idx = $idx + 8;

  my $end     = 1;
  my $bitmap2 = "";
  if ( $bitmap =~ /^(8|9|a|b|c|d|e|f)/ ) {
    $bitmap2 = substr( $message, $idx, 8 );
    $bitmap = unpack "H16", $bitmap2;
    print "bitmap2: $bitmap\n";

    my $removebit = pack "H*", "7fffffffffffffff";
    $bitmap1 = $bitmap1 & $removebit;

    $end = 2;
    $idx = $idx + 8;
  }

  @msgvalues = ();
  my $myk           = 0;
  my $myi           = 0;
  my $bitnum        = 0;
  my $bitnum2       = 0;
  my $bigbitmaphalf = $bitmap1;
  my $wordflag      = 0;
  for ( $myj = 1 ; $myj <= $end ; $myj++ ) {
    my $bitmaphalfa = substr( $bigbitmaphalf, 0, 4 );
    my $bitmapa = unpack "N", $bitmaphalfa;

    my $bitmaphalfb = substr( $bigbitmaphalf, 4, 4 );
    my $bitmapb = unpack "N", $bitmaphalfb;

    my $bitmaphalf = $bitmapa;

    while ( $idx < length($message) ) {
      my $bit = 0;
      while ( ( $bit == 0 ) && ( $bitnum < 65 ) ) {
        if ( ( $bitnum == 33 ) || ( $bitnum == 97 ) ) {
          $bitmaphalf = $bitmapb;
        }
        if ( ( $bitnum == 33 ) || ( $bitnum == 65 ) || ( $bitnum == 97 ) ) {
          $wordflag++;
        }

        #$bit = ($bitmaphalf >> (128 - $bitnum)) % 2;
        #$bit = ($bitmaphalf >> (128 - ($wordflag*32) - $bitnum)) % 2;
        $bit = ( $bitmaphalf >> ( 32 - ( $bitnum - ( $wordflag * 32 ) ) ) ) % 2;
        $bitnum++;
        $bitnum2++;
      }
      if ( ( $bitnum == 65 ) && ( $bit == 0 ) ) {
        last;
      }

      my $tempstr = substr( $message, $idx, 8 );
      $tempstr = unpack "H*", $tempstr;

      #$bitmaphalfstr = pack "N", $bitmaphalf;
      #$bitmaphalfstr = unpack "H*", $bitmaphalfstr;
      #print "aaaa $tempstr    $bitmaphalfstr\n";

      my $idxold = $idx;

      my $idxlen1 = $bitlenarray[ $bitnum2 - 1 ];
      my $idxlen  = $idxlen1;
      if ( $idxlen1 eq "LLVAR" ) {
        $idxlen = substr( $message, $idx, 1 );
        $idxlen = unpack "C", $idxlen;
        $idxlen = int( ( $idxlen / 2 ) + .5 );
        $idx = $idx + 1;
      } elsif ( $idxlen1 eq "LLVARa" ) {
        $idxlen = substr( $message, $idx, 1 );
        $idxlen = unpack "C", $idxlen;
        $idx = $idx + 1;
      } elsif ( $idxlen1 eq "LLLVAR" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idxlen = unpack "n", $idxlen;
        $idxlen = int( ( $idxlen / 2 ) + .5 );
        $idx = $idx + 2;
      } elsif ( $idxlen1 eq "LLLVARa" ) {
        $idxlen = substr( $message, $idx, 2 );
        $idxlen = unpack "n", $idxlen;
        $idx = $idx + 2;
      } elsif ( $idxlen1 =~ /a/ ) {
        $idxlen =~ s/a//g;
      } else {
        $idxlen = int( ( $idxlen / 2 ) + .5 );
      }
      my $value = substr( $message, $idx, $idxlen );
      if ( $idxlen1 !~ /a/ ) {
        $value = unpack "H*", $value;
      } elsif ( $bitnum - 1 != 62 ) {

        #$value = &ebcdic2ascii($value);
        $value = &decode( "cp1047", $value );    # posix-bc  cp37  cp1047
      }

      $tmpbit = $bitnum2 - 1;

      #if ($findbit eq "") {
      #  print "bit: $idxold  $tmpbit  $idxlen1 $idxlen  $value\n";
      #}

      $msgvalues[$tmpbit]    = "$value";
      $msgvaluesidx[$tmpbit] = $idx;

      $myk++;
      if ( $myk > 30 ) {
        exit;
      }
      if ( ( $findbit ne "" ) && ( $findbit == $bitnum - 1 ) ) {
        return $idx, $value;
      }
      $idx = $idx + $idxlen;
      if ( $bitnum == 65 ) {
        last;
      }
    }
    $bitnum        = 0;
    $wordflag      = 0;
    $bitnum2       = $bitnum2 - 1;
    $bigbitmaphalf = $bitmap2;
  }    # end for
  print "\n";

  my $tempstr = unpack "H*", $message;
  print "$tempstr\n\n";

  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fifththird/serverlogmsg.txt" );
  for ( my $i = 0 ; $i <= $#msgvalues ; $i++ ) {
    if ( $msgvalues[$i] ne "" ) {
      if ( ( $i == 2 ) || ( $i == 35 ) || ( $i == 45 ) ) {
        my $tmpval = $msgvalues[$i];
        $tmpval =~ s/./x/g;
        print logfile "$i  $tmpval\n";
      } elsif ( $i == 126 ) {
        my $tmpval = unpack "H*", $msgvalues[$i];
        if ( length($tmpval) == 4 ) {

          #$tmpval = &ebcdic2ascii($msgvalues[$i]);
          $tmpval = &decode( "cp1047", $msgvalues[$i] );    # posix-bc  cp37  cp1047
        }
        print logfile "$i  $tmpval\n";
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
            if ( $tagdata =~ /^ [0-9]{3}1/ ) {
              $data = substr( $data, 0, $newidx + 3 ) . 'xxx' . substr( $data, $newidx + 3 + 3 );
            } elsif ( $tagdata =~ /^[0-9]{4}1/ ) {
              $data = substr( $data, 0, $newidx + 2 ) . 'xxxx' . substr( $data, $newidx + 2 + 4 );
            }
          }
          $newidx = $newidx + 2 + $taglen;
        }
        print logfile "$i  $data\n";
      } else {
        print logfile "$i  $msgvalues[$i]\n";
      }
    }
  }
  close(logfile);

  return -1, "";
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
        and processor='fifththird'
        and status='locked'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute( "$status", "$invoicenum" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth->finish;

}

