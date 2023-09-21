#!/usr/local/bin/perl

package affiliate;
 
require 5.001;

use CGI;
use DBI;
use miscutils;
use Time::Local;
use Net::FTP;
use SHA;
use constants qw(@standardfields,%countries,%USstates,%USterritories,%CNprovinces,%USCNprov);

#use strict;

sub new {
  my $type = shift;
  ($dummy1,$dummy2,$dummy3,$sday,$smonth,$syear) = gmtime(time());
  $yyear = $syear + 1900;

  #($merchant,$source,$commonname,$from_email,$host,$homedir,$user2,$user3,$user4,$merchantdb) = @_;

  $merchant = $ENV{'REMOTE_USER'};

  if ($merchantdb eq "") {
    $merchantdb = $merchant;
  }

  $query = new CGI;
  if ($merchant eq "") {
    $merchant = &CGI::escapeHTML($query->param('merchant'));
  }
  $contactname = &CGI::escapeHTML($query->param('contactname'));
  $month = &CGI::escapeHTML($query->param('month'));
  $year = &CGI::escapeHTML($query->param('year'));
  $billingflag = &CGI::escapeHTML($query->param('billing'));
  $function = &CGI::escapeHTML($query->param('function'));
  $dropdown = &CGI::escapeHTML($query->param('dropdown'));
  $banner = &CGI::escapeHTML($query->param('banner'));
  $login = &CGI::escapeHTML($query->cookie('login'));
  $name = &CGI::escapeHTML($query->param('name'));
  $company = &CGI::escapeHTML($query->param('company'));
  $addr1 = &CGI::escapeHTML($query->param('addr1'));
  $addr2 = &CGI::escapeHTML($query->param('addr2'));
  $city = &CGI::escapeHTML($query->param('city'));
  $state = &CGI::escapeHTML($query->param('state'));
  $zip = &CGI::escapeHTML($query->param('zip'));
  $country = &CGI::escapeHTML($query->param('country'));
  $phone = &CGI::escapeHTML($query->param('phone'));
  $fax = &CGI::escapeHTML($query->param('fax'));
  $email = &CGI::escapeHTML($query->param('email'));
  ($commission,$commission_type) = split(/\|/,&CGI::escapeHTML($query->param('commission')),2);
  $url = &CGI::escapeHTML($query->param('url'));
  $url2 = &CGI::escapeHTML($query->param('url2'));

  $username = &CGI::escapeHTML($query->param('username'));
  $username =~ s/[^0-9a-zA-Z]//g; 
  $username = substr($username,0,10);

  $password = &CGI::escapeHTML($query->param('password'));

  $path_filexfer = "https://affiliate.plugnpay.com/filexfer.cgi";
  $path_base = "/home/p/pay1/web/payment/affiliate";
  $path_remotebase = "/home/a/affiliate/web/payment/affiliate";

  $affiliate::path_images = "/home/p/pay1/web/affiliate/images/";
 
  #  DCP 20060411
  #$dbh_aff = &miscutils::dbhconnect("affiliate");

  ($today) = &miscutils::gendatetime_only();

  $path_pw = "/home/p/pay1/pwfiles/";

  %endday = (1,31,2,28,3,31,4,30,5,31,6,30,7,31,8,31,9,30,10,31,11,30,12,31);
  %month_array = (1,"Jan",2,"Feb",3,"Mar",4,"Apr",5,"May",6,"Jun",7,"Jul",8,"Aug",9,"Sep",10,"Oct",11,"Nov",12,"Dec");
  %month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","Nov","11","Dec","12");

  if (0) {
    my $addr = "http://affiliate.plugnpay.com/aff_report.cgi";
    my $pairs = "function=affnew&merchant=$merchant";
    my $result = &miscutils::formpost_raw($addr,$pairs);
    my ($bannerstr,$templatestr) = split('\,',$result);
    $bannerstr =~ s/%(..)/pack('c',hex($1))/eg;
    foreach my $pair (split('&',$bannerstr)) {
      if ($pair =~ /(.*):(.*):(.*)/) { #found key=value;#
        my ($key,$value1,$value2) = ($1,$2,$3);  #get key, value
        $key =~ s/%(..)/pack('c',hex($1))/eg;
        $value1 =~ s/%(..)/pack('c',hex($1))/eg;
        $value2 =~ s/%(..)/pack('c',hex($1))/eg;
        $banner_name{$key} = $value1;
        $banner_url{$key} = $value2;
      }
    }
  }
  else {
 
  my $dbh = &miscutils::dbhconnect("affiliate");
  my $sth = $dbh->prepare(qq{
      select img_name, file_name, url 
      from banner_names
      where username='$merchant'
      }) or die "Can't do: $DBI::errstr";
  $sth->execute or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($img_name, $file_name, $banner_url));
  while($sth->fetch) {
    $banner_name{$file_name} = $img_name;
    $banner_url{$file_name} = $banner_url;
  }
  $sth->finish;
  $dbh->disconnect;
  }

  return [], $type;

}


