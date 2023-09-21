#!/bin/env perl

# Purpose: Check FAQ log file and generate usage stats
# Last Updated: 02/12/03

# To Be Completed:
# - average keywords used

# Initialize File Locations:
$faq_log  = "/home/p/pay1/web/reseller/reseller_board/reseller_board.log";      # path to FAQ log file
$faq_swap = "/home/p/pay1/web/reseller/reseller_board/reseller_board_stat.swp"; # path to FAQ log file
$faq_db   = "/home/p/pay1/webtxt/reseller/reseller_board/reseller_board.db";       # path to FAQ database file
$faq_most_active = "/home/p/pay1/web/reseller/reseller_board/reseller_board_most_active.htm"; # path to FAQ's most active content page

# Email Report Options:
$email      = "rridings\@plugnpay.com";  # TO Email Address to send FAQ Stat reports.
$cc_email   = "turajb\@plugnpay.com";    # CC Email Address to send FAQ Stat reports.  [default value is "" ==> NULL Value]
$bcc_email  = "";                        # BCC Email Address to send FAQ Stat reports. [default value is "" ==> NULL Value]
$subject    = "";                        # Custom email Subject header [default value is "" ==> NULL Value]
$from_email = "reseller_faq_stats\@plugnpay.com"; # FROM/REPLY Email Address

############################
# Program Begins Here

# Initialize necessary variables here
$report = ""; # clear & initialize report variable

# grab time/date
@todays_date = localtime(time);
# create date & time stamp for the report
$date_time = sprintf("%02d/%02d/%04d \@ %02d\:%02d\:%02d EST", $todays_date[4]+1, $todays_date[3], $todays_date[5]+1900, $todays_date[2], $todays_date[1], $todays_date[0]);

# open FAQ database file for reading
open (FAQ_DB, "$faq_db") or die "Cannot open $faq_db for reading. $!";

# read issue into memory
while(<FAQ_DB>) {
  $theline = $_;
  chomp $theline;
  $theline =~ s/\&quot;/\"/g;
  $theline =~ s/\&nbsp;/ /g;
  $theline =~ s/\&amp;/\&/g;
  #print "\n $theline";
  @issue_data = split(/\t/, $theline);
  $issue{"$issue_data[4]"} = $issue_data[1];
}

# close FAQ database file
close(FAQ_DB);


# create remove date for log entry removal
@remove_date = localtime(time);
$remove_year = $remove_date[5] + 1900;
$remove_month = ($remove_date[4] + 1) - 3; # adjust this number for how many month to only hold
if ($remove_month < 1) {
  $remove_month = $remove_month + 12;
  $remove_year = $remove_year - 1;
}
$remove_date_time = sprintf("%04d%02d%02d%02d%02d%02d",  $remove_year, $remove_month, $remove_date[3], $remove_date[2], $remove_date[1], $remove_date[0]);

# open FAQ log & swap files
open (LOG, "$faq_log") or die "Cannot open $faq_log for reading. $!"; 
open (SWAP, ">$faq_swap") or die "Cannot open $faq_swap for writing. $!"; 

# remove all entries older then removal date/time
while(<LOG>) {
  $theline = $_;
  @split_line = split(/\t/, $theline);
  # grab IP, Date, & Type
  $entry{'date'} = $split_line[1];

  if ($entry{'date'} >=  $remove_date_time) {
    print SWAP "$theline";
  }
}

# close FAQ log & swap files
close(LOG);
close(SWAP);

# write swap file to log file
$output = `cp \"$faq_swap\" \"$faq_log\"`;

sleep(2); # let I/O catch up

# open log file for reading
open (LOG, "$faq_log") or die "Cannot open $faq_log for reading. $!";

