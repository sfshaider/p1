package emailconf;

use strict;
use pnp_environment;
use miscutils;
use emailconfutils;
use CGI;
#use CCLibMCK qw(GetQuery);
use Tie::IxHash;
use sysutils;
use PlugNPay::Features;
use PlugNPay::GatewayAccount;
use PlugNPay::Die;
use PlugNPay::DBConnection;

# things to do
#  maybe fix marketing to prescan template for required variables.
# possibly eliminate marketing from the code

# list of test types
# tie %emailconf::testtype, "Tie::IxHash"; # i *really* don't see how this is necessary in the code, made 'none' default in select.
our %testtype = (
  'none' => 'none',
  'eq' => 'equal to',
  'lt' => 'less than',
  'gt' => 'greater than'
);

# list of fields that can be tested
our @testwhat = ('none','item','quantity','cost','plan','purchaseid','subacct','order-id','paymethod','acct_code','acct_code2','acct_code3');

# used to store default settings for all templates except marketing right now
# multiple is a flag for if the template type is allowed to have multiple copies
# also disables rule collection
our %template_kit = (
  confirmation => {
    emailtype => "conf",
    htmlname => "Customer Confirmation",
    file => "conf.msg",
    emaildelay => "0,none",
    emailexclude => "none",
    emailweight => "1",
    description => "confemail",
    multiple => 1,
    visible => 1,
  },
  merchant => {
    emailtype => "merch",
    htmlname => "Merchant Confirmation",
    file => "merch.msg",
    emaildelay => "0,none",
    emailexclude => "none",
    emailweight => "1",
    description => "merchemail",
    multiple => 1,
    visible => 1,
  }
);


