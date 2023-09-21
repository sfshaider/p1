package PlugNPay::LogFilter::Filter;

use Apache2::Const;
use APR::Const;
ModPERL::Const;
use PlugNPay::Email;

use strict;
#use warnings;

$LogFilter::Filter::progstart = time();
$LogFilter::Filter::path_siglog = "/home/apache/logs/signature_log.txt";  ##Log Activity
$LogFilter::Filter::siglist = "/home/apache/signature_list.txt";   ##Hack Signatures 1 per line
$LogFilter::Filter::iplist = "/home/apache/ip_list.txt";   ##IP Signatures 1 per line
$LogFilter::Filter::run_quiet = "/home/apache/runquiet.txt";   ##If file exists do not send emails

## Signature File Load Test
$LogFilter::Filter::sigload_time = 0;
$LogFilter::Filter::ipload_time = 0;

@LogFilter::Filter::sigarray = ();
@LogFilter::Filter::iparray = ('216.71.84.58');
@LogFilter::Filter::uriarray =('xz.cgi','.pl');



sub handler {
  my $r = shift;
  my $c = $r->connection;

  my ($username,$file_name,$sigfile_time,$sigfile_age,$ipfile_time,$ipfile_age);

  my $fndsigflg = 0;
  my $sigfound = "";
  my %apache = ();

  #Gather the per-request data and put it into a hash.
  # See http://perl.apache.org/docs/1.0/api/Apache.html#Client_Request_Parameters
  # For available paramter list

  #The $r->headers_in method will return a %hash of client request headers. 
  #This can be used to initialize a perl hash, or one could use the $r->header_in() method (described below) to retrieve a specific header value directly.
  #Will return a HASH reference blessed into the Apache::Table class when called in a scalar context with no "key" argument. This requires Apache::Table.
  #$r->header_in( $header_name, [$value] )
  #Return the value of a client header. Can be used like this:
  #$ct = $r->header_in("Content-type");
  #$r->header_in($key, $val); #set the value of header '$key'

  $apache{'request'} = $r->the_request;
  $apache{'status'} = $r->status;
  $apache{'bytes'} = $r->bytes_sent;
  $apache{'file'} = $r->filename;
  $apache{'uri'} = $r->uri;
  #$apache{'content'} = $r->content;   ## Empty - Probably as this is called at the end when logging and content has already been read

  $apache{'time'} = $r->request_time;
  $apache{'date'} = localtime($apache{'time'});
  my $localdatestr = &miscutils::timetostr("$apache{'time'}");

  $apache{'hostname'} = $r->hostname;
  $apache{'remote_ip'} = $c->remote_ip;


  if ($apache{'remote_ip'} =~ /10\.150\.50|10\.150\.97|204\.238\.82/) {
    return OK;
  }

  ## Headers

  my %headers = $r->headers_in;
  $apache{'useragent'} = $headers{'User-Agent'};
  $apache{'cookie'}= $headers{'Cookie'};
  $apache{'referer'} = $headers{'Referer'};
  

  ## QUERY STRING
  # $query = $r->args;   ## Data returned as string
  my %query  = $r->args;  ## Data returned as name/value hash
  my $qstr = $r->args;

  ## Clean Up Empty Apache Parameters
  foreach my $key (keys %apache) {
    if ($apache{$key} eq "") {
      delete $apache{$key};
    }
  }


  if (1) {  ### Commented Out for Testing

  ## Signature File Load Test
  $sigfile_age = (-M $LogFilter::Filter::siglist) * 24 * 3600;
  $sigfile_time = $LogFilter::Filter::progstart - $sigfile_age;

  if ($sigfile_time > $LogFilter::Filter::sigload_time) {    ## If timestamp on file is greater than time file was last opened then reload hack signatures.
    my ($dummy,$dummy1,$time) = &miscutils::gendatetime();
    my $now = localtime(time());
    open (SIGLOG,">>$LogFilter::Filter::path_siglog");
    print SIGLOG "LOADFILE, $now, PID:$$, SA:$sigfile_age, ST:$sigfile_time, LT:$LogFilter::Filter::sigload_time, START:$LogFilter::Filter::progstart\n";

    $LogFilter::Filter::sigload_time = time();  ## Load time siglist is loaded.

    open (SIGLIST,"$LogFilter::Filter::siglist");
    while (<SIGLIST>) {
      chop;
      if ($_ ne "") {
        print SIGLOG "$_, ";
        push (@LogFilter::Filter::sigarray,"$_");
      }
    }
    close (SIGLIST);
    print SIGLOG "\n";
    close (SIGLOG);
  }

  }

  foreach my $sig (@LogFilter::Filter::sigarray) {
    if ($sig ne "") {
      if (($apache{'useragent'} =~ /$sig/i) || ($apache{'cookie'} =~  /$sig/i) || ($apache{'referrer'} =~  /$sig/i)) {  
        $fndsigflg = 1;
        $sigfound = $sig;
      }
    }
  }

  if (-e "$LogFilter::Filter::iplist") {  ### Commented Out for Testing

  ## IP List
  $ipfile_age = (-M $LogFilter::Filter::iplist) * 24 * 3600;
  $ipfile_time = $LogFilter::Filter::progstart - $ipfile_age;

  if ($ipfile_time > $LogFilter::Filter::ipload_time) {    ## If timestamp on file is greater than time file was last opened then reload hack signatures.
    my ($dummy,$dummy1,$time) = &miscutils::gendatetime();
    my $now = localtime(time());
    open (SIGLOG,">>$LogFilter::Filter::path_siglog");
    print SIGLOG "LOADFILE, $now, PID:$$, SA:$ipfile_age, ST:$ipfile_time, LT:$LogFilter::Filter::ipload_time, START:$LogFilter::Filter::progstart\n";

    $LogFilter::Filter::ipload_time = time();  ## Load time siglist is loaded.

    open (SIGLIST,"$LogFilter::Filter::iplist");
    while (<SIGLIST>) {
      chop;
      if ($_ ne "") {
        print SIGLOG "$_, ";
        push (@LogFilter::Filter::iparray,"$_");
      }
    }
    close (SIGLIST);
    print SIGLOG "\n";
    close (SIGLOG);
  }

  }

  ### IP Filter
  foreach my $sig (@LogFilter::Filter::iparray) {
    if ($sig ne "") {
      if ($apache{'remote_ip'} =~ /$sig/i) {
        $fndsigflg = 1;
        $sigfound = $sig;
      }
    }
  }

  ###  URI Filter
  foreach my $sig (@LogFilter::Filter::uriarray) {
    if ($sig ne "") {
      if ($apache{'uri'} =~ /$sig$/i) {
        $fndsigflg = 1;
        $sigfound = $sig;
      }
    }
  }


  if ($fndsigflg == 1) {  ###  Found Hack Signature
    my @array = %apache;
    &log_hack("$sigfound",@array);

    my $now = localtime(time());

    my $msg = "$now\n";
    foreach my $key (keys %apache) {
      $msg .= "$key:$apache{$key}\n";
    }
    $msg .= "Suspect Signature Found: $sigfound\n";

    &sendemail($msg,$apache{'hostname'});

    $msg = "uri:$apache{'uri'}\nSuspect Signature Found: $sigfound\n";
    &sendpage($msg,$apache{'hostname'}); 

    $fndsigflg = 0; ## Reset Flag
    $sigfound = "";
  }


  if (-e "/home/apache/logs/enable_logfilter_debug.txt") {
    open (DEBUG,">>/home/apache/logs/logfilter.txt");
    print DEBUG "HEADER\n";
    foreach my $key (sort keys %headers) {
      print DEBUG "$key:$headers{$key}\n";
    }
    print DEBUG "DATE:$apache{'date'}, DATESTR:$localdatestr, HOSTNAME:$apache{'hostname'}, STATUS:$apache{'status'}, BYTES:$apache{'bytes'}, FILE:$apache{'file'}, URI:$apache{'uri'}, REMIP:$apache{'remote_ip'}\n";
    print DEBUG "QUERY\n";
    print DEBUG "QSTR:$qstr\n";
    foreach my $key (sort keys %query) {
      print DEBUG "K:$key:$query{$key}\n";
    }
    print DEBUG "REQUEST\n";
    print DEBUG "$apache{'request'}\n";
    print DEBUG "Content\n";
    print DEBUG "$apache{'content'}\n";

    close (DEBUG);
  }

  return OK;
}