while(<LOG>) {
  $theline = $_;
  chomp $theline;
  @split_line = split(/\t/, $theline);

  # grab IP, Date, & Type
  $entry{'ip'}   = $split_line[0];
  $entry{'date'} = $split_line[1];
  $entry{'type'} = $split_line[2];  
  for ($z = 3; $z <= $#split_line; $z++) {
    @temp = split(/\|/, $split_line[$z], 2);
    $entry{"$temp[0]"} = $temp[1]; # set names/values for entry data
    #print "  Entry: $temp[0] = $entry{\"$temp[0]\"}\n";
  }
  #print "\n";

  # skip PnP IPs
  if (($entry{'ip'} =~ /209.51.163.|209.51.171./) && ($ARGV[0] !~ /pnp/i) && ($entry{'type'} !~ /^(ADD|UPDATE|DELETE)$/)) {
    next; # skip entry
  }

  # add to total number of views and queries done
  if ($entry{'type'} eq "VIEW") {
    $total_views = $total_views + 1;
  }
  elsif ($entry{'type'} eq "QUERY") {
    $total_queries = $total_queries + 1;
  }
  elsif ($entry{'type'} eq "ADD") {
    $total_added = $total_added + 1;
  }
  elsif ($entry{'type'} eq "UPDATE") {
    $total_updated = $total_updated + 1;
  }
  elsif ($entry{'type'} eq "DELETE") {
    $total_deleted = $total_deleted + 1;
  }

  # process IP address
  &find_unique_ip();

  # process type & date
  &find_unique_date(); # track the dates
  &track_type();       # track the type of entry for that date
}

# close log file
close (LOG);

# produce/show stats
&stats_ip();
&stats_type();

&create_most_active_page();

if ($ARGV[0] =~ /email/) {
  &email_report();
}
else {
  print "$report";
} 

exit;

sub sort_hash_value {
  my $x = shift;
  my %array=%$x;
  sort { $array{$b} <=> $array{$a}; } keys %array;
}

sub find_unique_ip {
  # Function: finds & records new unique IPs
  $unique = "yes"; # assume IP will be unique

  for ($a = 0; $a <= $#unique_ips; $a++) {
    if ($unique_ips[$a] eq $entry{'ip'}) {
      $unique = "no";
      last;
    }
  }

  if ($unique eq "yes") {
    push(@unique_ips, $entry{'ip'}); 
    #print "Found Unique IP: $entry{'ip'}\n";
  }

  return;
}

sub stats_ip {
  # Function: produces stats on the unique IPs

  # product stat of how many IPs are seen using the FAQ
  $stats{'unique_ip_count'} = $#unique_ips + 1; # produce correct number of unique IPs.
  $report .= "\n";
  $report .= sprintf ("There were %03d unique IP addresses seen using the FAQ.\n", $stats{'unique_ip_count'});

  # produce adverage & total views and queries done
  $stats{'adverage_views_per_ip'} = $total_views / $stats{'unique_ip_count'};
  $stats{'adverage_queries_per_ip'} = $total_queries / $stats{'unique_ip_count'};
  $report .= sprintf ("There were %03d total issues viewed on the FAQ.\n", $total_views);
  $report .= sprintf ("There were %03d total queries performed on the FAQ.\n", $total_queries);
  $report .= "\n";
  $report .= sprintf ("There were %03d total issues added to the FAQ.\n", $total_added);
  $report .= sprintf ("There were %03d total issues updated in the FAQ.\n", $total_updated);
  $report .= sprintf ("There were %03d total issues deleted from the FAQ.\n", $total_deleted);
  $report .= "\n";
  $report .= sprintf("The adverage usage per IP - Views: %03.02f : Query: %03.02f\n", $stats{'adverage_views_per_ip'}, $stats{'adverage_queries_per_ip'});

  return;
}

sub find_unique_date {
  # Function: finds & records new unique IPs
  $unique = "yes"; # assume IP will be unique

  $date = substr($entry{'date'}, 0, 8); # grab date
 
  for ($a = 0; $a <= $#unique_date; $a++) {
    if ($unique_date[$a] eq $date) {
      $unique = "no";
      last;
    }
  }
 
  if ($unique eq "yes") {
    push(@unique_date, $date);
    #print "Found Unique date: $date\n";
  }

  # incriment count for that date
  $date_count{"$date"} = $date_count{"$date"} + 1;
 
  return;
}

