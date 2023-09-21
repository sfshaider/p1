#!/usr/local/bin/perl

require 5.001;
$| = 1;

package worklog;

# This package is used for inserting and reviewing items into
# the work log.

use CGI;
use SHA;
use miscutils;
use htmlutils;
use scrubdata;
use strict;

sub new {
  my $type = shift;

  # get our data together
  $worklog::query = new CGI;

  # scrubber for cleaning data
  $worklog::scrubber = new scrubdata;

  # list of admin users
  %worklog::admin_users = ("drew","1","dave","1","carol","1","isomaki","1");

  $worklog::user = $worklog::scrubber->untaintword($ENV{'REMOTE_USER'});
  # taint not so important as removing anything that might be bad
  $worklog::function = $worklog::scrubber->untaintword($worklog::query->param('function'));

  # path to main cgi script
  $worklog::path_cgi = "/private/work_log/index.cgi";

  ($worklog::id, $worklog::date, $worklog::time) = &miscutils::gendatetime();

  return [], $type;
}

# returns any function passed by calling form
sub function {
  return $worklog::function;
}

# connects to the db call before making a query
sub connect {
  if ($worklog::dbh eq "") {
    $worklog::dbh = &miscutils::dbhconnect("logdb");
  }
}

# disconnect from the db call before exiting script
sub disconnect {
  # check for valid connection first
  if ($worklog::dbh ne "") {
    $worklog::dbh->disconnect;
  }
}

# displays main menu for the cgi
sub main {
  &head();
  # allowed for all users
  &insert_menu();

  if ($worklog::admin_users{$worklog::user} eq "1") { 
    # form to check current changes displayed only for admin users
    &review_list();    
    
    # form to generate report display for admin users only
    &report_menu();
  } 

  &tail();
}

# output report generation menu
sub report_menu {
  print "<tr>\n";
  print "  <form action=\"$worklog::path_cgi\" method=\"post\">\n";
  print "    <input type=\"hidden\" name=\"function\" value=\"report\">\n";

  print "  <td colspan=\"2\"> Start Date: \n";
  print &htmlutils::gen_dateselect("start",(substr($worklog::date,0,4)-1),substr($worklog::date,0,4),$worklog::date);
  print "  </td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td colspan=\"2\"> End Date: \n";
  print &htmlutils::gen_dateselect("end",(substr($worklog::date,0,4)-1),substr($worklog::date,0,4),$worklog::date);
  print "  </td>\n";
  print "<tr>\n";

  print "<tr>\n";
  print "  <td colspan=\"2\">\n";
  print "    <input type=\"submit\" value=\"Report\">\n";
  print "  </td>\n";
  print "  </form>\n";
  print "</tr>\n";
}

