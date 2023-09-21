
#     |                   |                 |o|        |    |    o
# ,---|,---.    ,---.,---.|---     ,---.,---|.|---     |--- |---..,---.    ,---.,---.
# |   ||   |    |   ||   ||        |---'|   |||        |    |   ||`---.    |   ||   |
# `---'`---'    `   '`---'`---'    `---'`---'``---'    `---'`   '``---'    `---'`   '
#
#                    |          |    o
# ,---.,---.,---.,---|.   .,---.|--- .,---.,---.
# |   ||    |   ||   ||   ||    |    ||   ||   |
# |---'`    `---'`---'`---'`---'`---'``---'`   '
# |

package tds;

BEGIN {
  if (!defined $ENV{'PERLPR_LIB'}) {
    # default to prevent warnings if env variable is not set
    $ENV{'PERLPR_LIB'} = '/home/pay1/perlpr_lib';
  }
}

use strict;
use lib $ENV{'PERLPR_LIB'};
use PlugNPay::CGI;
use PlugNPay::Email;
use miscutils;
use PlugNPay::Environment;

sub tdsinit {
  my ($remoteflag) = @_;

  my %tdsresult = ();

  my $query = new CGI();
  my $querystr = $query->getRaw();

  if ($querystr =~ /.*?<([^\?\!]+?)\/{0,1}>/) {
    my $rootelement = $1;
    if ($rootelement eq "Error") {
      print "Content-Type: text/html\n\n";

      my %temparray = &readxml($querystr);
      &xmlerror("pares",%temparray);

      exit;
    }
  }


  my $pares = $query->param('PaRes');
  my $cprs = $query->param('C64S');
  my $tdspass = $query->param('tdspass');
  my $termurl = $query->param('TermUrl');
  my $md = $query->param('MD');

  my %datainfo = ();
  my $name = "";
  my (@names) = $query->param;
  foreach $name (@names) {
    $datainfo{$name} = $query->param($name);
  }



  if ($query->param('OrderID') =~ /firstatl/) {
    require firstatl;
    %tdsresult = &firstatl::recvpares($querystr);
    &firstatl::firstatllog($datainfo{'publisher-name'},$datainfo{'order-id'},"",$datainfo{'card-number'},"",$datainfo{'amount'},"final result","$tdsresult{'status'}: $tdsresult{'descr'}");
    $tdsresult{'tdsfinal'} = 1;
    return %tdsresult;
  }
  if (($pares eq "") && ($cprs eq "")) {
    $tdsresult{'querystr'} = $querystr;
    return %tdsresult;
  }
  elsif ($tdspass ne "1") {
    %tdsresult = &closewindow($pares,$md,$termurl,$remoteflag);
    return %tdsresult;
  }
  else {
    if ($query->param('MD') eq "wirecard3ds") {
      require wirecard3ds;
      %tdsresult = &wirecard3ds::recvpares($pares);
      &wirecard3ds::wirecardlog($datainfo{'publisher-name'},$datainfo{'order-id'},"",$datainfo{'card-number'},$datainfo{'amount'},"final result","$tdsresult{'status'}: $tdsresult{'descr'}");
      $tdsresult{'tdsfinal'} = 1;
    }
    elsif ($query->param('OrderID') =~ /firstatl/) {
      require firstatl;
      %tdsresult = &firstatl::recvpares($querystr);
      &firstatl::firstatllog($datainfo{'publisher-name'},$datainfo{'order-id'},"",$datainfo{'card-number'},"",$datainfo{'amount'},"final result","$tdsresult{'status'}: $tdsresult{'descr'}");
      $tdsresult{'tdsfinal'} = 1;
    }
    elsif ($query->param('MD') =~ /paay/) {
      require paay;
      %tdsresult = &paay::recvpares($querystr);
      &paay::paaylog($datainfo{'publisher-name'},$datainfo{'order-id'},"",$datainfo{'card-number'},"",$datainfo{'amount'},"final result","$tdsresult{'status'}: $tdsresult{'descr'}");
      $tdsresult{'tdsfinal'} = 1;
    }
    elsif ($query->param('MD') eq "cardinal") {
      require cardinal;
      %tdsresult = &cardinal::recvpares($pares);
      &cardinal::cardinallog($datainfo{'publisher-name'},$datainfo{'order-id'},"",$datainfo{'card-number'},"",$datainfo{'amount'},"final result","$tdsresult{'status'}: $tdsresult{'descr'}");
      $tdsresult{'tdsfinal'} = 1;
    }
    elsif ($query->param('MD') eq "payvision3ds") {
      require payvision3ds;
      %tdsresult = &payvision3ds::recvpares($pares);
      &payvision3ds::payvision3dslog($datainfo{'publisher-name'},$datainfo{'order-id'},"",$datainfo{'card-number'},"",$datainfo{'amount'},"final result","$tdsresult{'status'}: $tdsresult{'descr'}");
      $tdsresult{'tdsfinal'} = 1;
    }
    elsif ($query->param('MD') eq "pago3ds") {
      require pago3ds;
      %tdsresult = &pago3ds::recvpares($pares);
      &pago3ds::pago3dslog($datainfo{'publisher-name'},$datainfo{'order-id'},"",$datainfo{'card-number'},$datainfo{'amount'},"final result","$tdsresult{'status'}: $tdsresult{'descr'}");
      $tdsresult{'tdsfinal'} = 1;
    }
  }

  return %tdsresult;
}



