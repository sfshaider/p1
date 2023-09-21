#!/usr/local/bin/perl

use lib $ENV{'PNP_PERL_LIB'};

use miscutils;
use DBI;
use rsautils;
use smpsutils;
use SHA;
use Time::Local;

$errmsg = "";

$todaytime = time();

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime($todaytime);
$today = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$hournow = sprintf( "%02d", $hour );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime($todaytime);
$todaygmt = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = localtime( $todaytime - ( 3600 * 24 ) );
$yesterday = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
$dayofweek = $wday;

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $todaytime - ( 3600 * 24 ) );
$yesterdaygmt = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( $todaytime + ( 3600 * 24 ) );
$tomorrowgmt = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

$line = `crontab -l | grep '/genfiles.pl'`;
(@lines) = split( /\n/, $line );
foreach $line (@lines) {
  my $processor = "";
  my $group     = "";

  if ( $line =~ /^\s*#/ ) {
    next;
  }
  if ( $line =~ /^.*\/([a-z]+)\/genfiles.pl ([0-9]{0,1})/ ) {
    $processor = $1;
    $group     = $2;

  }

  &checkfiledates( $processor, $group );
}

&checkruntime();

if ( $hournow == 9 ) {
  &checkgetfiles();
}

&checkfdms();

print "\n";
print "errmsg:\n";
print "$errmsg\n";

if ( $errmsg ne "" ) {
  $mytime = gmtime( time() );
  open( MAIL, "| /usr/lib/sendmail -t" );
  print MAIL "To: 3039219466\@vtext.com\n";

  #print MAIL "Bcc: 6318061932\@txt.att.net\n";
  print MAIL "Bcc: cprice\@skybeam.com\n";
  print MAIL "Bcc: dprice\@plugnpay.com\n";
  print MAIL "From: checkbatch\@plugnpay.com\n";
  print MAIL "Subject: FAILURE - checkbatch\n\n";
  print MAIL "$mytime\n\n";
  print MAIL "$errmsg\n";
  close(MAIL);
}

exit;

