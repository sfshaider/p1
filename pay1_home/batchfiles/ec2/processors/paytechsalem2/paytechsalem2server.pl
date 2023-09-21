#!/bin/env perl

use lib '/home/pay1/batchfiles/perl_lib';
use lib '/home/pay1/batchfiles/perlpr_lib';

use miscutils;
use procutils;
use IO::Socket;
use Socket;

use rsautils;
use PlugNPay::CreditCard;
use PlugNPay::Processor::ProcessorMessageServiceClient;

sub proc {
  return 'paytechsalem2';
}

my $test = $ENV{'DEVELOPMENT'} eq 'TRUE' ? "yes" : "no";

if ( -e "/home/pay1/batchfiles/logs/paytechsalem2/failover.txt" ) {
  exit;
}

$keepalive   = time();
$getrespflag = 1;
$sequencenum = 0;
$numtrans    = 0;        # used only for throughput checks

## New Salem Host Address
$primaryipaddress = "206.253.180.113";    # primary server

$primaryport = "4558";                    ### Port when routing via IN.

$ipaddress1 = "206.253.184.65";           # secondary server
$port1      = "4623";

$ipaddress2 = $ipaddress1;                # secondary server
$port2      = $port1;

$testipaddress = "206.253.180.137";       # test server

$testport = "8526";                       # test server	# which one?

$ipaddress = $primaryipaddress;
$port      = $primaryport;

my %transactionRequestIdMap;

&checksecondary();
&socketopen( "$ipaddress", "$port" );

# delete rows older than 2 minutes
my $now      = time();
my $deltime  = &miscutils::timetostr( $now - 600 );
my $printstr = "deltime: $deltime\n";
my $logData = { 'deltime' => "$deltime", 'msg' => "$printstr" };
writeDebug( $username, $logData );

while (1) {
  &check();

  if ( $getrespflag == 0 ) {
    my $temptime   = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$temptime    getrespflag = 0, closing socket\n";
    my $logData = { 'temptime' => "$temptime", 'getrespflag' => "$getrespflag", 'msg' => "$logfilestr" };
    writeServerLog( $username, $logData );

    close(SOCK);
    $socketopenflag = 0;
    $getrespflag    = 1;
    &checksecondary();
    &socketopen( "$ipaddress", "$port" );    # primary server
  }

  $mytime  = time();
  $mydelta = $mytime - $keepalive;
  if ( $mytime - $keepalive >= 130 ) {
    my $printstr = "time - keepalive:  $mytime  $keepalive  $mydelta\n";
    my $logData = { 'mytime' => "$mytime", 'keepalive' => "$keepalive", 'mydelta' => "$mydelta", 'msg' => "$printstr" };
    writeDebug( $username, $logData );
    &socketread(0);

    if ( ( $mytime - $keepalive >= 370 ) && ( $keepalive > 0 ) ) {
      $temptime   = gmtime( time() );
      $logfilestr = "";
      $logfilestr .= "$temptime    no heartbeat, closing socket\n";
      my $logData = { 'temptime' => "$temptime", 'msg' => "$logfilestr" };
      writeServerLog( $username, $logData );

      close(SOCK);
      $socketopenflag = 0;
      $keepalive      = time();
      $getrespflag    = 1;
      &checksecondary();
      &socketopen( "$ipaddress", "$port" );    # primary server
    }
  }
}

exit;

