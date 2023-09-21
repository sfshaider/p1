#!/usr/local/bin/perl

$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use miscutils;
use rsautils;
use remote_strict;
use mckutils_strict;
use PlugNPay::Features;
use strict;

my ($parentid,$batchid,$merchant,$firstorderid,$lastorderid) = @ARGV;

# connect using don't die flag
my $dbh = &miscutils::dbhconnect("uploadbatch","yes");

# test db connection if fail email and die
if ($dbh eq "") {
  my $error_message = "Subject: Batch failure: database\n";
  $error_message .= "BatchID $batchid\n";
  $error_message .= "ParentID $parentid\n";
  $error_message .= "Merchant $merchant\n\n";
  $error_message .= "Database connection failure\n";
  &send_error($error_message);
  exit;
}

#### Question: are batchid unique between merchants ?

# update batchfile die if update fails
my $sth = $dbh->prepare(qq{
        update batchfile
        set processid='$$'
        where orderid between '$firstorderid' and '$lastorderid'
        and processid='$parentid'
        and batchid='$batchid'
        and status='locked'
}) or die "do something here $DBI::errstr\n";
$sth->execute or die "do something here $DBI::errstr\n";
$sth->finish;

my $number_of_transactions = $lastorderid - $firstorderid + 1;

my @transactions = ();

my ($header,$email_flag,$publisher_email,$header_flag);

# get batch information
$sth = $dbh->prepare(qq{
        select header,emailflag,emailaddress,headerflag
        from batchid
        where username='$merchant'
        and batchid='$batchid'
}) or &rollback_batchfile($parentid);
$sth->execute or &rollback_batchfile($parentid);
$sth->bind_columns(undef,\($header,$email_flag,$publisher_email,$header_flag));
$sth->fetch;
$sth->finish;

# get transactions
my $lineid = "";
my $line = "";
my $subacct = "";
my %transaction_hash = ();
my %subacct_hash = ();
$sth = $dbh->prepare(qq{
     select orderid,line,subacct
     from batchfile
     where orderid between '$firstorderid' and '$lastorderid'
     and batchid='$batchid'
     and username='$merchant'
     and status='locked'
     and processid='$$'
}) or &rollback_batchfile($parentid);
$sth->execute or &rollback_batchfile($parentid);
$sth->bind_columns(undef,\($lineid,$line,$subacct));

my $found_transactions = 0;

while ($sth->fetch) {
#print "LINEID $$ |$lineid|\n";
  $transaction_hash{$lineid} = $line;
  $subacct_hash{$lineid} = $subacct;
  $found_transactions++;
}

$sth->finish;

my($i);
# run through trxs and process them shove results into batchresults
foreach my $trxid (keys %transaction_hash) {
  $i++;
  &check_quit($trxid,$lastorderid);
#print "after check quit\n";
  my $result = &process_transaction($email_flag,$header_flag,$merchant,$publisher_email,$header,$trxid,$transaction_hash{$trxid});
#print "TST done proc tran\n";
  &update_transaction_status($batchid,$trxid,$merchant,$dbh);
#print "updated status\n";

  &insert_results($batchid,$trxid,$merchant,$result,$dbh);
#print "inserted results\n";
}

$dbh->disconnect;

exit;

