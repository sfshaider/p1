package PlugNPay::Batch::File;

use strict;
use miscutils;
use remote_strict;
use mckutils_strict;
use PlugNPay::Features;
use PlugNPay::Batch::ID;
use PlugNPay::Sys::Time;
use PlugNPay::CreditCard;
use PlugNPay::DBConnection;
use PlugNPay::Util::Status;
use PlugNPay::Batch::Results;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  return $self;
}

sub setBatchID {
  my $self = shift;
  my $batchID = shift;
  $self->{'batchID'} = $batchID;
}

sub getBatchID {
  my $self = shift;
  return $self->{'batchID'};
}

sub getLimit {
  my $self = shift;
  return $ENV{'BATCH_MAX_LIMIT_TRANSACTIONS'} || 200;
}

sub getLookBackTime {
  my $self = shift;
  return $ENV{'BATCH_LOOK_BACK_TIME'} || 30;
}

sub setTransTime {
  my $self = shift;
  my $transTime = shift;
  $self->{'transTime'} = $transTime;
}

sub getTransTime {
  my $self = shift;
  return $self->{'transTime'};
}

sub setOrderID {
  my $self = shift;
  my $orderID = shift;
  $self->{'orderID'} = $orderID;
}

sub getOrderID {
  my $self = shift;
  return $self->{'orderID'};
}

sub setProcessID {
  my $self = shift;
  my $processID = shift;
  $self->{'processID'} = $processID;
}

sub getProcessID {
  my $self = shift;
  return $self->{'processID'};
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

sub setStatus {
  my $self = shift;
  my $status = shift;
  $self->{'status'} = $status;
}

sub getStatus {
  my $self = shift;
  return $self->{'status'};
}

sub setLine {
  my $self = shift;
  my $line = shift;
  $self->{'line'} = $line;
}

sub getLine {
  my $self = shift;
  return $self->{'line'};
}

sub setSubAccount {
  my $self = shift;
  my $subAcct = shift;
  $self->{'subAcct'} = $subAcct;
}

sub getSubAccount {
  my $self = shift;
  return $self->{'subAcct'};
}

sub setPriority {
  my $self = shift;
  my $priority = shift;
  $self->{'priority'} = $priority;
}

sub getPriority {
  my $self = shift;
  return $self->{'priority'};
}

sub _setBatchFileFromRow {
  my $self = shift;
  my $row = shift;

  $self->{'batchID'}   = $row->{'batchid'};
  $self->{'transTime'} = $row->{'trans_time'};
  $self->{'orderID'}   = $row->{'orderid'};
  $self->{'processID'} = $row->{'processid'};
  $self->{'username'}  = $row->{'username'};
  $self->{'status'}    = $row->{'status'};
  $self->{'line'}      = $row->{'line'};
  $self->{'subAcct'}   = $row->{'subacct'};
  $self->{'priority'}  = $row->{'priority'};
}

#######################################
# Subroutine: loadTransactions
# -------------------------------------
# Description:
#   Loads the batch rows in batchfile 
# between the first and last order id
# specified where status is locked.
sub loadTransactions {
  my $self = shift;
  my $username = shift;
  my $batchID = shift;
  my $firstOrderID = shift;
  my $lastOrderID = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $batchRows = [];
  eval {
    my $sth = $dbs->prepare('uploadbatch', q/SELECT batchid,
                                                    trans_time,
                                                    processid,
                                                    username,
                                                    status,
                                                    priority,
                                                    subacct,
                                                    orderid,
                                                    line
                                             FROM batchfile
                                             WHERE orderid
                                             BETWEEN ?
                                                 AND ?
                                             AND batchid = ?
                                             AND username = ?
                                             AND status = ?/);
    $sth->execute($firstOrderID,
                  $lastOrderID,
                  $batchID,
                  $username,
                  'locked') or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    foreach my $row (@{$rows}) {
      my $batch = new PlugNPay::Batch::File();
      $batch->_setBatchFileFromRow($row);
      push (@{$batchRows}, $batch);
    }
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'        => $@,
      'batch'        => $batchID,
      'username'     => $username,
      'firstOrderID' => $firstOrderID,
      'lastOrderID'  => $lastOrderID,
      'function'     => 'loadTransactions',
      'module'       => 'PlugNPay::Batch::File'
    });
  }

  return $batchRows;
}