sub checkfiledates {
  my ( $processor, $group ) = @_;

  #print "/home/p/pay1/batchfiles/$processor/genfiles$group.txt\n";
  if ( !-e "/home/p/pay1/batchfiles/$processor/genfiles$group.txt" ) {
    return;
  }

  ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "/home/p/pay1/batchfiles/$processor/genfiles$group.txt";
  $lastupdatedhours = ( $todaytime - $modtime ) / 3600;

  if ( ( $processor !~ /cccc|cayman|paymentdata/ ) && ( $lastupdatedhours > 25 ) ) {
    $errmsg .= "File has not been updated in 24 hours:\n  $processor/genfiles$group.txt\n\n";
  }

  open( infile, "/home/p/pay1/batchfiles/$processor/genfiles$group.txt" );
  $username = <infile>;
  chop $username;
  close(infile);

  if ( $username ne "" ) {
    print "username: $username\n";

    $fileyear = substr( $tomorrowgmt, 0, 4 ) . "/" . substr( $tomorrowgmt, 4, 2 ) . "/" . substr( $tomorrowgmt, 6, 2 );

    $filename = `ls -1t /home/p/pay1/batchfiles/logs/$processor/$fileyear/$username*`;
    ($filename) = split( /\n/, $filename );

    if ( $filename eq "" ) {
      $filename = `ls -1t /home/p/pay1/batchfiles/logs/$processor/$fileyear/201*`;
      ($filename) = split( /\n/, $filename );
    }
    if ( $filename eq "" ) {
      $filename = `ls -1t /home/p/pay1/batchfiles/logs/$processor/$fileyear/G*`;
      ($filename) = split( /\n/, $filename );
    }

    if ( $filename ne "" ) {
      print "$filename\n";
      ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "$filename";
      $minutes = ( $todaytime - $modtime ) / 60;
      if ( $minutes < 0 ) {
        $minutes = 0;
      }
      if ( $minutes > 60 ) {
        $minutes = sprintf( "%d", $minutes );
        $errmsg .= "File not updated in one hour: $minutes\n  $filename\n\n";
      }
    } else {
      $fileyear = substr( $todaygmt, 0, 4 ) . "/" . substr( $todaygmt, 4, 2 ) . "/" . substr( $todaygmt, 6, 2 );

      $filename = `ls -1t /home/p/pay1/batchfiles/logs/$processor/$fileyear/$username*`;
      ($filename) = split( /\n/, $filename );

      if ( $filename eq "" ) {
        $filename = `ls -1t /home/p/pay1/batchfiles/logs/$processor/$fileyear/201*`;
        ($filename) = split( /\n/, $filename );
      }
      if ( $filename eq "" ) {
        $filename = `ls -1t /home/p/pay1/batchfiles/logs/$processor/$fileyear/G*`;
        ($filename) = split( /\n/, $filename );
      }

      if ( $filename ne "" ) {
        print "$filename\n";
        ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "$filename";
        $minutes = ( $todaytime - $modtime ) / 60;
        if ( $minutes < 0 ) {
          $minutes = 0;
        }
        if ( $minutes > 60 ) {
          $minutes = sprintf( "%d", $minutes );
          $errmsg .= "File not updated in one hour: $minutes\n  $filename\n\n";
        }
      } else {
        $fileyear = substr( $yesterdaygmt, 0, 4 ) . "/" . substr( $yesterdaygmt, 4, 2 ) . "/" . substr( $yesterdaygmt, 6, 2 );

        $filename = `ls -1t /home/p/pay1/batchfiles/logs/$processor/$fileyear/$username*`;
        ($filename) = split( /\n/, $filename );

        if ( $filename eq "" ) {
          $filename = `ls -1t /home/p/pay1/batchfiles/logs/$processor/$fileyear/201*`;
          ($filename) = split( /\n/, $filename );
        }
        if ( $filename eq "" ) {
          $filename = `ls -1t /home/p/pay1/batchfiles/logs/$processor/$fileyear/G*`;
          ($filename) = split( /\n/, $filename );
        }

        if ( $filename ne "" ) {
          print "$filename\n";
          ( $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $modtime ) = stat "$filename";
          $minutes = ( $todaytime - $modtime ) / 60;
          if ( $minutes < 0 ) {
            $minutes = 0;
          }
          if ( $minutes > 60 ) {
            $errmsg .= "File has not been updated in one hour: $todaytime  $modtime  $minutes\n  $filename\n\n";
          }
        } else {
          $errmsg .= "File cannot be found:\n  $processor $username\n\n";
        }

      }

    }
  }

}

sub checkruntime {

  $line = `ps -ef | grep genfiles | grep perl | grep -v grep | grep -v vim`;

  (@lines) = split( /\n/, $line );

  foreach $line (@lines) {
    $line =~ s/^ +//g;
    ( $d1, $d2, $d3, $d4, $time ) = split( / +/, $line );

    #print "\n$line\n";

    $processor = $line;
    $processor =~ s/\/genfiles.*$//g;
    $processor =~ s/^.*\///g;
    $processor =~ s/^.* //g;

    $group = $line;
    $group =~ s/^.*genfiles.*.pl //;
    $group = substr( $group, 0, 1 );
    if ( $group !~ /[0-9]/ ) {
      $group = "";
    }

    print "\nprocessor: $processor\n";
    print "group: $group\n";

    open( infile, "/home/p/pay1/batchfiles/$processor/genfiles$group.txt" );
    $username = <infile>;
    chop $username;
    close(infile);

    print "username: $username aa\n";

    if ( $time !~ /\:/ ) {
      my $shortline = substr( $line, 14 );
      $shortline =~ s/\/usr\/local\/bin\/perl/perl/;
      $shortline =~ s/\/home\/pay1\///;
      if ( ( $processor ne "epx" ) || ( $hournow > 8 ) ) {
        $errmsg .= "genfiles.pl $group running too long: $shortline\n";
        print "genfiles.pl $group running too long: $shortline\n";
      }
    } else {
      $time =~ s/\://g;
      $hour = substr( $time, 0, 1 );

      if ( $hour > $hournow ) {
        $day = $yesterday;
      } else {
        $day = $today;
      }
      $starttime = $day . $time;

      #$starttime = &zoneadjust($starttime,"EST","GMT",1);
      print "starttime: $starttime\n";
      $starttime = &strtotime($starttime);
      print "starttime: $starttime\n";
      $delta = $todaytime - $starttime;

      $minutes = $delta / 60;
      $hours   = $delta / 3600;

      if ( $hours < 0 ) {
        $hours = 0 - $hours;
      }

      if ( $minutes < 0 ) {
        $minutes = 0 - $minutes;
      }

      if ( $delta < 0 ) {
        $delta = 0 - $delta;
      }

      print "genfiles.pl $group has been running for $hours hours\n";
      print "genfiles.pl $group has been running for $minutes minutes\n";

      #print "genfiles.pl $group has been running for $delta seconds\n";

      if ( $hours > 12 ) {
        my $shortline = substr( $line, 14 );
        $shortline =~ s/\/usr\/local\/bin\/perl/perl/;
        $shortline =~ s/\/home\/pay1\///;
        $errmsg .= "genfiles.pl $group running too long: $shortline\n";
        print "genfiles.pl $group running too long: $shortline\n";
      }
    }
  }

}