sub head {
  print "<html>\n";
  print "<head>\n";
  print "<title>Affiliate</title> \n";
  print "</head>\n";
  print "<script Language=\"Javascript\">\n";
  print "<\!-- Start Script\n";

  print "function results() \{\n";
  print "   resultsWindow \= window.open(\"https://pay1.plugnpay.com/payment/recurring/blank.html\",\"results\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=400,height=300\")\;\n";
  print "}\n";

  print "function online_help(ht,wd) \{\n";
  print "   helpWindow \= window.open(\"https://pay1.plugnpay.com/payment/recurring/blank.html\",\"help\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=wd,height=ht\")\;\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n\n";

  if (-e "$affiliate::path_style/$affiliate::username\_aff.css") {
    print "<LINK REL=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/stylesheets/$affiliate::username\_aff.css\">
\n\n";
  }
  else {
    print "<LINK REL=\"stylesheet\" type=\"text/css\" href=\"https://pay1.plugnpay.com/stylesheets/standard_aff.css\">\n\n";
  }

  print "<body>\n";

  if (($affiliate::query{'logo'} ne "") && (-e "$affiliate::path_images/$affiliate::query{'logo'}")) {
    print "<div class=\"logo\">\n";
    print "<img src=\"/affiliate/images/$affiliate::query{'logo'}\">\n";
    print "</div>\n";
    print "\n";
  }
  print "<div class=\"page1\">\n";
}

sub enroll {
  
  print "<div class=\"enroll\">\m";
  print "<table class=\"enroll_table\">\n";
  print "<tr><td align=\"center\"><h3><font color=\"#4a7394\">Welcome to the Affiliate Setup Page</font></h3></td></tr>\n";
  print "<tr><td><font color=\"000000\" size=\"2\" face=\"Arial,Helvetica,Univers,Zurich BT\">If you wish to enroll as an affiliate, please choose a username and enter it below.</font></td></tr>\n";
  print "<tr><td><form method=\"post\" action=\"index.cgi\">\n";
  print "<input type=\"hidden\" name=\"function\" value=\"newuser\">\n";
  print "<input type=\"hidden\" name=\"url2\" value=\"$url\">\n";
  print "<font color=\"000000\" size=\"2\" face=\"Arial,Helvetica,Univers,Zurich BT\">Username:</font> <input type=\"text\" name=\"username\" value=\"$username\" size=\"10\"></td></tr>";
  print "<tr><td>";
  if ($merchant ne "") {
    print "<input type=\"hidden\" name=\"merchant\" value=\"$merchant\">\n";
  }
  else {
    print "\n";
    print "<font color=\"000000\" size=\"2\" face=\"Arial,Helvetica,Univers,Zurich BT\">The next thing we need is the PlugnPay merchant name supplied to you by your affiliate partner.<p>\n";
    print "PlugnPay Merchant Name: <input type=text name=\"merchant\"><p>\n";
  }

  print "<input type=\"submit\" value=\"Enroll as Affiliate\"></font></td></tr>\n";

}


sub tail {

  print "</table></div>\n";
  print "</body>\n";
  print "</html>\n";

}


1;
