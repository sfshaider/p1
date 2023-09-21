package xmlparse2;

use strict;
use miscutils;
use remote_strict;
use mckutils_strict;
use sysutils;
use CGI qw/:standard/;
use PlugNPay::Environment;
use PlugNPay::Features;
use PlugNPay::Logging::DataLog;
use PlugNPay::Transaction::TransactionProcessor;


sub new {
  my $type = shift;
  my (%result);
  %xmlparse2::tdsresult = ();
  %xmlparse2::feature   = ();
  @xmlparse2::ancestors = ();

  $xmlparse2::xmlROOT     = "";
  $xmlparse2::error_count = "";
  $xmlparse2::error_str   = "";

  $xmlparse2::tranqueactive = "";
  $xmlparse2::tranque       = "";

  $xmlparse2::gi       = "";
  $xmlparse2::file     = "";
  $xmlparse2::st_or_et = "";
  $xmlparse2::body     = "";
  $xmlparse2::attrline = "";
  $xmlparse2::attrs    = "";
  $xmlparse2::attrname = "";



  $xmlparse2::dtd_out  = 'http://www0.static.gateway-assets.com/xml/PnPxml_out.dtd';
  $xmlparse2::dtd_out2 = 'http://www0.static.gateway-assets.com/xml/PnPxml_out2.dtd';
  $xmlparse2::dtd_out3 = 'http://www0.static.gateway-assets.com/xml/PnPxml_out3.dtd';

  $xmlparse2::version = "";

  if ( exists $ENV{'MOD_PERL'} ) {
    $xmlparse2::pid = $$;
  } else {
    $xmlparse2::pid = getppid();
  }

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
    gmtime( time() );
  $xmlparse2::now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

  $xmlparse2::debug_file = "/home/p/pay1/database/debug/xmldebug" . sprintf( "%02d", $mon + 1 ) . ".txt";

  if ( ( $ENV{'HTTPS'} ne "on" ) && ( $ENV{'SERVER_NAME'} eq "" ) ) {
    my $message = "problem\n";
    $message .= "This transaction was sent to the non-secure server.  Please use the secure server.";
    &error_output($message);
    exit;
  }

  $xmlparse2::time = time();

  return [], $type;
}

