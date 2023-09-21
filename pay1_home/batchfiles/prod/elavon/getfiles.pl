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

#my $redofile = "P8836191011031202.rud";

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
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear" ) {
  system("mkdir /home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear");
}
if ( !-e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: elavon - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory logs/elavon/acctlogs/$fileyear.\n\n";
  close MAILERR;
  exit;
}

my $batchfile = substr( $redofile, 0, 14 );

if ( $redofile ne "" ) {
  my $printstr = "\nabout to process redofile $redofile\n";
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

  &processfile($redofile);

  exit;
}

my %chkfilearray = ();

my $dbquerystr = <<"dbEOM";
        select distinct filename
        from accountupd
        where trans_date>=?
dbEOM
my @dbvalues = ("$yesterday");
my @sthfilenamearray = &procutils::dbread( "elavon", "getfiles", "pnpmisc", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthfilenamearray) ; $vali = $vali + 1 ) {
  my $chkfilename = @sthfilenamearray[ $vali .. $vali + 0 ];
  $chkfilename =~ s/\.auc//;
  $chkfilearray{"$chkfilename"} = 1;

}

my $printstr = "expecting results for:\n";
foreach my $key ( sort keys %chkfilearray ) {
  $printstr .= "$key\n";
}
$printstr .= "\n";
&procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

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
  $chkfilename =~ s/\..*$//;

  #print "aa $chkfilename\n";

  if ( $chkfilearray{$chkfilename} != 1 ) {
    next;
  }

  #print "bb $chkfilename\n";

  #my $fileyear = "20" . substr($filename,5,2);
  my $fileyear = "20" . substr( $filename, 5, 2 ) . "/" . substr( $filename, 7, 2 ) . "/" . substr( $filename, 9, 2 );

  #my $printstr = "filename: $filename\n";
  #$printstr .= "fileyear: $fileyear\n\n";
  #&procutils::filewrite("elavon","elavon","/home/pay1/batchfiles/$devprod/elavon","ftplog.txt","append","misc",$printstr);

  if ( $filename =~ /(cnf|rud|mud)/ ) {
    if ( ( !-e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename" ) && ( !-e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename.out" ) ) {
      my $printstr = "get outbox/$filename /home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename\n";
      &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

      #print "get outbox/$filename /home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename  ??? ";
      #my $chkline = <stdin>;
      #if ($chkline !~ /y/) {
      #exit;
      #}

      #$ftp->get("outbox/$filename","/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename", 'copy_perm' => 0, 'copy_time' => 0);
      my $outboxfilestr = $ftp->get_content("Inbox/$filename");

      my $printstr = "status: " . $ftp->status . "\n";
      if ( $ftp->error ) {
        $printstr = "error: " . $ftp->error . "\n";
      }
      $printstr .= "\n";
      &procutils::filewrite( "elavon", "accountupd", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

      my $addtolist = 0;
      if ( ( $filename =~ /\.(rud|mud)/ ) && ( !-e "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename.out" ) ) {
        $addtolist = 1;    # file needs to be processed
      }

      if ( $filename =~ /\.(rud|mud)/ ) {
        my $fileencstatus = &procutils::fileencwrite( "elavon", "accountupd", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename", "write", "", $outboxfilestr );

        my $outfiletxtstr = "fileencwrite status: $fileencstatus\n";    # create a basic file so we know the file is stored in enc area
        &procutils::filewrite( "elavon", "accountupd", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename.out", "write", "", $outfiletxtstr );
      } elsif ( $filename =~ /\.cnf/ ) {
        my $fileencstatus = &procutils::filewrite( "elavon", "accountupd", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename", "write", "", $outboxfilestr );
      }

      if ( ( $filename =~ /\.(rud|mud)/ ) && ( $addtolist == 1 ) ) {
        @filenamearray = ( @filenamearray, $filename );
      }
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

  #my $fileyear = "20" . substr($filename,5,2);
  my $fileyear = "20" . substr( $filename, 5, 2 ) . "/" . substr( $filename, 7, 2 ) . "/" . substr( $filename, 9, 2 );

  #$fileyear = "2012";

  my $wasnowfilestr    = "";
  my $wasnowtxtfilestr = "";

  my %refarray = ();

  #my $reffilename = "P8836" . substr($filename,-13,6) . substr($filename,-6,6) . ".auc.ref";
  my $reffilename = $filename;
  $reffilename =~ s/.rud/.auc.ref/;
  $reffilename =~ s/.mud/.auc.ref/;

  my $reffilestr = &procutils::fileread( "elavon", "accountupd", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$reffilename" );

  my @reffilestrarray = split( /\n/, $reffilestr );
  foreach (@reffilestrarray) {
    my $line = $_;
    chop $line;

    my ( $database, $username, $refnumber ) = split( / /, $line );
    $refarray{"$refnumber"} = "$database $username";

    #print "cc $refnumber    $database $username\n";
  }

  my $merchdata     = "";
  my $database      = "";
  my $username      = "";
  my $bankid        = "";
  my $mid           = "";
  my $oldcardnumber = "";
  my $oldexp        = "";
  my $newcardnumber = "";
  my $newexp        = "";
  my $xs            = "";
  my $shacardnumber = "";
  my $cardnumber    = "";
  my $exp           = "";

  my $printstr = "filename: $filename\n";
  $printstr .= "fileyear: $fileyear\n";
  &procutils::filewrite( "elavon", "accountupd", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

  my $detailflag = 0;
  my $batchflag  = 0;
  my $fileflag   = 0;
  my $batchnum   = "";
  my $deleteok   = 0;

  #my $fileyear = "20" . substr($filename,5,2);
  my $fileyear = "20" . substr( $filename, 5, 2 ) . "/" . substr( $filename, 7, 2 ) . "/" . substr( $filename, 9, 2 );

  #print "fileencread: $fileyear    $filename\n";
  my $infilestr = &procutils::fileencread( "elavon", "accountupd", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename" );

  my @infilestrarray = split( /\n/, $infilestr );

  my $outfilestr = "";
  foreach (@infilestrarray) {
    my $line = $_;
    chop $line;

    #print "line: $line\n";

    if ( $line =~ /^10/ ) {
      $outfilestr .= "$line\n";
    } elsif ( $line =~ /^19/ ) {
      $outfilestr .= "$line\n";
      $deleteok = 1;
    } elsif ( $line =~ /^30/ ) {
      $outfilestr .= "$line\n";
      $bankid = substr( $line, 2, 6 );
      $mid    = substr( $line, 8, 15 );
      $mid =~ s/ //g;
    } elsif ( $line =~ /^50/ ) {
      $oldcardnumber = substr( $line, 11, 16 );
      $oldcardnumber =~ s/ //g;
      $oldexp = substr( $line, 27, 4 );
      $oldexp =~ s/ //g;
      if ( $oldexp ne "" ) {
        $oldexp = substr( $oldexp, 0, 2 ) . "/" . substr( $oldexp, 2, 2 );
      }

      my $xs = "x" x length($oldcardnumber);
      $line =~ s/$oldcardnumber/$xs/;
      $outfilestr .= "$line\n";
    } elsif ( $line =~ /^60/ ) {
      my $linelength = length($line);
      $newcardnumber = substr( $line, 9, 19 );
      $newcardnumber =~ s/ //g;
      $newexp = substr( $line, 28, 4 );
      $newexp =~ s/ //g;
      $newexp =~ s/0000//g;
      my $refnumber = substr( $line, 32, 30 );
      $refnumber =~ s/ //g;
      $merchdata = $refarray{"$refnumber"};
      ( $database, $username ) = split( / /, $merchdata );

      if ( $newexp ne "" ) {
        $newexp = substr( $newexp, 0, 2 ) . "/" . substr( $newexp, 2, 2 );
      }
      my $respcode = substr( $line, 62, 1 );

      #print "\n\nmerchdata: $merchdata    database: $database    username: $username\n";
      #print "oldcardnumber: $oldcardnumber    oldexp: $oldexp    $respcode\n";
      #print "newcardnumber: $newcardnumber    newexp: $newexp\n\n";

      if ( $newcardnumber ne "" ) {
        $xs = "x" x length($newcardnumber);
        $line =~ s/$newcardnumber/$xs/;
      }
      $outfilestr .= "$line\n";

      if ( $newcardnumber ne "" ) {
        $cardnumber = "$newcardnumber";
      } else {
        $cardnumber = "$oldcardnumber";
      }

      if ( $newexp ne "" ) {
        $exp = "$newexp";
      } else {
        $exp = "$oldexp";
      }

      my $luhn10 = &miscutils::luhn10($cardnumber);

      #my $encdata = "";
      #if ((($newcardnumber ne "") || ($newexp ne "")) && ($luhn10 ne "failure") && ($cardnumber ne "") && ($exp ne "")) {
      #  ($encdata) = &rsautils::rsa_encrypt_card("$exp $cardnumber",'/home/pay1/pwfiles/keys/key','log');
      #}

      my $dbquerystr = <<"dbEOM";
            select username,orderid,status,filename
            from accountupd
            where trans_date>=?
            and username=?
            and orderid=?
            and status in ('locked','done')
            order by trans_date desc
dbEOM
      my @dbvalues = ( "$yesterday", "$database", "$username" );
      my ( $database, $username, $status, $merchfilename ) = &procutils::dbread( $database, $username, "pnpmisc", $dbquerystr, @dbvalues );

      #print "yesterday: $yesterday    database: $database    username: $username    status: $status\n\n";

      if ( ( $database ne "" ) && ( $username ne "" ) ) {
        my $dbquerystr = <<"dbEOM";
                update accountupd
                set status='done'
                where trans_date>=?
                and username=?
                and orderid=?
                and status in ('locked','locked1')
dbEOM
        my @dbvalues = ( "$yesterday", "$database", "$username" );
        &procutils::dbupdate( $database, $username, "pnpmisc", $dbquerystr, @dbvalues );

      }

      if ( ( $database ne "" ) && ( $username ne "" ) && ( ( $newexp ne "" ) || ( $cardnumber ne "" ) ) ) {
        my $enccardnumber = "";
        if ( ( $cardnumber =~ /^[0-9]{13,19}/ ) && ( $respcode eq "A" ) ) {

          #my $oldenccardnumber = &smpsutils::getcardnumber($database,$username,'bill_member',$enccardnumber,'rec');
          #my $oldlength = 0;
          #my $oldchkcardnumber = &rsautils::rsa_decrypt_file($oldenccardnumber,$oldlength,"print enccardnumber 497","/home/pay1/pwfiles/keys/key");
          $wasnowfilestr .= "$database $username $oldcardnumber $oldexp $cardnumber $newexp $respcode\n";

          my $xoldchkcardnumber = $oldcardnumber;
          $xoldchkcardnumber =~ s/^(....)[0-9]+(....)/$1\.\.\.\.\.\.\.\.$2/;
          my $xcardnumber = $cardnumber;
          $xcardnumber =~ s/^(....)[0-9]+(....)/$1\.\.\.\.\.\.\.\.$2/;
          $wasnowtxtfilestr .= "$database $username $xoldchkcardnumber $oldexp $xcardnumber $newexp $respcode\n";

          # encrypt the new card number and decrypt it to make sure it encrypted ok
          ($enccardnumber) = &rsautils::rsa_encrypt_card( "$cardnumber", '/home/pay1/pwfiles/keys/key', 'log' );
          my $length = 0;
          my $chkcardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/pay1/pwfiles/keys/key" );

          my $maskcardnumber = $oldcardnumber;
          $maskcardnumber =~ s/^(......)[0-9]+(....)$/$1\*\*\*\*\*\*$2/;

          if ( ( $enccardnumber ne "" ) && ( $chkcardnumber eq $cardnumber ) ) {

            #print "save enccardnumber in secure area\n";
            $enccardnumber = &smpsutils::storecardnumber( $database, $username, 'bill_member', $enccardnumber, 'rec' );

            $maskcardnumber = $cardnumber;
            $maskcardnumber =~ s/^(......)[0-9]+(....)$/$1\*\*\*\*\*\*$2/;

            #print "save empty enccardnumber in customer table\n";

            my $dbquerystr = <<"dbEOM";
                  update customer set cardnumber=?,enccardnumber=?
                  where username=?
dbEOM
            my @dbvalues = ( "$maskcardnumber", "$enccardnumber", "$username" );
            &procutils::dbupdate( $database, $username, "$database", $dbquerystr, @dbvalues );
          }
        }

        if ( ( $newexp ne $oldexp ) && ( $newexp =~ /[0-9]{2}\/[0-9]{2}/ ) ) {

          #print "save new exp\n";

          if ( $respcode ne "A" ) {
            $wasnowfilestr    .= "$database $username  $oldexp  $newexp $respcode\n";
            $wasnowtxtfilestr .= "$database $username  $oldexp  $newexp $respcode\n";
          }

          my $dbquerystr = <<"dbEOM";
                update customer set exp=?
                where username=?
dbEOM
          my @dbvalues = ( "$newexp", "$username" );
          &procutils::dbupdate( $database, $username, "$database", $dbquerystr, @dbvalues );
        }

      } elsif (0) {
        open( MAILERR, "| /usr/lib/sendmail -t" );
        print MAILERR "To: cprice\@plugnpay.com\n";
        print MAILERR "From: dcprice\@plugnpay.com\n";
        print MAILERR "Subject: elavon - account update - FAILURE\n";
        print MAILERR "\n";
        print MAILERR "Couldn't find record.\n\n";
        print MAILERR "filename: $filename\n\n";
        print MAILERR "database: $database\n\n";
        print MAILERR "username: $username\n\n";
        close MAILERR;
        exit;
      }
    } else {
      $outfilestr .= "$line\n";
    }
  }

  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename.out", "write", "", $outfilestr );
  &procutils::fileencwrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename.wasnow", "write", "", $wasnowfilestr );
  &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear", "$filename.wasnow.txt", "write", "", $wasnowtxtfilestr );

  if ( $deleteok == 1 ) {

    #unlink "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename";
    #unlink "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename.out";
    #unlink "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename.pgp";
  } else {
    my $printstr = "ready to delete?...";
    &procutils::filewrite( "elavon", "elavon", "/home/pay1/batchfiles/$devprod/elavon", "ftplog.txt", "append", "misc", $printstr );

    #my $aaa  = $stdinstrarray[0];
    #if ($aaa =~ /^y/) {
    #unlink "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename";
    #unlink "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename.out";
    #unlink "/home/pay1/batchfiles/$devprod/elavon/acctlogs/$fileyear/$filename.pgp";
    #}
  }
}

exit;

