#!/usr/local/bin/perl

require 5.001;
$| = 1;

package checklog;

use CGI;
use SHA;
use miscutils;
use htmlutils;
use scrubdata;
use strict;

sub new {
  my $type = shift;

  # get our data together
  $checklog::query = new CGI;

  # scrubber for cleaning data
  $checklog::scrubber = new scrubdata;

  $checklog::user = $checklog::scrubber->untaintword($ENV{'REMOTE_USER'});
  # taint not so important as removing anything that might be bad
  $checklog::function = $checklog::scrubber->untaintword($checklog::query->param('function'));
  $checklog::address = $checklog::scrubber->untaintword($checklog::query->param('address'));

  # path to main cgi script
  $checklog::path_cgi = "/private/blocked/index.cgi";

  ($checklog::id, $checklog::date, $checklog::time) = &miscutils::gendatetime();
  $checklog::adayago = (&miscutils::gendatetime(-24*60*60))[2];

  return [], $type;
}

# returns any function passed by calling form
sub function {
  return $checklog::function;
}

# connects to the db call before making a query
sub connect {
  if ($checklog::dbh eq "") {
    $checklog::dbh = &miscutils::dbhconnect("logdb");
  }
}

# disconnect from the db call before exiting script
sub disconnect {
  # check for valid connection first
  if ($checklog::dbh ne "") {
    $checklog::dbh->disconnect;
  }
}

# displays main menu for the cgi
sub main {
  &head();

  &display_blocked_list();

  &tail();
}

# html head for all pages
sub head {
  print "<HTML>\n";
  print "  <HEAD>\n";
  print "    <TITLE>Blocked</TITLE>\n";
  print "  </HEAD>\n";
  print "  <BODY>\n";
  print "    <table border=1>\n";
  
  # if we encountered an error display it to the user
  if (%checklog::error ne "") {
    foreach my $error (sort keys %checklog::error) { 
      print "      <tr>\n";
      print "        <td> $error </td> <td> $checklog::error{$error} </td>\n";
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

sub display_blocked_list {

  &connect();

  print "<form action=\"\" method=\"POST\">\n";
  print "  <input type=hidden name=\"function\" value=\"delete\">\n";
  print "<tr><td>Delete</td><td>address</td><td>count</td><td>errtype</td><td>first_time</td><td>last_time</td><td>username</td></tr>\n";

  my $sth_list = $checklog::dbh->prepare(qq{
         select *
         from ip_log
         where first_time >= ?
         and count >= 6
         order by username
  }) or $checklog::error{"display_blocked_list prepare"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
  $sth_list->execute($checklog::adayago) or $checklog::error{"display_blocked_list execute"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";

  while (my $data = $sth_list->fetchrow_hashref) {
    print "<tr>\n";
    print "<td> <input type=\"radio\" name=\"address\" value=\"$data->{'address'}\"> </td>\n";
    foreach my $column (sort keys %{$data}) {
      print "  <td>\n";
      print "    $data->{$column}\n";
      print "  </td>\n";
    }
    print "</tr>\n";
  }
  print "<tr><td><input type=submit></td></tr>\n";
  print "</form>\n";

  $sth_list->finish;
}

sub remove_block {

  &connect();

  my $sth_del_block = $checklog::dbh->prepare(qq{
         delete from ip_log
         where address=?
  }) or $checklog::error{"remove_block prepare"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
  $sth_del_block->execute($checklog::address) or $checklog::error{"remove_block execute"} = __LINE__ . "  " . __FILE__ ."  $DBI::errstr";
  $sth_del_block->finish;

}
