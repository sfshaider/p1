package PlugNPay::Processor::Route::LegacyChecks;
our $__moduleDigest = "3ae63e5f9d375419deb4deb6533c1f87d7a780e98c39c250cb920f4979a403e4";

use strict;
use PlugNPay::Database::QueryBuilder;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;
use PlugNPay::Processor;
use PlugNPay::Processor::Account;
use PlugNPay::Processor::Process::Verification;
use PlugNPay::Util::Array qw(inArray);
use miscutils; # can this be removed?

sub trans_admin {
  my $queryRef = shift;
  my $username = $queryRef->{'publisher-name'};
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $featureVersion = $gatewayAccount->getFeatures()->get('queryTransVersion');

  if ($featureVersion == 2 || $gatewayAccount->usesUnifiedProcessing()) {
    return &_new_trans_admin($queryRef);
  } else {
    return &_trans_admin($queryRef);
  }
}

sub _new_trans_admin {
  my $queryRef = shift;
  my $username = $queryRef->{'publisher-name'};
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $accountFeatures = $gatewayAccount->getFeatures();

  my %query = %{$queryRef};
  my %result = ();

  my $orderID = $query{'orderID'} || "";
  my $amount = $query{'card-amount'};
  my $mode = $query{'mode'};
  my $processor = &_getProcessorName($username, $query{'accttype'}, $query{'processor'});

  #No merchant order ID or bad GA
  if ($orderID eq "" || !$username) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "problem";
    $result{'MErrMsg'} = "Missing or invalid information sent, $mode transaction failed.";
    return %result;
  }

  #test mode
  if (($gatewayAccount->isDebug() || $gatewayAccount->isTest()) && $query{'card-name'} =~ /^(pnptest|pnp test|cardtest|card test)$/) {
    return &_test_mode_response($username,$orderID,$amount,$mode);
  }

  my %trans = &check_trans(%query);

  if ($trans{'Duplicate'} eq 'yes') {
    delete $trans{'pnp_transaction_id'};
    return %trans;
  }

  my $currency = $query{'currency'} || substr($trans{'amount'},0,3) || $gatewayAccount->getDefaultCurrency();
  my $price = sprintf("%3s %.2f",$currency,$amount+0.0001);

  my $industryCode = '';
  my $processorObj = new PlugNPay::Processor({'shortName' => $processor});

  eval{
    my $processorAccount = new PlugNPay::Processor::Account({'gatewayAccount' => $username, 'processorID' => $processorObj->getID()});
    $industryCode = $processorAccount->getSettingValue('industryCode');
  };

  my @extrafields = ();
  if ($industryCode eq "restaurant") {
   @extrafields = ('gratuity', $query{'gratuity'});
  }

  if ($query{'accttype'} =~ /^(checking|savings)$/) {
    @extrafields = (@extrafields,'accttype', "$query{'accttype'}");
  }

  if ($mode =~ /mark|postauth/i) {
    my ($authcurr, $authamt) = split(' ',$trans{'authamt'});
    if ( $amount > $authamt && $industryCode ne 'restaurant') {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} = "Value for card amount exceeds original authorization amount. Transaction could not be processed.";
      $result{'aux-msg'} = $amount . ' is more than auth amount: ' . $trans{'authamt'};
      $result{'resp-code'} = "P198";
    } elsif ($trans{'allow_mark'}) {
      my %res = &miscutils::sendmserver($username,"postauth"
                ,'accttype',"$query{'accttype'}"
                ,'order-id',$orderID
                ,'amount', $price
                ,'acct_code4',"$query{'acct_code4'}",
                ,'pnp_transaction_id', $trans{'pnp_transaction_id'}
                ,@extrafields
      );
      $result{'FinalStatus'} = $res{'FinalStatus'};
      $result{'MStatus'} = $res{'MStatus'};
      if ($res{'FinalStatus'} =~ /success|pending/i) {
        $result{'aux-msg'} = $orderID . ' has been successfully marked for settlement.';
      } else {
        $result{'MErrMsg'} = $orderID . ' was not marked successfully.';
        $result{'aux-msg'} = $res{'MErrMsg'};
      }
    } else {
      $result{'FinalStatus'} = 'problem';
      $result{'MStatus'} = 'problem';
      $result{'MErrMsg'} = 'INVALID OPERATION: Transaction is not allowed to be marked.';
      $result{'resp-code'} = 'P21';
    }
  } elsif ($mode eq 'return') {
    if ($trans{'allow_return'}) {
      %result = &miscutils::sendmserver($username,'return'
               ,'accttype',"$query{'accttype'}"
               ,'amount',$price
               ,'order-id',$orderID
               ,'acct_code4',"$query{'acct_code4'}"
               ,'pnp_transaction_ref_id', $trans{'pnp_transaction_id'}
      );
      if ($result{'FinalStatus'} =~ /success|pending/i) {
        if ( ($accountFeatures->get('convfee')) || ($accountFeatures->get('cardcharge')) ) {
          my %resultCF = &convfee_admin($username,'void',$orderID,$query{'accttype'},$amount,$currency,$query{'acct_code4'});
          if ($resultCF{'FinalStatus'} =~ /^success|problem$/) {
            $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
            $result{'MErrMsgCF'} = $resultCF{'MErrMsg'};
          }
        }
      }

      delete $result{'auth-code'};
    } elsif ($mode eq 'return' && !$trans{'allow_return'}) {
      if ($trans{'locked_flag'}) {
        $result{'FinalStatus'} = 'pending';
        $result{'MStatus'} = 'pending';
        $result{'MErrMsg'} = 'Transaction currently locked. It has already been queued for later processing.';
      } elsif ($trans{'void_flag'}) {
        $result{'FinalStatus'} = 'problem';
        $result{'MStatus'} = 'problem';
        $result{'MErrMsg'} = 'Transaction has already been voided, cannot return.';
      } elsif ($trans{'setlret_flag'} == 1) {
        $result{'FinalStatus'} = 'problem';
        $result{'MStatus'} = 'problem';
        $result{'MErrMsg'} = 'Transaction already returned.';
      } elsif ($trans{'order-id'} eq '') {
        $result{'FinalStatus'} = 'problem';
        $result{'MStatus'} = 'problem';
        $result{'MErrMsg'} = 'Order ID does not exist as a previous order.  It may not be marked for return.';
      } elsif ($trans{'allow_void'}) {
        my %res = &miscutils::sendmserver($username,'void'
                ,'accttype',"$query{'accttype'}"
                ,'txn-type', 'auth'
                ,'order-id', $orderID
                ,'amount', $price
                ,'pnp_transaction_id', $trans{'pnp_transaction_id'}
                ,'acct_code4',"$query{'acct_code4'}"
        );

        $result{'FinalStatus'} = $res{'FinalStatus'};
        $result{'MStatus'} = $res{'MStatus'};
        if ($result{'FinalStatus'} eq 'success') {
          $result{'MErrMsg'} = "";
          $result{'aux-msg'} = $orderID . ' has been successfully voided.';
          if ( ($accountFeatures->get('convfee')) || ($accountFeatures->get('cardcharge')) ) {
            my %resultCF = &convfee_admin('void',$orderID,$query{'accttype'},$amount,$currency,$query{'acct_code4'});
            if ($resultCF{'FinalStatus'} =~ /^success|problem$/) {
              $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
              $result{'MErrMsgCF'} = $resultCF{'MErrMsg'};
            }
          }
        } else {
          $result{'aux-msg'} = $res{'MErrMsg'};
          $result{'MErrMsg'} = $orderID . ' was not voided successfully.';
        }
      } else {
        $result{'FinalStatus'} = 'problem';
        $result{'MStatus'} = 'problem';
        $result{'MErrMsg'} = 'Unable to perform return on desired transaction.';
      }

      delete $result{'auth-code'};
    }
  } elsif ($query{'mode'} eq 'reauth') {
    if ($trans{'allow_reauth'}) {
      my %res = &miscutils::sendmserver($username,'reauth'
                ,'order-id',$orderID
                ,'amount', $price
                ,'pnp_transaction_ref_id', $trans{'pnp_transaction_id'}
                ,'acct_code4',"$query{'acct_code4'}",
                @extrafields
      );

      $result{'refnumber'} = $res{'refnumber'};
      if ($res{'checknum'} ne "") {
        $result{'checknum'} = $res{'checknum'};
      }
      if ($res{'merchant_id'} ne "") {
        $result{'merchant_id'} = $res{'merchant_id'};
      }

      $result{'FinalStatus'} = $res{'FinalStatus'};
      $result{'MStatus'} = $res{'MStatus'};
      if ($res{'FinalStatus'} eq 'success') {
        if ($query{'reauthtype'} ne 'authonly') {
          my %pres = &miscutils::sendmserver($username,"postauth"
                ,'order-id',$orderID
                ,'orderID',$orderID
                ,'amount', $price
                ,'pnp_transaction_id', $res{'pnp_transaction_id'}
                ,'acct_code4',"$query{'acct_code4'}",
                @extrafields
          );

          $result{'aux-msg'} = $orderID . ' has been successfully reauthorized for ' . $price . '.';
          if ($pres{'FinalStatus'} =~ /success|pending/i) {
            $result{'aux-msg'} .= ' The transaction was successfully marked.';
          }
        }
      } else {
        $result{'MErrMsg'} = 'Failed reauthorization for ' . $orderID;
      }
    } else {
      $result{'FinalStatus'} = 'problem';
      $result{'MStatus'} = 'problem';
      $result{'MErrMsg'} = 'Transaction cannot be reauthorized.';
    }
  } elsif ($mode eq 'void') {
    if ($trans{'allow_void'}) {
      my $txntype = $query{'txn-type'} || 'auth';
      my %res = &miscutils::sendmserver($username,'void'
            ,'accttype',"$query{'accttype'}"
            ,'txn-type', $txntype
            ,'order-id', $orderID
            ,'orderID', $orderID
            ,'amount', $price
            ,'pnp_transaction_id', $trans{'pnp_transaction_id'}
            ,'acct_code4',"$query{'acct_code4'}"
      );
      $result{'FinalStatus'} = $res{'FinalStatus'};
      $result{'MStatus'} = $res{'MStatus'};
      if ($result{'FinalStatus'} eq 'success') {
        $result{'aux-msg'} = $orderID . ' has been successfully voided.';
        if ($result{'FinalStatus'} =~ /success/) {
          if ( ($accountFeatures->get('convfee')) || ($accountFeatures->get('cardcharge')) ) {
            my %resultCF = &convfee_admin('void',$orderID,$query{'accttype'},$amount,$query{'currency'},$query{'acct_code4'});
            if ($resultCF{'FinalStatus'} =~ /^success|problem$/) {
              $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
              $result{'MErrMsgCF'} = $resultCF{'MErrMsg'};
            }
          }
        }
      } else {
        $result{'MErrMsg'} = $orderID . ' was not voided successfully.';
        $result{'aux-msg'} = $res{'MErrMsg'};
      }
    } else {
      $result{'FinalStatus'} = 'problem';
      $result{'MStatus'} = 'problem';
      $result{'MErrMsg'} = 'Transaction cannot be voided.';
    }
  } else {
    $result{'FinalStatus'} = 'problem';
    $result{'MStatus'} = 'problem';
    $result{'MErrMsg'} = 'Invalid Action';
  }

  delete $result{'pnp_transaction_id'};
  return %result;
}

