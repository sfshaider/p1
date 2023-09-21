#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::SFTP::Foreign;
use miscutils;
use rsautils;
use SHA;
use GnuPG qw( :algo );

#use strict;

#$fdmsaddr = "206.201.53.145";  # test server
my $fdmsaddr = "64.69.201.25";    # production server

my $redofile = "";

#my $redofile = "20110323185135.nxjv8823.0001";

my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );

my ( $d1, $today, $todaytime ) = &miscutils::genorderid();
my $ttime = &miscutils::strtotime($today);

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 66 ) );
my $yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my $mytime = gmtime( time() );
print "\n$mytime\n\n";

my $fileyear = substr( $today, 0, 4 );
if ( !-e "/home/p/pay1/batchfiles/globalctf/logs/$fileyear" ) {
  system("mkdir /home/p/pay1/batchfiles/globalctf/logs/$fileyear");
}
if ( !-e "/home/p/pay1/batchfiles/globalctf/logs/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: globalctf - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory globalctf/logs/$fileyear.\n\n";
  close MAILERR;
  exit;
}

my %datainfo = ();

my $dbh = &miscutils::dbhconnect("pnpmisc");

my $batchfile = substr( $redofile, 0, 14 );

if ( $redofile ne "" ) {
  &processfile($redofile);
  $dbh->disconnect;
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
        select filename
        from batchfilesctf
        where status='locked'
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthbatch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
($batchfile) = $sthbatch->fetchrow;
$sthbatch->finish;

if ( $batchfile eq "" ) {
  print "No files needed\n";
  $dbh->disconnect;
  exit;
}

#$batchcnt = 0;
#while ($sthbatch->fetch) {
#  $filename = $batchfile;
#  $batchcnt++;
#print "aaaa $filename  $batchcnt\n";
#}
#$sthbatch->finish;

#if ($batchcnt < 1) {
#  print "More/less than one locked batch  $batchcnt   exiting\n";
#  exit;
#}

if (0) {
  my $ftpun = 'NXJV8823';
  my $ftppw = 'Rd2nyqKc';

  my $ftp = Net::FTP->new( "$fdmsaddr", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21" );
  if ( $ftp eq "" ) {
    print "Host $fdmsaddr is no good<br>\n";
    print "failure";
    $ftp = Net::FTP->new( "$fdmsaddr", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21" );
    if ( $ftp eq "" ) {
      exit;
    }
  }

  if ( $ftp->login( "$ftpun", "$ftppw" ) eq "" ) {
    print "Username $ftpun and password don't work<br>\n";
    print "failure";
    exit;
  }
}

my $ftpun = 'PLUGNPAYCTF2012';
my $host  = 'FT.PROD.GLOBALPAY.COM';
my $port  = '10022';

#my @opts = ('-v','-i','/home/p/pay1/.ssh/id_rsa');     # put '-v' at the begginning for debugging
my @opts = ( '-i', '/home/p/pay1/.ssh/id_rsa' );    # put '-v' at the begginning for debugging
my %args = (
  user => "$ftpun",
  port => 10022,

  #more => [-i => '/home/p/pay1/.ssh/id_rsa'] );
  more => [@opts]
);

my $ftp = Net::SFTP::Foreign->new( "$host", %args );

if ( $ftp eq "" ) {
  print "Host $host username $ftpun and key don't work<br>\n";
  exit;
}

$ftp->error and die "SSH connection failed: " . $ftp->error;

print "logged in\n";

#$ftp->quot("SITE FILETYPE=JES");
#$ftp->get("REMOTES.RCVPLU2.CONFIRM5","/home/p/pay1/batchfiles/globalctf/logs/temp.out");

#my $ls = $ftp->cwd();
#print "cwd: $ls\n";

print "before ls\n";

$ls = $ftp->ls("/OUTPUT");
$ftp->error and die "SSH command failed: " . $ftp->error;

#my @files = $ftp->ls("/in/$achfilename");

my $fn            = "";
my @filenamearray = ();
foreach my $var (@$ls) {
  print "aaaa " . $var->{"filename"} . "\n";
  $fn = $var->{"filename"};

  if ( $fn =~ /.done$/ ) {
    next;
  }

  my $fileyear = substr( $fn, 0, 4 );
  if ( !-e "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$fn" ) {
    print "get /OUTPUT/$fn  /home/p/pay1/batchfiles/globalctf/logs/$fileyear/$fn\n";
    $ftp->get( "/OUTPUT/$fn", "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$fn" );

    #if ($fn =~ /.pgp$/) {
    #  &decrypt_file("$fn");
    #  $fn =~ s/.pgp$/.out/;
    #}
    @filenamearray = ( @filenamearray, $fn );
  }
  if ( -e "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$fn" ) {
    $ftp->rename( "$fn", "$fn.done" );
  }
}

#$ftp->quit();

foreach my $filename (@filenamearray) {
  &processfile($filename);
}

$dbh->disconnect;

exit;

sub processfile {
  my ($filename) = @_;

  my $fileyear = substr( $filename, 0, 4 );

  if (0) {

    my $count       = "";
    my $amount      = "";
    my $username    = "";
    my $merchant_id = "";
    my $batchnum    = "";
    my $batchfile   = "";

    my $sth3 = $dbh->prepare(
      qq{
        select distinct b.count,b.amount,b.username,c.merchant_id,b.batchnum,b.filename
        from batchfilesfifth b, customers c
        where b.status='locked'
        and c.username=b.username
        and c.processor='globalctf'
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth3->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    $sth3->bind_columns( undef, \( $count, $amount, $username, $merchant_id, $batchnum, $batchfile ) );

    my $batchcnt = 0;
    my $batchamt = 0;
    while ( $sth3->fetch ) {

      #$newmid = substr($merchant_id,0,7);
      #$midamount{$newmid} = $amount;
      #$userarray{$newmid} = $username;
      #$batchnumarray{$newmid} = $batchnum;
      #$batchfilearray{$newmid} = $batchfile;
      #$newmidcnt{$newmid}++;
      #$batchamt = $batchamt + $amount;
      #$batchcnt = $batchcnt++;
    }
    $sth3->finish;

  }

  print "filename: $filename\n";
  my $detailflag = 0;
  my $batchflag  = 0;
  my $fileflag   = 0;
  my $batchnum   = "";

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

  $filenum = substr( $filename, 0, 14 );

  my $sth_trans = $dbh->prepare(
    qq{
        update batchfilesctf
        set status='done'
        where trans_date>='$yesterday'
        and filename='$filenum'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth_trans->execute() or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth_trans->finish;

  open( infile,  "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename" );
  open( outfile, ">/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.done" );
  while (<infile>) {
    my $line = $_;
    chop $line;

    if ( $line =~ /^FH/ ) {
      print outfile "$line\n";
    } elsif ( $line =~ /^MH/ ) {
      print outfile "$line\n";
      $bankid = substr( $line, 2, 6 );
      $mid    = substr( $line, 8, 15 );
      $mid =~ s/ //g;
      print "bankid: $bankid\n";
      print "mid: $mid\n";
    } elsif ( $line =~ /^OK / ) {
      print outfile "$line\n";
      my ( $d1, $batchamt, $batchcnt, $id, $id2 ) = split( / /, $line );

      print "batchamt: $batchamt\n";
      print "batchcnt: $batchcnt\n";
      print "id: $id\n";
      print "id2: $id2\n";

      print "successful: $orderid\n";
      print "filenum: $filenum\n";

      my $sthord = $dbh->prepare(
        qq{
            select username,orderid,status,operation
            from batchfilesctf
            where trans_date>='$yesterday'
            and filename='$filenum'
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthord->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sthord->bind_columns( undef, \( $username, $orderid, $status, $operation ) );

      #if ($username eq "") {
      #  open(MAILERR,"| /usr/lib/sendmail -t");
      #  print MAILERR "To: cprice\@plugnpay.com\n";
      #  print MAILERR "From: dcprice\@plugnpay.com\n";
      #  print MAILERR "Subject: globalctf - batchfilesctf - FAILURE\n";
      #  print MAILERR "\n";
      #  print MAILERR "Couldn't find file.\n\n";
      #  print MAILERR "filename: $filename\n\n";
      #  close MAILERR;
      #  exit;
      #}

      while ( $sthord->fetch ) {
        $operationstatus = $operation . "status";
        $operationtime   = $operation . "time";
        print "orderid: $orderid\n";
        print "status: $status\n";
        print "operation: $operation\n";
        print "filenum: $filenum\n";

        my $dbh2 = &miscutils::dbhconnect("pnpdata");

        my $sth_trans = $dbh2->prepare(
          qq{
                update trans_log
                set finalstatus='success',trans_time=?
                where orderid='$orderid'
                and result='$filenum'
                and operation='$operation'
                and finalstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sth_trans->execute("$todaytime") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sth_trans->finish;

        #and trans_date>='$twomonthsago'
        my $sthop = $dbh2->prepare(
          qq{
                update operation_log set $operationstatus='success',lastopstatus='success',$operationtime=?,lastoptime=?
                where orderid='$orderid'
                and username='$username'
                and batchfile='$filenum'
                and processor='globalctf'
                and lastop='$operation'
                and lastopstatus='locked'
                and (accttype is NULL or accttype='' or accttype='credit')
                }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sthop->execute( "$todaytime", "$todaytime" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sthop->finish;

        $dbh2->disconnect;

        print "yesterday: $yesterday\n";
        print "username: $username\n";
        print "orderid: $orderid\n";
        print "status: $status\n\n";
      }
      $sthord->finish;

    } elsif ( $line =~ /^ERR/ ) {
      print outfile "$line\n";
      my ( $d1, $linenum, $descr ) = split( / /, $line, 3 );
      $descr =~ s/ +$//g;

      $linenum = $linenum + 0;

      my $sthord = $dbh->prepare(
        qq{
            select username,orderid,status
            from batchfilesctf
            where trans_date>='$yesterday'
            and detailnum='$linenum'
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sthord->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      my ( $username, $orderid, $status ) = $sthord->fetchrow;
      $sthord->finish;

      print "yesterday: $yesterday\n";
      print "username: $username\n";
      print "orderid: $orderid\n";
      print "status: $status\n\n";

      if ( ( $orderid ne "" ) && ( $username ne "" ) ) {
        my $sth_trans = $dbh->prepare(
          qq{
                update batchfilesctf
                set status='done',newdata=?
                where trans_date>='$yesterday'
                and shacardnumber='$shacardnumber'
                and status in ('locked','locked1')
                }
          )
          or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
        $sth_trans->execute("$encdata") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
        $sth_trans->finish;

        open( MAILERR, "| /usr/lib/sendmail -t" );
        print MAILERR "To: cprice\@plugnpay.com\n";
        print MAILERR "From: dcprice\@plugnpay.com\n";
        print MAILERR "Subject: globalctf - batchfilesctf - FAILURE\n";
        print MAILERR "\n";
        print MAILERR "Detail error.\n\n";
        print MAILERR "filename: $filename\n\n";
        print MAILERR "linenum: $linenum\n\n";
        print MAILERR "username: $username\n\n";
        print MAILERR "orderid: $orderid\n\n";
        close MAILERR;
      } else {
        open( MAILERR, "| /usr/lib/sendmail -t" );
        print MAILERR "To: cprice\@plugnpay.com\n";
        print MAILERR "From: dcprice\@plugnpay.com\n";
        print MAILERR "Subject: globalctf - batchfilesctf - FAILURE\n";
        print MAILERR "\n";
        print MAILERR "Couldn't find record.\n\n";
        print MAILERR "filename: $filename\n\n";
        close MAILERR;
        exit;
      }
    } else {
      print outfile "$line\n";
    }
  }
  close(infile);

  #unlink "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename";
}

exit;

#require 'sys/ipc.ph';
#  require 'sys/msg.ph';

#$ENV{'PATH'} .= ":/usr/share/import/bin";

&encrypt_file("20090325171513");
exit;

sub encrypt_file {
  my ($filename) = @_;

  my $gpg           = new GnuPG();
  my $plaintextfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename";
  my $encryptedfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp";

  $gpg->encrypt(
    plaintext => "$plaintextfile",
    output    => "$encryptedfile",
    recipient => "Global (Global GnuPG key)",
    armor     => 1,
  );

  #$gpg->encrypt(plaintext=>"$plaintextfile",
  #              output=>"$encryptedfile",
  #              armor=>1,
  #              recipient=>"GLOBAL"
  #             );

  #unlink("$plaintxtfile");

}

sub decrypt_file {
  my ($filename) = @_;

  my $encryptedfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp";
  my $plaintextfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.out";
  my $gpg           = new GnuPG();

  $gpg->decrypt(
    ciphertext => "$encryptedfile",
    output     => "$plaintextfile",
    recipient  => "",
  );

  #$gpg->decrypt( ciphertext => "$encryptedfile",
  #               output => "$plaintextfile",
  #               passphrase => $passphrase );

}

#sub verify {
#  my ($filename,$passphrase) = @_;

#  my $encryptedfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp";
#  my $encryptedfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp";
#    $gpg->verify( signature => "file.txt.asc", file => "file.txt" );
#}

sub generate_key {
  my $gpg = new GnuPG();

  #$gpg->gen_key( name => "Global",
  #               comment => "Global GnuPG key",
  #             );

  #$gpg->gen_key( name => "Global",      comment => "Global GnuPG key",
  #               passphrase => $secret,
  #             );

  $gpg->export_keys(
    keys    => "Global",
    comment => "Global GnuPG key",
    armor   => 1,
    output  => "/home/p/pay1/batchfiles/globalctf/globalpgpkey.pub",
  );
}

sub import_key {
  my $gpg = new GnuPG();

  $gpg->import_keys( keys => "/home/p/pay1/batchfiles/globalctf/globalpgpkey.sec", );
}