sub input_xml {
  shift;
  my $env      = new PlugNPay::Environment();
  my $remoteIP = $env->get('PNP_CLIENT_IP');
  my ( $xmlstuff, %tdsresult ) = @_;
  my ( $message, %queryarray, %query, %result, %data );

  #use Datalog
  my $logger = new PlugNPay::Logging::DataLog( { collection => 'xmlparse2_input_xml' } );
  my %logdata = ();

  $xmlstuff =~ s/%(..)/pack('c',hex($1))/eg;
  $xmlstuff =~ s/\+/ /g;     # Substitue spaces for + sign
  $xmlstuff =~ s/^\s*//g;    # Strip whitespace in front.
  $xmlstuff =~ s/\=$//g;     # Strip trailing  = sign
  $xmlstuff =~ s/\s*$//g;    # Strip trailing whitespace

  my $validate_flag = &check_xml($xmlstuff);

  if ( $validate_flag != 1 ) {
    $xmlparse2::debug_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    &sysutils::filelog( "append", ">>$xmlparse2::debug_file" );
    open( DEBUG, ">>$xmlparse2::debug_file" );
    print DEBUG
      "DATE:$xmlparse2::now, IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$xmlparse2::pid, FAILED VALIDATION, ";
    $xmlstuff =~ s/(CardNumber>.*?<\/Card)/&filter_string($1)/gei;
    $xmlstuff =~ s/(CardCVV>[\d ]*<\/Card)/&filter_string($1)/gei;
    $xmlstuff =~ s/(CardExp>[\w\/ ]*<\/Card)/&filter_string($1)/gei;
    $xmlstuff =~ s/(AccountNum>[\w ]*<\/Account)/&filter_string($1)/gei;
    $xmlstuff =~ s/(RoutingNum>[\w ]*<\/Routing)/&filter_string($1)/gei;
    $xmlstuff =~ s/(Password>[\w ]*<\/Password)/&filter_string($1)/gei;
    $xmlstuff =~ s/(Merchpass>[\w ]*<\/MerchPass)/&filter_string($1)/gei;
    $xmlstuff =~ s/(MagStripe>[\w ]*<\/MagStripe)/&filter_string($1)/gei;

    if ( $xmlstuff =~ />([34567]\d{12,15})</ ) {
      $xmlstuff =~ s/>$1</&filter_string($1)/gei;
    }

    print DEBUG "$xmlstuff\n";
    print DEBUG "$xmlparse2::error_str\n";
    close(DEBUG);

    #use Datalog
    %logdata          = ();
    $logdata{DATE}    = $xmlparse2::now;
    $logdata{IP}      = $remoteIP;
    $logdata{SCRIPT}  = $ENV{'SCRIPT_NAME'};
    $logdata{HOST}    = $ENV{'SERVER_NAME'};
    $logdata{PORT}    = $ENV{'SERVER_PORT'};
    $logdata{BROWSER} = $ENV{'HTTP_USER_AGENT'};
    $logdata{PID}     = $xmlparse2::pid;
    $logger->log(
      { 'FAILED VALIDATION' => \%logdata,
        'xmlstuff'          => $xmlstuff,
        'error_str'         => $xmlparse2::error_str
      }
    );

    my $message = $xmlparse2::error_str;
    &error_output($message);
    exit;
  }

  %xmlparse2::tdsresult = %tdsresult;

  my $data = $xmlstuff;

  $data =~ s/<!\[CDATA\[(.*)\]\]>/&encode_string($1)/ge;
  $data =~ s/\r{0,1}\n/\n/g;
  $data =~ s/>\s*</>\n</g;
  my @tmpfields = split( /\n/, $data );
  %queryarray = ();
  my $levelstr = "";

  my ( $tranreq, $ordreq );

  foreach my $var (@tmpfields) {
    if ( $var =~ /<[!?]/ ) {
      next;
    }

    if ( $var =~ /<(.+)>(.*)</ ) {
      my $tmp1 = $1;    ## Element
      my $tmp2 = $2;    ## Value

      # Element Filtering
      # Strip out anything but alphanumeric,space,equals
      $tmp1 =~ s/[^a-zA-Z0-9\ \=]//g;

      # Remove front space padding
      $tmp1 =~ s/^\s*//g;
      my ( $var2, $stuff ) = split( '\ ', $tmp1 );
      $var2 =~ s/ .*$//;
      $var2 =~ tr/A-Z/a-z/;

      if ( exists $queryarray{'pnpxml,header,version'} ) {
        $xmlparse2::version = "$queryarray{'pnpxml,header,version'}";
      }

      # Value Filtering
      # Remove leading and trailing spaces etc.
      $tmp2 =~ s/^\s*//g;
      $tmp2 =~ s/\s*$//g;
      my $var3 = $tmp2;

      ## What Filtering Do we need to do on Value.  Is this too late?  Should we add filtering to tds input?

      my $key = "$levelstr$var2";
      if ( $queryarray{$key} eq "" ) {
        $queryarray{$key} = $var3;
      } else {
        $queryarray{$key} .= "," . $var3;
      }
    } elsif ( $var =~ /<\/(.+)>/ ) {
      $levelstr =~ s/,[^,]*?,$/,/;
    } elsif ( ( $var =~ /<(.+)>/ ) && ( $var !~ /<\?/ ) && ( $var !~ /\/>/ ) ) {
      my $var2 = $1;
      $var2 =~ s/ .*$//;
      $var2 =~ tr/A-Z/a-z/;

      if ( $xmlparse2::version > 1 ) {
        if ( ( $var2 =~ /TransactionRequest/i )
          && ( $var2 !~ /TransactionRequest\d/i ) ) {
          $tranreq++;
          $var2 .= $tranreq;
        }
        if ( ( $var2 =~ /OrderDetails/i ) && ( $var2 !~ /OrderDetails\d/i ) ) {
          $ordreq++;
          $var2 .= $ordreq;
        }
      }
      $levelstr .= $var2 . ",";
    }
  }

  $query{'publisher-name'} = $queryarray{'pnpxml,header,merchant,acctname'};
  $query{'publisher-name'} =~ s/[^a-zA-Z0-9]//g;
  $query{'publisher-password'} = $queryarray{'pnpxml,header,merchant,password'};
  $query{'client'}             = $queryarray{'pnpxml,header,client'};
  $query{'client'} =~ s/[^a-zA-Z0-9\_\-\ ]//g;

  ## For Testing
  my @array     = %query;
  my $pnpremote = remote->new(@array);

  my %security = &remote::security_check( $query{'publisher-name'}, $query{'publisher-password'}, "XML", $remoteIP, $query{'client'} );

  %xmlparse2::feature = %remote::feature;

  if ( $security{'flag'} != 1 ) {
    my $message = "$security{'MErrMsg'}";
    &error_output( $message, $query{'publisher-name'} );
    exit;
  }

  my $trancount = $queryarray{'pnpxml,header,trancount'};
  $trancount =~ s/[^0-9]//g;
  if ( ( $trancount <= 0 ) || ( $trancount > 99 ) ) {
    ##  Return Error.  Tran Count is Zero
    my $message = "TranCount Invalid";
    &error_output( $message, $query{'publisher-name'} );
    exit;
  }

  $query{'publisher-email'} = $queryarray{'pnpxml,header,merchant,email'};
  $query{'version'}         = $xmlparse2::version;

  my %sec_checked_msg = ();
  my %sec_checked_flg = ();

  my $trans_id = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
  my $group_id = $trans_id;

  if ( -e "/home/p/pay1/batchfiles/xml_multi.txt" ) {
    if ( ( $trancount > 1 ) && ( $xmlparse2::version == 4 ) ) {
      require tranque;
      $xmlparse2::tranque       = tranque->new( \%query );
      $xmlparse2::tranqueactive = $xmlparse2::tranque->check_tranque();
    }
  }

  my $tranquecnt = 0;

  for ( my $i = 1 ; $i <= $trancount ; $i++ ) {
    %data = ();

    $data{'mode'}       = $queryarray{"pnpxml,request,transactionrequest$i,mode"};
    $data{'orderID'}    = $queryarray{"pnpxml,request,transactionrequest$i,transactionid"};
    $data{'ipaddress'}  = $queryarray{"pnpxml,request,transactionrequest$i,ipaddress"};
    $data{'authtype'}   = $queryarray{"pnpxml,request,transactionrequest$i,authtype"};
    $data{'acct_code'}  = $queryarray{"pnpxml,request,transactionrequest$i,acctcode"};
    $data{'acct_code2'} = $queryarray{"pnpxml,request,transactionrequest$i,acctcode2"};
    $data{'acct_code3'} = $queryarray{"pnpxml,request,transactionrequest$i,acctcode3"};
    $data{'freeform'}   = $queryarray{"pnpxml,request,transactionrequest$i,freeform"};

    $data{'orderID'} =~ s/[^0-9]//g;

    if ( $data{'mode'} eq "" ) {
      $data{'mode'} = "auth";
    }

    if ( $data{'mode'} ne 'auth' ) {
      $data{'notify-email'} = $data{'publisher-email'};
    }

    if ( $data{'mode'} eq "query_trans" ) {
      $data{'startdate'}   = $queryarray{"pnpxml,request,transactionrequest$i,startdate"};
      $data{'enddate'}     = $queryarray{"pnpxml,request,transactionrequest$i,enddate"};
      $data{'operation'}   = $queryarray{"pnpxml,request,transactionrequest$i,txntype"};
      $data{'result'}      = $queryarray{"pnpxml,request,transactionrequest$i,result"};
      $data{'qresp'}       = $queryarray{"pnpxml,request,transactionrequest$i,qresp"};
      $data{'accttype'}    = $queryarray{"pnpxml,request,transactionrequest$i,accttype"};
      $data{'card-number'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardnumber"};
      $data{'card-name'}   = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardname"};
    } elsif ( $data{'mode'} =~ /^(returnprev)$/ ) {
      $data{'card-amount'} = $queryarray{"pnpxml,request,transactionrequest$i,order,cardamount"};
      $data{'transflags'}  = $queryarray{"pnpxml,request,transactionrequest$i,order,transflags"};
      $data{'email'}       = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,email"};

      if ( $queryarray{"pnpxml,request,transactionrequest$i,prevorderid"} ne "" ) {
        $data{'prevorderid'} = $queryarray{"pnpxml,request,transactionrequest$i,prevorderid"};

        my $debug_file = $xmlparse2::debug_file . "authprev";
        &sysutils::filelog( "append", ">>$debug_file" );
        open( DEBUG, ">>$debug_file" );
        print DEBUG "DATE:$xmlparse2::now, IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$xmlparse2::pid\n";
        close(DEBUG);

        #use Datalog
        %logdata          = ();
        $logdata{DATE}    = $xmlparse2::now;
        $logdata{IP}      = $remoteIP;
        $logdata{SCRIPT}  = $ENV{'SCRIPT_NAME'};
        $logdata{HOST}    = $ENV{'SERVER_NAME'};
        $logdata{PORT}    = $ENV{'SERVER_PORT'};
        $logdata{BROWSER} = $ENV{'HTTP_USER_AGENT'};
        $logdata{PID}     = $xmlparse2::pid;
        $logger->log( \%logdata );
      } else {
        $data{'prevorderid'} = $queryarray{"pnpxml,request,transactionrequest$i,prevtransactionid"};
      }
    } elsif ( $data{'mode'} =~ /^(postauth|mark|return|reauth)$/ ) {
      $query{'card-amount'} = $queryarray{"pnpxml,request,transactionrequest$i,order,cardamount"};
      $data{'accttype'}     = $queryarray{"pnpxml,request,transactionrequest$i,accttype"};
    } elsif ( $data{'mode'} =~ /void/ ) {
      $query{'card-amount'} = $queryarray{"pnpxml,request,transactionrequest$i,cardamount"};
      $query{'txn-type'}    = $queryarray{"pnpxml,request,transactionrequest$i,txntype"};
    } elsif ( $data{'mode'} =~ /^(credit|newreturn|payment)$/ ) {

      # credit card info
      $data{'card-number'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardnumber"};
      $data{'card-exp'}    = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardexp"};
      $data{'card-type'}   = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardtype"};
      $data{'card-cvv'}    = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardcvv"};
      $data{'magstripe'}   = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,magstripe"};

      # checking account info
      $data{'accountnum'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,accountnum"};
      $data{'routingnum'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,routingnum"};
      $data{'accttype'}   = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,accttype"};
      $data{'checknum'}   = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,checknum"};
      $data{'checktype'}  = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,checktype"};

      $data{'card-amount'}  = $queryarray{"pnpxml,request,transactionrequest$i,order,cardamount"};
      $data{'transflags'}   = $queryarray{"pnpxml,request,transactionrequest$i,order,transflags"};
      $data{'currency'}     = $queryarray{"pnpxml,request,transactionrequest$i,order,currency"};
      $data{'origorderid'}  = $queryarray{"pnpxml,request,transactionrequest$i,order,origorderid"};
      $data{'commcardtype'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,commcardtype"};

      # billing Information
      $data{'card-name'}     = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardname"};
      $data{'card-company'}  = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardcompany"};
      $data{'card-address1'} = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardaddress1"};
      $data{'card-address2'} = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardaddress2"};
      $data{'card-city'}     = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardcity"};
      $data{'card-state'}    = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardstate"};
      $data{'card-prov'}     = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardprov"};
      $data{'card-zip'}      = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardzip"};
      $data{'card-country'}  = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardcountry"};
      $data{'email'}         = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,email"};

    } elsif ( $data{'mode'} =~ /^(auth|checkcard|authprev|forceauth)$/ ) {
      ## authprev
      if ( $data{'mode'} =~ /^(authprev)$/ ) {
        if ( $queryarray{"pnpxml,request,transactionrequest$i,prevorderid"} ne "" ) {
          $data{'prevorderid'} = $queryarray{"pnpxml,request,transactionrequest$i,prevorderid"};

          my $debug_file = $xmlparse2::debug_file . "authprev";
          &sysutils::filelog( "append", ">>$debug_file" );
          open( DEBUG, ">>$debug_file" );
          print DEBUG "DATE:$xmlparse2::now, IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$xmlparse2::pid\n";
          close(DEBUG);

          #use Datalog
          %logdata          = ();
          $logdata{DATE}    = $xmlparse2::now;
          $logdata{IP}      = $remoteIP;
          $logdata{SCRIPT}  = $ENV{'SCRIPT_NAME'};
          $logdata{HOST}    = $ENV{'SERVER_NAME'};
          $logdata{PORT}    = $ENV{'SERVER_PORT'};
          $logdata{BROWSER} = $ENV{'HTTP_USER_AGENT'};
          $logdata{PID}     = $xmlparse2::pid;
          $logger->log( \%logdata );

        } else {
          $data{'prevorderid'} = $queryarray{"pnpxml,request,transactionrequest$i,prevtransactionid"};
        }
      } elsif ( $data{'mode'} eq "forceauth" ) {
        $data{'auth-code'} = $queryarray{"pnpxml,request,transactionrequest$i,authcode"};
      }
      ## Transaction Instructions
      $data{'dontsndmail'} = $queryarray{"pnpxml,request,transactionrequest$i,instructions,dontsndmail"};
      $data{'app-level'}   = $queryarray{"pnpxml,request,transactionrequest$i,instructions,applevel"};
      $data{'storedata'}   = $queryarray{"pnpxml,request,transactionrequest$i,instructions,storedata"};
      ## Surcharge Override
      $data{'override_adjustment'} = $queryarray{"pnpxml,request,transactionrequest$i,instructions,overrideadjustment"};

      ## ThreeDsecure Instructions
      $data{'cavv'}          = $queryarray{"pnpxml,request,transactionrequest$i,threedsecure,cavv"};
      $data{'cavvalgorithm'} = $queryarray{"pnpxml,request,transactionrequest$i,threedsecure,cavvalgorithm"};
      $data{'eci'}           = $queryarray{"pnpxml,request,transactionrequest$i,threedsecure,eci"};
      $data{'xid'}           = $queryarray{"pnpxml,request,transactionrequest$i,threedsecure,xid"};

      # billing Information
      $data{'card-name'}     = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardname"};
      $data{'card-company'}  = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardcompany"};
      $data{'card-address1'} = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardaddress1"};
      $data{'card-address2'} = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardaddress2"};
      $data{'card-city'}     = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardcity"};
      $data{'card-state'}    = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardstate"};
      $data{'card-prov'}     = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardprov"};
      $data{'card-zip'}      = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardzip"};
      $data{'card-country'}  = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardcountry"};
      $data{'email'}         = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,email"};
      $data{'phone'}         = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,phone"};
      $data{'fax'}           = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,fax"};

      # shipping Information
      $data{'shipname'}    = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,shipname"};
      $data{'shipcompany'} = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,company"};
      $data{'address1'}    = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,address1"};
      $data{'address2'}    = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,address2"};
      $data{'city'}        = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,city"};
      $data{'state'}       = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,state"};
      $data{'province'}    = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,province"};
      $data{'zip'}         = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,zip"};
      $data{'country'}     = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,country"};
      $data{'shipinfo'}    = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,shipinfo"};

      $data{'paymethod'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,paymentmethod"};

      if ( $data{'paymethod'} !~ /(credit|onlinecheck)/ ) {
        my (%result);
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'}     = "Missing Field:PnpXML,Request,TransactionRequest$i,PaymentDetails,PayMethod";
        my @array = ( %data, %query, %result );
        $message .= &output_xml( $i, @array );
        next;
      }

      if ( $data{'paymethod'} eq "credit" ) {
        $data{'card-number'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardnumber"};
        $data{'card-exp'}    = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardexp"};
        $data{'card-type'}   = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardtype"};
        $data{'card-cvv'}    = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardcvv"};
        $data{'magstripe'}   = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,magstripe"};
      } elsif ( $data{'paymethod'} eq "onlinecheck" ) {
        $data{'accountnum'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,accountnum"};
        $data{'routingnum'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,routingnum"};
        $data{'accttype'}   = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,accttype"};
        $data{'checknum'}   = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,checknum"};
        $data{'checktype'}  = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,checktype"};
        $data{'acctclass'}  = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,acctclass"};
      }
      $data{'commcardtype'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,commcardtype"};

      $data{'easycart'}    = $queryarray{"pnpxml,request,transactionrequest$i,order,easycart"};
      $data{'card-amount'} = $queryarray{"pnpxml,request,transactionrequest$i,order,cardamount"};
      $data{'currency'}    = $queryarray{"pnpxml,request,transactionrequest$i,order,currency"};
      $data{'tax'}         = $queryarray{"pnpxml,request,transactionrequest$i,order,tax"};
      $data{'shipping'}    = $queryarray{"pnpxml,request,transactionrequest$i,order,shipping"};

      $data{'transflags'} = $queryarray{"pnpxml,request,transactionrequest$i,order,transflags"};
      $data{'ponumber'}   = $queryarray{"pnpxml,request,transactionrequest$i,order,ponumber"};

      ####  Petroleum
      $data{'drivernum'}  = $queryarray{"pnpxml,request,transactionrequest$i,order,drivernum"};
      $data{'vehiclenum'} = $queryarray{"pnpxml,request,transactionrequest$i,order,vehiclenum"};
      $data{'odometer'}   = $queryarray{"pnpxml,request,transactionrequest$i,order,odometer"};
      $data{'jobnum'}     = $queryarray{"pnpxml,request,transactionrequest$i,order,jobnum"};
      $data{'deptnum'}    = $queryarray{"pnpxml,request,transactionrequest$i,order,deptnum"};
      $data{'licensenum'} = $queryarray{"pnpxml,request,transactionrequest$i,order,licensenum"};
      $data{'userdata'}   = $queryarray{"pnpxml,request,transactionrequest$i,order,userdata"};
      $data{'userid'}     = $queryarray{"pnpxml,request,transactionrequest$i,order,userid"};
      $data{'devseqnum'}  = $queryarray{"pnpxml,request,transactionrequest$i,order,devseqnum"};
      $data{'pin'}        = $queryarray{"pnpxml,request,transactionrequest$i,order,pin"};
      $data{'deviceid'}   = $queryarray{"pnpxml,request,transactionrequest$i,order,deviceid"};
      $data{'pumpid'}     = $queryarray{"pnpxml,request,transactionrequest$i,order,pumpid"};

      $data{'itemcount'} = $queryarray{"pnpxml,request,transactionrequest$i,order,itemcount"};

      if ( $data{'easycart'} == 1 ) {
        for ( my $k = 1 ; $k <= $data{'itemcount'} ; $k++ ) {
          $data{"item$k"}        = $queryarray{"pnpxml,request,transactionrequest$i,order,orderdetails$k,sku"};
          $data{"quantity$k"}    = $queryarray{"pnpxml,request,transactionrequest$i,order,orderdetails$k,qty"};
          $data{"cost$k"}        = $queryarray{"pnpxml,request,transactionrequest$i,order,orderdetails$k,cost"};
          $data{"description$k"} = $queryarray{"pnpxml,request,transactionrequest$i,order,orderdetails$k,desc"};
          $data{"unit$k"}        = $queryarray{"pnpxml,request,transactionrequest$i,order,orderdetails$k,unit"};
          $data{"customa$k"}     = $queryarray{ "pnpxml,request,transactionrequest$i,order,orderdetails$k,parameter1" };
          $data{"customb$k"}     = $queryarray{ "pnpxml,request,transactionrequest$i,order,orderdetails$k,parameter2" };
          $data{"customc$k"}     = $queryarray{ "pnpxml,request,transactionrequest$i,order,orderdetails$k,parameter3" };
          $data{"customd$k"}     = $queryarray{ "pnpxml,request,transactionrequest$i,order,orderdetails$k,parameter4" };
        }
      }
    } elsif ( $data{'mode'} =~ /^(add_member|update_member)$/ ) {

      # profile login info
      $data{'username'}   = $queryarray{"pnpxml,request,transactionrequest$i,username"};
      $data{'password'}   = $queryarray{"pnpxml,request,transactionrequest$i,password"};
      $data{'purchaseid'} = $queryarray{"pnpxml,request,transactionrequest$i,purchaseid"};

      # account status info
      $data{'startdate'} = $queryarray{"pnpxml,request,transactionrequest$i,startdate"};
      $data{'enddate'}   = $queryarray{"pnpxml,request,transactionrequest$i,enddate"};
      $data{'status'}    = $queryarray{"pnpxml,request,transactionrequest$i,status"};

      # credit card info
      $data{'card-number'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardnumber"};
      $data{'card-exp'}    = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,cardexp"};

      # checking account info
      $data{'accountnum'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,accountnum"};
      $data{'routingnum'} = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,routingnum"};
      $data{'accttype'}   = $queryarray{"pnpxml,request,transactionrequest$i,paymentdetails,accttype"};

      # plan info
      $data{'recfee'}    = $queryarray{"pnpxml,request,transactionrequest$i,order,recfee"};
      $data{'balance'}   = $queryarray{"pnpxml,request,transactionrequest$i,order,balance"};
      $data{'plan'}      = $queryarray{"pnpxml,request,transactionrequest$i,order,plan"};
      $data{'billcycle'} = $queryarray{"pnpxml,request,transactionrequest$i,order,billcycle"};

      # billing Information
      $data{'card-name'} = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardname"};

      #$data{'card-company'} = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardcompany"}; # must add to remote_strict.pm first
      $data{'card-address1'} = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardaddress1"};
      $data{'card-address2'} = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardaddress2"};
      $data{'card-city'}     = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardcity"};
      $data{'card-state'}    = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardstate"};
      $data{'card-prov'}     = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardprov"};
      $data{'card-zip'}      = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardzip"};
      $data{'card-country'}  = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,cardcountry"};
      $data{'email'}         = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,email"};
      $data{'phone'}         = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,phone"};
      $data{'fax'}           = $queryarray{"pnpxml,request,transactionrequest$i,billdetails,fax"};

      # shipping Information
      $data{'shipname'} = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,shipname"};
      $data{'company'}  = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,company"};
      $data{'address1'} = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,address1"};
      $data{'address2'} = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,address2"};
      $data{'city'}     = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,city"};
      $data{'state'}    = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,state"};
      $data{'province'} = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,province"};
      $data{'zip'}      = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,zip"};
      $data{'country'}  = $queryarray{"pnpxml,request,transactionrequest$i,shipdetails,country"};
    } elsif ( $data{'mode'} =~ /^(delete_member|cancel_member|query_member)$/ ) {
      $data{'username'} = $queryarray{"pnpxml,request,transactionrequest$i,username"};
    } elsif ( $data{'mode'} eq "query_billing" ) {
      $data{'username'}  = $queryarray{"pnpxml,request,transactionrequest$i,username"};
      $data{'startdate'} = $queryarray{"pnpxml,request,transactionrequest$i,startdate"};
      $data{'enddate'}   = $queryarray{"pnpxml,request,transactionrequest$i,enddate"};
    } elsif ( $data{'mode'} =~ /bill_member|credit_member/ ) {
      $data{'username'}    = $queryarray{"pnpxml,request,transactionrequest$i,username"};
      $data{'card-amount'} = $queryarray{"pnpxml,request,transactionrequest$i,order,cardamount"};
      $data{'transflags'}  = $queryarray{"pnpxml,request,transactionrequest$i,order,transflags"};
    }

    #$data{'client'} = "pnpxml";
    $data{'pnp_proto'} = "pnpxml";

    foreach my $key ( keys %data ) {
      if ( $data{$key} eq "" ) {
        delete $data{$key};
      }
    }

    ###  DCP 20090901  -  added to support onestep
    if ( $query{'client'} eq "onestep" ) {
      my %security = ();
      $query{'publisher-name'}     = $queryarray{"pnpxml,request,transactionrequest$i,merchname"};
      $query{'publisher-password'} = $queryarray{"pnpxml,request,transactionrequest$i,merchpass"};
      if ( $sec_checked_flg{ $query{'publisher-name'} } eq "" ) {
        my @array     = %query;
        my $pnpremote = remote->new(@array);
        %security = &remote::security_check( $query{'publisher-name'}, $query{'publisher-password'}, "XML", $remoteIP, $query{'client'} );
        $sec_checked_flg{ $query{'publisher-name'} } = $security{'flag'};
        $sec_checked_msg{ $query{'publisher-name'} } = $security{'MErrMsg'};
      }
      if ( $sec_checked_flg{ $query{'publisher-name'} } != 1 ) {
        my @array = ( %data, %query, 'FinalStatus', 'problem', 'MErrMsg', "$sec_checked_msg{$query{'publisher-name'}}" );
        $message .= &output_xml( $i, @array );
        next;
      }
    }

    ### DCP 20100716  -  Added to increment orderID's when doing returns.
    if ( ( $data{'mode'} =~ /^(credit|newreturn|payment|auth|authprev|bill_member)$/ )
      && ( $data{'orderID'} eq "" ) ) {
      $data{'orderID'} = PlugNPay::Transaction::TransactionProcessor::generateOrderID();
    }

    $tranquecnt++;

    my @array = ( %data, %query );
    if ( $xmlparse2::tranqueactive eq "yes" ) {
      my %inputhash = (@array);
      $trans_id = $xmlparse2::tranque->format_data( $trans_id, $group_id, \%inputhash, \%tdsresult );
    } else {
      @array = &process_tran(@array);
      $message .= &output_xml( $i, @array );
    }
  }

  if ( $xmlparse2::tranqueactive eq "yes" ) {
    my @results_array = &tranque::check_results( $group_id, $tranquecnt, $data{'mode'}, \%tdsresult );
    my $i = 0;
    foreach my $hash (@results_array) {
      $i++;
      my @array = %$hash;
      $message .= &output_xml( $i, @array );
    }
  }

  $message = &xml_wrapper( $message, $query{'publisher-name'} );
  return $message;
}

sub output_xml {

  my ( $tranidx, %result ) = @_;

  my %xmlmap = (
    'FinalStatus', 'FinalStatus',  'MErrMsg',   'MErrMsg', 'AuthCode',  'auth-code', 'CVVResp',       'cvvresp', 'AVSResp',   'avs-code',  'RespCode', 'resp-code',
    'RespSubCode', 'resp-subcode', 'SRespCode', 'sresp',   'Duplicate', 'Duplicate', 'TransactionID', 'orderID', 'Refnumber', 'refnumber', 'H1Data',   'h1data'
  );

  my %convfeemap = ( 'ConvFeeAmount', 'convfeeamt', 'TotalCharged', 'totalchrg', 'FinalStatus', 'FinalStatus', 'MErrMsg', 'MErrMsg', 'AuthCode', 'auth-code', 'TransactionID', 'orderID' );

  my %querymap = (
    'FinalStatus', 'FinalStatus', 'MErrMsg',   'MErrMsg',   'AuthCode',      'auth-code', 'CVVResp',   'cvvresp',   'AVSResp', 'avs-code', 'RespCode', 'resp-code',
    'SRespCode',   'sresp',       'Duplicate', 'Duplicate', 'TransactionID', 'orderID',   'Refnumber', 'refnumber', 'BatchID', 'result'
  );

  my %querysimple = ( 'FinalStatus', 'FinalStatus', 'TransactionID', 'orderID' );

  my @billdetails = ( 'CardName', 'CardCompany', 'CardAddress1', 'CardAddress2', 'CardCity', 'CardState', 'CardProv', 'CardZip', 'CardCountry', 'Email' );
  my %billdetails = (
    'CardName',  'card-name',  'CardCompany', 'card-company', 'CardAddress1', 'card-address1', 'CardAddress2', 'card-address2', 'CardCity', 'card-city',
    'CardState', 'card-state', 'CardProv',    'card-prov',    'CardZip',      'card-zip',      'CardCountry',  'card-country',  'Email',    'email'
  );

  my @order = ( 'CardAmount', 'Currency' );
  my %order = ( 'CardAmount', 'card-amount', 'Currency', 'currency' );

  my @misc = ( 'AcctCode', 'AcctCode2', 'AcctCode3', 'AcctCode4' );
  my %misc = ( 'AcctCode', 'acct_code', 'AcctCode2', 'acct_code2', 'AcctCode3', 'acct_code3', 'AcctCode4', 'acct_code4' );

  my @paydetails = ( 'CardNumber', 'CardExp', 'CardType', 'ReceiptCardNumber', 'AccountNum', 'RoutingNum', 'AcctType', 'CheckType', 'CheckNum' );
  my %paydetails = (
    'CardNumber', 'card-number', 'CardExp',  'card-exp', 'CardType',  'cardtype',  'ReceiptCardNumber', 'receiptcc', 'AccountNum', 'accountnum',
    'RoutingNum', 'routingnum',  'AcctType', 'accttype', 'CheckType', 'checktype', 'CheckNum',          'checknum'
  );

  my @membership = ('Username');
  my %membership = ( 'Username', 'username' );

  my @operations = ( 'auth', 'forceauth', 'postauth', 'return', 'void' );

  if ( $result{'client'} =~ /^(onestep)$/ ) {
    %xmlmap = ( %xmlmap, 'MerchName', 'publisher-name' );
  }
  if ( $result{'publisher-name'} =~ /^(jamestu2|pnpdemo2|americanfi4)$/ ) {
    %xmlmap = ( %xmlmap, 'AcctCode', 'acct_code' );
  }

  my ( $message, %opertotal );

  if ( $xmlparse2::version > 1 ) {
    $message = "<TransactionResponse>\n";
  } else {
    $message = "<TransactionResponse$tranidx>\n";
  }

  $message .= "  <Mode>$result{'mode'}</Mode>\n";

  if ( ( $result{'mode'} eq "query_trans" )
    && ( $result{'qresp'} ne "simple" ) ) {
    my ( %res, @batches, @dates );
    foreach my $key ( keys %result ) {
      if ( $key =~ /^opertotal_(.*)/ ) {
        $opertotal{"$1"} = $result{$key};
      } elsif ( $key =~ /^batchtotal_(.*)/ ) {
        $batches[ ++$#batches ] = "$1";
      } elsif ( $key =~ /^datetotal_(.*)/ ) {
        $dates[ ++$#dates ] = "$1";
      }
    }
    $message .= "  <Totals>\n";
    if ( @operations > 0 ) {
      foreach my $oper (@operations) {
        if ( exists $opertotal{$oper} ) {
          $opertotal{$oper} = sprintf( "%.2f", "$opertotal{$oper}" );
          $message .= "    <Operations>\n";
          $message .= "      <Operation>$oper</Operation>\n";
          $message .= "      <Amount>$opertotal{$oper}</Amount>\n";
          $message .= "    </Operations>\n";
        }
      }
    }
    if ( @batches > 0 ) {
      foreach my $batchid (@batches) {
        my $amt = $result{"batchtotal_$batchid"};
        $amt = sprintf( "%.2f", "$amt" );
        $message .= "    <Batches>\n";
        $message .= "      <BatchID>$batchid</BatchID>\n";
        $message .= "      <Amount>$amt</Amount>\n";
        $message .= "    </Batches>\n";
      }
    }
    if ( @dates > 0 ) {
      foreach my $date (@dates) {
        my $amt = $result{"datetotal_$date"};
        $amt = sprintf( "%.2f", "$amt" );
        $message .= "    <Daily>\n";
        $message .= "      <Dates>$date</Dates>\n";
        $message .= "      <Amount>$amt</Amount>\n";
        $message .= "    </Daily>\n";
      }
    }

    $message .= "  </Totals>\n";
    for ( my $i = 1 ; $i <= $result{'num-txns'} ; $i++ ) {

      #$message .= "  <QueryResponse$i>\n";
      $message .= "  <TranResults>\n";
      ## Parse Response
      my $idx = sprintf( "a%05d", $i - 1 );
      %res = ();
      foreach my $pair ( split( '&', $result{"$idx"} ) ) {
        if ( $pair =~ /(.*)=(.*)/ ) {    #found key=value;#
          my ( $key, $value ) = ( $1, $2 );    #get key, value
          $value =~ s/%(..)/pack('c',hex($1))/eg;
          $res{$1} = $value;

          #print"K:$key:VAL:$value<br>\n";
        }
      }
      if ( $res{'operation'} =~ /^auth$/ ) {
        if ( $res{'MErrMsg'} =~ /\:/ ) {
          ( $res{'resp-code'}, $res{'MErrMsg'} ) =
            split( '\:', $res{'MErrMsg'} );
        }
        if ( $res{'FinalStatus'} eq "success" ) {
          $res{'sresp'} = "A";
        } else {
          $res{'sresp'} = &simplified_resp( $remote::processor, $res{'FinalStatus'}, $res{'resp-code'} );
        }
      }
      if ( $result{'operation'} eq "batchquery" ) {
        $res{'batchid'} = $res{'result'};
      }
      if ( exists $res{'trans_time'} ) {
        my $year = substr( $res{'trans_time'}, 0,  4 );
        my $mon  = substr( $res{'trans_time'}, 4,  2 );
        my $day  = substr( $res{'trans_time'}, 6,  2 );
        my $hour = substr( $res{'trans_time'}, 8,  2 );
        my $min  = substr( $res{'trans_time'}, 10, 2 );
        my $sec  = substr( $res{'trans_time'}, 12, 2 );
        $res{'trans_time'} = sprintf( "%04d\-%02d\-%02dT%02d\:%02d\:%02d\+00\:00", $year, $mon, $day, $hour, $min, $sec );
      }
      if ( exists $res{'card-number'} ) {
        if ( $res{'card-number'} =~ /^(\d{9}) (\d+)/ ) {
          $res{'routingnum'} = $1;
          $res{'accountnum'} = $2;
        } else {
          $res{'cardtype'} = &miscutils::cardtype( $res{'card-number'} );
        }

        #$res{'receiptcc'} = substr($res{'card-number'},0,20); ####  DCP 20110126
        my ($cardnumber) = $res{'card-number'};
        my $cclength = length($cardnumber);
        my $last4 = substr( $cardnumber, -4, 4 );
        $cardnumber =~ s/./X/g;

        if ( $res{'receiptcc'} !~ /\d{4}$/ ) {
          $res{'receiptcc'} = substr( $cardnumber, 0, $cclength - 4 ) . $last4;
        }

        $res{'card-number'} = substr( $res{'card-number'}, 0, 4 ) . "**" . substr( $res{'card-number'}, -2 );
      }
      foreach my $key ( sort keys %querymap ) {
        my $value = $res{"$querymap{$key}"};
        if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
          $value = "<![CDATA[$value]]>";
        }
        if (
          ( $res{'operation'} eq "auth" )
          || ( ( $res{'operation'} ne "auth" )
            && ( $key !~ /^(MErrMsg|AVSResp|SRespCode|CVVResp|RespCode)$/ ) )
          ) {
          $message .= "    <$key>$value</$key>\n";
        }
      }
      $message .= "    <Operation>$res{'operation'}</Operation>\n";
      $message .= "    <TransTime>$res{'trans_time'}</TransTime>\n";
      foreach my $key (@misc) {
        my $value = $res{ $misc{$key} };
        if ( $value eq "" ) {
          next;
        }
        if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
          $value = "<![CDATA[$value]]>";
        }
        $message .= "    <$key>$value</$key>\n";
      }

      #$message .= "  </TranResults>\n";
      if ( $xmlparse2::version > 1 ) {
        $message .= "    <BillDetails>\n";
        foreach my $key (@billdetails) {
          my $value = $res{ $billdetails{$key} };
          if ( $value eq "" ) {
            next;
          }
          if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
            $value = "<![CDATA[$value]]>";
          }
          $message .= "      <$key>$value</$key>\n";
        }
        $message .= "    </BillDetails>\n";
        $message .= "    <Order>\n";
        foreach my $key (@order) {
          my $value = $res{ $order{$key} };
          if ( $value eq "" ) {
            next;
          }
          if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
            $value = "<![CDATA[$value]]>";
          }
          $message .= "      <$key>$value</$key>\n";
        }
        $message .= "    </Order>\n";
        $message .= "    <PaymentDetails>\n";
        foreach my $key (@paydetails) {
          my $value = $res{ $paydetails{$key} };
          if ( $value eq "" ) {
            next;
          }
          if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
            $value = "<![CDATA[$value]]>";
          }
          $message .= "       <$key>$value</$key>\n";
        }
        $message .= "    </PaymentDetails>\n";
      }
      $message .= "  </TranResults>\n";

      #$message .= "  </QueryResponse$i>\n";
    }
  } elsif ( ( $result{'mode'} eq "query_trans" )
    && ( $result{'qresp'} eq "simple" ) ) {
    my ( %res, @batches, @dates );
    foreach my $key ( sort keys %xmlmap ) {
      my $value = $result{ $xmlmap{$key} };
      if ( $xmlparse2::version > 1 ) {
        if ( $value eq "" ) {
          next;
        }
      }
      if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
        $value = "<![CDATA[$value]]>";
      }
      $message .= "  <$key>$value</$key>\n";
    }
    for ( my $i = 1 ; $i <= $result{'num-txns'} ; $i++ ) {
      $message .= "  <TranResults>\n";
      ## Parse Response
      my $idx = sprintf( "a%05d", $i - 1 );
      %res = ();
      foreach my $pair ( split( '&', $result{"$idx"} ) ) {
        if ( $pair =~ /(.*)=(.*)/ ) {    #found key=value;#
          my ( $key, $value ) = ( $1, $2 );    #get key, value
          $value =~ s/%(..)/pack('c',hex($1))/eg;
          $res{$1} = $value;

          #print"K:$key:VAL:$value<br>\n";
        }
      }

      if ( exists $res{'trans_time'} ) {
        my $year = substr( $res{'trans_time'}, 0,  4 );
        my $mon  = substr( $res{'trans_time'}, 4,  2 );
        my $day  = substr( $res{'trans_time'}, 6,  2 );
        my $hour = substr( $res{'trans_time'}, 8,  2 );
        my $min  = substr( $res{'trans_time'}, 10, 2 );
        my $sec  = substr( $res{'trans_time'}, 12, 2 );
        $res{'trans_time'} = sprintf( "%04d\-%02d\-%02dT%02d\:%02d\:%02d\+00\:00", $year, $mon, $day, $hour, $min, $sec );
      }

      foreach my $key ( sort keys %querysimple ) {
        my $value = $res{"$querymap{$key}"};
        if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
          $value = "<![CDATA[$value]]>";
        }
        $message .= "    <$key>$value</$key>\n";
      }
      $message .= "    <Operation>$res{'operation'}</Operation>\n";
      $message .= "    <TransTime>$res{'trans_time'}</TransTime>\n";
      foreach my $key (@misc) {
        my $value = $res{ $misc{$key} };
        if ( $value eq "" ) {
          next;
        }
        if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
          $value = "<![CDATA[$value]]>";
        }
        $message .= "    <$key>$value</$key>\n";
      }
      $message .= "  </TranResults>\n";
    }
  } elsif ( $result{'mode'} eq "query_noc" ) {
    my ( %res, @operations, @batches, @dates );

    for ( my $i = 1 ; $i <= $result{'num-txns'} ; $i++ ) {
      $message .= "  <QueryResponse$i>\n";
      $message .= "    <NOCResponse>\n";
      ## Parse Response
      my $idx = sprintf( "%05d", $i );
      %res = ();
      foreach my $pair ( split( '&', $result{"a$idx"} ) ) {
        if ( $pair =~ /(.*)=(.*)/ ) {    #found key=value;#
          my ( $key, $value ) = ( $1, $2 );    #get key, value
          $value =~ s/%(..)/pack('c',hex($1))/eg;
          $res{$1} = $value;
        }
      }
      foreach my $key ( sort keys %res ) {
        my $value = $res{"$xmlmap{$key}"};
        if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
          $value = "<![CDATA[$value]]>";
        }
        $message .= "      <$key>$value</$key>\n";
      }
      $message .= "    </NOCResponse>\n";
      $message .= "  </QueryResponse$i>\n";
    }
  } else {
    foreach my $key ( sort keys %xmlmap ) {
      my $value = $result{ $xmlmap{$key} };
      if ( $xmlparse2::version > 1 ) {
        if ( $value eq "" ) {
          next;
        }
      }
      if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
        $value = "<![CDATA[$value]]>";
      }
      $message .= "  <$key>$value</$key>\n";
    }
    if ( $xmlparse2::version > 1 ) {
      $message .= "  <BillDetails>\n";
      foreach my $key (@billdetails) {
        my $value = $result{ $billdetails{$key} };
        if ( $value eq "" ) {
          next;
        }
        if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
          $value = "<![CDATA[$value]]>";
        }
        $message .= "    <$key>$value</$key>\n";
      }
      $message .= "  </BillDetails>\n";
      $message .= "  <Order>\n";
      foreach my $key (@order) {
        my $value = $result{ $order{$key} };
        if ( $value eq "" ) {
          next;
        }
        if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
          $value = "<![CDATA[$value]]>";
        }
        $message .= "    <$key>$value</$key>\n";
      }
      $message .= "  </Order>\n";
    }
    if ( $result{'mode'} =~ /bill_member|credit_member/ ) {
      foreach my $key (@membership) {
        my $value = $result{ $membership{$key} };
        if ( $xmlparse2::version > 1 ) {
          if ( $value eq "" ) {
            next;
          }
        }
        if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
          $value = "<![CDATA[$value]]>";
        }
        $message .= "  <$key>$value</$key>\n";
      }
    }
    if ( $result{'convfeeamt'} > 0 ) {
      $message .= "  <ConvenienceFee>\n";
      foreach my $key ( sort keys %convfeemap ) {
        my $value = $result{ $convfeemap{$key} };
        if ( $xmlparse2::version > 1 ) {
          if ( $value eq "" ) {
            next;
          }
        }
        if ( $value =~ /[^0-9a-zA-Z_\. ]/ ) {
          $value = "<![CDATA[$value]]>";
        }
        $message .= "  <$key>$value</$key>\n";
      }
      $message .= "  </ConvenienceFee>\n";
    }
  }
  if ( $xmlparse2::version > 1 ) {
    $message .= "</TransactionResponse>\n";
  } else {
    $message .= "</TransactionResponse$tranidx>\n";
  }
  return $message;
}

sub xml_wrapper {
  my ( $message_body, $acct_name ) = @_;

  my $features = new PlugNPay::Features($acct_name,'general');
  my $dtd = $features->get('xml_response_dtd') || '';

  if ($dtd eq '') {   
    if ( $xmlparse2::version == 4 ) {
      $dtd = "$xmlparse2::dtd_out3";
    } elsif ( $xmlparse2::version == 3 ) {
      $dtd = "$xmlparse2::dtd_out3";
    } elsif ( $xmlparse2::version > 1 ) {
      $dtd = "$xmlparse2::dtd_out2";
    } else {
      $dtd = $xmlparse2::dtd_out;
    }
  }

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
    gmtime( time() );

  my $now = sprintf( "%04d\-%02d\-%02dT%02d\:%02d\:%02d\+00\:00", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

  my $message = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n";

  $message .= "<!DOCTYPE PNPxml SYSTEM \"$dtd\">\n";
  $message .= "<PNPxml version=\"2.0\" timestamp=\"$now\">\n";
  $message .= "<Header>\n";
  $message .= "  <Merchant>\n";
  $message .= "    <AcctName>$acct_name</AcctName>\n";
  $message .= "  </Merchant>\n";
  $message .= "  <Version>$xmlparse2::version</Version>\n";
  $message .= "</Header>\n";

  $message .= "<Response>\n";

  $message .= "$message_body\n";

  $message .= "</Response>\n";
  $message .= "</PNPxml>\n";

  #$message .= "<xml>\n";

  return $message;
}

sub encode_string {
  my ($str) = @_;
  $str =~ s/(\W)/'%' . unpack("H2",$1)/ge;
  return $str;
}

sub filter_string {
  my ($str) = @_;

  $str =~ />(.*)?</;
  my $tmp = $1;
  $tmp =~ s/./X/g;
  $str =~ s/>.*?</>$tmp</g;
  return $str;
}

sub process_tran {    ##Line 382 -
  my (%query) = @_;
  my ( $dont_allow_admin, %result );
  my $env      = new PlugNPay::Environment();
  my $remoteIP = $env->get('PNP_CLIENT_IP');

  if ( -e "/home/p/pay1/outagefiles/oracletomysql.txt" ) {
    $dont_allow_admin = 1;
  } elsif ( -e "/home/p/pay1/outagefiles/highvolume.txt" ) {
    $dont_allow_admin = 2;
  }

  if ( $query{'orderID'} =~ /[A-Za-z]/ ) {
    delete $query{'orderID'};
  }

  my %featureHolder = %remote::feature;
  my @array         = %query;
  my $pnpremote     = remote->new(@array);

  if ( $query{'client'} eq "onestep" ) {
    %remote::feature = %featureHolder;
  }

  # Moved from below  DCP 20040226
  %query = %remote::query;

  (@remote::modes) = split( /\||\,/, $query{'mode'} );

  $query{'mode'} = $remote::modes[0];

  if ( $query{'mode'} =~ /^(add_member|delete_member|cancel_member|update_member|query_member|query_member_fuzzy|query_billing|passwrdtest|bill_member|credit_member|list_members|clone_member)$/ ) {
    ## check for membership table space, when calling a membership specific mode
    eval { my $dbh = &miscutils::dbhconnect( $query{'publisher-name'} ); };
    if ($@) {

      # reject the remote request, table space isn't present.
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'}     = "Account not setup for membership service. Contact Tech Support.";
      $result{'resp-code'}   = "PXX";
      return %result, %query;
    }
  }

  if ( ( $query{'mode'} =~ /^(mark|postauth|void|return|credit|newreturn|forceauth|reauth|returnprev|payment)$/ )
    || ( $query{'mode'} =~ /^(add_member|delete_member|cancel_member|update_member|query_member|query_billing|passwrdtest|bill_member|credit_member)$/ )
    || ( $query{'mode'} =~ /^(batchcommit|query_trans|batchassemble|batchauth|query_chargeback|test_mode|batchfile|tran_status)$/ )
    || ( $query{'mode'} =~ /^(dccoptout|inforetrieval|query_noc)$/ )
    || ( $query{'mode'} =~ /^(ewallet_reg|query_sv|activate_sv|fund_sv|remove_ecard)$/ ) ) {

    if ( $query{'mode'} eq "passwrdtest" ) {
      %result = $pnpremote->passwrdtest();
    } elsif ( $query{'mode'} =~ /^(mark|void|return|postauth|reauth|tran_status)$/ ) {
      if ( $dont_allow_admin == 1 ) {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'}     = "Mode currently disabled for maintenance.";
      } else {
        my $scriptname = $ENV{'SCRIPT_NAME'};
        $scriptname =~ /.*\/(.*?\.cgi)/;
        $scriptname                  = $1;
        $remote::query{'acct_code4'} = "Merchant Initiated:$scriptname:$remoteIP";
        %result                      = $pnpremote->trans_admin();
      }
    } elsif ( $query{'mode'} =~ /^(credit|newreturn|payment)$/ ) {
      %result = $pnpremote->newreturn();
    } elsif ( $query{'mode'} =~ /^(returnprev)$/ ) {
      %result = $pnpremote->returnprev();
    } elsif ( $query{'mode'} =~ /^(forceauth)$/ ) {
      %result = $pnpremote->forceauth();
    } elsif ( $query{'mode'} =~ /^(query_trans)$/ ) {
      if ( $dont_allow_admin >= 2 ) {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'}     = "Mode currently disabled for maintenance.";
      } else {
        $remote::query{'decryptflag'}   = '1';
        $remote::query{'showreceiptcc'} = 'yes';
        %result                         = $pnpremote->query_trans();
      }
    } elsif ( $query{'mode'} =~ /^(batchcommit)$/ ) {
      if ( $dont_allow_admin == 1 ) {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'}     = "Mode currently disabled for maintenance.";
      } else {
        %result = $pnpremote->batch_commit();
      }
    } elsif ( $query{'mode'} =~ /^(batchassemble)$/ ) {
      if ( $dont_allow_admin >= 2 ) {
        $result{'FinalStatus'} = "problem";
        $result{'MErrMsg'}     = "Mode currently disabled for maintenance.";
      } else {
        %result = $pnpremote->batch_assemble();
      }
    } elsif ( $query{'mode'} =~ /^(batchauth)$/ ) {
      %result = $pnpremote->batch_auth();
    } elsif ( $query{'mode'} =~ /^(batchfile)$/ ) {
      if ( $remote::query{'format'} !~ /^(icverify|no)$/ ) {
        $remote::query{'format'} = "yes";
      }
      %result = $pnpremote->batch_file();
    } elsif ( $query{'mode'} eq "add_member" ) {
      %result = $pnpremote->add_member();
    } elsif ( $query{'mode'} eq "delete_member" ) {
      %result = $pnpremote->delete_member();
    } elsif ( $query{'mode'} eq "cancel_member" ) {
      %result = $pnpremote->cancel_member();
    } elsif ( $query{'mode'} eq "update_member" ) {
      %result = $pnpremote->update_member();
    } elsif ( $query{'mode'} eq "query_member" ) {
      %result = $pnpremote->query_member();
    } elsif ( $query{'mode'} eq "query_billing" ) {
      %result = $pnpremote->query_billing();
    } elsif ( $query{'mode'} =~ /bill_member|credit_member/ ) {
      %result = $pnpremote->bill_member();
    } elsif ( $query{'mode'} eq "query_chargeback" ) {
      %result = $pnpremote->query_chargeback();
    } elsif ( $query{'mode'} eq "test_mode" ) {
      %result = $pnpremote->test_mode();
    } elsif ( $query{'mode'} eq "dccoptout" ) {
      %result = $pnpremote->dccoptout();
    } elsif ( $query{'mode'} eq "inforetrieval" ) {
      %result = $pnpremote->info_retrieval();
    } elsif ( $query{'mode'} eq "query_noc" ) {
      %result = $pnpremote->query_noc();
    }
    ## eCard Functions
    elsif ( $query{'mode'} =~ /^(query_sv|fund_sv|activate_sv|remove_ecard)$/ ) {
      %result = $pnpremote->ecard("$query{'mode'}");
    }
    ## eWallet Function
    elsif ( $query{'mode'} =~ /^(ewallet_reg)$/ ) {
      %result = $pnpremote->ewallet_reg();
    }
  } elsif ( ( $query{'mode'} eq "" )
    || ( $query{'mode'} =~ /^(auth|debug|calc|checkcard|authprev)$/ ) ) {
    if ( $query{'mode'} =~ /^authprev$/ ) {
      %result = $pnpremote->authprev();
      if ( $result{'FinalStatus'} eq "problem" ) {
        $query{'MErrMsg'} = $result{'MErrMsg'};
        return %result, %query;
      }
    }

    my @array   = %remote::query;
    my $payment = mckutils->new(@array);
    $mckutils::source = 'rmt';
    if ( $mckutils::query{'card-type'} eq "" ) {

      #$mckutils::query{'card-type'} = &mckutils::cardtype($mckutils::query{'card-number'});
      $mckutils::query{'card-type'} = &miscutils::cardtype( $mckutils::query{'card-number'} );    # Modified 20060928 to use miscutils sub.
    }

    %query = %mckutils::query;

    if ( $query{'mode'} eq "calc" ) {
      $payment->shopdata();
      $payment->calculate_discnt();
      $mckutils::query{'card-amount'} = $mckutils::query{'subtotal'} + $mckutils::query{'shipping'} + $mckutils::query{'tax'};
      $mckutils::query{'card-amount'} =
        sprintf( "%.2f", $mckutils::query{'card-amount'} );
      $query{'mode'} = shift(@remote::modes);
    }

    if ( ( ( $query{'testmode'} =~ /debug/i ) || ( $query{'mode'} =~ /debug/i ) )
      && ( $query{'card-name'} eq "pnptest" )
      && ( $query{'card-number'} =~ /^(4111111111111111|4025241600000007)$/ ) ) {
      %result = $payment->pnptest();
    } elsif ( $query{'mode'} =~ /^checkcard$/i ) {
      $mckutils::query{'card-amount'} = "1.00";
      $mckutils::query{'acct_code3'}  = "AVS_TEST";
      %result                         = $payment->purchase("auth");
      delete $result{'auth-code'};
      if ( $result{'FinalStatus'} eq "success" ) {
        my (%result1);
        if ($query{'card-number'} !~ /^(4111111111111111)$/) {
          my $price = sprintf("%3s %.2f","$mckutils::query{'currency'}",$mckutils::query{'card-amount'});
          %result1 = &miscutils::sendmserver($mckutils::query{'publisher-name'},"void",'acct_code4', "$mckutils::query{'acct_code4'}",'txn-type','marked','amount',"$price",'order-id',"$mckutils::orderID");
        }  else {
          $result1{'FinalStatus'} = "success";
        }
        if ( $result1{'FinalStatus'} eq "success" ) {
          $result{'void-msg'}   = $result1{'aux-msg'};
          $result{'VoidStatus'} = "success";
        } else {
          $result{'void-msg'}   = $result1{'aux-msg'};
          $result{'VoidStatus'} = "problem";
        }
      }

      if ( ( $remote::modes[1] eq "add_member" )
        && ( $result{'FinalStatus'} eq "success" ) ) {
        if ( exists $mckutils::query{'card-exp'} ) {
          $remote::query{'card-exp'} = $mckutils::query{'card-exp'};
        }
        if ( ( !exists $remote::query{'orderID'} )
          && ( exists $mckutils::query{'orderID'} ) ) {
          $remote::query{'orderID'} = $mckutils::query{'orderID'};
        }

        my %result1 = $pnpremote->add_member();
        foreach my $key ( sort keys %result1 ) {
          $result{'a00001'} .= "$key=$result1{$key}\&";
        }
        chop $result{'a00001'};
      }

      ##  DCP - Need to rework this we can't exit out and not return XML.
      #my @array = (%remote::query,%result);
      #$pnpremote->script_output(@array);
      #exit;
    } else {
      if ( $mckutils::query{'tdsflag'} == 1 ) {
        if ( ( $xmlparse2::tdsresult{'tdsfinal'} == 1 )
          && ( $xmlparse2::tdsresult{'status'} eq "N" ) ) {

          # Not allowed to continue transaction
          #print "IF 1<br>\n";
          $result{'FinalStatus'} = "problem";
          $result{'MErrMsg'}     = $xmlparse2::tdsresult{'descr'};
          $result{'tds_status'}  = $xmlparse2::tdsresult{'status'};

          #exit;
        } elsif ( $xmlparse2::tdsresult{'tdsfinal'} == 1 ) {

          # continue transaction, status empty or status=U up to merchant
          #print "IF 2<br>\n";
        } else {

          # merchant and cardholder enrolled. creating authentication request.
          #print "IF 3<br>\n";
          my $price = sprintf( "%s %.2f", $mckutils::query{'currency'}, $mckutils::query{'card-amount'} );

          %xmlparse2::tdsresult = &tds::authenticate(
            $mckutils::query{'publisher-name'}, $xmlparse2::tdsresult{'querystr'}, 'order-id',    $mckutils::query{'orderID'},
            'card-number',                      $mckutils::query{'card-number'},   'card-exp',    $mckutils::query{'card-exp'},
            'termurl',                          $mckutils::query{'termurl'},       'merchanturl', $mckutils::query{'merchanturl'},
            'amount',                           $price
          );
          if ( $xmlparse2::tdsresult{'status'} eq "Y" ) {

            # this web page gets printed on the customers browser
            #print "IF 4<br>\n";
            $result{'FinalStatus'} = "success";
            $result{'tdsauthreq'}  = $xmlparse2::tdsresult{'pareq'};
            my @array = ( %remote::query, %result );

            ##  DCP - Need to rework this  we can't exit out and not return XML.
            $pnpremote->script_output(@array);
            exit;
          } elsif ( $xmlparse2::tdsresult{'status'} eq "N" ) {

            # person not enrolled, up to merchant
            #print "IF 5<br>\n";
            $xmlparse2::tdsresult{'eci'} = "06";
          } elsif ( $xmlparse2::tdsresult{'descr'} ne "" ) {

            # something went wrong, up to merchant
            #print "IF 6<br>\n";
            $xmlparse2::tdsresult{'eci'} = "06";
            $result{'FinalStatus'}       = "problem";
            $result{'MErrMsg'}           = $xmlparse2::tdsresult{'descr'};
            $result{'tds_status'}        = $xmlparse2::tdsresult{'status'};
          } else {

            # merchant not enrolled in 3dsecure
            #print "IF 7<br>\n";
            $xmlparse2::tdsresult{'eci'} = "07";

            #$result{'FinalStatus'} = "problem";
            #$result{'MErrMsg'} = "Merchant not currently enrolled in tds.";
          }
        }

        $xmlparse2::debug_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
        &sysutils::filelog( "append", ">>$xmlparse2::debug_file\.tds" );
        open( DEBUG, ">>$xmlparse2::debug_file\.tds" );
        print DEBUG "DATE:$remote::now IP:$remote::remoteaddr, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$xmlparse2::pid, ";
        foreach my $key ( sort keys %xmlparse2::tdsresult ) {
          print DEBUG "$key:$xmlparse2::tdsresult{$key}, ";
        }
        print DEBUG "\n";
        close(DEBUG);

        #use Datalog
        my $logger = new PlugNPay::Logging::DataLog( { collection => 'xmlparse2_process_tran' } );
        my %logdata = ();
        $logdata{DATE}    = $remote::now;
        $logdata{IP}      = $remote::remoteaddr;
        $logdata{SCRIPT}  = $ENV{'SCRIPT_NAME'};
        $logdata{HOST}    = $ENV{'SERVER_NAME'};
        $logdata{PORT}    = $ENV{'SERVER_PORT'};
        $logdata{BROWSER} = $ENV{'HTTP_USER_AGENT'};
        $logdata{PID}     = $$;

        foreach my $key ( sort keys %xmlparse2::tdsresult ) {
          $logdata{$key} = $xmlparse2::tdsresult{$key};
        }
        $logger->log( \%logdata );

        if ( !exists $result{'FinalStatus'} ) {
          %result = $payment->purchase("auth");
        }
      } else {
        ### DCP - eWallet 20050129
        if ( ( exists $mckutils::query{'ewallet_id'} )
          && ( $mckutils::query{'profile_1'} ne "" ) ) {
          require rsautils;
          my ($unencrypted_data);
          my (%data) = split( '\,', $mckutils::query{'profile_1'} );
          delete $mckutils::query{'profile_1'};
          if ( $data{'enccardnumber'} ne "" ) {
            $unencrypted_data = &rsautils::rsa_decrypt_file( $data{'enccardnumber'}, $data{'length'}, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
          }
          if ( $mckutils::query{'paymethod'} =~ /^(credit|pl_|sv_)/ ) {
            $mckutils::query{'card-number'} = $unencrypted_data;
          } elsif ( $ewallet::query{'paymethod'} =~ /^onlinecheck$/ ) {
            ( $mckutils::query{'accountnum'}, $mckutils::query{'routingnum'}, $mckutils::query{'accttype'} ) = split( '\ ', $unencrypted_data );
          } else {
            ##  Invalid Paymethod
          }
          delete $data{'enccardnumber'};
          delete $data{'length'};

          %mckutils::query = ( %mckutils::query, %data );
          %result = $payment->purchase("auth");

          if ( ( $result{'FinalStatus'} eq "success" )
            && ( $result{'MErrMsg'} eq "Insufficient Funds SV" )
            && ( $mckutils::query{'profile_2'} ne "" ) ) {
            my ($unencrypted_data);
            my (%data1) = split( '\,', $mckutils::query{'profile_2'} );
            delete $mckutils::query{'profile_2'};
            if ( $data1{'enccardnumber'} ne "" ) {
              $unencrypted_data = &rsautils::rsa_decrypt_file( $data1{'enccardnumber'}, $data1{'length'}, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );
            }
            if ( $mckutils::query{'paymethod'} =~ /^(credit|pl_|sv_)/ ) {
              $mckutils::query{'card-number'} = $unencrypted_data;
            } elsif ( $ewallet::query{'paymethod'} =~ /^onlinecheck$/ ) {
              ( $mckutils::query{'accountnum'}, $mckutils::query{'routingnum'}, $mckutils::query{'accttype'} ) = split( '\ ', $unencrypted_data );
            } else {
              ##  Invalid Paymethod
            }
            $result{'auth-code'} = substr( $result{'auth-code'}, 0, 6 );
            $payment->database();
            delete $data1{'enccardnumber'};
            delete $data1{'length'};
            foreach my $key ( keys %data ) {
              $data{$key} = "";
            }
            %mckutils::query = ( %mckutils::query, %data, %data1 );
            %result = $payment->purchase("auth");
          }
          delete $mckutils::query{'profile_2'};
        } else {
          %result = $payment->purchase("auth");
        }
      }
    }

    if ( ( $result{'FinalStatus'} eq "success" )
      && ( $mckutils::query{'conv_fee_amt'} > 0 )
      && ( $result{'MErrMsg'} !~ /^Duplicate/ ) ) {
      my %orig = ();
      my @orig = ( 'orderID', 'card-amount', 'publisher-name', 'publisher-email', 'acct_code', 'acct_code2', 'acct_code3', 'amountcharged' );
      foreach my $var (@orig) {
        $orig{$var} = $mckutils::query{$var};
      }

      my %legacyorigfeature = %mckutils::feature;
      my $orgifeatures      = $mckutils::accountFeatures;

      ### Set Features for Conv. Account
      $mckutils::accountFeatures = new PlugNPay::Features( $mckutils::query{'conv_fee_acct'}, 'general' );

      #### To support legacy feature hash
      my $features = $mckutils::accountFeatures->getSetFeatures();
      foreach my $var (@$features) {
        $mckutils::feature{$var} = $mckutils::accountFeatures->get($var);
      }

      delete $mckutils::feature{'auth_sec_req'};
      $mckutils::accountFeatures->removeFeature('auth_sec_req');

      my $feeamt   = $mckutils::query{'conv_fee_amt'};
      my $feeact   = $mckutils::query{'conv_fee_acct'};
      my $failrule = $mckutils::query{'conv_fee_failrule'};

      $mckutils::query{'card-amount'}    = $feeamt;
      $mckutils::query{'publisher-name'} = $feeact;
      $mckutils::query{'merchant'}       = $feeact;

      ( $mckutils::query{'orderID'} ) = PlugNPay::Transaction::TransactionProcessor::generateOrderID();

      $mckutils::orderID = $mckutils::query{'orderID'};
      $mckutils::query{'acct_code3'} = "ConvFeeC:$orig{'orderID'}:$orig{'publisher-name'}";

      if ( $mckutils::feature{'conv_fee_authtype'} eq "authpostauth" ) {
        $mckutils::query{'authtype'} = 'authpostauth';
      }

      my %resultCF = $payment->purchase("auth");

      $result{'auth-codeCF'}   = substr( $resultCF{'auth-code'}, 0, 6 );
      $result{'FinalStatusCF'} = $resultCF{'FinalStatus'};
      $result{'MErrMsgCF'}     = $resultCF{'MErrMsg'};
      $result{'orderIDCF'}     = $mckutils::query{'orderID'};
      $result{'convfeeamt'}    = $feeamt;

      my ( %result1, $voidstatus );

      if ( ( $resultCF{'FinalStatus'} ne "success" )
        && ( $failrule =~ /VOID/i ) ) {
        my $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $orig{'card-amount'} );
        ## Void Main transaction
        for ( my $i = 1 ; $i <= 3 ; $i++ ) {
          %result1 = &miscutils::sendmserver(
            $orig{'publisher-name'}, "void", 'acct_code', $mckutils::query{'acct_code'},
            'acct_code4', "$mckutils::query{'acct_code4'}",
            'txn-type', 'auth', 'amount', "$price", 'order-id', "$orig{'orderID'}"
          );
          last if ( $result1{'FinalStatus'} eq "success" );
        }
        $result{'voidstatus'}  = $result1{'FinalStatus'};
        $result{'FinalStatus'} = $resultCF{'FinalStatus'};
        $result{'MErrMsg'}     = $resultCF{'MErrMsg'};
      }
      if ( $resultCF{'FinalStatus'} eq "success" ) {
        $result{'totalchrg'} =
          sprintf( "%.2f", $orig{'card-amount'} + $feeamt );
      }

      $payment->database();

      %mckutils::result = ( %mckutils::result, %result );

      foreach my $var (@orig) {
        $mckutils::query{$var} = $orig{$var};
      }

      ## Set Features Back to Primary Account
      $mckutils::accountFeatures     = $orgifeatures;
      $mckutils::query{'convfeeamt'} = $result{'convfeeamt'};
      $mckutils::conv_fee_amt        = $mckutils::query{'conv_fee_amt'};
      $mckutils::conv_fee_acct       = $mckutils::query{'conv_fee_acct'};
      $mckutils::conv_fee_oid        = $result{'orderIDCF'};

      #### To support legacy feature hash
      %mckutils::feature = %legacyorigfeature;

      delete $mckutils::query{'conv_fee_amt'};
      delete $mckutils::query{'conv_fee_acct'};
      delete $mckutils::query{'conv_fee_failrule'};
    }

    if ( $result{'FinalStatus'} eq "success" ) {
      eval {
        $payment->logFeesIfApplicable(\%mckutils::query, \%mckutils::result, $mckutils::adjustmentFlag, $mckutils::conv_fee_acct, $mckutils::conv_fee_oid);
      };
    }

    $result{'sresp'} = &simplified_resp( $mckutils::processor, $result{'FinalStatus'}, $result{'resp-code'} );

    $result{'auth-code'} = substr( $result{'auth-code'}, 0, 6 );

    $payment->database();

    if ( ( $remote::modes[1] eq "add_member" )
      && ( $result{'FinalStatus'} eq "success" ) ) {
      if ( exists $mckutils::query{'card-exp'} ) {
        $remote::query{'card-exp'} = $mckutils::query{'card-exp'};
      }
      if ( ( !exists $remote::query{'orderID'} )
        && ( exists $mckutils::query{'orderID'} ) ) {
        $remote::query{'orderID'} = $mckutils::query{'orderID'};
      }

      my %result1 = $pnpremote->add_member();
      foreach my $key ( sort keys %result1 ) {
        $result{'a00001'} .= "$key=$result1{$key}\&";
      }
      chop $result{'a00001'};
    } elsif ( ( $remote::modes[1] =~ /^(activate_sv|fund_sv)$/ )
      && ( $result{'FinalStatus'} eq "success" ) ) {
      $remote::query{'card-number'} = $mckutils::query{'card-number_sv'};
      $remote::query{'card-type'} =
        &miscutils::cardtype( $mckutils::query{'card-number_sv'} );

      my %result1 = $pnpremote->ecard( $remote::modes[1] );
      foreach my $key ( sort keys %result1 ) {
        $result{'a00001'} .= "$key=$result1{$key}\&";
      }
      chop $result{'a00001'};
    } elsif ( ( $remote::modes[1] =~ /^(auth_sv)$/ )
      && ( $result{'FinalStatus'} eq "success" )
      && ( $mckutils::query{'card-number_sv'} ne "" ) ) {
      my $orig_orderID = $mckutils::query{'orderID'};
      %result = ( %result, 'orderID', "$mckutils::query{'orderID'}" );
      foreach my $key ( sort keys %result ) {
        $result{'a00001'} .= "$key=$result{$key}\&";
      }
      chop $result{'a00001'};
      my (%data);
      $data{'card-number'} = $mckutils::query{'card-number_sv'};
      $data{'card-type'} =
        &miscutils::cardtype( $mckutils::query{'card-number_sv'} );
      $data{'card-amount'} = $mckutils::query{'card-amount_sv'};
      $data{'orderID'}     = &miscutils::incorderid($orig_orderID);

      my @array   = ( %remote::query, %data );
      my $payment = mckutils->new(@array);
      my %result1 = $payment->purchase("auth");
      $payment->database();

      %result1 = ( %result1, 'orderID', "$mckutils::query{'orderID'}" );
      foreach my $key ( sort keys %result1 ) {
        $result{'a00002'} .= "$key=$result1{$key}\&";
      }
      chop $result{'a00002'};

      if ( $result1{'FinalStatus'} ne "success" ) {
        ## Need to Void first CC Charge and return badcard.
        my (%result2);
        my $amount = $mckutils::query{'card-amount'};
        my $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $amount );

        for ( my $i = 1 ; $i <= 3 ; $i++ ) {
          if ( ( $mckutils::trans_type eq "auth" )
            && ( $mckutils::proc_type eq "authcapture" ) ) {
            %result2 = &miscutils::sendmserver(
              $mckutils::query{'publisher-name'},
              "return", 'acct_code', $mckutils::query{'acct_code'},
              'acct_code4', "$mckutils::query{'acct_code4'}",
              'amount', "$price", 'order-id', "$orig_orderID"
            );
          } else {
            %result2 = &miscutils::sendmserver(
              $mckutils::query{'publisher-name'},
              "void", 'acct_code', $mckutils::query{'acct_code'},
              'acct_code4', "$mckutils::query{'acct_code4'}",
              'txn-type', 'marked', 'amount', "$price", 'order-id', "$orig_orderID"
            );
          }
          last if ( $result2{'FinalStatus'} =~ /^(success|pending)$/ );
        }
        %result2 = ( %result2, 'orderID', "$orig_orderID" );
        foreach my $key ( sort keys %result2 ) {
          $result{'a00003'} .= "$key=$result2{$key}\&";
        }
        chop $result{'a00003'};
        $result{'FinalStatus'} = "badcard";
      }
    }

    ## Add Fulfillment Support to pnpremote_strict.cgi Line 636
    if ( ( $remote::modes[1] eq "fulfillment" )
      && ( $result{'FinalStatus'} eq "success" ) ) {
      my @product = $payment->fulfillment1();
      my $j       = 1;
      foreach my $fulfillvar (@product) {
        my @fulfillment = split( '\|', $fulfillvar );
        if ( exists $remote::query{'fulfillmentmap'} ) {
          my @map = split( '\|', $remote::query{'fulfillmentmap'} );
          my $i = 0;
          foreach my $var (@map) {
            $remote::query{"$var$j"} = $fulfillment[$i];
            $i++;
          }
        } else {
          my @map = ('fulfillment');
          my $i   = 0;
          foreach my $var (@map) {
            $remote::query{"$var$j"} = $fulfillment[$i];
            $i++;
          }
        }
        $j++;
      }
    }
    %remote::query = ( %remote::query, %mckutils::query, %result );
    $payment->email();
  } else {
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'}     = "Invalid Mode";
  }

  if ( exists $result{'auth-code'} ) {
    $result{'auth-code'} = substr( $result{'auth-code'}, 0, 6 );
  }

  return %result, %query;
}

sub simplified_resp {
  my ( $processor, $finalstatus, $respcode ) = @_;
  my ($sresp);
  if ( $processor =~ /^(maverick|visanet)$/ ) {
    if ( $finalstatus eq "success" ) {
      $sresp = "A";
    } elsif ( $respcode =~ /^(01|02)$/ ) {
      $sresp = "C";
    } elsif ( $respcode =~ /^(05|51|N7)$/ ) {
      $sresp = "D";
    } elsif ( $respcode =~ /^(04|07|41|43)$/ ) {
      $sresp = "P";
    } elsif ( $respcode =~ /^(54|P57)$/ ) {
      $sresp = "X";
    } else {
      $sresp = "E";
    }
  } elsif ( $processor =~ /^(fdms)$/ ) {
    if ( $finalstatus eq "success" ) {
      $sresp = "A";
    } elsif ( $respcode =~ /^(R)$/ ) {
      $sresp = "C";
    } elsif ( $respcode =~ /^(D)$/ ) {
      $sresp = "D";
    } elsif ( $respcode =~ /^()$/ ) {
      $sresp = "P";
    } elsif ( $respcode =~ /^(X|05|P57)$/ ) {
      $sresp = "X";
    } else {
      $sresp = "E";
    }
  } elsif ( $processor =~ /^(fdmsomaha)$/ ) {
    if ( $finalstatus eq "success" ) {
      $sresp = "A";
    } elsif ( $respcode =~ /^(C)$/ ) {
      $sresp = "C";
    } elsif ( $respcode =~ /^(R)$/ ) {
      $sresp = "D";
    } elsif ( $respcode =~ /^(P)$/ ) {
      $sresp = "P";
    } elsif ( $respcode =~ /^(X|05|P57)$/ ) {
      $sresp = "X";
    } else {
      $sresp = "E";
    }
  } elsif ( $processor =~ /^(paytechtampa|testprocessor)$/ ) {
    if ( $finalstatus eq "success" ) {
      $sresp = "A";
    } elsif ( $respcode =~ /^(R|P30|01)$/ ) {
      $sresp = "C";
    } elsif ( $respcode =~ /^(P30|200)$/ ) {
      $sresp = "D";
    } elsif ( $respcode =~ /^(04)$/ ) {
      $sresp = "P";
    } elsif ( $respcode =~ /^(X|205|P57)$/ ) {
      $sresp = "X";
    } else {
      $sresp = "E";
    }
  } elsif ( $processor =~ /^(paytechsalem)$/ ) {
    if ( $finalstatus eq "success" ) {
      $sresp = "A";
    } elsif ( $respcode =~ /^(401|P30)$/ ) {    ### Refer to Card Issuer/Call Auth Center
      $sresp = "C";
    } elsif ( $respcode =~ /^(P30|302|303|530|531)$/ ) {    ### Decline
      $sresp = "D";
    } elsif ( $respcode =~ /^(501|502)$/ ) {                ### Pick Up Card
      $sresp = "P";
    } elsif ( $respcode =~ /^(522|605|P57)$/ ) {            ### Card Expired
      $sresp = "X";
    } else {
      $sresp = "E";                                         ## Other Error
    }
  } elsif ( $processor =~ /^(global)$/ ) {
    if ( $finalstatus eq "success" ) {
      $sresp = "A";
    } elsif ( $respcode =~ /^(001|002)$/ ) {
      $sresp = "C";
    } elsif ( $respcode =~ /^(005|007)$/ ) {
      $sresp = "D";
    } elsif ( $respcode =~ /^(004)$/ ) {
      $sresp = "P";
    } elsif ( $respcode =~ /^(|054|P57)$/ ) {
      $sresp = "X";
    } else {
      $sresp = "E";
    }
  } elsif ( $processor =~ /^(cccc)$/ ) {
    if ( $finalstatus eq "success" ) {
      $sresp = "A";
    } elsif ( $respcode =~ /^(02)$/ ) {
      $sresp = "C";
    } elsif ( $respcode =~ /^(P30|04|61|51)$/ ) {
      $sresp = "D";
    } elsif ( $respcode =~ /^(41|42|43|67)$/ ) {
      $sresp = "P";
    } elsif ( $respcode =~ /^(54|P57)$/ ) {
      $sresp = "X";
    } else {
      $sresp = "E";
    }
  } elsif ( $processor =~ /^(surefire)$/ ) {
    my %surefire_resp = (
      '1',        'E', '2',        'E', '3',        'E', '4',        'E', '5',        'D', '20',       'E', '21',       'E', '30',       'E', '31',       'E', '32',       'E', '33',       'E',
      '34 1005',  'D', '34 1007',  'D', '34 1059',  'D', '34 4000',  'D', '56',       'E', '58',       'D', '63',       'E', '91',       'E', '92',       'E', '93',       'E', '101',      'E',
      '111',      'E', '113',      'D', '116',      'D', '117',      'D', '118',      'D', '119',      'E', '120',      'E', '121',      'E', '130',      'X', '131',      'E', '132',      'E',
      '133',      'E', '134',      'E', '137',      'E', '138',      'E', '139',      'E', '161',      'E', '163',      'E', '174',      'E', '175',      'E', '176',      'E', '178',      'E',
      '209',      'E', '210',      'E', '212 1000', 'A', '213',      'E', '221 1001', 'D', '221 1002', 'D', '221 1003', 'C', '221 1004', 'D', '221 1006', 'E', '221 1008', 'D', '221 1010', 'D',
      '221 1014', 'D', '221 1016', 'D', '221 1040', 'D', '221 1081', 'D', '221 1082', 'P', '221 1083', 'P', '222',      'E', '281',      'E', '284',      'E', '311',      'E', '321',      'E',
      '331',      'E', '333',      'E', '345',      'D', '346',      'E', '347',      'E', '348',      'D', '353',      'E', '356',      'E', '600',      'E', '601',      'E', '651',      'E',
      '652',      'E', '653',      'E', '701',      'E', '702',      'E', '731',      'E', '751',      'E', '752',      'E', '771',      'E'
    );

    if ( exists $surefire_resp{$respcode} ) {
      $sresp = $surefire_resp{$respcode};
    } else {
      $sresp = "E";
    }
  }
  return $sresp;

}

sub script_output {
  shift;
  my ($message) = @_;
  my $env       = new PlugNPay::Environment();
  my $remoteIP  = $env->get('PNP_CLIENT_IP');

  my $etime = time() - $xmlparse2::time;
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
    gmtime( time() );
  my $now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

  my $logging = 0;
  if ( exists $xmlparse2::feature{'log_xml_output'} ) {    # the feature "log_xml_output specifies the time logging was turned on and lasts for 6 hours.
    my ( $d1, $d2, $nowminus6hrs ) = &miscutils::gendatetime( -6 * 3600 );
    my ( $d3, $d4, $now )          = &miscutils::gendatetime();
    if ( ( $now >= $xmlparse2::feature{'log_xml_output'} )
      && ( $nowminus6hrs < $xmlparse2::feature{'log_xml_output'} ) ) {
      $logging = 1;
    }
  }

  if ($logging) {
    $xmlparse2::debug_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    &sysutils::filelog( "append", ">>$xmlparse2::debug_file" );
    open( DEBUG, ">>$xmlparse2::debug_file" );
    print DEBUG "DATE:$now, TIME:$etime, IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$xmlparse2::pid, ";
    if ( $remoteIP ne "69.15.158.39" ) {    ### DCP 20110417 - due to runaway script
      print DEBUG "RESPONSE MESSAGE:$message \n";
    } else {
      print DEBUG "ONESTEP - LOG OUTPUT Suppressed\n";
    }
    close(DEBUG);

    #use Datalog
    my $logger = new PlugNPay::Logging::DataLog( { collection => 'xmlparse_script_output' } );
    my %logdata = ();
    $logdata{DATE}    = $now;
    $logdata{TIME}    = $etime;
    $logdata{IP}      = $remoteIP;
    $logdata{SCRIPT}  = $ENV{'SCRIPT_NAME'};
    $logdata{HOST}    = $ENV{'SERVER_NAME'};
    $logdata{PORT}    = $ENV{'SERVER_PORT'};
    $logdata{BROWSER} = $ENV{'HTTP_USER_AGENT'};
    $logdata{PID}     = $xmlparse2::pid;

    if ( $remoteIP ne "69.15.158.39" ) {    ### DCP 20110417 - due to runaway script
      $logdata{RESPONSE_MESSAGE} = $message;
    } else {
      $logdata{RESPONSE_MESSAGE} = "ONESTEP - LOG OUTPUT Suppressed\n";
    }
    $logger->log( \%logdata );

  }

  &sysutils::filelog( "append", ">>$remote::path_debug" );
  open( DEBUG, ">>$remote::path_debug" );
  print DEBUG "DATE:$now, TIME:$etime, IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$xmlparse2::pid\n\n";
  close(DEBUG);

  #use Datalog
  my $logger = new PlugNPay::Logging::DataLog( { collection => 'xmlparse_script_output' } );
  my %logdata = ();
  $logdata{DATE}    = $now;
  $logdata{TIME}    = $etime;
  $logdata{IP}      = $remoteIP;
  $logdata{SCRIPT}  = $ENV{'SCRIPT_NAME'};
  $logdata{HOST}    = $ENV{'SERVER_NAME'};
  $logdata{PORT}    = $ENV{'SERVER_PORT'};
  $logdata{BROWSER} = $ENV{'HTTP_USER_AGENT'};
  $logdata{PID}     = $xmlparse2::pid;
  $logger->log( \%logdata );

  my $len = length($message);
  print header( -type => 'text/xml', -Content_length => "$len" );
  print "$message\n";
}

sub error_output {
  my ( $message, $acct_name ) = @_;
  my $env      = new PlugNPay::Environment();
  my $remoteIP = $env->get('PNP_CLIENT_IP');

  $xmlparse2::debug_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
  &sysutils::filelog( "append", ">>$xmlparse2::debug_file" );
  open( DEBUG, ">>$xmlparse2::debug_file" );
  print DEBUG
    "DATE:$xmlparse2::now, IP:$remoteIP, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, BROWSER:$ENV{'HTTP_USER_AGENT'}, PID:$xmlparse2::pid, ERROR MESSAGE:$message \n";
  close(DEBUG);

  #use Datalog
  my $logger = new PlugNPay::Logging::DataLog( { collection => 'xmlparse_error_output' } );
  my %logdata = ();
  $logdata{DATE}          = $xmlparse2::now;
  $logdata{IP}            = $remoteIP;
  $logdata{SCRIPT}        = $ENV{'SCRIPT_NAME'};
  $logdata{HOST}          = $ENV{'SERVER_NAME'};
  $logdata{PORT}          = $ENV{'SERVER_PORT'};
  $logdata{BROWSER}       = $ENV{'HTTP_USER_AGENT'};
  $logdata{PID}           = $xmlparse2::pid;
  $logdata{ERROR_MESSAGE} = $message;
  $logger->log( \%logdata );

  $message = "<FinalStatus>problem</FinalStatus>\n<MErrMsg>$message</MErrMsg>";
  $message = &xml_wrapper( $message, $acct_name );

  my $len = length($message);
  print header( -type => 'text/xml', -Content_length => "$len" );
  print "$message\n";
}

sub check_xml {
  my ( $decl_seen, $misc_seen, $doctype_seen, $element_seen );

  ($xmlparse2::file) = @_;

  while ( $xmlparse2::file =~ /[^<]*<(\/)?([^>]+)>/ ) {
    $xmlparse2::st_or_et = $1;
    $xmlparse2::gi       = $2;
    $xmlparse2::file     = $';

    # I recognize the following kinds of objects: XML declaration
    # (a particular type of processing instruction), processing # instructions, comments, doctype declaration, cdata marked
    # sections, and elements. Since the document production has
    # order rules I set a flag when a particlar type of object
    # has been processed. I invoke a subroutine to process each
    # type of object.

    if ( $xmlparse2::gi =~ /^\?XML/i ) {

      #print "AA\n";
      &process_decl( $decl_seen, $misc_seen, $doctype_seen, $element_seen );
      $decl_seen = 1;
    } elsif ( $xmlparse2::gi =~ /^\?/ ) {

      #print "BB\n";
      &process_pi( $decl_seen, $misc_seen, $doctype_seen, $element_seen );
      $misc_seen = 1;
    } elsif ( $xmlparse2::gi =~ /^!\-\-/ ) {

      #print "CC\n";
      &process_comment( $decl_seen, $misc_seen, $doctype_seen, $element_seen );
      $misc_seen = 1;
    } elsif ( $xmlparse2::gi =~ /^!DOCTYPE/ ) {

      #print "DD\n";
      &process_doctype( $decl_seen, $misc_seen, $doctype_seen, $element_seen );
      $doctype_seen = 1;
    } elsif ( $xmlparse2::gi =~ /^\!\[CDATA\[/ ) {

      #print "EE\n";
      &process_cdata( $decl_seen, $misc_seen, $doctype_seen, $element_seen );
    } else {

      #print "FF\n";
      &process_element( $decl_seen, $misc_seen, $doctype_seen, $element_seen );
      $element_seen = 1;
    }
  }

  # There are some checks to catch various errors at the end. I
  # make sure I have emptied the stack of all parents and I
  # make sure there is no uncontained character data hanging
  # around.

  &check_empty_stack( $decl_seen, $misc_seen, $doctype_seen, $element_seen );
  &check_uncontained_pcdata( $decl_seen, $misc_seen, $doctype_seen, $element_seen );

  # Print a happy message if there are no errors.

  my $validate_flag = &check_error_count();
  return $validate_flag;
}

#--------------------------------------------------------------------------#
sub check_error_count {
  if ( $xmlparse2::error_count == 0 ) {
    return 1;
  } else {
    return 0;
  }
}

#--------------------------------------------------------------------------#

# Check to see if the ancestor stack containing all parents up to the
# root is empty.

sub check_empty_stack {
  if ( $#xmlparse2::ancestors > -1 ) {
    &print_error_at_context();
  }
}

#--------------------------------------------------------------------------#

# Check to see if there is any uncontained PCDATA lying around (white space
# at the end of the document doesn't count). I check also to see that
# a root to the document was found which catches a null file error.

sub check_uncontained_pcdata {
  if ( $xmlparse2::file !~ /^\s*$/ ) {
    $xmlparse2::error_count++;
    $xmlparse2::error_str .= "\nNot well formed uncontained #PCDATA.\n";
  }
  if ( $xmlparse2::xmlROOT eq "" ) {
    $xmlparse2::error_count++;
    $xmlparse2::error_str .= "\nNull file.\n";
  }
}

#--------------------------------------------------------------------------#

# Check that the XML declaration is coded properly and in the correct
# position (before any other object in the file and occuring only
# once.)

sub process_decl {
  my ( $decl_seen, $misc_seen, $doctype_seen, $element_seen ) = @_;
  if ( $decl_seen || $misc_seen || $doctype_seen || $element_seen ) {
    $xmlparse2::error_count++;
    $xmlparse2::error_str .= "XML declaration can only be at the head of the document.\n";
  }

  # No checks are performed on processing instructions but the following
  # will be used to store the PI in the $xmlparse2::gi variable and advance the
  # file pointer.

  &process_pi( $decl_seen, $misc_seen, $doctype_seen, $element_seen );

  # This is slightly lazy since we allow version='1.0". It is quite simple
  # to fix just by making an OR of each parameter with either ' ' or " "
  # quote marks.

  #<?xml version="1.0" encoding="ISO-8859-1" RMD="NONE" ?>
  #print "GI:$xmlparse2::gi\n";
  #?xml version="1.0" encoding="ISO-8859-1" RMD="NONE" ?
  #if ($xmlparse2::gi !~/\?XML\s+version=[\'\"]1.0[\'\"](\s+encoding=[\'\"][^\'\"]*[\'\"])?.*\?/i) {
  if ( $xmlparse2::gi !~ /\?XML\s+version=[\'\"]1.0[\'\"](\s+encoding=[\'\"][^\'\"]*[\'\"])?(\s+RMD=[\'\"](NONE|INTERNAL|ALL)[\'\"])?\s*\?/i ) {
    $xmlparse2::error_count++;
    $xmlparse2::error_str .= "Format of XML declaration is wrong.\n";
  }

}

#--------------------------------------------------------------------------#

# Check that the Doctype statement is in the right position and, otherwise,
# make no attempt to parse its contents, including the root element. The
# root element will determined from the element production itself and
# the "claim" of the Doctype won't be verified.

sub process_doctype {
  my ( $decl_seen, $misc_seen, $doctype_seen, $element_seen ) = @_;
  if ( $doctype_seen || $element_seen ) {
    $xmlparse2::error_count++;
    $xmlparse2::error_str .= "Doctype can only appear once and must be within prolog.\n";
  }
  if ( $xmlparse2::gi =~ /\[/ && $xmlparse2::gi !~ /\]$/ ) {
    $xmlparse2::file =~ /\]>/;
    $xmlparse2::file = $';
    $xmlparse2::gi   = $xmlparse2::gi . $` . $&;
  }
  return $xmlparse2::gi, $xmlparse2::file;
}

#--------------------------------------------------------------------------#

# Performs the well-formed check necessary to verify that CDATA is not
# nested. We will pick up the wrong end of CDATA marker if this is the
# case so the error message is critical.

sub process_cdata {
  if ( $xmlparse2::gi !~ /\]\]$/ ) {
    $xmlparse2::file =~ /\]\]>/;
    $xmlparse2::file = $';
    $xmlparse2::gi   = $xmlparse2::gi . $` . "]]";
  }
  $xmlparse2::gi =~ /\!\[CDATA\[(.*)\]\]/;
  $xmlparse2::body = $1;
  if ( $xmlparse2::body =~ /<\!\[CDATA\[/ ) {
    $xmlparse2::error_str .= "Nested CDATA.\n";
    &print_error_at_context();
  }
}

#--------------------------------------------------------------------------#

# Performs the well-formed check of ensuring that '--' is not nested
# in the comment body which would cause problems for SGML processors.

sub process_comment {
  if ( $xmlparse2::gi !~ /\-\-$/ ) {
    $xmlparse2::file =~ /\-\->/;
    $xmlparse2::file = $';
    $xmlparse2::gi   = $xmlparse2::gi . $` . "--";
  }
  $xmlparse2::gi =~ /\!\-\-((.|\n)*)\-\-/;
  $xmlparse2::body = $1;
  if ( $xmlparse2::body =~ /\-\-/ ) {
    $xmlparse2::error_count++;
    $xmlparse2::error_str .= "Comment contains --.\n";
  }
}

#--------------------------------------------------------------------------#

# This is the main subroutine which handles the ancestor stack (in an
# array) checking the proper nesting of the element part of the document
# production.

sub process_element {
  my ( $decl_seen, $misc_seen, $doctype_seen, $element_seen ) = @_;

  my ( $parent, $xml_empty );

  # Distinguish between empty elements which do not add a parent to the
  # ancestor stack and elements which can have content.

  if ( $xmlparse2::gi =~ /\/$/ ) {
    $xml_empty = 1;
    $xmlparse2::gi =~ s/\/$//;

    # XML well-formedness says every document must have a container so an
    # empty element cannot be the root, even if it is the only element in
    # the document.

    if ( !$element_seen ) {
      $xmlparse2::error_str .= "Empty element <$xmlparse2::gi/> cannot be the root.\n";
    }
  } else {
    $xml_empty = 0;
  }

  # Check to see that attributes are well-formed.

  if ( $xmlparse2::gi =~ /\s/ ) {
    $xmlparse2::gi       = $`;
    $xmlparse2::attrline = $';
    $xmlparse2::attrs    = $xmlparse2::attrline;

    # This time we properly check to see that either ' ' or " " is
    # used to surround the attribute values.

    while ( $xmlparse2::attrs =~ /\s*([^\s=]*)\s*=\s*(("[^"]*")|('[^']*'))/ ) {

      # An end tag may not, of course, have attributes.

      if ( $xmlparse2::st_or_et eq "\/" ) {
        $xmlparse2::error_str = "Attributes may not be placed on end tags.\n";
        &print_error_at_context();
      }
      $xmlparse2::attrname = $1;

      # Check for a valid attribute name.

      &check_name($xmlparse2::attrname);
      $xmlparse2::attrs = $';
    }
    $xmlparse2::attrs =~ s/\s//g;

    # The above regex should have processed all the attributes. If anything
    # is left after getting rid of white space it is because the attribute
    # expressesion was malformed.

    if ( $xmlparse2::attrs ne "" ) {
      $xmlparse2::error_str = "Malformed attributes.\n";
      &print_error_at_context();
    }
  }

  # If XML is declared case-sensitive the following line should be
  # removed. At the moment it isn't so I set everything to lower
  # case so we can match start and end tags irrespective of case
  # differences.

  $xmlparse2::gi =~ tr/A-Z/a-z/;

  #print "ELEMENTSEEN:$element_seen, GI:$xmlparse2::gi:XX:XX\n\n";
  if ( !$element_seen ) {
    $xmlparse2::xmlROOT = $xmlparse2::gi;
  }

  # Check to see that the generic identifier is a well-formed name.

  &check_name($xmlparse2::gi);

  # If I have an end tag I just check the top of the stack, the
  # end tag must match the last parent or it is an error. If I
  # find an error I have I could either pop or not pop the stack.
  # What I want is to perform some manner of error recovery so
  # I can continue to report well-formed errors on the rest of
  # the document. If I pop the stack and my problem was caused
  # by a missing end tag I will end up reporting errors on every
  # tag thereafter. If I don't pop the stack and the problem
  # was caused by a misspelled end tag name I will also report
  # errors on every following tag. I happened to chose the latter.

  if ( $xmlparse2::st_or_et eq "\/" ) {
    $parent = $xmlparse2::ancestors[$#xmlparse2::ancestors];
    if ( $parent ne $xmlparse2::gi ) {
      if ( @xmlparse2::ancestors eq $xmlparse2::xmlROOT ) {
        @xmlparse2::ancestors = "";
      } else {
        &print_error_at_context;
      }
    } else {
      pop @xmlparse2::ancestors;
    }
  } else {

    # This is either an empty tag or a start tag. In the latter case
    # push the generic identifier onto the ancestor stack.

    if ( !$xml_empty ) {
      push( @xmlparse2::ancestors, $xmlparse2::gi );
    }
  }
  return $xmlparse2::gi, $xmlparse2::file;
}

#--------------------------------------------------------------------------#

# Skip over processing instructions.

sub process_pi {
  if ( $xmlparse2::gi !~ /\?$/ ) {
    $xmlparse2::file =~ /\?>/;
    $xmlparse2::gi   = $xmlparse2::gi . $` . "?";
    $xmlparse2::file = $';
  }
}

#--------------------------------------------------------------------------#

sub print_error_at_context {
  my ($first);

  # This routine prints out an error message with the contents of the
  # ancestor stack so the context of the error can be identified.

  # It would be most helpful to have line numbers. In principle it
  # is possible but more difficult since we choose to not process the
  # document line by line. We could still count line break characters
  # as we scan the document.

  # Nesting errors can cause every tag thereafter to generate an error
  # so stop at 10.

  if ( $xmlparse2::error_count == 10 ) {
    $xmlparse2::error_str .= "More than 10 errors ...\n";
    $xmlparse2::error_count++;
  } else {
    $xmlparse2::error_count++;
    $xmlparse2::error_str .= "Not well formed at context ";

    # Just cycle through the ancestor stack.

    foreach my $element (@xmlparse2::ancestors) {
      $xmlparse2::error_str .= "$first$element";
      $first = "->";
    }
    $first = "";
    $xmlparse2::error_str .= " tag: <$xmlparse2::st_or_et$xmlparse2::gi $xmlparse2::attrline>\n";
  }

}

#--------------------------------------------------------------------------#

# Check for a well-formed Name as defined in the Name production.

sub check_name {
  my ($name) = @_;
  if ( $name !~ /^[A-Za-z_:][\w\.\-:]*$/ ) {
    $xmlparse2::error_str .= "Invalid element or attribute name: $name\n";
    &print_error_at_context();
  }
}

#--------------------------------------------------------------------------#

1;
