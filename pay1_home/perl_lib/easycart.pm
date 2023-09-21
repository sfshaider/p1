package easycart;

$| = 1;

use CGI qw/standard escapeHTML/;
use URI::Escape;

sub URLDecode {
  my $theURL = $_[0];
  $theURL =~ tr/+/ /;
  #$theURL =~ s/%([a-fA-F0-9]{2,2})/chr(hex($1))/eg;
  $theURL = &URI::Escape::uri_unescape($theURL);
  $theURL =~ s/<!--(.|\n)*-->//g;
  return $theURL;
}

sub URLEncode {
  my $theURL = $_[0];
  #$theURL =~ s/([\W])/"%" . uc(sprintf("%2.2x",ord($1)))/eg;
  $theURL = &URI::Escape::uri_escape_utf8($theURL);
  return $theURL;
}

sub new {
  my $type = shift;
  ($merchant,$from_email,$user1,$user2,$user3,$user4) = @_;

  #print "Content-type: text/html\n\n";

  local($ssec,$mmin,$hhour,$dday,$mmonth,$yyear,$wday,$yday,$isdst) = gmtime(time);
  $dday = $dday;
  $mmonth = $mmonth + 1;
  $yyear = $yyear + 1900;

  $path_easycart = $ENV{'PNP_WEB'};
  $path_easycart_txt = $ENV{'PNP_WEB_TXT'};

  $query = new CGI;

  $function  = &CGI::escapeHTML($query->param('function'));
  $function  =~ s/\W//g;

  $username  = &CGI::escapeHTML($query->param('username'));
  $username  =~ s/\W//g;

  #$transtype = &CGI::escapeHTML($query->param('transtype'));
  $continue  = &CGI::escapeHTML($query->param('continue'));

  $target    = &CGI::escapeHTML($query->param('target'));
  $target    =~ s/[^a-zA-Z_0-9\_]//g;

  $refsite   = &CGI::escapeHTML($query->param('refsite'));    #added so mechant can use mark multiple sites through ezcart**Sonny
  $refsite   =~ s/[^a-zA-Z0-9\_\-\:\/\.]//g;

  #$testwgt   = &CGI::escapeHTML($query->param('test_wgt'));  #added to test if it can be passed through with out using weight**Sonny

  $language  = &CGI::escapeHTML($query->param('language'));   #allows for spanish forms**Sonny
  $language  =~ s/\W//g;

  $acctcode  = &CGI::escapeHTML($query->param('acct_code'));  #allows for variable acct_code **Sonny
  $acctcode  =~ s/[^a-zA-Z0-9\-\ \:\.]//g;

  $url       = &CGI::escapeHTML($query->param('end-link'));
  $url       =~ s/[^a-zA-Z0-9\_\-\:\/\.]//g;

  $client    = &CGI::escapeHTML($query->param('client'));
  $client    =~ s/\W//g;

  $checkstock = &CGI::escapeHTML($query->param('checkstock'));
  $checkstock =~ s/\W//g;

  $order_id   = &CGI::escapeHTML($query->param('order-id'));
  $order_id   = substr($order_id,0,23);

  $ezc_shipping = &CGI::escapeHTML($query->param('ezc_shipping'));
  $ezc_shipping =~ s/\W//g;

  $taxshipline  = &CGI::escapeHTML($query->param('taxshipline'));
  $currency_symbol = &CGI::escapeHTML($query->param('currency_symbol'));

  $ss_version   = &CGI::escapeHTML($query->param('ss_version'));
  $ss_version   =~ s/[^0-9\.]//g;

  $ec_version   = &CGI::escapeHTML($query->param('ec_version'));
  $ec_version   =~ s/[^0-9\.]//g;

  if ($currency_symbol eq "") {
    $currency_symbol = "\$";
  }

  if ($target eq "") {
    $target = "_top";
  }

  #$debug = "yes";
  #$debugusername = "pnpdemo";

  if (($username eq $debugusername) && ($debug eq "yes")) {
    print "Content-type: text/html\n\n";
  }

  if ($username =~ /^(pnpdemo|pnpdemo2)$/) {
    # force ss_version for specific merchants
    $ss_version = 2;
  }

  if ($username =~ /^(theholisti|chloecreat|vistakawask|technologyf|chickweedh)$/) {
    # force ec_version for specific merchants
    $ec_version = 2;
  }

  if ($username =~ /^(digitalr|interactiv|alkireenter|foreignaffa|accredited)$/) {
    $allow_modify = "no";
  }

  if ($username =~ /^(friendfolks|ladybutton|pnpdemo)$/) {
    $allow_decimal_qty = 1;
  }

  if ($username =~ /^(pnpdemo2|diamond)$/) {
    $showskus = "yes";
  }

  # put merchant username here to force legacy (space delimited) cookie format 
  if ($username =~ /^(biggirls|biggirls2)$/) {
    $legacy_cookie = "yes";
  }

  # put merchant username here to bar customname/customvalue fields from being passed to payment page.
  if ($username =~ /^(safeplacel)$/) {
    $bar_custfields = "yes";
  }

  open(DOMAINS,"$path_easycart_txt/domains.txt");
  while (<DOMAINS>) {
    chop;
    if ($_ =~ /^$username\b/i) {
      ($d,$domain) = split('\t');
      last;
    }
  }
#  if($domain eq "actmerchant.com") {
#    $paydomain = "www.actmerchant.com";
#  }
  if($domain eq "pay-gate.com") {
    $paydomain = "www.pay-gate.com";
  }
  elsif($domain eq "icommercegateway.com") {
    $paydomain = "www.icommercegateway.com";
  }
  elsif($domain eq "frontlinestore.com") {
    $paydomain = "pay.frontlinestore.net";
  }
  else {
    $paydomain = "pay1.plugnpay.com";
    $domain = "plugnpay.com";
  }
  close(DOMAINS);

  if (($client ne "javascript") && ($function ne "empty")) {
    @item_names = $query->cookie;
    #$item_count = scalar(@item_names);
    #%item = ();
    foreach my $var (@item_names) {
      $tst = substr($var,0,6);
      if ($tst eq "ezcrt_") {
        $var = substr($var,6);
        my $tmp = &URLDecode("$var");
        $item{$var} = $query->cookie("ezcrt_$tmp"); # was $var
      }
    }
  }
  elsif (($client eq "javascript") && ($function ne "empty")) {
    $qstring = $ENV{'QUERY_STRING'};
    (@smallstr) = split(/\&/,$qstring);
    foreach my $var (@smallstr) {
      ($name,$value) = split(/=/,$var);
      $item{$name} = $value;
    }
  }

  if (($username eq $debugusername) && ($debug eq "yes")) {
    print "EXST COOKIES<br>\n";
    foreach my $key (sort keys %item) {
      print "$key=$item{$key}:<br>\n";
    }
  }

  if ($ENV{'REMOTE_ADDR'} =~ /^192\.223\.243/) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    my $path_debug = "$path_easycart_txt/../database/debug.txt";
    open(DEBUG,">>$path_debug");
    print DEBUG "DATE:$now, IP:$ENV{'REMOTE_ADDR'} SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$$, ";
    my @item_names = $query->param;
    foreach my $var (@item_names) {
      my $value = &CGI::escapeHTML($query->param("$var"));
      print DEBUG "$var:$value, ";
    }
    print DEBUG "\n";
    close(DEBUG);
  }

  return [], $type;
}

