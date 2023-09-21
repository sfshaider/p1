#!/usr/local/bin/perl

require 5.001;
$| = 1;

use lib '/home/p/pay1/perl_lib';

#use lib '/usr/local/lib/perl5/site_perl/sun4-solaris';
use miscutils;
use smpsutils;
use IO::Socket;
use Socket;
use SHA;
use rsautils;

#require 'sys/ipc.ph';
#require 'sys/msg.ph';

#Hagerstown 8  host 206.201.50.48 ports 16924, 16925
#Denver 5 host  206.201.53.72 ports 16935, 16936.

# keya keyb 5578 5579 netb uses these ipc addresses

$sha1 = new SHA;

$test    = "no";
$devprod = "prod";

$host = "processor-host";    # Source IP address

#$primaryipaddress = "206.201.53.50";	# primary server
#$primaryport = "30398";		# primary server
#$secondaryipaddress = "206.201.52.50";	# secondary server
#$secondaryport = "30398";		# secondary server
$primaryipaddress   = "167.16.0.95";     # primary server A1PVAP036
$primaryport        = "42020";           # primary server
$secondaryipaddress = "167.16.0.195";    # secondary server A3PVAP036
$secondaryport      = "42020";           # secondary server

$keepalive      = 0;
$keepalivecnt   = 0;
$getrespflag    = 1;
$socketopenflag = 0;

$nullmessage1 = "aa77000d0011";
$nullmessage2 = "aa550d001100";

