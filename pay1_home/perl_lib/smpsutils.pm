package smpsutils;

use strict;
use DBI;
use miscutils;
use rsautils;
use PlugNPay::Logging::MessageLog;
use PlugNPay::CreditCard;
use Sys::Hostname;
use PlugNPay::CardData;
use PlugNPay::Currency;
use PlugNPay::Transaction::Legacy::AdditionalProcessorData;
use PlugNPay::GatewayAccount;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::TransId;
use PlugNPay::Debug;

# caller should 
#     if ( ( $smps::processor =~ /^(planetpay|fifththird|testprocessor)$/ ) && ( $smps::feature{'multicurrency'} == 1 ) ) {
#     } else {
#        use price
#     }
sub calculateNativeAmountFromAuthCodeColumnData {
  my $input = shift;
use Data::Dumper; debug Dumper($input);
  my $processor = $input->{'processor'};
  my $authCodeColumnData = $input->{'authCodeColumnData'};
  my $nativeCurrency = $input->{'nativeCurrency'};
  my $convertedAmount = $input->{'convertedAmount'};

  my $conversionRate = conversionRateFromAuthCodeColumnData($input);

  my $nativeAmountUnformatted = ($convertedAmount * $conversionRate) + .00001;
  my $nativeAmountFormatted = new PlugNPay::Currency($nativeCurrency)->format( $nativeAmountUnformatted , { digitSeparator => '' } );

  return $nativeAmountFormatted;
}

sub conversionRateFromAuthCodeColumnData {
  my $input = shift;
use Data::Dumper; debug Dumper($input);
  my $processor = $input->{'processor'};
  my $authCodeColumnData = $input->{'authCodeColumnData'};

  my $processorData = new PlugNPay::Processor({ shortName => $processor });
  my $processorId = $processorData->getID();

  my $apd = new PlugNPay::Transaction::Legacy::AdditionalProcessorData({ processorId => $processorId });

  $apd->setAdditionalDataString($authCodeColumnData);

  if (!$apd->hasField('dccinfo')) {
    return '';
  }

  my $dccinfo = $apd->getField('dccinfo');

  my ($conversionRate, $orderOfMagnitude);
  if ( $dccinfo =~ /\,/ ) {
    my @dccData = split( /\,/, $dccinfo );
    $conversionRate = $dccData[3];
    $orderOfMagnitude = $dccData[4];
  } else {
    $conversionRate = substr( $dccinfo, 16, 10 ) + 0;
    $orderOfMagnitude  = substr( $dccinfo, 26, 1 );
  }

  $conversionRate = ( $conversionRate / ( 10**$orderOfMagnitude ) );

  if ($conversionRate == 0) {
    $conversionRate = 1;
  }

  return $conversionRate;
}

sub storecardnumber {
  my ( $username, $orderidOrCustomer, $processor, $enccardnumber, $storetype ) = @_;

  if ( $username eq "" ) {
    die "username is required to store card data";
  } 
  
  if ( $orderidOrCustomer eq "" ) {
    die "orderid or customer is required to store card data";
  }
  
  if ( $enccardnumber eq "" ) {
    return "";
  }

  my $cd = new PlugNPay::CardData();

  my $status = "";
  my $evalError;

  # store rec or order id 
  if ( $storetype eq "rec" ) {
    eval {
      $status = $cd->insertRecurringCardData( { username => $username, customer => $orderidOrCustomer, cardData => $enccardnumber } );
    };
    $evalError = $@;
  } else {
    eval {
      $status = $cd->insertOrderCardData( { orderID => $orderidOrCustomer, username => $username, cardData => $enccardnumber } );
    };
    $evalError = $@;
  }

  if ( $status ne "success" ) {
    my $msg = length($enccardnumber);

    my $mytime = gmtime( time() );
    open( LOGFILE, ">>/home/pay1/batchfiles/logs/cardnumissue.txt" );
    print LOGFILE "$mytime  $processor $username $orderidOrCustomer  store  $msg  $status\n";
    close(LOGFILE);

    my $logger = new PlugNPay::Logging::DataLog( { collection => 'smpsutils' } );

    my $logData = {
      processor => $processor,
      username  => $username,
      orderId   => $orderidOrCustomer,
      message   => 'Failed to store card data in card data service.',
      error     => $evalError
    };

    my $logOptions = { stackTraceEnabled => 1 };

    $logger->log( $logData, $logOptions );
  }

  return "";
}

sub getcardnumber {
  my ( $username, $orderidOrCustomer, $processor, $enccardnumber, $storetype, $options ) = @_;

  # for recurring   username is the table    orderid is the row in the table

  # return input enccardnumber  if username orderid or enccardnumber are empty
  if ( ( $username eq "" ) || ( $orderidOrCustomer eq "" ) ) {
    my $mytime = gmtime( time() );
    open( LOGFILE, ">>/home/pay1/batchfiles/logs/cardnumissue.txt" );
    print LOGFILE "$mytime  $processor $username $orderidOrCustomer  get\n";
    close(LOGFILE);

    # log data with datalog
    my $logger = new PlugNPay::Logging::DataLog( { collection => 'smpsutils' } );

    my $logData = {
      processor  => $processor,
      username   => $username,
      orderId    => $orderidOrCustomer,
      message    => sprintf( 'getcardnumber called without %s', ( $username ? 'orderId' : 'username' ) ),
      suggestion => 'Refactor this because returning enccardnumber in this case implies a bigger problem.  See stack trace.'
    };

    my $logOptions = { stackTraceEnabled => 1 };

    $logger->log( $logData, $logOptions );

    die "username and (orderid or customer) are required";
  }

  my $cd = new PlugNPay::CardData();

  my $evalError;

  my $enccardnumber = '';

  if ( $storetype eq "rec" ) {
    eval {
      $enccardnumber = $cd->getRecurringCardData( { username => $username, customer => $orderidOrCustomer, suppressAlert => $options->{'suppressAlert'} } );
    };
    $evalError = $@;
  } else {
    eval {
      $enccardnumber = $cd->getOrderCardData( { orderID => $orderidOrCustomer, username => $username, suppressAlert => $options->{'suppressAlert'} } );
    };
    $evalError = $@;
  }

  # check for errors
  if ( $evalError ne '' ) {
    # data error

    my $msg    = "";
    my $newmsg = "";

    my $mytime = gmtime( time() );
    open( LOGFILE, ">>/home/pay1/batchfiles/logs/cardnumissue.txt" );
    print LOGFILE "$mytime  $processor $username $orderidOrCustomer  get  $evalError\n";
    close(LOGFILE);

    # log error
    my $logger = new PlugNPay::Logging::DataLog( { collection => 'smpsutils' } );

    my $logData = {
      processor => $processor,
      username  => $username,
      orderId   => $orderidOrCustomer,
      message   => 'Failed to read card data from card data service.',
      error     => $evalError
    };

    my $logOptions = { stackTraceEnabled => 1 };

    $logger->log( $logData, $logOptions );
  }
  

  return $enccardnumber;
}