sub checkout {
  &process_prices;

  $item_count = 0;
  foreach my $key (keys %item) {
#    print "KEY:$key:$item{$key}<br>\n";
    if (($key =~ /\|/) && ($legacy_cookie ne "yes")) {
      ($itemname,$descra,$descrb,$descrc) = split(/\|/,$key);
    }
    else {
      ($itemname,$descra,$descrb,$descrc) = split(/ /,$key);
    }
    if (($item_price{"$itemname"} > 0) && ($item{"$key"} > 0)) {
      $item_count++;
    }
  }

  print "Content-type: text/html\n\n";
#  print "IC:$item_count";

  $username  =~ s/\W//g;
  if (($item_count == 0) && (-e "$path_easycart_txt/$username/emptycart.html")) {
    $template = "$path_easycart_txt/$username/emptycart.html";
  }
  else {
    $template = "$path_easycart_txt/$username/checkout.html";
  }
  open(TEMPLATEFILE,"$template");
  while (<TEMPLATEFILE>) {
    if ($_ =~ /\[table\]/) {
      last;
    }
    if (($_ =~ /\[continue\]/i) && ($continue ne "")) {
      s/\[continue\]/$continue/g;
    }
    if (($_ =~ /\[refsite\]/i) && ($refsite ne "")) {
      s/\[refsite\]/$refsite/g;
    }
    if (($_ =~ /\[order-id\]/i)) {
      s/\[order-id\]/$order_id/g;
    }
    if ($_ =~ /\[message\]/i) {
      s/\[message\]/$message/g;
    }

    print $_;
  }

  if ($item_count == 0) {
    print "<h3>Your shopping cart is empty<br>Either you have not ordered anything or you have \"Cookies\" turned off for your browser.</h3><br>";
  }
  else {
    if ($ENV{'SERVER_PORT'} == 80) {
      print "<form name=\"checkout\" method=\"post\" action=\"http://$ENV{'SERVER_NAME'}$ENV{'SCRIPT_NAME'}\">\n"; 
    }
    else {
      print "<form name=\"checkout\" method=\"post\" action=\"https://$ENV{'SERVER_NAME'}$ENV{'SCRIPT_NAME'}\">\n";
    }
    if ($allow_modify ne "no") {
      print "<input type=\"hidden\" name=\"function\" value=\"modify\">\n";
    }
    else {
      print "<input type=\"hidden\" name=\"function\" value=\"delete\">\"";
    }
    print "<input type=\"hidden\" name=\"username\" value=\"$username\">\n";
    print "<input type=\"hidden\" name=\"continue\" value=\"$continue\">\n";
    print "<input type=\"hidden\" name=\"refsite\" value=\"$refsite\">\n";
    print "<input type=\"hidden\" name=\"language\" value=\"$language\">\n";
    print "<input type=\"hidden\" name=\"acct_code\" value=\"$acctcode\">\n";
    #print "<input type=\"hidden\" name=\"test_wgt\" value=\"$testwgt\">\n";
    if ($order_id =~ /\w/) {
      print "<input type=\"hidden\" name=\"order-id\" value=\"$order_id\">\n";
    }
    print "<input type=\"hidden\" name=\"currency_symbol\" value=\"$currency_symbol\">\n";
    if ($ec_version >= 2) {
      print "<input type=\"hidden\" name=\"ec_version\" value=\"$ec_version\">\n";
    }
    print "<table border=0>\n";
    print "  <tr bgcolor=\"#000000\">";
    if ($showskus eq "yes") {
      print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Model \#</font></th>\n";
    }
    print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Description</font></th>\n";
    print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Price</font></th>\n";
    print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Qty</font></th>\n";
    print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Amount</font></th>\n";
    print "    <th class=\"itemscolor\">&nbsp;</th>\n";
    print "  </tr>\n";

    my $i = 1;
    foreach my $key (sort keys %item) {
      if (($key =~ /\|/) && ($legacy_cookie ne "yes")) {
        ($itemname,$descra,$descrb,$descrc) = split(/\|/,$key);
      }
      else {
        ($itemname,$descra,$descrb,$descrc) = split(/ /,$key);
      }

      if (($username eq $debugusername) && ($debug eq "yes")) {
        print ":$key:$item{$key}:$itemname:$item_price{$itemname}:<br>\n";
      }
      if (($item_price{"$itemname"} > 0) && ($item{"$key"} > 0)) {
        $subsubtotal = $item{"$key"} * $item_price{"$itemname"};
        $subtotal = $subtotal + $subsubtotal;

        print "  <tr>\n";
        if ($showskus eq "yes") {
          print "    <td class=\"itemrows\" align=\"center\"><font face=\"arial\">$itemname</font></td>\n";
        }

        # Was: printf("    <td class=\"itemrows\"><font face=\"arial\">%s %s %s %s</font></td>\n", $item_descr{"$itemname"}, $descra, $descrb, $descrc);
        printf("    <td class=\"itemrows\"><font face=\"arial\">%s", $item_descr{"$itemname"});
        if ($descra ne "") {
          printf(", %s", $descra);
        }
        if ($descrb ne "") {
          printf(", %s", $descrb);
        }
        if ($descrc ne "") {
          printf(", %s", $descrc);
        }
        print "</font></td>\n";

        printf("    <td class=\"itemrows\" align=\"center\"><font face=\"arial\">$currency_symbol%.2f</font></td>\n", $item_price{"$itemname"});
        print "    <td class=\"itemrows\" align=\"center\"><input type=\"hidden\" name=\"item$i\" value=\"$itemname\">\n"; # ** SEE IMPORTANT NOTE BELOW:
        # VERY IMPORTANT NOTE: DO NOT CHANGE the above itemX value of '$itemname' TO '$key' (to apply product attributes to the item SKU).
        #                      Doing so will mess up SKU based matching features in many PnP services (such as in Email Management & Coupon Management)
        #                      Any problems with this please consult James <turajb@plugnpay.com> - 07/31/03
        print "<input type=\"hidden\" name=\"descra$i\" value=\"$descra\">\n";
        print "<input type=\"hidden\" name=\"descrb$i\" value=\"$descrb\">\n";
        print "<input type=\"hidden\" name=\"descrc$i\" value=\"$descrc\">\n";
        # Note: seperate description fields required for modify quantity feature.

        if ($allow_modify ne "no") {
          if (($allow_decimal_qty == 1) && ($item{$key} =~ /\./)) {
            printf("<input type=\"text\" name=\"quantity$i\" value=\"%.2f\" size=\"3\" maxlength=\"3\"></td>\n", $item{"$key"});
          }
          else {
            printf("<input type=\"text\" name=\"quantity$i\" value=\"%d\" size=\"3\" maxlength=\"3\"></td>\n", $item{"$key"});
          }
          printf("    <td class=\"itemrows\" align=\"right\"><font face=\"arial\">$currency_symbol%.2f</font></td>\n", $subsubtotal);
          printf("    <td class=\"itemrows\"><font face=\"arial\"><input type=submit name=\"%s\" value=\"Modify Qty\"></font></td>\n", $key);
          print "  </tr>\n";
        }
        else {
          if ($item{$key} =~ /\./) {
            printf("<font face=\"aria\">%.2f</font></td>", $item{"$key"});
          }
          else {
            printf("<font face=\"aria\">%.0f</font></td>", $item{"$key"});
          }
          printf("    <td class=\"itemrows\" align=\"right\"><font face=\"arial\">$currency_symbol%.2f</font><input type=\"hidden\" name=\"quantity$i\" value=\"$item{$key}\"></td>\n", $subsubtotal);
          printf("    <td class=\"itemrows\"><font face=\"arial\"><input type=submit name=\"%s\" value=\"Remove\"></font></td>\n", $key);
          print "</tr>\n"; 
        }
        #printf("    <td class=\"itemrows\" align=\"right\"><font face=\"arial\" size=1>$currency_symbol%.2f</font></td>\n", $subsubtotal);
        #printf("    <td class=\"itemrows\"><font face=\"arial\" size=1><input type=\"submit\" name=\"%s\" value=\"Modify Qty\"></font></td>\n", $key);
        $i++;
        if ($shippingtype eq "item") {
          $shipping = $shipping + ($item_shipping{"$itemname"} * $item{"$key"});
        }
      }
    }

    my $colspan = 3;
    if ($showskus eq "yes") { $colspan = 4; }

    print "  <tr bgcolor=\"#C0C0C0\">\n";
    print "    <th align=\"left\" colspan=$colspan class=\"subdesc\"><font face=\"arial\">SUBTOTAL</font></th>\n";
    printf("    <td align=\"right\" class=\"subamt\"><font face=\"arial\">$currency_symbol%.2f</font></td>\n", $subtotal);
    print "  </tr>\n";

    $total = $subtotal + $shipping;

    print "</table>\n";
    if ($taxshipline ne "no") {
      print "<font face=\"arial\" size=1 id=\"taxship\">Tax and shipping are calculated upon checkout if applicable.</font>\n";
    }
    print "</form>\n";
  }

  if ($ss_version == 2) {
    ######## Start Smart Screens v2 checkout form here
    print "<form name=\"payment\" method=\"post\" action=\"https://$paydomain/pay/\" target=\"$target\">\n";
    #print "<input type=\"hidden\" name=\"function\" value=\"final\">\n";
    print "<input type=\"hidden\" name=\"pt_client_identifier\" value=\"easycart\">\n";
    #print "<input type=\"hidden\" name=\"continue\" value=\"$continue\">\n";
    if ($order_id =~ /\w/) {
      print "<input type=\"hidden\" name=\"pt_order_classifier\" value=\"$order_id\">\n";
    }
    print "<input type=\"hidden\" name=\"pt_account_code_1\" value=\"$acctcode\">\n";
    #print "<input type=\"hidden\" name=\"currency_symbol\" value=\"$currency_symbol\">\n";

    my $c = 1; # maintains counter for customname, customvalue fields
    if ($bar_custfields ne "yes") {
      print "<input type=\"hidden\" name=\"pt_custom_name_$c\" value=\"cart_hdr\">\n";
      print "<input type=\"hidden\" name=\"pt_custom_value_$c\" value=\"$cart_hdr\">\n";
      $c++;

      print "<input type=\"hidden\" name=\"pt_custom_name_$c\" value=\"ec_version\">\n";
      print "<input type=\"hidden\" name=\"pt_custom_value_$c\" value=\"$ec_version\">\n";
      $c++;

      print "<input type=\"hidden\" name=\"pt_custom_name_$c\" value=\"language\">\n";
      print "<input type=\"hidden\" name=\"pt_custom_value_$c\" value=\"$language\">\n";
      $c++;

      print "<input type=\"hidden\" name=\"pt_custom_name_$c\" value=\"refsite\">\n";
      print "<input type=\"hidden\" name=\"pt_custom_value_$c\" value=\"$refsite\">\n";
      $c++;
    }

    my $i = 1;
    foreach my $key (sort keys %item) {
      if (($key =~ /\|/) && ($legacy_cookie ne "yes")) {
        ($itemname,$descra,$descrb,$descrc) = split(/\|/,$key);
      }
      else {
        ($itemname,$descra,$descrb,$descrc) = split(/ /,$key);
      }

      if (($item_price{"$itemname"} > 0) && ($item{"$key"} > 0)) {
        printf("<input type=\"hidden\" name=\"pt_item_identifier_$i\" value=\"%s\">\n", $itemname);
        if ($allow_decimal_qty == 1) {
          printf("<input type=\"hidden\" name=\"pt_item_quantity_$i\" value=\"%.2f\">\n", $item{"$key"});
        }
        else{
          printf("<input type=\"hidden\" name=\"pt_item_quantity_$i\" value=\"%d\">\n", $item{"$key"});
        }
        printf("<input type=\"hidden\" name=\"pt_item_cost_$i\" value=\"%s\">\n", $item_price{"$itemname"});

        # Was: printf("<input type=\"hidden\" name=\"pt_item_description_$i\" value=\"%s %s %s %s\">\n", $item_descr{"$itemname"}, $descra, $descrb, $descrc);
        printf("<input type=\"hidden\" name=\"pt_item_description_$i\" value=\"%s", $item_descr{"$itemname"});
        if ($descra ne "") {
          printf(", %s", $descra);
        }
        if ($descrb ne "") {
          printf(", %s", $descrb);
        }
        if ($descrc ne "") {
          printf(", %s", $descrc);
        }
        print "\">\n";

        $extra = $itemname;
        foreach my $ky1 (keys %$extra) {
          if ($ky1 =~ /^(supplieremail)$/) {
            # itemize the column, because its used by smart screens.
            print "<input type=\"hidden\" name=\"$ky1$i\" value=\"$$extra{$ky1}\">\n";
          }
          elsif ($ky1 =~ /^(taxable)$/) {
            # itemize the column, because its used by smart screens.
            print "<input type=\"hidden\" name=\"pt_item_is_taxable_$i\" value=\"$$extra{$ky1}\">\n";
          }
          elsif ($ky1 =~ /^(weight)$/) {
            # itemize the column, because its used by smart screens.
            print "<input type=\"hidden\" name=\"$ky1$i\" value=\"$$extra{$ky1}\">\n";
          }
          else {
            # force all other columns as customnames/customvalues fields.  Necessary for backwards compatibility, should that data be needed at the success-link URL.
            if ($bar_custfields ne "yes") {
              print "<input type=\"hidden\" name=\"pt_custom_name_$c\" value=\"$ky1$i\">\n";
              print "<input type=\"hidden\" name=\"pt_custom_value_$c\" value=\"$$extra{$ky1}\">\n";
              $c++;
            }
          }
          if (($ky1 eq "plan") && ($$extra{$ky1} ne "")) {
            $roption = "<input type=\"hidden\" name=\"roption\" value=\"$i\">\n";
          }

          # pre-calculate weight total for select merchants
          if (($ky1 eq "weight") && ($username =~ /^(detailed|detailedpr)$/)) {
            $testwgt = $testwgt + ($item{"$key"} * $$extra{$ky1});
          }
        }
        $i++;
      }
    }
    print "<input type=\"hidden\" name=\"test_wgt\" value=\"$testwgt\">\n";

    print "<input type=\"hidden\" name=\"pt_subtotal\" value=\"$subtotal\">\n";
    print "<input type=\"hidden\" name=\"pt_shipping_amount\" value=\"$shipping\">\n";
    if ($taxrate ne "") {
      $taxrate =~ s/\,/\|/g;
      print "<input type=\"hidden\" name=\"pt_tax_rates\" value=\"$taxrate\">\n";
    }
    if ($taxstate ne "") {
      $taxstate =~ s/\|/\,/g;
      print "<input type=\"hidden\" name=\"taxstate\" value=\"$taxstate\">\n";
    }
    print "<input type=\"hidden\" name=\"pt_transaction_amount\" value=\"$total\">\n";
    print $roption;
    ######## End Smart Screens v2 checkout form here
  }
  else {
    ######## Start Smart Screens v1 checkout form here
    if ($ec_version >= 2) {
      print "<form name=\"payment\" method=\"post\" action=\"https://$paydomain/payment/pay.cgi\" target=\"$target\">\n"; 
    }
    else {
      print "<form name=\"payment\" method=\"post\" action=\"https://$paydomain/payment/" . $username . "pay.cgi\" target=\"$target\">\n";
    }
    #print "<input type=\"hidden\" name=\"function\" value=\"final\">\n";
    print "<input type=\"hidden\" name=\"client\" value=\"easycart\">\n";
    #print "<input type=\"hidden\" name=\"continue\" value=\"$continue\">\n";
    if ($order_id =~ /\w/) {
      print "<input type=\"hidden\" name=\"order-id\" value=\"$order_id\">\n";
    }
    print "<input type=\"hidden\" name=\"acct_code\" value=\"$acctcode\">\n";
    print "<input type=\"hidden\" name=\"currency_symbol\" value=\"$currency_symbol\">\n";

    my $c = 1; # maintains counter for customname, customvalue fields
    if ($bar_custfields ne "yes") {
      print "<input type=\"hidden\" name=\"customname$c\" value=\"cart_hdr\">\n";
      print "<input type=\"hidden\" name=\"customvalue$c\" value=\"$cart_hdr\">\n";
      $c++;

      print "<input type=\"hidden\" name=\"customname$c\" value=\"ec_version\">\n"; 
      print "<input type=\"hidden\" name=\"customvalue$c\" value=\"$ec_version\">\n";
      $c++;

      print "<input type=\"hidden\" name=\"customname$c\" value=\"language\">\n"; 
      print "<input type=\"hidden\" name=\"customvalue$c\" value=\"$language\">\n";
      $c++;

      print "<input type=\"hidden\" name=\"customname$c\" value=\"refsite\">\n"; 
      print "<input type=\"hidden\" name=\"customvalue$c\" value=\"$refsite\">\n";
      $c++;
    }

    my $i = 1;
    foreach my $key (sort keys %item) {
      if (($key =~ /\|/) && ($legacy_cookie ne "yes")) {
        ($itemname,$descra,$descrb,$descrc) = split(/\|/,$key);
      }
      else {
        ($itemname,$descra,$descrb,$descrc) = split(/ /,$key);
      }

      if (($item_price{"$itemname"} > 0) && ($item{"$key"} > 0)) {
        printf("<input type=\"hidden\" name=\"item$i\" value=\"%s\">\n", $itemname);
        if ($allow_decimal_qty == 1) {
          printf("<input type=\"hidden\" name=\"quantity$i\" value=\"%.2f\">\n", $item{"$key"});
        }
        else{
          printf("<input type=\"hidden\" name=\"quantity$i\" value=\"%d\">\n", $item{"$key"});
        }
        printf("<input type=\"hidden\" name=\"cost$i\" value=\"%s\">\n", $item_price{"$itemname"});

        # Was: printf("<input type=\"hidden\" name=\"description$i\" value=\"%s %s %s %s\">\n", $item_descr{"$itemname"}, $descra, $descrb, $descrc);
        printf("<input type=\"hidden\" name=\"description$i\" value=\"%s", $item_descr{"$itemname"});
        if ($descra ne "") {
          printf(", %s", $descra);
        }
        if ($descrb ne "") {
          printf(", %s", $descrb);
        }
        if ($descrc ne "") {
          printf(", %s", $descrc);
        }
        print "\">\n";

        $extra = $itemname;
        foreach my $ky1 (keys %$extra) {
          if ($ky1 =~ /^(supplieremail|taxable|weight)$/) {
            # itemize these columns, because they are used by smart screens.
            print "<input type=\"hidden\" name=\"$ky1$i\" value=\"$$extra{$ky1}\">\n";
          }
          else {
            # force all other columns as customnames/customvalues fields.  Necessary for backwards compatibility, should that data be needed at the success-link URL.
            if ($bar_custfields ne "yes") {
              print "<input type=\"hidden\" name=\"customname$c\" value=\"$ky1$i\">\n";
              print "<input type=\"hidden\" name=\"customvalue$c\" value=\"$$extra{$ky1}\">\n";
              $c++;
            }
          }
          if (($ky1 eq "plan") && ($$extra{$ky1} ne "")) {
            $roption = "<input type=\"hidden\" name=\"roption\" value=\"$i\">\n";
          }

          # pre-calculate weight total for select merchants
          if (($ky1 eq "weight") && ($username =~ /^(detailed|detailedpr)$/)) {
            $testwgt = $testwgt + ($item{"$key"} * $$extra{$ky1});
          }
        }
        $i++;
      }
    }
    print "<input type=\"hidden\" name=\"test_wgt\" value=\"$testwgt\">\n";

    print "<input type=\"hidden\" name=\"subtotal\" value=\"$subtotal\">\n";
    print "<input type=\"hidden\" name=\"shipping\" value=\"$shipping\">\n";
    # added by drew 04/04/2002
    if ($taxrate ne "") {
      print "<input type=\"hidden\" name=\"taxrate\" value=\"$taxrate\">\n";
    }
    if ($taxstate ne "") {
      print "<input type=\"hidden\" name=\"taxstate\" value=\"$taxstate\">\n";
    }
    print "<input type=\"hidden\" name=\"card\-amount\" value=\"$total\">\n";
    print $roption;
    ######## Start Smart Screens v1 checkout form here
  }

  while (<TEMPLATEFILE>) {
    if (($_ =~ /\[continue\]/i) && ($continue ne "")) {
      s/\[continue\]/$continue/g;
    }
    if (($_ =~ /\[refsite\]/i) && ($refsite ne "")) {
      s/\[refsite\]/$refsite/g;
    }
    if (($_ =~ /\[order-id\]/i)) {
      s/\[order-id\]/$order_id/g;
    }
    if ($_ =~ /\[message\]/i) {
      s/\[message\]/$message/g;
    }
    print $_;
  }
  close(TEMPLATEFILE);
}

