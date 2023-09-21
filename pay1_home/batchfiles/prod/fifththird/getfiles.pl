#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use Net::SFTP::Foreign;
use miscutils;

$devprod = "logs";

#$host = "qamft.ftpsllc.com";    # test
$host = "mft.ftpsllc.com";    # production

$ftpun = 'PNPTSFTP';
$ftppw = '8RUspu6eCe6R';

#$redofile = "PNPT_P0BCRPN2_20190925.20190925053303.done";
#my $filedate = "20190925";

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );

( $d1, $today, $todaytime ) = &miscutils::genorderid();
$ttime = &miscutils::strtotime($today);

print "\n\nin getfiles.pl\n";
print "$today\n\n";

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "/home/pay1/batchfiles/$devprod/fifththird/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir /home/pay1/batchfiles/$devprod/fifththird/$fileyearonly");
}
if ( !-e "/home/pay1/batchfiles/$devprod/fifththird/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir /home/pay1/batchfiles/$devprod/fifththird/$filemonth");
}
if ( !-e "/home/pay1/batchfiles/$devprod/fifththird/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir /home/pay1/batchfiles/$devprod/fifththird/$fileyear");
}
if ( !-e "/home/pay1/batchfiles/$devprod/fifththird/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: fifththird - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory $devprod/fifththird/$fileyear.\n\n";
  close MAILERR;
  exit;
}

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 4 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

$dbh  = &miscutils::dbhconnect("pnpmisc");
$dbh2 = &miscutils::dbhconnect("pnpdata");

$batchfile = substr( $redofile, 0, 14 );

if ( $redofile ne "" ) {
  &processfile( $redofile, $filedate );
  $dbh->disconnect;
  $dbh2->disconnect;
  exit;
}

#  my $sthbatch1 = $dbh->prepare(qq{
#        select distinct c.username,c.merchant_id
#        from customers c, batchfilesfifth b
#        where b.status='locked'
#        and c.username=b.username
#        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
#  $sthbatch1->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
#  $sthbatch1->bind_columns(undef,\($user,$mid));
#
#  while ($sthbatch1->fetch) {
#    $newmid = substr($mid,0,7);
#    $newuserarray{$newmid} = $user;
#  }
#  $sthbatch1->finish;

