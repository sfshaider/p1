#!/usr/bin/perl

require 5.001;
$| = 1;

package htmlutils;

use miscutils;
use strict;

sub gen_dateselect {
  my ($name,$start_year,$end_year,$selected_date) = @_;

  if ($start_year eq "") {
    $start_year = "2001";
  }
  $start_year = substr($start_year,0,4);

  if ($end_year eq "") {
    $end_year = (&miscutils::gendatetime(10*365*24*60*60))[1];
  }
  $end_year = substr($end_year,0,4);

  if ($selected_date eq "") {
    $selected_date = (&miscutils::gendatetime())[1];
  }
  my $selected_year = substr($selected_date,0,4);
  my $selected_month = substr($selected_date,4,2);
  $selected_month =~ s/^0//;
  my $selected_day = substr($selected_date,6,2);
  $selected_day =~ s/^0//;

  my $result = "";
  my $selected = "";

  # gen month list
  $result .= "Month: <select name=\"" . $name . "_month\">\n";
  for (my $month=1;$month<=12;$month++) {
    if ($selected_month == $month) {
      $selected = "selected";
    }
    else {      $selected = "";    }
    $result .= sprintf("<option value=\"%02d\" \%s>\%d</option>\n",$month,$selected,$month);
  }
  $result .= "</select>\n";

  # gen day list
  $result .= "Day: <select name=\"" . $name . "_day\">\n";
  for (my $day=1;$day<=31;$day++) {
    if ($selected_day == $day) {
      $selected = "selected";
    }
    else {      $selected = "";    }
    $result .= sprintf("<option value=\"%02d\" \%s>\%d</option>\n",$day,$selected,$day);
  }

  $result .= "</select>\n";

  # gen year list
  $result .= "Year: <select name=\"" . $name . "_year\">\n";
  for (my $year=$start_year;$year<=$end_year;$year++) {
    if ($selected_year == $year) {
      $selected = "selected";
    }
    else {
      $selected = "";
    }
    $result .= sprintf("<option value=\"\%d\" \%s>\%d</option>\n",$year,$selected,$year);
  }
  $result .= "</select>\n";

  return $result;
}

