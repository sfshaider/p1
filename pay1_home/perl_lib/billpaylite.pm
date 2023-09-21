package billpaylite;

use strict;
use pnp_environment;
use scrubdata;
use miscutils;
use language qw(%lang_titles);
use PlugNPay::Features;
use PlugNPay::WebDataFile;
use PlugNPay::Sys::Time;
use PlugNPay::API::REST::Session;
use PlugNPay::PayScreens::Assets;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  %billpaylite::query = @_;

  %billpaylite::template = ();

  my ($fconfig,%fraud_config);

  if (($billpaylite::query{'convert'} eq 'underscores') && ($billpaylite::query{'publisher_name'} ne "") && ($billpaylite::query{'publisher-name'} eq "")) {
    $billpaylite::query{'publisher-name'} = $billpaylite::query{'publisher_name'};
  }

  $billpaylite::query{'publisher-name'} =~ s/[^0-9a-zA-Z]//g;
  $billpaylite::query{'publisher-name'} = substr($billpaylite::query{'publisher-name'},0,12);
  my $gatewayAccountUsername = $billpaylite::query{'publisher-name'};

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(qq{
        select
          fraud_config,
          reseller,
          company,
          addr1,
          addr2,
          city,
          state,
          zip,
          country,
          tel
        from customers
        where username=?
        }) or die "Can't do: $DBI::errstr";
  $sth->execute($gatewayAccountUsername) or die "Can't execute: $DBI::errstr";
  (
    $fconfig,
    $billpaylite::reseller,
    $billpaylite::query{'dbcompany'},
    $billpaylite::query{'receipt-address1'},
    $billpaylite::query{'receipt-address2'},
    $billpaylite::query{'receipt-city'},
    $billpaylite::query{'receipt-state'},
    $billpaylite::query{'receipt-zip'},
    $billpaylite::query{'receipt-country'},
    $billpaylite::query{'receipt-phone'}
  ) = $sth->fetchrow;
  $sth->finish;

  $billpaylite::reseller =~ s/[^0-9a-zA-Z]//g;

  my $sth2 = $dbh->prepare(qq{
        select company
        from privatelabel
        where username=?
        });
  $sth2->execute("$billpaylite::reseller");
  ($billpaylite::company) = $sth2->fetchrow;
  $sth2->finish;

  $dbh->disconnect;

  my $accountFeatures = new PlugNPay::Features($gatewayAccountUsername,'general');
  my $f = $accountFeatures->getFeatures();
  $billpaylite::feature = %{$f};

  my $apiSessionId = '';
  my $bplApiSessionFeature = $accountFeatures->get('bplApiSession');
  if ($bplApiSessionFeature) {
    my $apiSession = new PlugNPay::API::REST::Session();
    if ($bplApiSessionFeature eq 'multi') {
      $apiSession->setMultiUse();
    }
    my $expireTime = new PlugNPay::Sys::Time();
    $expireTime->addMinutes(5);
    my $expirationTimeString = $expireTime->inFormat('db');
    $apiSession->setExpireTime($expirationTimeString);
    $apiSessionId = $apiSession->generateSessionID($gatewayAccountUsername);
  }
  $billpaylite::query{'api_session_id'} = $apiSessionId;

  my $plAccountFeatures = new PlugNPay::Features("$billpaylite::reseller",'general');
  $billpaylite::pl_features = $plAccountFeatures->getFeatureString();

  if ($billpaylite::pl_features =~ /(.*)=(.*)/) {
    my @array = split(/\,/,$billpaylite::pl_features);
    foreach my $entry (@array) {
      my($name,$value) = split(/\=/,$entry);
      $billpaylite::pl_feature{$name} = $value;
    }
  }

  my $path_web = &pnp_environment::get('PNP_WEB');
  my $pay_template_home = "$path_web/admin/templates/billpaylite";
  my $username = $billpaylite::query{'publisher-name'};
  $username =~ s/[^0-9a-zA-Z]//g;

  my $paytemplate = $billpaylite::query{'paytemplate'} || $billpaylite::query{'pt'};
  $paytemplate =~ s/[^0-9a-zA-Z\_]//g;

  my $cobrand = $accountFeatures->get('cobrand');
  $cobrand =~ s/[^0-9a-zA-Z\-\_]//g;

  my $bpltemplate = $accountFeatures->get('bpltemplate');
  $bpltemplate =~ s/[^0-9a-zA-Z\-\_]//g;

  my $loadedTemplate;
  if ($paytemplate) {
    $loadedTemplate = &loadWebDataFile($username . '_' . $paytemplate . '.txt');
  }

  if (!$loadedTemplate) {
    if ($billpaylite::feature{'bpltemplate'}) {
      $loadedTemplate = &loadWebDataFile($bpltemplate);
    } else {
      $loadedTemplate = &findBPLTemplate({
        username => $username,
        cobrand => $cobrand,
        reseller => $billpaylite::reseller
      });
    }

    if (!$loadedTemplate && $paytemplate =~ /^default_/) {
      $loadedTemplate = &loadWebDataFile($paytemplate. '.txt');
    }
  }

  if (defined $billpaylite::query{'validDelimiter'} && !$billpaylite::query{'validDelimiter'}) {
    # show unconfigured response, if template does not exist
    my $response = &unconfigured(1);
    print $response;
    return;
  }
  delete $billpaylite::query{'validDelimiter'};

  unless (defined $loadedTemplate) {
    # show unconfigured response, if template does not exist
    my $response = &unconfigured();
    print $response;
    return;
  }

  my (%tempflag,$tempflag);
  foreach my $line (split("\n", $loadedTemplate)) {
    if ($line =~ /<(language|head|top|body|tail|page)>/i) {
      if (($tempflag eq "") ) {
        $tempflag = $1;
        $tempflag =~ tr/A-Z/a-z/;
        next;
      }
    }
    if ($line =~ /<\/$tempflag>/i) {
      $tempflag = "";
      next;
    }
    if ($tempflag eq "language") {
        my ($key,$value) = split('\t');
        $billpaylite::lang_titles{$key}[$billpaylite::lang] = $value;
    } elsif ($tempflag =~ /^(head|top|body|tail|page)$/) {
      $billpaylite::template{$tempflag} .= &parse_template("$line") . "\n";
    }
  }

  my $psa = new PlugNPay::PayScreens::Assets();
  my $assetsMigratedTemplate = $psa->migrateTemplateAssets({
    username => $username,
    templateSections => \%billpaylite::template
  });
  %billpaylite::template = %{$assetsMigratedTemplate};

  foreach my $key (keys %billbaylite::template) {
    print "$billpaylite::template{$key}\n";
  }
  return $self;
}