###################################
# Subroutine: loadBatches
# ---------------------------------
# Description:
#   Loads batches that are pending
#   in the batchfile table.
sub loadBatches {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $batchData = {};
  eval {
    $dbs->begin('uploadbatch');

    my $timeObj = new PlugNPay::Sys::Time();
    $timeObj->subtractDays($self->getLookBackTime());

    my $sth = $dbs->prepare('uploadbatch', q/SELECT orderid,
                                                    batchid
                                             FROM batchfile
                                             WHERE status = ?
                                             AND username <> ?
                                             AND trans_time > ?
                                             ORDER BY priority DESC,
                                                      trans_time ASC,
                                                      orderid ASC
                                             LIMIT ?
                                             FOR UPDATE/);
    $sth->execute('pending',
                  'pnpdemo',
                  $timeObj->inFormat('gendatetime'),
                  $self->getLimit()) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});

    my $orderData = {};
    if (@{$rows} > 0) {
      foreach my $row (@{$rows}) {
        $orderData->{$row->{'orderid'}} = $row->{'batchid'};
      }
    }

    if (keys %{$orderData} > 0) {
      foreach my $order (sort keys %{$orderData}) {
        if (!defined $batchData->{$orderData->{$order}}{'first'}) {
          $batchData->{$orderData->{$order}}{'first'} = $order;
          $batchData->{$orderData->{$order}}{'last'} = $order;
        } else {
          $batchData->{$orderData->{$order}}{'last'} = $order;
        }
      }

      foreach my $batch (keys %{$batchData}) {
        my $updateSTH = $dbs->prepare('uploadbatch', qq/UPDATE batchfile
                                                        SET status = ?
                                                        WHERE orderid
                                                        BETWEEN ?
                                                            AND ?
                                                        AND status = ?
                                                        AND batchid = ?/);
        $updateSTH->execute('locked',
                            $batchData->{$batch}{'first'},
                            $batchData->{$batch}{'last'},
                            'pending',
                            $batch) or die $DBI::errstr;
      }
    }

    # commit here ! the rows are safe.
    $dbs->commit('uploadbatch');
  };

  if ($@) {
    $dbs->rollback('uploadbatch');

    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'        => $@,
      'function'     => 'loadBatches',
      'module'       => 'PlugNPay::Batch::File'
    });
  }

  # if no errors and batch rows
  if (!$@ && keys %{$batchData} > 0) {
    # iterate through batches and load the batchid data
    foreach my $batchID (keys %{$batchData}) {
      my $batch = new PlugNPay::Batch::ID();
      $batch->loadBatch($batchID);

      # for each row .. we have the header info
      my $batchEntries = $self->loadTransactions($batch->getUsername(),
                                                 $batchID,
                                                 $batchData->{$batchID}{'first'},
                                                 $batchData->{$batchID}{'last'});
      my $batchResult = new PlugNPay::Batch::Results();
      foreach my $batchEntry (@{$batchEntries}) {
        # process the transaction
        my $result;
        eval {
          $result = $self->_processTransaction($batch, $batchEntry);
        };

        if ($@) {
          # transaction wasn't processed .. log reason
          my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
          $logger->log({
            'error'        => $@,
            'function'     => 'loadBatches',
            'module'       => 'PlugNPay::Batch::File'
          });

          $self->resetTransactionStatus($batchEntry);
        } else {
          # update the batch
          $self->updateTransactionStatus($batchEntry);
        
          # save the results in batchresult
          $batchResult->insertBatchResult($batchEntry, $result);
        }
      }
    }
  }
}

