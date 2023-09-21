#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::FTP;
use Net::SFTP::Foreign;
use miscutils;
use GnuPG qw( :algo );
use strict;

#print "exiting because this must be done manually for now.\n";
#exit;

# sftp -oIdentityFile=/home/p/pay1/.ssh/id_rsa -oPort=10022 PLUGNPAYCTF2012@FT.PROD.GLOBALPAY.COM # production

#If VPN ipaddress is: 10.150.10.1
#If public ipaddress is:  69.18.198.8

#&decrypt_file("20090326144643.nxjv8823.9999.usr.vi0761004140");
#exit;
#&encrypt_file("consumers120090325140504");

my $redofile = "";

#my $redofile = "consumers120090325140504";

my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
my $julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

my ( $d1, $today ) = &miscutils::genorderid();
my $ttime = &miscutils::strtotime($today);
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 20 ) );
my $yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
print "\n\n$today  $yesterday\n";

my %datainfo = ();
my $username = "";
my $filename = "";
my $globalid = "";
my $bankid   = "";

my $ftpun = 'NXJV8823';
my $ftppw = 'Rd2nyqKc';

my $dbh = &miscutils::dbhconnect("pnpmisc");

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

if (0) {
  my $ftp = Net::FTP->new( "64.69.201.25", 'Timeout' => 2400, 'Debug' => 1, 'Port' => "21", 'LocalAddr' => 'processor-host' );
  if ( $ftp eq "" ) {
    print "Host is no good<br>\n";
    exit;
  }

  if ( $ftp->login( "$ftpun", "$ftppw" ) eq "" ) {
    print "Username $ftpun and password don't work<br>\n";
    exit;
  }
}

if ( $redofile ne "" ) {
  &sendfile("$redofile");

  #$ftp->quit;
  exit;
}

#$mode = "binary";
#$ftp->type("$mode");
print "aaaa\n";

my $sthbatch = $dbh->prepare(
  qq{
        select distinct username,filename
        from batchfilesctf
        where trans_date>='$yesterday'
        and status in ('pending')
        }
  )
  or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
$sthbatch->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
$sthbatch->bind_columns( undef, \( $username, $filename ) );

while ( $sthbatch->fetch ) {
  &sendfile("$filename");
}
$sthbatch->finish;

#$ftp->quit;

$dbh->disconnect;

exit;