sub empty {
  @item_array = $query->cookie(/ezcrt_/);	# xxxx
  $item_count = scalar(@item_array);

  foreach my $var (sort @item_array) {
    my $tmp = &URLEncode("$var");
    printf("Set-Cookie: %s=0; path=/; expires=Wednesday, 01-Jan-97 23:00:00 GMT; domain=.$domain\n", $tmp); # was $var
    $item{$var} = 0;
  }

  $emptymessage = "<h3>Your shopping cart is empty<br></h3><br>";
  # print "Content-type: text/html\n\n";

  $username  =~ s/\W//g;
  if (-e "$path_easycart_txt/$username/emptycart.html") {
    $template = "$path_easycart_txt/$username/emptycart.html";
  }
  elsif (-e "$path_easycart_txt/$username/view_cart.html") {
    $template = "$path_easycart_txt/$username/view_cart.html";
  }
  if ($template ne "") {
    print "Content-type: text/html\n\n";
    open(TEMPLATEFILE,"$template");
    while (<TEMPLATEFILE>) {
      if ($_ =~ /\[table\]/i) {
        s/\[table\]/$emptymessage/;
      }
      if (($_ =~ /\[continue\]/i) && ($continue ne "")) {
        s/\[continue\]/$continue/g;
      }
      if (($_ =~ /\[refsite\]/i) && ($refsite ne "")) {
        s/\[refsite\]/$refsite/g;
      }
      if (($_ =~ /\[order-id\]/i)) {
        s/\[order-id\]/$order_id/g;
      }
      if ($_ =~ /\[message\]/i) {
        s/\[message\]/$message/g;
      }
      print $_;
    }
    close(TEMPLATEFILE);
  }
  else {
    #&view_cart();
    &checkout();
  }
}