sub authenticate {
  my ($username,$querystr,@pairs) = @_;
  my %datainfo = @pairs;

  my $pares = $datainfo{'PaRes'};
  my $cprs = $datainfo{'C64S'};
  my $tdspass = $datainfo{'tdspass'};
  my $md = $datainfo{'MD'};

  my %tdsresult = ();

  if (($pares eq "") && ($cprs eq "")) {
    # new fields
    #    merchanturl       http://www.merchantsite.com
    #    recurfreq
    #    recurend
    #    recurinstall
    #    md


    my $dbh = &miscutils::dbhconnect("pnpmisc");

    my $sth = $dbh->prepare(qq{
            select tdsprocessor,tds_config from customers
            where username='$username'
            }) or die "Can't prepare: $DBI::errstr";
    $sth->execute or die "Can't execute: $DBI::errstr";
    my ($tdsprocessor,$tds_config) = $sth->fetchrow;
    $sth->finish;

    $dbh->disconnect;

    if ($tdsprocessor eq "firstatl") {
      require firstatl;
      %tdsresult = &firstatl::authenticate("$username",$querystr,%datainfo);
      &firstatl::firstatllog($username,$datainfo{'order-id'},"",$datainfo{'card-number'},"",$datainfo{'amount'},"authen result","$tdsresult{'status'}: $tdsresult{'descr'}");
    }
    elsif ($tdsprocessor eq "paay") {
      require paay;
      %tdsresult = &paay::authenticate("$username",$querystr,%datainfo);
      &paay::paaylog($username,$datainfo{'order-id'},"",$datainfo{'card-number'},"",$datainfo{'amount'},"authen result","$tdsresult{'status'}: $tdsresult{'descr'}");
    }
    elsif ($tdsprocessor eq "cardinal") {
      require cardinal;
      %tdsresult = &cardinal::authenticate("$username",$querystr,%datainfo);
      &cardinal::cardinallog($username,$datainfo{'order-id'},"",$datainfo{'card-number'},"",$datainfo{'amount'},"authen result","$tdsresult{'status'}: $tdsresult{'descr'}");
    }
    elsif ($tdsprocessor eq "payvision3ds") {
      require payvision3ds;
      %tdsresult = &payvision3ds::authenticate("$username",$querystr,%datainfo);
      &payvision3ds::payvision3dslog($username,$datainfo{'order-id'},"",$datainfo{'card-number'},"",$datainfo{'amount'},"authen result","$tdsresult{'status'}: $tdsresult{'descr'}");
    }
    elsif ($tdsprocessor eq "pago3ds") {
      require pago3ds;
      %tdsresult = &pago3ds::authenticate("$username",$querystr,%datainfo);
      &pago3ds::pago3dslog($username,$datainfo{'order-id'},"",$datainfo{'card-number'},$datainfo{'amount'},"authen result","$tdsresult{'status'}: $tdsresult{'descr'}");
    }
    elsif ($tdsprocessor eq "wirecard3ds") {
      require wirecard3ds;
      %tdsresult = &wirecard3ds::authenticate("$username",$querystr,%datainfo);
      &wirecard3ds::wirecardlog($username,$datainfo{'order-id'},"",$datainfo{'card-number'},$datainfo{'amount'},"authen result","$tdsresult{'status'}: $tdsresult{'descr'}");
    }
    else {
      $tdsresult{'eci'} = "07";
    }
    $tdsresult{'tds_config'} = $tds_config;
  }

  return %tdsresult;
}


