#!/usr/bin/perl

package uploadbatch_private;

require 5.001;
$| = 1;

use miscutils;
use CGI;
use Math::BigInt;
use strict;

# you know what this does
sub new {
  my $type = shift;
  ($uploadbatch_private::query) = @_;
  # This DBH handle should be used throughout the script disconnect on exit.
  $uploadbatch_private::dbh = &miscutils::dbhconnect("uploadbatch");
  $uploadbatch_private::script_location = "https://pay1.plugnpay.com/private/uploadbatch/index.cgi";
  $uploadbatch_private::sevendaysago = (&miscutils::gendatetime(-7*24*60*60))[2];
  $uploadbatch_private::onedayago = (&miscutils::gendatetime(-1*24*60*60))[2];
  $uploadbatch_private::lookback = (&miscutils::gendatetime(-4*24*60*60))[2];

  return [],$type;
}

# main menu displayed
sub main {
  my ($count);
  my ($batchid,$trans_time,$processid,$status,$firstorderid,$lastorderid,$username,$emailaddress,$hosturl);

  &head;

  &status();

  print "<TABLE border=1 cellspacing=0 cellpadding=2>\n";

  #my ($orderid,$date,$lookback_time) = &miscutils::gendatetime(-4*24*60*60);

  my %batch_hash = ();
  my $sth_main = $uploadbatch_private::dbh->prepare(qq{
               select batchid,trans_time,processid,status,firstorderid,lastorderid,username,emailaddress,hosturl
               from batchid
               where trans_time > ?
  }) or die "Can't prepare: $DBI::errstr\n";
  $sth_main->execute("$uploadbatch_private::lookback") or print "Can't execute:: $DBI::errstr\n";
  $sth_main->bind_columns(undef,\($batchid,$trans_time,$processid,$status,$firstorderid,$lastorderid,$username,$emailaddress,$hosturl));
  while ($sth_main->fetch) {
    $batch_hash{$batchid}{'trans_time'} = $trans_time;
    $batch_hash{$batchid}{'pid'} = $processid;
    $batch_hash{$batchid}{'status'} = $status;
    $batch_hash{$batchid}{'firstoid'} = $firstorderid;
    $batch_hash{$batchid}{'lastoid'} = $lastorderid;
    $batch_hash{$batchid}{'username'} = $username;
    $batch_hash{$batchid}{'hosturl'} = $hosturl;
  }
  $sth_main->finish;

  &gen_results_table(%batch_hash);

  print "</TABLE>\n";
  print "<P>\n";

  &search();

  &tail();
}

sub search {

  my @now = gmtime(time);
  my $current_year = $now[5]+1900;
  my $last_year = $current_year - 1;

  print "<FORM action=\"$uploadbatch_private::script_location\" method=\"post\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"query\">\n";

  print "<TABLE border=1 cellspacing=0 cellpadding=2>\n";
  print "  <TR class=\"menusection_title\">\n";
  print "    <TH colspan=2><b>Search:</b></TH>";
  print "  </TR>\n";
  print "  <TR>\n";
  print "    <TD class=\"leftside\">Username:</TD>\n";
  print "    <TD class=\"rightside\"><input type=\"text\" name=\"username\" size=\"16\" maxlength=\"16\"></TD>\n";
  print "  </TR>\n";
  print "  <TR>\n";
  print "    <TD class=\"leftside\">Start Date:</TD>\n";
  print "    <TD class=\"rightside\">" . &gen_date("start","$last_year","$current_year") . "</TD>\n";
  print "  </TR>\n";
  print "  <TR>\n";
  print "    <TD class=\"leftside\">End Date:</TD>\n";
  print "    <TD class=\"rightside\">" . &gen_date("end","$last_year","$current_year") . "</TD>\n";
  print "  </TR>\n";
  print "  <TR>\n";
  print "    <TD class=\"leftside\">Batch ID:</TD>\n";
  print "    <TD class=\"rightside\"><input type=\"text\" name=\"batchid\" size=\"16\" maxlength=\"30\"></TD>\n";
  print "  </TR>\n";
  print "  <TR>\n";
  print "    <TD class=\"rightside\" colspan=2><input type=\"submit\"></TD></FORM>\n";
  print "  </TR>\n";
  print "</TABLE\n";
}