sub thankyou {
  # Note: This function should not be required; as MCKUTILS will automatically delete cookies after a successful purchase
  #       Also note the 'end-link' field will be removed from the query string on a transition page success,
  #        but will remain under the POST success process. 
  if ($username eq "") {
    $username = &CGI::escapeHTML($query->param('publisher-name'));
  }

  @item_array = $query->cookie(/item/); # xxxx
  $item_count = scalar(@item_array);

  foreach my $var (sort @item_array) {
    my $tmp = &URLEncode("$var");
    printf("Set-Cookie: ezcrt_%s=0; path=/; expires=Wednesday, 01-Jan-97 23:00:00 GMT; domain=.$domain\n", $tmp); # was $var
  }

  print "Location: " . $url . "\n\n";
  exit;

  print "Content-type: text/html\n\n";
  print "<html>\n";
  print "<head>\n";
  print "<title>Clear Cart</title>\n";
  print "<META http-equiv=\"refresh\" content=\"5\; URL=$url\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<font size=+1>\n";
  print "Thank You for your order. Your shopping cart has been emptied.\n";
  print "</font>\n";
  print "<p>\n";
  print "</body>\n";
  print "</html>\n";
  exit;
}

sub add {
  @item_names = $query->param;
  $item_count = scalar(@item_array);
  foreach my $var (@item_names) {
    if ($var =~ /^item/) {
      $item_index = substr($var,4);
      $name = &CGI::escapeHTML($query->param("$var"));

      $da = &CGI::escapeHTML($query->param("descra$item_index"));
      $db = &CGI::escapeHTML($query->param("descrb$item_index"));
      $dc = &CGI::escapeHTML($query->param("descrc$item_index"));

      if ($legacy_cookie eq "yes") {
        # use space delimited cookie format
        if ($da ne "") {
          $name = "$name $da";
        }
        if ($db ne "") {
          $name = "$name $db";
        }
        if ($dc ne "") {
          $name = "$name $dc";
        }
      }
      else {
        # use pipe delimited cookie format
        if ($da ne "") {
          $name = "$name\|$da";
        }
        if ($db ne "") {
          $name = "$name\|$db";
        }
        if ($dc ne "") {
          $name = "$name\|$dc";
        }
      }
      $newitem{"$name"} = &CGI::escapeHTML($query->param("quantity$item_index"));
    }
  }

  if ($checkstock eq "yes") {
    &process_prices();
  }

  foreach my $key (sort keys %newitem) {
    # check for & change quantity to 0 when item is not instock 
    if (($$key{'Instock'} =~ /no/i) && ($newitem{"$key"} > 0)) {
      #$message = "Sorry, this item is currently out of stock.<br>";
      $message .= "<font face=\"arial\" size=2>Sorry, item \'$item_descr{$key}\' is currently out of stock.</font><br>";
      $newitem{$key} = 0;
      $outstock_count++;
    }
    elsif ($newitem{$key} > 0) {
      $instock_count++;
    }

    # set expiration time
    my $expires = gmtime(time()+48*3600);

    if ($allow_decimal_qty == 1) {
      # set cookie with decimal quantity
      if ($newitem{"$key"} > 0) {
        my $tmp = &URLEncode("$key");
        print "Set-Cookie: ezcrt_$tmp"; # was $key
        #printf("=%d; path=/; expires=$expires; domain=.$domain\n", $newitem{"$key"});
        printf("=%.2f; path=/; domain=.$domain\n", $newitem{"$key"});
        $item{$key} = $newitem{$key};
      }
    }
    else {
      # set cookie with whole number quantity
      if ($newitem{"$key"} > 0) {
        my $tmp = &URLEncode("$key");
        print "Set-Cookie: ezcrt_$tmp"; # was $key
        #printf("=%d; path=/; expires=$expires; domain=.$domain\n", $newitem{"$key"});
        printf("=%d; path=/; domain=.$domain\n", $newitem{"$key"});
        $item{$key} = $newitem{$key};
      }
    }
    if ($ezc_shipping ne "") {
      print "Set-Cookie: ezc_shipping";
      printf("=%.2f; path=/; domain=.$domain\n", $ezc_shipping);
    }
  }
  if (($username eq $debugusername) && ($debug eq "yes")) {
    print "NEW COOKIES:$domain<br>\n";
    foreach my $key (sort keys %newitem) {
      print "$key=$newitem{$key}:<br>\n";
    }
  }
  #%item = (%item,%newitem);
  if (($username eq $debugusername) && ($debug eq "yes")) {
    print "NEW ITEMS<br>\n";
    foreach my $key (sort keys %item) {
      print "$key=$item{$key}:<br>\n";
    }
  }
  #print "Content-type: text/html\n\n";

  if (($username eq $debugusername) && ($debug eq "yes")) {         
    print "instock count: $instock_count<br>\n";
    print "outstock_count: $outstock_count<br>\n";
  }

  $username  =~ s/\W//g;
  if (($outstock_count >= 1) && ($instock_count <= 0) && (-e "$path_easycart_txt/$username/nostock.html")) {
    print "Content-type: text/html\n\n";
    open(TEMPLATEFILE,"$path_easycart_txt/$username/nostock.html");
    while (<TEMPLATEFILE>) {
      if (($_ =~ /\[continue\]/i) && ($continue ne "")) {
        s/\[continue\]/$continue/g;
      }
      if (($_ =~ /\[refsite\]/i) && ($refsite ne "")) {
        s/\[refsite\]/$refsite/g;
      }
      if (($_ =~ /\[order-id\]/i)) {
        s/\[order-id\]/$order_id/g;
      }
      if ($_ =~ /\[message\]/i) {
        s/\[message\]/$message/g;
      }
      print $_;
    }
    close(TEMPLATEFILE);
  }
  elsif (-e "$path_easycart_txt/$username/add.html") {
    print "Content-type: text/html\n\n";
    open(TEMPLATEFILE,"$path_easycart_txt/$username/add.html");
    while (<TEMPLATEFILE>) {
      if (($_ =~ /\[continue\]/i) && ($continue ne "")) {
        s/\[continue\]/$continue/g;
      }
      if (($_ =~ /\[refsite\]/i) && ($refsite ne "")) {
        s/\[refsite\]/$refsite/g;
      }
      if (($_ =~ /\[order-id\]/i)) {
        s/\[order-id\]/$order_id/g;
      }
      if ($_ =~ /\[message\]/i) {
        s/\[message\]/$message/g;
      }
      print $_;
    }
    close(TEMPLATEFILE);
  }
  else {
    &checkout();
  }
  exit;
}