sub _trans_admin {
  my $queryRef = shift;
  my %query = %{$queryRef};

  my ($mark_flag,$void_flag,$mark_ret_flag,$settled_flag,$setlret_flag,$auth_flag,$reauth_flag,$pending_flag);
  my ($chkun,$accttype,$merchantid,$processor,$proc_type,$company,$currency,$custstatus,$testmode,$txntypevoid,$txntyperetry,$industrycode);
  my %result = ();
  my $username = $query{'publisher-name'};

  my $accountFeatures = new PlugNPay::Features($username,'general');

  if (($query{'orderID'} eq "") || ($query{'publisher-name'} eq "")) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "problem";
    $result{'MErrMsg'} = "Missing information. $query{'mode'} transaction failed.";
    return %result;
  }

  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  $processor = &_getProcessorName($username, $query{'accttype'}, $query{'processor'});

  my $processorAccount = new PlugNPay::Processor::Account({'processorName' => $processor, 'gatewayAccount' => $username});
  $chkun = $gatewayAccount->getGatewayAccountName();
  $merchantid = $processorAccount->getSettingValue('mid');
  $proc_type = $processorAccount->getSettingValue('authType');
  $company = $gatewayAccount->getCompanyName();
  $currency = $processorAccount->getSettingValue('currency');
  my $status = $gatewayAccount->getStatus();
  $testmode = $gatewayAccount->getTestMode();

  if ($processor =~ /^(visanet|global|fdms|fdmsnorth|fdmsrc|paytechtampa|paytechsalem|nova|fdmsintl|fifththird|maverick|moneris|mercury|elavon)$/) {
    $industrycode = $processorAccount->getSettingValue('industryCode');
  }

  if (($accountFeatures->get('demoacct') == 1) && ($query{'gratuity'} > 0)) {
    $industrycode = 'restaurant';
  }

  if ($chkun eq "") {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "problem";
    if ($query{'merchant'} ne "") {
      $result{'MErrMsg'} = "Missing/Invalid variable merchant. Transaction could not be processed.";
      $result{'resp-code'} = "P98";
    }
    else {
      $result{'MErrMsg'} = "Missing/Invalid variable publisher-name. Transaction could not be processed.";
      $result{'resp-code'} = "P98";
    }
    return %result;
  }

  if ((($custstatus eq "debug") || ($testmode eq "yes") && ($query{'card-name'} =~ /^(pnptest|pnp test|cardtest|card test)$/) )) {
    return &_test_mode_response($query{'publisher-name'},$query{'orderID'},$query{'card-amount'},$query{'mode'});
  }

  my $timeadjust = (180 * 24 * 3600);
  my (undef,$datestr1,$timestr1) = &miscutils::gendatetime_only("-$timeadjust");

  my $orderid = $query{'orderID'};
  $username = $query{'publisher-name'};

  my @array = %query;
  my %trans = &check_trans(@array);

  if (($query{'client'} eq "mm") && ($query{'mode'} eq "tran_status")) {
    return %trans;
  }


  if ($trans{'Duplicate'} eq "yes" && ($accountFeatures->get('allow_multret') ne "1" || $query{'mode'} ne "return")) {
    return %trans;
  }

  my $env = new PlugNPay::Environment();
  my $remoteaddr = $env->get('PNP_CLIENT_IP');

  if ($query{'mode'} eq "mark") {
    my $test = substr($trans{'authamt'},4);
    if ($test eq "") {
      $test = substr($trans{'amount'},4);
    }
    if (($test > $query{'card-amount'}) && ($industrycode ne "restaurant")) {
      $query{'mode'} = "reauth";
    }

    if (($query{'card-amount'} > $test) && ($industrycode ne "restaurant") && ($test ne "") && ($processor ne "fifththird")) {
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
      my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
      my $date = sprintf('%04d%02d%02d',$year+1900,$mon+1,$mday);
      open(DEBUG,">>","/home/pay1/database/remotepm_debug.transadmin.$date.log");
      print DEBUG "DATE:$now, IP:$remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, PID:$$, OID:$query{'orderID'}, ";
      print DEBUG "PN:$query{'publisher-name'}, CA:$query{'card-amount'}, AuthAMT:$test\n";
      close (DEBUG);

      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} = "Value for card amount exceeds original authorization amount. Transaction could not be processed.";
      $result{'resp-code'} = "P198";

      return %result;
    }
  }

  if ($query{'mode'} eq "return") {
    my $tmpcurr = substr($trans{'amount'},0,3);
    my $env = new PlugNPay::Environment();
    if ($query{'currency'} eq "") {
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
      my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
      $query{'currency'} = substr($trans{'amount'},0,3);
      my $date = sprintf('%04d%02d%02d',$year+1900,$mon+1,$mday);
      open(DEBUG,">>","/home/pay1/database/remotepm_debug.currency.$date.log");
      print DEBUG "DATE:$now, IP:$remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, PID:$$, RM:$ENV{'REQUEST_METHOD'}, ";
      print DEBUG "Currency Missing Test 1\n";
      close (DEBUG);
    }

    if ($query{'currency'} eq "") {
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
      my $now = sprintf("%04d%02d%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
      $query{'currency'} = "usd";
      my $date = sprintf('%04d%02d%02d',$year+1900,$mon+1,$mday);
      open(DEBUG,">>","/home/pay1/database/remotepm_debug.currency.$date.log");
      print DEBUG "DATE:$now, IP:$remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, PID:$$, RM:$ENV{'REQUEST_METHOD'}, ";
      print DEBUG "Currency Missing Test 2\n";
      close (DEBUG);
    }

    if (($query{'currency'} ne $tmpcurr)  && ($trans{'allow_return'} == 1)) {
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
      my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
      my $date = sprintf('%04d%02d%02d',$year+1900,$mon+1,$mday);
      open(DEBUG,">>","/home/pay1/database/remotepm_debug.currency.$date.log");
      print DEBUG "DATE:$now, IP:$remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, PID:$$, RM:$ENV{'REQUEST_METHOD'}, ";
      print DEBUG "UN:$query{'publisher-name'}, OID:$query{'orderID'}, CURR:$query{'currency'}, TMPCURR:$tmpcurr, ";
      print DEBUG "Currency Mismatch:fixed\n";
      close (DEBUG);
      $query{'currency'} = substr($trans{'amount'},0,3);
    }

    my (undef,$datestr) = &miscutils::gendatetime_only();
    my $orderid = $query{'orderID'};
    my $amount = $query{'card-amount'};
    my $price = sprintf("%3s %.2f","$query{'currency'}",$amount+0.0001);
    my $username = $query{'publisher-name'};

    my $testamt = substr($trans{'authamt'},4);
    if ($testamt eq "") {
      $testamt = substr($trans{'amount'},4);
    }

    if ($trans{'allow_return'} == 1) {
      %result = &miscutils::sendmserver("$username",'return'
               ,'accttype',"$query{'accttype'}"
               ,'amount',"$price"
               ,'order-id',"$orderid"
               ,'acct_code4',"$query{'acct_code4'}"
               );
      ###  Conv. Fee Return
      if ($result{'FinalStatus'} =~ /success|pending/) {
        if ( ($accountFeatures->get('returnfee')) && (($accountFeatures->get('convfee')) || ($accountFeatures->get('cardcharge'))) ) {
          my %resultCF = &convfee_admin('return',$orderid,$query{'accttype'},$amount,$query{'currency'},$query{'acct_code4'});
          if ($resultCF{'FinalStatus'} =~ /^success|problem$/) {
            $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
            $result{'MErrMsgCF'} = $resultCF{'MErrMsg'};
          }
        }
      }
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      if ($trans{'locked_flag'} == 1) {
        $result{'FinalStatus'} = "";
        $result{'MStatus'} = "";
        $result{'MErrMsg'} = "";
        my $dbh = &miscutils::dbhconnect("misccrap");

        my $sth = $dbh->prepare(qq{
            select username
            from return_que
            where username=? and orderid=?
          }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query,%trans);
        $sth->execute("$username","$orderid") or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr",%query,%trans);
        my ($test) = $sth->fetchrow;
        $sth->finish;
        if ($test ne "") {
          $result{'FinalStatus'} = "pending";
          $result{'MStatus'} = "pending";
          $result{'MErrMsg'} = "Transaction currently locked.  It has already been queued for later processing.";
        }
        else {
          my $sth = $dbh->prepare(qq{
              insert into return_que
              (username,orderid,trans_date,amount,operation)
              values (?,?,?,?,?)
            }) or $result{'FinalStatus'} = "problem";
          $sth->execute("$username","$orderid","$datestr","$price","return") or $result{'FinalStatus'} = "problem";
          $sth->finish;
        }
        $dbh->disconnect;

        if ($result{'FinalStatus'} ne "problem") {
          $result{'FinalStatus'} = "pending";
          $result{'MStatus'} = "pending";
          $result{'MErrMsg'} = "Transaction currently locked.  It has been queued for later processing.";
        }
        else {
          $result{'FinalStatus'} = "problem";
          $result{'MStatus'} = "problem";
          $result{'MErrMsg'} = "Transaction currently locked.  It may not be returned.";
        }
      }
      elsif ($trans{'void_flag'} == 1) {
        $result{'MErrMsg'} = "Transaction already voided.  It may not be returned.";
      }
      elsif ($trans{'setlret_flag'} == 1) {
        $result{'MErrMsg'} = "Transaction already returned.";
      }
      elsif ($trans{'order-id'} eq "") {
        $result{'MErrMsg'} = "Order ID does not exist as a previous order.  It may not be marked for return.";
      }
      elsif ($trans{'allow_void'} == 1) {
        if ($testamt > $query{'card-amount'}) {
          $result{'MErrMsg'} = "Transaction not yet settled.  It may not be voided for a lower amount.";
        }
        else {
          $result{'MErrMsg'} = "Transaction not yet settled.  It may not be returned.";
          my $txntype = $query{'txn-type'};
          if ($txntype eq "") {
            $txntype = "auth";
          }
          my $username = $query{'publisher-name'};
          my %res = &miscutils::sendmserver("$username",'void'
                ,'accttype',"$query{'accttype'}"
                ,'txn-type', "$txntype"
                ,'order-id', "$orderid"
                ,'amount', "$price"
                ,'acct_code4',"$query{'acct_code4'}"
                );

          $result{'FinalStatus'} = $res{'FinalStatus'};
          $result{'MStatus'} = $res{'MStatus'};
          if ($result{'FinalStatus'} eq "success") {
            $result{'MErrMsg'} = "";
            $result{'aux-msg'} = "$orderid has been successfully voided.";
          }
          else {
            $result{'MErrMsg'} = "$orderid was not voided successfully.";
          }
          if ($result{'FinalStatus'} =~ /success/) {
            if ( ($accountFeatures->get('convfee')) || ($accountFeatures->get('cardcharge')) ) {
              my %resultCF = &convfee_admin('void',$orderid,$query{'accttype'},$amount,$query{'currency'},$query{'acct_code4'});
              if ($resultCF{'FinalStatus'} =~ /^success|problem$/) {
                $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
                $result{'MErrMsgCF'} = $resultCF{'MErrMsg'};
              }
            }
          }

        }
      }
      else {
        $result{'MErrMsg'} = "Transaction could not be returned. Err 1.";
      }
    }
    if ( ($accountFeatures->get('returnfee')) && (($accountFeatures->get('convfee')) || ($accountFeatures->get('cardcharge'))) ) {
      if (! exists $result{'FinalStatusCF'}) {
        $result{'FinalStatusCF'} = "problem";
        $result{'MErrMsgCF'} = "Fee portion of transaction was unable to be returned.";
      }
    }

    delete $result{'auth-code'};
    return %result;
  }
  elsif ($query{'mode'} eq "mark") { ### Returns Pending on Success
    if ($trans{'allow_mark'} == 1) {
      my @extrafields = ();
      if ($industrycode eq "restaurant") {
        @extrafields = ('gratuity', $query{'gratuity'});
      }
      if ($query{'accttype'} =~ /^(checking|savings)$/) {
        @extrafields = (@extrafields,'accttype', "$query{'accttype'}");
      }

      if ($query{'currency'} eq "") {
        $query{'currency'} = "usd";
      }
      my $price = sprintf("%3s %.2f","$query{'currency'}",$query{'card-amount'}+0.0001);
      my %res = &miscutils::sendmserver($query{'publisher-name'},"postauth"
                ,'accttype',"$query{'accttype'}"
                ,'order-id',$query{'orderID'}
                ,'amount', $price
                ,'acct_code4',"$query{'acct_code4'}",
                 @extrafields
                );

      $result{'FinalStatus'} = $res{'FinalStatus'};
      $result{'MStatus'} = $res{'MStatus'};
      if (($result{'FinalStatus'} eq "pending") || ($result{'FinalStatus'} eq "success")) {
        if (($query{'publisher-name'} =~ /^(icommerceg|icgoceanba|icgcrossco)$/) && ($query{'subacct'} =~ /^(vmicard)$/)) {
          my $dbh = &miscutils::dbhconnect('pnpmisc');
           my $sth_history = $dbh->prepare(qq{
              update email
              set operation=?
              where orderid=?
            }) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
          $sth_history->execute("postauth","$query{'orderID'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%query);
          $sth_history->finish;
          $dbh->disconnect;
        }
        $result{'aux-msg'} = "$query{'orderID'} has been successfully marked for settlement.";
      }
      else {
        $result{'MErrMsg'} = "$query{'orderID'} was not marked successfully.";
        $result{'aux-msg'} = "$res{'MErrMsg'}";
        $result{'resp-code'} = "P22";
      }
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Transaction may not be marked.";
      $result{'resp-code'} = "P21";
    }
    return %result;
  }
  elsif ($query{'mode'} eq "reauth") {
    my @extrafields = ();
    if ($query{'accttype'} =~ /^(checking|savings)$/) {
      @extrafields = ('accttype', "$query{'accttype'}");
    }

    if ($trans{'allow_reauth'} == 1) {
      my ($curr,$test) = split('\ ',$trans{'authamt'});
      if ($test eq "") {
        ($curr,$test) = split('\ ',$trans{'amount'});
      }
      $trans{'amount'} = $test;
      $curr =~ tr/A-Z/a-z/;
      $curr =~ s/[^a-z]//g;
      $curr = substr($curr,0,3);

      $query{'currency'} = $curr;
      if ($query{'currency'} eq "") {
        $query{'currency'} = "usd";
      }

      if (($query{'card-amount'} >= $trans{'amount'}) && ($processor ne "fifththird")) {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} = "Card amount,$query{'card-amount'} greater than original authorized amount,$trans{'amount'}. Transaction may not be reauthorized.";
      }
      else {
        my (%res);
        my $price = sprintf("%3s %.2f","$query{'currency'}",$query{'card-amount'}+0.0001);
        %res = &miscutils::sendmserver($query{'publisher-name'},"reauth"
                ,'order-id',$query{'orderID'}
                ,'amount', $price
                ,'acct_code4',"$query{'acct_code4'}",
                @extrafields);

        $result{'refnumber'} = $res{'refnumber'};
        if ($res{'checknum'} ne "") {
          $result{'checknum'} = $res{'checknum'};
        }
        if ($res{'merchant_id'} ne "") {
          $result{'merchant_id'} = $res{'merchant_id'};
        }

        if (($res{'FinalStatus'} eq "success") && ($query{'reauthtype'} ne "authonly")) {
          %res = &miscutils::sendmserver($query{'publisher-name'},"postauth"
                ,'order-id',$query{'orderID'}
                ,'amount', $price
                ,'acct_code4',"$query{'acct_code4'}",
                @extrafields);
        }
        $result{'FinalStatus'} = $res{'FinalStatus'};
        $result{'MStatus'} = $res{'MStatus'};
        if ($result{'FinalStatus'} =~ /^pending|success$/) {
          $result{'aux-msg'} = "$query{'orderID'} has been successfully reauthed for $price.";
        }
        else {
          $result{'MErrMsg'} = "$query{'orderID'} was not reauthed successfully.";
        }
      }
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Transaction may not be reauthorized.";
    }
    return %result;
  }
  elsif ($query{'mode'} eq "void") { ### Returns success on success
    if ($trans{'allow_void'} == 1) {
      my $orderid = $query{'orderID'};
      my $txntype = $query{'txn-type'};

      if ($txntype eq "") {
        $txntype = "auth";
      }

      if ($query{'currency'} eq "") {
        $query{'currency'} = "usd";
      }

      my $amount = sprintf("%3s %.2f","$query{'currency'}",$query{'card-amount'}+0.0001);

      my $username = $query{'publisher-name'};
      my %res = &miscutils::sendmserver("$username",'void'
            ,'accttype',"$query{'accttype'}"
            ,'txn-type', "$txntype"
            ,'order-id', "$orderid"
            ,'amount', "$amount"
            ,'acct_code4',"$query{'acct_code4'}"
            );

      $result{'FinalStatus'} = $res{'FinalStatus'};
      $result{'MStatus'} = $res{'MStatus'};
      if ($result{'FinalStatus'} eq "success") {
        $result{'aux-msg'} = "$orderid has been successfully voided.";
      }
      else {
        $result{'MErrMsg'} = "$orderid was not voided successfully.";
      }
      if ($result{'FinalStatus'} =~ /success/) {
        if ( ($accountFeatures->get('convfee')) || ($accountFeatures->get('cardcharge')) ) {
          my %resultCF = &convfee_admin('void',$orderid,$query{'accttype'},$amount,$query{'currency'},$query{'acct_code4'});
          if ($resultCF{'FinalStatus'} =~ /^success|problem$/) {
            $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
            $result{'MErrMsgCF'} = $resultCF{'MErrMsg'};
          }
        }
      }
    }
    else {
      if ($trans{'order-id'} eq "") {
        $result{'MErrMsg'} = "Transaction orderid does not exist and may not be voided."
      }
      else {
        $result{'MErrMsg'} = "Transaction may not be voided."
      }
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
    }
    return %result;
  }

  return %result;
}