sub sendfile {
  my ($filename) = @_;

  my $hourminsec = substr( $filename, -14, 14 );
  print "aaaa $filename\n";
  print "bbbb $username\n";
  $username = $filename;
  print "cccc $username\n";
  $username =~ s/$hourminsec//;
  print "dddd $username\n";

  print "$hourminsec $username\n";

  #my $sthcust = $dbh->prepare(qq{
  #      select acctglobalid,bankid
  #      from global
  #      where username='$username'
  #      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  #$sthcust->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);
  #($globalid,$bankid) = $sthcust->fetchrow;
  #$sthcust->finish;

  #if ($globalid eq "") {
  #  print "Missing Big Batch ID  $username\n";
  #  next;
  #}

  #my ($lsec,$lmin,$lhour,$lday,$lmonth,$lyear,$wday,$yday,$isdst) = localtime(time());
  #my $ltrandate = sprintf("%04d%02d%02d%02d%02d%02d", 1900+$lyear, $lmonth+1, $lday, $lhour, $lmin, $lsec);
  print "$filename\n";

  my $hourminsec = substr( $filename, -14, 14 );

  #my $userid = substr($ftpun,0,4) . substr($ftpun,-4,4);

  #my $newfilename = "$hourminsec.$bankid.$globalid";  # production with pgp
  #print "$newfilename\n";

  $hourminsec = substr( $filename, -14, 14 );

  #my $newfilename = "$hourminsec.$userid." . "0001";  # production
  my $newfilename = "$hourminsec.NXJV8823." . "0001";    # production
  print "$newfilename\n";

  my $fileyear = substr( $hourminsec, 0, 4 );
  &encrypt_file("$filename");

  print "$filename.pgp $newfilename.pgp\n";
  print "put /home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp  /INPUT/$newfilename.pgp\n";

  $ftp->put( "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp", "/INPUT/$newfilename.pgp", 'copy_perm' => 0, 'copy_time' => 0 );
  $ftp->error and die "SSH command failed: " . $ftp->error;
  print "after put\n";

  #$ftp->rename("/ccs/ecommerce/t$filename","/ccs/ecommerce/$filename");

  print "$yesterday $username $filename\n";
  my $sthupd = $dbh->prepare(
    qq{
        update batchfilesctf
        set status='locked'
        where trans_date>='$yesterday'
        and status='pending'
        and filename='$filename'
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sthupd->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sthupd->finish;

  my $files = $ftp->ls('/INPUT')
    or die "unable to retrieve directory: " . $ftp->error;

  #print "aaaa $_->{filename}\n" for (@$files);

  if ( @$files == 0 ) {
    print "aa no report files\n";
  }
  foreach my $var (@$files) {

    #my $yearmonthdec = substr($filename,0,8);
    #my $fname = $var->{"filename"};
    #if ($fname =~ /$yearmonthdec/) {
    print "aa " . $var->{"filename"} . "\n";

    #}

    my $filenm = $var->{"filename"};
    if ( $filenm =~ /$filename/ ) {
      unlink "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename";
      unlink "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp";
    }

    #foreach $key (sort keys %$var){
    #  print "bb the value is $key =>" .  $var->{$key} . "\n";
    #}
  }

  #$ftp->cwd("ftp_dir/out");
  #my @list = $ftp->ls("/$userid/IN/$newfilename.pgp");
  #if (@list == 0) {
  #  print "aa no report files\n";
  #}
  #foreach my $var (@list) {
  #  print "aa var: $var\n";

  # xxxx temp for testing  for prod uncomment this line
  #unlink "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename";

  #unlink "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp";
  #}
}

sub encrypt_file {
  my ($filename) = @_;

  my $fileyear = substr( $filename, -14, 4 );

  #my $gpg = new GnuPG();
  my $plaintextfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename";
  my $encryptedfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp";

  if ( -e $encryptedfile ) {
    return;
  }

  print "aaaa $plaintextfile\n";
  print "bbbb $encryptedfile\n";

  my $line =
    `/usr/share/import/bin/gpg --homedir ~/batchfiles/globalctf/gnupg --encrypt --batch -v -q -r "Global Payments NA DXOP 2010 Production (DXOP NA 2010 Production)" -o $encryptedfile $plaintextfile`;

  #$gpg->encrypt(plaintext=>"$plaintextfile",
  #              output=>"$encryptedfile",
  #              recipient=>"Global Payments DXOP Production",
  #             );

  #  #$gpg->encrypt(plaintext=>"$plaintextfile",
  #  #              output=>"$encryptedfile",
  #  #              armor=>1,
  #  #              recipient=>"GLOBAL"
  #  #             );

  #unlink("$plaintextfile");

}

sub decrypt_file {
  my ( $filename, $passphrase ) = @_;

  my $fileyear      = substr( $filename, -14, 4 );
  my $encryptedfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp";
  my $plaintextfile = "/home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.out";

  #print "aaaa /home/p/pay1/batchfiles/globalctf/logs/$fileyear/$filename.pgp\n";
  #print "bbbb /home/p/pay1/batchfiles/global/logs/$fileyear/$filename.out\n";

  my $line = `/usr/share/import/bin/gpg --decrypt --batch -q -o $plaintextfile $encryptedfile`;

  #my $gpg = new GnuPG(trace => "true");
  #$gpg->decrypt( ciphertext => "$encryptedfile",
  #               output => "$plaintextfile",
  #               );
  #passphrase => "",

  #$gpg->decrypt( ciphertext => "$encryptedfile",
  #               output => "$plaintextfile",
  #               passphrase => $passphrase );

}

#sub verify {
#  my ($filename,$passphrase) = @_;

#  my $encryptedfile = "/home/p/pay1/batchfiles/global/logs/$fileyear/$filename.pgp";
#  my $encryptedfile = "/home/p/pay1/batchfiles/global/logs/$fileyear/$filename.pgp";
#    $gpg->verify( signature => "file.txt.asc", file => "file.txt" );
#}

sub generate_key {
  my $gpg = new GnuPG();

  $gpg->gen_key(
    name    => "PlugnPay-Global",
    comment => "Global GnuPG key",
  );

  #$gpg->gen_key( name => "Global",      comment => "Global GnuPG key",
  #               passphrase => $secret,
  #             );

  $gpg->export_keys(
    keys    => "PlugnPay-Global",
    comment => "Global GnuPG key",
    armor   => 1,
    output  => "/home/p/pay1/batchfiles/global/globalpgpkey.pub",
  );
}

sub import_key {
  my $gpg = new GnuPG();

  $gpg->import_keys( keys => "/home/p/pay1/batchfiles/global/globalpgpkey.sec", );
}