sub check {
  $todayseconds = time();
  my ( $sec1, $min1, $hour1, $day1, $month1, $year1, $dummy4 ) = gmtime( $todayseconds - ( 60 * 2 ) );
  $ttime1 = sprintf( "%04d%02d%02d%02d%02d%02d", $year1 + 1900, $month1 + 1, $day1, $hour1, $min1, $sec1 );

  $transcnt            = 0;
  $timecheckfirstflag  = 1;
  $timecheckfirstflag2 = 1;

  # retry
  foreach $rsequencenum ( keys %susername ) {
    $logfilestr = "";
    $logfilestr .= "retry: $sretries{$rsequencenum} $smessagestr{$rsequencenum}\n";
    my $logData = { 'retry' => "$sretries{$rsequencenum} $smessagestr{$rsequencenum}", 'msg' => "$logfilestr" };
    writeServerLog( $username, $logData );
    &socketwrite( $smessage{$rsequencenum} );
    $transcnt++;
  }

  my $pmsc = new PlugNPay::Processor::ProcessorMessageServiceClient(proc());
  my $request = $pmsc->newGetTransactionsRequest();

  $request->setProcessor(proc());
  $request->setCount(5);
  $request->setTimeout(1.0);
  my $responseStatus = $pmsc->sendRequest($request);
  if (!$responseStatus) {
    writeServerLog( '', {
      message => 'failed to get transactions from processor message service, will retry in 2s'
    });
    select undef,undef,undef,2.0;
    next;
  }

  my $response = $responseStatus->get('response');

  while (my $hasAnotherTransaction = $response->getTransaction()) {
    my $transaction = $hasAnotherTransaction->get('transaction');
    my $username = $transaction{'username'};
    my $orderid = $transaction->{'orderId'};
    my $message = $transaction->{'data'};
    my $transactionRequestId = $transaction->{'transactionRequestId'};
    
    datalog({
      username => $username,
      orderId => $orderid,
      message => sprintf('received transaction data for %s:%s from processor message service',$username,$orderid)
    });

    $username =~ s/[^0-9a-zA-Z_]//g;
    $orderid =~ s/[^0-9]//g;

    my $printstr = "";

    $transcnt++;
    $logfilestr = "";
    $logfilestr .= "transcnt: $transcnt\n";

    # invoicenum is characters (starting from 0) 5 through 25
    $invoicenum = substr($message,5,22);
    $sequencenum = $invoicenum;

    # set the transaction request id in the map so we can look it up later
    $transactionRequestIdMap{$sequencenum} = $transactionRequestId;

    $message = substr( $message, 0, 4 ) . $invoicenum . substr( $message, 26 );
    

    $printstr .= "sequencenum: $sequencenum\n";
    my $logData = { 'sequencenum' => "$sequencenum", 'msg' => "$printstr" };
    writeDebug( $username, $logData );

    $susername{"$sequencenum"}   = $username;
    $strans_time{"$sequencenum"} = $trans_time;
    $smessage{"$sequencenum"}    = $message;
    $sretries{"$sequencenum"}    = 1;
    $sorderid{"$sequencenum"}    = $orderid;
    $sinvoicenum{"$sequencenum"} = $sequencenum;

    $cardnum = substr( $message, 28, 19 );
    $cardnum =~ s/[^0-9]//g;
    $xs         = "x" x length($cardnum);
    $messagestr = $message;
    $messagestr =~ s/$cardnum/$xs/g;

    $extradata = substr( $message, 84 );
    $datalen   = length($extradata);
    $dataidx   = 84;
    my $temp   = $extradata;
    my $newidx = 0;
    for ( my $newidx = 0 ; $newidx < $datalen ; ) {
      $tag = substr( $temp, $newidx + 0, 2 );
      if ( $tag eq "EC" ) {
        $taglen = 11;
      } elsif ( $tag eq "AB" ) {
        $taglen = 139;
      } elsif ( $tag eq "FR" ) {
        $taglen = 7;
      } else {
        last;
      }
      if ( $tag eq "FR" ) {
        $cvv = substr( $temp, $newidx + 3, 4 );
        if ( $cvv =~ /[0-9]{3} / ) {
          $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 3 ) . 'xxx ' . substr( $messagestr, $dataidx + $newidx + 3 + 4 );
        } elsif ( $cvv =~ /[0-9]{4}/ ) {
          $messagestr = substr( $messagestr, 0, $dataidx + $newidx + 3 ) . 'xxxx' . substr( $messagestr, $dataidx + $newidx + 3 + 4 );
        }
      }
      $newidx = $newidx + $taglen;
    }

    $cardnumber = $cardnum;

    my $cc = new PlugNPay::CreditCard($cardnumber);
    $shacardnumber = $cc->getCardHash();

    $mytime       = gmtime( time() );
    $checkmessage = $messagestr;
    $checkmessage =~ s/\x1c/\[1c\]/g;
    $checkmessage =~ s/\x1e/\[1e\]/g;
    $checkmessage =~ s/\x0d/\[0d\]/g;
    $logfilestr .= "\n$username $orderid\n";
    $logfilestr .= "$mytime send: $checkmessage  $shacardnumber\n";
    my $logData = { 'transcnt' => "$transcnt", 'username' => "$username", 'orderid' => "$orderid", 'mytime' => "$mytime", 'checkmessage' => "$checkmessage", 'shacardnumber' => "$shacardnumber", 'msg' => "$logfilestr" };
    writeServerLog( $username, $logData );
    $smessagestr{"$sequencenum"} = $checkmessage;

    if ( $timecheckfirstflag == 1 ) {
      $timecheckstart1    = time();
      $timecheckfirstflag = 0;
    }

    $timecheckend1   = time();
    $timecheckdelta1 = $timecheckend1 - $timecheckstart1;

    $getrespflag = 0;

    datalog({
      username => $username,
      orderId => $orderid,
      data => $logfilestr,
      message => sprintf('sending data for %s:%s to processor',$username,$orderid)
    });

    &socketwrite($message);

    $socketOpenTimecnt = 0;

    $writearray{$sequencenum} = $trans_time;

    if ( $transcnt >= 8 ) {
      last;
    }
  }

  if ( $transcnt > 0 ) {
    $numtrans = $transcnt;
    &socketread($transcnt);

    foreach $rsequencenum ( keys %susername ) {
      if ( $sstatus{"$rsequencenum"} ne "done" ) {
        $sretries{"$rsequencenum"}++;
        if ( $sretries{"$rsequencenum"} > 2 ) {
          delete $susername{$rsequencenum};
          delete $strans_time{$rsequencenum};
          delete $smessage{$rsequencenum};
          delete $smessagestr{$rsequencenum};
          delete $sretries{$rsequencenum};
          delete $sorderid{$rsequencenum};
          delete $sinvoicenum{$rsequencenum};
        }
      }
    }
  }
}