my $sthbatch = $dbh->prepare(
  qq{
        select distinct filename
        from batchfilesfifth
        where status='locked'
        and trans_date>='$yesterday'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthbatch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthbatch->bind_columns( undef, \($batchfile) );

$batchcnt = 0;
while ( $sthbatch->fetch ) {
  $filename = $batchfile;
  $batchcnt++;
  print "aaaa $filename  $batchcnt\n";
}
$sthbatch->finish;

#if ($batchcnt < 1) {
#  print "More/less than one locked batch  $batchcnt   exiting\n";
#  exit;
#}

#my %args = (user => "$ftpun", password => "$ftppw", port => 6522,
#            key_path => '/home/pay1/batchfiles/prod/fdmsrctok/.ssh/id_rsa');
#my %args = (user => "$ftpun", password => "$ftppw", more => '-v');
my %args = ( user => "$ftpun", password => "$ftppw" );
$ftp = Net::SFTP::Foreign->new( "$host", %args );

$ftp->error and die "error: " . $ftp->error;

if ( $ftp eq "" ) {
  print "Username $ftpun and key don't work<br>\n";
  print "failure";
  exit;
}

#$Net::SFTP::Foreign::debug = -1;

$mytime = gmtime( time() );
print "$mytime connected\n";

$ftp->setcwd("'Inbox'");
my $files = $ftp->ls("/Inbox");

if ( @$files == 0 ) {
  print "aa no report files\n";
}
foreach $var (@$files) {
  print "aa " . $var->{"filename"} . "\n";
  $filename = $var->{"filename"};

  print "aaaa $filename\n";

  if ( $filename =~ /RECVD  Not Mounted/ ) {
    next;
  }

  # PNPT_P0BCRPN2_20190305
  if ( $filename =~ /PNPT_P0BCRPN2_/ ) {

    print "aaaa $filename bbbb $batchname\n";

    if ( !-e "/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename.out" ) {
      $ftp->get( "/Inbox/$filename", "/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename.$todaytime.out" );
      @filenamearray = ( @filenamearray, "$filename.$todaytime" );
    }
  }
}

#$ftp->quit();

foreach $filename (@filenamearray) {
  &processfile( $filename, $today );
}

$dbh->disconnect;
$dbh2->disconnect;

exit;

sub processfile {
  my ( $filename, $filedate ) = @_;

  $sth3 = $dbh->prepare(
    qq{
        select distinct b.count,b.amount,b.username,c.merchant_id,b.batchnum,b.filename
        from batchfilesfifth b, customers c
        where b.status='locked'
        and c.username=b.username
        and c.processor='fifththird'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth3->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth3->bind_columns( undef, \( $count, $amount, $username, $merchant_id, $batchnum, $batchfile ) );

  $batchcnt = 0;
  $batchamt = 0;
  while ( $sth3->fetch ) {
    $newmid = substr( $merchant_id, 0, 7 );
    $midamount{$newmid}      = $amount;
    $userarray{$newmid}      = $username;
    $batchnumarray{$newmid}  = $batchnum;
    $batchfilearray{$newmid} = $batchfile;
    $newmidcnt{$newmid}++;
    $batchamt = $batchamt + $amount;
    $batchcnt = $batchcnt++;
  }
  $sth3->finish;

  print "filename: $filename\n";
  $detailflag = 0;
  $batchflag  = 0;
  $fileflag   = 0;
  $batchnum   = "";
  $problemamt = 0;
  $ignoredups = 0;
  my $fileyear = substr( $filedate, 0, 4 ) . "/" . substr( $filedate, 4, 2 ) . "/" . substr( $filedate, 6, 2 );
  umask 0077;
  open( infile,  "/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename.out" );
  open( outfile, ">/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename.done" );

  while (<infile>) {
    $line = $_;
    chop $line;

    $lineout = $line;
    if ( $line =~ /^ [0-9]{6} / ) {
      $lineout =~ / ([0-9]{15,16}) /;
      $num = $1;
      $xs  = $num;
      $xs =~ s/[0-9]/x/g;
      $lineout =~ s/$num/$xs/;
    }
    print outfile "$lineout\n";

    if ( $line =~ /FILE SUBMISSION NO/ ) {
      my $myindex = index( $line, "FILE SUBMISSION NO" );
      $filenum = substr( $line, $myindex + 20 );
      ($filenum) = split( / /, $filenum );
      print "filenum: $filenum\n";
    } elsif ( $line =~ /0 BATCH/ ) {
      $batchnum = substr( $line, 9, 6 );
      $ignoredups = 0;
      print "batchnum: $batchnum\n";
    } elsif ( $line =~ /ALL ITEMS IN THIS BATCH WILL BE REJECTED/ ) {
      $ignoredups = 1;    # bad mid, all trans fail including dups
    } elsif ( $line =~ /-RECORD/ ) {
      $detailflag = 1;
    } elsif ( ( $detailflag == 1 ) && ( $line =~ /^ [0-9]/ ) ) {
      $detailnum = substr( $line, 1,  6 );
      $refnum    = substr( $line, 31, 14 );
      $refnum =~ s/ //g;
      $amount   = substr( $line, 61,  12 );
      $errormsg = substr( $line, 114, 22 );
      $amount =~ s/ //g;
      $amount =~ s/,//g;
      $errormsg =~ s/^ +//;
      $errormsg =~ s/ +$//;
      print "detailnum: $detailnum\n";
      print "refnum: $refnum\n";
      print "amount: $amount\n";
      print "errormsg: $errormsg\n\n";

      my $sthord = $dbh->prepare(
        qq{
            select orderid,username,batchname
            from batchfilesfifth
            where trans_date>='$yesterday'
            and filenum='$filenum'
            and detailnum='$detailnum'
            and batchnum='$batchnum'
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthord->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      ( $orderid, $username, $batchname ) = $sthord->fetchrow;
      $sthord->finish;
      print "username: $username  orderid: $orderid  batchname: $batchname  $filenum  $detailnum  $batchnum  $yesterday\n";
      $oidsub = substr( $orderid, -10, 10 );

      if ( ( $orderid ne "" ) && ( $refnum =~ /$oidsub/ ) && ( ( $errormsg !~ /(DUP|TEST)/ ) || ( $ignoredups == 1 ) ) ) {
        $problemamt = $problemamt + $amount;
        my $sth_trans = $dbh2->prepare(
          qq{
                update trans_log
                set finalstatus='problem',descr=?
                where orderid='$orderid'
                and username='$username'
                and finalstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sth_trans->execute("$errormsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sth_trans->finish;

        my $sthop1 = $dbh2->prepare(
          qq{
                update operation_log set returnstatus='problem',lastopstatus='problem',descr=?
                where orderid='$orderid'
                and username='$username'
                and processor='fifththird'
                and lastop='return'
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthop1->execute("$errormsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sthop1->finish;

        my $sthop2 = $dbh2->prepare(
          qq{
                update operation_log set postauthstatus='problem',lastopstatus='problem',descr=?
                where orderid='$orderid'
                and username='$username'
                and processor='fifththird'
                and lastop='postauth'
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthop2->execute("$errormsg") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sthop2->finish;
      }
    } elsif ( $line =~ /-BATCH/ ) {
      $detailflag = 0;
      $batchflag  = 1;
      $ignoredups = 0;
    } elsif ( ( $batchflag == 1 ) && ( $line =~ /^ +[0-9]/ ) ) {
      $records   = substr( $line, 21,  12 );
      $netamt    = substr( $line, 37,  12 );
      $salescnt  = substr( $line, 47,  12 );
      $salesamt  = substr( $line, 57,  12 );
      $returncnt = substr( $line, 74,  12 );
      $returnamt = substr( $line, 88,  12 );
      $rejectcnt = substr( $line, 106, 12 );
      $rejectamt = substr( $line, 118, 12 );
      $records =~ s/ //g;
      $netamt =~ s/ //g;
      $salescnt =~ s/ //g;
      $salesamt =~ s/ //g;
      $returncnt =~ s/ //g;
      $returnamt =~ s/ //g;
      $rejectcnt =~ s/ //g;
      $rejectamt =~ s/ //g;
      print "\nrecords: $records\n";
      print "netamt: $netamt\n";
      print "salescnt: $salescnt\n";
      print "salesamt: $salesamt\n";
      print "returncnt: $returncnt\n";
      print "returnamt: $returnamt\n";
      print "rejectcnt: $rejectcnt\n";
      print "rejectamt: $rejectamt\n\n";
    } elsif ( $line =~ /-FILE/ ) {
      $batchflag = 0;
      $fileflag  = 1;
    } elsif ( ( $fileflag == 1 ) && ( $line =~ /TOTALS +[0-9]/ ) ) {

      #($d1,$d2,$fileamt,$filebadamt) = split(/ +/,$line);
    } elsif ( $line =~ /FILE ACCEPTED/ ) {
      ( $d1, $d2, $d3, $d4, $fileamt ) = split( / +/, $line );
      $fileamt =~ s/[\$,]//g;
      $fileflag = 2;
    }

    if ( $fileamt =~ /^(.+)-$/ ) {
      $fileamt = "-" . $1;
    }
    print "dddd: $batchamt  $fileamt  $filebadamt  $fileflag  $username  $batchfile  $batchnum  $descr\n";

    if ( $fileflag == 2 ) {
      my $sthord = $dbh->prepare(
        qq{
            select count,amount
            from batchfilesfifth
            where trans_date>='$yesterday'
            and filenum='$filenum'
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthord->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      ( $chkfilecnt, $chkfileamt ) = $sthord->fetchrow;
      $sthord->finish;
      print "eeee: $filenum  $detailnum  $batchnum  $chkfilecnt  $chkfileamt\n";

      #update batchfilesfifth set status='done',reportnum='$filename'
      local $sth = $dbh->prepare(
        qq{
          update batchfilesfifth set status='done'
          where filenum='$filenum'
          and status='locked'
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    }

    # put in so if statement works with large amounts
    my $tmp = $chkfileamt - $problemamt;
    $fileamt = $fileamt + 0.00;
    $tmp     = $tmp + 0.00;
    $fileamt = sprintf( "%.2f", $fileamt );
    $tmp     = sprintf( "%.2f", $tmp );

    if ( ( $fileflag == 2 ) && ( $fileamt eq $tmp ) && ( $username ne "" ) ) {
      print "success aa: $username  $midamount{$mid}  $fields[2]\n";

      my $sthord = $dbh->prepare(
        qq{
            select orderid,username,batchnum
            from batchfilesfifth
            where trans_date>='$yesterday'
            and filenum='$filenum'
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthord->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthord->bind_columns( undef, \( $orderid, $username, $batchnum ) );

      while ( $sthord->fetch ) {
        print "successful: $username  $batchfile  $orderid  $batchnum\n";
        my $sth_trans = $dbh2->prepare(
          qq{
                update trans_log
                set finalstatus='success',trans_time=?
                where orderid='$orderid'
                and username='$username'
                and finalstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sth_trans->execute("$todaytime") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sth_trans->finish;

        my $sthop = $dbh2->prepare(
          qq{
                update operation_log set returnstatus='success',lastopstatus='success',returntime=?,lastoptime=?
                where orderid='$orderid'
                and username='$username'
                and processor='fifththird'
                and lastop='return'
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthop->execute( "$todaytime", "$todaytime" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sthop->finish;

        my $sthop = $dbh2->prepare(
          qq{
                update operation_log set postauthstatus='success',lastopstatus='success',postauthtime=?,lastoptime=?
                where orderid='$orderid'
                and username='$username'
                and processor='fifththird'
                and lastop='postauth'
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthop->execute( "$todaytime", "$todaytime" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sthop->finish;

      }
      $sthord->finish;

    } elsif ( $fileflag == 2 ) {
      umask 0077;
      open( outfile, ">>/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename.txt" );
      print outfile "$username\n";
      print outfile "File amount: $fileamt\n";
      print outfile "DB amount: $chkfileamt\n";
      print outfile "problem amount: $problemamt\n";
      print outfile "\n";
      close(outfile);

      print "$username locked\n";
      print "File amount: $fileamt\n";
      print "DB amount: $chkfileamt\n";
      print "problem amount: $problemamt\n";
      print "\n";
    }
  }
  close(infile);
  close(outfile);

  unlink "/home/pay1/batchfiles/$devprod/fifththird/$fileyear/$filename.out";
}

exit;

