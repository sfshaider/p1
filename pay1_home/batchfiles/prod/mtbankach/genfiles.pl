#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use rsautils;
use smpsutils;
use Time::Local;
use PlugNPay::Database;
use PlugNPay::Features;

#use strict;

$devprod     = "prod";
$devprodlogs = "logs";

my $root_file_path = "/home/p/pay1";
my $eol            = "\r\n";

$main::immediate_destination_name        = "M&T BANK BUFFALO NY";        ## Will be left justified and padded to 23 characters
$main::immediate_destination_routenumber = "022000046";                  ## Will be right justified and padded to 10 characters
$main::immediate_originating_name        = "Plug & Pay Technologies";    ## Will be right justified and padded to 10 characters

if ( ( -e "$root_file_path/batchfiles/logs/stopgenfiles.txt" ) || ( -e "$root_file_path/batchfiles/logs/mtbankach/stopgenfiles.txt" ) ) {
  exit;
}

my $cnt = `ps -ef | grep -v grep | grep -v vim | grep perl | grep -c 'mtbankach/genfiles.pl'`;
if ( $cnt > 1 ) {
  print "genfiles.pl already running, exiting...\n";
  exit;
}

my $mytime  = time();
my $machine = `uname -n`;

chop $machine;
open( outfile, ">$root_file_path/batchfiles/$devprodlogs/mtbankach/pid.txt" );
my $pidline = "$mytime $$ $machine";
print outfile "$pidline\n";
close(outfile);

&miscutils::mysleep(2.0);

open( infile, "$root_file_path/batchfiles/$devprodlogs/mtbankach/pid.txt" );
my $chkline = <infile>;
chop $chkline;
close(infile);

if ( $pidline ne $chkline ) {
  print "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print "$pidline\n";
  print "$chkline\n";

  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "Cc: dprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: mtbankach - dup genfiles\n";
  print MAILERR "\n";
  print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
  print MAILERR "$pidline\n";
  print MAILERR "$chkline\n";
  close MAILERR;

  exit;
}

my ($dummy);
( $dummy, $main::sixmonthsago, $main::sixmonthsagotime ) = &miscutils::gendatetime( -( 3600 * 24 * 30 * 6 ) );
( $dummy, $main::onemonthsago, $main::onemonthsagotime ) = &miscutils::gendatetime( -( 3600 * 24 * 30 * 1 ) );
( $dummy, $main::twomonthsago, $main::twomonthsagotime ) = &miscutils::gendatetime( -( 3600 * 24 * 30 * 2 ) );
( $dummy, $main::tomorrow,     $dummy )                  = &miscutils::gendatetime( ( 3600 * 24 ) );

( $batchorderid, $today, $todaytime ) = &miscutils::genorderid();
$batchid  = $batchorderid;
$filename = $todaytime;

$fileyear = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 ) . "/" . substr( $today, 6, 2 );
$filemonth = substr( $today, 0, 4 ) . "/" . substr( $today, 4, 2 );
$fileyearonly = substr( $today, 0, 4 );

if ( !-e "$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyearonly" ) {
  print "creating $fileyearonly\n";
  system("mkdir $root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyearonly");
  chmod( 0700, "$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyearonly" );
}
if ( !-e "$root_file_path/batchfiles/$devprodlogs/mtbankach/$filemonth" ) {
  print "creating $filemonth\n";
  system("mkdir $root_file_path/batchfiles/$devprodlogs/mtbankach/$filemonth");
  chmod( 0700, "$root_file_path/batchfiles/$devprodlogs/mtbankach/$filemonth" );
}
if ( !-e "$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear" ) {
  print "creating $fileyear\n";
  system("mkdir $root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear");
  chmod( 0700, "$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear" );
}
if ( !-e "$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear" ) {
  open( MAILERR, "| /usr/lib/sendmail -t" );
  print MAILERR "To: cprice\@plugnpay.com\n";
  print MAILERR "From: dcprice\@plugnpay.com\n";
  print MAILERR "Subject: mtbankach - FAILURE\n";
  print MAILERR "\n";
  print MAILERR "Couldn't create directory mtbankach/$fileyear.\n\n";
  close MAILERR;
  exit;
}

if ( ( -e "$root_file_path/batchfiles/stopgenfiles.txt" ) || ( -e "$root_file_path/batchfiles/$devprodlogs/mtbankach/stopgenfiles.txt" ) ) {
  unlink "$root_file_path/batchfiles/$devprodlogs/mtbankach/batchfile.txt";
  exit;
}

$batch_flag   = 1;
$file_flag    = 1;
$errorflag    = 0;
$usersalesamt = 0;

$main::dbase = new PlugNPay::Database();

## Create Array of customers that are live and use MTBank ACH
my @requestedData  = ('username');
my @params         = ( 'chkprocessor', 'mtbankach', 'status', 'live' );
my @results        = $main::dbase->databaseQuery( 'pnpmisc', 'customers', \@requestedData, \@params );
my @username_array = ();
my %username_hash  = ();
my $username_str   = "";

foreach my $Data (@results) {
  push( @username_array, $$Data{'username'} );
  $username_str .= "$$Data{'username'}|";
}
chop $username_str;

## USe above list and filter it to get list that have ach enabled
my @requestedData = ('ALL');
my @params        = ( 'username', $username_str, 'status', 'enabled' );
my @results       = $main::dbase->databaseQuery( 'pnpmisc', 'mtbankach', \@requestedData, \@params );

$username_str = "";
foreach my $Data (@results) {
  print "UN:$$Data{'username'}:  MC:$$Data{'merchantnum'}\n";

  #push (@userarray, $$Data{'username'});
  $username_str .= "$$Data{'username'}|";
  $username_hash{ $$Data{'username'} }     = 1;
  $merchantData_hash{ $$Data{'username'} } = $Data;
}
chop $username_str;

if (0) {
###  Not sure what this query does ## Looks to be master route/account number for merchants Bank Account?
  my @requestedData = ( 'enccardnumber', 'length' );
  my @params        = ( 'username',      'pnpcitymstr' );
  my @results = $main::dbase->databaseQuery( 'pnpmisc', 'mtbankach', \@requestedData, \@params );
  my $Data = $results[0];
  $enccardnumber = $$Data{'enccardnumber'};
  $length        = $$Data{'length'};

  $cardnumber = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
  ( $pnproutenum, $pnpacctnum ) = split( / /, $cardnumber );

}

### TEST
$pnproutenum = "999999992";
$pnpacctnum  = "123456789";

