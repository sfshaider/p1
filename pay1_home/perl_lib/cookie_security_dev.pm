#!/usr/local/bin/perl

$| = 1;

package cookie_security;

use CGI;
#use Apache;
use strict;

sub new {
  my $type = shift;

  ($cookie_security::source) = @_;

  my $data = new CGI;

  %cookie_security::feature = ();

  @cookie_security::new_areas = ();

  my @params = $data->param();
  my $datetime = gmtime(time());

  %cookie_security::areas = ('/','ADMIN');

  return [], $type;
}

sub log_in_cookie {
  my ($action, $destination, $message) = @_;

  $destination =~ s/[\(\)\;\'\"\<\>]//g;
  $destination = &CGI::escapeHTML($destination);

  &head();

  if ($message ne "") {
    print "  <tr>\n";
    print "    <td align=\"center\" colspan=\"3\" style=\"position:static; height: 40px; \" > $message </td>\n";
    print "  </tr>\n";
  }
  else {
    print "  <tr>\n";
    print "    <td align=\"center\" colspan=\"3\" style=\"position:static; height: 40px; \" > &nbsp; </td>\n";
    print "  </tr>\n";
  }


  print "<form method=\"post\" action=\"$action\" name=\"loginform\" onsubmit=\"return validateloginform()\">\n";
  print "<input type=\"hidden\" name=\"cchromebebroke\" value=\"1\">\n";  ### DCP 20111219 CHROME

  print "  <tr>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=\"right\" width=\"50%\" colspan=\"1\"><font size=\"+1\">Login:</font></td>\n";
  print "    <td align=\"left\" width=\"50%\" colspan=\"1\"><input name=\"credential_0\" type=\"text\" size=\"16\" maxlength=\"255\" value=\"\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td align=\"right\" width=\"50%\" colspan=\"1\"><font size=\"+1\">Password:</font>\n";
  print "    <td align=\"left\" width=\"50%\" colspan=\"1\"><input name=\"credential_1\" type=\"password\" size=\"16\" maxlength=\"255\" value=\"\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>&nbsp;</td>\n";
  print "    <td align=\"left\" width=\"50%\" colspan=\"2\"><a href=\"/lostpass.cgi\">Forgot Password?</a></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>&nbsp;</td>\n";
  print "    <td align=\"left\" width=\"50%\" colspan=\"2\"><a href=\"http://www.gatewaystatus.com\" target=\"_blank\">Gateway Status</a></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"center\"><input type=\"submit\" value=\" &nbsp; Log In &nbsp; \"></td>\n";
  print "  </tr>\n";
  print "  <input type=\"hidden\" name=\"destination\" value=\"$destination\">\n";
  print "</form>\n";
  &tail();
}

sub head {
  print "<html>\n";
  print "  <head>\n";
  print "    <title>Merchant Administration Area</title>\n";
  print "    <META HTTP-EQUIV=\"CACHE-CONTROL\" CONTENT=\"NO-CACHE\">\n";
  print "    <META HTTP-EQUIV=\"PRAGMA\" CONTENT=\"NO-CACHE\">\n";
  print "    <link href=\"/css/style_security.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  #print " <!--4012888888881881-->\n";
  #print "<!-- \n";
  #foreach my $key (sort keys %ENV) {
  #print "K:$key:$ENV{$key}\n";
  #}
  #print "-->\n";

  if ($ENV{'REDIRECT_URL'} =~ /courtpay/i) { 
    print "<link href=\"/css/style_security.css\" type=\"text/css\" rel=\"stylesheet\">\n";

    print "    <script type=\"text/javascript\">\n";
    print "      function validateloginform()\n";
    print "      {\n";
    print "        if (document.loginform.credential_0.value == \"\" || document.loginform.credential_1.value == \"\")\n";
    print "        {\n";
    print "          alert(\"A Username and Password are required.\");\n";
    print "          return false;\n";
    print "        }\n";
    print "        else \n";
    print "        {\n";
    print "          return true;\n";
    print "        }\n";
    print "      }\n";
    print "    </script>\n";

    #  $path_logout = $billpay_adminutils::path_logout;


    print "<link href=\"/css/style.css\" type=\"text/css\" rel=\"stylesheet\">\n";

    print "</head>\n";
    print "<body bgcolor=\"#ffffff\">\n";
     
    print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
    print "  <tr>\n";
    print "    <td colspan=\"3\" align=\"left\">";
    print "<img src=\"/logos/upload/logos/courtpay.jpg\" alt=\"CourtPay.\" height=\"44\" border=\"0\">";
    print "</td>\n";
    print "  </tr>\n";
    
    print "  <tr>\n";
    print "    <td colspan=\"3\" align=\"left\"><img src=\"/images/header_bottom_bar_gfx.gif\" width=\"760\" alt=\"plug \'n pay\" height=\"14\"></td>\n";
    print "  </tr>\n";
    print "</table>\n";

    print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"5\" width=\"760\">\n";
    print "  <tr>\n";
    print "    <td colspan=\"3\" valign=\"top\" align=\"left\">\n";
    print "<h1>CourtPay Administration</h1>\n";

    print "  </head>\n";
    #print "  <body bgcolor=\"#ffffff\" alink=\"#ffffff\" link=\"#ffffff\" vlink=\"#ffffff\" onLoad=\"document.loginform.credential_0.focus()\">\n";
  }
  else {
    print "    <script type=\"text/javascript\">\n";
    print "      function validateloginform()\n";
    print "      {\n";
    print "        if (document.loginform.credential_0.value == \"\" || document.loginform.credential_1.value == \"\")\n";
    print "        {\n";
    print "          alert(\"A Username and Password are required.\");\n";
    print "          return false;\n";
    print "        }\n";
    print "        else \n";
    print "        {\n";
    print "          return true;\n";
    print "        }\n";
    print "      }\n";
    print "    </script>\n";

    print "  </head>\n";
    print "  <body bgcolor=\"#ffffff\" alink=\"#ffffff\" link=\"#ffffff\" vlink=\"#ffffff\" onLoad=\"document.loginform.credential_0.focus()\">\n";
    print "    <div align=center>\n";
    print "      <table cellspacing=\"0\" cellpadding=\"4\" border=\"0\" width=\"500\">\n";
    print "        <tr>\n";
    print "          <td align=\"center\" colspan=\"3\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corp. Logo.\"></td>\n";
    print "        </tr>\n";
  }

}

sub tail {
  print "      </table>\n";
  print "    </div>\n";
  print "  </body>\n";
  print "</html>\n";
}


sub log_out_cookie {
  my ($action,$destination) = @_;

  &log_in_cookie($action, $destination, "<P>You have been logged out.</P>\n");
}