sub _test_mode_response {
  my $merchant = shift;
  my $orderID = shift;
  my $amount = shift;
  my $mode = shift;
  my %result = ();

  $result{'MErrMsg'} = "SYSTEM IN DEBUG MODE:";
  if ($mode =~ /mark|return|credit|postauth/i) {
    if ($amount ne "" && $orderID ne "" && $merchant ne "") {
      $result{'FinalStatus'} = "pending";
      $result{'MStatus'} = "pending";
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} .= "Missing informationr: $mode transaction failed";
    }
  } elsif ($mode eq "void") {
   if ($merchant ne "" && $orderID ne "") {
      $result{'FinalStatus'} = "success";
      $result{'MStatus'} = "success";
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} .= "Missing information. Transaction could not be voided.";
    }
  }

  return %result;
}

sub convfee_admin {
  my ($username,$mode,$orderid,$accttype,$amount,$currency,$acct_code4) = @_;
  my ($trans_date,$trans_time,$price,$operation);
  my ($db_trans_date,$db_trans_time,$db_price);
  my %result = ();

  my $accountFeatures = new PlugNPay::Features($username,'general');

  my $surcharge_flag = 0;
  my $feeacct = "";
  if ($accountFeatures->get('convfee')) {
    my $cf = new PlugNPay::ConvenienceFee($username);
    $feeacct = $cf->getChargeAccount();
    if ($cf->isSurcharge()) {
      $surcharge_flag = 1;
    }
  }
  elsif ($accountFeatures->get('cardcharge')) {
    my $coa = new PlugNPay::COA($username);
    $feeacct = $coa->getChargeAccount();
    if ($coa->isSurcharge()) {
      $surcharge_flag = 1;
    }
  }
  if ($surcharge_flag != 1) {
    ###  Merchant is configured for either COA or Conv Fee.
    ### Locate Conv Fee Tran.
    my $timeadjust = (185 * 24 * 3600);
    my ($dummy,$datestr,$timestr) = &miscutils::gendatetime("-$timeadjust");

    my $dbh = &miscutils::dbhconnect("pnpdata","","$username"); ## Trans_Log

    my $now = new PlugNPay::Sys::Time()->nowInFormat('database');
    my $today = substr($now,0,8);

    my $qb = new PlugNPay::Database::QueryBuilder();

    my $range = $qb->generateDateRange({ start_date => $datestr, end_date => $today });
    my $params = $range->{'params'};

    ## Get data from original transaction
    my $sth = $dbh->prepare(qq{
      select trans_date,trans_time,amount,operation
      from trans_log
      where trans_date in ($params)
      and orderid=?
      and username=?
      order by operation
    }) or die "Can't do: $DBI::errstr";
    $sth->execute(@{$range->{'values'}},$orderid,$username) or die "Can't execute: $DBI::errstr";
    $sth->bind_columns(undef,\($db_trans_date,$db_trans_time,$db_price,$operation));
    while($sth->fetch) {
      if ($operation eq 'auth') {
        $trans_time = $db_trans_time;
        $trans_date = $db_trans_date;
        $price = $db_price;
      }
      elsif ($operation =~ /^postauth|reauth$/) {
        $price = $db_price;
      }
    }
    $sth->finish;

    my $percent_returned = 0;
    my $temp_amount = $amount;
    $temp_amount =~ s/[^0-9\.]//g;
    my ($currency,$original_amount) = split(/ /,$price);
    if ($original_amount > 0) {
      $percent_returned = $temp_amount/$original_amount;
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Fee transaction not found or amount equals 0.";
      $dbh->disconnect;
      return %result;
    }

    my $ac3 = "%$orderid%";
    my $starttimestr =  &miscutils::timetostr(&miscutils::strtotime($trans_time)-10*60);
    my $endtimestr = &miscutils::timetostr(&miscutils::strtotime($trans_time)+10*60);
    my $enddate = substr($endtimestr,0,8);

    $range = $qb->generateDateRange({ start_date => $trans_date, end_date => $enddate });
    $params = $range->{'params'};

    ### locate conv fee transaction
    $sth = $dbh->prepare(qq{
        select orderid,amount
        from trans_log
        where trans_date in ($params)
        and username=?
        and trans_time>=?
        and trans_time<=?
        and acct_code3 LIKE ?
    }) or die "Can't do: $DBI::errstr";
    $sth->execute(@{$range->{'values'}},$feeacct,$starttimestr,$endtimestr,"$ac3") or die "Can't execute: $DBI::errstr";
    my ($convfee_orderid,$convfee_price) = $sth->fetchrow;
    $sth->finish;
    my ($convfee_currency,$convfee_amount) = split(/ /,$convfee_price);
    $dbh->disconnect;

    if ($convfee_orderid > 0) {
      my %data = ();
      $data{'orderID'} = $convfee_orderid;
      $data{'publisher-name'} = $feeacct;
      $data{'accttype'} = $accttype;
      $data{'mode'} = "return";

      my @array = %data;
      my %trans = &miscutils::check_trans(@array);

      my $price = sprintf("%3s %.2f",$convfee_currency,$convfee_amount*$percent_returned+0.0001);

      if (($mode eq "return") && ($trans{'allow_return'} == 1)) {
        %result = &miscutils::sendmserver("$feeacct",'return'
             ,'accttype',$data{'accttype'}
             ,'amount',$price
             ,'order-id',$data{'orderID'}
             ,'acct_code4',$acct_code4
             );
        if($result{'FinalStatus'} !~ /success|pending/) {
          $result{'MErrMsg'} = "Return of fee transaction failed.";
        }
      }
      elsif (($mode eq "void") && ($trans{'allow_void'} == 1)) {
        %result = &miscutils::sendmserver("$feeacct",'void'
             ,'accttype',$data{'accttype'}
             ,'amount',$price
             ,'order-id',$data{'orderID'}
             ,'acct_code4',$acct_code4
             );
        if($result{'FinalStatus'} !~ /success|pending/) {
          $result{'MErrMsg'} = "Void of fee transaction failed.";
        }
      }
      else {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'} = "Fee $mode not allowed.";
      }
    }
    else {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = "Fee transaction not found.";
    }
  }
  return %result;
}