if (0) {    ### A General Query just to see status of trans to make sure postauth worked correct
## For TEST
  my @requestedData = ('ALL');
  my @params        = ( 'trans_date', ">=20141001", 'trans_date', "<=$today", 'orderid', '2014100321132516330', 'username', 'pnpdemo2', 'accttype', 'checking|savings' );
  my @results       = $main::dbase->databaseQuery( 'pnpdata', 'operation_log', \@requestedData, \@params );

  foreach my $myData (@results) {
    foreach my $key ( sort keys %$myData ) {
      print "K:$key:$$myData{$key}, ";
    }
    print "\n\n";
  }
}

#my @requestedData = ('t.username','count(t.username)','min(o.trans_date)');
#my @params = ('t.trans_date',">=$onemonthsago",'t.trans_date',"<=$today",'t.operation','postauth|return','t.finalstatus','pending','t.accttype','checking|savings','o.orderid','t.orderid','o.username','t.username',
#              'o.processor','mtbankach','o.lastoptime',">=$onemonthsagotime",'o.lastopstatus','pending');
#my @groupby = ('t.username');
#my @results = $main::dbase->databaseQuery('pnpmisc','mtbankach',\@requestedData,\@params);
#my $Data = $results[0];

### Drew Says

my @requestedData = ( 'username', 'count(username)', 'min(trans_date)' );
my @params = (
  'trans_date',   ">=$main::onemonthsago", 'trans_date', "<=$today",  'username', $username_str,      'lastop',     'postauth|return',
  'lastopstatus', 'pending',               'processor',  'mtbankach', 'accttype', 'checking|savings', 'lastoptime', ">=$main::onemonthsagotime"
);
my @orderby = ();
my @groupby = ('username');

my @results = $main::dbase->databaseQuery( 'pnpdata', 'operation_log', \@requestedData, \@params, \@orderby, \@groupby );

