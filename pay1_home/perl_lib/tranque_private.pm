

package tranque_private;

require 5.001;
$| = 1;
 
use miscutils;
use CGI;
use Math::BigInt;
use strict;

sub new {
  my $type = shift;
  ($tranque_private::query) = @_;

  # This DBH handle should be used throughout the script disconnect on exit.
  $tranque_private::dbh = &miscutils::dbhconnect("tranque");

  $tranque_private::script_location = "https://pay1.plugnpay.com/private/tranque/index.cgi";

  return [], $type;
}

# main menu displayed
sub main {
  &head;

  &status();
  print "<form action=\"$tranque_private::script_location\" method=\"post\">\n";

  print "<div id=\"cBoxes\">\n";
  print "<TABLE border=1 cellspacing=0 cellpadding=2>\n";

  my $sth_main = $tranque_private::dbh->prepare(qq{
               select processid, status, trxs,starttime, endtime, lasttrantime, lastlooptime, command
               from tranproc
  }) or die "Can't prepare: $DBI::errstr\n";
  $sth_main->execute() or print "Can't execute:: $DBI::errstr\n";
  my $data = $sth_main->fetchall_arrayref({});
  $sth_main->finish;

  if (@{$data}) {
    # print header
    print "<tr>";
    print "  <th>";
    print "Processid";
    print "  </th>";
    print "  <th>";
    print "Status";
    print "  </th>";
    print "  <th>";
    print "Trxs";
    print "  </th>";
    print "  <th>";
    print "Start Time";
    print "  </th>";
    print "  <th>";
    print "End Time";
    print "  </th>";
    print "  <th>";
    print "Lasttran Time";
    print "  </th>";
    print "  <th>";
    print "Lastloop Time";
    print "  </th>";
    print "  <th>";
    print "Command";
    print "  </th>";
    print "  <th>";
    print "    <select name=\"mode\">\n";
    print "      <option value=\"\"> Mode </option>\n";
    print "      <option value=\"stop\"> Stop </option>\n";
    print "      <option value=\"delete\"> Delete </option>\n";
    print "      <option value=\"reload\"> Reload All </option>\n";
    print "    </select>\n";
    print "    <input type=\"submit\" value=\"Do\">\n";
    print "    <br>\n";
    print "    <a href=\"#\" onClick=\" return checkAll();\">All</a>\n";
    print "    <a href=\"#\" onClick=\" return checkNone();\">None</a>\n";
    print "  </th>\n";
    print "</tr>\n";    

    # print data
    foreach my $entry (@{$data}) {
      print "<tr>";
      print "<td>";
      print "$entry->{'processid'}";
      print "</td>";
      print "<td>";
      print "$entry->{'status'}";
      print "</td>";
      print "<td>";
      print "$entry->{'trxs'}";
      print "</td>";
      print "<td>";
      print "$entry->{'starttime'}";
      print "</td>";
      print "<td>";
      print "$entry->{'endtime'}";
      print "</td>";
      print "<td>";
      print "$entry->{'lasttrantime'}";
      print "</td>";
      print "<td>";
      print "$entry->{'lastlooptime'}";
      print "</td>";
      print "<td>";
      print "$entry->{'command'}";
      print "<td>\n";
      print "<input type=\"checkbox\" name=\"processid\" value=\"$entry->{'processid'}\"> Valid: ";
      if (($entry->{'command'} eq "") && ($entry->{'status'} eq "running"))  {
        print "Stop "; 
      }
      if (($entry->{'status'} eq "stopped") || ($entry->{'status'} eq "failed") || ($entry->{'status'} eq "stop")) {
        print "Delete ";
      } elsif ($entry->{'status'} eq "monitoring") {
        print "reload all ";
      }
      print "</td>";
      print "</tr>\n";
    }
  } else {
    print "<TR><TD>No processes in table</TD></TR>\n";
  }
  
  print "</TABLE>\n";
  print "</div>\n";
  print "</form>\n";
  print "<P>\n";

  &tail();
}