# check_trans - check to see if a transaction is allowed
# input: transaction hash a la mckutils
# output: changes depending on the outcome
##  if the transaction is not allowed, FinalStatus will have a value and the response is a result hash like the following:
##
##      $result{'FinalStatus'} = "problem";
##      $result{'MStatus'} = "problem";
##      $result{'MErrMsg'} .= "Missing information. Transaction could not be marked.";
##
##  if the transaction is allowed, a number of flags are returned (not conclusive):
##
##      $trans{'authamt'}
##      $trans{'auth_flag'}
##      $trans{'settled_flag'}
##      $trans{'void_flag'}
##      $trans{'reauth_flag'}
##      $trans{'setlret_flag'}
##      $trans{'settled_flag'}
##
sub check_trans {
  my %query = @_;
  require PlugNPay::GatewayAccount;
  my $username = $query{'publisher-name'};
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  my $featureVersion = $gatewayAccount->getFeatures()->get('queryTransVersion');

  if ($featureVersion == 2 || $gatewayAccount->usesUnifiedProcessing()) {
    my $verifier = new PlugNPay::Processor::Process::Verification();
    my $responses = $verifier->checkTransaction($username,\%query);
    my $response = $responses->{$query{'orderID'}};
    if (ref($response) ne 'HASH' && ref($responses) eq 'HASH') {
      my @keys = keys %{$responses};
      $response = $responses->{$keys[0]} || {};
    }
    return %{$response};
  } else {
    my $result = _legacyCheckTrans({
      orderId => $query{'orderID'},
      usernameParameter => $query{'merchant'} ? 'merchant' : 'publisher-name',
      username => $query{'merchant'} || $query{'publisher-name'},
      accountType => $query{'accttype'},
      processor => $query{'processor'},
      operation => $query{'mode'},
      amount => $query{'card-amount'},
      cardName => $query{'card-name'}
    });

    # the following is to ensure compatibility
    $result->{'order-id'} = $result->{'orderID'} = $result->{'orderId'} if defined $result->{'orderId'};

    return %{$result};
  }
}