foreach my $Data (@results) {
  if ( !exists $username_hash{ $$Data{'username'} } ) {
    next;
  } else {
    push( @userarray, $$Data{'username'} );
    $usercountarray{ $$Data{'username'} }  = $$Data{'count(username)'};
    $starttdatearray{ $$Data{'username'} } = $$Data{'min(trans_date)'};
  }
}
foreach $username (@userarray) {
  print "UN:$username\n";

  my $merchantData = $merchantData_hash{$username};
  if ( ( -e "$root_file_path/batchfiles/stopgenfiles.txt" ) || ( -e "$root_file_path/batchfiles/$devprodlogs/mtbankach/stopgenfiles.txt" ) ) {
    unlink "$root_file_path/batchfiles/$devprodlogs/mtbankach/batchfile.txt";
    last;
  }

  umask 0033;
  open( CHECKIN, ">$root_file_path/batchfiles/$devprodlogs/mtbankach/genfiles.txt" );
  print CHECKIN "$username\n";
  close(CHECKIN);

  umask 0033;
  open( BATCHFILE, ">$root_file_path/batchfiles/$devprodlogs/mtbankach/batchfile.txt" );
  print BATCHFILE "$username\n";
  close(BATCHFILe);

  $starttransdate = $starttdatearray{$username};
  if ( $starttransdate < $today - 10000 ) {
    $starttransdate = $today - 10000;
  }

  %checkdup = ();

  my $accountFeatures = new PlugNPay::Features( $username, 'general' );

  # sweeptime
  $sweeptime = $accountFeatures->get('sweeptime');    # sweeptime=1:EST:19   dstflag:timezone:time

  print "sweeptime: $sweeptime\n";

  my $esttime = "";
  if ( $sweeptime ne "" ) {
    ( $dstflag, $timezone, $settlehour ) = split( /:/, $sweeptime );
    $esttime = &zoneadjust( $todaytime, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
    my $newhour = substr( $esttime, 8, 2 );
    if ( $newhour < $settlehour ) {
      umask 0077;
      open( LOGFILE, ">>$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear/$username$time$$.txt" );
      print LOGFILE "aaaa  newhour: $newhour  settlehour: $settlehour\n";
      close(LOGFILE);
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 ) );
      $yesterday = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $month + 1, $day, $hour, $min, $sec );
      $yesterday = &zoneadjust( $yesterday, 'GMT', $timezone, $dstflag );    # give it gmt, it returns local time
      $settletime = sprintf( "%08d%02d%04d", substr( $yesterday, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    } else {
      umask 0077;
      open( LOGFILE, ">>$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear/$username$time4$$.txt" );
      print LOGFILE "bbbb  newhour: $newhour  settlehour: $settlehour\n";
      close(LOGFILE);
      $settletime = sprintf( "%08d%02d%04d", substr( $esttime, 0, 8 ), $settlehour, "0000" );
      $sweeptime = &zoneadjust( $settletime, $timezone, 'GMT', $dstflag );
    }
  }

  print "gmt today: $todaytime\n";
  print "est today: $esttime\n";
  print "est yesterday: $yesterday\n";
  print "settletime: $settletime\n";
  print "sweeptime: $sweeptime\n";

  umask 0077;
  open( LOGFILE, ">>$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear/$username$time$$.txt" );
  print "$username\n";
  print LOGFILE "$username  group: $batchgroup  sweeptime: $sweeptime  settletime: $settletime\n";

  ##  get accounts routing/accountnum
  #($merchroutenum,$merchacctnum) = split(/ /,$$merchantData{'merchantnum'});

  #$rlen = length($merchroutenum);
  #$alen = length($merchacctnum);

  #if (($rlen != 9) || ($alen < 2)) {
  #  print "$username - Missing or invalid routing or account number. RN:$merchroutenum, AN:$merchacctnum, RL:$rlen, AL:$alen\n";
  #  print LOGFILE "$username - Missing or invalid routing or account number. RN:$merchroutenum, AN:$merchacctnum, RL:$rlen, AL:$alen\n";
  #  next;
  #}
  #print "Routenum Length:$rlen Accountnum Length:$alen\n";
  print "twomonthsagotime: $main::twomonthsagotime\n";
  print "username: $username\n";
  print "starttransdate: $starttransdate\n";

  ## Grab list of orderIDs to settle
  my @requestedData = ( 'orderid', 'lastop', 'auth_code' );
  my @params = (
    'trans_date',   ">=$starttransdate", 'username',   "$username", 'lastoptime', ">=$main::twomonthsagotime", 'lastop', 'postauth|return',
    'lastopstatus', 'pending',           'voidstatus', 'NULL',      'accttype',   'checking|savings'
  );
  my @groupby = ('username');

  my @results = $main::dbase->databaseQuery( 'pnpdata', 'operation_log', \@requestedData, \@params );

  @orderidarray = ();
  foreach my $Data (@results) {
    my $seccode = substr( $$Data{'auth_code'}, 6, 3 );
    $orderidarray{"$seccode $$Data{'lastop'} $$Data{'orderid'}"} = 1;
    print "$$Data{'lastop'} $$Data{'orderid'}\n";
  }

  $mintrans_date = $today;

  foreach $key ( sort keys %orderidarray ) {
    my ( $seccode, $operation, $orderid ) = split( / /, $key );
    print "bb $seccode $operation $orderid\n";

    ### Foreach orderID now grab tran data.  Can this be combined with first query above?
    my @requestedData = ( 'trans_time', 'enccardnumber', 'length', 'amount', 'auth_code', 'finalstatus', 'card_name', 'accttype' );
    my @params =
      ( 'trans_date', ">=$main::twomonthsago", 'orderid', "$orderid", 'username', "$username", 'operation', "$operation", 'finalstatus', 'pending', 'duplicate', 'NULL', 'accttype', 'checking|savings' );
    my @results = $main::dbase->databaseQuery( 'pnpdata', 'trans_log', \@requestedData, \@params );
    my $tranData = $results[0];

    if ( ( -e "$root_file_path/batchfiles/stopgenfiles.txt" ) || ( -e "$root_file_path/batchfiles/$devprodlogs/mtbankach/stopgenfiles.txt" ) ) {
      last;
    }

    if ( $operation eq "void" ) {
      $orderidold = $orderid;
      next;
    }
    if ( ( $orderid eq $orderidold ) || ( $$tranData{'finalstatus'} ne "pending" ) ) {
      $orderidold = $orderid;
      next;
    }

    if ( ( $sweeptime ne "" ) && ( $$tranData{'trans_time'} > $sweeptime ) ) {
      $orderidold = $orderid;
      next;    # transaction is newer than sweeptime
    }

    if ( ( $$merchantData{'switchtime'} > $main::sixmonthsagotime ) && ( $$tranData{'trans_time'} < $$merchantData{'switchtime'} ) ) {
      $orderidold = $orderid;
      next;    # transaction is older then switchtime
    }

    if ( $checkdup{"$operation $orderid"} == 1 ) {
      next;
    }
    $checkdup{"$operation $orderid"} = 1;

    $$tranData{'enccardnumber'} = &smpsutils::getcardnumber( $username, $orderid, "mtbankach", $$tranData{'enccardnumber'} );

    $cardnumber = &rsautils::rsa_decrypt_file( $$tranData{'enccardnumber'}, $$tranData{'length'}, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    ( $routenum, $acctnum ) = split( / /, $cardnumber );

    my %data_to_validate = (
      'refnumber', '',        'operation',  $$tranData{'operation'}, 'finalstatus', $$tranData{'finalstatus'}, 'acctnum', $acctnum,
      'routenum',  $routenum, 'cardnumber', $cardnumber,             'amount',      $tranData{'amount'}
    );

    my $errflag = &errorchecking( \%data_to_validate );
    if ( $errflag ne "0" ) {
      print "cardnumber failed error checking $errflag\n";
      next;
    }

    if ( ( $batch_flag == 0 ) && ( $seccodeold ne "" ) && ( $seccode ne $seccodeold ) ) {
      &batchtrailer( $$merchantData{'company'} );

      #&batchheader($company,$companyid,"$seccodeold");
      #&batchtrailer();
      $usersalesamt = 0;
      $batch_flag   = 1;
      &filetrailer( $$merchantData{'company'} );
      $file_flag = 1;
    }

    if ( $file_flag == 1 ) {
      &pidcheck();
      if ( $seccode eq "PPD" ) {
        $companyid = $$merchantData{'companyid'};
      } else {
        $companyid = $$merchantData{'companyidccd'};
      }
      &fileheader( $$merchantData{'company'} );

      umask 0077;
      open( LOGFILE, ">>$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear/t$filename.txt" );
      print LOGFILE "\n$username\n";
      close(LOGFILE);
    }

    if ( ( $operationold ne "" ) && ( $operation ne $operationold ) ) {
      if ( $batch_flag == 0 ) {
        &batchtrailer( $$merchantData{'company'} );
      }
      $batch_flag = 1;
    }

    if ( $batch_flag == 1 ) {
      &batchheader( $$merchantData{'company'}, $companyid, $seccode );
      $batch_flag     = 0;
      $batchdetreccnt = 0;
      $batchfees      = 0;
      $usersalescnt   = 0;
      $userretamt     = 0;
      $userretcnt     = 0;
    }

    umask 0077;
    open( LOGFILE, ">>$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear/t$filename.txt" );
    print LOGFILE "$orderid $operation\n";
    close(LOGFILE);

    $transamt = substr( $$tranData{'amount'}, 4 );
    $transamt = sprintf( "%.2f", $transamt + .0001 );
    print "transamt: $transamt\n";

    if ( $operation =~ /postauth|return/ ) {
      my %updateData = ( 'finalstatus', 'locked', 'result', $batchid );
      my @params = ( 'orderid', $orderid, 'username', $username, 'trans_date', ">=$main::twomonthsago", 'finalstatus', 'pending', 'accttype', 'checking|savings' );
      my @results = $main::dbase->databaseUpdate( 'pnpdata', 'trans_log', \%updateData, \@params );

      my $operationstatus = $operation . "status";
      my $operationtime   = $operation . "time";

      my %updateData = ( "$operationstatus", 'locked', 'lastopstatus', 'locked', 'batchfile', "$batchid" );
      my @params = ( 'orderid', $orderid, 'username', $username, 'trans_date', ">=$main::sixmonthsago", 'accttype', 'checking|savings' );
      my @results = $main::dbase->databaseUpdate( 'pnpdata', 'operation_log', \%updateData, \@params );

      if ( $operation eq "postauth" ) {
        $usersalesamt = $usersalesamt + $transamt;
      } else {
        $usersalesamt = $usersalesamt - $transamt;
      }
      $usersalescnt = $usersalescnt + 1;

      if ( ( $operation eq "postauth" ) && ( $$tranData{'accttype'} eq "checking" ) ) {
        $tcode = "27";
      } elsif ( ( $operation eq "postauth" ) && ( $$tranData{'accttype'} eq "savings" ) ) {
        $tcode = "37";
      } elsif ( ( $operation eq "return" ) && ( $$tranData{'accttype'} eq "checking" ) ) {
        $tcode = "22";
      } elsif ( ( $operation eq "return" ) && ( $$tranData{'accttype'} eq "savings" ) ) {
        $tcode = "32";
      }

      &batchdetail( $routenum, $acctnum, $orderid, $$tranData{'card_name'}, $transamt, $tcode, $$tranData{'auth_code'}, $operation );
    } elsif ( (0) && ( $operation eq "return" ) ) {
      $amt                          = $transamt + $feerate;
      $userretamt                   = $userretamt + $transamt;
      $userretcnt                   = $userretcnt + 1;
      $retamt                       = $retamt + $amt;
      $batchorderid                 = &miscutils::incorderid($batchorderid);
      $merchroute{$batchorderid}    = $merchroutenum;
      $merchorderid{$batchorderid}  = $orderid;
      $merchacct{$batchorderid}     = $merchacctnum;
      $merchcompany{$batchorderid}  = $company;
      $merchdeposit{$batchorderid}  = $amt;
      $merchtcode{$batchorderid}    = $tcode;
      $merchusername{$batchorderid} = $username;
      $merchfeerate{$batchorderid}  = $feerate;
      $merchfilename{$batchorderid} = $filename;
      $merchtransamt{$batchorderid} = $transamt;
    }

    $temp = substr( $recseqnum, 3, 4 );
    if ( $temp >= 9998 ) {
      &batchtrailer( $$merchantData{'company'} );

      #&batchheader($company,$companyid,"$seccode");
      #&batchtrailer();
      $usersalesamt = 0;
      $batch_flag   = 1;
      &filetrailer( $$merchantData{'company'} );
      $file_flag = 1;
    }

    $usernameold  = $username;
    $operationold = $operation;
    $seccodeold   = $seccode;
  }

  if ( $batch_flag == 0 ) {
    &batchtrailer( $$merchantData{'company'} );

    #&batchheader($company,$companyid,"$seccode");
    #&batchtrailer();
    $usersalesamt = 0;
    $batch_flag   = 1;
  }
}

$a = keys(%merchroute);
print "a: $a\n";
if ( keys(%merchroute) > 0 ) {
  &batchheader("Plug & Pay Technologies, Inc.");
}

if ( $file_flag == 0 ) {
  foreach $key ( sort keys %merchroute ) {
    my %updateData = ( 'finalstatus', 'locked', 'result', $batchid );
    my @params = ( 'orderid', $merchorderid{$key}, 'username', $merchusername{$key}, 'trans_date', ">=$main::twomonthsago", 'finalstatus', 'pending', 'accttype', 'checking|savings' );
    my @results = $main::dbase->databaseUpdate( 'pnpdata', 'trans_log', \%updateData, \@params );

    my $operationstatus = $operation . "status";
    my $operationtime   = $operation . "time";

    my %updateData = ( "$operationstatus", 'locked', 'lastopstatus', 'locked', 'batchfile', "$batchid" );
    my @params = ( 'orderid', $merchorderid{$key}, 'username', $merchusername{$key}, 'trans_date', ">=$main::sixmonthsago", 'accttype', 'checking|savings' );
    ## Uncomment after testing
    my @results = $main::dbase->databaseUpdate( 'pnpdata', 'operation_log', \%updateData, \@params );

    #if ($merchtransamt{$key} > 0) {  ### found no use for this table
    #  $amt = sprintf("%.2f",(0 - $merchtransamt{$key})-.0001);
    #  my %insertData = ('username',$merchusername{$key},'filename',$merchfilename{$key},'batchid',$batchid,'orderid',$merchorderid{$key},'fileid',$fileid,'batchnum',$batchnum,
    #  my @results = $main::dbase->databaseInsert('pnpmisc','mtbankdetails',\%insertData);
    #}

    $user              = $merchusername{$key};
    $sumdeposit{$user} = $sumdeposit{$user} + $merchdeposit{$key};
    $sumroute{$user}   = $merchroute{$key};
    $sumacct{$user}    = $merchacct{$key};
    $sumcompany{$user} = $merchcompany{$key};

    ####  Commented out in citynat
    #&detail($merchroute{$key},$merchacct{$key},$merchorderid{$key},$merchcompany{$key},${merchdeposit$key},$merchtcode{$key});
  }

  foreach $key ( sort keys %sumdeposit ) {
    $batchorderid = &miscutils::incorderid($batchorderid);
    $amt = sprintf( "%.2f", $sumdeposit{$key} + .0001 );
    &detail( $sumroute{$key}, $sumacct{$key}, $batchorderid, $sumcompany{$key}, $amt, "27" );

    ###mtbankdetails does not exist.  Is it needed
    #my %updateData = ('detailnum',$recseqnum);
    #my @params = ('trans_date',$today,'batchid',$batchid,'username',$key);
    #my @results = $main::dbase->databaseUpdate('pnpmisc','mtbankdetails',\%updateData,\@params);
  }

  %sumdeposit    = ();
  %sumroute      = ();
  %sumacct       = ();
  %sumcompany    = ();
  %merchroute    = ();
  %merchacct     = ();
  %merchcompany  = ();
  %merchdeposit  = ();
  %merchtcode    = ();
  %merchusername = ();
  %merchfeerate  = ();
  %merchfilename = ();
  %merchorderid  = ();
  %merchtransamt = ();

  &filetrailer( $$merchantData{'company'} );
  $file_flag = 1;
}

unlink "$root_file_path/batchfiles/$devprodlogs/mtbankach/batchfile.txt";

umask 0033;
open( checkin, ">$root_file_path/batchfiles/$devprodlogs/mtbankach/genfiles.txt" );
close(checkin);

# xxxxaaaa
system("$root_file_path/batchfiles/$devprod/mtbankach/putfiles.pl >> $root_file_path/batchfiles/$devprodlogs/mtbankach/ftplog.txt 2>\&1");

exit;

sub batchheader {
  my ( $companyinfo, $companyid, $seccode ) = @_;

  $recseqnum++;
  $batchsalescnt  = 0;
  $batchsalesamt  = 0;
  $batchretcnt    = 0;
  $batchretamt    = 0;
  $batchtotamt    = 0;
  $batchtotcnt    = 0;
  $batchreccnt    = 1;
  $batchdetreccnt = 0;
  $batch_flag     = 0;
  $transseqnum    = 0;
  $routenumhash   = 0;
  $usersalescnt   = 0;
  $userretamt     = 0;
  $userretcnt     = 0;

  $batchcount++;
  $batchnum++;

  $batchid = &miscutils::incorderid($batchid);

  $batchreccnt = 1;
  $filereccnt++;

  @bh           = ();
  $bh[0]        = '5';                                        # record type code (1n)
  $bh[1]        = '200';                                      # service class code (3n)
  $companyname  = substr( $companyinfo . " " x 16, 0, 16 );
  $companydescr = substr( $companyinfo, 16, 10 );
  if ( $companydescr eq "" ) {
    $companydescr = "PAYMT     ";
  } else {
    $companydescr = substr( $companydescr . " PAYMT    ", 0, 10 );
  }
  $bh[2] = "$companyname";                                    # company name (16a)

  # xxxx
  $bh[3] = 'WAA009' . " " x 14;                               # company discretionary data (20a)
  $companyid = substr( $companyid . " " x 10, 0, 10 );
  $bh[4] = $companyid;                                        # company identification (10a)
  $bh[5] = $seccode;                                          # standard entry class code (3a)
  $bh[6] = $companydescr;                                     # company entry description (10a)
  $tdate = substr( $main::tomorrow, 2, 6 );
  $bh[7] = $tdate;                                            # company descriptive date (6a)

  # xxxx two days later than actual date
  $bh[8]  = $tdate;                                                      # effective entry date (6n)
  $bh[9]  = "   ";                                                       # settlement date (julian) - leave blank (3n)
  $bh[10] = '1';                                                         # originator status code (1a)
  $bh[11] = substr( $main::immediate_destination_routenumber, 0, 8 );    # originating dfi identification (8a)
  $batchnum = substr( "0" x 7 . $batchnum, -7, 7 );

  # xxxx sames as  8 record, field 11
  $bh[12] = $batchnum;                                                   # batch number (7n)

  foreach $var (@bh) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "$eol";
  print outfile2 "$eol";

}

sub detail {
  my ( $routenum, $acctnum, $orderid, $card_name, $transamt, $tcode ) = @_;

  $batchdetreccnt++;
  $filedetreccnt++;
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;

  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );

  if ( $tcode =~ /^(27|37)$/ ) {
    $batchsalesamt = $batchsalesamt + $transamt;
    $batchsalescnt = $batchsalescnt + 1;
    $filesalesamt  = $filesalesamt + $transamt;
    $filesalescnt  = $filesalescnt + 1;
  } else {
    $batchretamt = $batchretamt + $transamt;
    $batchretcnt = $batchretcnt + 1;
    $fileretamt  = $fileretamt + $transamt;
    $fileretcnt  = $fileretcnt + 1;
  }
  $batchtotamt = $batchtotamt + $transamt;
  $batchtotcnt = $batchtotcnt + 1;
  $filetotamt  = $filetotamt + $transamt;

  my @requestedData = ('refnumber');
  my @params        = ( 'username', 'pnpmtbankmst' );
  my @results       = $main::dbaseQuery->databaseQuery( 'pnpmisc', 'mtbankach', \@requestedData, \@params );
  my $Data          = $results[0];
  $refnumber = $$Data{'refnumber'};

  $refnumber = $refnumber + 1;
  if ( $refnumber >= 9999998 ) {
    $refnumber = 1;
  }

  $refnumber = substr( "0" x 15 . $refnumber, -15, 15 );

  my %updateData = ( 'refnumber', $refnumber );
  my @params     = ( 'username',  'pnpmtbankmst' );
  my @results = $main::dbase->databaseUpdate( 'pnpmisc', 'mtbankach', \%updateData, \@params );

  @bd              = ();
  $bd[0]           = '6';                                            # record type code (1n)
  $tcode           = substr( $tcode . "  ", 0, 2 );
  $bd[1]           = $tcode;                                         # transaction code (2n)
  $routenum        = substr( "0" x 9 . $routenum, -9, 9 );
  $routenumhash    = $routenumhash + substr( $routenum, 0, 8 );
  $totroutenumhash = $totroutenumhash + substr( $routenum, 0, 8 );
  $bd[2]           = $routenum;                                      # receiving dfi identification (8n) (9n) includes check digit
  $acctnum         = substr( $acctnum . " " x 17, 0, 17 );
  $bd[3]           = $acctnum;                                       # dfi account number (17a)
  $transamt        = substr( "0" x 10 . $transamt, -10, 10 );
  $bd[4]           = $transamt;                                      # amount (10n)
                                                                     #$oid = substr($orderid,-15,15);
                                                                     #$refnumber = substr($refnumber . " " x 15,0,15);
  $refnumber       = substr( "0" x 15 . $refnumber, -15, 15 );
  $bd[5]           = $refnumber;                                     # individual identification number (15a)
  $card_name =~ s/^ +//g;
  $card_name =~ s/[^0-9a-zA-Z ]//g;
  $card_name =~ tr/a-z/A-Z/;
  $card_name = substr( $card_name . " " x 22, 0, 22 );
  $bd[6] = $card_name;                                               # individual name (22a)
  $bd[7] = "  ";                                                     # discretionary data (2a)
  $bd[8] = "0";                                                      # addenda record indicator (1n)
  $recseqnum = substr( "0" x 7 . $recseqnum, -7, 7 );
  $bd[9] = substr( $main::immediate_destination_routenumber, 0, 8 ) . $recseqnum;    # trace number (15n)

  foreach $var (@bd) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "$eol";
  print outfile2 "$eol";

}