sub modify {
  @item_names = $query->param;
  $item_count = scalar(@item_array);
  foreach my $var (@item_names) {
    $name = &CGI::escapeHTML($query->param("$var"));
    if ($var =~ /^item/) {
      $item_index = substr($var,4);
      #$name = &CGI::escapeHTML($query->param("$var"));

      $da = &CGI::escapeHTML($query->param("descra$item_index"));
      $db = &CGI::escapeHTML($query->param("descrb$item_index"));
      $dc = &CGI::escapeHTML($query->param("descrc$item_index"));

      if ($legacy_cookie eq "yes") {
        # use space delimited cookie format
        if ($da ne "") {
          $name = "$name $da";
        }
        if ($db ne "") {
          $name = "$name $db";
        }
        if ($dc ne "") {
          $name = "$name $dc";
        }
      }
      else{
        # use pipe delimitied cookie format
        if ($da ne "") {
          $name = "$name\|$da";
        }
        if ($db ne "") {
          $name = "$name\|$db";
        }
        if ($dc ne "") {
          $name = "$name\|$dc";
        }
      }
      $newitem{"$name"} = &CGI::escapeHTML($query->param("quantity$item_index"));

    }
    if ($name =~ /remove/i) {
      $delete_item{$var} = 1;
    }
  }
  foreach my $key (keys %delete_item) {
    $newitem{$key} = 0;
  }
  foreach my $key (sort keys %newitem) {
    my $expires = gmtime(time()+48*3600);
    if ($newitem{"$key"} == 0) {
      print "Set-Cookie: ezcrt_";
      my $tmp = &URLEncode("$key");
      printf("%s=0; path=/; expires=Wednesday, 01-Jan-97 23:00:00 GMT; domain=.$domain\n", $tmp); # was $key
    }
    elsif ($newitem{"$key"} > 0) {
      if ($allow_decimal_qty == 1) {
        if ($newitem{"$key"} > 0) {
          my $tmp = &URLEncode("$key");
          print "Set-Cookie: ezcrt_$tmp"; # was $key
          printf("=%.2f; path=/; domain=.$domain\n", $newitem{"$key"});
        }
      }
      else {
        if ($newitem{"$key"} > 0) {
          my $tmp = &URLEncode("$key");
          print "Set-Cookie: ezcrt_$tmp"; # was $key
          printf("=%d; path=/; domain=.$domain\n", $newitem{"$key"});
        }
      }
      #my $tmp = &URLEncode("$key");
      #print "Set-Cookie: ezcrt_$tmp"; # was $key
      #printf("=%d; path=/; domain=.$domain\n", $newitem{"$key"});
    }
  }

  %item = (%item,%newitem);

  $username  =~ s/\W//g;
  if (-e "$path_easycart_txt/$username/add.html") {
    print "Content-type: text/html\n\n";
    open(TEMPLATEFILE,"$path_easycart_txt/$username/add.html");
    while (<TEMPLATEFILE>) {
      if (($_ =~ /\[continue\]/i) && ($continue ne "")) {
        s/\[continue\]/$continue/g;
      }
      if (($_ =~ /\[refsite\]/i) && ($refsite ne "")) {
        s/\[refsite\]/$refsite/g;
      }
      if (($_ =~ /\[order-id\]/i)) {
        s/\[order-id\]/$order_id/g;
      }
      if ($_ =~ /\[message\]/i) {
        s/\[message\]/$message/g;
      }
      print $_;
    }
    close(TEMPLATEFILE);
  }
  else {
    &checkout();
  }
  exit;
}