sub track_type {
  # Function: track each type count

  # track total type counts by date
  if ($entry{'type'} eq "VIEW") {
    $total_view_count{"$date"} = $total_view_count{"$date"} + 1;
  }
  elsif ($entry{'type'} eq "QUERY") {
    $total_query_count{"$date"} = $total_query_count{"$date"} + 1;
  }
  elsif ($entry{'type'} eq "ADD") {
    $total_add_count{"$date"} = $total_add_count{"$date"} + 1;
  }
  elsif ($entry{'type'} eq "UPDATE") {
    $total_update_count{"$date"} = $total_update_count{"$date"} + 1;
  }
  elsif ($entry{'type'} eq "DELETE") {
    $total_delete_count{"$date"} = $total_delete_count{"$date"} + 1;
  }


  # track type by IP
  if ($entry{'type'} eq "VIEW") {
    $ip_view_count{"$entry{'ip'}"} = $ip_view_count{"$entry{'ip'}"} + 1;
  }
  elsif ($entry{'type'} eq "QUERY") {
    $ip_query_count{"$entry{'ip'}"} = $ip_query_count{"$entry{'ip'}"} + 1;
  } 

  # track view type by id_number
  if ($entry{'type'} eq "VIEW") {   
    $id_number_count{"$entry{'id_number'}"} = $id_number_count{"$entry{'id_number'}"} + 1;
    #print "Found Viewed QA Number: $entry{'id_number'}\n";
  } 
  elsif ($entry{'type'} eq "QUERY") {
    # split search_keys for indivual keywords
    @keywords = split(/\, |\; |\,|\;/, $entry{'search_keys'});
    # read & count each keyword
    for ($a = 0; $a <= $keywords; $a++) {
      # check to see if it's a excluded word, if so clean it up
      $letter = substr($keywords[$a], 0, 1);
      if ($letter eq "-") {
        $keywords[$a] = substr($keywords[$a], 1); # remove first character, if it's "-".
      }
      if (($keywords[$a] !~ /QA200/) && ($keywords[$a] ne "")) {
        $keyword_count{"$keywords[$a]"} = $keyword_count{"$keywords[$a]"} + 1;
        #print "  Added Keyword: $keywords[$a]\n";
      }
    }
  }

  return;
}

sub stats_type {
  # Function: show stats for each type for each day 

  $report .= "\n";
  $report .= "General Stats: (By Date)\n";
  for ($a = 0; $a <= $#unique_date; $a++) {
    $report .= sprintf("Date: %s - Total: Viewed: %03d : Query: %03d : Added: %02d : Updated: %02d : Deleted: %02d\n", $unique_date[$a], $total_view_count{"$unique_date[$a]"}, $total_query_count{"$unique_date[$a]"}, $total_add_count{"$unique_date[$a]"}, $total_update_count{"$unique_date[$a]"}, $total_delete_count{"$unique_date[$a]"} );
  }

#  $report .= "\n";
#  $report .= "General Stats: (By IP)\n";
#  for ($a = 0; $a <= $#unique_ips; $a++) {
#    $report .= sprintf("IP: %15s - Total: Viewed: %02d : Query: %02d\n", $unique_ips[$a], $ip_view_count{"$unique_ips[$a]"}, $ip_query_count{"$unique_ips[$a]"} );
#  }

  $limit = 25; # max limit is X
  $count = 0;  # clear & initialize value
  $report .= "\n";
  $report .= "General Stats: (By QA Number) [Top $limit]\n";
  foreach $key (&sort_hash_value(\%id_number_count)) {
    $count++;
    if ($count <= $limit) {
      $report .= sprintf("QA Number: %s - Total Views: %04d\n", $key, $id_number_count{"$key"} );
      $report .= "----> $issue{$key}\n\n";
    }
    else {
      last;
    }
  }

  $limit = 100; # max limit is X
  $count = 0;  # clear & initialize value
  $report .= "\n";
  $report .= "General Stats: (By Keyword or Key Phrase) [Top $limit]\n";
  foreach $key (&sort_hash_value(\%keyword_count)) {
    $count++;
    if ($count <= $limit) {
      $report .= sprintf("Keyword: %42s - Total %04d\n", $key, $keyword_count{"$key"} );
    }
    else {
      last;
    }
  }

  return;
}