sub new {
  my $type = shift;

  # James - 12/30/09 - replaced old CCLibMCK GetQuery call with more secure CGI query data collection process
  #%emailconf::query = &GetQuery;

  if (1) {
    my $path_debug = "/home/p/pay1/database/debug/scripts_calling_emailconf.txt";
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
    my $now = sprintf("%04d%02d%02d %02d\:%02d\:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
    &sysutils::filelog("append",">>$path_debug");
    open(DEBUG,">>$path_debug");
    print DEBUG "DATE:$now, SCRIPT:$ENV{'SCRIPT_NAME'}, PID:$$\n";
    close (DEBUG);
  }

  %emailconf::query = ();
  my $query = new CGI;
  my @array = $query->param;
  foreach my $var (@array) {
    $var =~ s/[^a-zA-Z0-9\_\-]//g;
    #if ($var ne "email_confirmation") {
      $emailconf::query{"$var"} = &CGI::escapeHTML($query->param($var));
    #}
    #else {
    #  $emailconf::query{"$var"} = $query->param($var);
    #}
  }

  $emailconf::path_web = &pnp_environment::get('PNP_WEB');
  $emailconf::path_webtxt = &pnp_environment::get('PNP_WEB_TXT');

  %emailconf::email_fields = ();
  %emailconf::file_list = ();
  $emailconf::path_email_root = "$emailconf::path_web/admin/emailconf/";
  $emailconf::path_help_root = "$emailconf::path_web/new_docs/";
  $emailconf::path_to_cgi = $ENV{'SCRIPT_NAME'}; # "index.cgi";
  $emailconf::path_to_export = "export.cgi";

  # DWW 10/24/2005 put in to eliminate XSS
  $emailconf::query{'subject'} =~ s/[^a-zA-Z0-9\.\,\-\s\t\[\]\_\'\&\/\!\*\$\?]//g;
  $emailconf::query{'description'} =~ s/[^a-zA-Z0-9\.\,\-\s\t\[\]\_'\&\/\!\*\$\?]//g;
  $emailconf::query{'testname'} =~ s/[^a-zA-Z0-9\.\,\-\s\t\[\]\_\'\&\/\!\*\$\?]//g;
  $emailconf::query{'testwhat'} =~ s/[^a-zA-Z0-9\-\_]//g;
  $emailconf::query{'testtype'} =~ s/[^a-zA-Z0-9]//g;
  $emailconf::query{'bodytype'} =~ s/[^a-zA-Z0-9]//g;
  $emailconf::query{'filelist'} =~ s/[^a-zA-Z0-9\.]//g;

  $emailconf::path_root = "$emailconf::path_webtxt/emailconf/templates/";

  $emailconf::emailuser = $ENV{"REMOTE_USER"};

  my $emailfieldfile = $emailconf::path_email_root . "email_fields.txt";

  &sysutils::filelog("read","$emailfieldfile");
  open(FIELDINFILE,"$emailfieldfile") or die "Cannot open $emailfieldfile for reading. $!";
  while (<FIELDINFILE>) {
    my ($key,$value) = split(/ /,$_);
    chop($value);
    if ($value eq "") {
      $value="none";
    }
    $emailconf::email_fields{$key} = "$value";
  }
  close(FIELDINFILE);

  $emailconf::dbh_emailconf = &miscutils::dbhconnect("emailconf");
  my $sth_init = $emailconf::dbh_emailconf->prepare(qq{
        select description,body,type
        from emailconf
        where username=?
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare $DBI::errstr\n");
  $sth_init->execute("$emailconf::emailuser") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute $DBI::errstr\n");
  while (my ($emaildescription,$emailbody,$emailtype) = $sth_init->fetchrow) {
    $emailtype = uc("$emailtype");
    $emailconf::file_list{"$emailtype\:$emaildescription"} = $emailbody;
  }
  $sth_init->finish;

  my $gatewayAccount = new PlugNPay::GatewayAccount($emailconf::emailuser);
  my $resell = $gatewayAccount->getReseller();
  my $merch_company = $gatewayAccount->getMainContact()->getCompany();

  my $accountFeatures = new PlugNPay::Features("$emailconf::emailuser",'general');
  my $features = $accountFeatures->getFeatureString();

  %emailconf::feature = ();
  $emailconf::reseller = $resell;
  if ($features ne "") {
    my @array = split(/\,/,$features);
    foreach my $entry (@array) {
      my($name,$value) = split(/\=/,$entry);
      $emailconf::feature{$name} = $value;
    }
  }

  $emailconf::merch_company = $merch_company;

  if ($emailconf::feature{'sndemail'} eq "none") {
    $emailconf::feature{'merchemail'} = "checked";
    $emailconf::feature{'custemail'} = "checked";
  }
  elsif ($emailconf::feature{'sndemail'} eq "both") {
    $emailconf::feature{'merchemail'} = "";
    $emailconf::feature{'custemail'} = "";
  }
  elsif ($emailconf::feature{'sndemail'} eq "customer") {
    $emailconf::feature{'merchemail'} = "checked";
    $emailconf::feature{'custemail'} = "";
  }
  elsif ($emailconf::feature{'sndemail'} eq "merchant") {
    $emailconf::feature{'merchemail'} = "";
    $emailconf::feature{'custemail'} = "checked";
  }

  $emailconf::dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $emailconf::dbh->prepare(qq{
       select membership,affiliate
       from pnpsetups
       where username=?
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare $DBI::errstr\n");
  $sth->execute("$emailconf::emailuser") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute $DBI::errstr\n");
  ($emailconf::recurring_flag,$emailconf::affiliate_flag) = $sth->fetchrow;
  $sth->finish;

  # for future use turned off totally right now
  $emailconf::marketing_flag = "no";

  # do this so it's easier to look up by emailtype later on
  %emailconf::typelookup = ();
  foreach my $emailkit (keys %emailconf::template_kit) {
    $emailconf::typelookup{$emailconf::template_kit{$emailkit}{"emailtype"}} = $emailkit;
  }

  # set customer options visible

  return [], $type;
}

sub Configure_Email {
  my $dbh = &miscutils::dbhconnect("pnpmisc");

  if (($emailconf::query{'custemail'} eq "no") && ($emailconf::query{'merchemail'} eq "no")) {
    $emailconf::feature{'sndemail'} = "none";
  }
  elsif ($emailconf::query{'custemail'} eq "no") {
    $emailconf::feature{'sndemail'} = "merchant";
  }
  elsif ($emailconf::query{'merchemail'} eq "no") {
    $emailconf::feature{'sndemail'} = "customer";
  }
  else {
    $emailconf::feature{'sndemail'} = "both";
  }
  if ($emailconf::query{'suppress'} eq "yes") {
    $emailconf::feature{'suppress'} = "yes";
  }
  else {
    delete $emailconf::feature{'suppress'};
  }
  if ($emailconf::query{'pubemail'} ne "") {
    $emailconf::query{'pubemail'} = substr($emailconf::query{'pubemail'},0,75);
    $emailconf::query{'pubemail'} =~ s/\;/\,/g;
    my @temp = split("\,", $emailconf::query{'pubemail'});
    $emailconf::query{'pubemail'} = $temp[0]; # limit to single email address, because of feature string limitations
    $emailconf::query{'pubemail'} =~ s/[^_0-9a-zA-Z\-\@\.]//g; # removed "," from allowed chars, because it messes up the features string
    my $position = index($emailconf::query{'pubemail'},"\@");
    my $position1 = rindex($emailconf::query{'pubemail'},"\.");
    my $elength  = length($emailconf::query{'pubemail'});
    my $pos1 = $elength - $position1;
    if (($position < 1) || ($position1 < $position) || ($position1 >= $elength - 2) || ($elength < 5) || ($position > $elength - 5)) {
      delete $emailconf::feature{'pubemail'};
      ## pubemail looks invalid
    }
    else {
      $emailconf::feature{'pubemail'} = $emailconf::query{'pubemail'};
    }
  }
  else {
    delete $emailconf::feature{'pubemail'};
  }

  my ($config_string);
  foreach my $name (keys %emailconf::feature) {
    if (($name ne "custemail") && ($name ne "merchemail")) {
      $config_string .= "$name\=$emailconf::feature{$name},";
    }
  }
  chop $config_string;
  my $accountFeatures = new PlugNPay::Features("$emailconf::emailuser",'general');
  $accountFeatures->parseFeatureString($config_string);
  $accountFeatures->saveContext();
}

sub Update_Rule {
  # set function scoped variables from $emailconf package variables
  my $status = updateEmail({
    templateType => $emailconf::query{'template_type'},
    timeUnit => $emailconf::query{'timechunk'},
    timeUnitQuantity => $emailconf::query{'timequantity'},
    contentType => $emailconf::query{'bodytype'},
    description => $emailconf::query{'description'},
    subject => $emailconf::query{'subject'},
    content => $emailconf::query{'email_confirmation'},
    emailId => $emailconf::query{'emailbody'},
    gatewayAccount => $emailconf::emailuser,
    all => $emailconf::query{'all'},
    fileLink => $emailconf::query{'filelink'},
    tests => {
      what => $emailconf::query{'testwhat'},
      type => $emailconf::query{'testtype'},
      name => $emailconf::query{'testname'}
    },
    otherFields => \%emailconf::query
  });

  if (!$status) {
    print $status->getError() . "<br>";
  } else {
    &Close_Window();
  }
}

# old "Update_Rule" sub with the UI stuff removed.
sub updateEmail {
  my $input = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $templateType = $input->{'templateType'};
  my $timeUnit = $input->{'timeUnit'};
  my $timeUnitQuantity => $input->{'timeUnitQuantity'};
  my $contentType = $input->{'contentType'} || fail('contentType is required');
  my $subject = $input->{'subject'};
  my $description = $input->{'description'} || '';
  my $content = $input->{'content'} || fail('content is required');
  my $emailId = $input->{'emailId'} || fail('emailId is required');
  my $gatewayAccount = $input->{'gatewayAccount'} || fail('gatewayAccount is required');
  my $tests = $input->{'tests'};
  my $otherFields = $input->{'otherFields'};
  my $fileLink => $input->{'fileLink'};
  my $all = $input->{'all'};

  # if the email body is over 60K we barf
  if (length($content) > 60500) {
    $status->setFalse();
    $status->setError('Email body too long');
    return $status;
  }

  $content =~ s/\r\n/\n/g;

  my $ruleData = calculateEmailData({
    templateType => $templateType,
    all => $all,
    timeUnit => $timeUnit,
    subject => $subject,
    tests => $tests,
    otherFields => $otherFields,
    fileLink => $fileLink
  });

  my $emailtype = $ruleData->{'emailType'} || fail('failed to derive emailType') ;
  my $emaildelay = $ruleData->{'emailDelay'} || '';
  my $emailinclude = $ruleData->{'emailInclude'} || '';
  my $emailexclude= $ruleData->{'emailExclude'} || '';
  my $emailweight = $ruleData->{'emailWeight'} || ''; # heavy

  eval {
    updateEmailDb({
      emailType => $emailtype,
      delay => $emaildelay,
      include => $emailinclude,
      exclude => $emailexclude,
      description => $description,
      contentType => $contentType,
      content => $content,
      emailId => $emailId,
      gatewayAccount => $gatewayAccount
    });
  };

  if ($@) {
    $status->setError('Failed to update email in database');
    $status->setFalse();
  }

  return $status;
}

sub calculateEmailData {
  my $input = shift;

  my $templateType = $input->{'templateType'};
  my $timeUnit = $input->{'timeUnit'};
  my $timeUnitQuantity = $input->{'timeUnitQuantity'};
  my $subject = $input->{'subject'};
  my $otherFields = $input->{'otherFields'};
  my $fileLink = $input->{'fileLink'};
  my $tests = $input->{'tests'};
  my $all = $input->{'all'};

  my $emailtype="";
  my $emaildelay="";
  my $emailinclude = "";
  my $emailexclude="";
  my $emailweight = "";

  if ($templateType eq 'marketing') {
    $emailtype="mark";
    $emaildelay = $timeUnitQuantity . "," .$timeUnit;
    my @srch_fields = ("startmon","startday","startyear","endmon","endday","endyear","srchmorderid","srchmodel","srchlowamt","srchhighamt","srchcity","srchstate","srchzip","srchacctcode","filelink");
    my @weight_fields = ("weightmorderid","weightmodel","weightamt","weightcity","weightstate","weightzip","weightacctcode");
    $emailinclude = "\"subject=$subject\"\,";

    if ($all ne "yes") {
      foreach my $field (@srch_fields) {
        if ($otherFields->{$field} ne "") {
          $emailinclude .= '"' . $field . '=' . $otherFields->{$field} . '",';
        }
      }
      foreach my $field (@weight_fields) {
        if ($otherFields->{$field} ne "") {
          $emailweight .= '"'. $field . '=' . $otherFields->{$field} . '",';
        }
      }
    }
    else {
      $emailinclude .= "\"all=checked\",";
      if ($fileLink ne "None") {
        $emailinclude .= '"filelink=' . $fileLink . '",';
      }
    }

    chop $emailinclude;
    chop $emailweight;
    $emailexclude="none";
  }
  else {
    my $emailkit = $emailconf::template_kit{$templateType}; # global hash, this is ok
    $emailtype = $emailkit->{"emailtype"};
    $emaildelay = $emailkit->{"emaildelay"};
    $emailexclude = $emailkit->{"emailexclude"};

    $emailinclude = createEmailInclude($tests->{'what'},$tests->{'type'},$tests->{'name'},$subject);
  }

  return {
    emailType => $emailtype,
    emailDelay => $emaildelay,
    emailInclude => $emailinclude,
    emailExclude => $emailexclude,
    emailWeight => $emailweight # not used by anything calling this?
  };
}

sub updateEmailDb {
  my $input = shift;

  my $emailType = $input->{'emailType'} || die('emailType is required');
  my $delay = $input->{'delay'} || '0,none';
  my $include = $input->{'include'} || '';
  my $exclude = $input->{'exclude'} || '';
  my $description = $input->{'description'} || '';
  my $contentType = $input->{'contentType'} || die('contentType is required'); # called emailtype in the database
  my $content = $input->{'content'} || die('content is required');             # called data in the database
  my $emailId = $input->{'emailId'} || die('emailId is required');             # called body in the database :woozyface:
  my $gatewayAccount = $input->{'gatewayAccount'} || die('gatewayAccount is required');

  my $query = q/
    UPDATE emailconf
    SET type=?,delay=?,include=?,exclude=?,emailtype=?,description=?,data=?
    WHERE body=?
      AND username = ?
  /;
  my $values = [$emailType,$delay,$include,$exclude,$contentType,$description,$content,$emailId,$gatewayAccount];

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('emailconf',$query,$values);
}

sub Email_Preview {
  # prints a preview of the email message out to a browser window
  # if we are coming from the main interface we need to preview a
  # file not a email_confirmation.  So we go and open file_list.
  # either way we spit all the lines into Preview_fields then set
  # default values and then do our normal find replace on what we
  # can and display the message.

  my %templatehash = ();
  my %type_hash = ('confirmation','conf','merchant','merch');

  $templatehash{'include'} = $emailconf::query{'testwhat'} . ":" . $emailconf::query{'testtype'} . ":" . $emailconf::query{'testname'} . ":" . $emailconf::query{'subject'};
  $templatehash{'type'} = $type_hash{$emailconf::query{'template_type'}};
  $templatehash{'emailtype'} = $emailconf::query{'bodytype'};
  $templatehash{'weight'} = "";
  $templatehash{'delay'} = "";
  $templatehash{'data'} = $emailconf::query{'email_confirmation'};
#  $templatehash{'data'} =~ s/\r\n/\n/g;

  my $message = emailconfutils->new(&Preview_Values);
  $message->generate_email(\%templatehash);

  print "Use the back button to get back to your email template<br>\n";
}

sub Update_Email {
  # my ($includestring,$emailtype,$delay,$emailweight,$maininsert);

  if ($emailconf::query{'filelist'} ne "") {
    $emailconf::query{'emailbody'} = $emailconf::query{'filelist'};
  }

  my $data = loadEmail({
    emailId => $emailconf::query{'filelist'},
    gatewayAccount => $emailconf::emailuser
  });

  %emailconf::query = (%emailconf::query,%{$data->{'queryData'}});

  Display_Template($data->{'content'},$data->{'queryData'}{'template_type'});
}

sub loadEmail {
  my $input = shift;

  my $emailId = $input->{'emailId'};
  my $gatewayAccount = $input->{'gatewayAccount'};

  my $data = loadEmailDb({
    emailId => $emailId,
    gatewayAccount => $gatewayAccount
  });

  $data->{'contentType'} ||= 'text'; # change type to text if contentType is undefined or empty string
  my %queryData;

  $queryData{'description'} = $data->{'description'};
  $queryData{'bodytype'} = $data->{'contentType'};

  # set up query data to add for different types of emails
  if ($data->{'emailType'} eq 'mark') {
    $queryData{'template_type'} = 'marketing';
    while ($data->{'include'} =~ m/"([^"\\]*(\\.[^"\\]*)*)",?|([^,]+),?|,/g) {
      my ($name,$value) = split(/\=/, defined($1) ? $1 :$3);
      $queryData{$name} = $value;
    }
    while ($data->{'weight'} =~ m/"([^"\\]*(\\.[^"\\]*)*)",?|([^,]+),?|,/g) {
      my ($name,$value) = split(/\=/, defined($1) ? $1 :$3);
      $queryData{$name} = $value;
    }
    ($queryData{'timequantity'},queryData{'timechunk'}) = split(/\,/,$data->{'delay'});
  } else {
    foreach my $emailkit (keys %emailconf::template_kit) {
      if ($emailconf::template_kit{$emailkit}{"emailtype"} eq $data->{'emailType'}) {
        $queryData{'template_type'} = $emailkit;
        last;
      }
    }
    ($queryData{'testwhat'},$queryData{'testtype'},$queryData{'testname'},$queryData{'subject'}) = split(/:/,$data->{'include'},4);
  }

  $data->{'queryData'} = \%queryData;
  return $data;
}

sub loadEmailDb {
  my $input = shift;

  my $emailId = $input->{'emailId'};
  my $gatewayAccount = $input->{'gatewayAccount'};

  my $dbs = new PlugNPay::DBConnection();

  # seems like excludeUrl is not used.
  my $query = q/
  SELECT
    include,
    type as emailType,
    delay,
    description,
    emailtype as contentType,
    weight,
    excludeurl as excludeUrl,
    data as content
  FROM emailconf
  WHERE body=?
    AND username = ?
  /;

  my $values = [$emailId,$gatewayAccount];

  my $result = $dbs->fetchallOrDie('emailconf',$query,$values,{});
  my $rows = $result->{'rows'};
  my $row = $rows->[0];

  return $row;
}

sub Preview_Values {
  my %email_fields = ();
  my %query = ();
  my %result = ();

  $query{'merchant'} = $emailconf::emailuser;
  $query{'publisher-name'} = $emailconf::emailuser;
  $query{'order-id'} = "Your orderid here";
  $query{'merchantid'} = "Email Preview";
  $query{'card-name'} = "John Smith";
  $query{'card-address1'} = "123 Smith St.";
  $query{'card-address2'} = "Suite 2a";
  $query{'card-city'} = "Haupauge";
  $query{'card-state'} = "NY";
  $query{'card-zip'} = "11788";
  $query{'card-country'} = "USA";
  $query{'card-province'} = "Quebec";
  $query{'shipname'} = "John Smith";
  $query{'address1'} = "123 Smith St.";
  $query{'address2'} = "Suite 2a";
  $query{'city'} = "Haupauge";
  $query{'state'} = "NY";
  $query{'zip'} = "11788";
  $query{'country'} = "USA";
  $query{'province'} = "Quebec";
  $query{'shipping'} = "\$4.00";
  $query{'subtotal'} = "\$20.00";
  $query{'total'} = "\$25.00";
  $query{'tax'} = "\$1.00";
  $query{'card-number'} = "4111111111111111";
  $query{'orderID'} = "1234567890123456";
  $query{'card-amount'} = "\$24.00";
  $query{'INT_to_email'} = $emailconf::query{'merchantemailaddress'};
  $query{'INT_from_email'} = $emailconf::query{'merchantemailaddress'};
  $query{'INT_email_subject'} = $emailconf::query{'subject'};
  $query{'extra_field'} = "an extra field";
  $result{'FinalStatus'} = "success";

  $email_fields{'query'} = \%query;
  $email_fields{'result'} = \%result;
  $email_fields{'feature'} = \%emailconf::feature;
  $email_fields{'reseller'} = $emailconf::reseller;

  return \%email_fields;
}

sub Display_Help {
  my $helpinsert = "";
  my $helpfile = $emailconf::path_help_root . "Email_Management.htm";
  &Display_Template_help($helpfile,$helpinsert,"noparse");
}

sub Get_Values {
  &html_head();

  print "<form name=\"GETFORM\" method=\"post\" action=\"$emailconf::path_to_cgi\">\n";

  print "<table cellpadding=\"4\" cellspacing=\"0\" border=\"0\">\n";
  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp;<br>Configure Email</td>\n";
  print "    <td class=\"menurightside\">\n";

  print "<table border=0 cellspacing=0 cellpadding=2>\n";
  print "  <tr>\n";
  print "    <td><input type=\"checkbox\" name=\"custemail\" value=\"no\" $emailconf::feature{'custemail'}>\n";
  print "Check to disable sending of confirming emails to customer on purchase.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><input type=\"checkbox\" name=\"merchemail\" value=\"no\" $emailconf::feature{'merchemail'}>\n";
  print "Check to disable sending of confirming emails to yourself on purchase.</td>\n";
  print "  </tr>\n";
  my (%selected);
  $selected{'yes'} = "checked";
  print "  <tr>\n";
  print "    <td><input type=\"checkbox\" name=\"suppress\" value=\"yes\" $selected{$emailconf::feature{'suppress'}}>\n";
  print "Check to suppress blank lines when substitution variables are empty.</td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <td><b>Default email address for Merchant Confirmations.</b>\n";
  print "<br>Only used when 'publisher-email' variable is NOT sent with transaction data.\n";
  print "<br><input type=\"text\" name=\"pubemail\" value=\"$emailconf::feature{'pubemail'}\" size=\"40\" maxlength=\"75\">\n";
  print "<br><i>Enter single email address only.</i></td>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<input type=\"submit\" class=\"button\" name=\"function\" value=\"Configure Email\">\n";

  print "    </td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\"><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Create New Mailing Rules</td>\n";
  print "    <td class=\"menurightside\">Template: <select name=\"template_type\">\n";

  foreach my $emailkit (keys %emailconf::template_kit) {
    if ($emailconf::template_kit{$emailkit}{"visible"}) {
      print "<option value=\"" . $emailkit . "\">" . $emailconf::template_kit{$emailkit}{"htmlname"} . "</option>\n";
    }
  }

  print "</select>\n";
  print "<p><input type=\"submit\" class=\"button\" name=\"function\" value=\"New Template\" onClick=\"op(\'$emailconf::path_to_cgi\',\'CreateWindow\',650,550);\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\"><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">Manage Current Mailing Rules</td>\n";
  print "    <td class=\"menurightside\">Template: <select name=\"filelist\" size=1>\n";
  foreach my $key (sort keys %emailconf::file_list) {
      # Was: print "<option value=\"$emailconf::file_list{$key}\">$key\n";
      my @temp = split(/\:/, $key, 2);
      print "<option value=\"$emailconf::file_list{$key}\">$temp[0]\: $temp[1]</option>\n";
    }
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp</td>\n";
  print "    <td class=\"menurightside\"><input type=\"submit\" class=\"button\" name=\"function\" value=\"Delete\" onClick=\"return delete_confirm();\">\n";
  print " <input type=\"submit\" class=\"button\" name=\"function\" value=\"Edit\" onClick=\"op(\'$emailconf::path_to_cgi\',\'EditWindow\',700,550);\"></td>\n";
  print "  </tr>\n";

  print "</form>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\"><hr width=80%></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\"><form action=\"$emailconf::path_to_export\" method=\"post\" target=\"ExportWindow\">\n";
  print "<input type=\"submit\" class=\"button\" name=\"function\" value=\"Export Templates\" onClick=\"op(\'$emailconf::path_to_export\',\'ExportWindow\',700,550);\"></td></form>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\">&nbsp;</td>\n";
  print "    <td class=\"menurightside\"><form action=\"$emailconf::path_to_cgi\" method=\"post\" target=\"onlinehelp\">\n";
  print "<input type=\"submit\" class=\"button\" name=\"function\" value=\"Help\" onClick=\"onlinehelp();\"></td></form>\n";
  print "  </tr>\n";

  print "</table>\n";

  &html_tail();
  return;
}

sub Delete_Email {
  if ($emailconf::query{'filelist'} ne "") {
    eval {
      deleteEmailDb({
        emailId => $emailconf::query{'filelist'},
        gatewayAccount => $emailconf::emailuser
      });
    };
    if ($@) {
      die_metadata([$@],{
        emailId => $emailconf::query{'filelist'},
        gatewayAccount => $emailconf::emailuser
      });
    }
  }
  else {
    print "DELETE ERROR NO TEMPLATE<br>\n";
  }
}

sub deleteEmailDb {
  my $input = shift;

  my $emailId = $input->{'emailId'};
  my $gatewayAccount = $input->{'gatewayAccount'};

  my $query = q/
  DELETE FROM emailconf
  WHERE body=?
    AND username = ?
  /;

  my $values = [$emailId,$gatewayAccount];

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('emailconf',$query,$values);
}

sub Create_Email {
  my $createinsert = "";

  my $emailkit = $emailconf::template_kit{$emailconf::query{'template_type'}};
  $createinsert = $emailconf::path_root . $emailkit->{'file'};

  my $body_data = "";
  &sysutils::filelog("read","$createinsert");
  open(INFILE,"$createinsert") or die "Cannot open $createinsert for reading. $!";
  while (<INFILE>) {
    $body_data .= $_;
  }
  close(INFILE);

  &Display_Template($body_data,$emailconf::query{'template_type'});
}

sub Display_Template {
  my ($body_data,$template_type) = @_;

  &html_head("Edit Email Template");

  print "<form method=\"post\" action=\"$emailconf::path_to_cgi\">\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"2\">\n";
  print "  <tr>\n";
  print "    <td class=\"menuleftside\">\&nbsp;</td>\n";
  print "    <td class=\"menurightside\">\n";
  if ($emailconf::query{'createtype'} eq "update") {
    print "<input type=\"submit\" class=\"button\" name=\"function\" value=\"Update Rule\">\n";
  }
  else {
    print "<input type=\"submit\" class=\"button\" name=\"function\" value=\"Submit\">\n";
  }
  print "<input type=\"button\" class=\"button\" name=\"reset\" value=\"Forget Changes\" onClick=\"window.close()\">\n";
  print "<input type=\"button\" class=\"button\" value=\"Help\" onClick=\"change_win('$emailconf::path_to_cgi\?function\=Help',600,500,'onlinehelp')\">\n";
  print "<input type=\"submit\" class=\"button\" name=\"function\" value=\"Email Preview\">\n";
  print "<input type=\"text\" name=\"merchantemailaddress\" size=12 maxlength=40 value=\"\">\n";

  print "<input type=\"hidden\" name=\"template_type\" value=\"$emailconf::query{'template_type'}\">\n";
  print "<input type=\"hidden\" name=\"createtype\" value=\"$emailconf::query{'createtype'}\">\n";
  print "<input type=\"hidden\" name=\"emailbody\" value=\"$emailconf::query{'emailbody'}\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=Description\&section=emailconf\',300,200)\">Description</a></td>\n";
  print "    <td class=\"menurightside\"><input type=\"text\" name=\"description\" maxlength=16 size=16 value=\"$emailconf::query{'description'}\"></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=Email%20Subject\&section=emailconf\',300,200)\">Email Subject</a></td>\n";
  print "    <td class=\"menurightside\"><input type=text name=\"subject\" size=\"64\" maxlength=\"64\" value=\"$emailconf::query{'subject'}\"></td>\n";
  print "  </tr>\n";

  if (($emailconf::query{'template_type'} ne "affiliate_signup") && ($emailconf::query{'template_type'} ne "ecard_reg_link")) {
    print "  <tr>\n";
    print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=Select%20Rule\&section=emailconf\',300,200)\">Select Rule</a></td>\n";
    print "    <td class=\"menurightside\"><select name=\"testwhat\">\n";
    foreach my $option (@emailconf::testwhat) {
      print "<option value=\"$option\" ";
      if ($option eq $emailconf::query{'testwhat'}) {
        print "selected";
      }
      print "> $option </option>\n";
    }
    print "</select>\n";
    print " is ";
    print "<select name=\"testtype\">\n";
    $emailconf::query{'testtype'} ||= 'none'; # default
    foreach my $key (keys %emailconf::testtype) {
      print "<option value=\"$key\" ";
      if ($key eq $emailconf::query{'testtype'}) {
        print "selected";
      }
      print "> $emailconf::testtype{$key} </option>\n";
    }
    print "</select> \n";
    print "<input type=\"text\" name=\"testname\" value=\"$emailconf::query{'testname'}\" maxlength=45 size=16></td>\n";
    print "  </tr>\n";
  }

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=Email%20Body%20Type\&section=emailconf\',300,200)\">Email Body Type</a></td>\n";
  print "    <td class=\"menurightside\"><select name=\"bodytype\">\n";
  print "<option value=\"text\" ";
  if ($emailconf::query{'bodytype'} eq "text") {
    print "selected";
  }
  print "> text body</option>\n";
  print "<option value=\"html\" ";
  if ($emailconf::query{'bodytype'} eq "html") {
    print "selected";
  }
  print "> html body</option>\n";
  print "</select></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td class=\"menuleftside\"><a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=Message\&section=emailconf\',300,200)\">Message</a></td>\n";
  print "    <td class=\"menurightside\" colspan=4><textarea Cols=72 ROWS=16 name=\"email_confirmation\">$body_data</textarea></td>\n";
  print "  </tr>\n";
  print "</table>\n";

  print "</form>\n";

  &html_tail();
  return;
}

sub Create_Rule {
  if (length($emailconf::query{'email_confirmation'}) > 60565) {
    print "Email body too long<br>\n";
    return;
  }

  $emailconf::query{'email_confirmation'} =~ s/\r\n/\n/g;

  my ($emailinclude,$emailweight,$emaildelay,$emailexclude,$emailbody,$descriptionnumber,$emailtype,$emailsendtype);

  if ($emailconf::query{'template_type'} eq "marketing") {
    my @srch_fields = ("startmon","startday","startyear","endmon","endday","endyear","srchmorderid","srchmodel","srchlowamt","srchhighamt","srchcity","srchstate","srchzip","srchacctcode","filelink");
    my @weight_fields = ("weightmorderid","weightmodel","weightamt","weightcity","weightstate","weightzip","weightacctcode");
    $emailinclude = "\"subject=$emailconf::query{'subject'}\"\,";
    if ($emailconf::query{'all'} ne "yes") {
      foreach my $value (@srch_fields) {
        if ($emailconf::query{$value} ne "") {
          $emailinclude .= "\"$value=$emailconf::query{$value}\",";
        }
      }
      foreach my $value (@weight_fields) {
        if ($emailconf::query{$value} ne "") {
          $emailweight .= "\"$value=$emailconf::query{$value}\",";
        }
      }
    }
    else {
      $emailweight .= "\"all=checked\",";
      if ($emailconf::query{'filelink'} ne "None") {
        $emailweight .= "\"filelink=$emailconf::query{'filelink'}\",";
      }
    }
    chop $emailinclude;
    chop $emailweight;
    if ($emailconf::query{'timequantity'} eq "") {
      $emailconf::query{'timequantity'} = "1";
    }
    if ($emailconf::query{'timechunk'} eq "") {
      $emailconf::query{'timechunk'} = "day";
    }
    $emaildelay = $emailconf::query{'timequantity'} . "," .$emailconf::query{'timechunk'};
    $emailexclude = "none";
    if ($emailconf::query{'createtype'} ne "update") {
      ($emailbody,$descriptionnumber) = &Get_File_Name($emailconf::emailuser,"mark");
    }
    $emailtype = "mark";
    $emailsendtype = $emailconf::query{'bodytype'};
  }
  else {
    my $emailkit = $emailconf::template_kit{$emailconf::query{'template_type'}};
    ($emailbody,$descriptionnumber) = &Get_File_Name($emailconf::emailuser,$emailkit->{"emailtype"});
    if ((! $emailkit->{"multiple"}) && ($descriptionnumber > 0)) {
      # 666 possibly return a little more nicely here
      print "This template type can only have one template at any time.  Please delete your old template before adding a new one.<br>\n";
      return;
    }
    $emaildelay = $emailkit->{"emaildelay"};
    $emailtype = $emailkit->{"emailtype"};
    $emailexclude = $emailkit->{"emailexclude"};
    $emailweight = $emailkit->{"emailweight"};
    $emailsendtype = $emailconf::query{'bodytype'};
    if ($emailconf::query{'description'} eq "") {
      $emailconf::query{'description'} = $emailkit->{"description"};
    }
    $emailconf::query{'description'} = $emailconf::query{'description'} . " " . $descriptionnumber;

    $emailinclude = createEmailInclude($emailconf::query{'testwhat'},$emailconf::query{'testtype'},$emailconf::query{'testname'},$emailconf::query{'subject'});
  }

  # insert template
  my $sth_createrule = $emailconf::dbh_emailconf->prepare(qq{
    insert into emailconf
    (username,type,delay,include,exclude,body,emailtype,description,weight,excludeurl,data)
    values (?,?,?,?,?,?,?,?,?,?,?)
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare $DBI::errstr\n");
  $sth_createrule->execute("$emailconf::emailuser","$emailtype","$emaildelay","$emailinclude","$emailexclude","$emailbody","$emailsendtype","$emailconf::query{'description'}","$emailweight","$emailconf::query{'exclude_url'}","$emailconf::query{'email_confirmation'}") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute $DBI::errstr\n");
  $sth_createrule->finish;

  &Close_Window();
}

sub Close_Window {
  print "<HTML>\n";
  print "<HEAD>\n";
  print "<TITLE> Close Window</TITLE>\n";
  print "</HEAD>\n";
  print "<SCRIPT LANGUAGE=\"Javascript1.2\">\n";
  print "//<!--\n";
  print "  function close_window(a) {\n";
  print "    window.opener.location = a;\n";
  print "    window.close();\n";
  print "  }\n";
  print "//-->\n";
  print "</SCRIPT>\n";
  print "<BODY onload=\"close_window(\'$emailconf::path_to_cgi\');\">\n";
  print "</BODY>\n";
  print "</HTML>\n";
}

sub Display_Template_help {
  # watch for infinite loop when parsing helpfile
  my ($filetooutput,$filetoinsert,$parseflag) = @_;

  my $key;
  my $loopcount = 0;
  my ($replacefield);

  &sysutils::filelog("read","$filetooutput");
  open (MAININFILE,"$filetooutput") or die "Cannot open $filetooutput for reading. $!";
  while (<MAININFILE>) {
    if ($parseflag eq "noparse") {
      print $_;
    }
    else {
      # named the loop so next and last make more sense
      HTMLLINE: while (/\[email_.*|\[help_.*/) {
        $loopcount += 1;
        if ($loopcount >= 10) {
          last HTMLLINE;
        }
        if (/\[email_confirmation\]/) {
          if ($parseflag eq "nomaininsert") {
            $_ = "";
            $_ = $filetoinsert;
            last HTMLLINE;
          }
          else {
            foreach my $key (keys %emailconf::email_fields) {
              if ($filetoinsert =~ /$key/) {
                $filetoinsert =~ s/\[$key\]/$emailconf::email_fields{$key}/;
              }
            }
            $_ = $filetoinsert;
            last HTMLLINE;
          }
        }
        elsif (/\[email_filedropdown\]/) {
          print "<select name=\"filelist\" size=1>\n";
          foreach my $key (keys %emailconf::file_list) {
            # Was: print "  <option value=$emailconf::file_list{$key}>$key</option>\n";
            my @temp = split(/\:/, $key, 2);
            print "<option value=\"$emailconf::file_list{$key}\">$temp[1]</option>\n";
          }
          print "</select>\n";
          $_ = "";
        }
        elsif (/\[email_linkdropdown\]/) {
          print "<select name=\"filelink\" size=1>\n";
          print "  <option value=\"None\">None</option>\n";
          foreach my $key (keys %emailconf::file_list) {
            if ($emailconf::query{'filelink'} eq $emailconf::file_list{$key}) {
              # Was: print "  <option value=$emailconf::file_list{$key} selected>$key\n";
              my @temp = split(/\:/, $key, 2);
              print "<option value=\"$emailconf::file_list{$key}\" selected>$temp[1]</option>\n";
            }
            else {
              # Was: print "  <option value=$emailconf::file_list{$key}>$key\n";
              my @temp = split(/\:/, $key, 2);
              print "<option value=\"$emailconf::file_list{$key}\">$temp[1]</option>\n";
            }
          }
          print "</select>\n";
          $_ = "";
        }
        elsif (/\[email_hiddenfile\]/) {
          print "<input type=\"hidden\" name=\"filelist\" value=\"$emailconf::query{'filelist'}\">";
          $_ = "";
        }
        elsif (/\[email_select_([^\W]*)\]/) {
          $replacefield = $1;
          if (($_ =~ /$emailconf::query{$replacefield}/) && ($emailconf::query{$replacefield} ne "")) {
            $_ =~ s/\[email_select_$replacefield\]/selected/;
          }
          else {
            $_ =~ s/\[email_select_$replacefield\]//;
          }
        }
        elsif (/\[email_value_([^\W]*)\]/) {
          $replacefield = $1;
          if ($emailconf::query{$replacefield} ne "") {
            $_ =~ s/\[email_value_$replacefield\]/$emailconf::query{$replacefield}/;
          }
          else {
            $_ =~ s/\[email_value_$replacefield\]//;
          }
        }
        elsif (/\[email_merchant_name\]/) {
          $_ =~ s/\[email_merchant_name\]/$emailconf::emailuser/;
        }
        elsif (/\[help_(.*)\]/) {
          my $helpstring = $1;
          my $urlencodedtopic = $1;
          $urlencodedtopic =~ s/(\W)/'%' . unpack("H2",$1)/ge;
          my $replacementstring = "<a href=\"javascript:help_win(\'/admin/fthelp.cgi?topic=$urlencodedtopic\&section=emailconf\',300,200)\">$helpstring</a>";
          $_ =~ s/\[help_$helpstring\]/$replacementstring/;
        }
      }
      print $_;
      $loopcount = 0;
    }
  }
  close(MAININFILE);
}

sub Get_File_Name {
  # sub to get new file name to create next email message
  # need to pass it username and file type
  my ($fileuser,$filetype) = @_;

  my ($body,$new_filename,$new_number);
  my @body_array = ();

  my $sth_file = $emailconf::dbh_emailconf->prepare(qq{
      select body
      from emailconf
      where username=? and type=?
      order by body
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare $DBI::errstr\n");
  $sth_file->execute("$fileuser","$filetype") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute $DBI::errstr\n");
  $sth_file->bind_columns(undef,\($body));
  while ($sth_file->fetch) {
    $body_array[++$#body_array] = $body;
  }

  if ($#body_array == -1) {
    $new_filename = $fileuser . $filetype . "0.msg";
    $new_number = 0;
  }
  else {
    my $max = 0;
    for (my $i=0; $i<=$#body_array; $i++) {
      $body_array[$i] =~ s/$fileuser//;
      $body_array[$i] =~ s/$filetype//;
      $body_array[$i] =~ s/\.msg//;
      if ($body_array[$i] > $max) {
        $max = $body_array[$i];
      }
    }
    $new_number = $max+1;

    $new_filename = $fileuser . $filetype . $new_number . ".msg";
  }

  return($new_filename,$new_number);
}

sub createEmailInclude {
  my ($what,$type,$name,$subject) = @_;
  my $include = "";
  if (($what eq "") && ($type eq "") && ($name eq "") && ($subject eq "")) {
    $include = "none";
  }
  else {
    $include = $what . ":" . $type . ":" . $name . ":" . $subject;
  }
  return $include;
}

sub Export_Templates {
  my @templates = ();

  my $sth = $emailconf::dbh_emailconf->prepare(qq{
          select type, include, emailtype, description, data
          from emailconf
          where username=?
  });
  $sth->execute("$emailconf::emailuser");
  while (my $data = $sth->fetchrow_hashref) {
    $templates[++$#templates] = $data;
  }
  $sth->finish;

  foreach my $template (@templates) {
    my ($test, $field, $value, $subject) = split(/:/, $template->{'include'}, 4);
    print "Template Type: " . $emailconf::typelookup{$template->{'type'}} . "\n";
    print "Description: " . $template->{'description'} . "\n";
    print "Subject: " . $subject . "\n";
    print "Rule: " . $field . " " . $emailconf::testtype{$test} . " " . $value . "\n";
    print "Body Type: " . $template->{'emailtype'} . "\n";
    print "Body:\n" . $template->{'data'} . "\n";
    print "\n\n\n\n";
  }
}

sub html_head {
  my ($title) = @_;

  print "<html>\n";
  print "<head>\n";
  print "<title>Email Management</title>\n";
  print "<link href=\"/css/style_emailmgt.css\" type=\"text/css\" rel=\"stylesheet\">\n";

  # js logout prompt
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery_ui/jquery-ui.min.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/javascript/jquery_cookie.js\"></script>\n";
  print "<script type=\"text/javascript\" charset=\"utf-8\" src=\"/_js/admin/autologout.js\"></script>\n";
  print "<link rel=\"stylesheet\" type=\"text/css\" href=\"/javascript/jquery_ui/jquery-ui.css\">\n";

  print "<script type='text/javascript'>\n";
  print "       /** Run with defaults **/\n";
  print "       \$(document).ready(function(){\n";
  print "         \$(document).idleTimeout();\n";
  print "        });\n";
  print "</script>\n";
  # end logout js

  print "<script Language=\"Javascript\">\n";
  print "//<!-- Start Script\n";

  print "function op(pageurl,mytarget,swidth,sheight) {\n";
  print "  document.GETFORM.target = mytarget;\n";
  print "  open(pageurl,mytarget,\'scrollbars=yes,resizable=yes,toolbar=yes,menubar=yes,height=\'+sheight+\',width=\'+swidth);\n";
  print "}\n";

  print "function delete_confirm() {\n";
  print "  return confirm('Are you sure you want to delete this?');\n";
  print "}\n";

  print "function onlinehelp() {\n";
  print "  onlinehelp = window.open('','onlinehelp','width=600,height=400,toolbar=no,location=no,directories=no,status=yes,menubar=yes,scrollbars=yes,resizable=yes');\n";
  print "  if (window.focus) { onlinehelp.focus(); }\n";
  print "  return false;\n";
  print "}\n";

  print "function popminifaq() {\n";
  print "  minifaq = window.open('/admin/wizards/faq_board.cgi\?mode=mini_faq_list\&category=all\&search_keys=QA20021125164736,QA20031121185335','minifaq','width=600,height=400,toolbar=no,location=no,directories=no,status=yes,menubar=yes,scrollbars=yes,resizable=yes');\n";
  print "  if (window.focus) { minifaq.focus(); }\n";
  print "  return false;\n";
  print "}\n";

  print "function help_win(helpurl,swidth,sheight) {\n";
  print "  SmallWin = window.open(helpurl, \'HelpWindow\',\'scrollbars=yes,resizable=yes,toolbar=no,menubar=no,height=\'+sheight+\',width=\'+swidth);\n";
  print "}\n";

  print "function change_win(helpurl,swidth,sheight,windowname) {\n";
  print "  SmallWin = window.open(helpurl, windowname,'scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);\n";
  print "}\n";

  print "function closewin() {\n";
  print "  self.close();\n";
  print "}\n";

  print "//-->\n";
  print "</script>\n";

  #print "<META HTTP-EQUIV=\"Expires\" CONTENT=\"Mon, 01 Jan 2000 01:00:00 GMT\">\n";
  print "</head>\n";

  print "<body bgcolor=\"#ffffff\">\n";

  print "<table width=\"760\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\" id=\"header\">\n";
  print "  <tr>\n";
  print "    <td colspan=\"3\" align=\"left\">";
  if ($ENV{'SERVER_NAME'} =~ /plugnpay\.com/i) {
    print "<img src=\"/images/global_header_gfx.gif\" width=\"760\" alt=\"Plug 'n Pay Technologies - we make selling simple.\" height=\"44\" border=\"0\">";
  }
  else {
    print "<img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Logo\">\n";
  }
  print "</td>\n";
  print "  </tr>\n";

  if ($security::reseller !~ /(webassis)/) {
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
  print "    <td colspan=\"2\"><h1><a href=\"$ENV{'SCRIPT_NAME'}\">Email Management</a>";
  if ($title ne "") {
    print " / $title";
  }
  print " - $emailconf::merch_company</h1>\n";
}

sub html_tail {

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


1;