sub delete {
  @item_names = $query->param;
  my $expires = gmtime(time()-1*3600);
  foreach my $var (@item_names) {
    if (($var ne "function") && ($var ne "username") && ($var ne "continue") && ($var ne "order-id")) {
      my $tmp = &URLEncode("$var");
      printf("Set-Cookie: ezcrt_%s=0; path=/; expires=Wednesday, 01-Jan-97 23:00:00 GMT; domain=.$domain\n", $tmp); # was $var
      delete $item{"ezcrt_$var"};
      last;
    }
  }

  #&view_cart();
  &checkout();
  exit;
}

sub view_cart {
  print "Content-type: text/html\n\n";

  &process_prices;

  $username  =~ s/\W//g;
  open(TEMPLATEFILE,"$path_easycart_txt/$username/view_cart.html");
  while (<TEMPLATEFILE>) {
    if ($_ =~ /\[table\]/) {
      last;
    }
    if (($_ =~ /\[continue\]/i) && ($continue ne "")) {
      s/\[continue\]/$continue/g;
    }
    if (($_ =~ /\[refsite\]/i) && ($refsite ne "")) {
      s/\[refsite\]/$refsite/g;
    }
    if (($_ =~ /\[order-id\]/i)) {
      s/\[order-id\]/$order_id/g;
    }
    if (($_ =~ /\[message\]/i)) {
      s/\[message\]/$message/g;
    }
    print $_;
  }
  @item_names = $query->cookie;
  $item_count = scalar(@item_names);
  foreach my $var (@item_names) {
    $tst = substr($var,0,6);
    if ($tst eq "ezcrt_") {
      $var = substr($var,6);
      $item{$var} = $query->cookie("ezcrt_$var");
    }
  }

  if ($item_count == 0) {
    print "<h3>Your shopping cart is empty<br>Either you have not ordered anything or you have \"Cookies\" turned off for your browser.</h3><br>";
  }
  else {
    if ($ENV{'SERVER_PORT'} == 80) {
      print "<form method=\"post\" action=\"http://$ENV{'SERVER_NAME'}$ENV{'SCRIPT_NAME'}\">\n"; 
    }
    else {
      print "<form method=\"post\" action=\"https://$ENV{'SERVER_NAME'}$ENV{'SCRIPT_NAME'}\">\n";
    }
    print "<input type=\"hidden\" name=\"function\" value=\"modify\">\n";
    print "<input type=\"hidden\" name=\"username\" value=\"$username\">\n";
    print "<input type=\"hidden\" name=\"continue\" value=\"$continue\">\n";
    # added by carol 10/02/2003 for sonny
    print "<input type=\"hidden\" name=\"refsite\" value=\"$refsite\">\n";
    print "<input type=\"hidden\" name=\"language\" value=\"$language\">\n";
    print "<input type=\"hidden\" name=\"acct_code\" value=\"$acctcode\">\n";
    print "<input type=\"hidden\" name=\"test_wgt\" value=\"$testwgt\">\n";
    print "<input type=\"hidden\" name=\"currency_symbol\" value=\"$currency_symbol\">\n";
    if ($order_id =~ /\w/) { 
      print "<input type=\"hidden\" name=\"order-id\" value=\"$order_id\">\n";
    }

    print "<table border=0>\n";
    print "  <tr bgcolor=\"#000000\">";
    if ($showskus eq "yes") {
      print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Model \#</font></th>\n";
    }
    print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Description</font></th>\n";
    print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Price</font></th>\n";
    print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Qty</font></th>\n";
    print "    <th class=\"itemscolor\"><font color=\"#ffffff\" face=\"arial\">Amount</font></th>\n";
    print "    <th class=\"itemscolor\">&nbsp;</th>\n";
    print "  </tr>\n";

    foreach my $key (keys %item) {
      if (($key =~ /\|/) && ($legacy_cookie ne "yes")) {
        ($itemname,$descra,$descrb,$descrc) = split(/\|/,$key);
      }
      else {
        ($itemname,$descra,$descrb,$descrc) = split(/ /,$key);
      }

      if (($item_price{"$itemname"} > 0) && ($item{"$key"} > 0)) {
        $subsubtotal = $item{"$key"} * $item_price{"$itemname"};
        $subtotal = $subtotal + $subsubtotal;

        print "  <tr>\n";
        if ($showskus eq "yes") {
          print "    <td class=\"itemrows\"><font face=\"arial\">$itemname</font></td>\n";
        }

        # Was: printf("    <td><font face=\"arial\">%s %s %s %s</font></td>\n", $item_descr{"$itemname"}, $descra, $descrb, $descrc);
        printf("    <td class=\"itemrows\"><font faceface=\"arial\">%s", $item_descr{"$itemname"});
        if ($descra ne "") {
          printf(", %s", $descra);
        }
        if ($descrb ne "") {
          printf(", %s", $descrb);
        }
        if ($descrc ne "") {
          printf(", %s", $descrc);
        }
        print "</font></td>\n";

        printf("    <td class=\"itemrows\"><font faceface=\"arial\">$currency_symbol%.2f</font></td>\n", $item_price{"$itemname"});
        if ($item{$key} =~ /\./) {
          printf("    <td class=\"itemrows\"><font faceface=\"arial\">%.2f</font></td>\n", $item{"$key"});
        }
        else {
          printf("    <td class=\"itemrows\"><font faceface=\"arial\">%.0f</font></td>\n", $item{"$key"});
        }         
        printf("    <td class=\"itemrows\" align=\"right\"><font faceface=\"arial\">$currency_symbol%.2f</font></td>\n", $subsubtotal);
        printf("    <td class=\"itemrows\"><font faceface=\"arial\"><input type=submit name=\"%s\" value=\"Remove Item\"></font></td>\n", $key);
        print "  </tr>\n";
        if ($shippingtype eq "item") {
          $shipping = $shipping + ($item_shipping{"$itemname"} * $item{"$key"});
        }
      }
    }

    #$tax = ($subtotal + $shipping) * $taxrate;
    $total = $subtotal + $shipping;

    my $colspan = 3;
    if ($showskus eq "yes") { $colspan = 4; }

    print "  <tr bgcolor=\"#C0C0C0\">\n";
    print "    <th align=\"left\" colspan=$colspan class=\"subdesc\"><font faceface=\"arial\" size=1>SUBTOTAL</font></th>\n";
    printf("    <td align=\"right\" class=\"subamt\"><font faceface=\"arial\" size=1>$currency_symbol%.2f</font></td>\n", $subtotal);
    print "  </tr>\n";

    #print "  <tr>\n";
    #printf("  <th align=\"left\" colspan=$colspan><font faceface=\"arial\" size=1>SHIPPING</font></th>\n";
    #printf("  <td align=\"right\"><font faceface=\"arial\" size=1>$currency_symbol%.2f</font></td>\n", $shipping);
    #print "  </tr>\n";

    #print "  <tr>\n";
    #print "    <th align=\"left\" colspan=$colspan><font faceface=\"arial\" size=1>TAX ($taxstate only)</font></th>\n";
    #printf("    <td align=\"right\"><font faceface=\"arial\" size=1>%.2f\%</font></td>\n", $taxrate * 100);
    #print "  </tr>\n";

    #print "  <tr>\n";
    #print "    <th align=\"left\" colspan=$colspan>TOTAL</th>\n";
    #printf("    <td align=\"right\">$currency_symbol%.2f</td>\n", $total);
    #print "  </tr>\n";

    #print "  <tr>\n";
    #printf("    <th align=\"left\" colspan=$colspan><font faceface=\"arial\" size=1>TOTAL(%s res. add tax)</font></th>\n", $taxstate);
    #printf("    <td align=\"right\"><font faceface=\"arial\" size=1>$currency_symbol%.2f</font></td>\n", $total);
    #print "  </tr>\n";
    print "</table>\n";

    if ($taxshipline ne "no") {
      print "<font faceface=\"arial\" size=1 id=\"taxship\">Tax and shipping are calculated upon checkout if applicable.</font>\n";
    }
    print "</form>\n";
  }

  while (<TEMPLATEFILE>) {
    if (($_ =~ /\[continue\]/i) && ($continue ne "")) {
      s/\[continue\]/$continue/g;
    }
    if (($_ =~ /\[refsite\]/i) && ($refsite ne "")) {
      s/\[refsite\]/$refsite/g;
    }
    if (($_ =~ /\[order-id\]/i)) {
      s/\[order-id\]/$order_id/g;
    }
    print $_;
  }
  close(TEMPLATEFILE);
}