sub batchtrailer {

  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;

  $batchsalescnt  = substr( "0000000" . $batchsalescnt, -6,  6 );
  $batchretcnt    = substr( "0000000" . $batchretcnt,   -6,  6 );
  $batchtotamt    = substr( "0" x 12 . $batchtotamt,    -12, 12 );
  $batchtotcnt    = substr( "0" x 6 . $batchtotcnt,     -6,  6 );
  $batchdetreccnt = substr( "0" x 9 . $batchdetreccnt,  -9,  9 );
  $routenumhash   = substr( "0" x 10 . $routenumhash,   -10, 10 );

  $batchsalesamt = sprintf( "%d", $batchsalesamt + .0001 );
  $batchsalesamt = substr( "0" x 12 . $batchsalesamt, -12, 12 );

  $batchretamt = sprintf( "%d", $batchretamt + .0001 );
  $batchretamt = substr( "0" x 12 . $batchretamt, -12, 12 );

  @bt       = ();
  $bt[0]    = '8';                                   # record type code (1n)
  $bt[1]    = '200';                                 # service class code (3n)
  $bt[2]    = $batchtotcnt;                          # entry/addenda count (6n)
  $bt[3]    = $routenumhash;                         # entry hash (10n)
  $bt[4]    = $batchsalesamt;                        # total debit entry dollar amt (12n)
  $bt[5]    = $batchretamt;                          # total credit entry dollar amt (12n)
  $bt[6]    = '1113392673';                          # company identification (10a)
  $bt[7]    = ' ' x 19;                              # message authentication code (19a)
  $bt[8]    = '      ';                              # reserved (6a)
                                                     #$bt[9] = '11190324';          # originating dfi identification (8a)
  $bt[9]    = '06600436';                            # originating dfi identification (8a)
  $batchnum = substr( "0" x 7 . $batchnum, -7.7 );
  $bt[10]   = $batchnum;                             # batch number (7n)

  foreach $var (@bt) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "$eol";
  print outfile2 "$eol";

}

