#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use Net::FTP;
use Net::SFTP::Foreign;
use miscutils;
use procutils;
use rsautils;
use SHA;
use strict;

my $devprod = "logs";

my $redofile = "";

#my $redofile = "axn0.plgpay.xf00.P8017200721181114.cnf";

my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );

my ( $d1, $today, $todaytime ) = &miscutils::genorderid();
my $ttime = &miscutils::strtotime($today);

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 14 ) );
my $yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my $printstr = "\n\nin getfiles\n";
$printstr .= "\n$today  $yesterday\n";
&procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

my %datainfo = ();

my $dbh = "";

my $fileyear = substr( $today, 0, 4 );

#$fileyear = "2012";
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/$fileyear" ) {
  system("mkdir /home/pay1/batchfiles/$devprod/elavon/$fileyear");
}
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: elavon - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/elavon/$fileyear.\n\n";
  close MAILERR;
  exit;
}

my $batchfile = substr( $redofile, 0, 14 );

my %chkfilearray = ();

my $dbquerystr = <<"dbEOM";
        select distinct filename
        from batchfilesfdmsrc
        where trans_date>=?
        and processor=?
dbEOM
my @dbvalues = ( "$yesterday", "elavonfile" );
my @sthfilenamearray = &procutils::dbread( "elavon", "getfiles", "pnpmisc", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthfilenamearray) ; $vali = $vali + 1 ) {
  my $chkfilename = @sthfilenamearray[ $vali .. $vali + 0 ];

  #$chkfilename =~ s/\.edc//;
  $chkfilearray{"$chkfilename"} = 1;

}

my $printstr = "expecting results for:\n";
foreach my $key ( sort keys %chkfilearray ) {
  $printstr .= "$key\n";
}
$printstr .= "\n";
&procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

if ( $redofile ne "" ) {
  my $printstr = "\nabout to process redofile $redofile\n";
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

  &processfile($redofile);

  exit;
}

my $ftpun = 'nf001900';
my $ftppw = 'we3i#f#0';

#my $host = 'filegateway-test.elavon.com';             # test url
my $host = 'filegateway.elavon.com';    # production url

my $port = '20022';

#my @opts = ('-v');     # put '-v' at the begginning for debugging
#my %args = (user => "$ftpun", password => "$ftppw", port => $port, more=>[@opts]);
my %args = ( user => "$ftpun", password => "$ftppw", port => $port );

#my %args = (user => "$ftpun", password => "$ftppw", port => $port,
#            key_path => '/home/pay1/batchfiles/prod/elavon/.ssh/id_rsa');

my $ftp = Net::SFTP::Foreign->new( "$host", %args );

if ( $ftp eq "" ) {
  my $printstr = "Host $host username $ftpun and key don't work<br>\n";
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );
  exit;
}

$ftp->error and die "error: " . $ftp->error;

my $printstr = "logged in\n";
&procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

print "logged in \n";

if (1) {
  print "in /\n";
  my $files = $ftp->ls("/");

  if ( @$files == 0 ) {
    print "aa no report files\n";
  }
  foreach my $var (@$files) {
    my $fname = $var->{"filename"};

    print "aa " . $var->{"filename"} . "\n";
  }
}

if (1) {
  print "in /Inbox\n";
  my $files = $ftp->ls("/Inbox");

  if ( @$files == 0 ) {
    print "aa no report files\n";
  }
  foreach my $var (@$files) {
    my $fname = $var->{"filename"};

    print "aa " . $var->{"filename"} . "\n";
  }
}

my @filenamearray = ();

my $files = $ftp->ls("/Inbox");

if ( @$files == 0 ) {
  my $printstr = "aa no report files\n";
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );
}