sub process_prices {

  $username  =~ s/\W//g;
  open(INFILE,"$path_easycart_txt/$username/orderfrm.prices");
  while(<INFILE>) {
    chomp; 
    s/\n//g;
    s/\r//g;
    s/^\s+//g; # remove preceeding whitespace characters
    s/\s+$//g; # remove trailing whitespace characters
    ($operation,$var2) = split;
    if ($operation eq "tax") {
      ($dummy,$taxrate,$taxstate) = split;
    }
    elsif ($operation eq "shipping") {
      ($dummy,$shipping,$shippingtype) = split;
    }
    elsif ($operation eq "cardtype") {
      # do nothing...
    }
    elsif ($operation eq "header") {
      $_ =~ /(.*\w)\W*$/;
      $_ = $1;
      if ($_ =~ /\",\"/) {
        @ky = split(/\",\"/);
      }
      else {
        @ky = split(/\t/);
      }
      if ($shippingtype eq "item") {
        for (my $i=4; $i<=$#ky; $i++) {
          if($ky[$i] =~ /\w/) {
            $cart_hdr .= "$ky[$i]|";
          }
        }
      }
      else {
        for (my $i=3; $i<=$#ky; $i++) {
          if($ky[$i] =~ /\w/) {
            $cart_hdr .= "$ky[$i]|";
          }
        }
      }
      $cart_hdr =~ s/\|{2,}/\|/g; # replace 2 or more pipes, with just a single pipe
      $cart_hdr =~ s/\|+$//; # remove any trailing pipes
    }
    else {
      if ($shippingtype eq "item") {
        if ($_ =~ /\",\"/) {
          ($ordervar,$orderprice,$ordershipping,$orderdescr,@extrastuff) = split(/\",\"/);
          $stuff = @extrastuff;
          $ordervar =~ s/^[\'\"]//g;
          $orderdescr =~ s/[\"]//g;
        }
        else {
          ($ordervar,$orderprice,$ordershipping,$orderdescr,@extrastuff) = split(/	/);
          $stuff = @extrastuff;
        }
        $item_price{"$ordervar"} = $orderprice;
        $item_shipping{"$ordervar"} = $ordershipping;
        $item_descr{"$ordervar"} = $orderdescr;

        for (my $i=0; $i<$stuff; $i++) {
          if ($ky[$i+4] =~ /^(Graphics|Category|long_description)$/i) {
            # do not include columns intended for EasyCart catalog usage only
            next;
          }
          $ky[$i+4] =~ s/\"//g;
          $extrastuff[$i] =~ s/\"//g;
          $$ordervar{"$ky[$i+4]"} = $extrastuff[$i];
        }
      }
      else {
        if ($_ =~ /\",\"/) {
          ($ordervar,$orderprice,$orderdescr,@extrastuff) = split(/\",\"/);
          $ordervar =~ s/^[\'\"]//g;
          $orderdescr =~ s/[\"]//g;
        }
        else {
          ($ordervar,$orderprice,$orderdescr,@extrastuff) = split(/\t/);
        }
        $item_price{"$ordervar"} = $orderprice;
        $item_descr{"$ordervar"} = $orderdescr;
        for (my $i=0; $i<@extrastuff; $i++) {
          if ($ky[$i+3] =~ /^(Graphics|Category|long_description)$/i) {
            # do not include columns intended for EasyCart catalog usage only
            next;          
          }
          $ky[$i+3] =~ s/\"//g;
          $extrastuff[$i] =~ s/\"//g;
          $$ordervar{"$ky[$i+3]"} = $extrastuff[$i];
        }
      }
    }
  }
  close(INFILE);
}

1;