sub loadWebDataFile {
  my $templateFileName = shift;
  my $loadedTemplate;
  my $templatePath = &pnp_environment::get('PNP_WEB') . '/admin/templates/billpaylite';
  $templatePath =~ s/\/p\//\//;
  my $fileManager = new PlugNPay::WebDataFile();
  my $template = $fileManager->readFile({
    'localPath' => $templatePath,
    'fileName'  => $templateFileName
  });

  return $template;
}

sub findBPLTemplate {
  my $input = shift;

  my $username = $input->{'username'};
  my $cobrand = $input->{'cobrand'};
  my $reseller = $input->{'reseller'};

  my $accountFeatures = new PlugNPay::Features($username,'general');

  #Template specific to user
  my $template = &loadWebDataFile($username . '_template.txt');
  if ($template) {
    $accountFeatures->set('bpltemplate',$username . '_template.txt');
    $accountFeatures->saveContext();
    return $template;
  }

  #Templates specific to a subset of users
  my $subsetTempName = '';
  if (substr($username,0,3) =~ /^(ams|cyd)/) {
    $subsetTempName = "affiniscapebase_template.txt";
  } elsif(substr($username,0,2) =~ /^(lp|law|ap)/) {
    $subsetTempName = "lawpaybase_template.txt";
  }

  if ($subsetTempName) {
    $template = &loadWebDataFile($subsetTempName);
    if ($template) {
      $accountFeatures->set('bpltemplate', $subsetTempName);
      $accountFeatures->saveContext();
      return $template;
    }
  }

  #Template specific to a cobrand
  if ($cobrand) {
    my $filename = 'cobrand.' . $cobrand . '_template.txt';
    $template = &loadWebDataFile($filename);
    if ($template) {
      $accountFeatures->set('bpltemplate', $filename);
      $accountFeatures->saveContext();
      return $template;
    }
  }

  #Template specific to a reseller
  my $filename = 'reseller.' . $reseller . '_template.txt';
  $template = &loadWebDataFile($filename);
  if ($template) {
    $accountFeatures->set('bpltemplate', $filename);
    $accountFeatures->saveContext();
    return $template;
  }

  return undef;
}

sub print_launch {
  my $self = shift;
  if (exists $billpaylite::template{'page'}) {
    print "$billpaylite::template{'page'}\n";
  }
  else {
    print "$billpaylite::template{'head'}\n";
    print "$billpaylite::template{'top'}\n";
    print "$billpaylite::template{'body'}\n";
    print "$billpaylite::template{'tail'}\n";
  }
}