sub fileheader {
  my ($company_name) = @_;

  my ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $julian ) = gmtime( time() );
  my $julian = $julian + 1;
  $julian = substr( "000" . $julian, -3, 3 );

  $recseqnum       = $julian . "0000";
  $filesalescnt    = 0;
  $filesalesamt    = 0;
  $fileretcnt      = 0;
  $fileretamt      = 0;
  $filetotamt      = 0;
  $filereccnt      = 1;
  $filedetreccnt   = 0;
  $batchcount      = 0;
  $batchnum        = 0;
  $totroutenumhash = 0;
  $retamt          = 0;

  $filecnt = 0;

  $file_flag = 0;

  $filename = &miscutils::incorderid($filename);

  if (0) {    #### What id FileID and FielEXT
    my @requestedData = ( 'fileid',   'fileext' );
    my @params        = ( 'username', 'pnpmtbankmst' );
    my @results = $main::dbase->databaseQuery( 'pnpmisc', 'mtbankach', \@requestedData, \@params );
    my $Data = $results[0];

    $fileext = $$Data{'fileext'};
    $fileid  = $$Data{'fileid'};
  }

  $fileid =~ tr/A-Z0-9/B-Z0-9A/;
  if ( $fileid eq "" ) {
    $fileid = "A";
  }

  my %updateData = ( 'fileid',   $fileid );
  my @params     = ( 'username', 'pnpmtbankmst' );
  my @results = $main::dbase->databaseUpdate( 'pnpmisc', 'mtbankach', \%updateData, \@params );

  umask 0077;
  open( LOGFILE, ">>$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear/t$filename.txt" );
  print LOGFILE "fileid: $fileid\n";
  close(LOGFILE);

  umask 0077;
  open( outfile,  ">$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear/$filename.txt" );
  open( outfile2, ">$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear/$filename.done" );

  my $immediate_destination_name        = substr( $main::immediate_destination_name . " " x 23,   0, 23 );    #left justified and padded to 23 characters
  my $immediate_destination_routenumber = substr( " " . $main::immediate_destination_routenumber, 0, 10 );    ## Will be right justified and padded to 10 characters

  @fh     = ();
  $fh[0]  = '1';                                                                                              # record type code (1n)
  $fh[1]  = '01';                                                                                             # priority code (2n)
  $fh[2]  = $immediate_destination_routenumber;                                                               # immediate destination route number(10a)
  $fh[3]  = $companyid;                                                                                       # immediate origin (10a)
  $cdate  = substr( $todaytime, 2, 6 );
  $ctime  = substr( $todaytime, 8, 4 );
  $fh[4]  = $cdate;                                                                                           # file creation date (6n)
  $fh[5]  = $ctime;                                                                                           # file creation time (4n)
  $fileid = substr( $fileid, 0, 1 );
  $fh[6]  = $fileid;                                                                                          # file id modifier - like a seq num, A-Z, 1-9 (1a)
  $fh[7]  = '094';                                                                                            # record size (3n)
  $fh[8]  = '10';                                                                                             # blocking factor (2n)
  $fh[9]  = '1';                                                                                              # format code (1n)
  $fh[10] = $immediate_destination_name;                                                                      # immediate destination name (23a)
  my $companystr = substr( $company_name . " " x 23, 0, 23 );
  $fh[11] = $companystr;                                                                                      # immediate origin name (23a)
                                                                                                              # xxxx
  $refcode = substr( $filename, 2, 8 );
  $fh[12] = $refcode;                                                                                         # reference code (8a)

  foreach $var (@fh) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "$eol";
  print outfile2 "$eol";
}

