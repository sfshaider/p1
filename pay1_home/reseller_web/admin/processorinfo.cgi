#!/bin/env perl

require 5.001;
$|=1;

use lib '/home/p/pay1/perl_lib';
use isotables;
use constants qw(@planetpay_currencies,@fifththird_currencies,@ncb_currencies,@pago_currencies,@globalc_currencies,@wirecard_currencies,%currency_hash);
use CGI;

print "Content-Type: text/html\n\n";

my $query = new CGI;
##  Processor List
@processors = ('buypass','fdms','fdmsintl','fdmsomaha','universal','wirecard','global','globalc','paytechsalem','paytechtampa','nova','village','visanet','maverick','ncb','pago','planetpay','fifththird','barclays','rbc');

# check which processor
if (&CGI::escapeHTML($query->param('processor')) eq "paytechtampa") {
  # if not set use paytechtampa
  &head_paytechtampa();
  &main_paytechtampa();
  &tail();
}
elsif (&CGI::escapeHTML($query->param('processor')) eq "visanet") {
  # if not set use visanet
  &head_visanet();
  &main_visanet();
  &tail();
}
#elsif (&CGI::escapeHTML($query->param('processor')) eq "volpay") {
#  # if not set use volpay
#  &head_volpay();
#  &main_volpay();
#  &tail();
#}
elsif (&CGI::escapeHTML($query->param('processor')) eq "planetpay") {
  if (&CGI::escapeHTML($query->param('merchant_bank')) eq "tsys") {
    &head_planetpaytsys();
    &main_planetpaytsys();
  }
  else {
    &head_planetpay();
    &main_planetpay();
  }
  &tail();
}
elsif (&CGI::escapeHTML($query->param('processor')) eq "fifththird") {
  &head_fifththird();
  &main_fifththird();
  &tail();
}
elsif (&CGI::escapeHTML($query->param('processor')) eq "fdmsintl") {
  &head_fdmsintl();
  &main_fdmsintl();
  &tail();
}
elsif (&CGI::escapeHTML($query->param('processor')) eq "cccc") {
  &head_cccc();
  &main_cccc();
  &tail();
}
elsif (&CGI::escapeHTML($query->param('processor')) eq "ncb") {
  &head_ncb();
  &main_ncb();
  &tail();
}
elsif (&CGI::escapeHTML($query->param('processor')) eq "pago") {
  &head_pago();
  &main_pago();
  &tail();
}
else {
  # if not set use generic
  &head_generic();
  &main_generic();
  &tail();
}

exit;