# display a requested report
sub generate_report {
  # if not an admin user dump to main menu.
  if ($worklog::admin_users{$worklog::user} ne "1") {
    &main();
    &disconnect();
    exit;
  }

  # setup start and end date
  my $start_date = $worklog::query->param('start_year') . $worklog::query->param('start_month') . $worklog::query->param('start_day');
  $start_date = $worklog::scrubber->untaintdate($start_date);

  my $end_date = $worklog::query->param('end_year') . $worklog::query->param('end_month') . $worklog::query->param('end_day');
  $end_date = $worklog::scrubber->untaintdate($end_date);

  # if start or end date are bad don't run the report
  if (($start_date ne "") && ($end_date ne "") && ($start_date <= $end_date)) {
    &head();

    # make sure db is connected
    &connect();

    # prepare and execute query
    my $sth_report = $worklog::dbh->prepare(qq{
           select editor, reviewer, merchant, script, hostname, insert_date, review_date, description, msghash
           from worklog
           where insert_date between ? and ?
    }) or $worklog::error{"generate_report prepare"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
    $sth_report->execute("$start_date", "$end_date") or $worklog::error{"generate_report execute"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";

    my $field_names = $sth_report->{NAME_lc};

    # print out html table header here
    print "<tr>\n";
    foreach my $field (@{$field_names}) {
      print "<th>$field</th>";
    }
    print "\n</tr>\n";

    # fetch and output data
    while (my $data = $sth_report->fetchrow_hashref()) {
      print "<tr>\n";
      foreach my $field (@{$field_names}) {
        print "<td>$data->{$field}</td>";
      }
      print "\n</tr>\n";
    }

    $sth_report->finish;
    &tail();
  }
  else {
    # no report available
    &head();
    print "<tr>\n";
    print "  <td>\n";
    print "    No report available for current selection.\n";
    print "  </td>\n";
    print "</tr>\n";
    &tail();
  }
}

# update a reviewed item
sub review_item {
  # if not an admin user dump to main menu.
  if ($worklog::admin_users{$worklog::user} ne "1") {
    &main();
    &disconnect();
    exit;
  }

  my $review = $worklog::scrubber->untaintword($worklog::query->param('review'));
  my $workid = $worklog::scrubber->untaintinteger($worklog::query->param('workid'));

  if ($review eq "yes") {
    &connect();

    my $sth_review = $worklog::dbh->prepare(qq{
           update worklog
           set reviewer=?, review_date=?
           where workid=?
    }) or $worklog::error{"review_item prepare"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
# 666 add back after testing
# and editor<>?
#    my $result = $sth_review->execute("$worklog::user", "$worklog::date", "$workid", "$worklog::user") or $worklog::error{"review_item execute"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
    my $result = $sth_review->execute("$worklog::user", "$worklog::date", "$workid") or $worklog::error{"review_item execute"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
    $sth_review->finish;
  }

  # always dump to main when we are done update or not
  &main();
}

# display an item to be reviewed
sub review_menu {
  # if not an admin user dump to main menu.
  if ($worklog::admin_users{$worklog::user} ne "1") {
    &main();
    &disconnect();
    exit;
  }

  my $workid = $worklog::scrubber->untaintword($worklog::query->param('workid'));

  &connect();
  my $sth_item = $worklog::dbh->prepare(qq{
         select editor, merchant, script, hostname, insert_date, description
         from worklog
         where workid=?
  }) or $worklog::error{"review_menu prepare"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr"; 
  my $rows = $sth_item->execute("$workid") or $worklog::error{"review_menu execute"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";

  if ($rows >= 1) {
    &head();
    while (my $data = $sth_item->fetchrow_hashref()) {
      print "<tr>\n";
      print "  <td>\n";
      print "    <table border=1>\n";
      print "<tr>\n";
      print "  <td>User: " . $data->{'editor'} . "</td>\n";
      print "</tr>\n";
      
      print "<tr>\n";
      print "  <td>Merchant:" . $data->{'merchant'} . "</td>\n";
      print "</tr>\n";

      print "<tr>\n";
      print "  <td>Host: " . $data->{'hostname'} . "</td>\n";
      print "</tr>\n";

      print "<tr>\n";
      print "  <td>Script: " . $data->{'script'} . "</td>\n";
      print "</tr>\n";

      print "<tr>\n";
      print "  <td>Date: " . $data->{'insert_date'} . "</td>\n";
      print "</tr>\n";

      print "<tr>\n";
      print "  <td> Description: " . $data->{'description'} . "</td>\n";
      print "</tr>\n";

      print "<tr>\n";
      print "  <form action=\"$worklog::path_cgi\" method=\"post\">\n";
      print "    <input type=\"hidden\" name=\"function\" value=\"reviewitem\">\n";
      print "    <input type=\"hidden\" name=\"workid\" value=\"$workid\">\n";
      print "  <td>\n";
      print "    <input type=checkbox name=\"review\" value=\"yes\">\n";
      print "    <input type=submit value=\"Review\">\n";
      print "  </td>\n";
      print "  </form>\n";
      print "</tr>\n";
      print "    </table>\n";
      print "  </td>\n";
      print "</tr>\n";
    }

    &tail();
  }
  else {
    &main();
  }
  $sth_item->finish();
}

# display list of items needing review on main page
sub review_list {
  &connect();

  print "<tr>\n";
  print "  <form action=\"$worklog::path_cgi\" method=\"post\">\n";
  print "    <input type=\"hidden\" name=\"function\" value=\"reviewmenu\">\n";
  print "  <td> Review item: </td>\n";
  print "  <td> <select name=\"workid\">\n";

  my $sth_review = $worklog::dbh->prepare(qq{
         select editor, insert_date, script, workid
         from worklog
         where reviewer is null
         order by insert_date
  }) or $worklog::error{"review_list prepare"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
  $sth_review->execute() or $worklog::error{"review_list execute"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
  
  while (my $data = $sth_review->fetchrow_hashref()) {
    print "    <option value=\"" . $data->{'workid'} . "\">" . $data->{'insert_date'} . " " . $data->{'editor'} . " " . $data->{'script'} . " </option>\n";
  }
  $sth_review->finish;

  print "  </select> </td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>\n";
  print "        <input type=\"submit\" value=\"Review\">\n";
  print "      </form>\n";
  print "    </td>\n";
  print "  </tr>\n";
}

# html head for all pages
sub head {
  print "<HTML>\n";
  print "  <HEAD>\n";
  print "    <TITLE>Work Log</TITLE>\n";
  print "  </HEAD>\n";
  print "  <BODY>\n";
  print "    <table>\n";

  # if we encountered an error display it to the user
  if (%worklog::error ne "") {
    foreach my $error (sort keys %worklog::error) { 
      print "      <tr>\n";
      print "        <td> $error </td> <td> $worklog::error{$error} </td>\n";
      print "      </tr>\n";
    }
  }
}
 # html tail for all pages
sub tail {
  print "    </table>\n";
  print "  </BODY>\n";
  print "</HTML>\n";
}

# main menu for inserting new items
sub insert_menu {
  # form to insert script change
  print "<tr>\n";
  print "  <td>\n";
  print "    <form action=\"$worklog::path_cgi\" method=\"post\">\n";
  print "      <input type=\"hidden\" name=\"function\" value=\"insertitem\">\n";
  # if provided check if in customers table
  print "      Merchant :\n";
  print "  </td>\n";
  print "  <td>\n";
  print "      <input type=\"text\" name=\"merchant\" value=\"\">\n";
  print "   Only required for merchant scripts. </td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td>\n";
  # 
  print "    Hostname :*\n";
  print "  </td>\n";
  print "  <td>\n";
  print "      <input type=\"text\" name=\"host\" value=\"snowbird\">\n";
  print "  </td>\n";
  print "</tr>\n";

  print "<tr>\n";
  print "  <td>\n";
  # test script to make sure it exists ??
  print "    Script/Module :*\n";
  print "  </td>\n";
  print "  <td>\n";
  print "      <input type=\"text\" name=\"script\" value=\"/home/p/pay1/web/\" size=\"80\">\n";
  print "  </td>\n";
  print "</tr>\n";
  print "<tr>\n";
  print "  <td>\n";
  print "    Description :*\n";
  print "  </td>\n";
  print "  <td>\n";
  print "     <textarea name=\"description\" rows=\"20\" cols=\"80\"></textarea>\n";
  print "  </td>\n";
  print "</tr>\n";
  print "<tr>\n";
  print "  <td>\n";
  print "      <input type=\"submit\">\n";
  print "    </form>\n";
  print "  </td>\n";
  print "</tr>\n";
}

# insert an item to be reviewed
sub insertitem {
  my $merchant = $worklog::scrubber->untaintword($worklog::query->param('merchant'));
  my $script = $worklog::scrubber->untaintfile($worklog::query->param('script'));
  my $description = $worklog::scrubber->untainttext($worklog::query->param('description'));
  my $hostname = $worklog::scrubber->untaintword($worklog::query->param('host'));

  if (($script eq "") || ($description eq "") || ($hostname eq "")) {
    $worklog::error{"insertitem input check"} = __LINE__ . "  " . __FILE__ ."  A required field was empty. SCRIPT: $script DESC: $description host: $hostname";
    &main();
    &disconnect();
    exit;
  }

  my $work_id = $worklog::id;
  my $insert_date = $worklog::date;

  my $message = $merchant . $script . $hostname . $description . $insert_date;
  my $context = new SHA;
  $context->reset();
  $context->add($message);
  my $msghash = $context->hexdigest();

  &connect();

  my $sql_insert = $worklog::dbh->prepare(qq{
         insert into worklog
         (editor, reviewer, merchant, script, hostname, msghash, insert_date, workid, review_date, description)
         values (?, ?, ?, ?, ? ,? ,? ,? ,? ,?)
  }) or $worklog::error{"insertitem prepare"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
  $sql_insert->execute("$worklog::user", "", "$merchant", "$script", "$hostname", "$msghash", "$insert_date", "$work_id", "", "$description") or $worklog::error{"insertitem execute"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
  $sql_insert->finish;
}

#  database structure
#    worklog
#      editor
#      reviewer
#      merchant
#      script
#      hostname
#      msghash
#      insert_date
#      workid
#      review_date
#      description
