#!/usr/bin/perl

package login;

require 5.001;

use strict;

sub new {

}

sub log_in_cookie {
  my ($action) = @_;

  &head();
  print "<form method=\"post\" action=\"$action\">\n";
  print "  <tr>\n";
  print "    <td align=\"center\" colspan=\"3\">&nbsp;</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th align=\"right\">Login:</th>\n";
  print "    <td colspan=2><input name=\"credential_0\" type=\"text\" size=\"16\" maxlength=\"255\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th align=\"right\">Password:</th>\n";
  print "    <td colspan=2><input name=\"credential_1\" type=\"password\" size=\"16\" maxlength=\"255\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th class=\"leftside\">\&nbsp\;</th>\n";
  print "    <td colspan=2><input type=\"submit\" value=\" &nbsp; Log In &nbsp; \"></td>\n";
  print "  </tr>\n";
  print "<input type=\"hidden\" name=\"destination\" value=\"$ENV{'REQUEST_URI'}\">\n";
  print "</form>\n";
  &helpdesk();
  &tail();
}

sub log_out_cookie {
  &head();
  print "<P>You have been logged out and the cookie deleted from you browser.</P>\n";
  &helpdesk();
  &tail();
}

sub head {
  print "<html>\n";
  print "<head>\n";
  print "  <title> Login </title>\n";
  print "  <LINK REL=\"SHORTCUT ICON\" HREF=\"favicon.ico\">\n";
  print "  <META HTTP-EQUIV=\"expires\" CONTENT=\"0\">\n";
  print "  <style type=\"text/css\">\n";
  print "    th { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 11pt; color: #000000 }\n";
  print "    td { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 10pt; color: #000000 }\n";
  print "    .tdtitle { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 10pt; color: #000000; background: #d0d0d0 }\n";
  print "    .tdleft { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 10pt; color: #000000; background: #d0d0d0 }\n";
  print "    .tddark { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 10pt; color: #000000; background: #4a7394 }\n";
  print "    .even {background: #ffffff}\n";
  print "    .odd {background: #eeeeee}\n";
  print "    .badcolor { color: #ff0000 }\n";
  print "    .goodcolor { color: #000000 }\n";
  print "    .larger { font-size: 100% }\n";
  print "    .smaller { font-size: 60% }\n";
  print "    .short { font-size: 8% }\n";
  print "    .button { font-size: 75% }\n";
  print "    .itemscolor { background-color: #000000; color: #ffffff }\n";
  print "    .itemrows { background-color: #d0d0d0 }\n";
  print "    .items { position: static }\n";
  print "    .info { position: static }\n";
  print "    DIV.section { text-align: justify; font-size: 12pt; color: white}\n";
  print "    DIV.subsection { text-indent: 2em }\n";
  print "    H1 { font-style: italic; color: green }\n";
  print "    H2 { color: green }\n";
  print "  </style>\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" alink=\"#000000\" link=\"#000000\" vlink=\"#000000\">\n";
  print "  <div align=center>\n";
  print "  <table cellspacing=\"0\" cellpadding=\"4\" border=\"0\" width=\"500\">\n";
  print "    <tr>\n";
  print "      <td align=\"center\" colspan=\"3\">\n";
  print "        <img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corp. Logo\">\n";
  print "<tr><td align=\"center\" colspan=\"1\"><font size=\"4\" face=\"Arial,Helvetica,Univers,Zurich BT\">Administration Login</td></tr>\n";
  print "      </td>\n";
  print "    </tr>\n";
  print "  </table>\n";
  print "<br>\n";
  print "<table border=0 cellspacing=0 cellpadding=4>\n";
}

sub tail {
  print "    </table>\n";
  print "  </div>\n";
  print "</body>\n";
  print "</html>\n";
}

sub helpdesk {
  print "  <tr>\n";
  print "    <th class=\"leftside\">\&nbsp\;</th>\n";
  print "    <td colspan=\"2\"><form method=\"post\" action=\"/admin/helpdesk.cgi\" target=\"ahelpdesk\">\n";
  print "<input type=\"submit\" name=\"submit\" value=\"Help Desk\" onClick=\"window.open(\'\',\'ahelpdesk\',\'width=550,height=520,toolbar=no,location=no,directories=no,status=no,menubar=no,scrollbars=yes,resizable=yes\'); return(true);\">\n";
  print "</td></form>\n";
  print "  </tr>\n";
}