sub socketopen {
  my ( $addr, $port ) = @_;
  ( $iaddr, $paddr, $proto, $line, $response );

  $mytime     = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime socketopen attempt $addr $port\n";
  my $logData = { 'mytime' => "$mytime", 'addr' => "$addr", 'port' => "$port", 'msg' => "$logfilestr" };
  writeServerLog( $username, $logData );

  if ( $port =~ /\D/ ) { $port = getservbyname( $port, 'tcp' ) }
  die "No port" unless $port;
  $iaddr = inet_aton($addr) || die "no host: $addr";
  $paddr = sockaddr_in( $port, $iaddr );

  $proto = getprotobyname('tcp');

  socket( SOCK, PF_INET, SOCK_STREAM, $proto ) || die "socket: $!";
  my $printstr = "addr: $addr   port: $port\n";
  my $logData = { 'addr' => "$addr", 'port' => "$port", 'msg' => "$printstr" };
  writeDebug( $username, $logData );


  connect( SOCK, $paddr ) || die "connect: $!";
  my $printstr = "after connect\n";
  my $logData = { 'msg' => "$printstr" };
  writeDebug( $username, $logData );

  $socketopenflag = 1;
  $logfilestr     = "";
  $logfilestr .= "socketopen successful\n";
  my $logData = { 'msg' => "$logfilestr" };
  writeServerLog( $username, $logData );
}

sub socketwrite {
  my ($message) = @_;

  if ( $socketopenflag != 1 ) {
    my $printstr = "reopening socket\n";
    my $logData = { 'msg' => "$printstr" };
    writeDebug( $username, $logData );
    &checksecondary();
    &socketopen( "$ipaddress", "$port" );    # test server
  }

  $templen = length($message);
  my $printstr = "send: $templen $message";
  my $logData = { 'templen' => "$templen", 'message' => "$message", 'msg' => "$printstr" };
  writeDebug( $username, $logData );
  send( SOCK, $message, 0, $paddr );

}