# used to search for batchids
sub query {
  my ($trans_time,$processid,$status,$firstorderid,$lastorderid,$emailaddress);

  &head;

  # collect posted variables for search
  my $batchid = $uploadbatch_private::query->param('batchid');
  my $username = $uploadbatch_private::query->param('username');

  my $startmonth = $uploadbatch_private::query->param('startmonth');
  my $startday = $uploadbatch_private::query->param('startday');
  my $startyear = $uploadbatch_private::query->param('startyear');

  my $endmonth = $uploadbatch_private::query->param('endmonth');
  my $endday = $uploadbatch_private::query->param('endday');
  my $endyear = $uploadbatch_private::query->param('endyear');

  my $startdate = $startyear . $startmonth . $startday;
  my $enddate = $endyear . $endmonth . $endday;

  # build SQL for search
  my @placeholder = ();
  my $sql = "select batchid,trans_time,processid,status,firstorderid,lastorderid,username,emailaddress from batchid where";

  if ($username ne "") {
    $sql .= " username=?";
    push(@placeholder, "$username");
  }

  if ($batchid ne "") {
    if ($sql !~ /where$/) {
      $sql .= " and";
    }
    $sql .= " batchid=?";
    push(@placeholder, "$batchid");
  }

  if ($startdate != $enddate) {
    if ($sql !~ /where$/) {
      $sql .= " and";
    }
    my $starttime = $startdate . "000000";
    my $endtime = $enddate . "000000";
    
    $sql .= " trans_time between ? and ?";
    push(@placeholder, "$starttime", "$endtime");
  }
  else {
    if ($sql !~ /where$/) {
      $sql .= " and";
    }

    $sql .= " trans_time=?";
    push(@placeholder, $startdate."000000");
  }

  # run query and retrieve data
  my %batch_hash = ();
  my $sth_main = $uploadbatch_private::dbh->prepare(qq{$sql}) or die "prepare $DBI::errstr";
  my $result_count = $sth_main->execute(@placeholder) or print "Can't execute:: $DBI::errstr\n";
  $sth_main->bind_columns(undef,\($batchid,$trans_time,$processid,$status,$firstorderid,$lastorderid,$username,$emailaddress));
  while ($sth_main->fetch) {
    $batch_hash{$batchid}{'trans_time'} = $trans_time;
    $batch_hash{$batchid}{'pid'} = $processid;
    $batch_hash{$batchid}{'status'} = $status;
    $batch_hash{$batchid}{'firstoid'} = $firstorderid;
    $batch_hash{$batchid}{'lastoid'} = $lastorderid;
    $batch_hash{$batchid}{'username'} = $username;
  }
  $sth_main->finish;

  # output table of results
  print "<TABLE border=1 cellspacing=0 cellpadding=2>\n";
  &gen_results_table(%batch_hash);
  print "</TABLE>\n";

  &tail;
}