# this one is actually testable
sub _legacyCheckTrans {
  my $input = shift;
  my $testData = shift || {};

  my ($chkfinalstatus,$chkdescr);

  my $orderId = $input->{'orderId'};
  my $username = $input->{'username'};
  my $accountType = $input->{'accountType'};
  my $processor = $input->{'processor'};
  my $operation = $input->{'operation'};
  my $amount = $input->{'card-amount'};
  my $cardName = $input->{'card-name'};
  my $usernameParameter = $input->{'usernameParameter'};

  ########################################################################################################################
  # This section loads account and processor information, or uses $testData if test the necessary test data is provided. #
  ########################################################################################################################
  # load gateway account if test data is not provided (i.e. normal circumstances)
  my $gatewayAccountTest = defined $testData->{'exists'}   && defined $testData->{'custstatus'} &&
                           defined $testData->{'testmode'} && defined $testData->{'features'}   &&
                           defined $testData->{'processor'};
  my $ga = $gatewayAccountTest || new PlugNPay::GatewayAccount($username);
  my $exists     = $testData->{'exists'}     || $ga->exists();
  my $custstatus = $testData->{'custstatus'} || $ga->getStatus();
  my $testmode   = $testData->{'testmode'}   || $ga->isTestModeEnabled();

  my %feature; # use testData's features if present.
  if ($testData->{'features'}) {
    %feature = %{$testData->{'features'}};
  } else {
    %feature = %{$ga->getFeatures()->getFeatures()};
  }


  my $allowMultipleReturns = $feature{'allow_multret'} ? 1 : 0;

  if (!defined $processor || $processor eq '') {
    $processor = $testData->{'processor'} || $ga->getCardProcessor();
  }

  require PlugNPay::Processor;
  # testData reauthAllowd will short circuit causing processor not to be loaded.
  my $processorTest = defined $testData->{'reauthAllowed'};
  my $processorObj = $processorTest || new PlugNPay::Processor({'shortName' => $processor});
  my $reauthAllowed = $testData->{'reauthAllowed'} || $processorObj->getReauthAllowed();

  # get processor info to get $authType
  my $processorAccountTest = defined $testData->{'authType'} && defined $testData->{'isPetroleum'};
  my $processorAccount = $processorAccountTest  || new PlugNPay::Processor::Account({ gatewayAccount => $username, processorName => $processor });
  my $authType    = $testData->{'authType'}    || $processorAccount->getSettingValue('authType');
  my $isPetroleum = $testData->{'isPetroleum'} || ($processorAccount->getIndustry() eq 'petroleum');
  ########################################################################
  # This is the end of the section that loads account and processor data #
  ########################################################################

  if (!$exists) {
    my %result;
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'} = "problem";
    $result{'MErrMsg'} = sprintf('Invalid variable %s. Transaction could not be processed.', $usernameParameter);
    return \%result;
  }


  if ($custstatus eq "debug" || ($testmode eq "yes" && $cardName eq "pnptest")) {
    return _legacyCheckTransDebugMode({
      username  => $username,
      orderId   => $orderId,
      amount    => $amount,
      operation => $operation,
      testData  => $testData
    });
  }

  my $timeadjust = (180 * 24 * 3600);
  my (undef,$datestr) = &miscutils::gendatetime_only("-$timeadjust");

  #########################################################################
  # HEY LOOK AT ME I'M AN IMPORTANT LINE OF CODE AND I'M EASY TO OVERLOOK #
  #########################################################################
  $operation = $operation eq 'mark' ? 'postauth' : $operation;

  if (inArray($operation,['reauth','newreturn','return','returnprev','void','mark','postauth'])) {
    my $duplicateCheckResult = _legacyCheckTransDuplicateCheck({
      username             => $username,
      operation            => $operation,
      processor            => $processor,
      allowMultipleReturns => $allowMultipleReturns,
      orderId              => $orderId,
      allowMultipleReturns => $allowMultipleReturns,
      startDate            => $datestr
    },$testData);
    return $duplicateCheckResult if $duplicateCheckResult;
  }

  return _legacyCheckTransGetFlags({
    username             => $username,
    operation            => $operation,
    authType             => $authType,
    allowMultipleReturns => $allowMultipleReturns,
    orderId              => $orderId,
    startDate            => $datestr,
    accountType          => $accountType,
    reauthAllowed        => $reauthAllowed,
    allowMultipleReturns => $allowMultipleReturns,
    isPetroleum          => $isPetroleum
  }, $testData);
}