sub socketread {
  ($numtries) = @_;

  $donereadingflag = 0;
  $logfilestr      = "";
  $logfilestr .= "socketread: $transcnt\n";
  my $printstr = "socketread: $transcnt\n";
  my $logData = { 'socketread' => "$transcnt", 'msg' => "$printstr" };
  writeDebug( $username, $logData );
  writeServerLog( $username, $logData );

  vec( $rin, $temp = fileno(SOCK), 1 ) = 1;
  $count    = $numtries + 2;
  $mlen     = length($message);
  $response = "";
  $respdata = "";
  while ( $count && select( $rout = $rin, undef, undef, 7.0 ) ) {
    $logfilestr = "";
    $logfilestr .= "while\n";
    my $printstr = "while\n";
    recv( SOCK, $response, 2048, 0 );
    $printstr .= "resp: $response\n";

    $respdata = $respdata . $response;

    $resplength = index( $respdata, "\x0d" );
    $resplength = $resplength + 1;

    $rlen       = length($respdata);
    $logfilestr .= "rlen: $rlen, resplength: $resplength\n";
    $printstr .= "rlen: $rlen, resplength: $resplength\n";

    my $logData = { 'rlen' => "$rlen", 'resplength' => "$resplength", 'response' => "$response", 'msg' => "$printstr" };
    writeDebug( $username, $logData );

    my $logData = { 'rlen' => "$rlen", 'resplength' => "$resplength", 'msg' => "$logfilestr" };
    writeServerLog( $username, $logData );

    while ( ( $rlen >= $resplength ) && ( $rlen > 0 ) ) {
      $nullresp = substr( $respdata, 0, 3 );
      if ( $nullresp ne "HO1" ) {
        $response     = substr( $respdata, 0, $resplength );
        $rsequencenum = substr( $response, 4, 22 );
        my $printstr = "rsequencenum: $rsequencenum\n";
        my $logData = { 'rsequencenum' => "$rsequencenum", 'msg' => "$printstr" };
        writeDebug( $username, $logData );
        if ( $susername{$rsequencenum} ne "" ) {
          $transcnt--;
          if ( $transcnt == 0 ) {
            $getrespflag = 1;
            $logfilestr  = "";
            $logfilestr .= "getrespflag = 1\n";
            my $logData = { 'getrespflag' => "$getrespflag", 'msg' => "$logfilestr" };
            writeServerLog( $username, $logData );
          }
          &updatepaytech();
          delete $writearray{$rsequencenum};
        }

        if ( !%writearray ) {
          $donereadingflag = 1;
        }
      } else {
        my $printstr = "keepalive\n";
        my $logData = { 'msg' => "$printstr" };
        writeDebug( $username, $logData );
        $keepalive = time();
        ( $d1, $d2, $newtime ) = &miscutils::genorderid();
        $newtime = substr( $newtime, 6, 8 );
        $nullmessage = "HI1" . substr( $response, 3, 8 ) . $newtime . "\x0d";
        &socketwrite($nullmessage);
        $mytime     = gmtime( time() );
        $logfilestr = "";
        $logfilestr .= "null message found $mytime\n\n";
        my $logData = { 'mytime' => "$mytime", 'msg' => "$logfilestr" };
        writeServerLog( $username, $logData );
        $getrespflag = 1;
      }
      $respdata = substr( $respdata, $resplength );

      $resplength = index( $respdata, "\x0d" );
      $resplength = $resplength + 1;
      $rlen       = length($respdata);
    }

    if ( $donereadingflag == 1 ) {
      $logfilestr = "";
      $logfilestr .= "donereadingflag = 1\n";
      my $logData = { 'donereadingflag' => "$donereadingflag", 'msg' => "$logfilestr" };
      writeServerLog( $username, $logData );

      datalog({
        username => $username,
        orderId => $orderid,
        data => $logfilestr,
        message => sprintf('received data for %s:%s from processor',$username,$orderid)
      });

      last;
    }

    $count--;
  }
  $logfilestr = "";
  $logfilestr .= "end loop $transcnt\n\n\n\n";
  my $logData = { 'transcnt' => "$transcnt", 'msg' => "$logfilestr" };
  writeServerLog( $username, $logData );
  $transcnt = 0;
}

sub updatepaytech {
  $rsequencenum = substr( $response, 4, 22 );

  my $printstr = "recv sequencenum: $rsequencenum, transcnt: $transcnt\n";
  my $logData = { 'rsequencenum' => "$rsequencenum", 'transcnt' => "$transcnt" };
  writeDebug($username, $logData);

  $mytime       = gmtime( time() );
  $checkmessage = $response;
  $checkmessage =~ s/\x1c/\[1c\]/g;
  $checkmessage =~ s/\x1e/\[1e\]/g;
  $checkmessage =~ s/\x0d/\[0d\]/g;
  $checkmessage =~ /[^0-9]([0-9]{15,16}) /g;
  $num = $1;
  $xs  = $num;
  $xs =~ s/[0-9]/x/g;
  $checkmessage =~ s/$num/$xs/;
  $logfilestr = "";
  $logfilestr .= "$mytime recv: $checkmessage\n";
  $printstr .= "recv: $checkmessage\n";

  $logData = { %{$logData}, 'checkmessage' => "$checkmessage", 'msg' => "$printstr" };
  writeDebug( $username, $logData );
  my $logData = { 'mytime' => "$mytime", 'checkmessage' => "$checkmessage", 'msg' => "$logfilestr" };
  writeServerLog( $username, $logData );

  if ( $timecheckfirstflag2 == 1 ) {
    $timecheckstart2     = time();
    $timecheckfirstflag2 = 0;
  }

  $sstatus{"$rsequencenum"} = "done";

  $processid = $sprocessid{"$rsequencenum"};

  my $transactionRequestId = $transactionRequestIdMap{$rsequencenum};
  delete($transactionRequestIdMap{$rsequencenum});

  my $pmsc = new PlugNPay::Processor::ProcessorMessageServiceClient(proc());
  my $request = $pmsc->newPostTransactionResultRequest();
  $request->setTransactionRequestId($transactionRequestId);

  my $mytime = gmtime( time() );
  $logfilestr = "";
  $logfilestr .= "$mytime snd success $checktime\n";
  my $logData = { 'mytime' => "$mytime", 'checktime' => "$checktime", 'msg' => "$logfilestr" };
  writeServerLog( $username, $logData );

  delete $susername{$rsequencenum};
  delete $strans_time{$rsequencenum};
  delete $smessage{$rsequencenum};
  delete $smessagestr{$rsequencenum};
  delete $sretries{$rsequencenum};
  delete $sorderid{$rsequencenum};
  delete $sprocessid{$rsequencenum};
  delete $sinvoicenum{$rsequencenum};

  $timecheckdelta2 = time() - $timecheckstart2;
}

