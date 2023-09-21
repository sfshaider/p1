#!/usr/local/bin/perl

require 5.001;
$|=1;

package reseller_reports;

use miscutils;
use htmlutils;
use CGI;

sub new {
  my $type = shift;

  $reseller_reports::path_cgi = "index.cgi";

  $query = new CGI;

  $reseller_reports::dbh_misc = &miscutils::dbhconnect("pnpmisc");
  $reseller_reports::dbh_data = &miscutils::dbhconnect("pnpdata");

  return [], $type;
}

sub disconnect {
  $reseller_reports::dbh_misc->disconnect();
  $reseller_reports::dbh_data->disconnect();
}

sub function {
  return $query->param('function');
}

sub format {
  return $query->param('format');
}

sub main {
  &head();
  &count_form();
  &tail();
}

sub count_form {
  print "    <tr>\n";
  print "      <th rowspan=\"2\">Volpay Transaction Report</th>\n";
  print "    </tr>\n";

  print "   <tr>\n";
  print "     <td>&nbsp;\n";
  print "     </td>\n";
  print "   </tr>\n";

  print "   <tr>\n"; 
  print "     <td>&nbsp;\n";
  print "     </td>\n";
  print "   </tr>\n";

  print "    <tr>\n";
  print "      <td>\n";
  print "        <form action=\"\" method=\"post\">\n";
  print "          <input type=\"hidden\" name=\"function\" value=\"volpay_report\">\n";
  print "      </td>\n";
  print "    </tr>\n";

  print "    <tr>\n";
  print "      <td>\n";
  print "Start: " . &htmlutils::gen_dateselect("start",2005,2006);
  print "      </td>\n";
  print "    </tr>\n";

  print "    <tr>\n";
  print "      <td>\n";
  print "End:&nbsp; " . &htmlutils::gen_dateselect("end",2005,2006);
  print "      </td>\n";
  print "    </tr>\n";

  print "   <tr>\n";
  print "     <td>&nbsp;\n";
  print "     </td>\n"; 
  print "   </tr>\n";
  
  print "    <tr>\n";
  print "      <td>\n";
  print "        Username: <select name=\"username\">\n";
  print "          <option value=\"ALL\"> All </option>\n";
  my @userlist = &user_list_volpay();
  
  foreach my $username (@userlist) {
    print "          <option value=\"$username\">$username</option>\n";
  }

  print "        </select>\n";
  print "      </td>\n";
  print "    </tr>\n";

  print "   <tr>\n";
  print "     <td>&nbsp;\n";
  print "     </td>\n"; 
  print "   </tr>\n";

  print "    <tr>\n";
  print "      <td>\n";
  print "       Report Format:  <select name=\"format\">\n";
  print "          <option value=\"text\">Text</option>\n";
  print "          <option value=\"html\">HTML</option>\n";
  print "        </select>\n";
  print "      </td>\n";
  print "    </tr>\n";

  print "   <tr>\n";
  print "     <td>&nbsp;\n";
  print "     </td>\n"; 
  print "   </tr>\n";

  print "    <tr>\n";
  print "      <td>\n";
  print "          <input type=\"submit\">\n";
  print "        </form>\n";
  print "      </td>\n";
  print "    </tr>\n";
  
}

sub head {
  print "<html>\n";
  print "<head>\n";
  print "<title> Reseller Report Administration</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"stylesheet.css\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "  <table>\n";
}

sub tail {
  print "  </table>\n";
  print "</body>\n";
  print "</html>\n";
}

sub volpay_report {
  my $username = $reseller_reports::query->param('username');
  my $format = $reseller_reports::query->param('format');
  
  my $startdate = $reseller_reports::query->param('start_year') . $reseller_reports::query->param('start_month') . $reseller_reports::query->param('start_day');
  my $enddate = $reseller_reports::query->param('end_year') . $reseller_reports::query->param('end_month') . $reseller_reports::query->param('end_day');

  my $starttime = &miscutils::strtotime($startdate);
  my $endtime = &miscutils::strtotime($enddate);
  my $difference = $endtime - $starttime;

  if ($difference > (90*24*60*60)) {
    print "Please try a different date range\n";
    exit;
  }

  my $sql_where = "";

  if ($username eq "ALL") {
    my @user_list = &user_list_volpay();
    $sql_where = "username in (";
    foreach my $username (@user_list) {
      $sql_where .= "\'$username\',";
    }
    chop $sql_where;
    $sql_where .= ")";
  }
  else {
    $sql_where = "username=\'$username\'";
  }

  my $sth_oplog = $reseller_reports::dbh_data->prepare(qq{
         select username, authstatus, authtime, amount
         from operation_log
         where trans_date between '$startdate' and '$enddate'
         and $sql_where
  });

  $sth_oplog->execute();

  my %oplog_data = ();
  my %tran_count = ();

  while (my $data = $sth_oplog->fetchrow_hashref) {
    # username auth 
    my ($currency, $amount) = split(/\s/, $data->{'AMOUNT'});
    $oplog_data{$data->{'USERNAME'} . "|auth|" . $data->{'AUTHSTATUS'} . "|$currency"} += $amount;
    $tran_count{$data->{'USERNAME'} . "|auth|" . $data->{'AUTHSTATUS'} . "|$currency"} += 1;
  }
  $sth_oplog->finish;

  if ($format eq "text") {
    # username type status amount
    print "\"username\",\"operation\",\"FinalStatus\",\"currency\",\"amount\",\"count\"\n"; 
  }
  else {
    &head();
    print "<tr>\n";
    print "  <th>Username</th><th>Operation</th><th>FinalStatus</th><th>Currency</th><th>Amount</th><th>Count</th>\n";
    print "</tr>\n";
  }

  foreach my $data_key (sort keys %oplog_data) {
    my ($user, $operation, $status, $currency) = split(/\|/, $data_key);
    my $amount = sprintf("%.2f",$oplog_data{$data_key});
    if ($format eq "text") {
      print "\"$user\",\"$operation\",\"$status\",\"$currency\",\"$amount\",\"$tran_count{$data_key}\"\n"; 
    }
    else {
      print "<tr>\n";
      print "  <td>$user</td><td>$operation</td><td>$status</td><td>$currency</td><td>$amount</td><td>$tran_count{$data_key}\n";
      print "</tr>\n";
    }
  }
  if ($format ne "text") {
    &tail();
  }
}

sub user_list_volpay {
  my @result = ();

  my $sth_volpay = $reseller_reports::dbh_misc->prepare(qq{
         select username
         from customers
         where processor='volpay'
  });
  $sth_volpay->execute();
 
  while (my $username = $sth_volpay->fetchrow) {
    $result[++$#result] = $username;
  }

  $sth_volpay->finish;

  return @result;
}