sub _processTransaction {
  my $self = shift;
  my $batch = shift;
  my $batchEntry = shift;

  my %query = ();
  my %result = ();

  $query{'publisher-name'}  = $batch->getUsername();
  $query{'publisher-email'} = $batch->getEmailAddress();

  my @headerArray = split(/\t/, $batch->getHeader());
  my @queryArray = ();

  if ( ($batch->getHeaderFlag() eq 'yes') || ($batch->getHeaderFlag() eq '') ) {
    # pre authorization testing and build query hash
    $self->preAuthorizationPNP($batch, $batchEntry, \%query);
  } elsif ($batch->getHeaderFlag() eq 'icverify') {
    # pre authorization testing and build query hash
    $self->preAuthorizationICVerify($batchEntry->getLine(), \%query);
  }

  if ($query{'error_flag'} eq '') {
    my @array = %query;
    my $pnpremote = remote->new(@array);
 
    my $features = new PlugNPay::Features($batch->getUsername(), 'general');
    $remote::feature{'multicurrency'}           = $features->get('multicurrency');
    $remote::feature{'linked_accts'}            = $features->get('linked_accts');
    $remote::feature{'force_onfail'}            = $features->get('force_onfail');
    $remote::feature{'api_billmem_chkbalance'}  = $features->get('api_billmem_chkbalance');
    $remote::feature{'api_billmem_chkpasswrd'}  = $features->get('api_billmem_chkpasswrd');
    $remote::feature{'api_billmem_updtbalance'} = $features->get('api_billmem_updtbalance');
    $remote::feature{'billpay_remove_invoice'}  = $features->get('billpay_remove_invoice');
    $remote::feature{'altmerchantdb'}           = $features->get('altmerchantdb');
    $remote::feature{'allow_multret'}           = $features->get('allow_multret');
    $remote::feature{'iovation'}                = $features->get('iovation');

   if ($query{'mode'} =~ /^(mark|void|return|postauth|reauth)$/) {
      $remote::query{'acct_code4'} = "Collect Batch " . $batchEntry->getBatchID();
      %result = $pnpremote->trans_admin()
    } elsif ($query{'mode'} =~ /^(credit|newreturn|payment)$/) {
      $remote::query{'acct_code4'} = "Collect Batch " . $batchEntry->getBatchID();
      %result = $pnpremote->newreturn();
    } elsif ($query{'mode'} =~ /^(forceauth)$/) {
      $remote::query{'acct_code4'} = "Collect Batch " . $batchEntry->getBatchID();
      %result = $pnpremote->forceauth();
    } elsif ($query{'mode'} =~ /^(query_trans)$/) {
      %result = $pnpremote->query_trans();
    } elsif ($query{'mode'} eq "add_negative") {
      %result = $pnpremote->add_negative();
    } elsif($query{'mode'} =~ /add_member/) {
      %result = $pnpremote->add_member();
      # check for membership storage
      my (@modes) = split(/\||\,/,$query{'mode'});
      if (($modes[1] eq "bill_member") && ($result{'FinalStatus'} eq "success")) {
        my %result1 = $pnpremote->bill_member();
        foreach my $key (sort keys %result1) {
          $result{'a00001'} .= "$key=$result1{$key}\&";
        }
        chop $result{'a00001'};
      }
    } elsif($query{'mode'} =~ /delete_member/) {
      %result = $pnpremote->delete_member();
    } elsif($query{'mode'} =~ /cancel_member/) {
      %result = $pnpremote->cancel_member();
    } elsif($query{'mode'} =~ /update_member/) {
      %result = $pnpremote->update_member();
    } elsif ($query{'mode'} =~ /query_member/) {
      %result = $pnpremote->query_member();
    } elsif ($query{'mode'} =~ /bill_member|credit_member/) {
      %result = $pnpremote->bill_member();
    } elsif ($query{'mode'} =~ /^(returnprev)$/) {
      %result = $pnpremote->returnprev();
    } elsif ($query{'mode'} =~ /storedata/) {
      my $payment = mckutils->new(@array);
      $mckutils::query{'acct_code4'} = "Collect Batch " . $batchEntry->getBatchID();
      %result = $payment->purchase("storedata");
    } elsif ($query{'mode'} =~ /auth/) {
      if ($query{'mode'} =~ /^(authprev)$/) {
        %result = $pnpremote->authprev();
        @array = %remote::query;
        if ($features->get('uploadbatch_forcelocal')) {
          %query = %remote::query;
        }
      }
      my $payment = mckutils->new(@array);
      $mckutils::query{'acct_code4'} = "Collect Batch " . $batchEntry->getBatchID();
      my $start = time();

      %result = $payment->purchase("auth");

      my $delta = time() - $start;

      if (($result{'FinalStatus'} eq "success") && ($mckutils::query{'conv_fee_amt'} > 0 ) && ($result{'MErrMsg'} !~ /^Duplicate/)) {
        my %orig = ();
        my @orig = ('orderID','card-amount','publisher-name','publisher-email','acct_code','acct_code2','acct_code3','amountcharged');
        foreach my $var (@orig) {
          $orig{$var} = $mckutils::query{$var};
        }

        my %legacyorigfeatures = %mckutils::feature;

        ### Set Features for Conv. Account
        $mckutils::accountFeatures = new PlugNPay::Features($mckutils::query{'conv_fee_acct'},'general');

        #### To support legacy feature hash - currently redundant as it is pulled out again in purchase
        my $features = $mckutils::accountFeatures->getSetFeatures();
        foreach my $var (@{$features}) {
          $mckutils::feature{$var} = $mckutils::accountFeatures->get($var);
        }

        ## Mark transaction as a conv. fee transaction
        $mckutils::convfeeflag = 1;

        my $feeamt = $mckutils::query{'conv_fee_amt'};
        my $feeact = $mckutils::query{'conv_fee_acct'};
        my $failrule = $mckutils::query{'conv_fee_failrule'};

        $mckutils::query{'card-amount'} = $feeamt;
        $mckutils::query{'publisher-name'} = $feeact;

        if ($feeact eq $orig{'publisher-name'}) {
           $mckutils::query{'orderID'} =  $mckutils::query{'orderID'}  . "1";
        } else {
          $mckutils::query{'orderID'} = &miscutils::incorderid($mckutils::query{'orderID'});
        }
        $mckutils::orderID = $mckutils::query{'orderID'};
        $mckutils::query{'acct_code3'} = "ConvFeeC:$orig{'orderID'}:$orig{'publisher-name'}";

        if ($mckutils::feature{'conv_fee_authtype'} eq "authpostauth") {
          $mckutils::query{'authtype'} = 'authpostauth';
        }

        my %resultCF = $payment->purchase("auth");

        $result{'auth-codeCF'} = substr($resultCF{'auth-code'},0,6);
        $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
        $result{'MErrMsgCF'} = $resultCF{'MErrMsg'};
        $result{'orderIDCF'} = $mckutils::query{'orderID'};
        $result{'convfeeamt'} = $feeamt;

        my (%result1,$voidstatus);

        if (($resultCF{'FinalStatus'} ne "success") && ($failrule =~ /VOID/i)) {
          my $price = sprintf("%3s %.2f","$mckutils::query{'currency'}",$orig{'card-amount'});
          ## Void Main transaction
          #for(my $i=1; $i<=3; $i++) {
            %result1 = &miscutils::sendmserver($orig{'publisher-name'},"void"
               ,'acct_code', $mckutils::query{'acct_code'}
               ,'acct_code4', "$mckutils::query{'acct_code4'}"
               ,'txn-type','auth'
               ,'amount',"$price"
               ,'order-id',"$orig{'orderID'}"
               ,'accttype', $mckutils::query{'accttype'}
               );
          #  last if($result1{'FinalStatus'} eq "success");
          #}
          $result{'voidstatus'} = $result1{'FinalStatus'};
          $result{'FinalStatus'} = $resultCF{'FinalStatus'};
          $result{'MErrMsg'} = $resultCF{'MErrMsg'};
        }

        if ($resultCF{'FinalStatus'} eq "success") {
          $mckutils::query{'totalchrg'} = sprintf("%.2f",$orig{'card-amount'}+$feeamt);
        }

        $payment->database();

        %mckutils::result = (%mckutils::result,%result);

        foreach my $var (@orig) {
          $mckutils::query{$var} = $orig{$var};
        }

        ## Set Features Back to Primary Account
        $mckutils::accountFeatures = new PlugNPay::Features($mckutils::query{'publisher-name'},'general');

        #### To support legacy feature hash
        %mckutils::feature = %legacyorigfeatures;

        $mckutils::query{'convfeeamt'} = $result{'convfeeamt'};
        $mckutils::conv_fee_amt = $mckutils::query{'conv_fee_amt'};
        $mckutils::conv_fee_acct = $mckutils::query{'conv_fee_acct'};
        $mckutils::conv_fee_oid = $result{'orderIDCF'};

        delete $mckutils::query{'conv_fee_amt'};
        delete $mckutils::query{'conv_fee_acct'};
        delete $mckutils::query{'conv_fee_failrule'};

        ## un Mark transaction as a conv. fee transaction since tran is now complete

        $mckutils::convfeeflag = 0;
      }

      if ($result{'FinalStatus'} eq 'success') {
        eval {
          $payment->logFeesIfApplicable(\%mckutils::query, \%mckutils::result, $mckutils::adjustmentFlag, $mckutils::conv_fee_acct, $mckutils::conv_fee_oid);
        };
      }

      $result{'auth-code'} = substr($result{'auth-code'},0,6);

      $payment->database();

      if (($query{'sndemail'} ne "") || ($batch->getEmailFlag() eq "yes")) {
        $payment->email();
      }

      # code to sleep on processor problem
      if (($result{'FinalStatus'} eq "problem")
         && (($result{'MErrMsg'} eq "No response received from processor")
         || ($result{'MErrMsg'} eq "No response from processor error"))) {
        sleep 60;
      }

      # check for membership storage
      (@remote::modes) = split(/\||\,/,$query{'mode'});
      if (($remote::modes[1] eq "add_member") && ($result{'FinalStatus'} eq "success")) {
        my %result1 = $pnpremote->add_member();
        foreach my $key (sort keys %result1) {
          $result{'a00001'} .= "$key=$result1{$key}\&";
        }
        chop $result{'a00001'};
      }
    }
  } else {
    # failed
    if ($query{'luhn_check'} eq "failure") {
      $result{'FinalStatus'} = "badcard";
      $result{'MErrMsg'} = "Card number failed luhn10 check";
      $result{'resp-code'} = "P55";
    } elsif ($query{'mod_check'} eq "failure") {
      $result{'FinalStatus'} = "badcard";
      $result{'MErrMsg'} = "Routing number failed mod10 check";
      $result{'resp-code'} = "P53";
    } elsif ($query{'error_flag'} ne "") {
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'} = $query{'error_flag'};
    }
  }

    # build return string
  my $answer = "";

  # fix card number
  #$query{'card-number'} = substr($query{'card-number'},0,4) . '**' . substr($query{'card-number'},-2,2);
  my ($cardnumber) = substr($query{'card-number'},0,20);
  my $cclength = length($cardnumber);
  my $last4 = substr($cardnumber,-4,4);
  $cardnumber =~ s/./X/g;
  $query{'card-number'} = substr($cardnumber,0,$cclength-4) . $last4;

  if ($batch->getHeaderFlag() eq "yes") {
    $answer = $result{'FinalStatus'} . "\t" . $result{'MErrMsg'} . "\t" . $result{'resp-code'} . "\t" . $query{'orderID'} . "\t" . $result{'auth-code'} . "\t" . $result{'avs-code'} . "\t" . $result{'cvvresp'};

    foreach my $field (@headerArray) {
      $field =~ tr/A-Z/a-z/;
      $answer .= "\t" . $query{$field};
    }
  } elsif ($batch->getHeaderFlag() eq "icverify") {
    $answer = "$query{'trx_code'}\,$query{'CMc'}\,$query{'CMM'}\,$query{'ACT'}\,$query{'EXP'}\,$query{'AMT'}\,";

    if (($result{'FinalStatus'} eq "success") || ($result{'FinalStatus'} eq "pending")) {
      $answer .= "Y" . $result{'auth-code'};
    }
    else {
      $answer .= "N" . $result{'MErrMsg'};
    }
  } else {
    $answer = $result{'FinalStatus'} . "\t" . $result{'MErrMsg'} . "\t" . $query{'orderID'} . "\t" . $query{'card-name'} . "\t" . $query{'card-amount'} . "\t" . $query{'card-number'} . "\t" . $query{'acct_code'};
    my $key = "";
    foreach $key (sort keys %query) {
      if (($key ne "card-number")
          && ($key ne "card-exp")
          && ($key ne "year-exp")
          && ($key ne "month-exp")
          && ($key ne "pass")
          && ($key ne "attempts")
          && ($key ne 'User-Agent')) {
         $answer .= "\t" . $query{$key};
      }
    }
    foreach $key (sort keys %result) {
      if (($key ne "card-number")
          && ($key ne "card-exp")
          && ($key ne "year-exp")
          && ($key ne "month-exp")
          && ($key ne "pass")
          && ($key ne "attempts")
          && ($key ne 'User-Agent')) {
        $answer .= "\t" . $result{$key};
      }
    }
  }

  return $answer;
}

