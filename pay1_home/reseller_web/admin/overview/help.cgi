#!/bin/env perl

# Last Updated: 11/10/10

require 5.001;
$|=1;

use lib '/home/p/pay1/perl_lib/';
use CGI qw/standard escapeHTML/;
use sysutils;
use strict;

my $path_base = "/home/p/pay1/web/online_help/";

my %query;
my $query = new CGI;

my @array = $query->param;
foreach my $var (@array) {
  $query{"$var"} = &CGI::escapeHTML($query->param($var));
}

print "Content-Type: text/html\n\n";

my $subject = $query{'subject'};
$subject =~ s/[^a-zA-Z0-9\_\-]//g;

my $help_file = $query{'subject'} . ".txt";
$help_file =~ s/[^0-9a-zA-Z\_\-\.]//g;

my $anchor = $query{'anchor'};
$anchor =~ s/[^0-9a-zA-Z\_\-]//g;

my $fp = $path_base . $help_file;

#print "HF:$help_file, FULLPATH:$fp<br>\n";

if (-e "$fp") {
  &help_page($path_base, $help_file, $anchor);
}
else {
  my $message = "Sorry No Help is Available for that Subject";
  &response_page($message);
}

exit;

sub response_page {
  my ($message) = @_;
  print "<HTML>\n";
  print "<HEAD>\n";
  print "<TITLE>Online Help - Help Page Not Found</TITLE> \n";
  print "</HEAD>\n";
  print "<script Language=\"Javascript\">\n";
  print "<\!-- Start Script\n";
  print "function closeresults\(\) \{\n";
  print "  resultsWindow = window.close(\"results\")\;\n";
  print "\}\n";
  print "// end script-->\n";
  print "</script>\n";
  print "<BODY BGCOLOR=#FFFFFF>\n";
  print "<div align=center><p>\n";
  print "<font size=+1>$message</font><p>\n";
  print "<p>\n";
  print "<form><input type=button value=\"Close\" onClick=\"closeresults();\"></form>\n";
  print "</div>\n";
  print "</BODY>\n";
  print "</HTML>\n";
}

sub help_page {
  my ($path_base, $help_file) = @_;
  print "<HTML>\n";
  print "<HEAD>\n";
  print "<TITLE>Online Help</TITLE> \n";
  print "</HEAD>\n";
  print "<script Language=\"Javascript\">\n";
  print "<\!-- Start Script\n";
  print "function closeresults\(\) \{\n";
  print "  resultsWindow = window.close(\"results\")\;\n";
  print "\}\n";
  print "// end script-->\n";
  print "</script>\n";

  $help_file =~ s/[^0-9a-zA-Z_\-\.]//g; # added by carol
  #my $file = $path_base . $help_file;
  my $filteredname = &sysutils::filefilter("$path_base","$help_file") or die "a painful death";
  &sysutils::filelog("read","$filteredname");
  open (HTML,"$filteredname");
  while(<HTML>) {
    print $_;
  }
  close(HTML);
  exit;
}

