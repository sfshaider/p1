package uploadbatch;

require 5.001;
$| = 1;
 
use miscutils;
use rsautils;
use CGI;
use Math::BigInt;
use PlugNPay::Features;
use PlugNPay::Environment;
use PlugNPay::GatewayAccount;
use PlugNPay::GatewayAccount::LinkedAccounts;
use PlugNPay::Transaction::TransactionProcessor;
use strict;

# Things to fix
# stop using ENV variables in subs setup new to set variables based on what is being passed
# set PrintError for dbh so errors from mysql aren't printed need to fix rollback first
# change uniqueness so batchid is unique for username maybe??

sub new {
  my $type = shift;
  ($uploadbatch::query) = @_;

  # This DBH handle should be used throughout the script disconnect on exit.
  $uploadbatch::dbh = &miscutils::dbhconnect("uploadbatch");

  # fix to change depending on domain later
  # try proxy thing first
  # changed by drew 3/30/2009 for breach
  #$uploadbatch::server_name = $ENV{'HTTP_X_FORWARDED_HOST'};
  $uploadbatch::server_name = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];
  if ($uploadbatch::server_name eq "") {
    # then try SERVER_NAME
    $uploadbatch::server_name = $ENV{'SERVER_NAME'};
    if ($uploadbatch::server_name eq "") {
      # DEFAULT to pay1
      $uploadbatch::server_name = "pay1.plugnpay.com";
    }
  }

  $uploadbatch::script_location = "https://$uploadbatch::server_name/admin/uploadbatch.cgi";
  #$uploadbatch::script_location = "https://" . $ENV{'SERVER_NAME'} . $ENV{'SCRIPT_NAME'};

  # generate a batchid if none was sent
  my $merchant = "";
  if (defined $uploadbatch::query) {
    $uploadbatch::batchid = $uploadbatch::query->param('batchid');
    # strip spaces everything else should be ok
    $uploadbatch::batchid =~ s/[^a-zA-Z0-9\_\-]//g;

    $merchant = $uploadbatch::query->param('merchant');
    $merchant = lc($merchant);
    $merchant =~ s/[^a-z0-9]//g;
  }

  if ($uploadbatch::batchid eq "") {
    $uploadbatch::batchid = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  }

  # used to store info on failed transactions
  $uploadbatch::failure_hash = ();

  my $accountName;
  eval {
    $accountName= new PlugNPay::Environment()->get("PNP_ACCOUNT");
  };
  
  $uploadbatch::merchant = $accountName;
  if ($merchant ne "") {
    my $la = new PlugNPay::GatewayAccount::LinkedAccounts($accountName);
    if ($la->isLinkedTo($merchant)) {
      $uploadbatch::merchant = $merchant;
    }
  }

  my $gatewayAccount = new PlugNPay::GatewayAccount($uploadbatch::merchant);
  $uploadbatch::companyName = $gatewayAccount->getCompanyName();

  # Grab processing priority from Features
  my $accountFeatures = new PlugNPay::Features($uploadbatch::merchant,'general');
  if (($accountFeatures->get('upload_batch_priority') > 0) || ($accountFeatures->get('upload_batch_priority') < 0)){
    $uploadbatch::upload_batch_priority = $accountFeatures->get('upload_batch_priority');
  }
  else {
    $uploadbatch::upload_batch_priority = 0;
  }
  $uploadbatch::upload_batch_priority = substr($uploadbatch::upload_batch_priority,0,2);

  return [], $type;
}

