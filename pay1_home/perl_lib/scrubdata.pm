#!/usr/local/bin/perl

require 5.001;
$| = 1;

package scrubdata;


# strongly typed data
# length checked max and min
# range checked if numeric

# pass in list of vars to check
# name, type, max length, min length, valid values
# flags
#  alphanumeric
#  escape
# type = string, number, day, month, year, date, amount,
#  string can contain anything set level of sanitization on a field by field basis
#    1 = contains anything
#    5 = escape anything not a-z A-Z 0-9 - _ or space
#    9 = remove anything not a-z A-Z 0-9 - _ or space
# max length any number -1 for no max
# min length any number -1 for no min
# valid values array of valid values for field empty array for no checking

sub new {
  my $type = shift;

  %scrubdata::bad_html = (
                         "<","&lt;",
                         ">","&gt;",
                         "\"","&quot;",
                         "\'","&#39;",
                         "%","&#37;",
                         "\(","&#40;",
                         "\)","&#41;",
                         );
  

  return [], $type;
}

# removes everything except alpha numerics and underscore and untaints value
sub untaintword {
  shift;
  my ($tainted) = @_;

  $tainted =~ /([-\@\w.]+)/;

  return $1;
}

sub untaintfile {
  shift;
  # this just checks if the filename is semi legit be careful still
  my ($tainted) = @_;

  $tainted =~ m!^(.*)/(.*)$!;

  # path and filename are untainted
  my $path = $1;
  my $filename = $2;
 
  # filename and path must at least contain a word 
  if (($filename !~ /\w/) || ($path !~ /\w/)) {
    return "";
  }

  # remove any dots in the path
  $path =~ s/[.]+//g;

  # combine the filename and path again
  my $result = $path . "/" . $filename;

  return $result;
}

# makes safe for display in browser
# makes safe for sql insert
sub untainttext {
  shift;
  my ($tainted) = @_;

  # need to escape ampersand first
  $tainted =~ s/[\&]/\&amp\;/g;

  # remove all bad html characters from the text.
  foreach my $pattern (keys %scrubdata::bad_html) {
    $tainted =~ s/[$pattern]/$scrubdata::bad_html{$pattern}/g;
  }

  # at this point the text should be safe so we untaint it.
  #$tainted =~ /(.|\n)*/;
  
  my $result = $tainted;

  return $result;
}

sub untaintdate {
  shift;
  my ($tainted) = @_;

  $tainted =~ /^([0-9]+)$/;

  my $untainted = $1;

  my $result = "";

  my $year = substr($untainted, 0, 4);
  my $month = substr($untainted, 4, 2);
  my $day = substr($untainted, 6, 2);

  # check for valid lengths 
  if ((length($year) == 4) && (length($month) == 2) && (length($day) == 2)) {
    $result = $year;
   
    # strip leading 0 
    $month =~ s/^[0]//g;
    $day =~ s/^[0]//g;

    # check for valid month and day ranges
    if (($month >= 1) && ($month <= 12)
        && ($day >= 1) && ($day <= 31)) {
      $result .= sprintf("%02d", $month) . sprintf("%02d",$day);
    }
    else {
      return "";
    }
  } 
  else {
    return "";
  }
  return $result;
}

# untaints an integer will only match the first integer in a string
# everything else is ditched this may not be what you want
sub untaintinteger {
  shift;
  my ($tainted) = @_;

  # find first number in the string
  $tainted =~ /^([0-9]+)$/;

  # return it
  return $1;
}

# use to untaint and check form values must be words
sub untaintwordlist {
  shift;
  my ($tainted,@goodvalues) = @_;

  $tainted =~ /^([-\@\w.]+)$/;

  my $result = $1;

  foreach my $value (@goodvalues) {
    if ($result eq $value) {
      return $result;
    }
  }  

  return "";
}

sub untaintemail {

}
