#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};

#use Net::FTP;
use miscutils;
use procutils;
use Net::SFTP::Foreign;

( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
$julian = $julian + 1;
$julian = substr( "000" . $julian, -3, 3 );

( $d1, $today ) = &miscutils::genorderid();

my $printstr = "\ntoday: $today\n";
&procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

$ttime = &miscutils::strtotime($today);
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $ttime - ( 3600 * 24 * 6 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my $printstr = "yesterday: $yesterday\n";
&procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( time() );
$todaylocal = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

## To change password: https://filetransfer.jncb.com/manageaccount
$ftpun = 'ecommuser';

#$ftppw = 'jfOxuxurs$65';  ##20211019
#$ftppw = 'jfOWe5rs$65';  ##20201031
#$ftppw = 'tr34#r%JI2o';
#$ftppw = 'iK3659K##$io';
#$ftppw = "jfO659K##We";  ##
#$ftppw = 'jfaxuS48rs$65';   ##  20220115
#$ftppw = 'nhg3rRg$opof5';   ##  20210426
#$ftppw = '&$jf8h8935K#We';   ## 20210130
#$ftppw = 'iK3678!K9K&&$';    ## 20210721
$ftppw = '&$jf8XXYX35K#We';

#$ftppw= "plumbB0b@YY";   ## 20200315
#$ftppw = 'k&&5K#5Akith!57'; # 20211019
#$ftppw = "GatewayFX6860@"; ## Entered 20200316  DCP
$host       = "208.163.53.154";    ### Until further notice  07/16/2012
$remote_dir = "/home";

print "UN:$ftpun, PWD:$ftppw:\n";

# clean out batchfiles
my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 180 ) );
my $deletedate = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my $dbquerystr = <<"dbEOM";
      delete from batchfilesncb
      where trans_date<?