sub filetrailer {
  my ($company) = @_;
  print "in filetrailer\n";

  #if ($retamt > 0) {
  #  $tcode = "22";			# deposit into master account
  #  $batchorderid = &miscutils::incorderid($batchorderid);
  #  &detail($pnproutenum,$pnpacctnum,$batchorderid,"Plug & Pay Technologies, Inc.",$retamt,$tcode);
  #}

  if ( $batch_flag == 0 ) {
    &batchtrailer($company);
    $batch_flag = 1;
  }

  $filereccnt++;
  $recseqnum++;

  $filesalescnt    = substr( "0000000" . $filesalescnt,   -7,  7 );
  $filesalesamt    = substr( "0" x 12 . $filesalesamt,    -12, 12 );
  $fileretamt      = substr( "0" x 12 . $fileretamt,      -12, 12 );
  $fileretcnt      = substr( "0000000" . $fileretcnt,     -7,  7 );
  $filetotamt      = substr( "0" x 12 . $filetotamt,      -12, 12 );
  $filedetreccnt   = substr( "0" x 8 . $filedetreccnt,    -8,  8 );
  $filereccnt      = substr( "0" x 9 . $filereccnt,       -9,  9 );
  $totroutenumhash = substr( "0" x 10 . $totroutenumhash, -10, 10 );

  @ft = ();
  $ft[0] = '9';    # record type code (1n)

  # xxxx
  $batchnum = substr( "0" x 6 . $batchnum, -6.6 );
  $ft[1] = $batchnum;                     # batch count (6n)
  $blockcnt = ( $filereccnt - 1 ) / 10;
  $blockcnt = sprintf( "%06d", $blockcnt + 1 );
  $ft[2] = $blockcnt;                     # block count (6n)
  $ft[3] = $filedetreccnt;                # entry/addenda count (8n)
  $ft[4] = $totroutenumhash;              # entry hash (10n)
  $ft[5] = $filesalesamt;                 # total debit entry dollar amt in file (12n)
  $ft[6] = $fileretamt;                   # total credit entry dollar amt in file (12n)
  $ft[7] = ' ' x 39;                      # reserved (39a)

  foreach $var (@ft) {
    print outfile "$var";
    print outfile2 "$var";
  }
  print outfile "$eol";
  print outfile2 "$eol";

  # filler to make sure there are groups of 10 lines
  if ( $filereccnt % 10 != 0 ) {
    for ( $i = $filereccnt % 10 ; $i <= 9 ; $i++ ) {
      print outfile '9' x 94 . "$eol";     # filler (1n)
      print outfile2 '9' x 94 . "$eol";    # filler (1n)
    }
  }

  close(outfile);
  close(outfile2);
}