##################################
# Subroutine: preAuthorizationPNP
# --------------------------------
# Description:
#   Pre authorization check of
# transaction data.
sub preAuthorizationPNP {
  my $self = shift;
  my $batch = shift;
  my $batchEntry = shift;
  my $query = shift;

  my $header = $batch->getHeader();
  $header =~ tr/A-Z/a-z/;

  my @headerArray = split(/\t/, $header);
  my @queryArray  = split(/\t/, $batchEntry->getLine());

  for (my $index = 0; $index <= $#headerArray; $index++) {
    if ($headerArray[$index] =~ /(card-number|card_number|card-cvv|card_cvv|accountnum|x_card_num|x_card_code|x_bank_acct_num)/i) {
      my ($encLength, $encCard) = split(/\||\,/, $queryArray[$index]);
      my $cc = new PlugNPay::CreditCard();
      $cc->setNumberFromEncryptedNumber($encCard);
      $queryArray[$index] = $cc->getNumber();
    }

    if ($headerArray[$index] !~ /publisher-name/i) {
      if ($headerArray[$index] =~ /^orderid$/i) {
        $headerArray[$index] = 'orderID';
      }
      
      $query->{$headerArray[$index]} = $queryArray[$index];
    }
  }

  if ($query->{'orderID'} eq '') {
    $query->{'orderID'} = $batchEntry->getOrderID();
  }

  # test transaction type
  $query->{'!batch'} =~ tr/A-Z/a-z/;
  if ( ($query->{'!batch'} =~ /authprev/) || ($query->{'forceauth'}) ) {
    # do nothing apparently..
  } elsif ( (($query->{'!batch'} =~ /auth/) || ($query->{'!batch'} =~ /checkcard/)) && ($query->{'card-number'} ne '') && ($query->{'card-exp'} ne '') ) {
    $query->{'card-number'} =~ s/\D//g;
  } elsif ( ($query->{'!batch'} =~ /auth/) && ($query->{'routingnum'} ne '') && ($query->{'accountnum'} ne '') && ($query->{'accttype'} ne '') ) {
    $query->{'routingnum'} =~ s/[^0-9]//g;
    $query->{'nofraudcheck'} = 'yes';
  } elsif ($query->{'!batch'} =~ /mark|void|return|postauth|reauth|query_trans|add_member|delete_member|cancel_member|update_member|query_member|bill_member|credit_member/) {
    # do nothing apparently..
  } elsif ($query->{'!batch'} =~ /credit|newreturn|payment/) {
    if ( ($header =~ /routingnum/) && ($header =~ /accountnum/) && ($query->{'accttype'} ne '') ) {
      $query->{'routingnum'} =~ s/[^0-9]//g;
    } elsif (exists $query->{'card-number'}) {
      $query->{'card-number'} =~ s/\D//g;
    } else {
      $query->{'error_flag'} .= 'Return/credit missing required data.';
    }
  } elsif ( (($query->{'!batch'} =~ /auth/) && ($query->{'transflag'} =~ /issue/))
    || ($query->{'!batch'} =~ /storedata/)
    || ($query->{'!batch'} =~ /^add_negative$/) ) {
    # do nothing apparently..
  } else {
    $query->{'error_flag'} .= 'FAILED TO FIGURE OUT TRX TYPE!';
  }

  $query->{'mode'} = $query->{'!batch'};
}