sub checksecondary {
  if ( $test eq "yes" ) {

    $ipaddress = "206.253.180.137";    # test server
                                       #$port = "8535";                        # test server
    $port      = "8526";               # test server	# which one?
  } elsif ( -e "/home/pay1/batchfiles/logs/paytechsalem2/secondary.txt" ) {
    my @tmpfilestrarray = &procutils::flagread( "$username", "paytechsalem2", "/home/pay1/batchfiles/logs/paytechsalem2", "secondary.txt" );
    $secondary = $tmpfilestrarray[0];

    chop $secondary;

    $tmpfilestr = "";
    $tmpfilestr .= "secondary $secondary\n";
    my $logData = { 'secondary' => "$secondary" };
    writeDebug( $username, $logData );

    my $delta = time() - $manualswitchtime;
    if ( ( ( $secondary eq "1" ) && ( $ipaddress ne $ipaddress1 ) ) || ( ( $secondary eq "2" ) && ( $ipaddress ne $ipaddress2 ) ) ) {
      $mytime     = gmtime( time() );
      $tmpfilestr .= "$mytime switching to secondary socket $secondary\n";
      $logData = { %{$logData}, 'mytime' => "$mytime", 'secondary' => "$secondary" };
      writeServerLog( $username, $logData );

      close(SOCK);
      $socketopenflag = 0;
    }
    $logData = { %{$logData}, 'msg' => "$tmpfilestr" };
    writeServerLog( $username, $logData );

    if ( $secondary eq "1" ) {
      $ipaddress = $ipaddress1;
      $port      = $port1;
    } elsif ( $secondary eq "2" ) {
      $ipaddress = $ipaddress2;
      $port      = $port2;
    }
  } elsif ( !( -e "/home/pay1/batchfiles/logs/paytechsalem2/secondary.txt" ) && ( $ipaddress ne $primaryipaddress ) && ( $delta > 3600 ) ) {
    $mytime     = gmtime( time() );
    $logfilestr = "";
    $logfilestr .= "$mytime switching to primary socket\n";
    $logfilestr .= "$primaryipaddress  $primaryport\n";
    my $logData = { 'mytime' => "$mytime", 'primaryipaddress' => "$primaryipaddress", 'primaryport' => "$primaryport", 'msg' => "$logfilestr" };
    writeServerLog( $username, $logData );

    $ipaddress = $primaryipaddress;
    $port      = $primaryport;

    close(SOCK);
    $socketopenflag = 0;
  }
}

sub writeDebug {
  if ($ENV{'DEVELOPMENT'} ne 'TRUE') {
    return;
  }

  my $username = shift;
  my $data = shift;
  procutils::writeDataLog( $username, proc(), 'debug', $data );
}

sub writeServerLog {
  my $username = shift;
  my $data = shift;
  procutils::writeDataLog( $username, proc(), 'serverlogmsg', $data );
}

sub writeBatchfileLog {
  my $username = shift;
  my $data = shift;
  procutils::writeDataLog( $username, proc(), 'batchfile', $data );
}

sub datalog {
  my $data = shift;

  my $collection = 'paytechsalem2-server';

  my $logger = new PlugNPay::Logging::DataLog({ collection => $collection });
  $logger->log($data);
}