sub errorchecking {
  my ($data) = @_;

  my $errmsg = "";

  if ( ( $$data{'refnumber'} eq "" ) && ( ( $$data{'operation'} eq "auth" ) || ( ( $$data{'operation'} eq "return" ) && ( $$data{'finalstatus'} eq "locked" ) ) ) ) {
    $errmsg = "Missing transid";
  }

  if ( $$data{'acctnum'} =~ /[^0-9]/ ) {
    $errmsg = "Account number can only contain numbers";
  }

  if ( $$data{'routenum'} =~ /[^0-9]/ ) {
    $errmsg = "Route number can only contain numbers";
  }

  my $mod10 = &miscutils::mod10( $$data{'routenum'} );
  if ( $mod10 ne "success" ) {
    $errmsg = "route number failed mod10 check";
  }

  # check for 0 amount
  if ( $data{'amount'} eq "usd 0.00" ) {
    $errmsg = "amount = 0.00";
  }

  if ( $errmsg ne "" ) {
    my %updateData = ( 'finalstatus', 'problem', 'descr', "$errmsg" );
    my @params = ( 'trans_date', ">=$main::twomonthsago", 'orderid', $orderid, 'username', $username, 'finalstatus', 'locked|pending', 'accttype', 'checking|savings' );

    #my @results = $main::dbase->databaseUpdate('pnpdata','trans_log',\%updateData,\@params);
    my $transData = $results[0];

    my $operationstatus = $operation . "status";
    my $operationtime   = $operation . "time";

    my %updateData = ( "$operationstatus", 'problem', 'lastopstatus', 'problem', 'descr', "$errmsg" );
    my @params = ( 'orderid', $orderid, 'username', $username, "$operationstatus", 'locked|pending', 'voidstatus', 'NULL', 'accttype', 'checking|savings' );

    #my @results = $main::dbase->databaseUpdate('pnpdata','operation_log',\%updateData,\@params);
    my $transData = $results[0];

    return $errmsg;
  } else {
    return "0";
  }
}

sub batchdetail {
  my ( $routenum, $acctnum, $orderid, $card_name, $transamt, $tcode, $auth_code, $operation ) = @_;

  $batchdetreccnt++;
  $filedetreccnt++;
  $batchreccnt++;
  $filereccnt++;
  $recseqnum++;

  $recseqnum = substr( "0" x 7 . $recseqnum, -7, 7 );
  $transamt = sprintf( "%d", ( $transamt * 100 ) + .0001 );

  if ( $tcode =~ /^(27|37)$/ ) {
    $batchsalesamt = $batchsalesamt + $transamt;
    $batchsalescnt = $batchsalescnt + 1;
    $filesalesamt  = $filesalesamt + $transamt;
    $filesalescnt  = $filesalescnt + 1;
  } else {
    $batchretamt = $batchretamt + $transamt;
    $batchretcnt = $batchretcnt + 1;
    $fileretamt  = $fileretamt + $transamt;
    $fileretcnt  = $fileretcnt + 1;
  }
  $batchtotamt = $batchtotamt + $transamt;
  $batchtotcnt = $batchtotcnt + 1;
  $filetotamt  = $filetotamt + $transamt;

  $morderid = substr( $orderid, -16, 16 );

  my @requestedData = ('refnumber');
  my @params        = ( 'username', 'pnpmtbankmst' );
  my @results       = $main::dbase->databaseQuery( 'pnpmisc', 'mtbankach', \@requestedData, \@params );
  my $Data          = $results[0];
  $refnumber = $$Data{'refnumber'};

  $refnumber = $refnumber + 1;
  if ( $refnumber >= 999998 ) {
    $refnumber = 1;
  }

  $refnumber = substr( "0" x 15 . $refnumber, -15, 15 );
  $amt = sprintf( "%.2f", ( $transamt / 100 ) + .0001 );

  my %updateData = ( 'refnumber', $refnumber );
  my @params     = ( 'username',  'pnpmtbankmst' );
  my @results = $main::dbase->databaseUpdate( 'pnpmisc', 'mtbankach', \%updateData, \@params );

  my %insertData = (
    'username',  $username,  'filename',  $filename,  'trans_date', $today,     'orderid', $orderid, 'status', 'pending',
    'detailnum', $recseqnum, 'refnumber', $refnumber, 'operation',  $operation, 'fileext', $fileext
  );
  my @results = $main::dbase->databaseInsert( 'pnpmisc', 'batchfilesmtbank', \%insertData );

  if (0) {    #### I can't find where these tables are used for anything
    my %insertData = (
      'username',   $username, 'filename',  $filename,  'batchid',   $batchid,   'orderid', $orderid, 'fileid',     $fileid,
      'batchnum',   $batchnum, 'detailnum', $recseqnum, 'operation', $operation, 'amount',  $amt,     'descr',      $operation,
      'trans_date', $today,    'status',    'pending',  'transfee',  $feerate,   'step',    'one',    'trans_time', $todaytime
    );
    my @results = $main::dbase->databaseInsert( 'pnpmisc', 'mtbankdetails', \%insertData );
  }

  my $transflags = substr( $auth_code, 17, 10 );

  my $dd = "";    ### Discretionary Data
  if ( $transflags =~ /^recurring/i ) {
    $dd = "R";
  } else {
    $dd = "S";
  }

  @bd              = ();
  $bd[0]           = '6';                                            # record type code (1n)
  $bd[1]           = $tcode;                                         # transaction code (2n)
  $routenum        = substr( "0" x 9 . $routenum, -9, 9 );
  $routenumhash    = $routenumhash + substr( $routenum, 0, 8 );
  $totroutenumhash = $totroutenumhash + substr( $routenum, 0, 8 );
  $bd[2]           = $routenum;                                      # receiving dfi identification (8n) (9n) includes check digit
  $acctnum         = substr( $acctnum . " " x 17, 0, 17 );
  $bd[3]           = $acctnum;                                       # dfi account number (17a)
  $transamt        = substr( "0" x 10 . $transamt, -10, 10 );
  $bd[4]           = $transamt;                                      # amount (10n)
  $oid             = substr( "0" x 15 . $refnumber, -15, 15 );
  $bd[5]           = $oid;                                           # individual identification number (15a)
  $card_name =~ s/^ +//g;
  $card_name =~ s/[^0-9a-zA-Z ]//g;
  $card_name =~ tr/a-z/A-Z/;
  $card_name = substr( $card_name . " " x 22, 0, 22 );
  $bd[6] = $card_name;                                                               # individual name (22a)
  $bd[7] = "$dd ";                                                                   # discretionary data (2a)
  $bd[8] = "0";                                                                      # addenda record indicator (1n)
  $bd[9] = substr( $main::immediate_destination_routenumber, 0, 8 ) . $recseqnum;    # trace number (15n)

  my $myi = 0;
  foreach $var (@bd) {
    print outfile "$var";

    if ( ( $myi == 2 ) || ( $myi == 3 ) ) {
      $var =~ s/./x/g;
      print outfile2 "$var";
    } else {
      print outfile2 "$var";
    }
    $myi++;
  }
  print outfile "$eol";
  print outfile2 "$eol";

}