sub create_most_active_page {
  # Function: create the FAQ's most active content web page

  $data = ""; # initialize data variable which will contain all the most active web page content

  # create web page header
  $data .= "<html>\n";
  $data .= "<head>\n";
  $data .= "<title>Online Reseller Issuer Center & FAQ's Most Active</title>\n";
  $data .= "</head>\n";
  $data .= "<body bgcolor=\"\#ffffff\" text=\"\#000000\">\n";

  $data .= "<div align=\"center\">\n";
  $data .= "<font size=\"+1\"><b>Online Reseller Issuer Center & FAQ 's Most Active</b></font>\n";
  $data .= "<br><font size=\"-1\" color=\"\#000000\"><i>Last Updated: $date_time</i></font>\n";
  $data .= "<br><font size=\"-1\" color=\"\#ff0000\"><i>This Page Is Updated Weekly.</i></font>\n";

  $data .= "<p>Below you will find the most active content in which resellers have read \&amp; searched for.  We believe the below information will assist you in finding answers to those most frequently asked questions from our extensive online reseller FAQ database. If you do not find what you are looking for, don't forget to search the rest of our extensive online reseller FAQ database and review our documentation center.\n";

  # produce most active FAQ issues 
  $limit = 25; # max limit is X
  $count = 0;  # clear & initialize value

  $data .= "<p><table border=\"1\" width=\"80%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <th colspan=\"3\" bgcolor=\"\#6688A4\"><font color=\"\#ffffff\">Top $limit Most Active Issues</font></th>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
#  $data .= "    <th bgcolor=\"\#99BBD7\">QA Number:</th>\n";
  $data .= "    <th bgcolor=\"\#99BBD7\">Issue:</th>\n";
  $data .= "    <th bgcolor=\"\#99BBD7\">&nbsp;</th>\n";
  $data .= "  </tr>\n";

  foreach $key (&sort_hash_value(\%id_number_count)) {
    $count++;
    if ($count <= $limit) {
      $data .= "  <tr>\n";
#      $data .= "    <td width=\"15%\" align=\"center\">$key</td>\n";
      $data .= "    <td>$issue{$key}</td>\n";
      $data .= "    <td width=\"10%\" align=\"center\"><form method=\"post\" action=\"reseller_board.cgi\">\n";
      $data .= "      <input type=\"hidden\" name=\"mode\" value=\"view_description\">\n";
      $data .= "      <input type=\"hidden\" name=\"id_number\" value=\"$key\">\n";
      $data .= "      <input type=\"submit\" value=\"View Description\"></td></form>\n";
      $data .= "  </tr>\n";
    }
    else {
      last;
    }
  }

  $data .= "</table>\n";

  # produce most accessed keywords
  $limit = 25; # max limit is X
  $count = 0;  # clear & initialize value

  $data .= "<p><table border=\"1\" width=\"50%\">\n";
  $data .= "  <tr>\n";
  $data .= "    <th colspan=\"3\" bgcolor=\"\#6688A4\"><font color=\"\#ffffff\">Top $limit Most Active Keywords</font></th>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <th bgcolor=\"\#99BBD7\">Keyword or Key Phrase:</th>\n";
  $data .= "    <th bgcolor=\"\#99BBD7\">&nbsp;</th>\n";
  $data .= "  </tr>\n";

  foreach $key (&sort_hash_value(\%keyword_count)) {
    $count++;
    if ($count <= $limit) {
      $data .= "  <tr>\n";
      $data .= "    <td align=\"center\">$key</td>\n";
      $data .= "    <td width=\"10%\" align=\"center\"><form method=\"post\" action=\"reseller_board.cgi\">\n";
      $data .= "      <input type=\"hidden\" name=\"mode\" value=\"search_issue\">\n";
      $data .= "      <input type=\"hidden\" name=\"category\" value=\"all\">\n";
      $data .= "      <input type=\"hidden\" name=\"search_keys\" value=\"$key\">\n";
      $data .= "      <input type=\"submit\" value=\"Access Issue(s)\"></td></form>\n";
      $data .= "  </tr>\n";
    }
    else {
      last;
    }
  }

  $data .= "</table>\n";

  $data .= "</div>\n";

  $data .= "<div align=\"center\">\n";
  $data .= "<p><form><input type=\"button\" value=\"Back To Online Reseller FAQ\" onClick=\"javascript:history.go(-1);\"></form>\n";
  $data .= "</div>\n";

  $data .= "</body>\n";
  $data .= "</html>\n";

  # write web page
  open(MOST_ACTIVE, ">$faq_most_active") or die "Cannot open $faq_most_active for writing. $!";
  print MOST_ACTIVE $data;
  close(MOST_ACTIVE);

  return;
}

sub email_report {
  # Function: Email FAQ stats report

  # email the report
  open(MAIL1, "| /usr/lib/sendmail -t");
  print MAIL1 "To: $email\n";
  print MAIL1 "From: $from_email\n";
  if ($cc_email ne "") {
    print MAIL1 "Cc: $cc_email\n";
  }
  if ($bcc_email ne "") {
    print MAIL1 "Bcc: $bcc_email\n";
  }
  if ($subject ne ""){
    print MAIL1 "Subject: $subject\n";
  }
  else {
    print MAIL1 "Subject: Reseller FAQ Statistics - $date_time\n";
  }
  print MAIL1 "\n";

  print MAIL1 $report;

  print MAIL1 "\n\n";
  close(MAIL1);

  return;
}