sub queryOld {
  my $input = shift;

  my ( $username, $operation, %datainfo );
  my $options = {};
  if ( ref($input) eq 'HASH' ) {
    $username  = $input->{'username'};
    $operation = $input->{'operation'};
    %datainfo  = %{ $input->{'query'} || {} };
    $options   = $input->{'options'} || {};
  } else {
    $username  = $input;
    $operation = shift;
    %datainfo  = @_;
  }

  my ($orderidold);
  my ( $card_number, $card_exp,   $amount );
  my ( $trans_date,  $trans_time, $trans_type, $auth_code, $batchfile, $result, $starttransdate );
  my ( $avs_code,    $cvvresp,    $enccardnumber, $length, $merchant, $ipaddress, $orderid );

  #my ($acct_code2,$acct_code3,$acct_code4);
  my ( $card_addr, $card_city, $card_state, $card_zip, $card_country, $card_company, $cardextra, $processor );
  my ( $processor, $proc_type, $shacardnumber, $chkprocessor );
  my $descr;
  my $batch_time;
  my $transflags;

  my $lowamount   = $datainfo{'low-amount'};
  my $highamount  = $datainfo{'high-amount'};
  my $srchorderid = $datainfo{'order-id'};
  my $cardnumber  = $datainfo{'cardnumber'};
  my $status      = $datainfo{'txn-status'};
  my $txntype     = $datainfo{'txn-type'};
  my $cardtype    = $datainfo{'card-type'};
  my $accttype    = $datainfo{'accttype'};
  my $batchid     = $datainfo{'batch-id'};
  my $refnumber   = $datainfo{'refnumber'};

  my $starttime = $datainfo{'start-time'};
  my $endtime   = $datainfo{'end-time'};

  my $acct_code  = $datainfo{'acct_code'};
  my $acct_code2 = $datainfo{'acct_code2'};
  my $acct_code3 = $datainfo{'acct_code3'};
  my $acct_code4 = $datainfo{'acct_code4'};
  my $card_name  = $datainfo{'card-name'};
  $card_name =~ tr/a-z/A-Z/;

  my $subacct = $ENV{'SUBACCT'};

  my $decryptflag = $datainfo{'decrypt'};

  my $partial = $datainfo{'partial'};

  my $linked_accts = $datainfo{'linked_accts'};
  my $fuzzyun      = $datainfo{'fuzzyun'};

  my ( $d1, $d2, $hint );

  if ( $starttime < "20130101000000" ) {
    $starttime = "20130101000000";
  }
  my $startdate = substr( $starttime, 0, 8 );

  my $batchtime = $datainfo{'batch-time'};
  if ( $batchtime ne "" ) {
    if ( $batchtime < $starttime ) {
      $batchtime = $starttime;
    }
    $startdate = substr( $batchtime, 0, 8 );
  }

  if ( $endtime < 20130101000000 ) {
    ( $d1, $d2, $endtime ) = &miscutils::gendatetime();
  }

  my $enddate = substr( $endtime, 0, 8 );

  if ( $decryptflag eq "yes" ) {
    my ($cardflag);
    if ( $cardnumber ne "" ) {
      $cardflag = "yes";
    }

#my %logdata = ('LOGTYPE' => 'CARDQUERY','username' => $username, 'login' => $ENV{'LOGIN'}, 'remote_user' => $ENV{'REMOTE_USER'}, 'ipaddress' => $ENV{'REMOTE_ADDR'}, 'scriptname' => $ENV{'SCRIPT_NAME'}, 'PID' => $$);
#my $logger = new PlugNPay::Logging::MessageLog();
#$logger->logMessage(\%logdata);
  }

  my %result         = ();
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $processor      = $gatewayAccount->getCardProcessor();
  my $proc_type      = $gatewayAccount->getProcessingType();
  my $chkprocessor   = $gatewayAccount->getCheckProcessor();

  if ( ( $operation eq "batch-prep" ) && ( $proc_type eq "authcapture" ) ) {
    return;
  }

  # xxxx 04/11/2007
  my $nooidflag = 0;
  if ( $srchorderid eq "" ) {
    $nooidflag = 1;
  }

  my $searchstr    = "";
  my @executeArray = ();
  my $dateArrayRef = "";
  my $qmarks       = "";

  if ( $options->{'forcePrimary'} || $nooidflag != 1 ) {
    $hint      = "force index(PRIMARY)";
    $searchstr = q/
    select 
      orderid,
      refnumber,
      card_name,
      card_number,
      card_exp,
      amount,
      trans_date,
      trans_time,
      trans_type,
      auth_code,
      result,
      finalstatus,
      operation,
      avs,
      cvvresp,
      enccardnumber,
      length,
      acct_code,
      acct_code2,
      acct_code3,
      acct_code4,
      card_addr,
      card_city,
      card_state,
      card_zip,
      card_country,
      batch_time,
      transflags,
      descr,
      username,
      ipaddress,
      cardextra,
      processor
    /;
  } else {
    $hint      = "force index(tlog_tdateuname_idx)";
    $searchstr = q/
    select 
      orderid,
      refnumber,
      card_name,
      card_number,
      card_exp,
      amount,
      trans_date,
      trans_time,
      trans_type,
      auth_code,
      result,
      finalstatus,
      operation,
      avs,
      cvvresp,
      enccardnumber,
      length,
      acct_code,
      acct_code2,
      acct_code3,
      acct_code4,
      batch_time,
      transflags,
      descr,
      card_country,
      username,
      ipaddress,
      cardextra,
      processor
    /;
  }

  $searchstr .= " from trans_log $hint";

  my $op = "where";
  if ( $srchorderid ne "" ) {

    #push (@executeArray, $orderid);
    $searchstr .= " $op orderid = ?";
    $op = "and";
  }

  #if (($startdate ne "") && ($orderid eq "")) {

  if ( $startdate ne "" ) {
    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
    my $twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
    if ( $startdate < 19980101 ) {
      $startdate = $twomonthsago;
    }

    my $earliest_date = "20040101";
    if ( ( -e "/home/p/pay1/outagefiles/mediumvolume.txt" ) || ( -e "/home/p/pay1/outagefiles/highvolume.txt" ) ) {
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 2 ) );
      $earliest_date = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

      if ( $startdate < $earliest_date ) {
        $startdate = $earliest_date;
      }
    }

    if ( length($starttime) != 14 ) {
      $starttime .= "000000";
    }

    my $starttranstime = &miscutils::strtotime($startdate);
    if ( $starttranstime eq "" ) {
      $starttranstime = &miscutils::strtotime( $twomonthsago . "000000" );
    }
    my ($newtime);
    if ( ( $operation eq "batchquery" ) && ( $chkprocessor eq "selectcheck" ) && ( $datainfo{'accttype'} eq "checking" ) ) {
      $newtime = $starttranstime - ( 3600 * 24 * 21 );
    } elsif ( ( $operation eq "batchquery" ) && ( $chkprocessor eq "paymentdata" ) && ( $datainfo{'accttype'} eq "checking" ) ) {
      $newtime = $starttranstime - ( 3600 * 24 * 14 );
    } else {
      $newtime = $starttranstime - ( 3600 * 24 * 7 );
    }

    $starttransdate = &miscutils::timetostr($newtime);
    $starttransdate = substr( $starttransdate, 0, 8 );

    my $inclusiveDateFlag = 0;
    if ( substr( $endtime, 8 ) > 0 ) {
      $inclusiveDateFlag = 1;
    }

    if ( $starttransdate < 20160901 ) {
      $starttransdate = "20160901";
    }

    ( $qmarks, $dateArrayRef ) = &miscutils::dateIn( $starttransdate, $enddate, $inclusiveDateFlag );

    $searchstr .= " $op trans_date IN (PLACEHOLDER) ";
    $op = "and";

    #push (@executeArray, @$dateArray);
  }

  if ( $linked_accts ne "" ) {
    $linked_accts =~ s/[^0-9a-z\,]//g;
    my @linked_accts = split( /\,/, $linked_accts );
    my $qmarks = '?,' x @linked_accts;
    chop $qmarks;
    push( @executeArray, @linked_accts );
    $searchstr .= " and username IN ($qmarks) ";
  } elsif ( $fuzzyun ne "" ) {
    $searchstr .= " and username LIKE ? ";
    push( @executeArray, "$fuzzyun%" );
  } else {
    $searchstr .= " and username=?";
    push( @executeArray, $username );
  }

  if ( $batchtime ne "" ) {
    $searchstr .= " and batch_time>=?";
    push( @executeArray, $batchtime );
  } else {
    $searchstr .= " and trans_time>=?";
    push( @executeArray, $starttime );
  }

  $searchstr .= " and trans_time<?";
  push( @executeArray, $endtime );

  if ( $batchid ne "" ) {
    $searchstr .= " and result=?";
    push( @executeArray, $batchid );
  }

  if ( $refnumber ne "" ) {
    $searchstr .= " and refnumber like ?";
    push( @executeArray, "$refnumber%" );
  }

  if ( $subacct ne "" ) {
    $searchstr .= " and subacct=?";
    push( @executeArray, $subacct );
  }

  if ( $lowamount ne "" ) {
    $searchstr .= " and cast(substr(amount,5) AS DECIMAL(10,2))>=?";
    push( @executeArray, $lowamount );
  }
  if ( $highamount ne "" ) {
    $searchstr .= " and cast(substr(amount,5) AS DECIMAL(10,2))<=?";
    push( @executeArray, $highamount );
  }

  my @acctCodes = ( 'acct_code', 'acct_code2', 'acct_code3', 'acct_code4' );
  foreach my $var (@acctCodes) {
    if ( $datainfo{$var} ne "" ) {
      if ( $partial == 1 ) {
        $searchstr .= " and $var like ?";
        push( @executeArray, "%$datainfo{$var}%" );
      } else {
        $searchstr .= " and $var = ?";
        push( @executeArray, "$datainfo{$var}" );
      }
    }
  }

  if ( $card_name ne "" ) {
    $searchstr .= " and upper(card_name) like ?";
    push( @executeArray, $card_name );
  }

  if ( $cardtype ne "" ) {
    if ( $cardtype eq "vs" ) {
      $searchstr .= " and card_number like ?";
      push( @executeArray, "4%" );
    } elsif ( $cardtype eq "mc" ) {
      $searchstr .= " and card_number like ?";
      push( @executeArray, "5%" );
    } elsif ( $cardtype eq "ds" ) {
      $searchstr .= " and (card_number like ? or card_number like ?)";
      push( @executeArray, "6011%", "65%" );
    } elsif ( $cardtype eq "ax" ) {
      $searchstr .= " and (card_number like ? or card_number like ?)";
      push( @executeArray, "34%", "37%" );
    } elsif ( ( $cardtype eq "dc" ) || ( $cardtype eq "cb" ) ) {
      $searchstr .= " and (card_number like ? or card_number like ? or card_number like ?)";
      push( @executeArray, "30%", "36%", "38%" );
    } elsif ( $cardtype eq "jc" ) {
      $searchstr .= " and (card_number like ? or card_number like ? or card_number like ? or card_number like ? or card_number like ? or card_number like ?)";
      push( @executeArray, "3088%", "3096%", "3112%", "3158%", "3337%", "35%" );
    } elsif ( $cardtype eq "kc" ) {
      $searchstr .= " and (card_number like ? or card_number like ? or card_number like ?)";
      push( @executeArray, "7775%", "7776%", "7777%" );
    } elsif ( $cardtype eq "ma" ) {
      $searchstr .= " and card_number like ?";
      push( @executeArray, "6759%" );
    } elsif ( $cardtype eq "sw" ) {
      $searchstr .= " and card_number like ?";
      push( @executeArray, "6767%" );
    }
  }

  if ( $status ne "" ) {
    if ( $status eq "sap" ) {
      $searchstr .= " and finalstatus IN (?,?,?)";
      push( @executeArray, 'success', 'pending', 'locked' );
    } elsif ( $status eq "failure" ) {
      $searchstr .= " and finalstatus IN (?,?)";
      push( @executeArray, 'badcard', 'problem' );
    } elsif ( $status eq "pending" ) {
      $searchstr .= " and finalstatus IN (?,?)";
      push( @executeArray, 'pending', 'locked' );
    } else {
      $searchstr .= " and finalstatus=?";
      push( @executeArray, $status );
    }
  }

  if ( $txntype ne "" ) {
    if ( $txntype =~ /^(auth|capture)$/ ) {
      $searchstr .= " and operation='auth'";
    } elsif ( $txntype eq "anm" ) {
      my $earliest_date = "20130101";
      if ( ( -e "/home/p/pay1/outagefiles/mediumvolume.txt" ) || ( -e "/home/p/pay1/outagefiles/highvolume.txt" ) ) {
        my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 2 ) );
        $earliest_date = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

        if ( $startdate < $earliest_date ) {
          $startdate = $earliest_date;
        }
      }

      $searchstr .= " and operation in (?,?,?) and finalstatus in (?,?) ";
      push( @executeArray, 'auth', 'void', 'postauth', 'success', 'pending' );
    } elsif ( $txntype eq "marked" ) {
      $searchstr .= " and operation=?";
      push( @executeArray, 'postauth' );
    } elsif ( $txntype =~ /(return|markret)/ ) {
      $searchstr .= " and operation=?";
      push( @executeArray, 'return' );
    } elsif ( ( $accttype eq "checking" ) && ( $txntype eq "settled" ) ) {
      $searchstr .= " and operation=?";
      push( @executeArray, 'postauth' );
    } elsif ( $txntype eq "settled" ) {
      $searchstr .= " and operation=? and finalstatus=?";
      push( @executeArray, 'postauth', 'success' );
    } elsif ( $txntype eq "setlret" ) {
      $searchstr .= " and operation=? and finalstatus=?";
      push( @executeArray, 'return', 'success' );
    } elsif ( ( $accttype eq "checking" ) && ( $txntype eq "batch" ) && ( $operation eq "batchquery" ) ) {
      $searchstr .= " and operation in (?,?,?)";
      push( @executeArray, 'postauth', 'return', 'chargeback' );
    } elsif ( ( $accttype eq "checking" ) && ( $txntype eq "batch" ) ) {
      $searchstr .= " and operation in (?,?)";
      push( @executeArray, 'postauth', 'return' );
    } elsif ( $txntype eq "batch" ) {
      $searchstr .= " and operation in (?,?) and finalstatus=?";
      push( @executeArray, 'postauth', 'return', 'success' );
    } elsif ( $txntype =~ /void/ ) {
      $searchstr .= " and operation=? and finalstatus=?";
      push( @executeArray, 'void', 'success' );
    } elsif ( $txntype eq "forceauth" ) {
      $searchstr .= " and operation=?";
      push( @executeArray, 'forceauth' );
    } elsif ( ( $accttype eq "checking" ) && ( $txntype eq "chargeback" ) ) {
      $searchstr .= " and operation =?";
      push( @executeArray, 'chargeback' );
    }
  }

  if ( $cardnumber ne "" ) {
    my $cc         = new PlugNPay::CreditCard($cardnumber);
    my @cardHashes = $cc->getCardHashArray();
    my $qmarks     = '?,' x @cardHashes;
    chop $qmarks;
    $searchstr .= " and shacardnumber IN ($qmarks)  ";
    push( @executeArray, @cardHashes );
  }

  if ( $accttype =~ /^(checking|savings)$/ ) {
    $searchstr .= " and accttype in (?,?)";
    push( @executeArray, 'checking', 'savings' );
  } elsif ( $accttype =~ /^(seqr)$/ ) {
    $searchstr .= " and accttype=? ";
    push( @executeArray, $accttype );
  } else {
    $searchstr .= " and (accttype is NULL or accttype='' or accttype='credit')";
  }

  if ( $options->{'no-capture'} ) {
    $searchstr .= ' and transflags not like ? ';
    push @executeArray, '%capture%';
  }

  $searchstr .= " and (duplicate IS NULL or duplicate='')";
  $searchstr .= " and operation NOT IN (?,?,?,?) order by orderid,trans_time";

  push( @executeArray, 'query', 'batch-prep', 'batchquery', 'batchdetails' );

  my $origoperation = $operation;
  if ( $origoperation eq "batch-prep" ) {
    @executeArray = ();
    ## For Mysql
    my $hint = "force index(tlog_tdateuname_idx)";

    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 ) );
    my $twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

    $searchstr =
      "select orderid,refnumber,card_name,card_number,card_exp,amount,trans_date,trans_time,trans_type,auth_code,result,finalstatus,operation,avs,cvvresp,enccardnumber,length,acct_code,acct_code2,acct_code3,acct_code4,batch_time,transflags,descr,card_country,username,ipaddress,cardextra";

    $searchstr .= " from trans_log $hint ";

    my $earliest_date = "20040101";
    if ( ( -e "/home/p/pay1/outagefiles/mediumvolume.txt" ) || ( -e "/home/p/pay1/outagefiles/highvolume.txt" ) ) {
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 2 ) );
      $earliest_date = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
    }

    if ( $datainfo{'start-time'} eq "" ) {
      if ( $twomonthsago > $earliest_date ) {
        $startdate = $twomonthsago;
      } else {
        $startdate = $earliest_date;
      }
    } else {
      $startdate = substr( $datainfo{'start-time'}, 0, 8 );
      if ( $startdate < $earliest_date ) {
        $startdate = $earliest_date;
      }
    }

    my ($endate) = &miscutils::gendatetime_only();

    ( $qmarks, $dateArrayRef ) = &miscutils::dateIn( $startdate, $enddate, '1' );
    $searchstr .= " where trans_date IN (PLACEHOLDER)";

    $searchstr .= " and username=?";
    push( @executeArray, $username );

    if ( $subacct ne "" ) {
      $searchstr .= " and subacct=?";
      push( @executeArray, $subacct );
    }
    if ( $acct_code ne "" ) {
      $searchstr .= " and acct_code=?";
      push( @executeArray, $acct_code );
    }

    $searchstr .= " and operation IN (?,?,?,?,?,?,?)";
    push( @executeArray, 'auth', 'postauth', 'return', 'void', 'reauth', 'retry', 'forceauth' );

    if ( $accttype =~ /^(checking|savings)$/ ) {
      $searchstr .= " and accttype in (?,?)";
      push( @executeArray, 'checking', 'savings' );
    } else {
      $searchstr .= " and (accttype is NULL or accttype='' or accttype='credit')";
    }

    if ( $options->{'no-capture'} ) {
      $searchstr .= ' and transflags not like ? ';
      push @executeArray, '%capture%';
    }

    $searchstr .= " and (duplicate IS NULL or duplicate='')";

    # BUG 20220420-00001
    # if trans time for reauth and postauth are equivilent (within same second)
    # then this will return the results in the incorrect order, resulting in
    # /admin/smps showing transactions that have already to be marked as ready
    # to be marked.
    # possible solutions:
    # 1) change `operation DESC` to `FIELD(operation,'auth','reauth','postauth') DESC` (untested)
    # 2) inrcreasing granularity of timestamps to include milliseconds or nanoseconds (non-trivial, schema change, code changes)
    # 3) looping over operation in a specific order in the perl code (similar to #1, likely slower but potentially more control)
    $searchstr .= " order by orderid,trans_time DESC,operation DESC ";
  }

  my $qstr = $searchstr;
  $qstr =~ s/PLACEHOLDER/$qmarks/;

  my @array = ();
  if ( $nooidflag != 1 ) {
    @array = ($srchorderid);
  }
  push( @array, @$dateArrayRef, @executeArray );

  if ( -e "/home/p/pay1/outagefiles/log_smpsutils.txt" ) {
    my $datetime = gmtime( time() );
    open( DEBUG, ">>/home/p/pay1/database/debug/smpsutils_queries.txt" );
    print DEBUG "DATE:$datetime, UN:$username, SN:$ENV{'SCRIPT_NAME'}, NOOIDFLG:$nooidflag, FUZZY:$fuzzyun, LINKED:$linked_accts, PID:$$, LINE:396, SRCHSTR:$qstr\n";
    foreach my $var (@array) {
      print DEBUG "$var, ";
    }
    print DEBUG "\n\n";
    close(DEBUG);

    #use Datalog
    my %sdata = ();
    $sdata{DATE}     = $datetime;
    $sdata{UN}       = $smps::username;
    $sdata{SN}       = $ENV{'SCRIPT_NAME'};
    $sdata{NOOIDFLG} = $nooidflag;
    $sdata{FUZZY}    = $fuzzyun;
    $sdata{LINKED}   = $linked_accts;
    $sdata{PID}      = $$;
    $sdata{SRCHSTR}  = $qstr;

    foreach my $var (@array) {
      print DEBUG "$var, ";
      $sdata{$var} = $var;
    }

    my $logger = new PlugNPay::Logging::DataLog( { collection => 'smpsutils_queries' } );
    $logger->log( \%sdata );
  }

  my $dbh1 = &miscutils::dbhconnect( "pnpdata", "", "$username" );

  my $sth1 = $dbh1->prepare($qstr) or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth1->execute(@array) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );

  my $array1 = $sth1->fetchall_arrayref( {} );
  $sth1->finish;

  my @dataArray = ();

  push( @dataArray, @{$array1} );
  my $i = 1;
  my (%anm_delete);
  foreach my $data (@dataArray) {
    ( $orderid, $refnumber, $card_name, $card_number, $card_exp, $amount, $trans_date ) =
      ( $data->{'orderid'}, $data->{'refnumber'}, $data->{'card_name'}, $data->{'card_number'}, $data->{'card_exp'}, $data->{'amount'}, $data->{'trans_date'} );
    ( $trans_time, $trans_type, $auth_code, $batchfile ) = ( $data->{'trans_time'}, $data->{'trans_type'}, $data->{'auth_code'}, $data->{'result'} );
    ( $result, $operation, $avs_code, $cvvresp, $enccardnumber, $length ) =
      ( $data->{'finalstatus'}, $data->{'operation'}, $data->{'avs'}, $data->{'cvvresp'}, $data->{'enccardnumber'}, $data->{'length'} );
    ( $acct_code, $acct_code2, $acct_code3, $acct_code4, $card_addr, $card_city, $card_state ) =
      ( $data->{'acct_code'}, $data->{'acct_code2'}, $data->{'acct_code3'}, $data->{'acct_code4'}, $data->{'card_addr'}, $data->{'card_city'}, $data->{'card_state'} );
    ( $card_zip, $card_country, $batch_time, $transflags, $descr ) = ( $data->{'card_zip'}, $data->{'card_country'}, $data->{'batch_time'}, $data->{'transflags'}, $data->{'descr'} );
    ( $merchant, $ipaddress, $cardextra, $processor ) = ( $data->{'username'}, $data->{'ipaddress'}, $data->{'cardextra'}, $data->{'processor'} );

    # xxxx 10/27/1999
    if ( ( $origoperation eq "batch-prep" ) && ( $operation eq "auth" ) && ( $result ne "success" ) ) {
      next;
    }
    if ( ( $origoperation eq "batch-prep" ) && ( $result ne "success" ) ) {
      $orderidold = $orderid;
      next;
    }
    if ( ( $origoperation eq "batch-prep" ) && ( $transflags =~ /gift|avsonly|balance/ ) ) {
      $orderidold = $orderid;
      next;
    }

    if ( ( $txntype eq "anm" ) && ( $operation =~ /(postauth|void)/ ) ) {
      $anm_delete{$orderid} = 1;
      next;
    }
    my $decrypttrantime = &miscutils::strtotime($trans_date);
    my ($sixmonthsago);
    if ( $username =~ /^(initaly)$/ ) {
      $sixmonthsago = time() - ( 365 * 24 * 3600 );
    } else {
      $sixmonthsago = time() - ( 365 * 24 * 3600 );    ###  DCP extended query time to go back for 1 year.  20070607
    }

    if ( $decrypttrantime < $sixmonthsago ) {
      $decryptflag = "no";
    }

    # THE FOLLOWING CONTAINS SOME CODE THAT IS INTENTIONALLY COMMENTED OUT AND LEFT HERE
    # The map $result does not/should not contain these keys.  If for some reason they need
    # to be re-added, leaving the code here for a few releases would make switching back simpler.
    if ( ( $length > 0 ) && ( $length <= 1024 ) && ( $origoperation ne "batch-prep" ) && ( $operation =~ /^(forceauth|auth|postauth|return|storedata)$/ ) ) {
      if ( ( $ENV{'SEC_LEVEL'} < 7 ) && ( $decryptflag eq "yes" ) ) {
        $card_number = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
      }

      #   else {
      #     #print "REMOTEUSR:$ENV{'REMOTE_USER'}, LOGIN:$ENV{'LOGIN'}, SUB:$ENV{'SUBACCT'}, SEC LEV:$ENV{'SEC_LEVEL'}<br>\n";
      #   }
      #   $result{'card-number'} = $card_number;

      #   if (length($result{'card-number'}) > 60) {
      #     $result{'card-number'} = "";
      #   }

      # }
      # else {
      #   $result{'card-number'} = "";
      # }

      # if ($auth_code ne "") {
      #   $result{'auth-code'} = $auth_code;
      # }
      # if ($avs_code ne "") {
      #   $result{'avs-code'} = $avs_code;
      # }
      # if ($cvvresp ne "") {
      #   $result{'cvvresp'} = $cvvresp;
      # }
      # if ($card_exp ne "") {
      #   $result{'card-exp'} = $card_exp;
    }

    my $shortcard = substr( $card_number, 0, 4 );
    my $card_type = "";

    if ( ( $shortcard >= 4000 ) && ( $shortcard <= 4999 ) ) {
      $card_type = "vs";    # visa
    } elsif ( ( $shortcard >= 5000 ) && ( $shortcard <= 5999 ) ) {
      $card_type = "mc";    # mastercard
    } elsif ( ( $shortcard >= 2221 ) && ( $shortcard <= 2720 ) ) {
      $card_type = "mc";    # mastercard
    } elsif ( ( ( $shortcard >= 3400 ) && ( $shortcard <= 3499 ) )
      || ( ( $shortcard >= 3700 ) && ( $shortcard <= 3799 ) ) ) {
      $card_type = "ax";    # amex
    } elsif ( ( $shortcard == 6011 ) || ( $shortcard =~ /^65/ ) ) {
      $card_type = "ds";    # discover
    } elsif ( ( $shortcard >= 3930 ) && ( $shortcard <= 3949 ) ) {
      $card_type = "cb";    # diners
    } elsif ( ( ( $shortcard >= 3000 ) && ( $shortcard <= 3059 ) )
      || ( ( $shortcard >= 3600 ) && ( $shortcard <= 3699 ) )
      || ( ( $shortcard >= 3800 ) && ( $shortcard <= 3899 ) ) ) {
      $card_type = "dc";
    } elsif ( ( ( $shortcard >= 3083 ) && ( $shortcard <= 3329 ) )
      || ( ( $shortcard >= 3528 ) && ( $shortcard <= 3589 ) ) ) {
      $card_type = "jc";
    } elsif ( $shortcard =~ /^(7775|7776|7777)/ ) {
      $card_type = 'kc';    # keycard
    } elsif ( $shortcard =~ /^(6767)/ ) {
      $card_type = 'sw';    # solo
    } elsif ( $shortcard =~ /^(6759)/ ) {
      $card_type = 'ma';    # maestro, switch is now maestro
    } elsif ( $shortcard =~ /^(8)/ ) {
      $card_type = "pl";    # pnp private label
    } elsif ( $shortcard =~ /^(9)/ ) {
      $card_type = "sv";    # pnp stored value
    }

    if ( $transflags =~ /milstar/ ) {
      $card_type = "ms";
    }

    $card_company = "";
    if ( $origoperation ne "batch-prep" ) {
      $result{"a$i"} =
        "order-id=$orderid\&time=$trans_time\&merch-txn=$refnumber\&card-number=$card_number\&card-exp=$card_exp\&amount=$amount\&txn-type=$operation\&auth-code=$auth_code\&avs-code=$avs_code\&cvvresp=$cvvresp\&txn-status=$result\&card-type=$card_type\&operation=$operation\&card-name=$card_name\&acct_code=$acct_code\&acct_code2=$acct_code2\&acct_code3=$acct_code3\&acct_code4=$acct_code4\&batch-id=$batchfile\&card-addr=$card_addr\&card-city=$card_city\&card-state=$card_state\&card-zip=$card_zip\&card-country=$card_country\&batch_time=$batch_time\&transflags=$transflags\&descr=$descr\&card-company=$card_company\&username=$merchant\&ipaddress=$ipaddress\&cardextra=$cardextra";
      $i++;
    } elsif ( ( $origoperation eq "batch-prep" )
      && ( ( $operation eq "auth" ) || ( $operation eq "reauth" ) || ( $operation eq "forceauth" ) )
      && ( $orderid ne $orderidold )
      && ( $result eq "success" )
      && ( ( $datainfo{'card-type'} eq "" ) || ( $datainfo{'card-type'} eq $card_type ) ) ) {

      $result{"a$i"} =
        "time=$trans_time\&order-id=$orderid\&merch-txn=$refnumber\&card-number=$card_number\&card-exp=$card_exp\&amount=$amount\&txn-type=$operation\&auth-code=$auth_code\&avs-code=$avs_code\&cvvresp=$cvvresp\&txn-status=$result\&card-type=$card_type\&operation=$operation\&card-name=$card_name\&acct_code=$acct_code\&acct_code2=$acct_code2\&acct_code3=$acct_code3\&acct_code4=$acct_code4\&card-addr=$card_addr\&card-city=$card_city\&card-state=$card_state\&card-zip=$card_zip\&card-country=$card_country\&batch_time=$batch_time\&transflags=$transflags";
      $i++;
      if ( ( $username =~ /^(achepenzio|achadvancec|achworldwi1|plugnpay)$/ ) && ( $i % 50 == 0 ) ) {
        print " ";
      }
    }
    $orderidold = $orderid;
  }

  if ( $txntype eq "anm" ) {
    foreach my $key ( keys %result ) {
      $result{$key} =~ /order\-id=(\d*)\&/;
      if ( exists $anm_delete{$1} ) {
        delete $result{$key};
      }
    }
  }

  return %result;
}

