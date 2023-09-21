#!/usr/local/bin/perl

$| = 1;

use lib '/home/p/pay1/perl_lib';
use Net::FTP;
use miscutils;
use IO::Socket;
use Socket;
use rsautils;
use smpsutils;
use Crypt::CBC;
use Crypt::DES;



my ($d1,$trans_date) = &miscutils::genorderid();


# get list of all pending ksn's
my $dbh = &miscutils::dbhconnect("pnpmisc");

my $sth = $dbh->prepare(qq{
        select ksn
        from dukpt
        where trans_date='$trans_date'
        and status='pending'
        }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%fdms::datainfo);
$sth->execute or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%fdms::datainfo);
$sth->bind_columns(undef,\($chkksn));

while ($sth->fetch) {
  print "$chkksn\n";
}
$sth->finish;

$dbh->disconnect;

print "\n";



print "ksn: ";
$ksn = <stdin>;
chop $ksn;

while ($ksn ne "") {

$bdk = "0123456789ABCDEFFEDCBA9876543210";	# ansi test
#$ksn = "FFFF9876543210E00001";			# ansi test
#$enccardnumber = "FC0D53B7EA1FDA9E";		# ansi test  data variant
#$enccardnumber = "1B9C1845EB993A7A";		# ansi test  pin variant

print "aaaa $ksn bbbb\n";
print "aaaa $bdk bbbb\n";

  my $errmsg = &injectipek("$ksn","$bdk");
  print "errmsg: $errmsg\n";

  print "ksn: ";
  $ksn = <stdin>;
  chop $ksn;
}

#my %result = &dukpt::magtekdecrypt("$line");
#foreach $key (sort keys %result) {
#  print "$key  $result{$key}\n";
#}

#my $decdata = &dukpt::dukptdecrypt("$ksn","$enccardnumber");

#print "decdata: $decdata\n\n\n\n";

exit;






sub injectipek {
  my ($ksn,$bdk) = @_;

  if ($ksn !~ /^[0-9a-fA-F]{20}$/) {
    return "error, bad ksn";
  }

  my $ksnpadded = substr("F" x 20 . $ksn,-20,20);
  $ksnpadded = pack "H*", $ksnpadded;
  $ksnpadded = $ksnpadded & pack "H*", "ffffffffffffffe00000";	# set rightmost 21 bits to 0
  my $ksnpad = unpack "H*", $ksnpadded;


  my $dbh = &miscutils::dbhconnect("pnpmisc");

  #my $bdk = $bdk1 ^ $bdk2;
  #$bdk = unpack 'H*', $bdk;

  if (length($bdk) != 32) {
    return "error, bad bdk $bdk";
  }

  # create ipek from bdk and ksn
  my $ksnpadded = substr("F" x 20 . $ksn,-20,20);
  $ksnpadded = pack "H*", $ksnpadded;
  $ksnpadded = $ksnpadded & pack "H*", "ffffffffffffffe00000";    # set rightmost 21 bits to 0

  my $left8ksn = substr($ksnpadded,0,8);
  my $right8ksn = substr($ksnpadded,8,16);

  my $bdkpacked = pack "H*", $bdk;
  my $ipekleft = &dukpt::tdesencrypt($left8ksn,$bdkpacked); # double DES

  my $xor = pack "H*", "c0c0c0c000000000c0c0c0c000000000";
  my $bdkxor = $bdkpacked ^ $xor;

  my $ipekright = &dukpt::tdesencrypt($left8ksn,$bdkxor);   # double DES

  my $ipek = $ipekleft . $ipekright;

  $ipek = unpack "H*", $ipek;

  my ($encipek) = &rsautils::rsa_encrypt_card($ipek,'/home/p/pay1/pwfiles/keys/key','');

  my $sth2 = $dbh->prepare(qq{
        update dukpt set encipek=?,status='done'
        where ksn='$ksnpad'
        }) or &miscutils::errmaildie(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth2->execute("$encipek")
             or &miscutils::errmaildie(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  $sth2->finish;

  $dbh->disconnect;

}





# sub tdesencrypt {
#   my ($data, $key) = @_;

#   my $keyleft = substr($key,0,8);
#   my $keymiddle = substr($key,8,8);
#   my $keyright = substr($key,16,8);

#   if ($keymiddle eq "") {
#     $keymiddle = $keyleft;
#     $keyright = $keyleft;
#     #single des
#   }
#   elsif ($keyright eq "") {
#     $keyright = $keyleft;
#     #double des
#   }
#   else {
#     #triple des
#   }

#   my $cipher1 = new Crypt::DES $keyleft;
#   my $cipher2 = new Crypt::DES $keymiddle;
#   my $cipher3 = new Crypt::DES $keyright;
#   $data = $cipher1->encrypt($data);  # can only be 8 bytes
#   $data = $cipher2->decrypt($data);  # can only be 8 bytes
#   $data = $cipher3->encrypt($data);  # can only be 8 bytes

#   return $data;
# }


# sub tdesdecrypt {
#   my ($data, $key) = @_;

#   my $keyleft = substr($key,0,8);
#   my $keymiddle = substr($key,8,8);
#   my $keyright = substr($key,16,8);

#   if ($keymiddle eq "") {
#     $keymiddle = $keyleft;
#     $keyright = $keyleft;
#     #single des
#   }
#   elsif ($keyright eq "") {
#     $keyright = $keyleft;
#     #double des
#   }
#   else {
#     #triple des
#   }

#   my $cipher1 = new Crypt::DES $keyleft;
#   my $cipher2 = new Crypt::DES $keymiddle;
#   my $cipher3 = new Crypt::DES $keyright;

#   my $result = "";
#   my $cipher = pack "H*", "0000000000000000";
#   for (my $idx=0; $idx<length($data); $idx=$idx+8) {
#     my $encdata = substr($data,$idx,8);

#     my $decdata = $cipher1->decrypt($encdata);  # can only be 8 bytes
#     $decdata = $cipher2->encrypt($decdata);  # can only be 8 bytes
#     $decdata = $cipher3->decrypt($decdata);  # can only be 8 bytes

#     $decdata = $decdata ^ $cipher;

#     $cipher = $encdata;

#     $result = $result . $decdata;

#   }


#   return $result;
# }