sub head_generic {
  &head_start();
  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "  function postResults() {\n";
  print "    window.opener.document.addmerchant.merchant_id.value = document.generic.merchant_id.value;\n";
  print "    window.opener.document.addmerchant.terminal_id.value = document.generic.pubsecret.value;\n";
  print "    window.opener.document.addmerchant.banknum.value = document.generic.banknum.value;\n";
  print "    window.close();\n";
  print "  }\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_paytechtampa {
  &head_start();
  print "  <script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "  function postResults() {\n";
  print "    window.opener.document.addmerchant.merchant_id.value = document.paytechtampa.merchant_id.value;\n";
  print "    window.opener.document.addmerchant.terminal_id.value = document.paytechtampa.pubsecret.value;\n";
  print "    window.opener.document.addmerchant.banknum.value = document.paytechtampa.banknum.value;\n";
  print "    window.opener.document.addmerchant.clientid.value = document.paytechtampa.clientid.value;\n";
  print "    window.close();\n";
  print "  }\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_visanet {
  &head_start();
  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "function postResults() {\n";
  print "  window.opener.document.addmerchant.currency.value = document.visanet.currency.value;\n";
  print "  window.opener.document.addmerchant.merchant_id.value = document.visanet.merchant_id.value;\n";
  print "  window.opener.document.addmerchant.terminal_id.value = document.visanet.pubsecret.value;\n";
  print "  window.opener.document.addmerchant.bin.value = document.visanet.bin.value;\n";
  print "  window.opener.document.addmerchant.categorycode.value = document.visanet.categorycode.value;\n";
  print "  window.opener.document.addmerchant.agentbank.value = document.visanet.agentbank.value;\n";
  print "  window.opener.document.addmerchant.agentchain.value = document.visanet.agentchain.value;\n";
  print "  window.opener.document.addmerchant.storenum.value = document.visanet.storenum.value;\n";
  print "  window.opener.document.addmerchant.terminalnum.value = document.visanet.terminalnum.value;\n";
  print "  window.close();\n";
  print "}\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_planetpaytsys {
  &head_start();
  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "function postResults() {\n";
  print "  window.opener.document.addmerchant.currency.value = document.planetpay.currency.value;\n";
  print "  window.opener.document.addmerchant.merchant_id.value = document.planetpay.merchant_id.value;\n";
  print "  window.opener.document.addmerchant.terminal_id.value = document.planetpay.pubsecret.value;\n";
  print "  window.opener.document.addmerchant.bin.value = document.planetpay.bin.value;\n";
  print "  window.opener.document.addmerchant.categorycode.value = document.planetpay.categorycode.value;\n";
  print "  window.opener.document.addmerchant.agentbank.value = document.planetpay.agentbank.value;\n";
  print "  window.opener.document.addmerchant.agentchain.value = document.planetpay.agentchain.value;\n";
  print "  window.opener.document.addmerchant.storenum.value = document.planetpay.storenum.value;\n";
  print "  window.opener.document.addmerchant.terminalnum.value = document.planetpay.terminalnum.value;\n";
  print "  window.close();\n";
  print "}\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_planetpay {
  &head_start();
  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "function postResults() {\n";
  print "  window.opener.document.addmerchant.currency.value = document.planetpay.currency.value;\n";
  print "  window.opener.document.addmerchant.merchant_id.value = document.planetpay.merchant_id.value;\n";
  print "  window.opener.document.addmerchant.categorycode.value = document.planetpay.categorycode.value;\n";
  print "  window.opener.document.addmerchant.banknum.value = document.planetpay.banknum.value;\n";
  print "  window.close();\n";
  print "}\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_fifththird {
  &head_start();
  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "  function postResults() {\n";
  print "    window.opener.document.addmerchant.merchant_id.value = document.fifththird.merchant_id.value;\n";
  print "    window.opener.document.addmerchant.categorycode.value = document.fifththird.categorycode.value;\n";
  print "    window.opener.document.addmerchant.banknum.value = document.fifththird.banknum.value;\n";
  print "    window.close();\n";
  print "  }\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_fdmsintl {
  &head_start();
  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "  function postResults() {\n";
  print "    window.opener.document.addmerchant.merchant_id.value = document.fdmsintl.merchant_id.value;\n";
  print "    window.opener.document.addmerchant.categorycode.value = document.fdmsintl.categorycode.value;\n";
  print "    window.opener.document.addmerchant.banknum.value = document.fdmsintl.banknum.value;\n";
  print "    window.close();\n";
  print "  }\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_pago {
  &head_start();
  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "  function postResults() {\n";
  print "    window.opener.document.addmerchant.merchant_id.value = document.pago.clientname.value;\n";
  print "    window.opener.document.addmerchant.categorycode.value = document.pago.saleschannel.value;\n";
  print "    window.close();\n";
  print "  }\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_cccc {
  &head_start();
  print "  <script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "  function postResults() {\n";
  print "    window.opener.document.addmerchant.merchant_id.value = document.cccc.merchant_id.value;\n";
  print "    window.opener.document.addmerchant.terminal_id.value = document.cccc.pubsecret.value;\n";
  print "    window.opener.document.addmerchant.banknum.value = document.cccc.banknum.value;\n";
  print "    window.opener.document.addmerchant.clientid.value = document.cccc.categorycode.value;\n";
  print "    window.close();\n";
  print "  }\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}


sub head_ncb {
  &head_start();
  print "  <script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "  function postResults() {\n";
  print "    window.opener.document.addmerchant.merchant_id.value = document.ncb.merchant_id.value;\n";
  print "    window.opener.document.addmerchant.terminal_id.value = document.ncb.pubsecret.value;\n";
  print "    window.opener.document.addmerchant.banknum.value = document.ncb.banknum.value;\n";
  print "    window.opener.document.addmerchant.clientid.value = document.ncb.categorycode.value;\n";
  print "    window.opener.document.addmerchant.poscond.value = document.ncb.poscond.value;\n";
  print "    window.close();\n";
  print "  }\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_volpay {
  &head_start();
  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";
  print "function postResults() {\n";
  print "  window.opener.document.addmerchant.currency.value = document.volpay.currency.value;\n";
  print "  window.close();\n";
  print "}\n";
  print "//-->\n";
  print "</script>\n";
  &head_end();
}

sub head_start {
  print "<html>\n";
  print "<head>\n";
  print "<title> Reseller Administration</title>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"stylesheet.css\">\n";
}

sub head_end {
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
}

sub tail {
  print "</body>\n";
  print "</html>\n";
}

sub main_generic {
  # collect mid, tid, banknum
  print "  <form name=\"generic\">\n";
  print "  <table border=\"0\" cellspacing=\"0\">\n";
  print "    <tr class=\"tr1\"><th>mid:</th><td> <input type=\"text\" name=\"merchant_id\" value=\"\"><!-- 10 digits--></td>\n";
  print "    <tr class=\"tr1\"><th>tid (v#):</th><td> <input type=\"text\" name=\"pubsecret\" value=\"\"><!-- 16 digits--></td>\n";
  print "    <tr class=\"tr1\"><th>banknum:</th><td> <input type=\"text\" name=\"banknum\" value=\"\"> 6 digits</td>\n";
  print "    <tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "  </table>\n";
  print "  </form>\n";
}

sub main_paytechtampa {
  print "  <form name=\"paytechtampa\">\n";
  print "    <table border=\"0\" cellspacing=\"0\">\n";
  print "    <tr class=\"tr1\"><th>mid:</th><td> <input type=\"text\" name=\"merchant_id\" value=\"\"> 12 digits</td>\n";
  print "    <tr class=\"tr1\"><th>tid (v#):</th><td> <input type=\"text\" name=\"pubsecret\" value=\"\"> 3 digits</td>\n";
  print "    <tr class=\"tr1\"><th>client id:</th><td> <input type=\"text\" name=\"clientid\" value=\"\"> 4 digits</td>\n";
  print "    <tr class=\"tr1\"><th>banknum:</th><td> <input type=\"text\" name=\"banknum\" value=\"\"> 3 digits</td>\n";
  print "    <tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}

sub main_visanet {
  my %selected = ();
  $selected{'usd'} = " selected";
  print "<form name=\"visanet\">\n";
  print "<table border=\"0\" cellspacing=\"0\">\n";
  print "<tr class=\"tr1\"><th>Currency:</th><td>\n";
  print "  <select name=\"currency\">\n";
  foreach my $key (@constants::visanet_currencies) {
    print "<option value=\"$key\" $selected{$key}> $constants::currency_hash{$key} </option>\n";
  }
  print "  </select>\n";
  print "</td>\n";

  print "<tr class=\"tr1\"><th>mid:</th><td> <input type=\"text\" name=\"merchant_id\" value=\"\"> 12 digits</td>\n";
  print "<tr class=\"tr1\"><th>tid (v#):</th><td> <input type=\"text\" name=\"pubsecret\" value=\"\"> 8 digits</td>\n";
  print "<tr class=\"tr1\"><th>bin:</th><td> <input type=\"text\" name=\"bin\" value=\"\"> 6 digits</td>\n";
  print "<tr class=\"tr1\"><th>categorycode:</th><td> <input type=\"text\" name=\"categorycode\" value=\"\"> 4 digits</td>\n";
  print "<tr class=\"tr1\"><th>agentbank:</th><td> <input type=\"text\" name=\"agentbank\" value=\"\"> 6 digits </td>\n";
  print "<tr class=\"tr1\"><th>agentchain:</th><td> <input type=\"text\" name=\"agentchain\" value=\"\"> 6 digits </td>\n";
  print "<tr class=\"tr1\"><th>storenum:</th><td> <input type=\"text\" name=\"storenum\" value=\"\"> 4 digits </td>\n";
  print "<tr class=\"tr1\"><th>terminalnum:</th><td> <input type=\"text\" name=\"terminalnum\" value=\"\"> 4 digits </td>\n";
  print "<tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}

sub main_planetpaytsys {
  print "<form name=\"planetpay\">\n";
  print "<table border=\"0\" cellspacing=\"0\">\n";
  print "<tr class=\"tr1\"><th>Currency:</th><td>\n";
  print "  <select name=\"currency\" multiple size=4>\n";
  foreach my $key (@constants::planetpay_currencies) {
    print "<option value=\"$key\"";
    print "> $constants::currency_hash{$key} </option>\n";
  }
  print "  </select>\n";
  print "</td>\n";

  print "<tr class=\"tr1\"><th>mid:</th><td> <input type=\"text\" name=\"merchant_id\" value=\"\"> 12 digits</td>\n";
  print "<tr class=\"tr1\"><th>tid (v#):</th><td> <input type=\"text\" name=\"pubsecret\" value=\"\"> 8 digits</td>\n";
  print "<tr class=\"tr1\"><th>bin:</th><td> <input type=\"text\" name=\"bin\" value=\"\"> 6 digits</td>\n";
  print "<tr class=\"tr1\"><th>categorycode:</th><td> <input type=\"text\" name=\"categorycode\" value=\"\"> 4 digits</td>\n";
  print "<tr class=\"tr1\"><th>agentbank:</th><td> <input type=\"text\" name=\"agentbank\" value=\"\"> 6 digits </td>\n";
  print "<tr class=\"tr1\"><th>agentchain:</th><td> <input type=\"text\" name=\"agentchain\" value=\"\"> 6 digits </td>\n";
  print "<tr class=\"tr1\"><th>storenum:</th><td> <input type=\"text\" name=\"storenum\" value=\"\"> 4 digits </td>\n";
  print "<tr class=\"tr1\"><th>terminalnum:</th><td> <input type=\"text\" name=\"terminalnum\" value=\"\"> 4 digits </td>\n";
  print "<tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}

sub main_planetpay {
  print "<form name=\"planetpay\">\n";
  print "<table border=\"0\" cellspacing=\"0\">\n";
  print "<tr class=\"tr1\"><th>Currency:</th><td>\n";
  print "  <select name=\"currency\" multiple size=4>\n";
  foreach my $key (@constants::planetpay_currencies) {
    print "<option value=\"$key\"";
    print "> $constants::currency_hash{$key} </option>\n";
  }
  print "  </select>\n";
  print "</td>\n";
  print "<tr class=\"tr1\"><th>mid:</th><td> <input type=\"text\" name=\"merchant_id\" value=\"\"> 12 digits</td>\n";
  if (&CGI::escapeHTML($query->param('merchant_bank')) =~ /Humbolt/) {
    print "<tr class=\"tr1\"><th>Bankid:</th><td> 441895<input type=\"hidden\" name=\"banknum\" value=\"441895\"> 6 digits</td>\n";
  }
  else {
    print "<tr class=\"tr1\"><th>Bankid:</th><td> <input type=\"text\" name=\"banknum\" value=\"\"> 6 digits</td>\n";
  }
  print "<tr class=\"tr1\"><th>categorycode:</th><td> <input type=\"text\" name=\"categorycode\" value=\"\"> 4 digits</td>\n";
  print "<tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}

sub main_fifththird {
  print "<form name=\"fifththird\">\n";
  print "<table border=\"0\" cellspacing=\"0\">\n";
  print "<tr class=\"tr1\"><th>Currency:</th><td>\n";
  print "  <select name=\"currency\" multiple size=4>\n";
  foreach my $key (@constants::fifththird_currencies) {
    print "<option value=\"$key\"";
    print "> $constants::currency_hash{$key} </option>\n";
  }
  print "  </select>\n";
  print "</td>\n";

  print "<tr class=\"tr1\"><th>mid:</th><td> <input type=\"text\" name=\"merchant_id\" value=\"\"> 12 digits</td>\n";
  print "<tr class=\"tr1\"><th>Bankid:</th><td> <input type=\"text\" name=\"banknum\" value=\"\"> 6 digits</td>\n";
  print "<tr class=\"tr1\"><th>categorycode:</th><td> <input type=\"text\" name=\"categorycode\" value=\"\"> 4 digits</td>\n";
  print "<tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}

sub main_fdmsintl {
  my %selected = ();
  $selected{'usd'} = " selected";
  print "<form name=\"fdmsintl\">\n";
  print "<table border=\"0\" cellspacing=\"0\">\n";
  print "<tr class=\"tr1\"><th>Currency:</th><td>\n";
  print "  <select name=\"currency\">\n";
  foreach my $key (@constants::fdmsintl_currencies) {
    print "<option value=\"$key\" $selected{$key}> $constants::currency_hash{$key} </option>\n";
  }
  print "  </select>\n";
  print "</td>\n";

  print "<tr class=\"tr1\"><th>mid:</th><td> <input type=\"text\" name=\"merchant_id\" value=\"\"> 12 digits</td>\n";
  print "<tr class=\"tr1\"><th>bankid:</th><td> <input type=\"text\" name=\"banknum\" value=\"\"> 6 digits</td>\n";
  print "<tr class=\"tr1\"><th>categorycode:</th><td> <input type=\"text\" name=\"categorycode\" value=\"\"> 4 digits</td>\n";
  print "<tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}

sub main_pago {
  print "<form name=\"pago\">\n";
  print "<table border=\"0\" cellspacing=\"0\">\n";
  print "<tr class=\"tr1\"><th>Currency:</th><td>\n";
  print "  <select name=\"currency\" multiple size=4>\n";
  foreach my $key (sort keys %isotables::currencyUSD2) {
    print "<option value=\"$key\"";
    if ($key =~ /USD/i) {
      print " selected";
    }
    print "> $key </option>\n";
  }
  print "  </select>\n";
  print "</td>\n";

  print "<tr class=\"tr1\"><th>client name:</th><td> <input type=\"text\" name=\"clientname\" value=\"\"> 12 digits</td>\n";
  print "<tr class=\"tr1\"><th>sales channel:</th><td> <input type=\"text\" name=\"saleschannel\" value=\"\"> 6 digits</td>\n";
  print "<tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}

sub main_cccc {
  my %selected = ();
  $selected{'usd'} = " selected";
  print "<form name=\"cccc\">\n";
  print "<table border=\"0\" cellspacing=\"0\">\n";
  print "<tr class=\"tr1\"><th>Currency:</th><td>\n";
  print "  <select name=\"currency\">\n";
  foreach my $key (@constants::cccc_currencies) {
    print "<option value=\"$key\" $selected{$key}> $constants::currency_hash{$key} </option>\n";
  }
  print "  </select>\n";
  print "</td>\n";
  print "<tr class=\"tr1\"><th>mid:</th><td> <input type=\"text\" name=\"merchant_id\" value=\"\"> 12 digits</td>\n";
  print "<tr class=\"tr1\"><th>tid:</th><td> <input type=\"text\" name=\"pubsecret\" value=\"\"> 8 digits</td>\n";
  print "<tr class=\"tr1\"><th>bankid:</th><td> <input type=\"text\" name=\"banknum\" value=\"\"> 6 digits</td>\n";
  print "<tr class=\"tr1\"><th>categorycode:</th><td> <input type=\"text\" name=\"categorycode\" value=\"\"> 4 digits</td>\n";
  print "<tr class=\"tr1\"><th>POS CondCode:</th><td> <input type=\"text\" name=\"poscond\" value=\"\"> 4 digits</td>\n";
  print "<tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}

sub main_ncb {
  my %selected = ();
  $selected{'usd'} = " selected";
  print "<form name=\"ncb\">\n";
  print "<table border=\"0\" cellspacing=\"0\">\n";
  print "<tr class=\"tr1\"><th>Currency:</th><td>\n";
  print "  <select name=\"currency\" multiple size=4>\n";
  foreach my $key (@constants::ncb_currencies) {
    print "<option value=\"$key\" $selected{$key}> $constants::currency_hash{$key} </option>\n";
  }
  print "  </select>\n";
  print "</td>\n";

  print "<tr class=\"tr1\"><th>mid:</th><td> <input type=\"text\" name=\"merchant_id\" value=\"\"> 12 digits</td>\n";
  print "<tr class=\"tr1\"><th>tid:</th><td> <input type=\"text\" name=\"pubsecret\" value=\"\"> 8 digits</td>\n";
  print "<tr class=\"tr1\"><th>bankid:</th><td> <input type=\"text\" name=\"banknum\" value=\"\"> 6 digits</td>\n";
  print "<tr class=\"tr1\"><th>categorycode:</th><td> <input type=\"text\" name=\"categorycode\" value=\"\"> 4 digits</td>\n";
  print "<tr class=\"tr1\"><th>POS CondCode:</th><td> <input type=\"text\" name=\"poscond\" value=\"\"> 4 digits</td>\n";
  print "<tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}


# main body for volpay
sub main_volpay {
  print "<form name=\"volpay\">\n";
  print "  <table border=\"0\" cellspacing=\"0\">\n";
  print "  <tr class=\"tr1\"><th>Currency:</th><td> <input type=\"radio\" name=\"currency\" value=\"usd\"> (usd) <input type=\"radio\" name=\"currency\" value=\"eur\"> (eur)</td>\n";
  print "  <tr><td colspan=\"2\"><input type=\"button\" value=\"Send Info\" onClick=\"postResults();\"> <input type=\"reset\" value=\"Reset Form\"></td>\n";
  print "</table>\n";
  print "</form>\n";
}