sub readxml {
  my ($msg) = @_;

  $msg =~ s/\n//g;
  $msg =~ s/>[  \n]*?</>\n</g;
  my @tmpfields = split(/\n/,$msg);
  my %temparray = ();
  my $levelstr = "";
  foreach my $var (@tmpfields) {
    if ($var =~ /<(.+)>(.*)</) {
      my $var2 = $1;
      $var2 =~ s/ .*$//;
      if ($temparray{"$levelstr$var2"} eq "") {
        $temparray{"$levelstr$var2"} = $2;
      }
      else {
        $temparray{"$levelstr$var2"} = $temparray{"$levelstr$var2"} . "," . $2;
      }
    }
    elsif ($var =~ /<\/(.+)>/) {
      $levelstr =~ s/,[^,]*?,$/,/;
    }
    elsif (($var =~ /<(.+)>/) && ($var !~ /<\?/) && ($var !~ /<\!/) && ($var !~ /\/>/)) {
      my $var2 = $1;
      $var2 =~ s/ .*$//;
      $levelstr = $levelstr . $var2 . ",";
      my $levelstr2 = $levelstr;
      chop $levelstr2;
      $temparray{"$levelstr2"} = "";
    }
  }

  return %temparray;
}

sub closewindow {
  my ($pares,$md,$termurl,$remoteflag) = @_;
  my %tdsresult = ();
  my $message = "";

  $message .= "Content-Type: text/html\n\n";
  $message .= "<html>\n";
  $message .= "<head>\n";
  $message .= "<script Language=\"Javascript\">\n";
  $message .= "<!--\n";
  $message .= "function OnLoadEvent()\n";
  $message .= "{\n";
  $message .= "  document.acsform.submit();\n";
  $message .= "}\n";
  $message .= "//-->\n";
  $message .= "</script>\n";
  $message .= "</head>\n";

  if ($termurl eq "") {
    my $env = new PlugNPay::Environment();
    my $httphost = $env->get('PNP_SERVER_NAME');
    $termurl = "https://" . $httphost . $ENV{'REQUEST_URI'};
  }

  $message .= "<body onLoad=\"OnLoadEvent();\">\n";
  $message .= "<form name=\"acsform\" method=\"post\" action=\"$termurl\" target=\"_self\">\n";

  $message .= "<noscript>\n";
  $message .= "<br>\n";
  $message .= "<br>\n";
  $message .= "<center>\n";
  $message .= "<h3>Please click on the Submit button to continue\n";
  $message .= "the processing of your 3-D secure\n";
  $message .= "transaction.</h3>\n";
  $message .= "<input type=\"submit\" value=\"Submit\">\n";
  $message .= "</center>\n";
  $message .= "</noscript>\n";

  $message .= "<input type=\"hidden\" name=\"PaRes\" value=\"$pares\">\n";
  $message .= "<input type=\"hidden\" name=\"MD\" value=\"$md\">\n";
  $message .= "<input type=\"hidden\" name=\"tdspass\" value=\"1\">\n";
  $message .= "</form>\n";
  $message .= "</body>\n";
  $message .= "</html>\n";

  if ($remoteflag eq "remote") {
    $tdsresult{'closewindow'} = $message;
    return %tdsresult;
  } else {
    print "$message";
  }

  exit;
}

sub xmlerror {
  my ($operation,%temparray) = @_;

  my $errorcode = $temparray{'ThreeDSecure,Message,Error,errorCode'};
  my $errormsg = $temparray{'ThreeDSecure,Message,Error,errorMessage'};
  my $errordet = $temparray{'ThreeDSecure,Message,Error,errorDetail'};
  my $vendorcode = $temparray{'ThreeDSecure,Message,Error,vendorCode'};

  my $emailObj = new PlugNPay::Email('legacy');
  $emailObj->setGatewayAccount('');
  $emailObj->setTo('cprice@plugnpay.com');
  $emailObj->setFrom('dcprice@plugnpay.com');
  $emailObj->setSubject("3ds - $operation problem\n");
  my $message = '';
  $message .= "operation: $operation\n";
  $message .= "errorcode: $errorcode\n";
  $message .= "errormsg: $errormsg\n";
  $message .= "errordet: $errordet\n";
  $message .= "vendorcode: $vendorcode\n";
  $emailObj->setContent($message);
  $emailObj->send();
}


1;