sub zoneadjust {
  my ( $origtime, $timezone1, $timezone2, $dstflag ) = @_;

  # converts from local time to gmt, or gmt to local
  print "origtime: $origtime $timezone1\n";

  if ( length($origtime) != 14 ) {
    return $origtime;
  }

  # timezone  hours  week of month  day of week  month  time   hours  week of month  day of week  month  time
  %timezonearray = (
    'EST', '-4,2,0,3,02:00, -5,1,0,11,02:00',    # 4 hours starting 2nd Sunday in March at 2am, 5 hours starting 1st Sunday in November at 2am
    'CST', '-5,2,0,3,02:00, -6,1,0,11,02:00',    # 5 hours starting 2nd Sunday in March at 2am, 6 hours starting 1st Sunday in November at 2am
    'MST', '-6,2,0,3,02:00, -7,1,0,11,02:00',    # 6 hours starting 2nd Sunday in March at 2am, 7 hours starting 1st Sunday in November at 2am
    'PST', '-7,2,0,3,02:00, -8,1,0,11,02:00',    # 7 hours starting 2nd Sunday in March at 2am, 8 hours starting 1st Sunday in November at 2am
    'GMT', ''
  );

  if ( ( $timezone1 eq $timezone2 ) || ( ( $timezone1 ne "GMT" ) && ( $timezone2 ne "GMT" ) ) ) {
    return $origtime;
  } elsif ( $timezone1 eq "GMT" ) {
    $timezone = $timezone2;
  } else {
    $timezone = $timezone1;
  }

  if ( $timezonearray{$timezone} eq "" ) {
    return $origtime;
  }

  my ( $hours1, $times1, $wday1, $month1, $time1, $hours2, $times2, $wday2, $month2, $time2 ) = split( /,/, $timezonearray{$timezone} );

  my $origtimenum =
    timegm( substr( $origtime, 12, 2 ), substr( $origtime, 10, 2 ), substr( $origtime, 8, 2 ), substr( $origtime, 6, 2 ), substr( $origtime, 4, 2 ) - 1, substr( $origtime, 0, 4 ) - 1900 );

  my $newtimenum = $origtimenum;
  if ( $timezone1 eq "GMT" ) {
    $newtimenum = $origtimenum + ( 3600 * $hours1 );
  }

  my $timenum = timegm( 0, 0, 0, 1, $month1 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month1 happens on wday $wday\n";

  if ( $wday1 < $wday ) {
    $wday1 = 7 + $wday1;
  }
  my $mday1 = ( 7 * ( $times1 - 1 ) ) + 1 + ( $wday1 - $wday );
  my $timenum1 = timegm( 0, substr( $time1, 3, 2 ), substr( $time1, 0, 2 ), $mday1, $month1 - 1, substr( $origtime, 0, 4 ) - 1900 );

  #print "time1: $time1\n\n";

  print "The $times1 Sunday of month $month1 happens on the $mday1\n";

  $timenum = timegm( 0, 0, 0, 1, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );
  my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($timenum);

  #print "The first day of month $month2 happens on wday $wday\n";

  if ( $wday2 < $wday ) {
    $wday2 = 7 + $wday2;
  }
  my $mday2 = ( 7 * ( $times2 - 1 ) ) + 1 + ( $wday2 - $wday );
  my $timenum2 = timegm( 0, substr( $time2, 3, 2 ), substr( $time2, 0, 2 ), $mday2, $month2 - 1, substr( $origtime, 0, 4 ) - 1900 );

  print "The $times2 Sunday of month $month2 happens on the $mday2\n";

  #print "origtimenum: $origtimenum\n";
  #print "newtimenum:  $newtimenum\n";
  #print "timenum1:    $timenum1\n";
  #print "timenum2:    $timenum2\n";
  my $zoneadjust = "";
  if ( $dstflag == 0 ) {
    $zoneadjust = $hours1;
  } elsif ( ( $newtimenum >= $timenum1 ) && ( $newtimenum < $timenum2 ) ) {
    $zoneadjust = $hours1;
  } else {
    $zoneadjust = $hours2;
  }

  if ( $timezone1 ne "GMT" ) {
    $zoneadjust = -$zoneadjust;
  }

  print "zoneadjust: $zoneadjust\n";
  my $newtime = &miscutils::timetostr( $origtimenum + ( 3600 * $zoneadjust ) );
  print "newtime: $newtime $timezone2\n\n";
  return $newtime;

}

sub pidcheck {
  open( infile, "$root_file_path/batchfiles/$devprodlogs/mtbankach/pid.txt" );
  $chkline = <infile>;
  chop $chkline;
  close(infile);

  if ( $pidline ne $chkline ) {
    umask 0077;
    open( LOGFILE, ">>$root_file_path/batchfiles/$devprodlogs/mtbankach/$fileyear/$username$time$$.txt" );
    print LOGFILE "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print LOGFILE "$pidline\n";
    print LOGFILE "$chkline\n";
    close(LOGFILE);

    print "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print "$pidline\n";
    print "$chkline\n";

    open( MAILERR, "| /usr/lib/sendmail -t" );
    print MAILERR "To: cprice\@plugnpay.com\n";
    print MAILERR "Cc: dprice\@plugnpay.com\n";
    print MAILERR "From: dcprice\@plugnpay.com\n";
    print MAILERR "Subject: mtbankach - dup genfiles\n";
    print MAILERR "\n";
    print MAILERR "$username\n";
    print MAILERR "genfiles.pl already running, pid alterred by another program, exiting...\n";
    print MAILERR "$pidline\n";
    print MAILERR "$chkline\n";
    close MAILERR;

    exit;
  }
}