if ( $test eq "yes" ) {
  $ipaddress = "167.16.0.125";           # test server A1QVAP998
  $port      = "41020";                  # test server emv testing
} elsif ( ( -e "/home/p/pay1/batchfiles/$devprod/fdmsemv/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
  print logfile "$mytime switching to secondary socket\n";
  print logfile "$sockaddrport\n";
  print logfile "$sockettmp\n\n";
  close(logfile);
  $ipaddress = $secondaryipaddress;
  $port      = $secondaryport;
} elsif ( !( -e "/home/p/pay1/batchfiles/$devprod/fdmsemv/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
  print logfile "$mytime switching to primary socket\n";
  print logfile "$sockaddrport\n";
  print logfile "$sockettmp\n\n";
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
        where (trans_time<?
          or trans_time is NULL
          or trans_time='')
        and processor='fdmsemv'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $fdmsemvintl::DBI::errstr", %datainfo );
$sth->execute("$deltime")
  or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $fdmsemvintl::DBI::errstr", %datainfo );
$sth->finish;

$dbhmisc->disconnect;

while (1) {
  $temptime = time();
  open( outfile, ">/home/p/pay1/batchfiles/$devprod/fdmsemv/accesstime.txt" );
  print outfile "$temptime\n";
  close(outfile);

  $keepalivecnt++;
  if ( $keepalivecnt >= 60 ) {
    print "keepalivecnt = $keepalivecnt\n";
    $keepalivecnt = 0;
    $socketcnt    = `netstat -n | grep $port | grep ESTABLISHED | grep -c $sockaddrport`;
    if ( $socketcnt < 1 ) {
      print "socketcnt < 1\n";
      shutdown SOCK, 2;
      close(SOCK);
      $socketopenflag = 0;
      if ( $socketopenflag != 1 ) {
        $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
        ( $d1, $d2, $tmptime ) = &miscutils::genorderid();
        open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
        print logfile "No ESTABLISHED $tmptime\n";
        print logfile "$sockaddrport\n";
        print logfile "$sockettmp\n\n";
        close(logfile);
      }
      while ( $socketopenflag != 1 ) {
        &socketopen( "$ipaddress", "$port" );
      }
      $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
      print logfile "socket reopened\n";
      print logfile "$sockaddrport\n";
      print logfile "$sockettmp\n\n";
      close(logfile);
    }
  }

  if ( $test eq "yes" ) {
    $ipaddress = "167.16.0.125";    # test server
    $port      = "41020";           # test server emv testing
  } elsif ( ( -e "/home/p/pay1/batchfiles/$devprod/fdmsemv/secondary.txt" ) && ( $ipaddress ne $secondaryipaddress ) ) {
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
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
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
    print logfile "$mytime secondary socket opened\n";
    print logfile "$sockaddrport\n";
    print logfile "$sockettmp\n\n";
    close(logfile);
  } elsif ( !( -e "/home/p/pay1/batchfiles/$devprod/fdmsemv/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) ) {
    $mytime = gmtime( time() );
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
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
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
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

  my $sth1 = $dbhmisc->prepare(
    qq{
        select trans_time,processid,username,orderid,message,status,response
        from processormsg
        where processor='fdmsemv'
        and status in ('pending','success')
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $fdmsemv::DBI::errstr", %datainfo );
  $sth1->execute() or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $fdmsemv::DBI::errstr", %datainfo );
  $sth1->bind_columns( undef, \( $trans_time, $processid, $username, $orderid, $encmessage, $processormsgstatus, $encmsgresponse ) );

  while ( $sth1->fetch ) {

    $message     = &rsautils::rsa_decrypt_file( $encmessage,     "", "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    $msgresponse = &rsautils::rsa_decrypt_file( $encmsgresponse, "", "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

    # void if transaction never finished after 45 seconds
    if ( $processormsgstatus eq "success" ) {
      my $now    = time();
      my $mytime = &miscutils::strtotime($trans_time);
      my $delta  = $now - $mytime;
      if ( $delta > 65 ) {

        #my ($enclen,$encdata) = split(/ /,$message,2);
        #$message = &rsautils::rsa_decrypt_file($encdata,$enclen,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");

        if ( $message =~ /<(Credit|Debit)Request/ ) {
          print "msgstatus: $processormsgstatus\n";
          print "msgstatus: $delta\n";

          #my ($enclen,$encdata) = split(/ /,$msgresponse,2);
          #$msgresponse = &rsautils::rsa_decrypt_file($encdata,$enclen,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");

          &decodebitmap( $msgresponse, "", "no" );

          my $paymenttype = "";
          my $chopmessage = substr( $msgresponse, 12 );
          if ( $chopmessage =~ /^.*?<([a-zA-Z]+)Response>/ ) {
            $paymenttype = $1;
          }
          $responsetype = $paymenttype . "Response";

          my $messtype = $temparray{"GMF,$responsetype,CommonGrp,TxnType"};    # messtype
          my $respcode = $temparray{"GMF,$responsetype,RespGrp,RespCode"};     # bit 39
          print "messtype: $messtype\n";
          print "respcode: $respcode\n";
          if ( ( $paymenttype =~ /^(Credit|Debit)$/ ) && ( $respcode =~ /^(000|002|85)$/ ) ) {
            $rsequencenum = $sseqnum{"$username $orderid"};
            $respfield63  = $msgvalues[63];
            $message      = &voidmessage($message);
            &decodebitmap( $message, "", "no" );

            $checkmessage = $message;

            #$checkmessage = substr($checkmessage,6);
            #$checkmessage = substr($checkmessage,0,length($message)-4);
            #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
            #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
            $checkmessage =~ s/\x02/\[02\]/g;
            $checkmessage =~ s/\x03/\[03\]/g;
            $checkmessage =~ s/\x1c/\[1c\]/g;
            $checkmessage =~ s/Track2Data>(.).+?<\/Track2Data/Track2Data>$1xxxxx<\/Track2Data/g;
            $checkmessage =~ s/Track1Data>(.).+?<\/Track1Data/Track1Data>$1xxxxx<\/Track1Data/g;
            $checkmessage =~ s/AcctNum>(.).+?<\/AcctNum/AcctNum>$1xxxxx<\/AcctNum/g;
            $checkmessage =~ s/CCVData>[0-9]{3}<\/CCVData/CCVData>xxx<\/CCVData/g;
            $checkmessage =~ s/CCVData>[0-9]+?<\/CCVData/CCVData>xxxx<\/CCVData/g;
            $checkmessage =~ s/></>\n</g;
            $temptime = gmtime( time() );
            open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
            print logfile "\nvoid message $username $orderid $trans_time $delta\n";
            print logfile "$temptime send: $checkmessage\n";
            print "$temptime send: $checkmessage\n";
            close(logfile);

            $susername{$rsequencenum} = $username;
            $sorderid{$rsequencenum}  = $orderid;
            $sreason{$rsequencenum}   = "timeout";
            print "rsequencenumaaaa: $rsequencenum\n";

            $transcnt++;
            &socketwrite($message);
            &socketread(4);
          }

          # permanent
          if (0) {
            my $dbh_trans = &miscutils::dbhconnect("pnpdata");

            my $sth_upd3 = $dbh_trans->prepare(
              qq{
              update trans_log
              set finalstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and operation='auth'
              and finalstatus='success'
              }
              )
              or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %fdmsemv::datainfo );
            $sth_upd3->execute( "$orderid", "$username" )
              or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %fdmsemv::datainfo );
            $sth_upd3->finish;

            my $sth_upd2 = $dbh_trans->prepare(
              qq{
              update operation_log
              set authstatus='problem',lastopstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and lastop='auth'
              and lastopstatus='success'
              }
              )
              or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %fdmsemv::datainfo );
            $sth_upd2->execute( "$orderid", "$username" )
              or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %fdmsemv::datainfo );
            $sth_upd2->finish;

            $dbh_trans->disconnect;
          }

          my $sth = $dbhmisc->prepare(
            qq{
              delete from processormsg
              where username=?
              and orderid=?
              and processor='fdmsemv'
              }
            )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
          $sth->execute( "$username", "$orderid" )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
          $sth->finish;

          open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
          print logfile "delete from processormsg $username $orderid\n";
          close(logfile);

        }
      }
      next;
    }

    my $sth = $dbhmisc->prepare(
      qq{
          update processormsg set status='locked'
          where processid=?
          and processor='fdmsemv'
          and status='pending'
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $fdmsemv::DBI::errstr", %datainfo );
    $sth->execute("$processid") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $fdmsemv::DBI::errstr", %datainfo );
    $sth->finish;

    #while (1) {}

    $username =~ s/[^0-9a-zA-Z_]//g;
    $trans_time =~ s/[^0-9]//g;
    $orderid =~ s/[^0-9]//g;
    $processid =~ s/[^0-9a-zA-Z]//g;

    #my ($enclen,$encdata) = split(/ /,$message,2);
    #$message = &rsautils::rsa_decrypt_file($encdata,$enclen,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");

    print "$mytime msgrcv $username $orderid\n";

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

    $dbh = &miscutils::dbhconnect("pnpmisc");

    if ( $temparray{"GMF,$requesttype,CommonGrp,STAN"} ne "000000" ) {
      $sequencenum = $temparray{"GMF,$requesttype,CommonGrp,STAN"};      # bit 11
      $refnum      = $temparray{"GMF,$requesttype,CommonGrp,RefNum"};    # bit 37
      $terminalnum = $temparray{"GMF,$requesttype,CommonGrp,TermID"};    # bit 41

      %datainfo = ( "username", "$username" );
      $sth1 = $dbh->prepare(
        qq{
            select username,tracenum
            from merchant_terminal_trace
            where username=?
            and terminalnum=?
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth1->execute( "$username", "$terminalnum" )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      ( $chkusername, $chkinvoicenum ) = $sth1->fetchrow;
      $sth1->finish;

      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
      print logfile "a $username $requesttype  invoicenum: $sequencenum  $chkinvoicenum\n";
      close(logfile);

      if ( ( $sequencenum > $chkinvoicenum ) || ( ( $chkinvoicenum > 99998 ) && ( $sequencenum < 100000 ) ) ) {
        if ( $chkusername eq "" ) {
          $sth = $dbh->prepare(
            qq{
                insert into merchant_terminal_trace
                (username,terminalnum,tracenum)
                values (?,?,?)
                }
            )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
          $sth->execute( "$username", "$terminalnum", "$sequencenum" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
          $sth->finish;
        } else {
          $sth = $dbh->prepare(
            qq{
                update merchant_terminal_trace set tracenum=?
                where username=?
                and terminalnum=?
                }
            )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
          $sth->execute( "$sequencenum", "$username", "$terminalnum" )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
          $sth->finish;
        }
      }
    } else {

      %datainfo = ( "username", "$username" );
      $sth1 = $dbh->prepare(
        qq{
            select username,tracenum
            from merchant_terminal_trace
            where username=?
            and terminalnum=?
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth1->execute( "$username", "$terminalnum" )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      ( $chkusername, $invoicenum ) = $sth1->fetchrow;
      $sth1->finish;

      $invoicenum = ( $invoicenum + 1 ) % 99999;

      if ( $chkusername eq "" ) {
        $sth = $dbh->prepare(
          qq{
              insert into merchant_terminal_trace
              (username,terminalnum,tracenum)
              values (?,?,?)
              }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sth->execute( "$username", "$terminalnum", "$invoicenum" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sth->finish;
      } else {
        $sth = $dbh->prepare(
          qq{
              update merchant_terminal_trace set tracenum=?
              where username=?
              and terminalnum=?
              }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sth->execute( "$invoicenum", "$username", "$terminalnum" )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sth->finish;
      }

      #$mainsequencenum = ($mainsequencenum + 1) % 99999;
      $sequencenum = sprintf( "%06d", $invoicenum );

      #$newsequencenum = pack "H6",$sequencenum;
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
      print logfile "b $username invoicenum: $invoicenum  $sequencenum\n";
      close(logfile);
      $message =~ s/<STAN>(.*)<\/STAN>/<STAN>$sequencenum<\/STAN>/;

      $refnum = $temparray{"GMF,$requesttype,CommonGrp,RefNum"};    # bit 37
      if ( $refnum eq "000000000000" ) {
        $message =~ s/<OrderNum>(.*)<\/OrderNum>/<OrderNum>00$sequencenum<\/OrderNum>/;

        #$message = substr($message,0,$msgvaluesidx[11]) . $newsequencenum . substr($message,$msgvaluesidx[11]+3);

        $tidstr = substr( $temparray{"GMF,$requesttype,CommonGrp,TermID"}, -2, 2 );    # bit 41
        $refnum = '0000' . $tidstr . $sequencenum;
        $refnum = substr( "0" x 12 . $refnum, -12, 12 );
        $message =~ s/<RefNum>(.*)<\/RefNum>/<RefNum>$refnum<\/RefNum>/;

        #$message = substr($message,0,$msgvaluesidx[37]) . $refnum . substr($message,$msgvaluesidx[37]+12);
      }
    }

    $dbh->disconnect;

    #$message = substr($message,0,2) . $sequencenum . substr($message,14);
    &decodebitmap($message);

    #if (1) {
    #    $chkinvoicenum = substr($message,87,10);
    #    if ($chkinvoicenum eq "0000000000") {
    #      $invoicenum = sprintf("%010d", $invoicenum + .0001);
    #print "invoicenum: $invoicenum\n";
    #      $message = substr($message,0,87) . $invoicenum . substr($message,97);
    #    }
    #    else {
    #      $invoicenum = $chkinvoicenum;
    #    }
    #}
    #else {
    #    $invoicenum = sprintf("%010d", $invoicenum + .0001);
    #print "invoicenum: $invoicenum\n";
    #    $message = substr($message,0,87) . $invoicenum . substr($message,97);
    #}

    $susername{"$sequencenum"}     = $username;
    $sseqnum{"$username $orderid"} = $sequencenum;
    $strans_time{"$sequencenum"}   = $trans_time;
    $smessage{"$sequencenum"}      = $message;
    $sretries{"$sequencenum"}      = 1;
    $sorderid{"$sequencenum"}      = $orderid;
    $sprocessid{"$sequencenum"}    = $processid;
    $sreason{"$sequencenum"}       = "";
    $sinvoicenum{"$sequencenum"}   = $invoicenum;

    #if ($msgvalues[63] =~ /^\x00\x2232/) {
    #  $scardtype{"$sequencenum"} = "interac";
    #}
    #else {
    $scardtype{"$sequencenum"} = "";

    #}

    $cardnum = $temparray{"GMF,$requesttype,CardGrp,AcctNum"};    # bit 2
    if ( $cardnum eq "" ) {
      $cardnum = $temparray{"GMF,$requesttype,CardGrp,Track2Data"};    # bit 35
    }
    if ( $cardnum eq "" ) {
      $cardnum = $temparray{"GMF,$requesttype,CardGrp,Track1Data"};    # bit 45
    }
    $xs = "x" x length($cardnum);

    $messagestr = $message;

    #$messagestr =~ s/$cardnum/$xs/g;

    if ( $cardnum ne "" ) {
      $cardnumbin = pack "H*", $cardnum;
      $myidx = index( $messagestr, $cardnumbin );
      if ( $myidx > 0 ) {
        $xs3  = "x" x length($cardnumbin);
        $len3 = length($cardnumbin);

        #$messagestr = substr($messagestr,0,$myidx) . $xs3 . substr($messagestr,$myidx+$len3);
      }
    }

    if ( $messagestr =~ /\#0131(.*)?\#/ ) {
      $cvv = $1;
      $cvv =~ s/ //;
      $xs = "x" x length($cvv);

      #$messagestr =~ s/\#0131$cvv/\#0131$xs/;
    } elsif ( $messagestr =~ /\@0131(.*)?\#/ ) {
      $cvv = $1;
      $cvv =~ s/ //;
      $xs = "x" x length($cvv);

      #$messagestr =~ s/\@0131$cvv/\@0131$xs/;
    }

    $cardnumber = $cardnum;
    $sha1->reset;
    $sha1->add($cardnumber);
    $shacardnumber = $sha1->hexdigest();

    $checkmessage = $messagestr;

    #$checkmessage = substr($checkmessage,6);
    #$checkmessage = substr($checkmessage,0,length($message)-4);
    #$checkmessage =~ s/([^0-9A-Za-z\/\<\> ])/\[$1\]/g;
    #$checkmessage =~ s/([^0-9A-Za-z\/\<\>\[\] ])/unpack("H2",$1)/ge;
    $checkmessage =~ s/\x02/\[02\]/g;
    $checkmessage =~ s/\x03/\[03\]/g;
    $checkmessage =~ s/\x1c/\[1c\]/g;
    $checkmessage =~ s/Track2Data>(.).+?<\/Track2Data/Track2Data>$1xxxxx<\/Track2Data/g;
    $checkmessage =~ s/Track1Data>(.).+?<\/Track1Data/Track1Data>$1xxxxx<\/Track1Data/g;
    $checkmessage =~ s/AcctNum>(.).+?<\/AcctNum/AcctNum>$1xxxxx<\/AcctNum/g;
    $checkmessage =~ s/CCVData>[0-9]{3}<\/CCVData/CCVData>xxx<\/CCVData/g;
    $checkmessage =~ s/CCVData>[0-9]+?<\/CCVData/CCVData>xxxx<\/CCVData/g;
    $checkmessage =~ s/></>\n</g;
    $temptime = gmtime( time() );

    #$tempstr = unpack "H*", $message;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
    print logfile "$username  $orderid\n";
    print logfile "$temptime send: $checkmessage  $shacardnumber\n\n";
    print logfile "sequencenum: $sequencenum retries: $retries\n";
    close(logfile);

    $getrespflag = 0;
    &socketwrite($message);

    $keepalive    = 0;
    $keepalivecnt = 0;

    $temptime = time();
    open( outfile, ">/home/p/pay1/batchfiles/$devprod/fdmsemv/accesstime.txt" );
    print outfile "$temptime\n";
    close(outfile);

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt > 6 ) {
      last;
    }
  }

  if ( $transcnt > 0 ) {
    $numtrans = $transcnt;
    &socketread($transcnt);
  }

  foreach $rsequencenum ( keys %susername ) {
    if ( $smessage{"$rsequencenum"} !~ /<(Credit|Debit)Request/ ) {
      next;
    }
    if ( $scardtype{"$rsequencenum"} eq "interac" ) {
      next;
    }
    if ( $sstatus{"$rsequencenum"} ne "done" ) {
      print "bbbb $rsequencenum\n";
      my $now    = time();
      my $mytime = &miscutils::strtotime( $strans_time{$rsequencenum} );
      my $delta  = $now - $mytime;
      print "cccc delta: $delta\n";
      if ( $delta > 40 ) {
        my $tmpstr = substr( $smessage{$rsequencenum}, 0, 8 );
        $tmpstr = unpack "H*", $tmpstr;
        print "about to compare $tmpstr and 02464402....0100\n";
        if ( ( $delta < 180 ) && ( $tmpstr =~ /^02464402....0100/ ) ) {    # void all messages
          if ( ( ( $delta > 40 ) && ( $sretries{"$rsequencenum"} < 2 ) )
            || ( ( $delta > 80 )  && ( $sretries{"$rsequencenum"} < 3 ) )
            || ( ( $delta > 120 ) && ( $sretries{"$rsequencenum"} < 4 ) ) ) {
            $sretries{"$rsequencenum"}++;
            print "comparison passed\n";
            $respfield63 = "";
            $message     = &voidmessage( $smessage{$rsequencenum} );

            &decodebitmap($message);

            $checkmessage = $message;

            #$checkmessage = substr($checkmessage,6);
            #$checkmessage = substr($checkmessage,0,length($message)-4);
            #$checkmessage =~ s/([^0-9A-Za-z ])/\[$1\]/g;
            #$checkmessage =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
            $checkmessage =~ s/\x02/\[02\]/g;
            $checkmessage =~ s/\x03/\[03\]/g;
            $checkmessage =~ s/\x1c/\[1c\]/g;
            $checkmessage =~ s/Track2Data>(.).+?<\/Track2Data/Track2Data>$1xxxxx<\/Track2Data/g;
            $checkmessage =~ s/Track1Data>(.).+?<\/Track1Data/Track1Data>$1xxxxx<\/Track1Data/g;
            $checkmessage =~ s/AcctNum>(.).+?<\/AcctNum/AcctNum>$1xxxxx<\/AcctNum/g;
            $checkmessage =~ s/CCVData>[0-9]{3}<\/CCVData/CCVData>xxx<\/CCVData/g;
            $checkmessage =~ s/CCVData>[0-9]+?<\/CCVData/CCVData>xxxx<\/CCVData/g;
            $temptime = gmtime( time() );
            open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
            print logfile "\nvoid message\n";
            print logfile "$temptime send: $checkmessage\n";
            print "$temptime send: $checkmessage\n";
            close(logfile);

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
          delete $sreason{$rsequencenum};
          delete $sprocessid{$rsequencenum};
          delete $sinvoicenum{$rsequencenum};
          delete $scardtype{$rsequencenum};
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

  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
  print logfile "socketopen attempt $addr $port\n";
  close(logfile);

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
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
    print logfile "$sockaddrport\n";
    print logfile "socketopen successful\n";
    close(logfile);
    $getrespflag = 1;
  } else {
    $socketopenflag = 0;
    select undef, undef, undef, 5.00;
  }
}

sub socketopen2 {
  my ( $addr, $port, $errmsg ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
  print logfile "$mytime socketopen failed  $errmsg\n";
  print logfile "$mytime socketopen attempt secondary $addr  $port\n";
  close(logfile);

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";

  #  Added by Dave  09/08/2003
  $iaddr = inet_aton($host);
  my $sockaddr = sockaddr_in( 0, $iaddr );
  bind( SOCK, $sockaddr ) || die "bind: $!\n";

  connect( SOCK, $paddr ) || die "connect: $addr $port $!";

  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
  print logfile "socketopen successful secondary\n";
  close(logfile);

  $socketopenflag = 1;
}

sub socketwrite {
  my ($message) = @_;
  print "in socketwrite\n";

  if ( $socketopenflag != 1 ) {
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
    print logfile "socketopenflag = 0, in socketwrite\n";
    close(logfile);
  }
  while ( $socketopenflag != 1 ) {
    &socketopen( "$ipaddress", "$port" );
  }
  send( SOCK, $message, 0, $paddr );
}

sub socketread {
  my ($numtries) = @_;

  print "in socketread\n";
  $donereadingflag = 0;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
  print logfile "socketread: $transcnt\n";
  close(logfile);

  $temp11 = time();
  vec( $rin, fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 3;
  $mlen     = length($message);
  $respdata = "";
  $mydelay  = 30.0;
  while ( $count && select( $rout = $rin, undef, undef, $mydelay ) ) {
    print "in while\n";
    $mydelay = 5.0;
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
    print logfile "while\n";
    close(logfile);
    recv( SOCK, $response, 2048, 0 );
    $tempstr = unpack "H*", $response;
    print "aaaa $tempstr\n";

    $respdata = $respdata . $response;

    $resplength = unpack "S", substr( $respdata, 4 );
    $resplength = $resplength + 10;
    $rlen       = length($respdata);
    open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
    print logfile "rlen: $rlen, resplength: $resplength\n";
    close(logfile);

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $transcnt--;

      $getrespflag = 1;

      $response = substr( $respdata, 0, $resplength );
      &updatefdmsemv();
      delete $writearray{$rsequencenum};
      if ( !%writearray ) {
        $donereadingflag = 1;
      }
      $respdata = substr( $respdata, $resplength );
      $resplength = unpack "S", substr( $respdata, 4 );
      $resplength = $resplength + 10;
      $rlen       = length($respdata);

      $temptime = time();
      open( outfile, ">/home/p/pay1/batchfiles/$devprod/fdmsemv/accesstime.txt" );
      print outfile "$temptime\n";
      close(outfile);
    }

    if ( $donereadingflag == 1 ) {
      open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
      print logfile "donereadingflag = 1\n";
      close(logfile);
      last;
    }

    $count--;
  }
  $delta = time() - $temp11;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
  print logfile "end loop $transcnt delta: $delta\n\n\n\n";
  close(logfile);

}

sub updatefdmsemv {
  print "in updatefdmsemv\n";

  &decodebitmap($response);

  my $paymenttype = "";
  my $chopmessage = substr( $response, 12 );
  if ( $chopmessage =~ /^.*?<([a-zA-Z]+)Response>/s ) {
    $paymenttype = $1;
  }
  $responsetype = $paymenttype . "Response";

  $rsequencenum = $temparray{"GMF,$responsetype,CommonGrp,STAN"};    # bit 11
  print "aaaa rseq: $rsequencenum\n";

  if ( $response =~ /<ReversalResponse>/ ) {
    print "void response found\n";

    my $username = $susername{$rsequencenum};
    my $orderid  = $sorderid{$rsequencenum};
    my $reason   = $sreason{$rsequencenum};
    print "rseqbbbb: $rsequencenum\n";
    print "username: $username\n";
    print "orderid: $orderid\n";
    if ( ( $username ne "" ) && ( $orderid ne "" ) && ( $reason eq "timeout" ) ) {
      my $dbh_trans = &miscutils::dbhconnect("pnpdata");

      my $sth_upd3 = $dbh_trans->prepare(
        qq{
              update trans_log
              set finalstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and operation='auth'
              and finalstatus='success'
              }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %fdmsemv::datainfo );
      $sth_upd3->execute( "$orderid", "$username" )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %fdmsemv::datainfo );
      $sth_upd3->finish;

      my $sth_upd2 = $dbh_trans->prepare(
        qq{
              update operation_log
              set authstatus='problem',lastopstatus='problem',descr='no response from card, transaction voided'
              where orderid=?
              and username=?
              and lastop='auth'
              and lastopstatus='success'
              }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %fdmsemv::datainfo );
      $sth_upd2->execute( "$orderid", "$username" )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %fdmsemv::datainfo );
      $sth_upd2->finish;

      $dbh_trans->disconnect;
    }

  }

  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
  print logfile "sequencenum: $rsequencenum, transcnt: $transcnt\n";
  close(logfile);
  $checkmessage = $response;
  $checkmessage = substr( $checkmessage, 6 );
  $checkmessage = substr( $checkmessage, 0, length($response) - 4 );

  $checkmessage =~ s/\x02/\[02\]/g;
  $checkmessage =~ s/\x03/\[03\]/g;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/Track2Data>(.).+?<\/Track2Data/Track2Data>$1xxxxx<\/Track2Data/g;
  $checkmessage =~ s/Track1Data>(.).+?<\/Track1Data/Track1Data>$1xxxxx<\/Track1Data/g;
  $checkmessage =~ s/AcctNum>(.).+?<\/AcctNum/AcctNum>$1xxxxx<\/AcctNum/g;
  $checkmessage =~ s/CCVData>[0-9]{3}<\/CCVData/CCVData>xxx<\/CCVData/g;
  $checkmessage =~ s/CCVData>[0-9]+?<\/CCVData/CCVData>xxxx<\/CCVData/g;
  $checkmessage =~ s/></>\n</g;
  my $mylen = length($response);
  $temptime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
  print logfile "$temptime recv: $mylen $checkmessage\n";
  close(logfile);

  $sstatus{"$rsequencenum"} = "done";

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");
  $processid = $sprocessid{"$rsequencenum"};
  if ( &mysqlmsgsnd( $dbhmisc, $processid, "success", "", "$response" ) == NULL ) { }
  $dbhmisc->disconnect;

  my $mytime = gmtime( time() );
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/bbserverlogmsg.txt" );
  print logfile "$mytime snd success $checktime\n";
  close(logfile);

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sprocessid{$rsequencenum};
  delete $sreason{$rsequencenum};
  delete $sinvoicenum{$rsequencenum};
  delete $scardtype{$rsequencenum};

}

sub socketclose {
  $sockettmp = `netstat -n | grep $port | grep -v TIME_WAIT`;
  open( logfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
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
  print MAIL "Subject: fdmsemv - no response to authorization\n";
  print MAIL "\n";

  print MAIL "fdmsemv socket is being closed, then reopened because no response was\n\n";
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
    print "aa $key    bb $temparray{$key}\n";
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
    $tempstr = pack "L", $tempdata;
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
        update processormsg set status=?,invoicenum=?,response=\@sensitivedata
        where processid=?
        and processor='fdmsemv'
        and status='locked'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute( "$status", "$invoicenum", "$processid" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth->finish;

}

sub voidmessage {
  my ($message) = @_;

  print "in voidmessage\n";

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

  my %msgarray = &decodebitmap($message);
  if ( $msgarray{"GMF,$requesttype,CardGrp,Track2Data"} ne "" ) {
    my ( $val1, $val2 ) = split( /=/, $msgarray{"GMF,$requesttype,CardGrp,Track2Data"} );
    my $month = substr( $val2, 0, 2 );
    my $year  = substr( $val2, 2, 2 );
    $message =~ s/<Track2Data>(.*?)<\/Track2Data>/<CardNum>$val1<\/CardNum><CardExpiryDate>20$year$month<\/CardExpiryDate>/;
  } elsif ( $msgarray{"GMF,$requesttype,CardGrp,Track1Data"} ne "" ) {
    my ( $val1, $val2, $val3 ) = split( /\^/, $msgarray{"GMF,$requesttype,CardGrp,Track1Data"} );
    my $month = substr( $val3, 0, 2 );
    my $year  = substr( $val3, 2, 2 );
    $val1 =~ s/B//;
    $message =~ s/<Track1Data>(.*?)<\/Track1Data>/<CardNum>$val1<\/CardNum><CardExpiryDate>20$year$month<\/CardExpiryDate>/;
  }

  return $message;

  if (0) {
    @transaction = ();

    $data    = $msgvalues[2];
    $datalen = length($data);
    $datalen = substr( "00" . $datalen, -2, 2 );
    $transaction[2] = pack "H2H$datalen", "$datalen", "$data";
    $transaction[3] = pack "H6",          $msgvalues[3];
    $transaction[4] = pack "H12",         $msgvalues[4];
    $transaction[7] = pack "H10",         $msgvalues[7];
    if ( $msgvalues[11] ne "000000" ) {
      $transaction[11] = pack "H6", $msgvalues[11];
    } else {
      $transaction[11] = pack "H6", $rsequencenum;
    }
    print "11: $msgvalues[11]\n";
    $transaction[12] = pack "H6", $msgvalues[12];
    $transaction[13] = pack "H4", $msgvalues[13];
    if ( $msgvalues[14] eq "" ) {
      if ( $msgvalues[35] ne "" ) {
        my ( $val1, $val2 ) = split( /=/, $msgvalues[35] );
        my $month = substr( $val2, 0, 2 );
        my $year  = substr( $val2, 2, 2 );
        $transaction[14] = pack "H4", $year . $month;
      } elsif ( $msgvalues[45] ne "" ) {
        my ( $val1, $val2, $val3 ) = split( /\^/, $msgvalues[45] );
        my $month = substr( $val3, 0, 2 );
        my $year  = substr( $val3, 2, 2 );
        $transaction[14] = pack "H4", $year . $month;
      }
    } else {
      $transaction[14] = pack "H4", $msgvalues[14];
    }

    $transaction[18] = pack "H4", $msgvalues[18];

    my $posentry = $msgvalues[22];
    if ( $posentry eq "0902" ) {
      $posentry = "0012";
    }
    $transaction[22] = pack "H4", $posentry;

    $transaction[24] = pack "H4", $msgvalues[24];
    $transaction[25] = pack "H2", $msgvalues[25];
    if ( $msgvalues[31] ne "" ) {
      $transaction[31] = pack "H2A1", "01", $msgvalues[31];
    }
    $transaction[37] = $msgvalues[37];
    $transaction[41] = $msgvalues[41];
    $transaction[42] = $msgvalues[42];

    $data    = $msgvalues[48];
    $datalen = length($data);
    if ( $datalen > 0 ) {
      $datalen = substr( "0000" . $datalen, -4, 4 );
      $transaction[48] = pack "H4A$datalen", $datalen, $data;
    }

    print "49: $msgvalues[49]\n";
    $transaction[49] = pack "H4", $msgvalues[49];

    $data    = $msgvalues[55];
    $datalen = length($data);
    if ( $datalen > 0 ) {
      $datalen = substr( "0000" . $datalen, -4, 4 );
      $transaction[55] = pack "H4A$datalen", $datalen, $data;
    }

    $transaction[59] = pack "H2A9", "09", $msgvalues[59];

    $data = $msgvalues[63];
    print "63: $msgvalues[63]\n";

    $card_type = "";

    # bit 63

    my %emvtagarray = ();
    my $e2string    = "";
    if ( $fdmsemv::datainfo{'emvtags'} ne "" ) {
      my $emvtags = $msgvalues[55];

      my $cnt    = 0;
      my $tag    = "";
      my $taglen = "";
      my $idxlen = "";
      my $idx    = "";
      while ( $idx < length($emvtags) ) {
        $cnt++;
        if ( $cnt > 100 ) {
          last;
        }
        $tag    = substr( $emvtags, $idx,     2 );
        $taglen = substr( $emvtags, $idx + 2, 2 );
        $idxlen = 2;
        if ( $tag =~ /^(1|3|5|7|9|B|D|F)F$/ ) {
          $tag    = substr( $emvtags, $idx,     4 );
          $taglen = substr( $emvtags, $idx + 4, 2 );
          $idxlen = 4;
        }
        $taglen = pack "H2", $taglen;
        $taglen = unpack "C", $taglen;
        my $data = substr( $emvtags, $idx + $idxlen + 2, $taglen * 2 );
        if ( $tag eq "E2" ) {
          my $taglen = substr( $emvtags, $idx + 2, 2 );
          if ( $taglen eq "81" ) {
            $data = substr( $emvtags, $idx + $idxlen + 2 + 2 );
          } elsif ( $taglen eq "82" ) {
            $data = substr( $emvtags, $idx + $idxlen + 2 + 4 );
          } else {
            $data = substr( $emvtags, $idx + $idxlen + 2 + 0 );
          }
        }

        $emvtagarray{"$tag"} = $data;
        if ( $tag eq "4F" ) {
          last;
        }

        $idx = $idx + $idxlen + 2 + ( $taglen * 2 );
      }
    }

    my $cardnumber  = "";
    my $servicecode = "";
    if ( $emvtagarray{"4F"} ne "" ) {
      my $aid = $emvtagarray{"4F"};
      if ( $aid =~ /^A000000004/ ) {
        $card_type = "mc";
      } elsif ( $aid =~ /^A000000003/ ) {
        $card_type = "vi";
      } elsif ( $aid =~ /^A000000025/ ) {
        $card_type = "ax";
      } elsif ( $aid =~ /^A000000277/ ) {
        $card_type = "in";
      }
      open( tmpfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
      print tmpfile "card_type: $card_type scode: $servicecode 4F: $emvtagarray{'4F'} 2: $msgvalues[35] 1: $msgvalues[45]\n";
      close(tmpfile);
    } elsif ( $msgvalues[35] ne "" ) {    # track 2
      my $magstripe = $msgvalues[35];
      $servicecode = "";
      if ( index( $magstripe, "=" ) > 0 ) {
        $cardnumber = substr( $magstripe, 0, index( $magstripe, "=" ) );
        $servicecode = substr( $magstripe, index( $magstripe, "=" ) + 5, 3 );
      } elsif ( index( $magstripe, "D" ) > 0 ) {
        $cardnumber = substr( $magstripe, 0, index( $magstripe, "D" ) );
        $servicecode = substr( $magstripe, index( $magstripe, "D" ) + 5, 3 );
      } elsif ( index( $magstripe, "d" ) > 0 ) {
        $cardnumber = substr( $magstripe, 0, index( $magstripe, "d" ) );
        $servicecode = substr( $magstripe, index( $magstripe, "d" ) + 5, 3 );
      }
      $cardnumber =~ s/[^0-9]//g;
      if ( $servicecode eq "220" ) {
        $card_type = "in";
      }
      open( tmpfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
      print tmpfile "card_type: $card_type cardnumber: $cardnumber scode: $servicecode 4F: $emvtagarray{'4F'} 2: $msgvalues[35] 1: $msgvalues[45]\n";
      close(tmpfile);
    } elsif ( $msgvalues[45] ne "" ) {    # track 1
      my $magstripe = $msgvalues[45];
      $cardnumber = substr( $magstripe, 0, index( $magstripe, "^" ) );
      $cardnumber =~ s/[^0-9]//g;

      if ( $servicecode eq "" ) {
        $servicecode = $magstripe;
        $servicecode =~ s/^.*\^....(...).*$/$1/;
      }
      if ( $servicecode eq "220" ) {
        $card_type = "in";
      }
      open( tmpfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
      print tmpfile "card_type: $card_type scode: $servicecode 4F: $emvtagarray{'4F'} 2: $msgvalues[35] 1: $msgvalues[45]\n";
      close(tmpfile);
    } elsif ( $msgvalues[2] ne "" ) {
      $cardnumber = $msgvalues[2];
      open( tmpfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
      print tmpfile "card_type: $card_type scode: $servicecode 4F: $emvtagarray{'4F'} 2: $msgvalues[35] 1: $msgvalues[45]\n";
      close(tmpfile);
    }
    if ( $card_type eq "" ) {
      $card_type = &smpsutils::checkcard($cardnumber);
    }
    open( tmpfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
    print tmpfile "card_type: $card_type\n";
    close(tmpfile);

    my $newidx = 0;
    my $data   = $respfield63;
    if ( $data eq "" ) {
      $data = $msgvalues[64];
    }
    my $field63 = "";
    my $datalen = length($data);
    for ( my $newidx = 0 ; $newidx < $datalen ; ) {
      my $taglenstr = substr( $data, $newidx + 0, 2 );
      $taglen = unpack "H4", $taglenstr;
      my $tag     = substr( $data, $newidx + 2, 2 );
      my $tagdata = substr( $data, $newidx + 4, $taglen - 2 );
      $newidx = $newidx + 2 + $taglen;

      if ( ( $card_type eq "vi" ) && ( $tag eq "14" ) ) {
        $origamt = $msgvalues[4];
        $origamt = substr( "0" x 12 . $origamt, -12, 12 );

        $tagdata = substr( $tagdata, 0, 22 ) . $origamt . $origamt;
      } elsif ( ( $card_type eq "mc" ) && ( $tag eq "14" ) ) {
        $origamt = $msgvalues[4];
        $origamt = substr( "0" x 12 . $origamt, -12, 12 );
        $tagdata = substr( $tagdata, 0, 34 ) . $origamt;
      }
      if ( $tag ne "22" ) {
        $field63 = $field63 . $taglenstr . $tag . $tagdata;
      }

      my $tmpstr = $field63;
      $tmpstr =~ s/([^0-9A-Za-z ])/\[$1\]/g;
      $tmpstr =~ s/([^0-9A-Za-z\[\] ])/unpack("H2",$1)/ge;
      open( tmpfile, ">>/home/p/pay1/batchfiles/$devprod/fdmsemv/serverlogmsg.txt" );
      print tmpfile "field 63: $tmpstr\n";
      close(tmpfile);

    }

    if ( ( $msgvalues[24] eq "0047" ) && ( $msgvalues[3] =~ /^..(1|2|9)0..$/ ) ) {    # canadian
      $revreason = pack "H4A2A4", "0004", "38", "01";                                 # reversal reason code - no response
      $field63 = $field63 . $revreason;
    }

    $datalen = length($field63);
    if ( $datalen > 0 ) {
      $datalen = substr( "0000" . $datalen, -4, 4 );
      $transaction[63] = pack "H4A$datalen", $datalen, $field63;
    }

    my ( $bitmap1, $bitmap2 ) = &generatebitmap(@transaction);

    $bitmap1 = pack "H16", $bitmap1;
    if ( $bitmap2 ne "" ) {
      $bitmap2 = pack "H16", $bitmap2;
    }

    my $message = "";

    my $mcode = pack "H4", "0400";

    $message = $message . $mcode . $bitmap1 . $bitmap2;

    foreach my $var (@transaction) {
      $message = $message . $var;
    }

    my $head = pack "H8", "02464402";
    my $tail = pack "H8", "03464403";
    my $length = length($message) + 0;
    my $tcpheader = pack "S", $length;
    $message = $head . $tcpheader . $message . $tail;

    return $message;
  }
}

