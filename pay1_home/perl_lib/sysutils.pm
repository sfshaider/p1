package sysutils;

use strict;
use PlugNPay::Environment;
use pnp_environment;
use PlugNPay::Logging::DataLog;

# examples
#
# use sysutils.pm
# ...
# $filepath = "/home/p/pay1/web/payment/recurring/";
# $filepath = "/home/p/pay1/webtxt/payment/recurring/";
# $filepath = "./recurring/";
# my $newfilename = &sysutils::filefilter($filepath,$filename,$suffix);
# open (INFILE,"$newfilename");
#


sub logupload {
  my ($username,$operation,$destination,$filename) = @_;

  my $environment = new PlugNPay::Environment();
  my $remoteIP = $environment->get('PNP_CLIENT_IP');
  $username =~ s/[^0-9a-zA-Z]//g;
  $operation =~ s/[^0-9a-zA-Z]//g;
  $destination =~ s/[^0-9a-zA-Z_\/\.\*\-]//g;

  my ($lsec,$lmin,$lhour,$lday,$lmonth,$lyear,$wday,$yday,$isdst) = localtime(time());
  $lyear = $lyear + 1900;
  my $timestr = sprintf("%04d%02d%02d%02d%02d%02d", $lyear, $lmonth+1, $lday, $lhour, $lmin, $lsec);

  my $webtxt = &pnp_environment::get('PNP_WEB_TXT');

  if ($filename ne "") {
    $filename =~ s/$webtxt\/uploaddir\///;
    chmod(0666,"$webtxt/uploaddir/$filename");
  }

  open(OUTFILE,">>$webtxt/uploaddir/instructions.txt");
  print OUTFILE "$timestr $username $remoteIP $operation $destination $filename\n";
  close(OUTFILE);
}


sub filelog {
  my ($operation,$message) = @_;

  new PlugNPay::Logging::DataLog({'collection' => 'refactor_me'})->log({
    'message'               => 'File access logger called, please remove read/write to local files',
    'function'              => 'sysutils::filelog',
    'operation'             => $operation,
    'message'               => $message,
    'alternateModuleToCall' => 'Use S3 to read/write to files (or PlugNPay::AWS::FileMigration once rolled out'
  });

  #my $webtxt = &pnp_environment::get('PNP_WEB_TXT');
  #my $environment = new PlugNPay::Environment();
  #my $remoteIP = $environment->get('PNP_CLIENT_IP');


  #my $mytime = gmtime(time());
  #open(OUTFILE,">>$webtxt\/filelog.txt");
  #printf OUTFILE ("%s\t%s\t%s\t%s\t%s\n", $mytime, $remoteIP, $operation, $ENV{'SCRIPT_NAME'}, $message);
  #close(OUTFILE);
}


sub filefilter {
  my ($filepath, $filename) = @_;

  my $origfilename = $filename;
  my $errormsg = "";

  my $environment = new PlugNPay::Environment();
  my $remoteIP = $environment->get('PNP_CLIENT_IP');
  my $web = &pnp_environment::get('PNP_WEB');
  my $webtxt = &pnp_environment::get('PNP_WEB_TXT');

  #my $logfiledir = "/home/p/pay1/webtxt";
  my $logfiledir = $webtxt;

  # fail if filepath does not begin with the path to web or webtxt or has .. in it
  if ($filepath =~ /[^a-zA-Z0-9\/_\.]/) {
    $errormsg .= "filepath invalid characters, ";
  }
  if ($filepath =~ /\.\./) {
    $errormsg .= "filepath double dots, ";
  }
  if (($filepath =~ /^\//) && ($filepath !~ /^($web|$webtxt)\//)) {
    $errormsg .= "filepath other than /home..., ";
  }

  if ($filepath eq "") {
    $filepath = ".";
  }

  my $suffix = $filename;
  $suffix =~ s/^.*\.([a-zA-Z]{2,4})$/$1/;
  $filename =~ s/^(.*)\.[a-zA-Z]{2,4}$/$1/;


  if (($filename eq "") || ($suffix eq "")) {
    $errormsg .= "filename or suffix empty, ";
  }

  # fail if filename other than letters, numbers, dash, underscore, dot
  if ($filename !~ /^[a-zA-Z0-9-_\.]+$/) {
    $errormsg .= "filename invalid characters, ";
  }

  # fail if suffix has other than 2 to 4 letters
  if ($suffix !~ /^[a-zA-Z]{2,4}$/) {
    $errormsg .= "suffix invalid characters, ";
  }
  if ($suffix !~ /^(jpg|xml|gif|txt|html|iif|csv|htm|css|bmp|png|zip|gz|jar|pdf|doc|xls|ppt|sit|tar|tgz|db)$/i) {
    $errormsg .= "suffix extension not allowed, ";
  }

  my $mytime = gmtime(time());
  open(OUTFILE,">>$logfiledir/sysutilsout.txt");
  print OUTFILE "$mytime  $remoteIP $ENV{'SCRIPT_NAME'}  $filepath/$filename.$suffix    $filepath  $origfilename  $errormsg\n";
  close(OUTFILE);

  if ($errormsg ne "") {
    open(ERRFILE,">>$logfiledir/sysutilserr.txt");
    print ERRFILE "$mytime  $remoteIP $ENV{'SCRIPT_NAME'}  $filepath  $origfilename  $errormsg\n";
    close(ERRFILE);
    return undef;
  }

  return "$filepath/$filename.$suffix";
}


sub myopen {
  my ($openmode, $filepath, $filename, $suffix) = @_;

  # will return undef on failure check your file handle.
  # openmode defaults to read only
  # openmode valid values < > >> +< +> +>>

  # filter filename
  # strip out anything not a-z A-Z 0-9 - or _ from filename
  if ($filename =~ /[^a-zA-Z0-9-_]/) {
    return undef;
  }

  # default to read only access for openmode
  if ($openmode eq "") {
    $openmode = "<";
  }
  
  # only < > and + are valid for openmode
  if ($openmode =~ /[^<>+]/) {
    return undef;
  }

  my $file_to_open = $filepath . $filename . $suffix;
  if (($openmode =~ /(\<|\>\>)/) && (! -e $file_to_open)) {
    return undef;
  }
  else {
    $file_to_open = $openmode . $file_to_open;
    my $result = undef;
    open($result, "$file_to_open");
  
    return $result;
  }
}

1;
