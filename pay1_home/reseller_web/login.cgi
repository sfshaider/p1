#!/bin/env perl

require 5.001;
$|=1;

use lib $ENV{'PNP_PERL_LIB'};
use cookie_security_dev;
use CGI;
use strict;

#print "Content-Type: text/html\n\n";

my $query = new CGI();

my %act_to_dest = ("admin","/ADMIN","private","/PRIV",'wml','/PRIV');

# get a domain to set cookies formy
my $login_domain = $ENV{'HTTP_X_FORWARDED_HOST'};
if ($login_domain =~ /\,/) {
  $login_domain = (split(/\,/,$login_domain))[0];
}
if ($login_domain eq "") {
  $login_domain = $ENV{'SERVER_NAME'};
  if ($login_domain eq "") {
    $login_domain = ".plugnpay.com";
  }
}

$ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];  #### DCP 20100713

# use full domain for policy_link
my $policy_link = "https://" . $login_domain . "/w3c/p3p.xml";
my $login_host = $login_domain;

my @domain_parts = split(/\./, $login_domain);
my $login_domain_org = $login_domain;
$login_domain = "." . $domain_parts[$#domain_parts - 1] . "." . $domain_parts[$#domain_parts];

#my $CP = "NOI CURa ADMa DEVa TAIa CONa OUR DELa BUS IND PHY ONL UNI PUR COM NAV DEM STA";
#my $CP = "NOI CURa ADMa TAIa BUS IND ONL UNI COM NAV STA";
#my $CP = "NOI CURa ADMa TAIa BUS ONL UNI COM NAV STA";
#my $CP = "NOI";
#my $CP = "IDC DSP COR CURa ADMa OUR IND PHY ONL COM STA";
#$CP = "NOI ADM DEV PSAi COM NAV OUR OTRo STP IND DEM";
my $CP = "STA NAV UNI INT PSA NOI BUS TAI CUR OUR NOR";  ###  From Citibank Site

my $P3P = "policyref=$policy_link, CP=\"$CP\"";
my $cache_control = "no-store, no-cache, must-revalidate, private";


my $script_location = $ENV{'SCRIPT_URI'};
$script_location =~ s/\:81//;
$script_location =~ s/\:82//;
$script_location =~ s/http\:/https\:/i;
$script_location =~ s/backend1\.plugnpay\.com/$login_host/i;
$script_location =~ s/backend2\.plugnpay\.com/$login_host/i;

my $cp_cookie = $query->cookie(-name=>'CP',
                               -value=>$CP,
                               -expires=>'+1d',
                               -path=>'/',
                               -secure=>1,
                               -domain=>$login_domain);

# cookie variable we use to test
my $allow_cookie = $query->cookie(-name=>'allow_cookie');

# filter allow_cookie
$allow_cookie =~ /(^yes$)/;
$allow_cookie = $1;


# code to redirect after 3 attempts
my $loginattempts = $query->cookie(-name=>'loginattempts');
# filter out anything not a number
$loginattempts =~ /(^[0-9]*$)/;
$loginattempts = $1;

if ($loginattempts >= 6) {
  # redirect to failed login page
  print $query->header(-P3P => $P3P,
                       -Cache_control => $cache_control);

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);

  print "<html>\n";
  print "<head>\n";
  print "<title>Login</title>\n";
  print "<meta http-equiv=\"P3P\" content=\'CP=\"$CP\"\'>\n";
  print "<meta http-equiv=\"Refresh\" content=\"1; URL=/errors/unauthorized.cgi\">\n";
  print "<link rel=\"P3Pv1\" href=\"$policy_link\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "</body>\n";
  print "</html>\n";
  exit;
}

# increase loginattempts counter
$loginattempts += 1;
my $cookie = $query->cookie(-name=>'loginattempts',
                               -value=>$loginattempts,
                               -expires=>'+30m',
                               -path=>'/',
                               -secure=>1,
                               -domain=>$login_domain);

print $query->header(-cookie=>[$cp_cookie,$cookie],
                     -P3P => $P3P,
                     -Cache_control => $cache_control);

my $destination = $ENV{'REDIRECT_URL'};

# used as default destination if no REDIRECT_URL
# or if it contains logout.cgi
if (($destination eq "") || ($destination =~ /logout\.cgi/) || ($destination !~ /^\//)) {
  $destination = "/admin/";
}


# get the beggining part of the url
my ($action_destination) = (split(/\//,$destination))[1];
# select an action for that part
my $action = $act_to_dest{$action_destination};
# default to /admin if we can't find an action
if ($action eq "") {
  $action = "/ADMIN";
}

my $message = "";

if (($ENV{'REDIRECT_AuthCookieReason'} eq "bad_credentials") || ($ENV{'AuthCookieReason'} eq "bad_credentials")) {
  $message = "Username/Password Mismatch.<br>Please try again.";
} elsif (($ENV{'REDIRECT_AuthCookieReason'} eq "bad_cookie") || ($ENV{'AuthCookieReason'} eq "bad_cookie")) {
  $message = "You have been logged out.";
}

print "
<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">
  <html>
    <head>
      <meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\" />
      <title>Merchant Administration Area</title>
    </head>
    <body>
      <div id=\"root\"></div>
      <script src=\"/_js/r/login.js\"></script>
    </body>
  </html>
";



exit;

1;