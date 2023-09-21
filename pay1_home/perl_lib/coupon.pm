package coupon;

use miscutils;
use CGI;
use PlugNPay::InputValidator;
use PlugNPay::GatewayAccount;
use PlugNPay::Util::RandomString;
use strict;

sub new {
  my $type = shift;
  my $data = new CGI;

  %coupon::query = PlugNPay::InputValidator::filteredQuery('coupon');

  $coupon::function = $coupon::query{'function'};

  my $gatewayAccount = new PlugNPay::GatewayAccount($ENV{'REMOTE_USER'});
  $coupon::reseller = $gatewayAccount->getReseller();
  $coupon::merch_company = $gatewayAccount->getCompanyName();

  if (($coupon::query{'expires'} eq "") && (($coupon::query{'endyear'} ne "") || ($coupon::query{'endmonth'} ne "") || ($coupon::query{'endday'} ne ""))) {
    $coupon::query{'expires'} = sprintf("%04d%02d%02d", $coupon::query{'endyear'}, $coupon::query{'endmonth'}, $coupon::query{'endday'});
  }

  $coupon::username = $ENV{'REMOTE_USER'};
  $coupon::subacct = $ENV{'SUBACCT'};

  my @deletelist;
  foreach my $param (keys %coupon::query) {
    if (($param =~ /^delete_/) && ($coupon::function eq "delete_offer")) {
      delete $coupon::query{"$param"};
      my $di = substr($param,7);
      $di =~ s/[^a-zA-Z0-9\-\_\ ]//g;
      $deletelist[++$#deletelist] = "$di";
    }
  }
  if ((@deletelist > 0) && ($coupon::function eq "delete_offer")) {
    &delete_offer(@deletelist);
  }

  &get_promocode();

  return [], $type;
}

sub delete_offer {
  my (@deletelist) = @_;

  my $dbh_disc = &miscutils::dbhconnect("merch_info");
  foreach my $var (@deletelist) {
    my $sth = $dbh_disc->prepare(qq{
        delete from promo_offers 
        where username=? and promocode=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute("$coupon::username", "$var") or die "Can't execute: $DBI::errstr";
    $sth->finish;

    my $sth2 = $dbh_disc->prepare(qq{
        delete from promo_coupon
        where username=? and promocode=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth2->execute("$coupon::username", "$var") or die "Can't execute: $DBI::errstr";
    $sth2->finish;

  }
  $dbh_disc->disconnect;
}

sub delete_coupon {
  if ($coupon::query{'delete'} == 1) {
    my $dbh_disc = &miscutils::dbhconnect("merch_info");

    my $sth = $dbh_disc->prepare(qq{
        delete from promo_coupon
        where username=? and promoid=?
      }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
    $sth->execute("$coupon::username", "$coupon::query{'promoid'}") or die "Can't execute: $DBI::errstr";
    $sth->finish;

    $dbh_disc->disconnect;
  }
}


sub main {
  #&get_promocode();
  &promo_offer_config();
  &promo_coupon_config();
}


sub get_promocode {
  @coupon::promocodes = ();
  my $dbh_disc = &miscutils::dbhconnect("merch_info");

  my ($promocode);
  my $sth = $dbh_disc->prepare(qq{
      select promocode
      from promo_offers
      where username=? and subacct=?
      order by promocode
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$coupon::username", "$coupon::subacct") or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($promocode));
  my $i = 0;
  while($sth->fetch) {
    push @coupon::promocodes, $promocode;
  }
  $sth->finish;

  $dbh_disc->disconnect;
}

sub details_offer {
  my $dbh_disc = &miscutils::dbhconnect("merch_info");
  my $sth = $dbh_disc->prepare(qq{
      select discount,disctype,usetype,status,minpurchase,sku,expires,subacct
      from promo_offers
      where username=? and promocode=? and subacct=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$coupon::username", "$coupon::query{'promocode'}", "$coupon::subacct") or die "Can't execute: $DBI::errstr";
  ($coupon::query{'discount'},$coupon::query{'disctype'},$coupon::query{'usetype'},$coupon::query{'status'},$coupon::query{'minpurchase'},$coupon::query{'sku'},$coupon::query{'expires'},$coupon::query{'subacct'}) = $sth->fetchrow; 
  $sth->finish;
  $dbh_disc->disconnect;

  $coupon::query{'endyear'} = substr($coupon::query{'expires'},0,4);
  $coupon::query{'endmonth'} = substr($coupon::query{'expires'},4,2);
  $coupon::query{'endday'} = substr($coupon::query{'expires'},6,2);
}


sub details_coupon {
  my $dbh_disc = &miscutils::dbhconnect("merch_info");
  my $sth = $dbh_disc->prepare(qq{
      select promocode,use_limit,use_count,expires,status
      from promo_coupon
      where username=?
      and promoid=?
      and subacct=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$coupon::username", "$coupon::query{'promoid'}", "$coupon::subacct")  or die "Can't execute: $DBI::errstr";
  ($coupon::query{'promocode'},$coupon::query{'use_limit'},$coupon::query{'use_count'},$coupon::query{'expires'},$coupon::query{'status'}) = $sth->fetchrow;
  $sth->finish;
  $dbh_disc->disconnect;

  $coupon::query{'endyear'} = substr($coupon::query{'expires'},0,4);
  $coupon::query{'endmonth'} = substr($coupon::query{'expires'},4,2);
  $coupon::query{'endday'} = substr($coupon::query{'expires'},6,2);
}

sub export_coupon {
  my ($data,$i,$promoid,$promocode,$use_limit,$use_count,$expires,$status);
  my $color = 1;

  my $dbh_disc = &miscutils::dbhconnect("merch_info");
  my $sth = $dbh_disc->prepare(qq{
      select promoid,promocode,use_limit,use_count,expires,status
      from promo_coupon
      where username=? and subacct=?
      order by promocode
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$coupon::username", "$coupon::subacct") or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($promoid,$promocode,$use_limit,$use_count,$expires,$status));
  while($sth->fetch) {
    $i++;
    if ($coupon::query{'format'} eq "table") {
      if ($color == 1) {
        $data .= "<tr class=\"listrow_color1\">\n";
      }
      else {
        $data .= "<tr class=\"listrow_color0\">\n";
      }
      $data .= "  <td>$promoid</td>\n";
      $data .= "  <td>$promocode</td>\n";
      $data .= "  <td>$use_limit</td>\n";
      $data .= "  <td>$use_count</td>\n";
      $data .= "  <td>$expires</td>\n";
      $data .= "  <td>$status</td>\n";
      $data .= "  <td><a href=\"$ENV{'SCRIPT_NAME'}\?function=edit_coupon\&promoid=$promoid\">[Edit]</a> &nbsp; <a href=\"$ENV{'SCRIPT_NAME'}\?function=delete_coupon\&promoid=$promoid\&delete=1\">[Delete]</a></td>\n";
      $data .= "</tr>\n";

      $color = ($color + 1) % 2;
    }
    else {
      $data .= "$promoid\t$promocode\t$use_limit\t$use_count\t$expires\t$status\n";
    }
    last if ($i > 250000);
  }
  $sth->finish;
  $dbh_disc->disconnect;

  if ($coupon::query{'format'} eq "table") {
    #print "Content-Type: text/html\n";
    #print "X-Content-Type-Options: nosniff\n";
    #print "X-Frame-Options: SAMEORIGIN\n\n";
  }
  elsif ($coupon::query{'format'} eq "download") {
    print "Content-Type: text/tab-separated-values\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n";
    print "Content-Disposition: attachment; filename=\"export.tsv\"\n\n";
  }
  else {
    print "Content-Type: text/plain\n";
    print "X-Content-Type-Options: nosniff\n";
    print "X-Frame-Options: SAMEORIGIN\n\n";
  }

  if ($coupon::query{'format'} eq "table") {
    &head();

    print "<table border=\"1\" cellspacing=\"0\" cellpadding=\"2\">\n";
    print "  <tr class=\"listsection_title\">\n";
    print "    <td>Coupon ID</td>\n";
    print "    <td>Promo Offer</td>\n";
    print "    <td>Use Limit</td>\n";
    print "    <td>Usage Count</td>\n";
    print "    <td>Expiration</td>\n";
    print "    <td>Status</td>\n";
    print "    <td>&nbsp;</td>\n";
    print "</tr>\n";
  }
  else {
    print "PROMO_ID\tOFFER_CODE\tUSE_LIMIT\tUSE_CNT\tEXPIRE_DATE\tSTATUS\n";
  }

  print $data;

  if ($coupon::query{'format'} eq "table") {
    print "</table>\n";
    &tail();
  }

  return; 
}


sub promo_offer_config {
  if (@coupon::promocodes > 0) {
    ###  Edit Form
    print "<tr><td class=\"menuleftside\" colspan=1 rowspan=2>Edit Promo Offer\n";
    print "<form method=post action=\"$ENV{'SCRIPT_NAME'}\">\n";
    print "<input type=\"hidden\" name=\"function\" value=\"edit_offer\"></td></tr>\n";
    print "<tr><td>\n";
  
    print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
    print "<tr><td class=\"$coupon::color{'promo_offer'}\">Promotional Offer</td>\n";
    print "<td class=\"$coupon::color{'promo_offer'}\">\n";
    print "<select name=\"promocode\">\n";
    foreach my $var (@coupon::promocodes) {
      print "<option value=\"$var\">$var</option>\n";
    }
    print "</select></td></tr>\n";
    print "</table>\n";
    print "<br><input type=submit name=submit value=\" Edit Offer \"></form></td></tr>\n";

    ###  Delete Form
    print "<tr><td class=\"menuleftside\" colspan=1 rowspan=2>Delete Promo Offers\n";
    print "<form method=post action=\"$ENV{'SCRIPT_NAME'}\">\n";
    print "<input type=\"hidden\" name=\"function\" value=\"delete_offer\"></td></tr>\n";
    print "<tr><td>\n";
    print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
    print "<tr class=\"listsection_title\"><td>Promotional Offer ID</td><td>Action</td></tr>\n";
    foreach my $key (@coupon::promocodes) {
      print "<tr><td>$key</td>\n";
      print "<td><input type=checkbox name=\"delete_$key\" value=\"1\"> Delete</td></tr>\n";
    }
    print "</table>\n";
    print "<br><input type=submit name=submit value=\" Delete Offer \"></form></td></tr>\n";
  }
 
  ###  Add Form
  &add_edit_offer_form();

}


sub add_edit_offer_form {

  print "<tr><td class=\"menuleftside\" colspan=1 rowspan=2>";
  if ($coupon::function eq "edit_offer") {
    print "Edit Promo Offer\n";
  }
  else {
    print "Add Promo Offer\n";
  }

  print "<form method=post action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"function\" value=\"add_offer\"></td></tr>\n";
  print "<tr><td>\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "<tr><td class=\"$coupon::color{'promocode'}\">Promotional Offer ID</td>\n";
  print "<td><input type=text name=\"promocode\" value=\"$coupon::query{'promocode'}\" size=\"20\" maxlength=\"30\"> &nbsp; &nbsp; </td></tr>\n";

  print "<tr><td class=\"$coupon::color{'discount'}\">Discount</td><td><input size=\"9\" type=\"text\" name=\"discount\" value=\"$coupon::query{'discount'}\">\n";
  #print "<br><font size=\"-2\">- For Item Certificates, enter prerequisite SKU, if another product must be present for redemption.</font>\n";
  print "</td></tr>\n";

  my %selected = ();
  $selected{$coupon::query{'disctype'}} = " selected";

  print "<tr><td class=\"$coupon::color{'disctype'}\">Discount Type</td><td><select name=\"disctype\">";
  print "<option value=\"gift\"$selected{'gift'}> Gift Certificate &nbsp;&nbsp; </option>\n";
  print "<option value=\"cert\"$selected{'cert'}> Item Certificate &nbsp;&nbsp; </option>\n";
  print "<option value=\"amt\"$selected{'amt'}> Currency Value &nbsp;&nbsp; </option>\n";
  print "<option value=\"pct\"$selected{'pct'}> Percentage Discount &nbsp; </option>\n";
  print " </select></td></tr>\n";

  print "<tr><td class=\"$coupon::color{'minpurchase'}\">Minimum Purchase</td><td><input size=\"9\" type=\"text\" name=\"minpurchase\" value=\"$coupon::query{'minpurchase'}\"></td></tr>\n";

  print "<tr><td class=\"$coupon::color{'sku'}\">SKU</td><td><input size=\"9\" type=\"text\" name=\"sku\" value=\"$coupon::query{'sku'}\"></td></tr>\n";

  #print "<tr><td class=\"$coupon::color{'uselimit'}\">Use Limit</td><td><input size=\"9\" type=\"text\" name=\"uselimit\" value=\"$query{'uselimit'}\"> Enter no. times </td></tr>\n";

  my $html = &end_date($coupon::query{'endyear'}, $coupon::query{'endmonth'}, $coupon::query{'endday'});
  print "<tr><td class=\"$coupon::color{'expires'}\">Expiration Date</td><td>$html</td></tr>\n";

  print "</table><br>\n";
  if ($coupon::function eq "edit_offer") {
    print "<input type=submit name=submit value=\" Update Promo Offer \">";
  }
  else {
    print "<input type=submit name=submit value=\" Add Promo Offer \">";
  }

  print "&nbsp; &nbsp; <a href=\"javascript:help_win('/new_docs/Coupon_Management.htm',600,500)\">Online Help</a></form></td></tr>\n";
}

sub promo_coupon_config {

  ###  Edit Coupon
  print "<tr><td class=\"menuleftside\" colspan=1 rowspan=2>Edit Coupon\n";
  print "<form method=post action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"function\" value=\"edit_coupon\"></td></tr>\n";
  print "<tr><td>\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "<tr><td class=\"$coupon::color{'promoid'}\">Coupon ID</td>\n";
  print "<td><input type=text name=\"promoid\" value=\"$coupon::query{'promoid'}\" size=\"20\" maxlength=\"59\"> </td></tr>\n";
  print "</table>\n";
  print "<br><input type=submit name=submit value=\" Edit Coupon \"></form></td></tr>\n";

  ###  Delete Coupon
  print "<tr><td class=\"menuleftside\" colspan=1 rowspan=2>Delete Coupon\n";
  print "<form method=post action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"function\" value=\"delete_coupon\"></td></tr>\n";
  print "<tr><td>\n";
  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "<tr class=\"listsection_title\"><td>Coupon ID</td><td>Action</td></tr>\n";
  print "<tr><td><input type=text name=\"promoid\" value=\"$coupon::query{'promoid'}\" size=\"20\" maxlength=\"59\"> </td>\n";
  print "<td><input type=checkbox name=\"delete\" value=\"1\"> Delete</td></tr>\n";
  print "</table>\n";
  print "<br><input type=submit name=submit value=\" Delete Coupon \"></form></td></tr>\n";

  ###  Add Coupon
  &add_edit_coupon_form();

  ###  Export Coupons
  print "<tr><td class=\"menuleftside\" colspan=1 rowspan=2>Export Coupon Database\n";
  print "<form method=post action=\"$ENV{'SCRIPT_NAME'}\" target=\"newWin\">\n";
  print "<input type=\"hidden\" name=\"function\" value=\"export_coupon\"></td></tr>\n";
  print "<td>&nbsp; Format: <input type=\"radio\" name=\"format\" value=\"download\" checked> Download \n";
  print "<input type=\"radio\" name=\"format\" value=\"text\"> Text \n";
  print "<input type=\"radio\" name=\"format\" value=\"table\"> Table \n";
  print "<br><input type=submit name=submit value=\" Export Coupon Database\"></form></td></tr>\n";
}

sub add_edit_coupon_form {
  my %selected = ();

  print "<tr><td class=\"menuleftside\" colspan=1 rowspan=2>";
  if ($coupon::function eq "edit_coupon") {
    print "Edit Coupon\n";
    $coupon::query{'allow_update'} = "allow_update";
  }
  else {
    print "Add Coupon\n";
  }

  print "<form method=post action=\"$ENV{'SCRIPT_NAME'}\">\n";
  print "<input type=\"hidden\" name=\"function\" value=\"add_coupon\"></td></tr>\n";
  print "<tr><td>\n";

  print "<table border=1 cellspacing=0 cellpadding=4 width=\"100%\">\n";
  print "<tr><td class=\"$coupon::color{'promoid'}\" rowspan=\"3\">Starting Coupon ID</td>\n";
  print "<td><input type=text name=\"promoid\" value=\"$coupon::query{'promoid'}\" size=\"20\" maxlength=\"59\"><br>\n";
  print "Must be numeric if Coupon Count value is greater than 1.<br>Leave blank if Random option is slected. </td></tr>\n";
  %selected = ();
  $selected{$coupon::query{'id_type'}} = " checked";
  print "<tr><td><input type=\"checkbox\" name=\"id_type\" value=\"random\" $selected{'id_type'}>Random Generated</td></tr>\n";

  %selected = ();
  $selected{$coupon::query{'allow_update'}} = " checked";
  print "<tr><td><input type=\"checkbox\" name=\"allow_update\" value=\"1\" $selected{'allow_update'}>Allow Override of existing.</td></tr>\n";

  %selected = ();
  $selected{$coupon::query{'id_cnt'}} = " selected";
  print "<tr><td>Coupon Count</td><td><select name=\"id_cnt\">\n";
  my @cnt_values = ('1','10','50','100','250','500','1000','2500','5000','10000');
  foreach my $var (@cnt_values) {
    print "<option value=\"$var\" $selected{$var}>$var</option>\n";
  } 
  print "</select> Select no. of Coupons to Generate.</td></tr>\n";

  print "<tr><td class=\"$coupon::color{'promo_offer'}\">Promotional Offer</td>\n";
  print "<td class=\"$coupon::color{'promo_offer'}\">\n";
  print "<select name=\"promocode\">\n";

  %selected = ();
  $selected{$coupon::query{'promocode'}} = " selected";
  foreach my $var (@coupon::promocodes) {
    print "<option value=\"$var\" $selected{$var}>$var</option>\n";
  }
  print "</select></td></tr>\n";

  print "<tr><td class=\"$coupon::color{'use_limit'}\">Use Limit</td><td><input size=\"9\" type=\"text\" name=\"use_limit\" value=\"$coupon::query{'use_limit'}\">\n";
  print "<br><font size=\"-2\">- Leave blank for no usage limit on Item Certificates, Currency Values &amp; Percentage Discounts.</font>\n";
  print "<br><font size=\"-2\">- For Gift Certificates, \$ values MUST set limit in xxx.xx format. (e.g. 1234.56)</font>\n";
  print "</td></tr>\n";

  my $html = &end_date($coupon::query{'endyear'}, $coupon::query{'endmonth'}, $coupon::query{'endday'});
  print "<tr><td class=\"$coupon::color{'expire'}\">Expiration Date</td><td>$html</td></tr>\n";

  %selected = ();
  $selected{$coupon::query{'status'}} = " selected";

  print "<tr><td class=\"$coupon::color{'status'}\">Status</td><td><select name=\"status\">";
  print "<option value=\"1\"$selected{'1'}> Active &nbsp;&nbsp; </option>\n";
  print "<option value=\"0\"$selected{'0'}> In-Active &nbsp;&nbsp; </option>\n";
  print " </select></td></tr>\n";

  print "</table><br>\n";
  if ($coupon::function eq "edit_coupon") {
    print "<input type=submit name=submit value=\" Update Coupon \">";
  }
  else {
    print "<input type=submit name=submit value=\" Add Coupon \">";
  }
  print "&nbsp; &nbsp; <a href=\"javascript:help_win('/new_docs/Coupon_Management.htm',600,500)\">Online Help</a></form></td></tr>\n";
}



sub update_offer {
  $coupon::query{'expires'} = $coupon::query{'endyear'} . $coupon::query{'endmonth'} . $coupon::query{'endday'};
  my $dbh = &miscutils::dbhconnect("merch_info");

  my $sth = $dbh->prepare(qq{
      select username
      from promo_offers
      where username=? and promocode=? and subacct=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$coupon::username", "$coupon::query{'promocode'}", "$coupon::subacct") or die "Can't execute: $DBI::errstr";
  my ($test) = $sth->fetchrow;
  $sth->finish;

  print "TEST:$test<br>\n";

  if ($test ne "") {
    my $sth = $dbh->prepare(qq{
        update promo_offers
        set discount=?, disctype=?, usetype=?, status=?, minpurchase=?, sku=?, expires=?
        where username=? and promocode=? and subacct=?
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$coupon::query{'discount'}","$coupon::query{'disctype'}","$coupon::query{'usetype'}",
                  "$coupon::query{'status'}","$coupon::query{'minpurchase'}","$coupon::query{'sku'}","$coupon::query{'expires'}",
                  "$coupon::username", "$coupon::query{'promocode'}", "$coupon::subacct") 
    or die "Can't execute: $DBI::errstr";
    $sth->finish;
  }
  else {
    my $sth = $dbh->prepare(qq{
        insert into promo_offers
        (username,promocode,discount,disctype,usetype,status,minpurchase,sku,expires,subacct)
        values (?,?,?,?,?,?,?,?,?,?)
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$coupon::username","$coupon::query{'promocode'}","$coupon::query{'discount'}","$coupon::query{'disctype'}",
                 "$coupon::query{'usetype'}","$coupon::query{'status'}","$coupon::query{'minpurchase'}","$coupon::query{'sku'}",
                 "$coupon::query{'expires'}","$coupon::subacct");
    $sth->finish;
  }
  $dbh->disconnect;
}


sub generate_ids {
  my ($self,$cnt) = @_;

  # use $coupon::query{'id_cnt'} if $cnt is not passed in as a variable
  $cnt ||= $coupon::query{'id_cnt'};

  # if $cnt is still undefined, try $self, in case called statically.
  if (!ref($self)) {
    $cnt ||= $self;
  }

  $cnt ||= 1; # always generate at least one

  my $promoid = $coupon::query{'promoid'};
  my @ids;

  my $randomGenerator = new PlugNPay::Util::RandomString();

  for (my $i=1; $i<=$cnt; $i++) { # seriously wtf was that?  it was off by 1, the else never gets run if $cnt > 1.
    if ($coupon::query{'id_type'} eq "random") {
      $promoid = $randomGenerator->randomAlphaNumeric(40); # used to be a sha1 hash which is 40 characters
    }
    else {
      $promoid++;
    }
    push @ids,$promoid;
  }

  return \@ids;
}

sub update_coupon {
  my ($self,$promoid) = @_;
  $promoid ||= $self; # for if called as $coupon->update_coupon
  my $dbh = &miscutils::dbhconnect("merch_info");

  my $sth = $dbh->prepare(qq{
      select username
      from promo_coupon
      where username=? and promoid=? and subacct=?
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$coupon::username", "$promoid", "$coupon::subacct") or die "Can't execute: $DBI::errstr";
  my ($test) = $sth->fetchrow;
  $sth->finish;

  if ($test ne "") {
    if ($coupon::query{'allow_update'} == 1) {
      my $sth = $dbh->prepare(qq{
          update promo_coupon
          set promocode=?, use_limit=?, expires=?, status=?
          where username=? and promoid=? and subacct=?
        }) or die "Can't prepare: $DBI::errstr";
      $sth->execute("$coupon::query{'promocode'}","$coupon::query{'use_limit'}","$coupon::query{'expires'}","$coupon::query{'status'}",
                    "$coupon::username", "$promoid", "$coupon::subacct")
      or die "Can't execute: $DBI::errstr";
      $sth->finish;
    }
  }
  else {
    my $sth = $dbh->prepare(qq{
        insert into promo_coupon
        (username,promoid,promocode,use_limit,expires,status,subacct)
        values (?,?,?,?,?,?,?)
      }) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$coupon::username","$promoid","$coupon::query{'promocode'}","$coupon::query{'use_limit'}",
                 "$coupon::query{'expires'}","$coupon::query{'status'}","$coupon::subacct");
    $sth->finish;
  }
  $dbh->disconnect;
}

sub discountreport {

  #%month_array = (1,"Jan",2,"Feb",3,"Mar",4,"Apr",5,"May",6,"Jun",7,"Jul",8,"Aug",9,"Sep",10,"Oct",11,"Nov",12,"Dec");
  my %month_array2 = ("Jan","01","Feb","02","Mar","03","Apr","04","May","05","Jun","06","Jul","07","Aug","08","Sep","09","Oct","10","Nov","11","Dec","12");

  my $start = sprintf("%04d%02d%02d", $coupon::query{'startyear'}, $month_array2{$coupon::query{'startmonth'}}, $coupon::query{'startday'});
  my $end = sprintf("%04d%02d%02d", $coupon::query{'endyear'}, $month_array2{$coupon::query{'endmonth'}}, $coupon::query{'endday'});

  print "<html>\n";
  print "<head>\n";
  print "<title>Discount Report</title>\n";
  print "<link href=\"/css/style_coupon.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<META HTTP-EQUIV=\"Pragma\" CONTENT=\"no-cache\">\n";
  print "<META HTTP-EQUIV=\"Cache-Control\" CONTENT=\"no-cache\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<form method=\"post\" action=\"editcust.cgi\">\n";
  print "<input type=\"hidden\" name=\"function\" value=\"updatediscounts\">\n";
  print "<div align=\"center\">\n";
  print "<table border=\"0\" width=\"400\">\n";
  print "<tr>";
  print "<th align=\"left\">Date</th>";
  print "<th align=\"left\">OrderID</td>\n";
  print "<th align=\"left\">Softcart ID</th>";
  print "<th align=\"left\">Certificate</th>";
  print "<th align=\"right\">Amount</th>\n";

  my $dbh_disc = &miscutils::dbhconnect("isi");

  my ($orderid,$trans_date,$softcartid,$certnum,$amount);
  my $sth = $dbh_disc->prepare(qq{
      select orderid,trans_date,softcartid,certnum,amount
      from certificate
      where orderid IS NOT NULL and orderid<>''
      and trans_date>=? and trans_date<?
      order by orderid
    }) or die "Can't do: $DBI::errstr";
  $sth->execute("$start", "$end") or die "Can't execute: $DBI::errstr";
  $sth->bind_columns(undef,\($orderid,$trans_date,$softcartid,$certnum,$amount));

  while($sth->fetch) {
    my $datestr = sprintf("%02d/%02d/%04d", substr($trans_date,4,2), substr($trans_date,6,2), substr($trans_date,0,4));

    print "<tr>";
    print "<th align=\"left\">$datestr</th>\n";
    print "<td>$orderid</td>\n";
    print "<td>$softcartid</td>\n";
    print "<td>$certnum</td>\n";
    printf("<td align=\"right\">%.2f</td>\n", $amount);
  }
  $sth->finish;

  $dbh_disc->disconnect;

  print "</table>\n";
  print "</div>\n";
  print "</body>\n";
  print "</html>\n";
}

sub response_page {
  print "Content-Type: text/html\n";
  print "X-Content-Type-Options: nosniff\n";
  print "X-Frame-Options: SAMEORIGIN\n\n";
  my($message,$close) = @_;
  print "<html>\n";
  print "<head>\n";
  print "<title>Response Page</title>\n";
  print "<link href=\"/css/style_coupon.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<META HTTP-EQUIV=\"Pragma\" CONTENT=\"no-cache\">\n";
  print "<META HTTP-EQUIV=\"Cache-Control\" CONTENT=\"no-cache\">\n";

  my ($autoclose);
  if ($close eq "auto") {
    $autoclose = "onLoad=\"update_parent();\"\n"
  }
  elsif ($close eq "relogin") {
    $autoclose = "onLoad=\"update_parent1();\"\n"
  }

  print "<script Language=\"Javascript\">\n";
  print "<\!-- Start Script\n";

  print "function closeresults() {\n";
  print "  resultsWindow = window.close(\"results\");\n";
  print "}\n\n";

  print "function update_parent() {\n";
  print "  window.opener.location = 'security.cgi';\n";
  print "  self.close();\n";
  print "}\n";

  print "function update_parent1() {\n";
  print "  window.opener.location = '/adminlogin.html';\n";
  print "  self.close();\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n";

  print "</head>\n";

  print "<body bgcolor=\"#ffffff\" $autoclose>\n";
  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"1\" width=\"500\">\n";
  print "<tr><td align=\"center\" colspan=\"4\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\"></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"4\" class=\"larger\" bgcolor=\"#000000\"><font color=\"#ffffff\">Promotional Discounts Administration Area</font></td></tr>\n";
  print "<tr><td align=\"center\" colspan=\"4\"><img src=\"/images/icons.gif\" alt=\"The PowertoSell\"></td></tr>\n";
  print "<tr><td>&nbsp;</td><td>&nbsp;</td><td colspan=2>&nbsp;</td></tr>\n";
  print "<tr><td colspan=\"4\">$message</td></tr>\n";
  print "</table>\n";

  if ($close eq "yes") {
    print "<p><div align=\"center\"><a href=\"javascript:update_parent();\">Close Window</a></div>\n";
  }

  print "</body>\n";
  print "</html>\n";
  exit;
}


sub response_page_blank {
  print "Content-Type: text/html\n";
  print "X-Content-Type-Options: nosniff\n";
  print "X-Frame-Options: SAMEORIGIN\n\n";
  my($message,$close) = @_;
  print "<html>\n";
  print "<head>\n";
  print "<title>Response Page</title>\n";
  print "<link href=\"/css/style_coupon.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<META HTTP-EQUIV=\"Pragma\" CONTENT=\"no-cache\">\n";
  print "<META HTTP-EQUIV=\"Cache-Control\" CONTENT=\"no-cache\">\n";
  print "</head>\n";

  my ($autoclose);
  if ($close eq "auto") {
    $autoclose = "onLoad=\"update_parent();\"\n"
  }
  elsif ($close eq "relogin") {
    $autoclose = "onLoad=\"update_parent1();\"\n"
  }

  print "<script Language=\"Javascript\">\n";
  print "<\!-- Start Script\n";

  print "function update_parent() {\n";
  print "  window.opener.location = '/admin/security.cgi';\n";
  print "  self.close();\n";
  print "}\n";

  print "function update_parent1() {\n";
  print "  window.opener.location = '/adminlogin.html';\n";
  print "  self.close();\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" $autoclose>\n";
  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"1\" width=\"500\">\n";
  print "<tr><td colspan=\"4\">Working . . . . . . . . . . . . . . . . . </td></tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
  exit;
}

sub tail {
  print "</td></tr>\n";
  print "</table>\n";

  my @now = gmtime(time);
  my $copy_year = $now[5]+1900;

  print "</td>\n";
  print "  </tr>\n";
  print "</table>\n";
  
  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"footer\">\n";
  print "  <tr>\n";
  print "    <td align=\"left\"><p><a href=\"/admin/logout.cgi\" title=\"Click to log out\">Log Out</a> | <a href=\"javascript:change_win('/admin/helpdesk.cgi',600,500,'ahelpdesk')\">Help Desk</a> | <a id=\"close\" href=\"javascript:closewin();\" title=\"Click to close this window\">Close Window</a></p></td>\n";
  print "    <td align=\"right\"><p>\&copy; $copy_year, ";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "Plug and Pay Technologies, Inc.";
  }
  else {
    print "$ENV{'SERVER_NAME'}";
  }
  print "</p></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</body>\n";
  print "</html>\n";
}

sub head {
  print "Content-Type: text/html\n";
  print "X-Content-Type-Options: nosniff\n";
  print "X-Frame-Options: SAMEORIGIN\n\n";

  print "<html>\n";
  print "<head>\n";
  print "<title>Promotional Discounts Administration</title>\n";
  print "<link href=\"/css/style_coupon.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "<META HTTP-EQUIV=\"Pragma\" CONTENT=\"no-cache\">\n";
  print "<META HTTP-EQUIV=\"Cache-Control\" CONTENT=\"no-cache\">\n";

  print "<script Language=\"Javascript\">\n";
  print "<!-- // Begin Script \n\n";

  print "function results() {\n";
  print "  // resultsWindow = window.open(\"/payment/recurring/blank.html\",\"results\",\"menubar=yes,toolbar=yes,status=no,scrollbars=yes,resizable=yes,width=550,height=500\");\n";
  print "}\n";

  print "function onlinehelp(subject) {\n";
  print "  helpURL = '/online_help/' + subject + '.html';\n";
  print "  helpWin = window.open(helpURL,\"helpWin\",\"menubar=no,status=no,scrollbars=yes,resizable=yes,width=350,height=350\");\n";
  print "}\n";

  print "function help_win(helpurl,swidth,sheight) {\n";
  print "  SmallWin = window.open(helpurl, 'HelpWindow','scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function close_me() {\n";
  print "  //tttt = window.opener.window.name.value;\n";
  print "  //alert(tttt);\n";
  print "  document.editUser.submit();\n";
  print "  // self.close();\n";
  print "}\n";

  print "function popminifaq() {\n";
  print "  minifaq=window.open('/admin/wizards/faq_board.cgi\?mode=mini_faq_list\&category=all\&search_keys=QA20020122235446,QA20020122235541,QA20020122235817,QA20020123000121,QA20020429211456','minifaq','width=600,height=400,toolbar=no,location=no,directories=no,status=yes,menubar=yes,scrollbars=yes,resizable=yes');\n";
  print "  if (window.focus) { minifaq.focus(); }\n";
  print "  return false;\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "// end script-->\n";
  print "</script>\n";

  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\">";
  if ($ENV{'SERVER_NAME'} eq "pay1.plugnpay.com") {
    print "<img src=\"/css/global_header_gfx.gif\" width=\"760\" alt=\"Plug 'n Pay Technologies - we make selling simple.\"  height=\"44\" border=\"0\">";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corporate Logo\">";
  }
  print "</td>\n";
  print "  </tr>\n";

  if ($coupon::reseller !~ /(webassis)/) {
    print "  <tr>\n";
    print "    <td align=\"left\" nowrap><a href=\"$ENV{'SCRIPT_NAME'}\">Home</a></td>\n";
    print "    <td align=\"right\" nowrap><!--<a href=\"/admin/logout.cgi\">Logout</a> &nbsp;\|&nbsp; --><a href=\"#\" onClick=\"popminifaq();\">Mini-FAQ</a></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\"><img src=\"/css/header_bottom_bar_gfx.gif\" width=\"760\" height=\"14\"></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"5\" width=\"760\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" valign=\"top\" align=\"left\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"2\"><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Promotional Discounts Administration Area</a> - $coupon::merch_company</h1></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td>";

  print "<table border=\"0\" cellspacing=\"1\" cellpadding=\"0\" width=\"100%\">\n";
}


sub input_check {
  my ($error);

  foreach my $key (keys %coupon::query) {
    $coupon::color{$key} = 'goodcolor';
  }

  #my @check = @required_fields;
  my @check = ('promocode');

  if ($coupon::function =~ /^(add_offer|edit_offer)$/) {
    if ($coupon::query{'disctype'} eq "pct") {
      #@check = (@check,'promocode','discount');
      $check[++$#check] = 'promocode';
      $check[++$#check] = 'discount';
    }
    elsif ($coupon::query{'disctype'} eq "amt") {
      #@check = (@check,'promocode','discount');
      $check[++$#check] = 'promocode'; 
      $check[++$#check] = 'discount';
    }
    elsif ($coupon::query{'disctype'} eq "gift") {
      #@check = (@check); # no requirements when being used for gift certificates (micro-payments)
    }
    else { ##  Disctype Certificate
      #@check = (@check,'promocode','sku'); # SKU requirements for free item certs
      $check[++$#check] = 'promocode'; 
      $check[++$#check] = 'sku';
    }
  }
  elsif ($coupon::function =~ /^(add_coupon|edit_coupon)$/) {
    if ($coupon::query{'id_type'} ne "random") {
      #@check = (@check,'promoid','promocode');
      $check[++$#check] = 'promoid'; 
      $check[++$#check] = 'promocode';
    }
    else {
      #@check = (@check,'promocode');
      $check[++$#check] = 'promocode'; 
    }
  }
  else {
    #@check = (@check);
  }

#  foreach my $var (@check) {
#    $test_str .= "$var|";
#  }

  foreach my $var (@check) {
    my $val = $coupon::query{$var};
    $val =~ s/[^a-zA-Z0-9]//g;
    if (length($val) < 1) {
      $coupon::error_string .= "Missing Value for $var.<br>";
      $error = 1;
      $coupon::color{$var} = 'badcolor';
      $coupon::errvar .= "$var\|";
    }
  }
#  if ($test_str =~ /discount/) {
#    if ($coupon::query{'ipaddress'} !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
#      $coupon::error_string .= "IP Address incorrect Format.<br>";
#      $error = 7;
#      $coupon::color{'ipaddress'} = 'badcolor';
#      $coupon::errvar .= "ipaddress\|";
#    }
#  }

  if ($coupon::error_string ne "") {
    $coupon::error_string .= "Please Re-enter.";
  }

  $coupon::error = $error;
  return $error;
}

sub calculate_discnt {
  my (%query) = @_;
  my (@discountarray) = "";
  my ($temp,$promoid,$promocode,$limit,$count,$expires,$status,$discounttotal);
  my ($dummy,$datestr,$timestr) = &miscutils::gendatetime();

  my (@codes, $errmsg);
  my ($discount,$disctype,$usetype,$minpurchase,$sku,$i);

  my $qstr1 = "select promoid,promocode,use_limit,use_count,expires,status,";
  $qstr1 .= "where username=? ";
  my @placeholder1 = ("$query{'publisher-name'}");

  foreach my $promoid (@discountarray) {
    $temp .= "promoid=? or ";
    push(@placeholder1, "$promoid");
  }
  $temp = substr($temp,0,length($temp)-3);

  $qstr1 .= "and ($temp) ";

  if ($query{'subacct'} ne "") {
    $qstr1 .= "and subacct=? ";
    push(@placeholder1, "$query{'subacct'}");
  }

  my $dbh = &miscutils::dbhconnect('merchinfo');

  my $sth1 = $dbh->prepare(qq{$qstr1});
  $sth1->execute(@placeholder1);
  my $rv1 = $sth1->bind_columns(undef,\($promoid,$promocode,$limit,$count,$expires,$status));
  while ($sth1->fetch) {
    $count++;
    if ($expires > $datestr) {
      $errmsg .= "Coupon Code:$promoid, Offer expired.|";
      next;
    }
    elsif ($status eq "cancel") {
      $errmsg .= "Coupon Code:$promoid, Offer canceled.|";
      next;
    }
    elsif ($count > $limit) {
      $errmsg .= "Coupon Code:$promoid, Use count exceeded.|";
      next;
    }
    push(@codes, $promocode);
  }
  $sth1->finish;

  my $qstr2 = "select discount,disctype,usetype,status,minpurchase,sku ";
  $qstr2 .= "where username=? ";
  my @placeholder2 = ("$query{'publisher-name'}");

  foreach my $promocode (@codes) {
    $temp .= "promocode=? or ";
    push(@placeholder2, "$promocode");
  }
  $temp = substr($temp,0,length($temp)-3);

  $qstr2 .= "and ($temp) ";

  if ($query{'subacct'} ne "") {
    $qstr2 .= "and subacct=? ";
    push(@placeholder2, "$query{'subacct'}");
  }

  my $sth2 = $dbh->prepare(qq{$qstr2});
  $sth2->execute(@placeholder2);
  my $rv2 = $sth2->bind_columns(undef,\($discount,$disctype,$usetype,$status,$minpurchase,$sku));
  while ($sth2->fetch) {
    if ($expires > $datestr) {
      $errmsg .= "Coupon Code:$promoid, Offer expired.|";
      next;
    }
    if ($sku ne "") {
      my  $i=1;
      foreach my $var (@payutils::item) {
        if (($var =~ /$var/) && ($payutils::subtotal > $minpurchase) && ($status ne "cancel")) {
          if ($disctype eq "cert") {
            $discounttotal += $payutils::cost[$i];
          }
          elsif ($disctype eq "dscnt") {
            $discounttotal += $discount;
          }
          elsif ($disctype eq "prcnt") {
            $discounttotal += ($payutils::cost[$i] * $discount);
          }
        }
      }  
      last;
    }
    else {
      if ($disctype eq "dscnt") {
        $discounttotal += $discount;
      }
      elsif ($disctype eq "prcnt") {
        $discounttotal += ($payutils::cost[$i] * $discount);
      }
      last;
    }
  }
  $sth2->finish;

  if ($discounttotal > $payutils::subtotal) {
    $payutils::subtotal = 0;
  }
  else {
    $payutils::subtotal -= $discounttotal;
  }

  $dbh->disconnect();

  return $discounttotal;
}

sub end_date {
  my ($select_yr, $select_mo, $select_dy) = @_;

  my @month_names = ('', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

  my @default_date = gmtime(time + 2629743.83); # set default to 1 month into future [1 month = 2629743.83 seconds]
  $default_date[5] += 1900; # adjust for correct 4-digit year
  $default_date[4] += 1;    # adjust for correct 2-digit month

  my $data = "<select name=\"endmonth\">\n";
  for (my $i = 1; $i <= $#month_names; $i++) {
    $data .= sprintf("<option value=\"%02d\"", $i);
    if ($select_mo =~ /\d/) {
      if ($i == $select_mo) {
        $data .= " selected";
      }
    }
    else {
      if ($i == $default_date[4]) {
        $data .= " selected";
      }
    }
    $data .= ">$month_names[$i]</option>\n";
  }
  $data .= "</select>\n";
  $data .= "<select name=\"endday\">\n";
  for (my $i = 1; $i <= 31; $i++) {
    $data .= sprintf("<option value=\"%02d\"", $i);
    if ($select_dy =~ /\d/) {
      if ($i == $select_dy) {
        $data .= " selected";
      }
    }
    else {
      #if ($i == $default_date[3]) {
      #  $data .= " selected";
      #}
    }
    $data .= ">$i</option>\n";
  }
  $data .= "</select>\n";
  $data .= "<select name=\"endyear\">\n";
  for (my $i = 2000; $i <= $default_date[5]+5; $i++) {
    $data .=  sprintf("<option value=\"%04d\"", $i);
    if ($select_yr =~ /\d/) {
      if ($i == $select_yr) {
        $data .= " selected";
      }
    }
    else {
      if ($i == $default_date[5]) {
        $data .= " selected";
      }
    }
    $data .= ">$i</option>\n";
  }
  $data .= "</select>\n";

  return $data;
}

1;