sub query {
  if ( -e '/home/pay1/etc/smpsutils/queryV2' ) {
    return queryV2(@_);
  }

  return queryOld(@_);
}

sub queryV2 {
  my $input = shift;

  my ( $username, $operation, %datainfo );
  my $options = {};
  if ( ref($input) eq 'HASH' ) {
    $username  = $input->{'username'};
    $operation = $input->{'operation'};
    %datainfo  = %{ $input->{'query'} || {} };
    $options   = $input->{'options'} || {};
  } else {
    $username  = $input;
    $operation = shift;
    %datainfo  = @_;
  }

  my ($orderidold);
  my ( $card_number, $card_exp,   $amount );
  my ( $trans_date,  $trans_time, $trans_type, $auth_code, $batchfile, $result, $starttransdate );
  my ( $avs_code,    $cvvresp,    $enccardnumber, $length, $merchant, $ipaddress, $orderid );

  #my ($acct_code2,$acct_code3,$acct_code4);
  my ( $card_addr, $card_city, $card_state, $card_zip, $card_country, $card_company, $cardextra, $processor );
  my ( $processor, $proc_type, $shacardnumber, $chkprocessor );
  my $descr;
  my $batch_time;
  my $transflags;

  my $lowamount   = $datainfo{'low-amount'};
  my $highamount  = $datainfo{'high-amount'};
  my $srchorderid = $datainfo{'order-id'};
  my $cardnumber  = $datainfo{'cardnumber'};
  my $status      = $datainfo{'txn-status'};
  my $txntype     = $datainfo{'txn-type'};
  my $cardtype    = $datainfo{'card-type'};
  my $accttype    = $datainfo{'accttype'};
  my $batchid     = $datainfo{'batch-id'};
  my $refnumber   = $datainfo{'refnumber'};
  my $starttime   = $datainfo{'start-time'};
  my $endtime     = $datainfo{'end-time'};

  my $acct_code  = $datainfo{'acct_code'};
  my $acct_code2 = $datainfo{'acct_code2'};
  my $acct_code3 = $datainfo{'acct_code3'};
  my $acct_code4 = $datainfo{'acct_code4'};
  my $card_name  = $datainfo{'card-name'};
  $card_name =~ tr/a-z/A-Z/;

  my $decryptflag = $datainfo{'decrypt'};

  my $partial = $datainfo{'partial'};

  my $linked_accts = $datainfo{'linked_accts'};
  my $fuzzyun      = $datainfo{'fuzzyun'};

  my ( $d1, $d2, $hint );

  if ( $starttime < "20130101000000" ) {
    $starttime = "20130101000000";
  }
  my $startdate = substr( $starttime, 0, 8 );

  my $batchtime = $datainfo{'batch-time'};
  if ( $batchtime ne "" ) {
    if ( $batchtime < $starttime ) {
      $batchtime = $starttime;
    }
    $startdate = substr( $batchtime, 0, 8 );
  }

  if ( $endtime < 20130101000000 ) {
    ( $d1, $d2, $endtime ) = &miscutils::gendatetime();
  }

  my $enddate = substr( $endtime, 0, 8 );

  if ( $decryptflag eq "yes" ) {
    my ($cardflag);
    if ( $cardnumber ne "" ) {
      $cardflag = "yes";
    }
  }

  my %result         = ();
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $processor      = $gatewayAccount->getCardProcessor();
  my $proc_type      = $gatewayAccount->getProcessingType();
  my $chkprocessor   = $gatewayAccount->getCheckProcessor();

  if ( ( $operation eq "batch-prep" ) && ( $proc_type eq "authcapture" ) ) {
    return;
  }

  # xxxx 04/11/2007
  my $nooidflag = 0;
  if ( $srchorderid eq "" ) {
    $nooidflag = 1;
  }

  my $searchstr    = "";
  my @executeArray = ();
  my $dateArrayRef = "";
  my $qmarks       = "";

  if ( $nooidflag == 1 ) {
    $hint = "force index(tlog_tdateuname_idx)";
  } else {
    $hint = "force index(PRIMARY)";
  }

  $searchstr = qq/
    SELECT 
      t.orderid as orderid,
      t.refnumber as refnumber,
      t.card_name as card_name,
      t.card_number as card_number,
      t.card_exp as card_exp,
      t.amount as amount,
      t.trans_date as trans_date,
      t.trans_time as trans_time,
      t.trans_type as trans_type,
      t.auth_code as auth_code,
      t.result as result,
      t.finalstatus as finalstatus,
      t.operation as operation,
      t.avs as avs,
      t.cvvresp as cvvresp,
      t.enccardnumber as enccardnumber,
      t.length as length,
      t.acct_code as acct_code,
      t.acct_code2 as acct_code2,
      t.acct_code3 as acct_code3,
      t.acct_code4 as acct_code4,
      t.card_addr as card_addr,
      t.card_city as card_city,
      t.card_state as card_state,
      t.card_zip as card_zip,
      t.card_country as card_country,
      t.batch_time as batch_time,
      t.transflags as transflags,
      t.descr as descr,
      t.username as username,
      t.ipaddress as ipaddress,
      t.cardextra as cardextra,
      t.processor as processor
    FROM trans_log t $hint, operation_log o FORCE INDEX (PRIMARY)
    WHERE t.orderid = o.orderid AND t.username = o.username
  /;

  if ( $srchorderid ne "" ) {
    $searchstr .= " AND t.orderid = ? ";
  }

  if ( $startdate ne "" ) {
    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 60 ) );
    my $twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
    if ( $startdate < 19980101 ) {
      $startdate = $twomonthsago;
    }

    my $earliest_date = "20040101";
    if ( ( -e "/home/p/pay1/outagefiles/mediumvolume.txt" ) || ( -e "/home/p/pay1/outagefiles/highvolume.txt" ) ) {
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 2 ) );
      $earliest_date = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

      if ( $startdate < $earliest_date ) {
        $startdate = $earliest_date;
      }
    }

    if ( length($starttime) != 14 ) {
      $starttime .= "000000";
    }

    my $starttranstime = &miscutils::strtotime($startdate);
    if ( $starttranstime eq "" ) {
      $starttranstime = &miscutils::strtotime( $twomonthsago . "000000" );
    }
    my ($newtime);
    if ( ( $operation eq "batchquery" ) && ( $chkprocessor eq "selectcheck" ) && ( $datainfo{'accttype'} eq "checking" ) ) {
      $newtime = $starttranstime - ( 3600 * 24 * 21 );
    } elsif ( ( $operation eq "batchquery" ) && ( $chkprocessor eq "paymentdata" ) && ( $datainfo{'accttype'} eq "checking" ) ) {
      $newtime = $starttranstime - ( 3600 * 24 * 14 );
    } else {
      $newtime = $starttranstime - ( 3600 * 24 * 7 );
    }

    $starttransdate = &miscutils::timetostr($newtime);
    $starttransdate = substr( $starttransdate, 0, 8 );

    my $inclusiveDateFlag = 0;
    if ( substr( $endtime, 8 ) > 0 ) {
      $inclusiveDateFlag = 1;
    }

    if ( $starttransdate < 20160901 ) {
      $starttransdate = "20160901";
    }

    ( $qmarks, $dateArrayRef ) = &miscutils::dateIn( $starttransdate, $enddate, $inclusiveDateFlag );
    $searchstr .= " AND t.trans_date IN (PLACEHOLDER) ";
  }

  if ( $linked_accts ne "" ) {
    $linked_accts =~ s/[^0-9a-z\,]//g;
    my @linked_accts = split( /\,/, $linked_accts );
    my $qmarks = '?,' x @linked_accts;
    chop $qmarks;
    push( @executeArray, @linked_accts );
    $searchstr .= " and t.username IN ($qmarks) ";
  } elsif ( $fuzzyun ne "" ) {
    $searchstr .= " and t.username LIKE ? ";
    push( @executeArray, "$fuzzyun%" );
  } else {
    $searchstr .= " and t.username=?";
    push( @executeArray, $username );
  }

  if ( $batchtime ne "" ) {
    $searchstr .= " and t.batch_time>=?";
    push( @executeArray, $batchtime );
  } else {
    $searchstr .= " and t.trans_time>=?";
    push( @executeArray, $starttime );
  }

  $searchstr .= " and t.trans_time<?";
  push( @executeArray, $endtime );

  if ( $batchid ne "" ) {
    $searchstr .= " and t.result=?";
    push( @executeArray, $batchid );
  }

  if ( $refnumber ne "" ) {
    $searchstr .= " and t.refnumber like ?";
    push( @executeArray, "$refnumber%" );
  }

  if ( $lowamount ne "" ) {
    $searchstr .= " and cast(substr(t.amount,5) AS DECIMAL(10,2))>=?";
    push( @executeArray, $lowamount );
  }
  if ( $highamount ne "" ) {
    $searchstr .= " and cast(substr(t.amount,5) AS DECIMAL(10,2))<=?";
    push( @executeArray, $highamount );
  }

  my @acctCodes = ( 'acct_code', 'acct_code2', 'acct_code3', 'acct_code4' );
  foreach my $var (@acctCodes) {
    if ( $datainfo{$var} ne "" ) {
      if ( $partial == 1 ) {
        $searchstr .= " and t.$var like ?";
        push( @executeArray, "%$datainfo{$var}%" );
      } else {
        $searchstr .= " and t.$var = ?";
        push( @executeArray, "$datainfo{$var}" );
      }
    }
  }

  if ( $card_name ne "" ) {
    $searchstr .= " and upper(t.card_name) like ?";
    push( @executeArray, $card_name );
  }

  if ( $cardtype ne "" ) {
    if ( $cardtype eq "vs" ) {
      $searchstr .= " and t.card_number like ?";
      push( @executeArray, "4%" );
    } elsif ( $cardtype eq "mc" ) {
      $searchstr .= " and t.card_number like ?";
      push( @executeArray, "5%" );
    } elsif ( $cardtype eq "ds" ) {
      $searchstr .= " and (t.card_number like ? or t.card_number like ?)";
      push( @executeArray, "6011%", "65%" );
    } elsif ( $cardtype eq "ax" ) {
      $searchstr .= " and (t.card_number like ? or t.card_number like ?)";
      push( @executeArray, "34%", "37%" );
    } elsif ( ( $cardtype eq "dc" ) || ( $cardtype eq "cb" ) ) {
      $searchstr .= " and (t.card_number like ? or t.card_number like ? or t.card_number like ?)";
      push( @executeArray, "30%", "36%", "38%" );
    } elsif ( $cardtype eq "jc" ) {
      $searchstr .= " and (t.card_number like ? or t.card_number like ? or t.card_number like ? or t.card_number like ? or t.card_number like ? or t.card_number like ?)";
      push( @executeArray, "3088%", "3096%", "3112%", "3158%", "3337%", "35%" );
    } elsif ( $cardtype eq "kc" ) {
      $searchstr .= " and (t.card_number like ? or t.card_number like ? or t.card_number like ?)";
      push( @executeArray, "7775%", "7776%", "7777%" );
    } elsif ( $cardtype eq "ma" ) {
      $searchstr .= " and t.card_number like ?";
      push( @executeArray, "6759%" );
    } elsif ( $cardtype eq "sw" ) {
      $searchstr .= " and t.card_number like ?";
      push( @executeArray, "6767%" );
    }
  }

  if ( $status ne "" ) {
    if ( $status eq "sap" ) {
      $searchstr .= " and t.finalstatus IN (?,?,?)";
      push( @executeArray, 'success', 'pending', 'locked' );
    } elsif ( $status eq "failure" ) {
      $searchstr .= " and t.finalstatus IN (?,?)";
      push( @executeArray, 'badcard', 'problem' );
    } elsif ( $status eq "pending" ) {
      $searchstr .= " and t.finalstatus IN (?,?)";
      push( @executeArray, 'pending', 'locked' );
    } else {
      $searchstr .= " and t.finalstatus=?";
      push( @executeArray, $status );
    }
  }

  if ( $txntype ne "" ) {
    if ( $txntype =~ /^(auth|capture)$/ ) {
      $searchstr .= " and t.operation='auth'";
    } elsif ( $txntype eq "anm" ) {
      my $earliest_date = "20130101";
      if ( ( -e "/home/p/pay1/outagefiles/mediumvolume.txt" ) || ( -e "/home/p/pay1/outagefiles/highvolume.txt" ) ) {
        my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 2 ) );
        $earliest_date = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

        if ( $startdate < $earliest_date ) {
          $startdate = $earliest_date;
        }
      }

      $searchstr .= " and t.operation in (?,?,?) and t.finalstatus in (?,?) ";
      push( @executeArray, 'auth', 'void', 'postauth', 'success', 'pending' );
    } elsif ( $txntype eq "marked" ) {
      $searchstr .= " and t.operation=?";
      push( @executeArray, 'postauth' );
    } elsif ( $txntype =~ /(return|markret)/ ) {
      $searchstr .= " and t.operation=?";
      push( @executeArray, 'return' );
    } elsif ( ( $accttype eq "checking" ) && ( $txntype eq "settled" ) ) {
      $searchstr .= " and t.operation=?";
      push( @executeArray, 'postauth' );
    } elsif ( $txntype eq "settled" ) {
      $searchstr .= " and t.operation=? and t.finalstatus=?";
      push( @executeArray, 'postauth', 'success' );
    } elsif ( $txntype eq "setlret" ) {
      $searchstr .= " and t.operation=? and t.finalstatus=?";
      push( @executeArray, 'return', 'success' );
    } elsif ( ( $accttype eq "checking" ) && ( $txntype eq "batch" ) && ( $operation eq "batchquery" ) ) {
      $searchstr .= " and t.operation in (?,?,?)";
      push( @executeArray, 'postauth', 'return', 'chargeback' );
    } elsif ( ( $accttype eq "checking" ) && ( $txntype eq "batch" ) ) {
      $searchstr .= " and t.operation in (?,?)";
      push( @executeArray, 'postauth', 'return' );
    } elsif ( $txntype eq "batch" ) {
      $searchstr .= " and t.operation in (?,?) and t.finalstatus=?";
      push( @executeArray, 'postauth', 'return', 'success' );
    } elsif ( $txntype =~ /void/ ) {
      $searchstr .= " and t.operation=? and t.finalstatus=?";
      push( @executeArray, 'void', 'success' );
    } elsif ( $txntype eq "forceauth" ) {
      $searchstr .= " and t.operation=?";
      push( @executeArray, 'forceauth' );
    } elsif ( ( $accttype eq "checking" ) && ( $txntype eq "chargeback" ) ) {
      $searchstr .= " and t.operation =?";
      push( @executeArray, 'chargeback' );
    }
  }

  if ( $cardnumber ne "" ) {
    my $cc         = new PlugNPay::CreditCard($cardnumber);
    my @cardHashes = $cc->getCardHashArray();
    my $qmarks     = '?,' x @cardHashes;
    chop $qmarks;
    $searchstr .= " and t.shacardnumber IN ($qmarks)  ";
    push( @executeArray, @cardHashes );
  }

  if ( $accttype =~ /^(checking|savings)$/ ) {
    $searchstr .= " and o.accttype in (?,?)";
    push( @executeArray, 'checking', 'savings' );
  } elsif ( $accttype =~ /^(seqr)$/ ) {
    $searchstr .= " and o.accttype=? ";
    push( @executeArray, $accttype );
  } else {
    $searchstr .= " and (o.accttype is NULL or o.accttype='' or o.accttype='credit')";
  }

  if ( $options->{'no-capture'} ) {
    $searchstr .= ' and t.transflags not like ? ';
    push @executeArray, '%capture%';
  }

  $searchstr .= " and (t.duplicate IS NULL or t.duplicate='')";
  $searchstr .= " and t.operation NOT IN (?,?,?,?) order by t.orderid,t.trans_time";

  push( @executeArray, 'query', 'batch-prep', 'batchquery', 'batchdetails' );

  my $origoperation = $operation;
  if ( $origoperation eq "batch-prep" ) {
    @executeArray = ();
    ## For Mysql
    my $hint = "force index(tlog_tdateuname_idx)";

    my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 30 ) );
    my $twomonthsago = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );

    $searchstr = qq/
    select 
      t.orderid as orderid,
      t.refnumber as refnumber,
      t.card_name as card_name,
      t.card_number as card_number,
      t.card_exp as card_exp,
      t.amount as amount,
      t.trans_date as trans_date,
      t.trans_time as trans_time,
      t.trans_type as trans_type,
      t.auth_code as auth_code,
      t.result as result,
      t.finalstatus as finalstatus,
      t.operation as operation,
      t.avs as avs,
      t.cvvresp as cvvresp,
      t.enccardnumber as encccardnumber,
      t.length as length,
      t.acct_code as acct_code,
      t.acct_code2 as acct_code2,
      t.acct_code3 as acct_code3,
      t.acct_code4 as acct_code4,
      t.batch_time as batch_time,
      t.transflags as transflags,
      t.descr as descr,
      t.card_country as card_country,
      t.username as username,
      t.ipaddress as ipaddress,
      t.cardextra as cardextra,
      t.processor as processor
    /;

    # operation log used to filter on accttype
    $searchstr .= " from trans_log t $hint, operation_log o";

    my $earliest_date = "20040101";
    if ( ( -e "/home/p/pay1/outagefiles/mediumvolume.txt" ) || ( -e "/home/p/pay1/outagefiles/highvolume.txt" ) ) {
      my ( $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst ) = gmtime( time() - ( 3600 * 24 * 2 ) );
      $earliest_date = sprintf( "%04d%02d%02d", $year + 1900, $month + 1, $day );
    }

    if ( $datainfo{'start-time'} eq "" ) {
      if ( $twomonthsago > $earliest_date ) {
        $startdate = $twomonthsago;
      } else {
        $startdate = $earliest_date;
      }
    } else {
      $startdate = substr( $datainfo{'start-time'}, 0, 8 );
      if ( $startdate < $earliest_date ) {
        $startdate = $earliest_date;
      }
    }

    my ($endate) = &miscutils::gendatetime_only();

    ( $qmarks, $dateArrayRef ) = &miscutils::dateIn( $startdate, $enddate, '1' );
    $searchstr .= " where t.trans_date IN (PLACEHOLDER)";

    $searchstr .= " and t.username=?";
    push( @executeArray, $username );

    if ( $acct_code ne "" ) {
      $searchstr .= " and t.acct_code=?";
      push( @executeArray, $acct_code );
    }

    $searchstr .= " and t.operation IN (?,?,?,?,?,?,?)";
    push( @executeArray, 'auth', 'postauth', 'return', 'void', 'reauth', 'retry', 'forceauth' );

    if ( $accttype =~ /^(checking|savings)$/ ) {
      $searchstr .= " and o.accttype in (?,?)";
      push( @executeArray, 'checking', 'savings' );
    } else {
      $searchstr .= " and (o.accttype is NULL or o.accttype='' or o.accttype='credit')";
    }

    if ( $options->{'no-capture'} ) {
      $searchstr .= ' and t.transflags not like ? ';
      push @executeArray, '%capture%';
    }

    $searchstr .= " and (t.duplicate IS NULL or t.duplicate='')";
    $searchstr .= " order by t.orderid,t.trans_time DESC,t.operation DESC";
  }

  my $qstr = $searchstr;
  $qstr =~ s/PLACEHOLDER/$qmarks/;

  my @array = ();
  if ( $nooidflag != 1 ) {
    @array = ($srchorderid);
  }
  push( @array, @$dateArrayRef, @executeArray );

  if ( -e "/home/p/pay1/outagefiles/log_smpsutils.txt" ) {
    my $datetime = gmtime( time() );
    open( DEBUG, ">>/home/p/pay1/database/debug/smpsutils_queries.txt" );
    print DEBUG "DATE:$datetime, UN:$username, SN:$ENV{'SCRIPT_NAME'}, NOOIDFLG:$nooidflag, FUZZY:$fuzzyun, LINKED:$linked_accts, PID:$$, LINE:396, SRCHSTR:$qstr\n";
    foreach my $var (@array) {
      print DEBUG "$var, ";
    }
    print DEBUG "\n\n";
    close(DEBUG);

    #use Datalog
    my %sdata = ();
    $sdata{DATE}     = $datetime;
    $sdata{UN}       = $smps::username;
    $sdata{SN}       = $ENV{'SCRIPT_NAME'};
    $sdata{NOOIDFLG} = $nooidflag;
    $sdata{FUZZY}    = $fuzzyun;
    $sdata{LINKED}   = $linked_accts;
    $sdata{PID}      = $$;
    $sdata{SRCHSTR}  = $qstr;

    foreach my $var (@array) {
      print DEBUG "$var, ";
      $sdata{$var} = $var;
    }

    my $logger = new PlugNPay::Logging::DataLog( { collection => 'smpsutils_queries' } );
    $logger->log( \%sdata );
  }

  my $dbh1 = &miscutils::dbhconnect( "pnpdata", "", "$username" );

  my $sth1 = $dbh1->prepare($qstr) or die($DBI::errstr);    #&miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%datainfo);
  $sth1->execute(@array) or die($DBI::errstr);              #&miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%datainfo);

  my $array1 = $sth1->fetchall_arrayref( {} );
  $sth1->finish;

  my @dataArray = ();

  push( @dataArray, @{$array1} );
  my $i = 1;
  my (%anm_delete);
  foreach my $data (@dataArray) {
    ( $orderid, $refnumber, $card_name, $card_number, $card_exp, $amount, $trans_date ) =
      ( $data->{'orderid'}, $data->{'refnumber'}, $data->{'card_name'}, $data->{'card_number'}, $data->{'card_exp'}, $data->{'amount'}, $data->{'trans_date'} );
    ( $trans_time, $trans_type, $auth_code, $batchfile ) = ( $data->{'trans_time'}, $data->{'trans_type'}, $data->{'auth_code'}, $data->{'result'} );
    ( $result, $operation, $avs_code, $cvvresp, $enccardnumber, $length ) =
      ( $data->{'finalstatus'}, $data->{'operation'}, $data->{'avs'}, $data->{'cvvresp'}, $data->{'enccardnumber'}, $data->{'length'} );
    ( $acct_code, $acct_code2, $acct_code3, $acct_code4, $card_addr, $card_city, $card_state ) =
      ( $data->{'acct_code'}, $data->{'acct_code2'}, $data->{'acct_code3'}, $data->{'acct_code4'}, $data->{'card_addr'}, $data->{'card_city'}, $data->{'card_state'} );
    ( $card_zip, $card_country, $batch_time, $transflags, $descr ) = ( $data->{'card_zip'}, $data->{'card_country'}, $data->{'batch_time'}, $data->{'transflags'}, $data->{'descr'} );
    ( $merchant, $ipaddress, $cardextra, $processor ) = ( $data->{'username'}, $data->{'ipaddress'}, $data->{'cardextra'}, $data->{'processor'} );

    # xxxx 10/27/1999
    if ( ( $origoperation eq "batch-prep" ) && ( $operation eq "auth" ) && ( $result ne "success" ) ) {
      next;
    }
    if ( ( $origoperation eq "batch-prep" ) && ( $result ne "success" ) ) {
      $orderidold = $orderid;
      next;
    }
    if ( ( $origoperation eq "batch-prep" ) && ( $transflags =~ /gift|avsonly|balance/ ) ) {
      $orderidold = $orderid;
      next;
    }

    if ( ( $txntype eq "anm" ) && ( $operation =~ /(postauth|void)/ ) ) {
      $anm_delete{$orderid} = 1;
      next;
    }
    my $decrypttrantime = &miscutils::strtotime($trans_date);
    my ($sixmonthsago);
    if ( $username =~ /^(initaly)$/ ) {
      $sixmonthsago = time() - ( 365 * 24 * 3600 );
    } else {
      $sixmonthsago = time() - ( 365 * 24 * 3600 );    ###  DCP extended query time to go back for 1 year.  20070607
    }

    if ( $decrypttrantime < $sixmonthsago ) {
      $decryptflag = "no";
    }

    # THE FOLLOWING CONTAINS SOME CODE THAT IS INTENTIONALLY COMMENTED OUT AND LEFT HERE
    # The map $result does not/should not contain these keys.  If for some reason they need
    # to be re-added, leaving the code here for a few releases would make switching back simpler.
    if ( ( $length > 0 ) && ( $length <= 1024 ) && ( $origoperation ne "batch-prep" ) && ( $operation =~ /^(forceauth|auth|postauth|return|storedata)$/ ) ) {
      if ( ( $ENV{'SEC_LEVEL'} < 7 ) && ( $decryptflag eq "yes" ) ) {
        $card_number = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
      }

      #   else {
      #     #print "REMOTEUSR:$ENV{'REMOTE_USER'}, LOGIN:$ENV{'LOGIN'}, SUB:$ENV{'SUBACCT'}, SEC LEV:$ENV{'SEC_LEVEL'}<br>\n";
      #   }
      #   $result{'card-number'} = $card_number;

      #   if (length($result{'card-number'}) > 60) {
      #     $result{'card-number'} = "";
      #   }

      # }
      # else {
      #   $result{'card-number'} = "";
      # }

      # if ($auth_code ne "") {
      #   $result{'auth-code'} = $auth_code;
      # }
      # if ($avs_code ne "") {
      #   $result{'avs-code'} = $avs_code;
      # }
      # if ($cvvresp ne "") {
      #   $result{'cvvresp'} = $cvvresp;
      # }
      # if ($card_exp ne "") {
      #   $result{'card-exp'} = $card_exp;
    }

    my $shortcard = substr( $card_number, 0, 4 );
    my $card_type = "";

    if ( ( $shortcard >= 4000 ) && ( $shortcard <= 4999 ) ) {
      $card_type = "vs";    # visa
    } elsif ( ( $shortcard >= 5000 ) && ( $shortcard <= 5999 ) ) {
      $card_type = "mc";    # mastercard
    } elsif ( ( $shortcard >= 2221 ) && ( $shortcard <= 2720 ) ) {
      $card_type = "mc";    # mastercard
    } elsif ( ( ( $shortcard >= 3400 ) && ( $shortcard <= 3499 ) )
      || ( ( $shortcard >= 3700 ) && ( $shortcard <= 3799 ) ) ) {
      $card_type = "ax";    # amex
    } elsif ( ( $shortcard == 6011 ) || ( $shortcard =~ /^65/ ) ) {
      $card_type = "ds";    # discover
    } elsif ( ( $shortcard >= 3930 ) && ( $shortcard <= 3949 ) ) {
      $card_type = "cb";    # diners
    } elsif ( ( ( $shortcard >= 3000 ) && ( $shortcard <= 3059 ) )
      || ( ( $shortcard >= 3600 ) && ( $shortcard <= 3699 ) )
      || ( ( $shortcard >= 3800 ) && ( $shortcard <= 3899 ) ) ) {
      $card_type = "dc";
    } elsif ( ( ( $shortcard >= 3083 ) && ( $shortcard <= 3329 ) )
      || ( ( $shortcard >= 3528 ) && ( $shortcard <= 3589 ) ) ) {
      $card_type = "jc";
    } elsif ( $shortcard =~ /^(7775|7776|7777)/ ) {
      $card_type = 'kc';    # keycard
    } elsif ( $shortcard =~ /^(6767)/ ) {
      $card_type = 'sw';    # solo
    } elsif ( $shortcard =~ /^(6759)/ ) {
      $card_type = 'ma';    # maestro, switch is now maestro
    } elsif ( $shortcard =~ /^(8)/ ) {
      $card_type = "pl";    # pnp private label
    } elsif ( $shortcard =~ /^(9)/ ) {
      $card_type = "sv";    # pnp stored value
    }

    if ( $transflags =~ /milstar/ ) {
      $card_type = "ms";
    }

    $card_company = "";
    if ( $origoperation ne "batch-prep" ) {
      $result{"a$i"} =
        "order-id=$orderid\&time=$trans_time\&merch-txn=$refnumber\&card-number=$card_number\&card-exp=$card_exp\&amount=$amount\&txn-type=$operation\&auth-code=$auth_code\&avs-code=$avs_code\&cvvresp=$cvvresp\&txn-status=$result\&card-type=$card_type\&operation=$operation\&card-name=$card_name\&acct_code=$acct_code\&acct_code2=$acct_code2\&acct_code3=$acct_code3\&acct_code4=$acct_code4\&batch-id=$batchfile\&card-addr=$card_addr\&card-city=$card_city\&card-state=$card_state\&card-zip=$card_zip\&card-country=$card_country\&batch_time=$batch_time\&transflags=$transflags\&descr=$descr\&card-company=$card_company\&username=$merchant\&ipaddress=$ipaddress\&cardextra=$cardextra\&processor=$processor";
      $i++;
    } elsif ( ( $origoperation eq "batch-prep" )
      && ( ( $operation eq "auth" ) || ( $operation eq "reauth" ) || ( $operation eq "forceauth" ) )
      && ( $orderid ne $orderidold )
      && ( $result eq "success" )
      && ( ( $datainfo{'card-type'} eq "" ) || ( $datainfo{'card-type'} eq $card_type ) ) ) {

      $result{"a$i"} =
        "time=$trans_time\&order-id=$orderid\&merch-txn=$refnumber\&card-number=$card_number\&card-exp=$card_exp\&amount=$amount\&txn-type=$operation\&auth-code=$auth_code\&avs-code=$avs_code\&cvvresp=$cvvresp\&txn-status=$result\&card-type=$card_type\&operation=$operation\&card-name=$card_name\&acct_code=$acct_code\&acct_code2=$acct_code2\&acct_code3=$acct_code3\&acct_code4=$acct_code4\&card-addr=$card_addr\&card-city=$card_city\&card-state=$card_state\&card-zip=$card_zip\&card-country=$card_country\&batch_time=$batch_time\&transflags=$transflags";
      $i++;
      if ( ( $username =~ /^(achepenzio|achadvancec|achworldwi1|plugnpay)$/ ) && ( $i % 50 == 0 ) ) {
        print " ";
      }
    }
    $orderidold = $orderid;
  }

  if ( $txntype eq "anm" ) {
    foreach my $key ( keys %result ) {
      $result{$key} =~ /order\-id=(\d*)\&/;
      if ( exists $anm_delete{$1} ) {
        delete $result{$key};
      }
    }
  }

  return %result;

}