# returns a duplicate  response if there is a duplicate, or undef if it is not a duplicate.
sub _legacyCheckTransDuplicateCheck {
  my $input = shift;
  my $testData = shift || {};
  my $username             = $input->{'username'};
  my $orderId              = $input->{'orderId'};
  my $operation            = $input->{'operation'};
  my $allowMultipleReturns = $input->{'allowMultipleReturns'};
  my $processor            = $input->{'processor'};

  my ($chkfinalstatus,$chkdescr);

  my $dbs = new PlugNPay::DBConnection();
  if ($operation eq "reauth") {
    my $query = 'SELECT finalstatus,descr FROM trans_log FORCE INDEX(PRIMARY) WHERE orderid=? AND username=? AND operation=? AND finalstatus=? LIMIT 1';
    my $values = [$orderId,$username,'reauth','success'];
    $dbs->fetchallOrDie('pnpdata',$query,$values,{}, { callback => sub {
      my $row = shift;
      $chkfinalstatus = $row->{'finalstatus'};
      $chkdescr = $row->{'descr'};
    }, mockRows => $testData->{'mockDuplicateRows'} });
  } elsif ($operation eq "return" && $processor eq 'wirecard') {
    # this being wirecard specific seems rather odd, @dprice says it might be related to auth capture?  need to talk to @cprice
    # I'm wondering if wirecard had a high failure rate for returns
    my $query = 'SELECT finalstatus,descr FROM trans_log FORCE INDEX(PRIMARY) WHERE orderid=? AND username=? AND operation=? AND finalstatus IN (?,?,?) LIMIT 1';
    my $values = [$orderId,$username,'return','success','pending','locked'];
    $dbs->fetchallOrDie('pnpdata',$query,$values,{},{ callback => sub {
      my $row = shift;
      $chkfinalstatus = $row->{'finalstatus'};
      $chkdescr = $row->{'descr'};
    }, mockRows => $testData->{'mockDuplicateRows'} });
  } else { # all other operations
    my $query = 'SELECT finalstatus,descr FROM trans_log FORCE INDEX(PRIMARY) WHERE orderid=? AND username=? AND operation=? LIMIT 1';
    my $values = [$orderId,$username,$operation];
    $dbs->fetchallOrDie('pnpdata',$query,$values,{},{ callback => sub {
      my $row = shift;
      $chkfinalstatus = $row->{'finalstatus'};
      $chkdescr = $row->{'descr'};
    }, mockRows => $testData->{'mockDuplicateRows'} });
  }

  if (($operation ne "return" || !$allowMultipleReturns) && $chkfinalstatus ne '') {
    return {
      FinalStatus => "$chkfinalstatus",
      MStatus => "$chkfinalstatus",
      MErrMsg => "Duplicate $operation: $chkdescr",
      Duplicate => 'yes'
    };
  }

  return undef;
}