sub process_transaction {
  my ($email_flag,$header_flag,$publisher_name,$publisher_email,$header,$orderid,$transaction_line) = @_;
#print "TST proc tran\n";
  my %query = ();
  my %result = ();

  $query{'publisher-name'} = $merchant;
  $query{'publisher-email'} = $publisher_email;
#  $query{'subacct'} = $subacct;

  my @query_array = ();
  my @header_array = ();

  @header_array = split(/\t/,$header);

  # the two pnp formats
  if (($header_flag eq "yes") || ($header_flag eq "")) {
    # pre authorization testing and build query hash
    &preauth_verify_pnp($header,$transaction_line,$orderid,\%query);
  }
  # the icverify format
  elsif ($header_flag eq "icverify") {
    # pre authorization testing and build query hash
    &preauth_verify_icverify($transaction_line,\%query);
  }
#print "tst preauth done\n";
  # need to check luhn_check and error_flag before we process
  #if ((($query{'luhn_check'} eq "success") || ($query{'mod_check'} eq "success")) && ($query{'error_flag'} eq "")) {
  if ($query{'error_flag'} eq "") {

    my @array = %query;

    my $pnpremote = remote->new(@array);
    my $features = new PlugNPay::Features($publisher_name,'general');
    $remote::feature{'multicurrency'} = $features->get('multicurrency');
    $remote::feature{'linked_accts'} = $features->get('linked_accts');
    $remote::feature{'force_onfail'} = $features->get('force_onfail');
    $remote::feature{'api_billmem_chkbalance'} = $features->get('api_billmem_chkbalance');
    $remote::feature{'api_billmem_chkpasswrd'} = $features->get('api_billmem_chkpasswrd');
    $remote::feature{'api_billmem_updtbalance'} = $features->get('api_billmem_updtbalance');
    $remote::feature{'billpay_remove_invoice'} = $features->get('billpay_remove_invoice');
    $remote::feature{'altmerchantdb'} = $features->get('altmerchantdb');
    $remote::feature{'allow_multret'} = $features->get('allow_multret');
    $remote::feature{'iovation'} = $features->get('iovation');

    if ($query{'mode'} =~ /^(mark|void|return|postauth|reauth)$/) {
      $remote::query{'acct_code4'} = "Collect Batch " . $batchid;
      %result = $pnpremote->trans_admin()
    }
    elsif ($query{'mode'} =~ /^(credit|newreturn|payment)$/) {
      $remote::query{'acct_code4'} = "Collect Batch " . $batchid;
      %result = $pnpremote->newreturn();
    }
    elsif ($query{'mode'} =~ /^(forceauth)$/) {
      $remote::query{'acct_code4'} = "Collect Batch " . $batchid;
      %result = $pnpremote->forceauth();
    }
    elsif ($query{'mode'} =~ /^(query_trans)$/) {
      %result = $pnpremote->query_trans();
    }
    elsif ($query{'mode'} eq "add_negative") {
      %result = $pnpremote->add_negative();
    }
    elsif($query{'mode'} =~ /add_member/) {
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
    }
    elsif($query{'mode'} =~ /delete_member/) {
      %result = $pnpremote->delete_member();
    }
    elsif($query{'mode'} =~ /cancel_member/) {
      %result = $pnpremote->cancel_member();
    }
    elsif($query{'mode'} =~ /update_member/) {
      %result = $pnpremote->update_member();
    }
    elsif ($query{'mode'} =~ /query_member/) {
      %result = $pnpremote->query_member();
    }
    elsif ($query{'mode'} =~ /bill_member|credit_member/) {
      %result = $pnpremote->bill_member();
    }
    elsif ($query{'mode'} =~ /^(returnprev)$/) {
      %result = $pnpremote->returnprev();
    }
    elsif ($query{'mode'} =~ /storedata/) {
      my $payment = mckutils->new(@array);
      $mckutils::query{'acct_code4'} = "Collect Batch " . $batchid;
      %result = $payment->purchase("storedata");
    }
    elsif ($query{'mode'} =~ /auth/) {
      if ($query{'mode'} =~ /^(authprev)$/) {
        %result = $pnpremote->authprev();
        @array = %remote::query;
        if ($features->get('uploadbatch_forcelocal')) {
          %query = %remote::query;
        }
      }
      my $payment = mckutils->new(@array);
      $mckutils::query{'acct_code4'} = "Collect Batch " . $batchid;
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
        }
        else {
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

      if ($result{'FinalStatus'} eq "success") {
        eval {
          $payment->logFeesIfApplicable(\%mckutils::query, \%mckutils::result, $mckutils::adjustmentFlag, $mckutils::conv_fee_acct, $mckutils::conv_fee_oid);
        };
      }

      $result{'auth-code'} = substr($result{'auth-code'},0,6);

      $payment->database();

      if (($query{'sndemail'} ne "") || ($email_flag eq "yes")) {
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
  }
  else {
    # something failed in preauth checking
    if ($query{'luhn_check'} eq "failure") {
      $result{'FinalStatus'} = "badcard";
      $result{'MErrMsg'} = "Card number failed luhn10 check";
      $result{'resp-code'} = "P55";
    }
    elsif ($query{'mod_check'} eq "failure") {
      $result{'FinalStatus'} = "badcard";
      $result{'MErrMsg'} = "Routing number failed mod10 check";
      $result{'resp-code'} = "P53";
    }
    elsif ($query{'error_flag'} ne "") {
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


  if ($header_flag eq "yes") {
    $answer = $result{'FinalStatus'} . "\t" . $result{'MErrMsg'} . "\t" . $result{'resp-code'} . "\t" . $query{'orderID'} . "\t" . $result{'auth-code'} . "\t" . $result{'avs-code'} . "\t" . $result{'cvvresp'};

    foreach my $header_field (@header_array) {
      $header_field =~ tr/A-Z/a-z/;
      $answer .= "\t" . $query{$header_field};
    }
  }
  elsif ($header_flag eq "icverify") {
    $answer = "$query{'trx_code'}\,$query{'CMc'}\,$query{'CMM'}\,$query{'ACT'}\,$query{'EXP'}\,$query{'AMT'}\,";

    if (($result{'FinalStatus'} eq "success") || ($result{'FinalStatus'} eq "pending")) {
      $answer .= "Y" . $result{'auth-code'};
    }
    else {
      $answer .= "N" . $result{'MErrMsg'};
    }
  }
  else {
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

sub insert_results {
  my ($batchid,$transactionid,$publisher_name,$result,$dbh) = @_;

  my $sth = $dbh->prepare(qq{
          insert into batchresult
          (batchid,orderid,processid,username,line)
          values (?,?,?,?,?)
  }) or &store_in_file($batchid,$transactionid,$publisher_name,$result," prepare $DBI::errstr");
  $sth->execute($batchid,$transactionid,$$,$publisher_name,$result) or &store_in_file($batchid,$transactionid,$publisher_name,$result," execute $DBI::errstr");
  $sth->finish;
}

sub update_transaction_status {
  my ($batchid,$transactionid,$publisher_name,$dbh) = @_;

  my $sth = $dbh->prepare(qq{
          update batchfile
          set status='success'
          where orderid='$transactionid'
          and batchid='$batchid'
          and processid='$$'
          and username='$publisher_name'
          and status='locked'
  }) or &store_in_file($batchid,$transactionid,$publisher_name,"$DBI::errstr"," prepare");
  $sth->execute or &store_in_file($batchid,$transactionid,$publisher_name,"$DBI::errstr"," execute");
  $sth->finish;
}

sub send_error {
  my ($message) = @_;

  open(MAIL,"| /usr/lib/sendmail -t");
  print MAIL "To: dprice\@plugnpay.com\n";
  print MAIL "From: collectbatch\@plugnpay.com\n";
  print MAIL $message;
  close MAIL;
}

sub rollback_batchfile {
#print "ROLLBACK\n";
  my ($parentid) = @_;

  # sleep for a bit maybe what ever happened cleared up.
  sleep 60;

  my $rollback = "yes";

  # try to undo changes
  my $sth = $dbh->prepare(qq{
          update batchfile
          set processid='$parentid',
          where firstorderid>='$firstorderid'
          and lastorderid<='$lastorderid'
          and batchid='$batchid'
          and processid='$$'
  }) or $rollback="no";
  $sth->execute or $rollback="no";
  $sth->finish;

  my $error_message = "Subject: Batch failure database";
  $error_message .= "Batch died rollback was attempted.";
  $error_message .= "Rollback = $rollback\n";
  $error_message .= "Parentid $parentid\n";
  $error_message .= "Myid $$\n";

  &send_error($error_message);

  exit;
}

sub store_in_file {
  # in case something goes wrong after a trx we store it in a file
  my ($batchid,$transactionid,$publisher_name,$result,$where) = @_;
  my $problem_batch_dir = "/home/p/pay1/private/uploadbatch/problem/";

  my $fileid = &miscutils::genorderid;

  my $backup_file = $problem_batch_dir . $fileid . "." . $publisher_name . "." . $batchid . ".result";

  if (-e $backup_file) {
    open(OUTFILE,">>$backup_file");
  }
  else {
    open(OUTFILE,">$backup_file");
  }

  print OUTFILE $batchid . "\t" . $where . "\t" . $transactionid . "\t" . $$ . "\t" . $publisher_name . "\t" . $result . "\n";

  close OUTFILE;
}


sub preauth_verify_icverify {
  my ($transaction_line,$query) = @_;

  my @query_array = split(/\,/,$transaction_line);

  # munch the ICVerify line and translate it
  $query->{"trx_code"} = $query_array[0];    # trx type C6=pre-auth C5=force sale C3=credit
  $query->{"CMc"} = $query_array[1];    # company id we maybe store this on acct_code
  $query->{'acct_code'} = substr($query_array[1],0,10);
  $query->{'orderID'} = substr($query_array[1],11);
  $query->{'acct_code'} =~ s/\s*//g;
  $query->{'orderID'} =~ s/\s*//g;

  $query->{"CMM"} = $query_array[2];    # comment O=order R=return + doc#

  my ($ic_card,$ic_length) = split(/\||\,/,$query_array[3]);
  $ic_card = &rsautils::rsa_decrypt_file($ic_card,$ic_length,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");

  $query->{"ACT"} = $ic_card;    # card number
  $query->{"card-number"} = $ic_card;
  $query->{"ACT"} =~ s/\s*//g;
  $query->{"card-number"} =~ s/\s*//g;
  $query->{"EXP"} = $query_array[4];    # card exp
  $query->{"card-exp"} = substr($query_array[4],0,2) . "/" . substr($query_array[4],2);
  $query->{"AMT"} = $query_array[5];    # card amount
  $query->{"card-amount"} = $query_array[5];
  # replace padded 0's with nothing
  $query->{"card-amount"} =~ s/^0*//g;

  if ($query->{'trx_code'} eq "C5") {
    # force auth
    $query->{'auth-code'} = $query_array[6];
  }

  #$query->{'luhn_check'} = &miscutils::luhn10($query->{'card-number'});

  #if (($query->{'trx_code'} eq "C6") && ($query->{'luhn_check'} eq "success")) {
  if ($query->{'trx_code'} eq "C6") {
    # normal auth
    $query->{'mode'} = "auth";
  }
  #elsif (($query->{'trx_code'} eq "C3") && ($query->{'luhn_check'} eq "success")) {
  elsif ($query->{'trx_code'} eq "C3") {
    # a new return
    $query->{'mode'} = "newreturn";
  }
  #elsif (($query->{'trx_code'} eq "C5") && ($query->{'luhn_check'} eq "success")) {
  elsif ($query->{'trx_code'} eq "C5") {
    # force auth
    $query->{'mode'} = "forceauth";
  }
  else {
    # unsupported trx type
    $query->{'error_flag'} = "Unknown trx type.";
  }
}

sub preauth_verify_pnp {
  my ($header,$transaction_line,$orderid,$query) = @_;

  $header =~ tr/A-Z/a-z/;
  #$header =~ s/orderid/orderID/;

  my @query_array = split(/\t/,$transaction_line);
  my @header_array = split(/\t/,$header);

  # setup the query hash and decrypt stuff
  for (my $index=0;$index<=$#header_array;$index++) {
    # decrypt
    if ($header_array[$index] =~ /(card-number|card_number|card-cvv|card_cvv|accountnum|x_card_num|x_card_code|x_bank_acct_num)/i) {
      my ($enclength,$encdata) = split(/\||\,/,$query_array[$index]);
#print "ENCD: $encdata\n";
#print "ENCL: $enclength\n";
      $query_array[$index] = &rsautils::rsa_decrypt_file($encdata,$enclength,"print enccardnumber 497","/home/p/pay1/pwfiles/keys/key");
#print "ENC: $header_array[$index]\n";
#print "ENC: $query_array[$index]\n";
    }
    # build query
    if ($header_array[$index] !~ /publisher-name/i) {
      if ($header_array[$index] =~ /^orderid$/i) {
        $header_array[$index] = "orderID";
      }
      $query->{$header_array[$index]} = $query_array[$index];
    }
  }

  if ($query->{'orderID'} eq "") {
    $query->{'orderID'} = $orderid;
  }

  # test the transaction type
  #forceauth
  $query->{'!batch'} =~ tr/A-Z/a-z/;
  if ($query->{'!batch'} =~ /forceauth/) {
      #$query->{'luhn_check'} = &miscutils::luhn10($query->{'card-number'});
  }
  elsif ($query->{'!batch'} =~ /authprev/) {
  }
  # some sort of normal auth credit card
  elsif (($query->{'!batch'} =~ /auth/) && ($query->{'card-number'} ne "") && ($query->{'card-exp'} ne "")) {
  #elsif (($query->{'!batch'} =~ /auth/) && (exists $query->{'card-number'}) && (exists $query->{'card-exp'})) {
    $query->{'card-number'} =~ s/\D//g;
    #$query->{'luhn_check'} = &miscutils::luhn10($query->{'card-number'});
  }
  elsif  (($query->{'!batch'} =~ /checkcard/) && ($query->{'card-number'} ne "") && ($query->{'card-exp'} ne "")) {
    $query->{'card-number'} =~ s/\D//g;
  }
  # checking auth
  #elsif (($query->{'!batch'} =~ /auth/) && ($header =~ /routingnum/) && ($header =~ /accountnum/) && ($query->{'accttype'} ne "")) {
  elsif (($query->{'!batch'} =~ /auth/) && ($query->{'routingnum'} ne "") && ($query->{'accountnum'} ne "") && ($query->{'accttype'} ne "")) {
    $query->{'routingnum'} =~ s/[^0-9]//g;
    #$query->{'mod_check'} = &miscutils::mod10($query->{'routingnum'});
    $query->{'nofraudcheck'} = "yes";
  }
  # everything else that doesn't require luhn10
  elsif ($query->{'!batch'} =~ /mark|void|return|postauth|reauth|query_trans|add_member|delete_member|cancel_member|update_member|query_member|bill_member|credit_member/) {
    #$query->{'luhn_check'} = "success";
  }
  # credit and newreturn
  elsif ($query->{'!batch'} =~ /credit|newreturn|payment/) {
    if (($header =~ /routingnum/) && ($header =~ /accountnum/) && ($query->{'accttype'} ne "")) {
      $query->{'routingnum'} =~ s/[^0-9]//g;
      #$query->{'mod_check'} = &miscutils::mod10($query->{'routingnum'});
    }
    elsif (exists $query->{'card-number'}) {
      $query->{'card-number'} =~ s/\D//g;
      #$query->{'luhn_check'} = &miscutils::luhn10($query->{'card-number'});
    }
    else {
      $query->{'error_flag'} .= "Return/credit missing required data.";
    }
  }
  elsif (($query->{'!batch'} =~ /auth/) && ($query->{'transflags'} =~ /issue/)) {

  }
  elsif ($query->{'!batch'} =~ /storedata/) {

  }
  elsif ($query->{'!batch'} =~ /^add_negative$/) {

  }
  # oops something bad happened
  else {
    $query->{'error_flag'} .= "FAILED TO FIGURE OUT TRX TYPE!";
  }

  # convert for mode
  $query->{'mode'} = $query->{'!batch'};
}

sub check_quit {
  my ($first,$last) = @_;
  if ((-e "/home/p/pay1/private/uploadbatch/stopcollectbatch.txt") || (-e "/home/p/pay1/outagefiles/highvolume.txt")) {
    my $sth = $dbh->prepare(qq{
         update batchfile
         set status='pending'
         where orderid between '$first' and '$last'
         and status='locked'
         and processid='$$'
    }) or &miscutils::errmail(__LINE__,__FILE__,"failed unlock $first $last $DBI::errstr\n");
    $sth->execute or &miscutils::errmail(__LINE__,__FILE__,"failed unlock $first $last $DBI::errstr\n");
    $sth->finish;
    $dbh->disconnect;
    exit;
  }
}