foreach my $var (@$files) {
  my $filename = $var->{"filename"};

  my $chkfilename = $filename;

  # axn0.plgpay.xf00.P8017200714202028.cnf
  $chkfilename =~ s/^.*?\..*?\..*?\.//;
  $chkfilename =~ s/\.cnf//;
  $chkfilename .= ".edc";

  print "bb $chkfilename\n";

  if ( $chkfilearray{$chkfilename} != 1 ) {
    next;
  }

  #print "bb $chkfilename\n";

  #my $fileyear = "20" . substr($filename,5,2);
  my $fileyear = "20" . substr( $filename, 22, 2 ) . "/" . substr( $filename, 24, 2 ) . "/" . substr( $filename, 26, 2 );

  #my $printstr = "filename: $filename\n";
  #$printstr .= "fileyear: $fileyear\n\n";
  #&procutils::filewrite("elavon","elavon","/home/pay1/batchfiles/$devprod/elavon","ftplog.txt","append","misc",$printstr);
  print "bbbb $filename\n";

  if ( $filename =~ /(P8017.*cnf)/ ) {
    if ( ( !-e "/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename" ) && ( !-e "/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename.out" ) ) {
      my $printstr = "get outbox/$filename /home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename\n";
      &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

      #print "get outbox/$filename /home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename  ??? ";
      #my $chkline = <stdin>;
      #if ($chkline !~ /y/) {
      #exit;
      #}

      #$ftp->get("outbox/$filename","/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename", 'copy_perm' => 0, 'copy_time' => 0);
      my $outboxfilestr = $ftp->get_content("Inbox/$filename");

      my $printstr = "status: " . $ftp->status . "\n";
      if ( $ftp->error ) {
        $printstr = "error: " . $ftp->error . "\n";
      }
      $printstr .= "\n";
      &procutils::filewrite( "elavon", "getfiles", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );
      print "\n\n$outboxfilestr\n\n";
      print "/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename\n";

      #if ($filename =~ /\.(cnf)/) {
      #  my $fileencstatus = &procutils::fileencwrite("elavon","getfiles","/home/pay1/batchfiles/$devprod/elavon/$fileyear","$filename","write","",$outboxfilestr);
      #
      #          my $outfiletxtstr = "fileencwrite status: $fileencstatus\n";	# create a basic file so we know the file is stored in enc area
      #          &procutils::filewrite("elavon","getfiles","/home/pay1/batchfiles/$devprod/elavon/$fileyear","$filename.out","write","",$outfiletxtstr);
      #        }
      my $fileencstatus = &procutils::filewrite( "elavon", "getfiles", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$filename", "write", "", $outboxfilestr );

      @filenamearray = ( @filenamearray, $filename );
    }
  }
}

foreach my $filename (@filenamearray) {

  # yyyy
  my $printstr = "\nabout to process file $filename\n";
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

  &processfile($filename);

}

exit;

sub processfile {
  my ($filename) = @_;
  print "in processfile: $filename\n";

  #my $fileyear = "20" . substr($filename,5,2);
  my $fileyear = "20" . substr( $filename, 22, 2 ) . "/" . substr( $filename, 24, 2 ) . "/" . substr( $filename, 26, 2 );

  #$fileyear = "2012";

  my $printstr = "filename: $filename\n";
  $printstr .= "fileyear: $fileyear\n";
  &procutils::filewrite( "elavon", "getfiles", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

  my $detailflag = 0;
  my $batchflag  = 0;
  my $fileflag   = 0;
  my $batchnum   = "";
  my $deleteok   = 0;

  my $fileyear = "20" . substr( $filename, 22, 2 ) . "/" . substr( $filename, 24, 2 ) . "/" . substr( $filename, 26, 2 );

  my $infilestr = &procutils::fileread( "elavon", "getfiles", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$filename" );

  my @infilestrarray = split( /\n/, $infilestr );

  my $outfilestr = "";
  foreach (@infilestrarray) {
    my $line = $_;
    chop $line;

    # plgpay_edc-8017_P.200721_181114 file received.
    # P8017200721181114.edc

    if ( $line =~ /plgpay_([a-z]{3})-([0-9]{4})_P\.([0-9]{6})_([0-9]{6}) file received/ ) {
      my $newfile = "P" . $2 . $3 . $4 . "\." . $1;

      $outfilestr .= "$line\n\n";
      print "line: $line\n";

      if ( $chkfilearray{$newfile} == 1 ) {
        print "in db\n";
        $outfilestr .= "filename: $filename\n";
        $outfilestr .= "line: $line\n";
        $outfilestr .= "newfile: $newfile\n";
        $outfilestr .= "in db\n";
      }

      if ( $chkfilearray{$newfile} == 1 ) {
        my $dbquerystr = <<"dbEOM";
              update batchfilesfdmsrc
              set status='done'
              where trans_date>=?
              and filename=?
              and processor='elavonfile'
              and status in ('locked','locked1')
dbEOM
        my @dbvalues = ( "$yesterday", "$newfile" );
        &procutils::dbupdate( "elavonfile", "getfilesfile", "pnpmisc", $dbquerystr, @dbvalues );

        print "$yesterday $newfile elavonfile\n";

        my $dbquerystr = <<"dbEOM";
              select orderid,username,operation
              from batchfilesfdmsrc
              where trans_date>=?
              and filename=?
              and processor=?
dbEOM
        my @dbvalues = ( "$yesterday", "$newfile", "elavonfile" );
        my @sthordvalarray = &procutils::dbread( "elavonfile", "getfilesfile", "pnpmisc", $dbquerystr, @dbvalues );
        print "$dbquerystr\n";

        for ( my $vali = 0 ; $vali < scalar(@sthordvalarray) ; $vali = $vali + 3 ) {
          my ( $orderid, $username, $operation ) = @sthordvalarray[ $vali .. $vali + 2 ];

          my $dbquerystr = <<"dbEOM";
                update trans_log
                set finalstatus='success',trans_time=?
                where orderid=?
                and username=?
                and operation=?
                and finalstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
          my @dbvalues = ( "$todaytime", "$orderid", "$username", "$operation" );
          &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

          my $operationstatus = $operation . "status";
          my $operationtime   = $operation . "time";

          my $dbquerystr = <<"dbEOM";
                update operation_log set $operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?
                where orderid=?
                and username=?
                and processor='elavon'
                and lastop=?
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
dbEOM
          my @dbvalues = ( "$todaytime", "$todaytime", "$orderid", "$username", "$operation" );
          &procutils::dbupdate( $username, $orderid, "pnpdata", $dbquerystr, @dbvalues );

        }

      } elsif (0) {
        open( MAILERR, "| /usr/lib/sendmail -t" );
        print MAILERR "To: cprice\@plugnpay.com\n";
        print MAILERR "From: dcprice\@plugnpay.com\n";
        print MAILERR "Subject: elavon - settlement file - FAILURE\n";
        print MAILERR "\n";
        print MAILERR "Couldn't find record.\n\n";
        print MAILERR "filename: $filename\n";
        print MAILERR "newfile: $newfile\n\n";
        close MAILERR;
        exit;
      }
    } else {
      $outfilestr .= "$line\n";
    }
  }

  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon/$fileyear", "$filename.out", "write", "", $outfilestr );

  #&procutils::fileencwrite("elavon","elavon","/home/pay1/batchfiles/$devprod/elavon/$fileyear","$filename.wasnow","write","",$wasnowfilestr);
  #&procutils::filewrite("elavon","elavon","/home/pay1/batchfiles/$devprod/elavon/$fileyear","$filename.wasnow.txt","write","",$wasnowtxtfilestr);

  if ( $deleteok == 1 ) {

    #unlink "/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename";
    #unlink "/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename.out";
    #unlink "/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename.pgp";
  } else {
    my $printstr = "ready to delete?...";
    &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

    #my $aaa  = $stdinstrarray[0];
    #if ($aaa =~ /^y/) {
    #unlink "/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename";
    #unlink "/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename.out";
    #unlink "/home/pay1/batchfiles/$devprod/elavon/$fileyear/$filename.pgp";
    #}
  }
}

exit;