# the head stupid
sub head {
  print "<HTML>\n";
  print "<HEAD><TITLE>Tranque Admin</TITLE>\n";


  # Javascript for check all and none
  print "<SCRIPT LANGUAGE=\"Javascript\" TYPE=\"text/javascript\">\n";
  print "<!-- //\n";
  print "  function checkAll() {\n";
  print "    var container = document.getElementById(\'cBoxes\');\n";
  print "    var boxes = container.getElementsByTagName(\'input\');\n";
  print "    for (var i = 0; i < boxes.length; i++) {\n";
  print "      myType = boxes[i].getAttribute(\"type\");\n";
  print "      if ( myType == \"checkbox\") {\n";
  print "        boxes[i].checked=1;\n";
  print "      }\n";
  print "    }\n";
  print "  }\n";
  print "  function checkNone() {\n";
  print "    var container = document.getElementById(\'cBoxes\');\n";
  print "    var boxes = container.getElementsByTagName(\'input\');\n";
  print "    for (var i = 0; i < boxes.length; i++) {\n";
  print "      myType = boxes[i].getAttribute(\"type\");\n";
  print "      if ( myType == \"checkbox\") {\n";
  print "        boxes[i].checked=0;\n";
  print "      }\n";
  print "    }\n";
  print "  }\n";
  print "//-->\n";
  print "</SCRIPT>\n";

  print "</Head>\n";
  print "<link href=\"/css/style_private.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<BODY>\n";
}

# the tail stupid
sub tail {
  print "</BODY>\n";
  print "</HTML>\n";
}

sub status {
  print "<table border=1 cellspacing=0 cellpadding=2>\n";

  my $sth_stat = $tranque_private::dbh->prepare(qq{
               select count(orderid),status
               from tranlist
               group by status
  }) or die "cant prepare $DBI::errstr";
  $sth_stat->execute() or die "cant execute $DBI::errstr\n";

  print "<tr><th>Status</th><th>Count</th></tr>\n";
  while (my $data = $sth_stat->fetchrow_arrayref) {
    print "<tr><td>" . $data->[1] . "</td><td>" . $data->[0] . "</td></tr>\n";
  }
  $sth_stat->finish;

  # list current number of running process.pl
  my $pid_result = `/usr/bin/ps -ef |/bin/grep perl |/bin/grep \"tranproc\" |/bin/grep -v grep`;
  my @pid_lines = split(/\n/,$pid_result);
  print "<tr><td>";
  print " <b>Currently running</b></td><td><b>" . ($#pid_lines + 1) . "</b>";
  print " </td></tr>\n";
  print "<tr><td>\n";
  print "<form action=\"$tranque_private::script_location\" method=\"post\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"deltranlist\">\n";
  print "<input type=\"submit\" value=\"Del Tranlist\">\n";
  print "</form>\n";
  print " </td>\n";
  print "<td>\n";
  print "<form action=\"$tranque_private::script_location\" method=\"get\">\n";
  print "<input type=\"submit\" value=\"Refresh Page\">\n";
  print "</form>\n";
  print " </td>\n";
  print "</tr>\n";
  print "</table>\n";
}

sub stoptranproc {
  my ($self, @processid) = @_;

  for (my $pos=0; $pos<=$#processid; $pos++) {
    $processid[$pos] =~ s/[^0-9]//g;

    if ($processid[$pos] ne "") {
      my $sth = $tranque_private::dbh->prepare(qq{
              update tranproc
              set command=?
              where processid=?
              and status in (?,?)
      }) or die "cant prepare $DBI::errstr";
      $sth->execute("stop","$processid[$pos]","running","monitoring") or die "cant execute $DBI::errstr\n";
      $sth->finish;
    }
  }
}

sub reloadall {
  my ($self, @processid) = @_;

  for (my $pos=0; $pos<=$#processid; $pos++) { 
  
    $processid[$pos] =~ s/[^0-9]//g;

    if ($processid[$pos] ne "") {
      my $sth = $tranque_private::dbh->prepare(qq{
              update tranproc
              set command=?
              where processid=?
              and status=?
      }) or die "cant prepare $DBI::errstr";
      $sth->execute("reload","$processid[$pos]","monitoring") or die "cant execute $DBI::errstr\n";
      $sth->finish;
    }
  }
}

sub deletetranproc {
  my ($self, @processid) = @_;
  
  for (my $pos=0; $pos<=$#processid; $pos++) {
    $processid[$pos] =~ s/[^0-9]//g;

    if ($processid[$pos] ne "") {
      my $sth = $tranque_private::dbh->prepare(qq{
              delete from tranproc
              where processid=?
              and status in (?,?)
      }) or die "cant prepare $DBI::errstr";
      $sth->execute("$processid[$pos]","stopped","failed") or die "cant execute $DBI::errstr\n";
      $sth->finish;
    }
  }
}

sub deletetranlist {
    my $sth = $tranque_private::dbh->prepare(qq{
            delete from tranlist
    }) or die "cant prepare $DBI::errstr";
    $sth->execute() or die "cant execute $DBI::errstr\n";
    $sth->finish;
}

1;