#######################################
# Subroutine: preAuthorizationICVerify
# -------------------------------------
# Description:
#   Pre authorization check of
# transaction data for ICVerify.
sub preAuthorizationICVerify {
  my $self = shift;
  my $transactionLine = shift;
  my $query = shift;

  my @queryArray = split(/\t/, $transactionLine);
  $query->{'trx_code'}  = $queryArray[0];
  $query->{'CMc'}       = $queryArray[1];
  $query->{'acct_code'} = substr($queryArray[1], 0, 10);
  $query->{'acct_code'} =~ s/\s*//g;
  $query->{'orderID'}   = substr($queryArray[1], 11);
  $query->{'orderID'}   =~ s/\s*//g;
  $query->{'CMM'}       = $queryArray[2];

  my ($encLength, $encCard) = split(/\||\,/, $queryArray[3]);
  my $cc = new PlugNPay::CreditCard();
  $cc->setNumberFromEncryptedNumber($encCard);
  my $card = $cc->getNumber();

  $query->{'ACT'} = $card;
  $query->{'ACT'} =~ s/\s*//g;
  $query->{'card-number'} = $card;
  $query->{'card-number'} =~ s/\s*//g;
  $query->{'EXP'} = $queryArray[4];
  $query->{'card-exp'} = substr($queryArray[4], 0, 2) . '/' . substr($queryArray[4], 2);
  $query->{'AMT'} = $queryArray[5];
  $query->{'card-amount'} = $queryArray[5];
  $query->{'card-amount'} =~ s/^0*//g;

  if ($query->{'trx_code'} eq 'C6') {
    $query->{'mode'} = 'auth';
  } elsif ($query->{'trx_code'} eq 'C3') {
    $query->{'mode'} = 'newreturn';
  } elsif ($query->{'trx_code'} eq 'C5') {
    $query->{'mode'} = 'forceauth';
    $query->{'auth-code'} = $queryArray[6];
  } else {
    $query->{'error_flag'} = 'Unknown trx type.';
  }
}