sub _legacyCheckTransDebugMode {
  my $input = shift;
  my $orderId   = $input->{'orderId'};
  my $amount    = $input->{'amount'};
  my $username  = $input->{'username'};
  my $operation = $input->{'operation'};

  my %result;

  $result{'debug'} = 1;
  $result{'MErrMsg'} = "SYSTEM IN DEBUG MODE:";

  if ($operation eq "return") {
    if ($orderId ne "" && $amount ne '' && $username ne '') {
      $result{'FinalStatus'} = "pending";
      $result{'MStatus'} = "pending";
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} .= "Missing information. Transaction could not be returned.";
    }
  } elsif ($operation eq "mark") {
    if ($orderId ne "" && $amount ne "" && $username ne "") {
      $result{'FinalStatus'} = "pending";
      $result{'MStatus'} = "pending";
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} .= "Missing information. Transaction could not be marked.";
    }
  } elsif ($operation eq "void") {
    if ($orderId ne '' && $username ne '') {
      $result{'FinalStatus'} = "success";
      $result{'MStatus'} = "success";
    } else {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'} = "problem";
      $result{'MErrMsg'} .= "Missing information. Transaction could not be voided.";
    }
  }

  return %result;
}

sub _legacyCheckTransGetFlags {
  my $input = shift;
  my $testData = shift || {};
  my $username      = $input->{'username'};
  my $authType      = $input->{'authType'};
  my $orderId       = $input->{'orderId'};
  my $startDate     = $input->{'startDate'};
  my $accountType   = $input->{'accountType'};
  my $reauthAllowed = $input->{'reauthAllowed'};
  my $isPetroleum   = $input->{'$isPetroleum'};
  my $allowMultipleReturns = $input->{'allowMultipleReturns'};

  my $queryInfo = _legacyCheckTransGetFlagsGenerateQuery($input);

  my $amount;
  my %trans;

  # reauth is the only one that starts out true.
  $trans{'reauth_flag'} = 1;

  my $dbs = new PlugNPay::DBConnection();

  $dbs->fetchallOrDie('pnpdata', $queryInfo->{'query'}, $queryInfo->{'values'}, {}, { callback => sub {
    my $row = shift; # the callback takes a row from the db as an argument

    # the following are expected to be in each row of the results or test data:
    my $operation   = $row->{'operation'};
    my $status      = $row->{'finalstatus'};
    my $amount      = $row->{'amount'};
    my $transDate   = $row->{'trans_date'};
    my $accountType = $row->{'accttype'};
    my $rowOrderId  = $row->{'orderid'};

    $trans{'orderId'} = $rowOrderId;
    $trans{'amount'} = $amount;

    if ($status eq 'success') {
      $trans{'authamt'} = $amount if ($operation eq 'auth');
      $trans{'auth_flag'} = 1     if (inArray($operation,['auth','forceauth']));
      $trans{'settled_flag'} = 1  if ($operation eq 'postauth');
      $trans{'void_flag'} = 1     if ($operation eq "void");
      $trans{'reauth_flag'} = 0   if (inArray($operation,['postauth','void','reauth']));
      $trans{'setlret_flag'} = 1  if ($operation eq "return");
      $trans{'settled_flag'} = 1  if ($operation eq "auth" && $authType eq "authcapture");
    }

    if ($status eq 'locked') {
      if ($operation eq "postauth") {
        $trans{'mark_flag'} = 0;
        $trans{'locked_flag'} = 1;
      }
    }

    if ($status eq 'pending') {
      if (inArray($operation,['postauth','return'])) {
        $trans{'mark_flag'} = 1;
      }
      if ($operation eq 'return') {
        $trans{'mark_ret_flag'} = 1;
      }
    }

    if ($operation eq 'storedata') {
      $trans{'storedata_flag'} = 1;
      $trans{'reauth_flag'} = 0;
    }
  }, mockRows => $testData->{'mockTransactionHistory' }});

  # Return
  if ($trans{'void_flag'} != 1 && $trans{'settled_flag'} == 1 && $trans{'mark_ret_flag'} == 0 && $trans{'locked_flag'} != 1) {
    if ($trans{'setlret_flag'} != 1 || $allowMultipleReturns eq "1") {
      $trans{'allow_return'} = 1;
    }
  }

  # Mark
  if ($trans{'auth_flag'} == 1 && $trans{'mark_flag'} == 0 && $trans{'void_flag'} !=1) {
    $trans{'allow_mark'} = 1;
  }

  # Re-auth

  if ($reauthAllowed == 1 && $accountType ne "checking" && $trans{'settled_flag'} == 0 && $trans{'reauth_flag'} == 1 && $trans{'storedata_flag'} == 0) {
    $trans{'allow_reauth'} = 1;
  }

  # Void
  if (($trans{'settled_flag'} == 0 || $isPetroleum) && $trans{'void_flag'} != 1 && $trans{'setlret_flag'} == 0 && $trans{'locked_flag'} != 1 && $trans{'storedata_flag'} == 0) {
    $trans{'allow_void'} = 1;
  }

  return \%trans;
}