sub sendemail {
  my ($msg,$hostname) = @_;

  if (-e "$LogFilter::Filter::run_quiet") {
    return;
  }

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
  my $time = sprintf("%02d/%02d %02d:%02d",$mon+1,$mday,$hour,$min);

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setTo('dprice@plugnpay.com');
  $emailObj->setFrom('checklog@plugnpay.com');
  $emailObj->setSubject("Hack Attempt $hostname");

  my $message = '';
  $message .= "$time\n\n";
  $message .= "$msg\n";

  $emailObj->setContent($message);
  $emailObj->send();
}

sub sendpage {
  my ($msg,$hostname) = @_;

  if (-e "$LogFilter::Filter::run_quiet") {
    return;
  }
  
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
  my $time = sprintf("%02d/%02d %02d:%02d",$mon+1,$mday,$hour,$min);

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setFormat('text');
  $emailObj->setTo('6318061932@txt.att.net');
  $emailObj->setFrom('checklog@plugnpay.com');
  $emailObj->setSubject("Hack Attempt $hostname");

  my $message = '';
  $message .= "$time\n\n";
  $message .= "$msg\n";

  $emailObj->setContent($message);
  $emailObj->send();
}


sub log_hack {
  my ($sigfound,%apache) = @_;
  open (HACKLOG, ">>$LogFilter::Filter::path_siglog");
  my $now = localtime(time());
  print HACKLOG "HACKFND, $now, SIG:$sigfound, PID:$$, ";
  foreach my $key (sort keys %apache) {
    print HACKLOG "K:$key:$apache{$key}, ";
  }
  print HACKLOG "\n\n";
  close(HACKLOG);

  return;
}


1;