sub resetTransactionStatus {
  my $self = shift;
  my $batchEntry = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status();
  eval {
    my $sth = $dbs->prepare('uploadbatch', q/UPDATE batchfile
                                             SET status = ?
                                             WHERE orderid = ?
                                             AND username = ?
                                             AND status = ?
                                             AND batchid = ?/);
    $sth->execute('pending',
                  $batchEntry->getOrderID(),
                  $batchEntry->getUsername(),
                  'locked',
                  $batchEntry->getBatchID()) or die $DBI::errstr;
    $status->setTrue();
  };

  if ($@) {
    $status->setFalse();

    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'        => $@,
      'function'     => 'resetTransactionStatus',
      'batchID'      => $batchEntry->getBatchID(),
      'username'     => $batchEntry->getUsername(),
      'module'       => 'PlugNPay::Batch::File'
    });
  }

  return $status;
}

sub updateTransactionStatus {
  my $self = shift;
  my $batchEntry = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $status = new PlugNPay::Util::Status();
  eval {
    my $sth = $dbs->prepare('uploadbatch', q/UPDATE batchfile
                                             SET status = ?
                                             WHERE orderid = ?
                                             AND username = ?
                                             AND status = ?
                                             AND batchid = ?/);
    $sth->execute('success',
                  $batchEntry->getOrderID(),
                  $batchEntry->getUsername(),
                  'locked',
                  $batchEntry->getBatchID()) or die $DBI::errstr;
    $status->setTrue();
  };

  if ($@) {
    $status->setFalse();

    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'batch_job' });
    $logger->log({
      'error'        => $@,
      'function'     => 'updateTransactionStatus',
      'batchID'      => $batchEntry->getBatchID(),
      'username'     => $batchEntry->getUsername(),
      'module'       => 'PlugNPay::Batch::File'
    });
  }

  return $status;
}

sub checkPendingTransactions {
  my $self = shift;
  my $batchID = shift;

  my $dbs = new PlugNPay::DBConnection();

  my $count = 0;
  eval {
    my $sth = $dbs->prepare('uploadbatch', q/SELECT COUNT(*) as `incomplete`
                                             FROM batchfile
                                             WHERE status <> ?
                                             AND batchid = ?/);
    $sth->execute('success',
                  $batchID) or die $DBI::errstr;
    my $rows = $sth->fetchall_arrayref({});
    $count = $rows->[0]{'incomplete'};
  };

  return $count;
}

1;