sub _legacyCheckTransGetFlagsGenerateQuery {
  my $input = shift;
  my $username = $input->{'username'};
  my $orderId = $input->{'orderId'};
  my $startDate = $input->{'startDate'};
  my $accountType = $input->{'accountType'};

  my @queryValues;
  my @query;
  push @query, "SELECT orderid,amount,trans_date,trans_time,finalstatus,operation";
  push @query, "FROM trans_log FORCE INDEX(PRIMARY)"; # primary is orderid, username, operation, trans_time
  push @query, "WHERE orderid = ?";   push @queryValues, $orderId;
  push @query, "AND username  = ?";    push @queryValues, $username;

  my @operations = ('auth','postauth','return','void','reauth','retry','forceauth','storedata');
  push @query, 'AND operation IN (' . join(',',map {'?'} @operations) . ')';
  push @queryValues, @operations;

  my $qb = new PlugNPay::Database::QueryBuilder();
  my ($today) = &miscutils::gendatetime_only();
  my $dates = $qb->generateDateRange({ start_date => $startDate, end_date => $today });

  # we only want to look at
  push @query, sprintf('AND trans_date IN (%s)', $dates->{'params'});
  push @queryValues, @{$dates->{'values'}};

  push @query, "AND COALESCE(duplicate,'') = ?";
  push @queryValues, '';

  # matches against accttype, defaulting to 'credit' if null or empty string for what is in db and inputted into query.
  push @query, "AND COALESCE(NULLIF(accttype,''),'credit') = COALESCE(NULLIF(?,''),'credit')";
  push @queryValues, $accountType;

  # the following line used to be order by orderid, trans_time.  makes no sense to order by order id when the query is 'orderid = ?'
  push @query, "ORDER BY trans_time DESC";
  my $searchstr = join(' ',@query);

  return { query => $searchstr, values => \@queryValues};
}

sub _getProcessorName {
  my $username = shift;
  my $accountType = shift;
  my $processor = shift;
  my $gatewayAccount = new PlugNPay::GatewayAccount($username);
  if (!$processor) {
    if (lc($accountType) =~ /savings|checking/) {
      $processor = $gatewayAccount->getCheckProcessor();
    } else {
      $processor = $gatewayAccount->getCardProcessor();
    }
  }

  return $processor;
}

1;