dbEOM
my @dbvalues = ("$deletedate");
&procutils::dbdelete( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

#$ftp = Net::SFTP->new("$host",'user' => $ftpun, 'password' => $ftppw, 'Timeout' => 2400, 'Debug' => 1);
$ftp = Net::SFTP::Foreign->new( 'host' => "$host", 'user' => $ftpun, 'password' => $ftppw, 'port' => 22, 'timeout' => 30 );
$ftp->error and die "cannot connect: " . $ftp->error;

if ( $ftp eq "" ) {
  my $printstr = "Host $host username $username and key don't work<br>\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

  exit;
}

#$ftp = Net::SFTP::Foreign->new('host' => "$host",'user' => $ftpun, 'password' => $ftppw, 'port' => 22, 'timeout' => 30);
#$ftp = Net::SFTP::Foreign->new('host' => "$host",'user' => $ftpun, 'password' => $ftppw, 'port' => 22, 'timeout' => 30, more => '-v');
#$ftp->error and die "cannot connect: " . $ftp->error;
#if ($ftp eq "") {
#  print "Host $host is no good<br>\n";
#  print "failure";
#  exit;
#}

my $printstr = "logged in\n";
&procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

$mode = "A";

#$ftp->type("$mode");

#$yesterday = '20031121';

my $dbquerystr = <<"dbEOM";
        select batchdate,filenum
        from ncb
        where username='ncb'
dbEOM
my @dbvalues = ();
( $batchdate, $filenum ) = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

my $dbquerystr = <<"dbEOM";
        select distinct filename
        from batchfilesncb
        where trans_date>=?
        and status='pending'
dbEOM
my @dbvalues = ("$yesterday");
my @sthbatchvalarray = &procutils::dbread( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

for ( my $vali = 0 ; $vali < scalar(@sthbatchvalarray) ; $vali = $vali + 1 ) {
  ($filename) = @sthbatchvalarray[ $vali .. $vali + 0 ];

  if ( $todaylocal > $batchdate ) {
    $filenum = "01";
  } else {
    $filenum = $filenum + 1;
    $filenum = substr( "00" . $filenum, -2, 2 );
  }

  # xxxxxyyyy
  #$filenum = "01";

  $filename2 = "ECOM." . substr( $filename, 6, 2 ) . substr( $filename, 4, 2 ) . substr( $filename, 2, 2 ) . "$filenum.txt";
  $filename3 = "ECOMrep." . substr( $filename, 6, 2 ) . substr( $filename, 4, 2 ) . substr( $filename, 2, 2 ) . "$filenum.txt";

  my $printstr = "$filename    $filename2\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

  my $tmpfilename = $filename . "rep";
  my $fileyear = substr( $filename, 0, 4 ) . "/" . substr( $filename, 4, 2 ) . "/" . substr( $filename, 6, 2 );
  $month = substr( $filename, 4, 2 );
  $year  = substr( $filename, 2, 2 );
  if ( -e "/home/pay1/batchfiles/logs/ncb/$fileyear/$filename" ) {
    system("chmod go-rwx /home/pay1/batchfiles/logs/ncb/$fileyear/*");

    #my $res = $ftp->put("/home/pay1/batchfiles/logs/ncb/$fileyear/$filename", "/$filename2");
    #my $res = $ftp->put("/home/pay1/batchfiles/logs/ncb/$fileyear/$filename", "$remote_dir/$filename2");

    my $printstr = "put /home/pay1/batchfiles/logs/ncb/$fileyear/$filename $remote_dir/$filename2\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

    $ftp->put( "/home/pay1/batchfiles/logs/ncb/$fileyear/$filename", "$remote_dir/$filename2", 'copy_perm' => 0, 'copy_time' => 0 ) or die "put failed: " . $ftp->error;

    #my $tmpstr = Net::SFTP::Util::fx2txt($ftp->status);
    #print "aaaa $tmpstr\n";

    my $printstr = "status1: " . $ftp->status . "\n";
    if ( $ftp->error ) {
      $printstr .= "error: " . $ftp->error . "\n";
    }
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

    #$ftp->do_rename("$remote_dir/$filename.tmp","$remote_dir/$filename.txt");
    #$res = $ftp->put("/home/pay1/batchfiles/logs/ncb/$fileyear/$tmpfilename", "/$filename3");

    my $printstr = "put /home/pay1/batchfiles/logs/ncb/$fileyear/$tmpfilename $remote_dir/$filename3\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

    $ftp->put( "/home/pay1/batchfiles/logs/ncb/$fileyear/$tmpfilename", "$remote_dir/$filename3" );

    my $printstr = "status2: " . $ftp->status . "\n";
    if ( $ftp->error ) {
      $printstr .= "error: " . $ftp->error . "\n";
    }
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

    #$ftp->do_rename("$remote_dir/$tmpfilename.tmp","$remote_dir/$tmpfilename.txt");
  } else {
    my $printstr = "file /home/pay1/batchfiles/logs/ncb/$fileyear/$filename does not exist\n\n";
    &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );
  }

  my $dbquerystr = <<"dbEOM";
        update batchfilesncb
        set status='locked'
        where trans_date>=?
        and status='pending'
        and filename=?
dbEOM
  my @dbvalues = ( "$yesterday", "$filename" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  my $dbquerystr = <<"dbEOM";
          update ncb set batchdate=?,filenum=?
          where username='ncb'
dbEOM
  my @dbvalues = ( "$todaylocal", "$filenum" );
  &procutils::dbupdate( $username, $orderid, "pnpmisc", $dbquerystr, @dbvalues );

  open( MAIL, "| /usr/lib/sendmail -t" );
  print MAIL "To: ecomrecon\@jncb.com\n";
  print MAIL "From: settlement\@plugnpay.com\n";
  print MAIL "Subject: ncb settlement file  $filename2\n";
  print MAIL "\n";
  print MAIL "Files: $filename2 and $filename3\n";
  close(MAIL);

  $filefilter  = "$month$year" . "01.txt";
  $filefilter2 = "$month$year" . "02.txt";

  my $printstr = "filefilter: $filefilter\n";
  &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );

  my $ls = $ftp->ls($remote_dir);
  $file1flag = 0;
  $file2flag = 0;
  foreach $var (@$ls) {
    if ( ( $var->{"filename"} =~ /$filefilter/ ) || ( $var->{"filename"} =~ /$filefilter2/ ) ) {
      my $printstr = "bb " . $var->{"filename"} . "\n";
      &procutils::filewrite( "$username", "ncb", "/home/pay1/batchfiles/logs/ncb", "ftplog.txt", "append", "misc", $printstr );
    }
    if ( $var->{"filename"} eq "$filename2" ) {
      $file1flag = 1;
    }
    if ( $var->{"filename"} eq "$filename3" ) {
      $file2flag = 1;
    }

    #foreach $key (sort keys %$var){
    #  print "bb the value is $key =>" .  $var->{$key} . "\n";
    #}
  }

  if ( ( $file1flag == 1 ) && ( $file2flag == 1 ) ) {

    #system("cp /home/pay1/batchfiles/logs/ncb/$fileyear/$filename /home/pay1/batchfiles/logs/ncb/$fileyear/$filename.sav");
    #system("cp /home/pay1/batchfiles/logs/ncb/$fileyear/$tmpfilename /home/pay1/batchfiles/logs/ncb/$fileyear/$tmpfilename.sav");

    unlink "/home/pay1/batchfiles/logs/ncb/$fileyear/$filename";
    unlink "/home/pay1/batchfiles/logs/ncb/$fileyear/$tmpfilename";

    #rename "/home/pay1/batchfiles/logs/ncb/$fileyear/$filename", "/home/pay1/batchfiles/logs/ncb/$fileyear/$filename" . "sav";
    #rename "/home/pay1/batchfiles/logs/ncb/$fileyear/$tmpfilename", "/home/pay1/batchfiles/logs/ncb/$fileyear/$tmpfilename" . "sav";
  }

  #@list = $ftp->ls("$remote_dir/$filename2");
  #if (@list == 0) {
  #  print "bb no report files\n";
  #}
  #foreach $var (@list) {
  #  print "bb var: $var\n";
  #}

}

#$ftp->quit;

exit;