# used to validate the batch file being uploaded and inserts the data into the tables
sub batchupload {
  my $valid_batchid = "no";
  my $number_of_trxs = 0;
  my %failure_hash = ();
  my $insert_tran_cnt = 20;

  my $header_format = $uploadbatch::query->param('header_format');
  my $header = "";

  my $trans_id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my $firstorderid = $trans_id;
  my $lastorderid = "";

  ## DCP 20070508
  &head();

  # Make sure this batchid does not exist.
  my $sth = $uploadbatch::dbh->prepare(q{
     SELECT batchid
     FROM batchfile
     WHERE batchid=?
    }) or print "__LINE__,__FILE__,Can't prepare: $DBI::errstr";
  $sth->execute("$uploadbatch::batchid") or print "__LINE__,__FILE__,Can't prepare: $DBI::errstr"; 
  my ($batchid_exists) = $sth->fetchrow;
  $sth->finish;

  if ($batchid_exists eq "") {
    $valid_batchid = "yes";
    my $file_data = $uploadbatch::query->upload('data');
    my $file_type = "";
    if ($file_data ne "") {
      $file_type = $uploadbatch::query->uploadInfo($file_data)->{'Content-Type'};
    }
    else {
    #  &head();
      print "<P> You must select a valid file when submitting your batch.</P>\n";
      &tail();
      return;
    }

    if (($file_type eq "text/plain") && ($valid_batchid eq "yes")) {
      # get header if needed
      if (($header_format eq "") || ($header_format eq "yes")) {
        $header = <$file_data>;
        $header =~ s/\r//g;
        $header =~ s/\n//g;
        if ($header !~ /^\!batch/i) {
          # &head();
          print "Invalid header, check and attempt upload again.<br>\n";
          &tail();
          $uploadbatch::dbh->disconnect;
          exit;
        }
      }

      if ($header =~ /\^/) {  # replacement for nisc
        $header =~ s/\^/\t/g;
      }
      elsif ($header =~ /\%09/) {  # replacement for consumers
        $header =~ s/\%09/\t/g;
      }

      my ($junk1,$junk2,$trans_time) = &miscutils::gendatetime();
      my @array1 = ();
      my @array2 = ();
      while (<$file_data>) {
        $_ =~ s/\r//g;
        $_ =~ s/\n//g;

        if ($_ =~ /\^/) {  # replacement for nisc
          $_ =~ s/\^/\t/g;
        }
        elsif ($_ =~ /\%09/) {  # replacement for consumers
          $_ =~ s/\%09/\t/g;
        }

        my $temp_line = $_;
        $temp_line =~ s/\t//g;

        if (($_ ne "") && ($temp_line ne "") && ($_ !~ /^\!batch/i)) {
          if ($number_of_trxs =~ /000$/) {
            print ".";
          }

          if ($number_of_trxs > 15000) {
            print "<P> The file you have attempted to upload is too large.  Please keep files below 15,000 transactions.</P>\n";
            &tail();
          }
          elsif (($number_of_trxs > 50) && ($uploadbatch::merchant eq "pnpdemo2")) {
            print "<P> Test accounts are limited to 50 transaction per batch file.  Please keep files below 50 transactions.</P>\n";
            &tail();
          }

          @array2 = ("$uploadbatch::batchid","$trans_id","$uploadbatch::merchant","$_","$trans_time","$number_of_trxs","$ENV{'SUBACCT'}","$header","$header_format");
          $array1[++$#array1] = [@array2];
          $number_of_trxs++;
          $lastorderid = $trans_id;
          $trans_id = &miscutils::incorderid($trans_id);
          if (@array1 == $insert_tran_cnt) {
            &insert_transaction_multi(\@array1);
            @array1 = ();
          }
        }
      }

      ## Last
      if (@array1 > 0) {
        &insert_transaction_multi(\@array1);
        @array1 = ();
      }

      &insert_batch($uploadbatch::batchid,$firstorderid,$lastorderid,$uploadbatch::merchant,$header,$uploadbatch::query->param('header_format'),$uploadbatch::query->param('emailresults'),$uploadbatch::query->param('sndmail'));
      &display_results($uploadbatch::batchid,$number_of_trxs);
    }
    else {
      # &head();
      print "<P> The file you have attempted to upload is not a plain text file.  Please check the file you are trying to upload and try again.</P>\n";
      &tail();
    }
  }
  else {
    # &head();
    print "<P> A file with a batch id of $uploadbatch::batchid is currently in the system.  Please select a different batch id and upload your file again.</P>\n";
    &tail();
  }
} # end uploadbatch

sub insert_transaction_old {
  my ($batchid,$orderid,$username,$line,$trans_time,$number_of_trxs,$subacct) = @_;
  my $sth = $uploadbatch::dbh->prepare(q{
      INSERT INTO batchfile
      (`batchid`, `trans_time`, `orderid`, `processid`, `username`, `status`, `line`, `subacct`)
      VALUES (?,?,?,?,?,?,?,?)
    }) or &mark_as_failed($number_of_trxs+1,"database");
  $sth->execute("$batchid","$trans_time","$orderid","none","$username","locked","$line","$subacct") or &mark_as_failed($number_of_trxs+1,"database");
  $sth->finish();
}

sub insert_transaction_multi {
  my ($data) = @_;
  my ($batchid,$orderid,$username,$line,$trans_time,$number_of_trxs,$subacct,$header,$header_format);

  my @placeholder = (); 
  my $qstr = " INSERT INTO batchfile (batchid,trans_time,orderid,processid,username,status,line,subacct,priority) VALUES ";

  foreach my $var (@$data) { 
    ($batchid,$orderid,$username,$line,$trans_time,$number_of_trxs,$subacct,$header,$header_format) = @$var;

    if ($batchid eq "") {
      print "Missing BatchID. - Exiting.\n";
      exit; 
    } 

    if ($username eq "") {
      print "Missing Username. - Exiting.\n";
      exit;
    }

    # need to enc the data in the line
    # for icverify only
    if ($header_format eq "icverify") {
      # split up the line
      my @data = split(/\,/,$line);
      # enc the sensitive data
      my ($enccardnumber,$enclength) = &rsautils::rsa_encrypt_card("$data[3]",'/home/p/pay1/pwfiles/keys/key','log');
      $data[3] = $enclength . "|" . $enccardnumber;
      my $newline = "";
      # rebuild the line
      foreach my $value (@data) {
        $newline .= $value . ",";
      }
      chop $newline;
      $line = $newline;
    }
    # this covers pnp sensitive data and authnet
    elsif ($header =~ /(card-number|card_number|card-cvv|card_cvv|accountnum|x_card_num|x_card_code|x_bank_acct_num)/i) {
      # split up the important data
      my @header_vars = split(/\t/,$header);
      my @data = split(/\t/,$line);
      my $newline = "";
      # loop through the header to find the sensitive data
      for (my $pos=0;$pos<=$#header_vars;$pos++) {
        if ($header_vars[$pos] =~ /(card-number|card_number|card-cvv|card_cvv|accountnum|x_card_num|x_card_code|x_bank_acct_num)/i) {
          #print "CN: $data[$pos] <br>\n";
          my ($encdata,$enclength) = &rsautils::rsa_encrypt_card("$data[$pos]",'/home/p/pay1/pwfiles/keys/key','log');
          $data[$pos] = $enclength . "|" . $encdata;
        }
        # rebuild the line
        $newline .= $data[$pos] . "\t";
      }
      chomp $newline;
      $line = $newline;
    }
    #$line =~ s/"/\\"/g;
    $line =~ s/'/\\'/g;

    $qstr .= "\n(?,?,?,?,?,?,?,?,?),";
    push(@placeholder, "$batchid","$trans_time","$orderid","none","$username","locked","$line","$subacct","$uploadbatch::upload_batch_priority");
  }
  chop $qstr;
  #print "QSTR:$qstr\n";
  #return;

  my $sth = $uploadbatch::dbh->prepare(qq{$qstr}) or &mark_as_failed($number_of_trxs+1,"database");
  $sth->execute(@placeholder) or &mark_as_failed($number_of_trxs+1,"database");
  $sth->finish();
}

sub insert_transaction {
  my ($batchid,$orderid,$username,$line,$trans_time,$number_of_trxs,$subacct,$header,$header_format) = @_;

  # check header for card number, cvv, accountnum,
  # icverify column 4
  # x_card_num authnet 
  # x_Card_Num
  # x_card_code
  # x_Card_Code
  # x_bank_acct_num

  if ($batchid eq "") {
    print "Missing BatchID. - Exiting\n";
    exit;
  }

  if ($username eq "") {
    print "Missing Username. - Exiting.\n";
    exit;
  }


  # need to enc the data in the line
  # for icverify only
  if ($header_format eq "icverify") {
    # split up the line
    my @data = split(/\,/,$line);
    # enc the sensitive data
    my ($enccardnumber,$enclength) = &rsautils::rsa_encrypt_card("$data[3]",'/home/p/pay1/pwfiles/keys/key','log');
    $data[3] = $enclength . "|" . $enccardnumber;
    my $newline = "";
    # rebuild the line
    foreach my $value (@data) {
      $newline .= $value . ",";
    }
    chop $newline;
    $line = $newline;
  }
  # this covers pnp sensitive data and authnet
  elsif ($header =~ /(card-number|card_number|card-cvv|card_cvv|accountnum|x_card_num|x_card_code|x_bank_acct_num)/i) {
    # split up the important data
    my @header_vars = split(/\t/,$header);
    my @data = split(/\t/,$line);
    my $newline = "";
    # loop through the header to find the sensitive data
    for (my $pos=0;$pos<=$#header_vars;$pos++) {
      if ($header_vars[$pos] =~ /(card-number|card_number|card-cvv|card_cvv|accountnum|x_card_num|x_card_code|x_bank_acct_num)/i) {
#print "CN: $data[$pos] <br>\n";
        my ($encdata,$enclength) = &rsautils::rsa_encrypt_card("$data[$pos]",'/home/p/pay1/pwfiles/keys/key','log');
        $data[$pos] = $enclength . "|" . $encdata;
      }
      # rebuild the line
      $newline .= $data[$pos] . "\t";
    }
    chomp $newline;
    $line = $newline;
  }

  my $sth = $uploadbatch::dbh->prepare(q{
      INSERT INTO batchfile
      (batchid,trans_time,orderid,processid,username,status,line,subacct,priority)
      VALUES (?,?,?,?,?,?,?,?,?)
    }) or &mark_as_failed($number_of_trxs+1,"database");
  $sth->execute("$batchid","$trans_time","$orderid","none","$username","locked","$line","$subacct","$uploadbatch::upload_batch_priority") or &mark_as_failed($number_of_trxs+1,"database");
  $sth->finish();
}

sub insert_batch {
  my ($batchid,$firstorderid,$lastorderid,$username,$header,$headerflag,$emailaddress,$emailflag) = @_;

  my ($orderid,$trans_date,$trans_time) = &miscutils::gendatetime();
  
  my $sth = $uploadbatch::dbh->prepare(q{
      INSERT INTO batchid
      (batchid,trans_time,processid,status,firstorderid,lastorderid,username,headerflag,header,emailflag,emailaddress,hosturl)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    }) or &rollback_batch("$batchid");
  $sth->execute("$batchid","$trans_time","none","locked","$firstorderid","$lastorderid","$username","$headerflag","$header","$emailflag","$emailaddress","$uploadbatch::server_name") or &rollback_batch("$batchid");
  $sth->finish;
}

sub rollback_batch {
  my ($batchid) = @_;

  my $sth = $uploadbatch::dbh->prepare(q{
      DELETE FROM batchfile
      WHERE batchid=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid");
  $sth->execute("$batchid") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid");
  $sth->finish;

  #$number_of_trxs = 0;

  &mark_as_failed(0,"batch upload error contact helpdesk.");
}

sub mark_as_failed {
  my ($line_number,$type) = @_;

 # print "LINE$line_number, TYPE:$type<p>\n";

  $uploadbatch::failure_hash{$line_number} = $type;
}

sub display_results {
  my ($batchid,$number_of_trxs) = @_;
  my %reason_hash = ();
  my $total_failures = 0;

  # &head();

  print "$number_of_trxs transactions have been uploaded.<br>\n";

  if (keys(%uploadbatch::failure_hash) > 0) { 
    print "The following line numbers failed in your file.<br>\n";

    foreach my $key (sort keys %uploadbatch::failure_hash)  {
      print $key . "\&nbsp;" . $uploadbatch::failure_hash{$key} . "<br>\n";
      $reason_hash{$uploadbatch::failure_hash{$key}}++; 
      $total_failures++;
    }
  }

  foreach my $key (sort keys %reason_hash) {
    print $reason_hash{$key} . " failed because \"" . $key . "\"<br>\n";
  }

  print "Use this <a href=\"uploadbatch.cgi?function=checkstatus&batchid=$batchid\&merchant=$uploadbatch::merchant\">link</a> to check the status of your batch.<br>\n";

  if ($total_failures > 0) {
    print "There were some problems with your batch file.  If these<br>\n";
    print "errors do not seem critical you may confirm the batch and it<br>\n";
    print "will be processed.\n";
    print "<form method=\"post\" action=\"$uploadbatch::script_location\">\n";
    print "  <input type=\"hidden\" name=\"function\" value=\"confirmbatch\">\n";
    print "  <input type=\"hidden\" name=\"merchant\" value=\"$uploadbatch::merchant\">\n";
    print "  <input type=\"submit\" value=\"confirm\">\n";
    print "</form>\n";
  }
  else {
    &finalize_batch($batchid);
  }
  &tail();
}

sub finalize_batch {
  my ($batchid) = @_;

  my $sth = $uploadbatch::dbh->prepare(q{
      UPDATE batchfile
      SET status='pending'
      WHERE batchid=?
    }) or &rollback_batch("$batchid");
  $sth->execute("$batchid") or &batch_failure("$batchid");
  $sth->finish;

  $sth = $uploadbatch::dbh->prepare(q{
      UPDATE batchid
      SET status='pending'
      WHERE batchid=?
    }) or &rollback_batch("$batchid");
  $sth->execute("$batchid") or &batch_failure("$batchid");
  $sth->finish;
}

sub batch_failure {
  my ($batchid) = @_;

  print "BATCH FAILURE ATTEMPTING TO ROLLBACK.<br>";
  &rollback_batch($batchid);
  print "There was a problem finalizing your batch.<br>\n";
  print "Please contact the helpdesk.  The transactions will<br>\n";
  print "not be processed and an attempt has been made to remove<br>\n";
  print "them from the batch file system.<br>\n";

}

sub display_batch_status {
  my ($type,$batchid) = @_;

  &head($uploadbatch::script_location . "?function=checkstatus\&batchid=$batchid\&merchant=$uploadbatch::merchant");

  my $sth = $uploadbatch::dbh->prepare(q{
      SELECT COUNT(status)
      FROM batchfile
      WHERE status='success'
      AND batchid=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid count success");
  $sth->execute("$batchid") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid count success");
  my $success_count = $sth->fetchrow;
  $sth->finish;

  $sth = $uploadbatch::dbh->prepare(q{
      SELECT COUNT(status)
      FROM batchfile
      WHERE status='pending'
      AND batchid=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid count pending");
  $sth->execute("$batchid") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid count pending");
  my $pending_count = $sth->fetchrow;
  $sth->finish;

  $sth = $uploadbatch::dbh->prepare(q{
      SELECT COUNT(status)
      FROM batchfile
      WHERE status='locked'
      AND batchid=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid count locked");
  $sth->execute("$batchid") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid count locked");
  my $locked_count = $sth->fetchrow;
  $sth->finish;

  $sth = $uploadbatch::dbh->prepare(q{
      SELECT COUNT(status)
      FROM batchfile
      WHERE batchid=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid count total");
  $sth->execute("$batchid") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid count total");
  my $total_count = $sth->fetchrow;
  $sth->finish;
  
  print "<p>This page will refresh every 10 minutes.</p>\n";
  print "<table border=\"1\" cellspacing=\"0\" cellpadding=\"2\">\n";
  print "  <tr>\n";
  print "    <th bgcolor=\"#dddddd\"><p>Status</p></th>\n";
  print "    <th bgcolor=\"#dddddd\"><p>Count</p></th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><p>Pending:</p></td>\n";
  print "    <td><p>$pending_count</p></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><p>Locked:</p></td>\n";
  print "    <td><p>$locked_count</p></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><p>Success:</p></td>\n";
  print "    <td><p>$success_count</p></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><p>Total:</p></td>\n";
  print "    <td><p>$total_count</p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  if (($success_count == $total_count) && ($total_count != 0)) {
    print "<p>BatchID $batchid is complete.<br><a href=\"$uploadbatch::script_location?function=retrieveresults\&batchid=$batchid\&merchant=$uploadbatch::merchant\">Click here for results.</a></p>\n";
  }

  &tail;
}

sub head {
  my ($meta_link) = @_;

  print "Content-Type: text/html\n\n";
  print "<html>\n";
  print "<head>\n";
  print "<title>Batch Upload Administration</title>\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link href=\"/css/style.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  if ($meta_link ne "") { 
    print "<meta http-equiv=\"Refresh\" content=\"600; URL=$meta_link\">\n";
  }
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" onLoad=\"self.focus()\">\n";

  print "<div align=\"center\">\n";
  print "<table cellspacing=\"0\" cellpadding=\"4\" border=\"0\" width=\"500\">\n";
  print "  <tr>\n";
  print "    <td align=\"center\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corp. Logo\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th align=\"center\"><font size=\"4\" face=\"Arial,Helvetica,Univers,Zurich BT\">Batch Upload Administration</font></th>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th align=\"center\"><font size=\"3\" face=\"Arial,Helvetica,Univers,Zurich BT\">$uploadbatch::companyName</font></th>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<br></div>\n";

  print "  <div align=center>\n";
}

sub tail {
  print "  </div>\n";
  print "</body>\n";
  print "</html>\n";
}

sub retrieve_results {
  my ($type,$batchid,$username) = @_;

  print "Content-Type: text/plain\n\n";

  # get batch header flag
  my $sth = $uploadbatch::dbh->prepare(q{
      SELECT headerflag,header
      FROM batchid
      WHERE username=?
      AND batchid=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid");
  $sth->execute("$username","$batchid") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid");
  my ($headerflag, $header) = $sth->fetchrow;
  $sth->finish;

  if ($headerflag eq "yes") {
    print "FinalStatus\tMErrMsg\tresp-code\torderID\tauth-code\tavs-code\tcvvresp\t$header\n";
  } 

  my $tranfoundflag = 0;

  my $sth2 = $uploadbatch::dbh->prepare(q{
      SELECT line
      FROM batchresult
      WHERE batchid=?
      AND username=?
    }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid");
  $sth2->execute("$batchid","$username") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid");
  while (my ($line) = $sth2->fetchrow) {
    if ($uploadbatch::query->param('transtatus') eq "successonly") {
      if ($line =~ /^success/) {
        $tranfoundflag = 1;
        print $line . "\n";
      }
    }
    elsif ($uploadbatch::query->param('transtatus') eq "failureonly") {
      if ($line !~ /^success/) {
        print $line . "\n";
        $tranfoundflag = 1;
      }
    }
    else {
      print $line . "\n";
    }
    if (($uploadbatch::query->param('transtatus') =~ /successonly|failureonly/) && ($tranfoundflag == 0)) {
      print "No Records Found\n";
    }
  }
  $sth2->finish;
}

########################################################################

sub list_batches {
  # lists recent batches, which were uploaded by the merchant

  my ($count, $batchid, $trans_time, $status, $firstorderid, $lastorderid);

  print "<table border=\"1\" cellspacing=\"0\" cellpadding=\"3\">\n";

  print "  <tr>\n";
  print "    <th bgcolor=\"#dddddd\" colspan=\"5\">Recent Batches:</th>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <th><p>Batch ID</p></th>\n";
  print "    <th><p>Date/Time (GMT)</p></th>\n";
  print "    <th><p>Status</p></th>\n";
  print "    <th><p>Trans Count</p></th>\n";
  print "    <th><p>&nbsp;</p></th>\n";
  print "  </tr>\n";

  my ($orderid,$date,$lookback_time) = &miscutils::gendatetime(-14*24*60*60);

  my $sth_main = $uploadbatch::dbh->prepare(q{
      SELECT batchid,trans_time,status,firstorderid,lastorderid
      FROM batchid
      WHERE trans_time>? AND username=?
      ORDER BY trans_time
    }) or die "Can't prepare: $DBI::errstr\n";
  $sth_main->execute("$lookback_time", "$uploadbatch::merchant") or print "Can't execute:: $DBI::errstr\n";
  while (my ($batchid,$trans_time,$status,$firstorderid,$lastorderid) = $sth_main->fetchrow) {
    my $first = Math::BigInt->new("$firstorderid");
    my $last = Math::BigInt->new("$lastorderid");

    print "  <tr rowspan=\"2\">\n";
    print "    <td><p><a href=\"$uploadbatch::script_location\?function=checkstatus\&batchid=$batchid\&merchant=$uploadbatch::merchant\">$batchid</a></p></td>\n";
    printf ("    <td><p>%02d\/%02d\/%04d  %02d\:%02d\:%02d</p></td>", substr($trans_time, 4, 2), substr($trans_time, 6, 2), substr($trans_time, 0, 4), substr($trans_time, 8, 2), substr($trans_time, 10, 2), substr($trans_time, 12, 2) );
    print "    <td><p>$status</p></td>\n";
    print "    <td><p>" . ($last - $first + 1) . "</p></td>\n";
    if ($status eq "success") {
      print "    <td><p><a href=\"$uploadbatch::script_location?function=retrieveresults\&batchid=$batchid\&merchant=$uploadbatch::merchant\">Download Results</p></a></td>\n";
    }
    else {
      print "    <td><p>&nbsp;</p></td>\n";
    }
    print "  </tr>\n";

    $count = $count + 1;
  }
  $sth_main->finish;

  if ($count < 1) {
    print "  <tr>\n";
    print "    <td colspan=\"6\"><p>Sorry, there is no recent upload batch information available.</p></th>\n";
    print "  </tr>\n";
  }

  print "</table>\n";

  return;
}

1;
