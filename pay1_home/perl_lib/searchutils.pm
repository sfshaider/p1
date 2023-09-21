#!/usr/bin/perl

require 5.001;
$|=1;

package searchutils;

use miscutils;
use htmlutils;
use scrubdata;
use CGI;
use SHA;

sub new {
  my $type = shift;

  $searchutils::query = new CGI;

  $searchutils::path_cgi = "/private/search.cgi";

  # scrubber for cleaning data
  $searchutils::scrubber = new scrubdata;

  # taint not so important as removing anything that might be bad
  $searchutils::function = $searchutils::scrubber->untaintword($searchutils::query->param('function'));

  $searchutils::format = $searchutils::scrubber->untaintword($searchutils::query->param('format'));

  return [], $type;
}

sub format {
  return $searchutils::format;
}

sub function {
  return $searchutils::function;
}

sub head {
  print "<html>\n";
  print "  <head>\n";
  print "    <title>Trans Search</title>\n";
  print "    <META HTTP-EQUIV=\"CACHE-CONTROL\" CONTENT=\"NO-CACHE\">\n";
  print "    <META HTTP-EQUIV=\"PRAGMA\" CONTENT=\"NO-CACHE\">\n";
  print "  </head>\n";

  print "<body bgcolor=\"#ffffff\">\n";
}

sub main {
  &head();
  &trans_search_form();
  &tail();
}

sub trans_search_form {
  print "  <form method=post action=\"$searchutils::path_cgi\" target=\"searchwin\">\n";
  print "    <input type=\"hidden\" name=\"function\" value=\"transaction_search\">\n";
  print "    Username: <input type=\"text\" name=\"username\" maxlength=\"16\" size=\"16\">\n";
  print "    <br>\n";
  print "  Start Date: " . &htmlutils::gen_dateselect("start");
  print "<br>\n";
  print "  End Date: " . &htmlutils::gen_dateselect("end");
  print "<br>\n";
  print "Search by: ";
  print "  <select name=\"search_by\">\n";
  print "    <option value=\"orderid\">transaction orderID</option>\n";
  print "    <option value=\"card_name\"> card holder name</option>\n";
  print "    <option value=\"card_addr\"> card holder street address</option>\n";
  print "    <option value=\"card_number\"> partial card number 4111**11</option>\n";
  print "    <option value=\"amount\"> transaction amount</option>\n";
  print "    <option value=\"acct_code\"> acct_code</option>\n";
  print "    <option value=\"shacardnumber\"> SHA card number</option>\n";
  print "    <option value=\"refnumber\"> ref number</option>\n";
  print "  </select>\n";
  print "<br>\n";
  print "Search Value: <input type=\"text\" maxlength=\"64\" size=\"32\">\n";
  print "<br>\n";
  print "    <input type=\"submit\">\n";
  print "  </form>\n";
}

sub tail {
  print "  </body>\n";
  print "</html>\n";
}