sub checkgetfiles {
  $fileyear = substr( $yesterdaygmt, 0, 4 ) . "/" . substr( $yesterdaygmt, 4, 2 ) . "/" . substr( $yesterdaygmt, 6, 2 );
  if ( $dayofweek !~ /(0|1|2|3|4)/ ) {
    return;
  }

  $filename = `ls -1t /home/p/pay1/batchfiles/logs/paymentdata/$fileyear/20*`;
  ($filename) = split( /\n/, $filename );

  if ( $filename ne "" ) {
    $filename = `ls -1t /home/p/pay1/batchfiles/logs/paymentdata/$fileyear/PNP.*.pend*`;
    ($filename) = split( /\n/, $filename );
    if ( $filename eq "" ) {
      $errmsg .= "paymentdata didn't receive a .pend file for $yesterdaygmt\n";
      print "paymentdata didn't receive a .pend file for $yesterdaygmt\n";
    }
  }
}

sub checkfdms {
  if ( -e "/home/p/pay1/batchfiles/fdms/batcherror.txt" ) {
    open( infile, "/home/p/pay1/batchfiles/fdms/batcherror.txt" );
    while (<infile>) {
      $errmsg .= $_;
    }
    close(infile);
  }
}

sub strtotime {
  my ($string) = @_;

  if ( $string ne "" ) {
    my $year  = substr( $string, 0,  4 );
    my $month = substr( $string, 4,  2 );
    my $day   = substr( $string, 6,  2 );
    my $hour  = substr( $string, 8,  2 );
    my $min   = substr( $string, 10, 2 );
    my $sec   = substr( $string, 12, 2 );

    if ( ( $month =~ /^(04|06|09|11)$/ ) && ( $day > 30 ) ) {
      $day = 30;
    } elsif ( ( $year =~ /^(2004|2008|2012|2016|2020|2024|2028)$/ )
      && ( $month eq "02" )
      && ( $day > 29 ) ) {
      $day = 29;
    } elsif ( ( $year !~ /^(2004|2008|2012|2016|2020|2024|2028)$/ )
      && ( $month eq "02" )
      && ( $day > 28 ) ) {
      $day = 28;
    } elsif ( $day > 31 ) {
      $day = 31;
    }

    if ( ( $year < 1995 )
      || ( $year > 2032 )
      || ( $month < 1 )
      || ( $month > 12 )
      || ( $day < 1 )
      || ( $day > 31 )
      || ( $hour < 0 )
      || ( $hour > 23 )
      || ( $min < 0 )
      || ( $min > 59 )
      || ( $sec < 0 )
      || ( $sec > 59 ) ) {
      return "";
    }

    $string = $string . "000000";
    my $time = timelocal( $sec, $min, $hour, $day, $month - 1, $year - 1900 );

    #my $time = timegm(substr($string,12,2),substr($string,10,2),substr($string,8,2),substr($string,6,2),substr($string,4,2)-1,substr($string,0,4)-1900);
    return $time;
  }
  return "";
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

exit;