# used to retrieve details of a specific batchid
sub details {
  my $batchid = $uploadbatch_private::query->param('batchid');
  my ($count,$status);

  &head;
  my $sth_details = $uploadbatch_private::dbh->prepare(qq{
         select trans_time,processid,status,firstorderid,lastorderid,username,headerflag,header,emailflag,emailaddress,hosturl
         from batchid
         where batchid=?
  }) or die "prepare $DBI::errstr\n";
  $sth_details->execute("$batchid") or die "execute $DBI::errstr\n";
  my $details_hash = $sth_details->fetchrow_hashref;
  $sth_details->finish;

  print "<b>BatchID:</b> $batchid<br>\n";
  print "<b>Username:</b> $details_hash->{'username'}<br>\n";
  print "<b>Emailaddress:</b> $details_hash->{'emailaddress'}<br>\n";
  print "<b>Status:</b> $details_hash->{'status'}<br>\n";
  print "<b>PID:</b> $details_hash->{'processid'}<br>\n";
  print "<b>First oid:</b> $details_hash->{'firstorderid'}<br>\n";
  print "<b>Last oid:</b> $details_hash->{'lastorderid'}<br>\n";
  print "<b>Header Type:</b> $details_hash->{'headerflag'}<br>\n";
  print "<b>Email type:</b> $details_hash->{'emailflag'}<br>\n";
  print "<b>Header:</b> $details_hash->{'header'}<br>\n";
  print "<b>Results Link:</b> https://$details_hash->{'hosturl'}/admin/uploadbatch.cgi?function=retrieveresults\&batchid=$batchid<br>\n";
  print "<a href=\"/private/uploadbatch/index.cgi\?batchid=$batchid\&mode=download\">Download File</a><br>\n";
  print "<a href=\"/private/uploadbatch/index.cgi?batchid=$batchid\&username=$details_hash->{'username'}\&mode=viewresults\">View Results</a><br>\n";
  if (($details_hash->{'status'} eq "success") && ($details_hash->{'headerflag'} eq "yes")) {
    print "<a href=\"/private/uploadbatch/index.cgi\?batchid=" . $batchid . "\&username=" . $details_hash->{'username'} . "\&mode=voidbatch\">Generate Void File</a><br>\n";
  }


  my $sth_count = $uploadbatch_private::dbh->prepare(qq{
         select count(orderid),status
         from batchfile
         where batchid=?
         group by status
  }) or die "prepare $DBI::errstr\n";
  $sth_count->execute("$batchid") or die "execute $DBI::errstr\n";
  $sth_count->bind_columns(undef,\($count,$status));
  print "Status counts:<br>\n";
  my $locked_flag = 0;
  # count of trxs left to process
  my $process_count = 0;
  while ($sth_count->fetch) {
    if (($status eq "locked") && ($count > 0)) {
      $locked_flag = 1;
    }
    if (($status eq "pending") || ($status eq "locked")) {
      $process_count += $count;
    }
    print "<b>$status</b> $count<br>\n";
  }
  $sth_count->finish;

  # we always add 5 minutes to the estimate because a process.pl
  # should take at most 5 minutes to run these is a reason for this
  # leave it alone.
  if ($process_count > 0) {
    print "Estimated time to completion: " . ((($process_count * 2)/60) + 5) . " minutes<br>\n";
  }

  # only do this for drew
  if (($locked_flag == 1) && (($ENV{REMOTE_USER} eq "drew") || ($ENV{REMOTE_USER} eq "unplugged"))) {
    # get pid for current process.pl
    my $pid_result = `/usr/bin/ps -ef |/bin/grep "process.pl" |/bin/grep -v grep`;
    my @pids = ();
    if ($pid_result ne "") {
      my @lines = split(/\n/,$pid_result);
      foreach my $line (@lines) {
        $pids[++$#pids] = (split(/\s/,$line))[1];
      }
    }
    # get processids for locked trxs
    my $sth_pid = $uploadbatch_private::dbh->prepare(qq{
           select distinct processid
           from batchfile
           where batchid=?
           and trans_time between ? and ?
           and status=?
    }) or die "prepare $DBI::errstr\n";
    $sth_pid->execute("$batchid","$uploadbatch_private::sevendaysago","$uploadbatch_private::onedayago","locked") or die "execute $DBI::errstr\n";

    my $can_unlock = 1;

    while (my $data = $sth_pid->fetchrow_hashref) { 
      # make sure the processid is not still running
      my $batchpid = $data->{'processid'};
      foreach my $pid (@pids) {
        if ($pid eq $batchpid) {
          $can_unlock = 0;
        }
      }
    }
    $sth_pid->finish; 

    if ($can_unlock) {
      print "<a href=\"$uploadbatch_private::script_location?mode=unlock&batchid=$batchid&username=$details_hash->{'username'}\">unlock</a> <br>\n";
    }
  }

  if (($ENV{REMOTE_USER} eq "drew") || ($ENV{REMOTE_USER} eq "unplugged")) {
    print "<a href=\"$uploadbatch_private::script_location?mode=delbatch&batchid=$batchid&username=$details_hash->{'username'}\">delete batch</a> <br>\n";
  }
  
  &tail;
}

# used to delete a batch file
sub delbatch {
  my $batchid = $uploadbatch_private::query->param('batchid');
  my $username = $uploadbatch_private::query->param('username');

  if (($batchid ne "") && ($username ne "")) {
    my $sth_delbatch = $uploadbatch_private::dbh->prepare(qq{
           delete from batchfile
           where batchid=?
           and username=?
    }) or die "prepare $DBI::errstr\n";
    $sth_delbatch->execute($batchid,$username) or die "execute $DBI::errstr\n";

    $sth_delbatch = $uploadbatch_private::dbh->prepare(qq{
           delete from batchid
           where batchid=?
           and username=?
    }) or die "prepare $DBI::errstr\n";
    $sth_delbatch->execute($batchid,$username) or die "execute $DBI::errstr\n";

    $sth_delbatch->finish;
  }

  &head();
  print "Batch $batchid deleted for user $username<br>\n";
  &tail();
}
 
# used to download a batch file
sub download {
  my ($header,$line);

  my $batchid = $uploadbatch_private::query->param('batchid');

  my $sth_head = $uploadbatch_private::dbh->prepare(qq{
         select header
         from batchid
         where batchid=?
  }) or die "prepare $DBI::errstr\n";
  $sth_head->execute("$batchid") or die "execute $DBI::errstr\n";;
  $sth_head->bind_columns(undef,\($header));
  $sth_head->fetch;
  $sth_head->finish;

  print $header . "\n";

  my $sth_line = $uploadbatch_private::dbh->prepare(qq{
         select line
         from batchfile
         where batchid=?
  }) or die "prepare $DBI::errstr\n";
  $sth_line->execute("$batchid") or die "execute $DBI::errstr\n";
  $sth_line->bind_columns(undef,\($line));

  while ($sth_line->fetch) {
    print $line . "\n";
  }

  $sth_line->finish;
}

# used to generate select for date range selection
sub gen_date {
  my ($option_name,$start_date,$end_date,$selected_date) = @_;
  # option_name is required will be set to option_namemonth, option_nameday,
  # and option_nameyear
  # selected_date is optional will default to today if not passed
  # start_date and end_date are required so that the script calling this has
  # to pay attention to queries.  it can just be the year though the rest
  # is ignored
  
  my %endday = (1,31,2,28,3,31,4,30,5,31,6,30,7,31,8,31,9,30,10,31,11,30,12,31);

  my %month_hash = (1,"Jan",2,"Feb",3,"Mar",4,"Apr",5,"May",6,"Jun",7,"Jul",8,"Aug",9,"Sep",10,"Oct",11,"Nov",12,"Dec");

  my ($dummy,$selected_year,$selected_month,$selected_day);

  my $start_year = substr($start_date,0,4);
  my $end_year = substr($end_date,0,4);

  if ($selected_date ne "") {
    $selected_year = substr($selected_date,0,4);
    $selected_month = substr($selected_date,4,2);
    $selected_day = substr($selected_date,6,2);
  }
  else {
    ($dummy,$dummy,$dummy,$selected_day,$selected_month,$selected_year) = gmtime(time());
    $selected_year = $selected_year + 1900;
    $selected_month = $selected_month + 1;
  }

  my $html = "<select name=\"" . $option_name ."month\">\n";

  my %selected_month_hash = ("$selected_month"," selected");

  for (my $i=1; $i<=12; $i++) {
    my $value = sprintf("%02d",$i);
    $html .= "<option value=\"$value\" $selected_month_hash{$i}>$month_hash{$i}</option>\n";
  }
  $html .= "</select>\n";

  $html .= "<select name=\"" . $option_name . "day\">\n";
  my %selected_day_hash = ("$selected_day"," selected");
  for (my $i=1; $i<=31; $i++) {
    my $value = sprintf("%02d",$i);
    $html .= "<option value=\"$value\" $selected_day_hash{$value}>$value</option>\n";
  }
  $html .= "</select>\n";

  $html .= "<select name=\"" . $option_name . "year\">\n";
  my %selected_year_hash = ("$selected_year"," selected");
  for(my $i=$start_year; $i<=$end_year; $i++) {
    $html .= "<option value=\"$i\" $selected_year_hash{$i}>$i</option>\n";
  }
  $html .= "</select>\n";

  return $html;
}

# the head stupid
sub head {
  print "<HTML>\n";
  print "<HEAD><TITLE>Upload Batch Admin</TITLE></Head>\n";
  print "<link href=\"/css/style_private.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<BODY>\n";
}

# the tail stupid
sub tail {
  print "</BODY>\n";
  print "</HTML>\n";
}

# used to generate table of batches from a query
sub gen_results_table {
  my (%batch_hash) = @_;

  #print "<TR><TH>User</TH><TH>Batch ID</TH><TH>Time</TH><TH>Status</TH><TH>Pid</TH><TH>TRXs</TH></TR>\n";
  print "<TR><TH>User</TH><TH>Batch ID</TH><TH>Time</TH><TH>Status</TH><TH>TRXs</TH></TR>\n";

  my $color = 1;
  foreach my $batchid (sort {return $batch_hash{$a}{'trans_time'} cmp $batch_hash{$b}{'trans_time'}} keys %batch_hash) {
    my $first = Math::BigInt->new("$batch_hash{$batchid}{'firstoid'}");
    my $last = Math::BigInt->new("$batch_hash{$batchid}{'lastoid'}");
    if ($color == 1) {
      print "  <TR class=\"listrow_color1\" rowspan=2>\n";
    }
    else {
      print "  <TR class=\"listrow_color0\" rowspan=2>\n";
    }
    #print "<TR rowspan=\"2\">\n";
    print "  <TD>$batch_hash{$batchid}{'username'}</TD>\n";
    print "  <TD><a href=\"/private/uploadbatch/index.cgi?batchid=$batchid\&mode=details\">$batchid</a></TD>\n";
    print "  <TD>$batch_hash{$batchid}{'trans_time'}</TD>\n";
    print "  <TD>$batch_hash{$batchid}{'status'}</TD>\n";
    # print "  <TD>$batch_hash{$batchid}{'pid'}</TD>\n";
    print "  <TD>" . ($last - $first + 1) . "</TD>\n";
    print "</TR>\n";

    $color = ($color + 1) % 2;
  }
}


sub status {
  print "<table border=0 cellspacing=0 cellpadding=2>\n";

  # list current number of running process.pl
  my $pid_result = `/usr/bin/ps -ef |/bin/grep \"process.pl\" |/bin/grep -v grep`;
  my @pid_lines = split(/\n/,$pid_result);
  print " <tr><td>\n";
  print " <b>Currently running " . ($#pid_lines + 1) . "</b>\n";
  print "  </tr></td>\n";


  print " <tr><td><b>\n";
  # check /tmp/collectbatch.pid
  if (-e "/tmp/collectbatch.pid") {
    my $file_age = (stat "/tmp/collectbatch.pid")[9];
    # if collectbatch.pid hasn't changed in 1 hour it probably needs to be fixed
    if ((time() - $file_age) >= (60*60)) {
      print "<font color=\"#ff0000\">/tmp/collectbatch.pid is stale check and delete.</font>\n";
    }
    else {
      print "/tmp/collectbatch.pid is good.\n";
    }
  }
  else {
    print "/tmp/collectbatch.pid is good.\n";
  }

  print "</b></td></tr>\n";

  # check /home/p/pay1/outagefiles/highvolume.txt
  if (-e "/home/p/pay1/outagefiles/highvolume.txt") {
    print " <tr><td>\n";
    print "<font color=\"#ff0000\">high volume collectbatch.pl not allowed to run.</font>\n";
    print "</td></tr>\n";
  }

  # /home/p/pay1/private/uploadbatch/stopcollectbatch.txt
  if (-e "/home/p/pay1/private/uploadbatch/stopcollectbatch.txt") {
    print " <tr><td>\n";
    print "<font color=\"#ff0000\">collectbatch.pl has been forced to stop.</font>\n";
    print "</td></tr>\n";
  }
 
  print "</table>\n";
}

sub unlockbatch {
  my $batchid = $uploadbatch_private::query->param('batchid');
  my $username = $uploadbatch_private::query->param('username');

  &head();

  # exit if batchid or username are empty
  if (($batchid eq "") || ($username eq "")) {
    print "Bad you:  BatchID and/or Username Missing <br>\n";
    &tail();
    return;
  }

  print "batchid: $batchid <br>\n";
  print "username: $username <br>\n";

  my $bid = &queryBatchfile($username,$batchid);

  print "BID:$bid\n";

  if ($bid ne "") {
    &updateStatus($username,$batchid);
  }

  &tail();
}

sub createvoidbatch {
  # this generates a file of voids for the batch
  my $batchid = $uploadbatch_private::query->param('batchid');
  my $username = $uploadbatch_private::query->param('username');

  my ($header,$line);
  my @result = ();

  # trxs must be auth only
  # must get orderID from results file

  my $sth_head = $uploadbatch_private::dbh->prepare(qq{
         select header
         from batchid
         where batchid=?
         and username=?
  }) or die "prepare $DBI::errstr\n";
  $sth_head->execute($batchid,$username) or die "execute $DBI::errstr\n";
  $sth_head->bind_columns(undef,\($header));
  $sth_head->fetch;
  $sth_head->finish;

  my @header_array = (("FinalStatus","MErrMsg","resp-code","orderID","auth-code","avs-code","cvvresp"),split(/\t/,$header));



  my $sth_batchresult = $uploadbatch_private::dbh->prepare(qq{
         select line
         from batchresult
         where batchid=?
         and username=?
  }) or die "prepare $DBI::errstr\n";
  $sth_batchresult->execute($batchid,$username) or die "execute $DBI::errstr\n";
  $sth_batchresult->bind_columns(undef,\($line));
  while ($sth_batchresult->fetch) {
    # process the line here pull out orderID, card-amount, trx type
    my @entries = split(/\t/,$line);
    my %temp_hash = ();
    for (my $pos=0;$pos<=$#header_array;$pos++) {
      $temp_hash{$header_array[$pos]} = $entries[$pos];
    }

    if ($temp_hash{"!BATCH"} eq "auth") {
      $result[++$#result] = "void\t" . $temp_hash{'orderID'} . "\t" . $temp_hash{'card-amount'} . "\tauth\n";
    }
    else {
      @result = ();
      last;
    }
  }
  $sth_batchresult->finish;

  if ($#result >= 0) {
    print "!BATCH\torderID\tcard-amount\ttxn-type\n";
    foreach my $entry (@result) {
      print $entry;
    }
  }
  else {
    print "This is not a normal batch of auths can\'t void\n";
  }

}

sub viewresults {
  my $batchid = $uploadbatch_private::query->param('batchid');
  my $username = $uploadbatch_private::query->param('username');

  # get batch header flag
  my $headerflag = "";
  my $header = "";
  my $line = "";

  my $sth = $uploadbatch_private::dbh->prepare(qq{
          select headerflag,header
          from batchid
          where username=?
          and batchid=?
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid");
  $sth->execute("$username", "$batchid") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid");
  $sth->bind_columns(undef,\($headerflag,$header));
  $sth->fetch;
  $sth->finish;

  if ($headerflag eq "yes") {
    print "FinalStatus\tMErrMsg\tresp-code\torderID\tauth-code\tavs-code\tcvvresp\t$header\n";
  }

  my $tranfoundflag = 0;

  my $sth2 = $uploadbatch_private::dbh->prepare(qq{
          select line
          from batchresult
          where batchid=?
          and username=?
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr $batchid");
  $sth2->execute("$batchid", "$username") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr $batchid");
  $sth2->bind_columns(undef,\($line));
  while ($sth2->fetch()) {
    print $line . "\n";
  }
  $sth2->finish;
}


sub updateStatus {
  my ($username,$batchid) = @_;
  my ($bid);
  my $sth = $uploadbatch_private::dbh->prepare(qq{
        update batchfile
        set status=?
        where batchid=?
        and username=?
        and status=?
  }) or &error_email("666","Line " . __LINE__ . "\n Execute $DBI::errstr\n");
  $sth->execute('pending',$batchid,$username,'locked') or &error_email("666","Line " . __LINE__ . "\n Execute $DBI::errstr\n");
  $sth->finish;


  my $checkBatchID = &queryBatchfile($username,$batchid);

  if ($checkBatchID ne "") {
    print "Error - Update Did Not Work\n";
  }
  else {
    print "BatchID $batchid status set to pending\n";
  }
}



sub queryBatchfile {
  my ($username,$batchid) = @_;
  my ($bid); 
  my $sth = $uploadbatch_private::dbh->prepare(qq{
        select batchid 
        from batchfile
        where status=?
        and username=?
        and batchid=?
  }) or &error_email("666","Line " . __LINE__ . "\n Execute $DBI::errstr\n");
  $sth->execute('locked',$username,$batchid) or &error_email("666","Line " . __LINE__ . "\n Execute $DBI::errstr\n");
  my ($bid) = $sth->fetchrow;
  $sth->finish;

  return $bid;


}

1;
