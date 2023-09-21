#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use procutils;
use smpsutils;
use IO::Socket;
use Socket;
use fdmsrctok;
use rsautils;
use PlugNPay::CreditCard;

$test    = "no";
$devprod = "logs";

$host               = "processor-host";     # Source IP address
$primaryipaddress   = "204.194.139.203";    # primary server
$primaryport        = "42020";              # primary server
$secondaryipaddress = "204.194.127.203";    # secondary server
$secondaryport      = "42020";              # secondary server
$testipaddress      = "167.16.0.125";       # test server
$testport           = "41020";              # test port

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;

$nullmessage1 = "aa77000d0011";
$nullmessage2 = "aa550d001100";

if ( $test eq "yes" ) {
  $ipaddress = $testipaddress;              # test server
  $port      = $testport;                   # test server emv testing
} elsif ( ( -e "/home/pay1/batchfiles/$devprod/fdmsrctok/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to secondary socket\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $secondaryipaddress;
  $port      = $secondaryport;
} elsif ( !( -e "/home/pay1/batchfiles/$devprod/fdmsrctok/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime switching to primary socket\n";
  $logfilestr .= "$sockaddrport\n";
  $logfilestr .= "$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
  $ipaddress = $primaryipaddress;
  $port      = $primaryport;
}

while ( $socketopenflag != 1 ) {
  &socketopen( "$ipaddress", "$port" );
  select undef, undef, undef, 2.00;
}

# delete rows older than 10 minutes
my $now     = time();
my $deltime = &miscutils::timetostr( $now - 600 );

my $dbquerystr = <<"dbEOM";
        delete from processormsg
        where processor='fdmsrctok'
          and (trans_time<?
          or trans_time is NULL
          or trans_time='')
dbEOM
my @dbvalues = ("$deltime");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

while (1) {
  $temptime   = time();
  $outfilestr = "";
  $outfilestr .= "$temptime\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "accesstime.txt", "write", "", $outfilestr );

  $keepalivecnt++;
  if ( $keepalivecnt >= 60 ) {
    my $printstr = "keepalivecnt = $keepalivecnt\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
    $keepalivecnt = 0;
    $socketcnt    = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
    if ( $socketcnt < 1 ) {
      my $printstr = "socketcnt < 1\n";
      &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
      shutdown SOCK, 2;

      $socketopenflag = 0;
      if ( $socketopenflag != 1 ) {
        $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
        ( $d1, $d2, $tmptime ) = &miscutils::genorderid();
        $logfilestr = "";
        $logfilestr .= "No ESTABLISHED $tmptime\n";
        $logfilestr .= "$sockaddrport\n";
        $logfilestr .= "$sockettmp\n\n";
        &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
      }
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }
      $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
      $logfilestr = "";
      $logfilestr .= "socket reopened\n";
      $logfilestr .= "$sockaddrport\n";
      $logfilestr .= "$sockettmp\n\n";
      &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
    }
  }

  if ( $test eq "yes" ) {
    $ipaddress = $testipaddress;    # test server
    $port      = $testport;         # test server emv testing
  } elsif ( ( -e "/home/pay1/batchfiles/$devprod/fdmsrctok/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to secondary socket\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

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
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
  } elsif ( !( -e "/home/pay1/batchfiles/$devprod/fdmsrctok/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "$sockettmp\n\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

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
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
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

  my $dbquerystr = <<"dbEOM";
        select trans_time,processid,username,orderid,message,status,response
        from processormsg
        where processor='fdmsrctok'
        and status in ('pending','success')
dbEOM
  my @dbvalues = ();
  my @sth1valarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  for ( my $vali = 0 ; $vali < scalar(@sth1valarray) ; $vali = $vali + 7 ) {
    ( $trans_time, $processid, $username, $orderid, $encmessage, $processormsgstatus, $encmsgresponse ) = @sth1valarray[ $vali .. $vali + 6 ];

    $message     = &rsautils::rsa_decrypt_file( $encmessage,     "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );
    $msgresponse = &rsautils::rsa_decrypt_file( $encmsgresponse, "", "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

    # void if transaction never removed from processormsg after 65 seconds
    if ( $processormsgstatus eq "success" ) {
      my $now    = time();
      my $mytime = &miscutils::strtotime($trans_time);
      my $delta  = $now - $mytime;
      if ( $delta > 65 ) {

        if ( $message =~ /<(Credit|Debit)Request/ ) {
          my $printstr = "msgstatus: $processormsgstatus\n";
          &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
          my $printstr = "msgstatus: $delta\n";
          &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

          &decodebitmap( $msgresponse, "", "no" );

          my $paymenttype = "";
          my $chopmessage = substr( $msgresponse, 12 );
          if ( $chopmessage =~ /^.*?<([a-zA-Z]+)Response>/ ) {
            $paymenttype = $1;
          }
          $responsetype = $paymenttype . "Response";

          my $messtype = $temparray{"GMF,$responsetype,CommonGrp,TxnType"};    # messtype
          my $respcode = $temparray{"GMF,$responsetype,RespGrp,RespCode"};     # bit 39
          my $printstr = "messtype: $messtype\n";
          &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
          my $printstr = "respcode: $respcode\n";
          &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
          my $printstr = "paymenttype: $paymenttype\n";
          &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
          if ( ( $paymenttype =~ /^(Credit|Debit)$/ ) && ( $respcode =~ /^(000|002|85)$/ ) ) {
            $rsequencenum = $sseqnum{"$username $orderid"};
            $respfield63  = $msgvalues[63];
            $message      = &voidmessage( $message, $username, $rsequencenum );
            &decodebitmap( $message, "", "no" );

            $checkmessage = $message;
            $checkmessage = &fdmsrctok::stripfields($checkmessage);
            $checkmessage =~ s/\x02/\[02\]/g;
            $checkmessage =~ s/\x03/\[03\]/g;
            $checkmessage =~ s/\x1c/\[1c\]/g;
            $checkmessage =~ s/></>\n</g;
            $temptime   = gmtime( time() );
            $logfilestr = "";
            $logfilestr .= "\nvoid message $username $orderid $trans_time $delta\n";
            $logfilestr .= "$temptime send: $checkmessage\n";
            my $printstr = "$temptime send: $checkmessage\n";
            &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok",  "miscdebug.txt",    "append", "misc", $printstr );
            &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "",     $logfilestr );

            $susername{$rsequencenum} = $username;
            $sorderid{$rsequencenum}  = $orderid;
            $sreason{$rsequencenum}   = "timeout";
            $smid{"$rsequencenum"}    = $temparray{"GMF,$requesttype,CommonGrp,MerchID"};
            $smid{"$rsequencenum"} =~ s/^0+//;
            $stid{"$rsequencenum"} = $temparray{"GMF,$requesttype,CommonGrp,TermID"};

            my $printstr = "rsequencenumaaaa: $rsequencenum\n";
            &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

            $transcnt++;
            &socketwrite($message);
            &socketread(4);
          }

          # permanent
          if (0) {

            my $dbquerystr = <<"dbEOM";
              update trans_log
              set finalstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and operation='auth'
              and finalstatus='success'
dbEOM
            my @dbvalues = ( "$orderid", "$username" );
            &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

            my $dbquerystr = <<"dbEOM";
              update operation_log
              set authstatus='problem',lastopstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and lastop='auth'
              and lastopstatus='success'
dbEOM
            my @dbvalues = ( "$orderid", "$username" );
            &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

          }

          my $dbquerystr = <<"dbEOM";
              delete from processormsg
              where processid=?
              and username=?
              and orderid=?
              and processor='fdmsrctok'
dbEOM
          my @dbvalues = ( "$processid", "$username", "$orderid" );
          &procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

          $logfilestr = "";
          $logfilestr .= "delete from processormsg $username $orderid\n";
          &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

        }
      }
      next;
    }

    my $dbquerystr = <<"dbEOM";
          update processormsg set status='locked'
          where processid=?
          and processor='fdmsrctok'
          and status='pending'
dbEOM
    my @dbvalues = ("$processid");
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $username =~ s/[^0-9a-zA-Z_]//g;
    $trans_time =~ s/[^0-9]//g;
    $orderid =~ s/[^0-9]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;

    my $printstr = "$mytime msgrcv $username $orderid\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

    my $now    = time();
    my $mytime = &miscutils::strtotime($trans_time);
    my $delta  = $now - $mytime;
    if ( $delta > 60 ) {
      &mysqlmsgsnd( $dbhmisc, $processid, "failure", "", "failure: message timeout" );
      next;
    }

    $transcnt++;

    &decodebitmap( $message, '', "no" );

    my $paymenttype = "";
    my $chopmessage = substr( $message, 12 );
    if ( $chopmessage =~ /^.*?<([a-zA-Z]+)Request>/ ) {
      $paymenttype = $1;
    }
    $requesttype  = $paymenttype . "Request";
    $responsetype = $paymenttype . "Response";

    if ( ( $temparray{"GMF,$requesttype,CommonGrp,STAN"} ne "000000" ) && ( $temparray{"GMF,$requesttype,CommonGrp,STAN"} ne "" ) ) {
      $sequencenum = $temparray{"GMF,$requesttype,CommonGrp,STAN"};      # bit 11
      $refnum      = $temparray{"GMF,$requesttype,CommonGrp,RefNum"};    # bit 37

      %datainfo = ( "username", "$username" );
      my $dbquerystr = <<"dbEOM";
            select username,invoicenum
            from fdmsemv
            where username=?
dbEOM
      my @dbvalues = ("$username");
      ( $chkusername, $chkinvoicenum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      $logfilestr = "";
      $logfilestr .= "a $username $requesttype  invoicenum: $sequencenum  $chkinvoicenum\n";
      &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

      if ( ( $sequencenum > $chkinvoicenum ) || ( ( $chkinvoicenum > 99998 ) && ( $sequencenum < 100000 ) ) ) {
        if ( $chkusername eq "" ) {
          my $dbquerystr = <<"dbEOM";
                insert into fdmsemv
                (username,invoicenum)
                values (?,?)
dbEOM

          my %inserthash = ( "username", "$username", "invoicenum", "$sequencenum" );
          &procutils::dbinsert( $username, $orderid, "pnpmisc", "fdmsemv", %inserthash );

        } else {
          my $dbquerystr = <<"dbEOM";
                update fdmsemv set invoicenum=?
                where username=?
dbEOM
          my @dbvalues = ( "$sequencenum", "$username" );
          &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

        }
      }
    } else {

      %datainfo = ( "username", "$username" );
      my $dbquerystr = <<"dbEOM";
            select username,invoicenum
            from fdmsemv
            where username=?
dbEOM
      my @dbvalues = ("$username");
      ( $chkusername, $invoicenum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      $invoicenum = ( $invoicenum + 1 ) % 99999;

      if ( $chkusername eq "" ) {
        my $dbquerystr = <<"dbEOM";
              insert into fdmsemv
              (username,invoicenum)
              values (?,?)
dbEOM

        my %inserthash = ( "username", "$username", "invoicenum", "$invoicenum" );
        &procutils::dbinsert( $username, $orderid, "pnpmisc", "fdmsemv", %inserthash );

      } else {
        my $dbquerystr = <<"dbEOM";
              update fdmsemv set invoicenum=?
              where username=?
dbEOM
        my @dbvalues = ( "$invoicenum", "$username" );
        &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

      }

      $sequencenum = sprintf( "%06d", $invoicenum );

      $logfilestr = "";
      $logfilestr .= "b $username invoicenum: $invoicenum  $sequencenum\n";
      &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
      $message =~ s/<STAN>(.*)<\/STAN>/<STAN>$sequencenum<\/STAN>/;

      $refnum = $temparray{"GMF,$requesttype,CommonGrp,RefNum"};    # bit 37
      if ( ( $refnum eq "000000000000" ) || ( $refnum eq "" ) ) {
        $message =~ s/<OrderNum>(.*)<\/OrderNum>/<OrderNum>00$sequencenum<\/OrderNum>/;

        $tidstr = substr( $temparray{"GMF,$requesttype,CommonGrp,TermID"}, -2, 2 );    # bit 41
        $refnum = '0000' . $tidstr . $sequencenum;
        $refnum = substr( "0" x 12 . $refnum, -12, 12 );
        $message =~ s/<RefNum>(.*)<\/RefNum>/<RefNum>$refnum<\/RefNum>/;

      }
    }

    &decodebitmap($message);

    my $mtmid = $temparray{"GMF,$requesttype,CommonGrp,MerchID"};
    $mtmid =~ s/^0+//;
    my $mtsequencenum = $mtmid . " " . $temparray{"GMF,$requesttype,CommonGrp,TermID"} . " " . $sequencenum;
    $susername{"$mtsequencenum"}   = $username;
    $sseqnum{"$username $orderid"} = $mtsequencenum;
    $strans_time{"$mtsequencenum"} = $trans_time;
    $smessage{"$mtsequencenum"}    = $message;
    $sretries{"$mtsequencenum"}    = 1;
    $sorderid{"$mtsequencenum"}    = $orderid;
    $sprocessid{"$mtsequencenum"}  = $processid;
    $sreason{"$mtsequencenum"}     = "";
    $sinvoicenum{"$mtsequencenum"} = $invoicenum;
    $srefnum{"$mtsequencenum"}     = $refnum;

    $smid{"$mtsequencenum"} = $temparray{"GMF,$requesttype,CommonGrp,MerchID"};
    $smid{"$mtsequencenum"} =~ s/^0+//;
    $stid{"$mtsequencenum"} = $temparray{"GMF,$requesttype,CommonGrp,TermID"};

    if ( $message =~ /<TrnmsnDateTime>([0-9]+)<\/TrnmsnDateTime>/ ) {
      $trandatetime = $1;
      $sdatetime{"$mtsequencenum"} = $trandatetime;
    }
    if ( $message =~ /<LocalDateTime>([0-9]+)<\/LocalDateTime>/ ) {
      $localdatetime = $1;
      $sldatetime{"$mtsequencenum"} = $localdatetime;
    }

    $scardtype{"$mtsequencenum"} = "";

    $cardnum = $temparray{"GMF,$requesttype,CardGrp,AcctNum"};    # bit 2
    if ( $cardnum eq "" ) {
      $cardnum = $temparray{"GMF,$requesttype,CardGrp,Track2Data"};    # bit 35
    }
    if ( $cardnum eq "" ) {
      $cardnum = $temparray{"GMF,$requesttype,CardGrp,Track1Data"};    # bit 45
    }
    $xs = "x" x length($cardnum);

    $messagestr = $message;

    if ( $cardnum ne "" ) {
      $cardnumbin = pack "H*", $cardnum;
      $myidx = index( $messagestr, $cardnumbin );
      if ( $myidx > 0 ) {
        $xs3  = "x" x length($cardnumbin);
        $len3 = length($cardnumbin);

      }
    }

    if ( $messagestr =~ /\#0131(.*)?\#/ ) {
      $cvv = $1;
      $cvv =~ s/ //;
      $xs = "x" x length($cvv);

    } elsif ( $messagestr =~ /\@0131(.*)?\#/ ) {
      $cvv = $1;
      $cvv =~ s/ //;
      $xs = "x" x length($cvv);

    }

    my $cc = new PlugNPay::CreditCard($cardnumber);
    $shacardnumber = $cc->getCardHash();

    $checkmessage = $messagestr;
    $checkmessage = &fdmsrctok::stripfields($checkmessage);
    $checkmessage =~ s/\x02/\[02\]/g;
    $checkmessage =~ s/\x03/\[03\]/g;
    $checkmessage =~ s/\x1c/\[1c\]/g;
    $checkmessage =~ s/></>\n</g;
    $temptime = gmtime( time() );

    $logfilestr = "";
    $logfilestr .= "$username  $orderid\n";
    $logfilestr .= "$temptime send: $checkmessage  $shacardnumber\n\n";
    $logfilestr .= "sequencenum: $mtsequencenum retries: $retries\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime   = time();
    $outfilestr = "";
    $outfilestr .= "$temptime\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "accesstime.txt", "write", "", $outfilestr );

    $writearray{$mtsequencenum} = $trans_time;

    if ( $transcnt > 6 ) {
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

      if ( ( $delta > 240 ) && ( ( $smessage{"$rsequencenum"} !~ /<(Credit|Debit)Request/ ) || ( $scardtype{"$rsequencenum"} eq "interac" ) ) ) {
        delete $susername{$rsequencenum};
        delete $strans_time{$rsequencenum};
        delete $smessage{$rsequencenum};
        delete $sretries{$rsequencenum};
        delete $sorderid{$rsequencenum};
        delete $smid{$rsequencenum};
        delete $stid{$rsequencenum};
        delete $srefnum{$rsequencenum};
        delete $sreason{$rsequencenum};
        delete $sprocessid{$rsequencenum};
        delete $sinvoicenum{$rsequencenum};
        delete $scardtype{$rsequencenum};
        delete $sdatetime{$rsequencenum};
        delete $sldatetime{$rsequencenum};
      } elsif ( $delta > 40 ) {

        my $tmpstr = $smessage{$rsequencenum};
        $tmpstr = unpack "H*", $tmpstr;
        my $tmpstr2 = substr( $tmpstr, 0, 160 );
        my $chkstr1 = unpack "H*", "<TxnType>Authorization</TxnType>";
        my $chkstr2 = unpack "H*", "<TxnType>Sale</TxnType>";
        my $chkstr3 = unpack "H*", "<TxnType>Refund</TxnType>";
        my $printstr = "about to compare message and Authorization Sale or Refund $tmpstr2\n";
        &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

        if ( ( $delta < 180 ) && ( $tmpstr =~ /($chkstr1|$chkstr2|$chkstr3)/ ) ) {    # void all messages
          if ( ( ( $delta > 40 ) && ( $sretries{"$rsequencenum"} < 2 ) )
            || ( ( $delta > 80 )  && ( $sretries{"$rsequencenum"} < 3 ) )
            || ( ( $delta > 120 ) && ( $sretries{"$rsequencenum"} < 4 ) ) ) {
            $sretries{"$rsequencenum"}++;
            my $printstr = "comparison passed\n";
            &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
            $respfield63 = "";
            $message = &voidmessage( $smessage{$rsequencenum}, $susername{$rsequencenum}, $rsequencenum );

            &decodebitmap($message);

            $checkmessage = $message;
            $checkmessage = &fdmsrctok::stripfields($checkmessage);

            $checkmessage =~ s/\x02/\[02\]/g;
            $checkmessage =~ s/\x03/\[03\]/g;
            $checkmessage =~ s/\x1c/\[1c\]/g;
            $checkmessage =~ s/></>\n</g;
            $temptime   = gmtime( time() );
            $logfilestr = "";
            $logfilestr .= "\nvoid message\n";
            $logfilestr .= "$temptime send: $checkmessage\n";
            my $printstr = "$temptime send: $checkmessage\n";
            &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok",  "miscdebug.txt",    "append", "misc", $printstr );
            &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "",     $logfilestr );

            $transcnt++;
            &socketwrite($message);
            &socketread(4);
            $keepalive = 0;
          }
        } else {
          delete $susername{$rsequencenum};
          delete $strans_time{$rsequencenum};
          delete $smessage{$rsequencenum};
          delete $sretries{$rsequencenum};
          delete $sorderid{$rsequencenum};
          delete $smid{$rsequencenum};
          delete $stid{$rsequencenum};
          delete $srefnum{$rsequencenum};
          delete $sreason{$rsequencenum};
          delete $sprocessid{$rsequencenum};
          delete $sinvoicenum{$rsequencenum};
          delete $scardtype{$rsequencenum};
          delete $sdatetime{$rsequencenum};
          delete $sldatetime{$rsequencenum};
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

  $logfilestr = "";
  $logfilestr .= "socketopen attempt $addr $port\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  connect( SOCK, $paddr ) || &socketopen2( $secondaryipaddress, $secondaryport, "connect: $!" );

  $socketopenflag = 1;

  $sockaddr    = getsockname(SOCK);
  $sockaddrlen = length($sockaddr);
  if ( $sockaddrlen == 16 ) {
    ($sockaddrport) = unpack_sockaddr_in($sockaddr);
    $logfilestr = "";
    $logfilestr .= "$sockaddrport\n";
    $logfilestr .= "socketopen successful\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
    $getrespflag = 1;
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }
}

sub socketopen2 {
  my ( $addr, $port, $errmsg ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen failed  $errmsg\n";
  $logfilestr .= "$mytime socketopen attempt secondary $addr  $port\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  connect( SOCK, $paddr ) || die "connect: $addr $port $!";

  $logfilestr = "";
  $logfilestr .= "socketopen successful secondary\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

  $socketopenflag = 1;
}

sub socketwrite {
  my ($message) = @_;
  my $printstr = "in socketwrite\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

  if ( $socketopenflag != 1 ) {
    $logfilestr = "";
    $logfilestr .= "socketopenflag = 0, in socketwrite\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
  }
  while ( $socketopenflag != 1 ) {
    &socketopen( "$ipaddress", "$port" );
  }
  send( SOCK, $message, 0, $paddr );

}

sub socketread {
  my ($numtries) = @_;

  my $printstr = "in socketread\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

  $temp11 = time();
  vec( $rin, fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $respdata = "";
  $mydelay  = 30.0;
  while ( $count && select( $rout = $rin, undef, undef, $mydelay ) ) {
    my $printstr = "in while\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
    $mydelay    = 5.0;
    $logfilestr = "";
    $logfilestr .= "while\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
    recv( SOCK, $response, 2048, 0 );
    $tempstr = unpack "H*", $response;
    my $printstr = "aaaa $tempstr\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

    $respdata = $respdata . $response;

    $resplength = unpack "n", substr( $respdata, 4 );
    $resplength = $resplength + 10;
    $rlen       = length($respdata);
    $logfilestr = "";
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $transcnt--;

      $getrespflag = 1;

      $response = substr( $respdata, 0, $resplength );
      &updatefdmsrctok();
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
      &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "accesstime.txt", "write", "", $outfilestr );
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
      last;
    }

    $count--;
  }
  $delta      = time() - $temp11;
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt delta: $delta\n\n\n\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

}

sub updatefdmsrctok {
  my $printstr = "in updatefdmsrctok\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

  &decodebitmap($response);

  my $paymenttype = "";
  my $chopmessage = substr( $response, 12 );
  $responsetype = $paymenttype . "Response";
  if ( $chopmessage =~ /RejectResponse/s ) {
    if ( $chopmessage =~ /^.*?<([a-zA-Z]+)Request>/s ) {
      $paymenttype = $1;
    }
    $rejectrespflag = 1;
    $responsetype   = "RejectResponse,GMF," . $paymenttype . "Request";
  } elsif ( $chopmessage =~ /^.*?<([a-zA-Z]+)Response>/s ) {
    $paymenttype  = $1;
    $responsetype = $paymenttype . "Response";
  }
  my $printstr = "responsetype: $responsetype\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

  $rsequencenum = $temparray{"GMF,$responsetype,CommonGrp,STAN"};      # bit 11
  $mid          = $temparray{"GMF,$responsetype,CommonGrp,MerchID"};
  $mid =~ s/^0+//;
  $tid = $temparray{"GMF,$responsetype,CommonGrp,TermID"};

  if ( $rsequencenum eq "" ) {

    # in case of reject response
    # GMF,RejectResponse,GMF,CreditRequest,CommonGrp,MerchID

    my $requesttype = "CreditRequest";
    $mid = $temparray{"GMF,RejectResponse,GMF,CreditRequest,CommonGrp,MerchID"};
    if ( $mid eq "" ) {
      $mid         = $temparray{"GMF,RejectResponse,GMF,DebitRequest,CommonGrp,MerchID"};
      $requesttype = "DebitRequest";
    }
    if ( $mid eq "" ) {
      $mid         = $temparray{"GMF,RejectResponse,GMF,TransArmorRequest,CommonGrp,MerchID"};
      $requesttype = "TransArmorRequest";
    }
    $mid =~ s/^0+//;

    $tid          = $temparray{"GMF,RejectResponse,GMF,$requesttype,CommonGrp,TermID"};
    $rsequencenum = $temparray{"GMF,RejectResponse,GMF,$requesttype,CommonGrp,STAN"};     # bit 11

  }

  if ( $rsequencenum eq "" ) {

    # generic error message does not have a STAN, merchant id, or terminal id
    my $chkrefnum = $temparray{"GMF,$responsetype,CommonGrp,RefNum"};
    if ( $chkrefnum ne "" ) {
      my $foundcnt = 0;
      foreach my $mkey ( sort keys %strans_time ) {
        if ( $srefnum{"$mkey"} eq $chkrefnum ) {
          $foundcnt++;
          ( $mid, $tid, $rsequencenum ) = split( / /, $mkey );
        }
      }
      if ( $foundcnt > 1 ) {
        $rsequencenum eq "";
      }
    }
    my $printstr = "aaaa rseq: $rsequencenum\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
  }

  $mid =~ s/^0+//;
  my $mtrsequencenum = $mid . " " . $tid . " " . $rsequencenum;
  my $printstr       = "mtrseq: $mtrsequencenum\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

  if ( $response =~ /<ReversalResponse>/ ) {

    #return;	# for testing voidmessage

    my $username = $susername{$mtrsequencenum};
    my $orderid  = $sorderid{$mtrsequencenum};
    my $mid      = $smid{$mtrsequencenum};
    my $tid      = $stid{$mtrsequencenum};
    my $reason   = $sreason{$mtrsequencenum};
    my $printstr = "rseqbbbb: $mtrsequencenum\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "username: $username\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
    my $printstr = "orderid: $orderid\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

    if ( ( $username ne "" ) && ( $orderid ne "" ) && ( $reason eq "timeout" ) ) {

      my $dbquerystr = <<"dbEOM";
              update trans_log
              set finalstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and operation='auth'
              and finalstatus='success'
dbEOM
      my @dbvalues = ( "$orderid", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

      my $dbquerystr = <<"dbEOM";
              update operation_log
              set authstatus='problem',lastopstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and lastop='auth'
              and lastopstatus='success'
dbEOM
      my @dbvalues = ( "$orderid", "$username" );
      &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

    }

  }

  $logfilestr = "";
  $logfilestr .= "sequencenum: $mtrsequencenum, transcnt: $transcnt\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
  $checkmessage = $response;
  $checkmessage = substr( $checkmessage, 6 );
  $checkmessage = substr( $checkmessage, 0, length($response) - 4 );

  $checkmessage =~ s/\x02/\[02\]/g;
  $checkmessage =~ s/\x03/\[03\]/g;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/></>\n</g;
  my $mylen = length($response);
  $temptime   = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$temptime recv: $mylen $checkmessage\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );

  foreach my $seqkey ( sort keys %sorderid ) {
    my $printstr = "$seqkey    $smid{$seqkey}    $stid{$seqkey}\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
  }

  $mid =~ s/^0+//;
  my $printstr = "mt: $mtrsequencenum    mid: $mid  $smid{$mtrsequencenum}    tid: $tid  $stid{$mtrsequencenum}\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
  if ( ( $mtrsequencenum ne "" ) && ( $mid eq $smid{"$mtrsequencenum"} ) && ( $tid eq $stid{"$mtrsequencenum"} ) ) {
    my $printstr = "done\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
    $sstatus{"$mtrsequencenum"} = "done";

    $processid = $sprocessid{"$mtrsequencenum"};
    if ( &mysqlmsgsnd( $dbhmisc, $processid, "success", "", "$response" ) == NULL ) { }

    my $mytime = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime snd success $checktime\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "bbserverlogmsg.txt", "append", "", $logfilestr );

    delete $susername{$mtrsequencenum};
    delete $strans_time{$mtrsequencenum};
    delete $smessage{$mtrsequencenum};
    delete $sretries{$mtrsequencenum};
    delete $sorderid{$mtrsequencenum};
    delete $smid{$mtrsequencenum};
    delete $stid{$mtrsequencenum};
    delete $srefnum{$mtrsequencenum};
    delete $sprocessid{$mtrsequencenum};
    delete $sreason{$mtrsequencenum};
    delete $sinvoicenum{$mtrsequencenum};
    delete $scardtype{$mtrsequencenum};
    delete $sdatetime{$mtsequencenum};
    delete $sldatetime{$mtsequencenum};
  }

}

sub socketclose {
  $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
  $logfilestr = "";
  $sockettmp  = `netstat -n | grep $port | grep -v TIME_WAIT`;
  ( $d1, $d2, $temp ) = &miscutils::genorderid();
  $logfilestr .= "before socket is closed because of no response $temp\n$sockaddrport\n$sockettmp\n\n";

  shutdown SOCK, 2;

  $socketopenflag = 0;
  $getrespflag    = 1;

  open( MAIL, "| /usr/lib/sendmail -t" );
  print MAIL "To: cprice\@plugnpay.com\n";
  print MAIL "From: dprice\@plugnpay.com\n";
  print MAIL "Subject: fdmsrctok - no response to authorization\n";
  print MAIL "\n";

  print MAIL "fdmsrctok socket is being closed, then reopened because no response was\n\n";
  print MAIL "received to an authorization request.\n";

  close(MAIL);

  $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  $tmpi      = 0;
  while ( $socketcnt >= 1 ) {
    $tmpi++;
    if ( $tmpi > 4 ) {
      $logfilestr .= "exiting program because socket couldn't be closed\n\n";
      &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
      exit;
    }
    shutdown SOCK, 2;

    select( undef, undef, undef, 0.5 );
    $socketcnt = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
  }

  shutdown SOCK, 2;

  $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
  ( $d1, $d2, $temp ) = &miscutils::genorderid();
  $logfilestr .= "socket closed because of no response $temp\n$sockaddrport\n$sockettmp\n\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
}

sub decodebitmap {
  my ( $message, $findbit, $logflag ) = @_;

  my $chkmessage = $message;
  $chkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
  $chkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;

  my $data = $message;
  $data =~ s/\r{0,1}\n//g;
  $data =~ s/></>;;;;</g;
  my @tmpfields = split( /;;;;/, $data );
  %temparray = ();
  my $levelstr = "";
  foreach my $var (@tmpfields) {

    if ( $var =~ /<\!/ ) {
    } elsif ( $var =~ /<\?/ ) {
    } elsif ( $var =~ /<(.+)>(.*)</ ) {
      my $var2 = $1;
      my $var3 = $2;
      $var2 =~ s/ .*$//;
      if ( $temparray{"$levelstr$var2"} eq "" ) {
        $temparray{"$levelstr$var2"} = $var3;
      } else {
        $temparray{"$levelstr$var2"} = $temparray{"$levelstr$var2"} . "," . $var3;
      }
    } elsif ( $var =~ /<\/(.+)>/ ) {
      $levelstr =~ s/,[^,]*?,$/,/;
    } elsif ( ( $var =~ /<(.+)>/ ) && ( $var !~ /<\?/ ) && ( $var !~ /\/>/ ) ) {
      my $var2 = $1;
      $var2 =~ s/ .*$//;
      $levelstr = $levelstr . $var2 . ",";
    }
  }

  foreach my $key ( sort keys %temparray ) {
    my $printstr = "aa $key    bb $temparray{$key}\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
  }

  return %temparray;
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

sub mysqlmsgsnd {
  my ( $dbhhandle, $processid, $status, $invoicenum, $msg ) = @_;

  my ($encmsg) = &rsautils::rsa_encrypt_card( $msg, '/home/pay1/pwfiles/keys/key', 'log' );

  if ( length($encdata) > 3600 ) {
    open( MAIL, "| /usr/lib/sendmail -t" );
    print MAIL "To: cprice\@plugnpay.com\n";
    print MAIL "From: dprice\@plugnpay.com\n";
    print MAIL "Subject: fdmsrctok - response too large\n";
    print MAIL "\n";

    my $encdatalen = length($encdata);

    print MAIL "fdmsrctok response is too large for processormsg.  $encdatalen\n\n";
    print MAIL "invoicenum: $invoicenum\n\n";

    close(MAIL);
  } else {
    %datainfo = ( "processid", "$processid", "status", "$status", "invoicenum", "$invoicenum", "msg", "$encmsg" );
    my $dbquerystr = <<"dbEOM";
          update processormsg set status=?,invoicenum=?,response=?
          where processid=?
          and processor='fdmsrctok'
          and status='locked'
dbEOM
    my @dbvalues = ( "$status", "$invoicenum", "$encmsg", "$processid" );
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  }

}

sub voidmessage {
  my ( $message, $usernm, $rsequencenum ) = @_;

  my $printstr = "in voidmessage\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

  $message = substr( $message, 6 );
  $message = substr( $message, 0, length($message) - 4 );

  my $printstr = "origmessage: $message\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

  my %msgarray = &decodebitmap($message);

  $time = time();
  local ( $sec,  $min,  $hour,  $day,  $month,  $year,  $wday, $yday, $isdst ) = gmtime($time);
  local ( $lsec, $lmin, $lhour, $lday, $lmonth, $lyear, $wday, $yday, $isdst ) = localtime($time);

  my $paymenttype = "";
  my $chopmessage = substr( $message, 12 );
  if ( $chopmessage =~ /^.*?<([a-zA-Z]+)Request>/ ) {
    $paymenttype = $1;
  }
  $requesttype  = $paymenttype . "Request";
  $responsetype = $paymenttype . "Response";

  $message =~ s/<TxnType>(.*?)<\/TxnType>/<ReversalInd>Timeout<\/ReversalInd><TxnType>Authorization<\/TxnType>/;
  $message =~ s/$requesttype>/ReversalRequest>/g;

  if ( $msgarray{"GMF,$requesttype,CardGrp,Track2Data"} ne "" ) {
    my ( $val1, $val2 ) = split( /=/, $msgarray{"GMF,$requesttype,CardGrp,Track2Data"} );
    my $year  = substr( $val2, 0, 2 );
    my $month = substr( $val2, 2, 2 );
    $message =~ s/<Track2Data>(.*?)<\/Track2Data>/<AcctNum>$val1<\/AcctNum><CardExpiryDate>20$year$month<\/CardExpiryDate>/;
  } elsif ( $msgarray{"GMF,$requesttype,CardGrp,Track1Data"} ne "" ) {
    my ( $val1, $val2, $val3 ) = split( /\^/, $msgarray{"GMF,$requesttype,CardGrp,Track1Data"} );
    my $year  = substr( $val3, 0, 2 );
    my $month = substr( $val3, 2, 2 );
    $val1 =~ s/B//;
    $message =~ s/<Track1Data>(.*?)<\/Track1Data>/<CardNum>$val1<\/CardNum><CardExpiryDate>20$year$month<\/CardExpiryDate>/;
  }

  $message =~ s/<CCVInd>(.*?)<\/CCVInd>//;
  $message =~ s/<CCVData>(.*?)<\/CCVData>//;

  my $td = "";
  $td .= "<OrigAuthGrp>";

  my $trandatetime = "";
  if ( $message =~ /<TrnmsnDateTime>([0-9]+)<\/TrnmsnDateTime>/ ) {
    $trandatetime = $1;

    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() );
    my $gmttime = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
    $message =~ s/<TrnmsnDateTime>([0-9]+)<\/TrnmsnDateTime>/<TrnmsnDateTime>$gmttime<\/TrnmsnDateTime>/;
  }

  if ( $message =~ /<LocalDateTime>([0-9]+)<\/LocalDateTime>/ ) {
    $trandatetime = $1;

    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
    my $localtime = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
    $message =~ s/<LocalDateTime>([0-9]+)<\/LocalDateTime>/<LocalDateTime>$localtime<\/LocalDateTime>/;
  }

  my $stan = "";
  if ( $message =~ /<STAN>([0-9]+)<\/STAN>/ ) {

    my $printstr = "update invoicenum $rsequencenum $usernm\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

    %datainfo = ( "username", "$usernm" );
    my $dbquerystr = <<"dbEOM";
          select username,invoicenum
          from fdmsemv
          where username=?
dbEOM
    my @dbvalues = ("$usernm");
    ( $chkusername, $invoicenum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $invoicenum = ( $invoicenum + 1 ) % 99999;

    my $dbquerystr = <<"dbEOM";
          update fdmsemv set invoicenum=?
          where username=?
dbEOM
    my @dbvalues = ( "$invoicenum", "$usernm" );
    &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

    $sequencenum = sprintf( "%06d", $invoicenum );
    $logfilestr = "";
    $logfilestr .= "b $rsequencenum $susername{$rsequencenum} invoicenum: $invoicenum  $sequencenum\n";
    foreach my $key ( sort keys %sldatetime ) {
      $logfilestr .= "sldatetime: $key  $sldatetime{$key}\n";
    }
    $logfilestr .= "origstan: $sinvoicenum{$rsequencenum}  stan: $sequencenum  refnum: $refnum\n";
    &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/$devprod/fdmsrctok", "serverlogmsg.txt", "append", "", $logfilestr );
    $message =~ s/<STAN>(.*)<\/STAN>/<STAN>$sequencenum<\/STAN>/;

  }

  $td .= "<OrigLocalDateTime>$sldatetime{$rsequencenum}</OrigLocalDateTime>";
  $td .= "<OrigTranDateTime>$sdatetime{$rsequencenum}</OrigTranDateTime>";
  $stan = $sinvoicenum{$rsequencenum};
  $stan = sprintf( "%06d", $stan );
  $td .= "<OrigSTAN>$stan</OrigSTAN>";

  $td .= "</OrigAuthGrp>";
  $message =~ s/<\/ReversalRequest>/$td<\/ReversalRequest>/;

  my $head = pack "H8", "02464402";
  my $tail = pack "H8", "03464403";
  my $length = length($message) + 0;
  my $tcpheader = pack "n", $length;
  $message = $head . $tcpheader . $message . $tail;

  my $mtsequencenum = $smid{$rsequencenum} . " " . $stid{$rsequencenum} . " " . $sequencenum;
  $susername{$mtsequencenum}   = $susername{$rsequencenum};
  $strans_time{$mtsequencenum} = $strans_time{$rsequencenum};
  $smessage{$mtsequencenum}    = $smessage{$rsequencenum};
  $sretries{$mtsequencenum}    = $sretries{$rsequencenum};
  $sorderid{$mtsequencenum}    = $sorderid{$rsequencenum};
  $smid{$mtsequencenum}        = $smid{$rsequencenum};
  $stid{$mtsequencenum}        = $stid{$rsequencenum};
  $srefnum{$mtsequencenum}     = $srefnum{$rsequencenum};
  $sprocessid{$mtsequencenum}  = $sprocessid{$rsequencenum};
  $sreason{$mtsequencenum}     = $sreason{$rsequencenum};
  $sinvoicenum{$mtsequencenum} = $sinvoicenum{$rsequencenum};
  $scardtype{$mtsequencenum}   = $scardtype{$rsequencenum};
  $sdatetime{$mtsequencenum}   = $sdatetime{$rsequencenum};
  $sldatetime{$mtsequencenum}  = $sldatetime{$rsequencenum};
  $snewstan{$mtsequencenum}    = $sequencenum;
  my $printstr = "mmmm $rsequencenum\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
  my $printstr = "mmmm $mtsequencenum\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );
  my $tmpstr = substr( $smessage{"$mtsequencenum"}, 0, 80 );
  my $printstr = "nnnn $tmpstr\n";
  &procutils::filewrite( "$username", "fdmsrctok", "/home/pay1/batchfiles/devlogs/fdmsrctok", "miscdebug.txt", "append", "misc", $printstr );

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $smid{$rsequencenum};
  delete $stid{$rsequencenum};
  delete $srefnum{$rsequencenum};
  delete $sprocessid{$rsequencenum};
  delete $sreason{$rsequencenum};
  delete $sinvoicenum{$rsequencenum};
  delete $scardtype{$rsequencenum};
  delete $sdatetime{$rsequencenum};
  delete $sldatetime{$rsequencenum};

  return $message;

}

