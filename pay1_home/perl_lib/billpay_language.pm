package billpay_language;

require 5.001;

use pnp_environment;
use CGI;
use CGI::Cookie;
use miscutils;
use sysutils;
use strict;
use PlugNPay::PayScreens::Assets;
use language qw(%billpay_titles);

sub new {
  my $type = shift;

  #%billpay_language::query = @_;
  
  %billpay_language::query = ();
  $billpay_language::query = new CGI;

  my @array = $billpay_language::query->param;
  foreach my $var (@array) {
    $var =~ s/[^a-zA-Z0-9\_\-]//g;
    $billpay_language::query{$var} = &CGI::escapeHTML($billpay_language::query->param($var));
  }

  $billpay_language::query{'merchant'} =~ s/[^a-zA-Z0-9]//g;
  my $tmp_merch = $billpay_language::query{'merchant'}; # hold merchant username for later

  ## figure out cobrand stuff... 
  my $cobrand = 0; # assume nothings set [0 = not set, 1 = cobrand cookie, 2 = cobrand lookup]
  my $cobrand_merchant = "";
  my $cobrand_title = "";

  # look through cookies & try to find cobrand cookie data
  my %cookies = fetch CGI::Cookie;

  if ($cookies{'BILLPAY_COBRAND'} ne "") {
    my $cookie_data = $cookies{'BILLPAY_COBRAND'}->value;
    $cookie_data =~ tr/+/ /;
    $cookie_data =~ s/\%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;

    ## split cookie value
    my ($merchant, $title) = split(/\t/, $cookie_data);
    $merchant =~ s/[^a-zA-Z0-9]//g;
    $merchant = lc("$merchant");
    $title =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]//g;

    # set in cobrand data in memory
    $cobrand = 1;
    $cobrand_merchant = $merchant;
    $billpay_language::query{'merchant'} = $merchant;
    $cobrand_title = $title;
  }

  if ($ENV{'SCRIPT_NAME'} =~ /^(\/admin\/billpay\/)/) {
    $cobrand = 1;
    $cobrand_merchant = $ENV{'REMOTE_USER'};
    $billpay_language::query{'merchant'} = $cobrand_merchant;
  }

  %billpay_language::lang_titles = ();
  %billpay_language::tableprop = ();
  %billpay_language::template = ();
  my %lang_titles = %language::billpay_titles;

  # Languange Setting: # '0' = English # '1' = Spanish # '2' = French
  %billpay_language::lang_hash = ('en','0','sp','1','fr','2','es','1');

  # check and enforce languange setting
  $billpay_language::query{'lang'} =~ tr/A-Z/a-z/;
  $billpay_language::query{'lang'} =~ s/[^a-z]//;
  $billpay_language::lang = $billpay_language::lang_hash{$billpay_language::query{'lang'}};
  if ($billpay_language::lang <= 0) {
    $billpay_language::lang = 0; # assume English by default
  }

  ## Change from 2D hash to 1D, to simplify things
  foreach my $key (keys %lang_titles) {
    $billpay_language::lang_titles{"$key"} = $lang_titles{"$key"}[$billpay_language::lang];
  }

  my $path_web = &pnp_environment::get('PNP_WEB');
  my $template_home = "$path_web/admin/templates/billpay/";
  my $template_file = "";

  my ($merchant);
  if ($tmp_merch ne "") {
    $merchant = $tmp_merch;
  }
  else {
    $merchant = $billpay_language::query{'merchant'};
  }

  my $merchantTemplateFile = "$merchant\_paytemplate\.txt";
  my $resellerTemplateFile = "$billpay_language::reseller\_paytemplate\.txt";

  $merchant =~ s/[^0-9a-zA-Z]//g;
  if (-e "$template_home/$merchantTemplateFile") {
    $template_file = "$template_home/$merchantTemplateFile";
  } elsif (-e "$template_home/$resellerTemplateFile") {
    $template_file = "$template_home/$resellerTemplateFile";
  }

  if ($template_file ne "") {
    my (%tempflag,$tempflag);
    $template_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    &sysutils::filelog("read","$template_file");
    open (TEMPLATE,'<',"$template_file");
    while (<TEMPLATE>) {
      chop;
      if ($_ =~ /<(doctype|language|head|top|tail|table|submtpg1|submtpg2|inputcheck|shipping|displayamt|email|body_[a-z0-9_]+)>/i) {
        if ($tempflag eq "") {
          $tempflag = $1;
          $tempflag =~ tr/A-Z/a-z/;
          next;
        }
      }
      if ($_ =~ /<\/$tempflag>/i) {
        $tempflag = "";
        next;
      }
      if ($tempflag eq "language") {
        my ($key,$value) = split('\t');
        $billpay_language::lang_titles{"$key"} = $value;
      }
      elsif ($tempflag eq "table") {
        my ($key,$value) = split('\t');
        $billpay_language::tableprop{"$key"} = $value;
      }
      elsif ($tempflag =~ /^(doctype|head|top|tail|submtpg1|submtpg2|inputcheck|shipping|displayamt|email|body_[a-z0-9_]+)$/) {
        $billpay_language::template{"$tempflag"} .= &parse_template("$_") . "\n";
      }
    }

    my $psa = new PlugNPay::PayScreens::Assets();
    my $assetsMigratedTemplate = $psa->migrateTemplateAssets({
      username => $merchant,
      templateSections => \%billpay_language::template
    });
    %billpay_language::template = %{$assetsMigratedTemplate};

    close(TEMPLATE);
  }

  return [], $type;
}

sub parse_template {
  my($line) = @_;
  if ($line !~ /\[pnp_/) {
    return $line;
  }
  $line =~ s/\r\n//g;
  my $parsecount = 0;
  while ($line =~ /\[pnp\_([0-9a-zA-Z-+_]*)\]/) {
    #print "LINE:$line<br>\n";
    my $query_field = $1;
    $parsecount++;
    if ($billpay_language::query{$query_field} ne "") {
      if ($query_field =~ /^(card-number|card_number|card-exp|card_exp|accountnum|routingnum)$/) {
        $line =~ s/\[pnp\_([0-9a-zA-Z-+]*)\]/FILTERED/;
      }
      elsif ($query_field =~ /^(subtotal|tax|shipping|handling|discnt)$/) {
        $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $billpay_language::query{$query_field})/e;
      }
      else {
        $line =~ s/\[pnp\_$query_field\]/$billpay_language::query{$query_field}/;
      }
    }
    elsif ($query_field =~ /^(orderID)$/) {
      $line =~ s/\[pnp_$query_field\]/$billpay_language::orderID/e;
    }
    else {
      $line =~ s/\[pnp\_$query_field\]//;
    }
    if ($parsecount >= 10) {
      return $line;
    }
  } # end while
  return $line;
}

1;