sub parse_template {
  my ($line) = @_;

  # for modile browser compatability
  if ($line =~ /\[mobile_head\]/) {
    if ($billpaylite::query{'client'} =~ /mobile/) {
      # for modile browser compatability
      my $mobile_head = "  <meta name=\"viewport\" content=\"width=320; initial-scale=1.0; maximum-scale=1.0; user-scalable=0;\"/>\n";
      $mobile_head .= "  <link rel=\"apple-touch-icon\" href=\"/javascript/iui/pnpicon.png\" />\n";
      $mobile_head .= "  <meta name=\"apple-touch-fullscreen\" content=\"YES\" />\n";
      $mobile_head .= "  <style type=\"text/css\" media=\"screen\">\@import \"/css/$payutils::query{'client'}/iui.css\";</style>\n";

      $line =~ s/\[mobile_head\]/$mobile_head/;
    }
    else {
      $line =~ s/\[mobile_head\]//;
    }
  }

  if ($line !~ /[\[\{]pnp_/) {
    return $line;
  }
  $line =~ s/\r\n//g;
  my $parsecount = 0;
  my $value = "";
  while ($line =~ /[\[\{]pnp\_([0-9a-zA-Z-+_]*?)[\]\}]/) {
    my $query_field = $1;
    $parsecount++;
    if ($billpaylite::query{$query_field} ne "") {
      if ($query_field =~ /^(card-number|card_number|card-exp|card_exp|accountnum|routingnum)$/) {
        $value = "FILTERED";
      } elsif ($query_field =~ /^(subtotal|tax|shipping|handling|discnt)$/) {
        $value = sprintf("%.2f", $billpaylite::query{$query_field});
      } else {
        $value = $billpaylite::query{$query_field};
      }
    } elsif ($query_field =~ /^(orderID)$/) {
      $value = $billpaylite::orderID;
    } elsif ($query_field =~ /^(HIDDEN)$/) {
      my ($hidden);
      foreach my $key (sort keys %billpaylite::query) {
        my $value = $billpaylite::query{$key};
        $value =~ s/^ +//g;
        if (($value =~ /\d+/) && (length($value) >= 13) && ($value =~ /^[3-7]/)) {
          $value =~ s/"/\\"/g;
          my @valueArray = $value =~ /(.{1,4})/g;
          $value = '["' . join('","',@valueArray) . '"]';
        }
        $hidden .= "<input type='hidden' name='$key' value=\"$value\">\n";
      }
      $line =~ s/\[pnp\_$query_field\]/$hidden/;
      next;
    } else {
      $value = "";
    }

    $line =~ s/\[pnp\_$query_field\]/$value/;

    $value =~ s/"/\\"/g;
    my @valueArray = $value =~ /(.{1,4})/g;
    $value = '["' . join('","',@valueArray) . '"]';
    $line =~ s/\{pnp\_$query_field\}/$value/;

    if ($parsecount >= 10) {
      return $line;
    }
  } # end while
  return $line;
}

sub unconfigured {
  my $self = shift;
  my $delimiterError = shift || $self;
  my $data = "";

  $data .= "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">\n";
  $data .= "<html>\n";
  $data .= "<head>\n";

  if ($delimiterError) {
    $data .= "<title>Invalid Delimiter Provided</title>\n";
  } else {
    $data .= "<title>Service Not Configured</title>\n";
  }

  if ($billpaylite::query{'client'} =~ /mobile/) {
    $data .= "<meta name=\"viewport\" content=\"width=320; initial-scale=1.0; maximum-scale=1.0; user-scalable=0;\"/>\n";
    $data .= "<link rel=\"apple-touch-icon\" href=\"/javascript/iui/pnpicon.png\" />\n";
    $data .= "<meta name=\"apple-touch-fullscreen\" content=\"YES\" />\n";
    $data .= "<style type=\"text/css\" media=\"screen\">\@import \"/css/$payutils::query{'client'}/iui.css\";</style>\n";
  } else {
    $data .= "<style type=\"text/css\">\n";
    $data .= "  th { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 75%; color: #000000 }\n";
    $data .= "  td { font-family: Arial,Helvetica,Univers,Zurich BT; font-size: 100%; color: #000000 }\n";
    $data .= "</style>\n";
  }

  $data .= "</head>\n";
  $data .= "<body bgcolor=\"#FFFFFF\">\n";
  $data .= "<div align=\"center\">\n";
  $data .= "<p><table border=0>\n";
  $data .= "  <tr>\n";

  if ($delimiterError) {
    $data .= "    <td><b>Invalid Delimiter Provided.</b>\n";
    $data .= "      <p>Sorry, but the url parameters must not be delimited by the equals sign.\n";
    $data .= "      <p>Please refer to our online documentation \&amp; FAQ, or contact technical support, for assistance on url parameters \&amp;/or configuring this particular service/feature.\n";
  } else {
    $data .= "    <td><b>Service Not Configured.</b>\n";
    $data .= "      <p>Sorry, but the service/feature you are attempting to use has not been activated or configured properly.\n";
    $data .= "      <p>Please refer to our online documentation \&amp; FAQ, or contact technical support, for assistance activating \&amp;/or configuring this particular service/feature.\n";
  }

  $data .= "    </td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";
  $data .= "</div>\n";
  $data .= "</body>\n";
  $data .= "</html>\n";

  return $data;
}

1;