sub details {
  my ( $username, %datainfo ) = @_;

  my ( $refnumber, $card_number, $card_exp, $amount, $trans_date, $trans_time, $trans_type );
  my ( $auth_code, $result, $avs_code, $cvvresp, $operation, $enccardnumber, $length, $proc_type );
  my %result = ();

  my $orderid = $datainfo{'order-id'};

  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $proc_type      = $gatewayAccount->getProcessingType();

  my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$username" );

  my $descr;
  my $sth = $dbh->prepare(
    qq{
      select orderid,refnumber,card_number,card_exp,
             amount,trans_date,trans_time,trans_type,
             auth_code,finalstatus,avs,cvvresp,operation
             enccardnumber,length,descr
      from trans_log where orderid='$orderid' and username='$username' and operation<>'query'
      order by trans_time
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth->bind_columns( undef,
    \( $orderid, $refnumber, $card_number, $card_exp, $amount, $trans_date, $trans_time, $trans_type, $auth_code, $result, $avs_code, $cvvresp, $operation, $enccardnumber, $length, $descr ) );
  my $i = 0;
  while ( $sth->fetch ) {
    if ( ( $length > 0 ) && ( $length <= 1024 ) ) {
      if ( $ENV{'SEC_LEVEL'} < 7 ) {
        $card_number = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
      }
      $result{'card-number'} = $card_number;
    } else {
      $result{'card-number'} = "";
    }

    if ( ( $proc_type eq "authonly" ) && ( $operation eq "postauth" ) ) {
      $trans_type = "marked";
    }

    if ( $auth_code ne "" ) {
      $result{'auth-code'} = $auth_code;
    }
    if ( $avs_code ne "" ) {
      $result{'avs-code'} = $avs_code;
    }
    if ( $cvvresp ne "" ) {
      $result{'cvvresp'} = $cvvresp;
    }

    $result{"a$i"} =
      "order-id=$orderid\&merch-txn=$refnumber\&card-number=$card_number\&card-exp=$card_exp\&amount=$amount\&time=$trans_time\&txn-type=$trans_type\&auth-code=$auth_code\&txn-status=$result\&avs-code=$avs_code\&cvvresp=$cvvresp\&descr=$descr";

    $i++;
  }
  $sth->finish;

  #$dbh->disconnect; # 20170421 DCP
}

sub carddetails {
}

sub unmark {
  my ( $username, %datainfo ) = @_;

  my %result = ();

  my $orderid = $datainfo{'order-id'};

  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $processor      = $gatewayAccount->getCardProcessor();
  my $proc_type      = $gatewayAccount->getProcessingType();
  my $chkprocessor   = $gatewayAccount->getCheckProcessor();

  my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$username" );

  my $sth = $dbh->prepare(
    qq{
      select trans_type,finalstatus,operation,acct_code,acct_code2,acct_code3,subacct,card_name,card_number,transflags
      from trans_log
      where orderid='$orderid'
      and username='$username'
      and finalstatus IN ('success','pending','hold')
      order by trans_time desc
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  my ( $trans_type, $finalstatus, $operation, $acct_code, $acct_code2, $acct_code3, $subacct, $card_name, $card_number, $transflags ) = $sth->fetchrow;
  $sth->finish;

  my $sth2 = $dbh->prepare(
    qq{
      select lastop
      from operation_log
      where orderid='$orderid'
      and username='$username'
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth2->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  my ($lastop) = $sth2->fetchrow;
  $sth2->finish;

  my $line1 = "";
  my $line2 = "";

  if ( -e "/home/p/pay1/batchfiles/$processor/batchfile.txt" ) {
    $line1 = `cat /home/p/pay1/batchfiles/$processor/batchfile.txt`;
  }

  if ( $chkprocessor eq "" ) {
    if ( -e "/home/p/pay1/batchfiles/ach/batchfile.txt" ) {
      $line2 = `cat /home/p/pay1/batchfiles/ach/batchfile.txt`;
    }
  } else {
    if ( -e "/home/p/pay1/batchfiles/$chkprocessor/batchfile.txt" ) {
      $line2 = `cat /home/p/pay1/batchfiles/$chkprocessor/batchfile.txt`;
    }
  }

  my $authcaptureflag = 0;
  if ( ( $transflags =~ /capture/ ) || ( ( $proc_type eq "authcapture" ) && ( $transflags !~ /authonly/ ) ) ) {
    $authcaptureflag = 1;
  }

  if ( ( $lastop !~ /^(auth|reauth|forceauth)$/ ) || ( $authcaptureflag == 1 ) ) {
    if ( ( $line1 =~ /$username/ ) || ( $line2 =~ /$username/ ) ) {
      $result{'MErrMsg'}     = "Operation void not allowed at this time. Please try again later.";
      $result{'MStatus'}     = "problem";
      $result{'FinalStatus'} = "problem";
      $result{'acct_code'}   = "$acct_code";
      $result{'acct_code2'}  = "$acct_code2";
      $result{'acct_code3'}  = "$acct_code3";
      $result{'subacct'}     = "$subacct";
      $result{'card-name'}   = "$card_name";
      $result{'card-number'} = "$card_number";
      return %result;
    }
  }

  if ( $operation =~ /^(auth|reauth|forceauth|return|postauth)$/ ) {
    $result{'MStatus'}     = "success";
    $result{'FinalStatus'} = "success";
    $result{'acct_code'}   = "$acct_code";
    $result{'acct_code2'}  = "$acct_code2";
    $result{'acct_code3'}  = "$acct_code3";
    $result{'subacct'}     = "$subacct";
    $result{'card-name'}   = "$card_name";
    $result{'card-number'} = "$card_number";
    return %result;
  } else {
    $result{'MStatus'}     = "problem";
    $result{'FinalStatus'} = "problem";
    $result{'acct_code'}   = "$acct_code";
    $result{'acct_code2'}  = "$acct_code2";
    $result{'acct_code3'}  = "$acct_code3";
    $result{'subacct'}     = "$subacct";
    $result{'card-name'}   = "$card_name";
    $result{'card-number'} = "$card_number";
    return %result;
  }

  #$dbh->disconnect;  # 20170421 DCP

  return %result;
}

sub cardquery {
  my ( $username, %datainfo ) = @_;

  my %result        = ();
  my $length        = "";
  my $enccardnumber = "";

  #my $dbh = &miscutils::dbhconnect("pnpdata");
  my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$username" );

  my $sth = $dbh->prepare(
    qq{
      select card_name,card_addr,card_city,card_state,card_zip,enccardnumber,length,card_exp
      from trans_log
      where orderid='$datainfo{'order-id'}'
      and username='$username'
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  ( $result{'card-name'}, $result{'card-addr'}, $result{'card-city'}, $result{'card-state'}, $result{'card-zip'}, $enccardnumber, $length, $result{'card-exp'} ) = $sth->fetchrow;
  $sth->finish;

  #$dbh->disconnect;  # 20170421 DCP

  if ( ( $length > 0 ) && ( $length <= 1024 ) ) {
    $result{'card-number'} = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
    if ( $ENV{'SEC_LEV'} >= 7 ) {
      $result{'card-number'} = substr( $result{'card-number'}, 0, 4 ) . "**" . substr( $result{'card-number'}, -2 );
    }
  } else {
    $result{'card-number'} = "";
  }

  return %result;
}

sub mark {
  my ( $username, %datainfo ) = @_;
}

sub batchunroll {
  my ( $username, %datainfo ) = @_;
}

sub batchquery {
  my ( $username, %datainfo ) = @_;
}

sub assemble {
  my ( $username, %datainfo ) = @_;
}

sub checkmagstripe {
  my ( $magstripe, $debug ) = @_;

  my $magstripetrack2 = "";
  my $magstripetrack  = "";
  my $ok1index        = "";
  my $ok2index        = "";
  my $cardnum2        = "";
  my $cardnum         = "";
  my $expdate2        = "";
  my $expdate         = "";
  my $magstripeout2   = "";
  my $magstripeout    = "";

  if ( $magstripe eq "" ) {
    $magstripetrack = "";
    $magstripeout   = "";
    $cardnum        = "";
    $expdate        = "";
    return ( $magstripetrack, $magstripeout, $cardnum, $expdate );
  }

  if ( $magstripe =~ /^(\%|\0*B)/ ) {
    my $bindex    = index( $magstripe, "B", 0 );
    my $nameindex = index( $magstripe, "^", 0 );
    my $dateindex = index( $magstripe, "^", $nameindex + 1 );
    $ok1index = index( $magstripe, "ok", $dateindex + 1 );
    if ( $ok1index <= $dateindex ) {
      $ok1index = index( $magstripe, "?", $dateindex + 1 );
    }
    if ( ( $bindex >= 0 )
      && ( $nameindex > $bindex )
      && ( $dateindex > $nameindex )
      && ( $ok1index > $dateindex )
      && ( $ok1index - $bindex < 80 ) ) {
      $magstripetrack = "1";
      $magstripeout = substr( $magstripe, $bindex, $ok1index - $bindex );

      #$magstripe = $magstripe . '?';
      $cardnum = substr( $magstripe, $bindex + 1, $nameindex - $bindex - 1 );
      $expdate = substr( $magstripe, $dateindex + 3, 2 ) . '/' . substr( $magstripe, $dateindex + 1, 2 );
    }

    if ( $debug eq "yes" ) {
      print "bindex: $bindex<br>\n";
      print "nameindex: $nameindex<br>\n";
      print "dateindex: $dateindex<br>\n";
      print "ok1index: $ok1index<br>\n";
      print "magstripetrack: $magstripetrack<br>\n";
      print "magstripeout: $magstripeout<br>\n";
      print "cardnum: $cardnum<br>\n";
      print "expdate: $expdate<br>\n";
    }
  }

  #if ($magstripetrack ne "1") {}
  if (1) {

    #my $magstripe = $magstripe;
    my $scindex    = index( $magstripe, ";", 0 );
    my $equalindex = index( $magstripe, "=", $scindex + 1 );
    $ok2index = index( $magstripe, "ok", $equalindex + 1 );
    if ( $ok2index <= $equalindex ) {
      $ok2index = index( $magstripe, "?", $equalindex + 1 );
    }
    if ( ( $scindex >= $ok1index ) && ( $equalindex > $scindex ) && ( $ok2index > $equalindex ) ) {
      my $temp = substr( $magstripe, 1, $ok2index - $scindex - 1 );
      $magstripetrack2 = "2";
      $magstripeout2 = substr( $magstripe, $scindex + 1, $ok2index - $scindex - 1 );

      #$magstripe = $magstripe . '?';
      $cardnum2 = substr( $magstripe, $scindex + 1, $equalindex - $scindex - 1 );
      $expdate2 = substr( $magstripe, $equalindex + 3, 2 ) . '/' . substr( $magstripe, $equalindex + 1, 2 );
    }
    if ( $debug eq "yes" ) {
      print "scindex: $scindex<br>\n";
      print "equalindex: $equalindex<br>\n";
      print "ok2index: $ok2index<br>\n";
      print "magstripetrack: $magstripetrack2<br>\n";
      print "magstripeout2: $magstripeout2<br>\n";
      print "cardnum: $cardnum2<br>\n";
      print "expdate: $expdate2<br>\n";
    }
  }

  if ( ( $magstripeout2 ne "" ) && ( ( length($cardnum2) >= 12 ) && ( length($cardnum2) < 20 ) && ( $cardnum2 =~ /^[0-9]+$/ ) && ( $expdate2 =~ /^[0-9][0-9]\/[0-9][0-9]$/ ) ) ) {
    if ( $debug eq "yes" ) {
      print "aaaa\n";
    }
    $magstripetrack = $magstripetrack2;
    $magstripeout   = $magstripeout2;
    $cardnum        = $cardnum2;
    $expdate        = $expdate2;
  }

  if ( $magstripetrack eq "" ) {
    if ( $debug eq "yes" ) {
      print "bbbb\n";
    }
    $magstripetrack = "0";
    $magstripeout   = "";
    $cardnum        = "";
    $expdate        = "";
  }

  if ( length($cardnum) > 19 ) {
    if ( $debug eq "yes" ) {
      print "cccc\n";
    }
    $magstripetrack = "0";
    $magstripeout   = "";
    $cardnum        = "";
    $expdate        = "";
  }
  $cardnum =~ s/[^0-9]//g;

  return ( $magstripetrack, $magstripeout, $cardnum, $expdate );
}

sub checkexp {
  my ($card_exp) = @_;

  my $yearexp  = substr( $card_exp, 3, 2 );
  my $monthexp = substr( $card_exp, 0, 2 );

  if ( $card_exp !~ /^[0-9]{2}\/[0-9]{2}$/ ) {
    return "Expiration date must be of the format: MM/YY";
  }

  if ( $yearexp >= 70 ) {
    $yearexp = "19" . $yearexp;
  } else {
    $yearexp = "20" . $yearexp;
  }

  my $cardexp = $yearexp . $monthexp;

  my ($today) = &miscutils::gendatetime_only();
  my $todaymonth = substr( $today, 0, 6 );

  if ( $todaymonth > $cardexp ) {
    return "Card has expired";
  }
  return "";
}

sub checkcvv {
  my ($cvv) = @_;

  if ( $cvv eq "" ) {
    return "";
  } elsif ( $cvv =~ /[^0-9]/ ) {
    return "Card verification value incorrect";
  } elsif ( length($cvv) > 4 ) {
    return "Card verification value incorrect";
  } elsif ( length($cvv) == 2 ) {
    return "Card verification value incorrect";
  }

  return "";
}

sub checkamt {
  my ( $amount, $highflg ) = @_;

  my ( $currency, $amt ) = split( / /, $amount );

  if ( ( $currency !~ /^[a-zA-Z]{3}$/ ) || ( $amt =~ /[^0-9\.]/ ) ) {
    return "Amount must be of the format: usd 1.23";
  }
  if ( $amt =~ /\..*\./ ) {
    return "Amount must be of the format: usd 1.23";
  }
  if ( $amt < .01 ) {
    return "Amount must be greater than 0.00";
  }
  if ( ( $currency !~ /usd/i ) || ( $highflg == 1 ) ) {
    my ($highlimit);
    my %limits = ( 'jmd', '200000000.00' );
    if ( exists $limits{$currency} ) {
      $highlimit = $limits{$currency};
    } else {
      $highlimit = 9999999.99;
    }
    if ( $amt > $highlimit ) {
      return "Amount must be less than $highlimit";
    }
  } else {
    if ( $amt > 99999.99 ) {
      return "Amount must be less than 99999.99";
    }
  }
  return "";
}

sub checkcard {
  my ($cardnumber) = @_;

  my $cabbrev = substr( $cardnumber, 0, 4 );
  my $cardbin = substr( $cardnumber, 0, 6 );
  my $clen    = length($cardnumber);

  my $cardtype = "";

  if ( $cardnumber =~ /^(6767)/ ) {    ## New Solo Card Range
    $cardtype = "sw";
  } elsif (
    ( $cardnumber =~ /^(6759)/ )
    || ( $cardnumber =~ /^(490303)/ )    ## Can be removed after Nov. 30 2006
    ) {                                  ## Maestro UK Card Range
    $cardtype = "ma";
  } elsif ( ( $cardnumber =~ /^4/ ) && ( ( $clen == 13 ) || ( $clen == 16 ) || ( $clen == 19 ) ) ) {
    $cardtype = 'vi';                    # visa
  } elsif ( ( $cardnumber =~ /^5[12345]/ ) && ( $clen == 16 ) ) {
    $cardtype = 'mc';                    # mastercard
  } elsif ( ( ( $cardbin >= 222100 ) && ( $cardbin <= 272099 ) ) && ( $clen == 16 ) ) {    ## New MC Bin Range Effective Oct. 1, 2016
    $cardtype = "mc";
  } elsif ( ( $cardnumber =~ /^3[47]/ ) && ( $clen == 15 ) ) {
    $cardtype = 'ax';                                                                      # amex
  } elsif ( ( $cardnumber =~ /^3[0689]/ ) && ( $clen == 14 ) ) {
    $cardtype = 'dc';                                                                      # diners club/carte blanche
  } elsif ( ( $cardnumber =~ /^3[89]/ ) && ( $clen == 16 ) ) {
    $cardtype = 'dc';                                                                      # diners club/carte blanche
  } elsif ( ( $cardnumber =~ /^30[012345]/ ) && ( $clen == 16 ) ) {
    $cardtype = 'dc';                                                                      # diners club/carte blanche
  } elsif ( ( $cardnumber =~ /^3095/ ) && ( $clen == 16 ) ) {
    $cardtype = 'dc';                                                                      # diners club/carte blanche
  } elsif ( ( $cardnumber =~ /^(6011|64|65|62)/ ) && ( $clen == 16 ) ) {
    $cardtype = 'ds';                                                                      # discover
  } elsif ( ( ( $cardnumber =~ /^(3088|3096|3112|3158|3337)/ ) || ( ( $cabbrev >= 3528 ) && ( $cabbrev < 3590 ) ) )
    && ( $clen == 16 ) ) {                                                                 # jcb
    $cardtype = 'jc';                                                                      # jcb
  } elsif ( ( $cardnumber =~ /^(7775|7776|7777)/ ) && ( $clen == 16 ) ) {
    $cardtype = 'kc';                                                                      # keycard
  } elsif ( ( $cardnumber =~ /^(604626|605011|603028|603628)/ ) && ( ( $clen == 16 ) || ( $clen == 18 ) || ( $clen == 19 ) || ( $clen == 20 ) || ( $clen == 21 ) ) ) {
    $cardtype = 'pl';                                                                      # private label
  } elsif ( ( ( $cardnumber =~ /^(048|0420|0430|0498|0481)/ ) && ( $clen == 13 ) ) || ( ( $cardnumber =~ /^(690046|707138)/ ) && ( $clen == 19 ) ) ) {
    $cardtype = 'wx';                                                                      # wex
  } elsif ( $cardnumber =~ /^(8)/ ) {
    $cardtype = "pp";                                                                      # pnp private label
  } elsif ( $cardnumber =~ /^(9)/ ) {
    $cardtype = "sv";                                                                      # pnp stored value
  } elsif (
    ( ( $cardbin >= 500000 ) && ( $cardbin <= 509999 ) )                                   ## International Maestro
    || ( ( $cardbin >= 560000 ) && ( $cardbin <= 589999 ) )
    || ( ( $cardbin >= 600000 ) && ( $cardbin <= 699999 ) )
    ) {
    $cardtype = "ma";
  } else {
    $cardtype = '';
  }

  return $cardtype;
}

sub checkdup {
  my ( $username, $operation, $orderid, $shacardnumber, $cardnumber ) = @_;

  my ($cc);
  if ( $cardnumber ne "" ) {
    $cc = new PlugNPay::CreditCard($cardnumber);
  }

  my %result = ();
  my ( $chkfinalstatus, $chkavs, $chkauthcode, $chkdescr, $chkamount, $chkoperation, $chktrans_time, $chkcardnumber, $chkcvvresp );

  my $dbh_dup = &miscutils::dbhconnect( "pnpdata", "", "$username" );

  if ( ( $operation eq "auth" ) || ( $operation eq "return" ) ) {
    my $sth_dup = $dbh_dup->prepare(
      qq{
            select finalstatus,avs,auth_code,descr,amount,operation,trans_time,shacardnumber,cvvresp
            from trans_log
            where orderid='$orderid'
            and username='$username'
            and operation in ('auth','forceauth','return')
            }
      )
      or die "Can't do: $DBI::errstr";
    $sth_dup->execute;
    ( $chkfinalstatus, $chkavs, $chkauthcode, $chkdescr, $chkamount, $chkoperation, $chktrans_time, $chkcardnumber, $chkcvvresp ) = $sth_dup->fetchrow;
    $sth_dup->finish;
  } else {
    my $sth_dup = $dbh_dup->prepare(
      qq{
            select finalstatus,avs,auth_code,descr,amount,operation,trans_time,shacardnumber,cvvresp
            from trans_log
            where orderid='$orderid'
            and username='$username'
            and operation='$operation'
            }
      )
      or die "Can't do: $DBI::errstr";
    $sth_dup->execute;
    ( $chkfinalstatus, $chkavs, $chkauthcode, $chkdescr, $chkamount, $chkoperation, $chktrans_time, $chkcardnumber, $chkcvvresp ) = $sth_dup->fetchrow;
    $sth_dup->finish;
  }

  if ( $chkfinalstatus ne "" ) {
    my $origtime  = &miscutils::strtotime($chktrans_time);
    my $duptime   = time();
    my $deltatime = $duptime - $origtime;

    if ( $operation eq "auth"
      && $chkoperation eq "auth"
      && $deltatime < 1200
      && $cardnumber ne ""
      && $cc->compareHash($chkcardnumber) ) {
      $result{'FinalStatus'} = "$chkfinalstatus";
      $result{'MStatus'}     = "$chkfinalstatus";
      $result{'MErrMsg'}     = "Duplicate $operation: $chkdescr";
      $result{'avs-code'}    = "$chkavs";
      $result{'cvvresp'}     = "$chkcvvresp";
      $result{'auth-code'}   = substr( $chkauthcode, 0, 6 );
      $result{'Duplicate'}   = "yes";
      if ( $chkdescr =~ /^([0-9]+:)/ ) {
        $result{'resp-code'} = $1;
      }
    } elsif ( $operation eq "return"
      && $cardnumber ne ""
      && !$cc->compareHash($chkcardnumber) ) {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'}     = "problem";
      $result{'MErrMsg'}     = "Illegal $operation: orderid has already been used";
    } elsif ( $operation eq "return" ) {
      return %result;
    } elsif ( $operation eq "auth" ) {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'}     = "problem";
      $result{'MErrMsg'}     = "Illegal $operation: orderid has already been used";
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'}     = "problem";
      $result{'MErrMsg'}     = "Duplicate $operation: $chkdescr";
      $result{'Duplicate'}   = "yes";
      if ( $chkdescr =~ /^([0-9]+:)/ ) {
        $result{'resp-code'} = $1;
      }
    }
    $result{'card-amount'} = $chkamount;
  }

  return %result;
}

sub gettransid {
  my ( $ipcusername, $processor, $ipcorderid ) = @_;

  if ( -e "/home/pay1/etc/transid/$processor" || -e "/home/pay1/etc/transid/all_processors" ) {
    return PlugNPay::Transaction::TransId::getTransIdV1(
      { username  => $ipcusername,
        orderId   => $ipcorderid,
        processor => $processor
      }
    );
  }

  my $ipcprocessid = $$;

  my $hostnm = hostname;
  $hostnm =~ s/[^0-9a-zA-Z]//g;
  $ipcprocessid = $ipcprocessid . $hostnm;

  my $ipcprocessor = "transid";

  my %datainfo = ( "username", "$ipcusername", "orderid", "$ipcorderid" );

  my ( undef, $ipctrans_time ) = &miscutils::gendatetime_only();

  my $method = "processormsg";

  my $dbhmisc = &miscutils::dbhconnect("pnpmisc");

  my $sth = $dbhmisc->prepare(
    qq{
        delete from processormsg
        where processid=?
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth->execute($ipcprocessid) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth->finish;

  my $sth2 = $dbhmisc->prepare(
    q{
        insert into processormsg
        (trans_time,processid,processor,username,orderid,status,message)
        values (?,?,?,?,?,?,?)
        }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
  $sth2->execute( "$ipctrans_time", "$ipcprocessid", "$ipcprocessor", "$ipcusername", "$ipcorderid", "pending", "$processor" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
  $sth2->finish;

  my $ipcstatus     = "";
  my $ipcinvoicenum = "";
  my $ipcresponse   = "";

  my $delay = 0.30;

  for ( my $myi = 0 ; $myi < 50 ; $myi++ ) {
    &miscutils::mysleep($delay);
    $delay = 0.20;

    my $sth = $dbhmisc->prepare(
      qq{
          select status,invoicenum,message
          from processormsg
          where processid=?
          and processor=?
          and orderid=?
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
    $sth->execute( "$ipcprocessid", "$ipcprocessor", "$ipcorderid" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
    ( $ipcstatus, $ipcinvoicenum, $ipcresponse ) = $sth->fetchrow;
    $sth->finish;

    if ( $ipcstatus eq "" ) {
      $ipcstatus   = "failure";
      $ipcresponse = "mysql connection is down";
      last;
    } elsif ( $ipcstatus !~ /(pending|locked)/ ) {
      my $sth = $dbhmisc->prepare(
        qq{
            delete from processormsg
            where processid=?
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute($ipcprocessid) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sth->finish;

      last;
    } else {
      $ipcresponse = "";
    }

  }

  #$dbhmisc->disconnect; # 20170421 DCP

  if ( $ipcresponse eq "" ) {
    my $transseqnum = "";
    $method = "mysql";

    my $dbh = &miscutils::dbhconnect("pnpmisc");

    my $sth2 = $dbh->prepare(
      qq{
          select username,transseqnum
          from transid
          where username=?
          }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $dbi::errstr", %datainfo );
    $sth2->execute("$ipcusername") or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $dbi::errstr", %datainfo );
    ( my $chkusername, $transseqnum ) = $sth2->fetchrow;
    $sth2->finish;

    $transseqnum = ( $transseqnum % 100000000 ) + 1;

    if ( $chkusername eq "" ) {
      my $sth = $dbh->prepare(
        qq{
            insert into transid
            (username,transseqnum)
            values (?,?)
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( "$ipcusername", "$transseqnum" )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sth->finish;
    } else {
      my $sth = $dbh->prepare(
        qq{
            update transid set transseqnum=?
            where username=?
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %datainfo );
      $sth->execute( "$transseqnum", "$ipcusername" ) or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %datainfo );
      $sth->finish;
    }

    #$dbh->disconnect;  # 20170421 DCP

    $ipcresponse = $transseqnum;
  }

  open( LOGFILE, ">>/home/p/pay1/batchfiles/transid/serverlogmsg.txt" );
  print LOGFILE "$ipcusername  $ipcorderid  $ipcresponse  $method\n";
  close(LOGFILE);

  return "$ipcresponse";
}

1;
