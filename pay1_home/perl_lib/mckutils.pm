package mckutils;

use strict;

use CGI qw/:standard/;
use JSON::XS;
use MD5;
use NetAddr::IP;
use POSIX qw(ceil floor);
use PlugNPay::API;
use PlugNPay::COA;
use PlugNPay::CardData;
use PlugNPay::Client::AmexExpress;
use PlugNPay::Client::Masterpass;
use PlugNPay::ConvenienceFee;
use PlugNPay::Country::State;
use PlugNPay::CreditCard;
use PlugNPay::Currency;
use PlugNPay::DBConnection;
use PlugNPay::Email;
use PlugNPay::Environment;
use PlugNPay::Features;
use PlugNPay::Legacy::MckUtils::Receipt;
use PlugNPay::Legacy::MckUtils::Transition;
use PlugNPay::Logging::DataLog;
use PlugNPay::Logging::MessageLog;
use PlugNPay::Logging::Performance;
use PlugNPay::Merchant::VerificationHash::Digest;
use PlugNPay::PayScreens::Assets;
use PlugNPay::PayScreens::Cookie;
use PlugNPay::Processor::ResponseCode;
use PlugNPay::ResponseLink;
use PlugNPay::Sys::Time;
use PlugNPay::Token;
use PlugNPay::Transaction::DefaultValues;
use PlugNPay::Transaction::Logging::Adjustment;
use PlugNPay::Transaction::MapAPI;
use PlugNPay::Transaction::TransactionProcessor;
use PlugNPay::Transaction::TransactionRouting;
use PlugNPay::Transaction;
use PlugNPay::Username;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::Util::CardFilter;
use PlugNPay::Util::Hash;
use PlugNPay::Util::UniqueID;
use Text::Table;
use Time::Local;
use URI::Escape;
use URI;
use constants qw(%countries %USstates %USterritories %USCNprov);
use emailconfutils;
use miscutils;
use pnp_environment;
use rsautils;
use smpsutils;
use sysutils;

my (%result);

local (%mckutils::query);

sub new {
  my $type = shift;
  %mckutils::query = @_;

  $mckutils::path_web    = &pnp_environment::get('PNP_WEB');
  $mckutils::path_webtxt = &pnp_environment::get('PNP_WEB_TXT');

  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  $mckutils::transition            = "";
  $mckutils::max                   = "";
  $mckutils::trans_type            = "";
  $mckutils::pnp_debug             = "";
  $mckutils::postauthflag          = "";
  $mckutils::drop_ship_flag        = "";
  $mckutils::socketflag            = "";
  $mckutils::voidstatus            = "";
  $mckutils::proc_type             = "";
  $mckutils::sendpwinfo            = "";
  %mckutils::mark_flag             = "";
  $mckutils::domain                = "";
  $mckutils::company               = "";
  $mckutils::esub                  = "";
  $mckutils::browsertype           = "";
  $mckutils::success               = "";
  $mckutils::volumelimit           = 0;
  $mckutils::response_type         = "";
  $mckutils::reseller              = "";
  $mckutils::fraudtrack            = "";
  $mckutils::processor             = "";
  $mckutils::walletprocessor       = "";
  $mckutils::sendcc                = "";
  $mckutils::mystring              = "";
  $mckutils::filteredCC            = "";
  $mckutils::filteredRN            = "";
  $mckutils::filteredAN            = "";
  $mckutils::filteredSSN           = "";
  $mckutils::company_name          = "";
  $mckutils::time                  = time();
  $mckutils::paypairs_datanotfound = 0;
  $mckutils::submitted_amount      = 0;
  $mckutils::industrycode          = "";
  $mckutils::convfeeflag           = 0;
  $mckutils::skipsecurityflag      = 0;
  $mckutils::templatePath          = "";

  $mckutils::dcc          = "";
  $mckutils::buypassfraud = "";
  $mckutils::source       = "";
  $mckutils::freqcnt      = "";
  ## DCP - eWallet/Loyalty
  $mckutils::ew_customer_id = "";

  $mckutils::certitaxhost = "certitax";

  $mckutils::conv_fee_amt   = "";
  $mckutils::conv_fee_acct  = "";
  $mckutils::conv_fee_oid   = "";
  $mckutils::adjustmentFlag = 0;

  $mckutils::member_dbasetype = "mysql";

  my ($getallowed);

  @mckutils::attributes       = ();
  @mckutils::emailextrafields = ();
  @mckutils::timetest         = ();

  %mckutils::result = ();
  %result           = ();

  %mckutils::info      = ();
  %mckutils::cookie    = ();
  %mckutils::feature   = ();
  %mckutils::recurring = ();
  %mckutils::payplans  = ();
  %mckutils::times     = ();
  %mckutils::fconfig   = ();
  %mckutils::encquery  = ();

  $mckutils::success = "";

  if ( $mckutils::query{'pairsref'} ne "" ) {
    my ( $datafound, %pairs ) =
      &retrieve_pairs( $mckutils::query{'pairsref'} );

    if ( $datafound == 1 ) {
      my $ptCustomExists = grep { /^pt_custom_name/ } keys %pairs;
      if ($ptCustomExists) {
        my $api = new PlugNPay::API( 'payscreens', \%pairs );
        %pairs = %{ $api->getLegacyHyphenated() };
      }
      %mckutils::query = ( %pairs, %mckutils::query );
    } else {
      $mckutils::paypairs_datanotfound = 1;
    }
  }

  if ( $mckutils::query{'convert'} =~ /underscores/i ) {
    &underscore_to_hyphen();
    $mckutils::query{'convertflg'} = "1";
  }

  # Pre Card Amount Filter
  if ( exists $mckutils::query{'card-amount'} ) {
    $mckutils::query{'card-amount'} =~ s/[^0-9\.]//g;
    $mckutils::query{'card-amount'} =
      sprintf( "%.2f", $mckutils::query{'card-amount'} );
  }

  ### Transaction Routing DCP 20130607
  my $accountFeatures = new PlugNPay::Features( $mckutils::query{'publisher-name'}, 'general' );

  if ( $accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('startNew');
  }

  if ( ( $mckutils::query{'tranroutingflg'} == 1 )
    || ( $accountFeatures->get('tranroutingflg') == 1 ) ) {
    my $tr = new PlugNPay::Transaction::TransactionRouting();
    $tr->setLegacyTransaction( \%mckutils::query );
    my $un = $tr->tranRouting();
    if ( ( $un ne "" ) && ( $un ne $mckutils::query{'publisher-name'} ) ) {
      ## Add indicator, transaction has been rerouted and pointer to original account name.
      $mckutils::query{'preRoutedAccount'} = $mckutils::query{'publisher-name'};
      $mckutils::query{'publisher-name'}   = $un;
      delete $mckutils::query{'tranroutingflg'};
    }
  }
  ### Balance Routing DCP 20140416
  if ( ( $mckutils::query{'balanceroutingflg'} == 1 )
    || ( $accountFeatures->get('balanceroutingflg') == 1 ) ) {
    my $tr = new PlugNPay::Transaction::TransactionRouting();
    $tr->setLegacyTransaction( \%mckutils::query );
    my $un = $tr->balanceRouting();
    if ( ( $un ne "" ) && ( $un ne $mckutils::query{'publisher-name'} ) ) {
      $mckutils::query{'publisher-name'} = $un;
    }
  }

  if (
    ( $accountFeatures->get('defaultReceiptType') =~ /^(simple|itemized|pos_itemized|pos_simple)$/i )
    && ( ( $mckutils::query{'receipt_type'} eq "" )
      && ( $mckutils::query{'receipt-type'} eq "" ) )
    ) {
    $mckutils::query{'receipt_type'} = $accountFeatures->get('defaultReceiptType');
  }

  if ( ( $mckutils::query{'plan'} ne "" )
    && ( $ENV{'SCRIPT_NAME'} =~ /auth\.cgi/ ) ) {
    my @array = %mckutils::query;
    %mckutils::query = &mckutils::payment_plans(@array);
  }

  $mckutils::submitted_amount = $mckutils::query{'card-amount'};

  # Encrypted Swipe
  if (
    ( $mckutils::query{'magensacc'} ne "" )
    || ( ( $mckutils::query{'devicesn'} ne "" )
      && ( $mckutils::query{'KSN'} ne "" ) )
    ) {
    my $results;

    # Use PlugNPay::CreditCard which will see if magensacc was already decrypted and if not, it will decrypt.
    if ( ( defined $mckutils::query{'magensacc'} && $mckutils::query{'magensacc'} ne "" )
      && ( $mckutils::query{'swipedevice'} !~ /^ipad|idtechkybrd/ ) ) {

      #PGP encrypted string can be passed in thru magensacc as "pgpdata:<BASE64_STRING>"
      my $cc = new PlugNPay::CreditCard();
      $cc->setSwipeDevice( $mckutils::query{'swipedevice'} );
      $results = $cc->decryptMagensa( $mckutils::query{'magensacc'}, $mckutils::query{'publisher-name'} );
    }

    #######################################################################################################################################
    #                                                                                                                                     #
    # WARNING: MAGTEK IPADS, MOBILE CARD READERS, AND IDTECH KEYBOARD READERS WILL NOT WORK WITH PlugNPay::CreditCard()->decryptMagensa() #
    # Instead the code below will be used for these                                                                                       #
    #                                                                                                                                     #
    #######################################################################################################################################
    elsif (
      ( ( $mckutils::query{'magensacc'} ne "" ) && ( $mckutils::query{'swipedevice'} =~ /^ipad|idtechkybrd/ ) )
      || ( ( $mckutils::query{'devicesn'} ne "" )
        && ( $mckutils::query{'KSN'} ne "" ) )
      ) {
      if ( ( $mckutils::query{'MPStatus'} eq "" )
        && ( $mckutils::query{'MagnePrintStatus'} ne "" ) ) {
        $mckutils::query{'MPStatus'} = $mckutils::query{'MagnePrintStatus'};
      }
      my %input = ();
      my @magensa_variables =
        ( 'magensacc', 'devicesn', 'KSN', 'Track1', 'EncTrack1', 'EncTrack2', 'EncTrack3', 'EncMP', 'MPStatus', 'card-exp', 'swipedevice', 'publisher-name', 'EncPostalKSN', 'EncPostalCode' );
      foreach my $var (@magensa_variables) {
        if ( ( defined $mckutils::query{$var} )
          && ( $mckutils::query{$var} ne "" ) ) {
          $input{$var} = $mckutils::query{$var};
        }
      }
      require magensa;
      my %resultsHash = &magensa::decrypt( $mckutils::query{'magensacc'}, \%input );
      $results = \%resultsHash;
    }

    if ( !$results->{'error'} ) {
      $mckutils::query{'card-number'} = $results->{'PAN'};

      $mckutils::query{'card-exp'} = $results->{'card-exp'};

      if ( $results->{'card-cvv'} ne "" ) {
        $mckutils::query{'card-cvv'} = $results->{'card-cvv'};
      }
      if ( ( $mckutils::query{'card-zip'} eq "" )
        && ( $results->{'card-zip'} ne "" ) ) {
        $mckutils::query{'card-zip'} = $results->{'card-zip'};
      }
      if ( length( $results->{'magstripe'} ) > 25 ) {
        $mckutils::query{'magstripe'} = $results->{'magstripe'};
      }
    }
    $mckutils::query{'StatusMsg'}    = $results->{'StatusMsg'};
    $mckutils::query{'StatusCode'}   = $results->{'StatusCode'};
    $mckutils::query{'MagensaScore'} = $results->{'Score'};
  }

  # Non-encrypted swipe
  elsif ( ( exists $mckutils::query{'magstripe'} )
    && ( !exists $mckutils::query{'card-number'} ) ) {
    my @array = %mckutils::query;
    %mckutils::query = &input_swipe(@array);
  }

  if ( ( exists $mckutils::query{'paymentToken'} )
    && ( $mckutils::query{'card-number'} eq "" ) ) {
    my $cc = new PlugNPay::Token();
    my $redeemedToken = $cc->fromToken( $mckutils::query{'paymentToken'}, 'PROCESSING' );
    if ( $redeemedToken =~ /(\d+) (\d+)/ ) {
      my ( $routingnum, $accountnum ) = split( / /, $redeemedToken );
      my $ach = new PlugNPay::OnlineCheck();
      $ach->setABARoutingNumber($routingnum);
      $ach->setAccountNumber($accountnum);
      if ( $ach->verifyABARoutingNumber() ) {
        $mckutils::query{'routingnum'} = $routingnum;
        $mckutils::query{'accountnum'} = $accountnum;
      }
    } else {
      my $cc = new PlugNPay::CreditCard($redeemedToken);
      if ( $cc->verifyLuhn10() ) {
        $mckutils::query{'card-number'} = $redeemedToken;
      }
    }
  }

  $mckutils::cardtype = &miscutils::cardtype( $mckutils::query{'card-number'} );

  if ( ( $mckutils::query{'publisher-name'} =~ /^(skyhawkete)$/ )
    && ( $mckutils::cardtype =~ /^(JCB)$/ ) ) {
    $mckutils::query{'card-type'}      = $mckutils::cardtype;
    $mckutils::query{'publisher-name'} = "skyhawket1";
  }

  if ( ( $mckutils::query{'card-type'} eq "" )
    && ( $mckutils::cardtype ne "failure" ) ) {
    $mckutils::query{'card-type'} = $mckutils::cardtype;
  }

  ## Added DCP 20070609
  $mckutils::query{'publisher-name'} =~ s/[^0-9a-zA-Z]//g;
  $mckutils::query{'merchant'} =~ s/[^0-9a-zA-Z]//g;

  $mckutils::query{'publisher-name'} =
    substr( $mckutils::query{'publisher-name'}, 0, 12 );
  $mckutils::query{'merchant'} =
    substr( $mckutils::query{'merchant'}, 0, 12 );

  if ( ( $mckutils::query{'publisher-name'} =~ /^(rspinc2)$/ )
    && ( $mckutils::query{'card-name'} !~ /[a-zA-Z]/ ) ) {
    $mckutils::query{'card-name'} = "RSP Inc.";
  }

  my ( $processor, $acctFeatures );
  {    # this block is so that $ga doesn't accidently overwrite something else in this very large scope
    my $ga = new PlugNPay::GatewayAccount( $mckutils::query{'publisher-name'} );
    $processor = $ga->getCardProcessor();
    %mckutils::feature =
      %{ $ga->getFeatures()->getFeatures() };    # yes this is corrct

    my $cardProcessorAccount = new PlugNPay::Processor::Account(
      { gatewayAccount => "$ga",
        processorName  => $processor
      }
    );
    $mckutils::industrycode = $cardProcessorAccount->getIndustry();
  }

  ###  DCP 20110812 - Support of MonkeyMedia merchant
  if ( ( $mckutils::query{'amexlev2'} == 1 )
    && ( $mckutils::cardtype eq "AMEX" )
    && ( $mckutils::query{'publisher-name'} eq "boudin" ) ) {
    $mckutils::query{'commcardtype'} = "purchase";
  }

  ###  DCP 20110812 - Support of MonkeyMedia merchant
  if ( ( $mckutils::query{'publisher-name'} eq "boudin" )
    && ( $mckutils::query{'commcardtype'} ne "" ) ) {
    if ( $mckutils::query{'employeename'} ne "" ) {
      $mckutils::query{'shipname'} = $mckutils::query{'employeename'};
    }
    if ( $mckutils::query{'costcenternum'} ne "" ) {
      $mckutils::query{'address1'} = $mckutils::query{'costcenternum'};
    }

    if ( $mckutils::query{'costcenternum'} ne "" ) {
      $mckutils::query{'ponumber'} = "$mckutils::query{'costcenternum'}";
    }

    $mckutils::query{'easycart'}     = "1";
    $mckutils::query{'item1'}        = "PurchaseCard";
    $mckutils::query{'cost1'}        = "$mckutils::query{'card-amount'}";
    $mckutils::query{'quantity1'}    = "1";
    $mckutils::query{'description1'} = "$mckutils::query{'shipname'}";
    $mckutils::query{'unit1'}        = "NMB";

    if ( $mckutils::cardtype =~ /^(VISA|MSTR)$/ ) {
      $mckutils::query{'transflags'} = "level3";
    }
  }

  if ( ( $mckutils::query{'merchant'} ne "" )
    && ( $mckutils::query{'publisher-name'} eq "" ) ) {
    $mckutils::query{'publisher-name'} = $mckutils::query{'merchant'};
  } else {
    $mckutils::query{'merchant'} = $mckutils::query{'publisher-name'};
  }

  if ( ( $mckutils::query{'convert'} =~ /underscores/i )
    && ( $mckutils::query{'paymethod'} eq "swipe" ) ) {
    if ( ( $mckutils::query{'month-exp'} eq "" )
      && ( $mckutils::query{'month_exp'} ne "" ) ) {
      $mckutils::query{'month-exp'} = $mckutils::query{'month_exp'};
    }
    if ( ( $mckutils::query{'year-exp'} eq "" )
      && ( $mckutils::query{'year_exp'} ne "" ) ) {
      $mckutils::query{'year-exp'} = $mckutils::query{'year_exp'};
    }
  }

  $mckutils::accountFeatures = new PlugNPay::Features( $mckutils::query{'publisher-name'}, 'general' );

  ## Added DCP 20070609
  $mckutils::query{'publisher-name'} =~ s/[^0-9a-zA-Z]//g;
  $mckutils::query{'merchant'} =~ s/[^0-9a-zA-Z]//g;

  $mckutils::query{'publisher-name'} =
    substr( $mckutils::query{'publisher-name'}, 0, 12 );
  $mckutils::query{'merchant'} =
    substr( $mckutils::query{'merchant'}, 0, 12 );

  if ( $ENV{'SERVER_NAME'} =~ /pay\-gate/ ) {
    $mckutils::domain  = "pay\-gate.com";
    $mckutils::company = "World Wide Merchant Services";
    $mckutils::esub    = "WWMS";
  } elsif ( $ENV{'SERVER_NAME'} =~ /penzpay/ ) {
    $mckutils::domain  = "penzpay.com";
    $mckutils::company = "Epenzio Merchant Services";
    $mckutils::esub    = "EPZ";
  } elsif ( $ENV{'SERVER_NAME'} =~ /icommercegateway/ ) {
    $mckutils::domain  = "icommercegateway.com";
    $mckutils::company = "National Bancard Merchant Services";
    $mckutils::esub    = "NAB";
  } elsif ( $ENV{'SERVER_NAME'} =~ /cw-ebusiness/ ) {
    $mckutils::domain  = "cw-ebusiness.com";
    $mckutils::company = "Cable \& Wireless";
    $mckutils::esub    = "CW";
  } elsif ( $ENV{'SERVER_NAME'} =~ /eci-pay/ ) {
    $mckutils::domain  = "eci-pay.com";
    $mckutils::company = "ECI";
    $mckutils::esub    = "ECI";
  } else {
    $mckutils::domain  = "plugnpay.com";
    $mckutils::company = "Plug \& Pay Technologies, Inc.";
    $mckutils::esub    = "PnP";
  }

  if ( ( $ENV{'HTTP_COOKIE'} ne "" ) ) {
    my (@cookies) = split( '\;', $ENV{'HTTP_COOKIE'} );
    foreach my $var (@cookies) {
      my ( $name, $value ) = split( '=', $var );

      $name =~ s/ //g;
      $mckutils::cookie{$name} = $value;
    }
  }

  ###  DCP 20050121 - EWallet
  if ( exists $mckutils::query{'ewallet_id'} ) {
    require ewallet;
    my @array   = %mckutils::query;
    my $ewallet = ewallet->new(@array);
    if ( $ewallet::ew_customer_id ne "" ) {
      $mckutils::query{'ew_customer_id'} = $ewallet::ew_customer_id;
    }
    my %result = $ewallet->retrieve_pay_vehicle();
    %mckutils::query = ( %mckutils::query, %result );
  }

  ( $mckutils::orderID, $mckutils::query{'auth_date'} ) =
    miscutils::gendatetime();

  if ( exists $mckutils::query{'orderID'} ) {
    $mckutils::query{'orderID'} =~ s/[^0-9]//g;
  }

  if ( $mckutils::query{'orderID'} ne "" ) {

    #$mckutils::query{'orderID'} =~ s/[^0-9]//g;
    $mckutils::query{'orderID'} =
      substr( $mckutils::query{'orderID'}, 0, 23 );
    $mckutils::orderID = $mckutils::query{'orderID'};
  } else {
    $mckutils::query{'orderID'} = $mckutils::orderID;
  }

  my $COA = new PlugNPay::COA( $mckutils::query{'publisher-name'} );

  # do not apply adjustment to recurring payments when 'recurringSkipAdjustment' feature is set
  if ( ( $mckutils::query{'card-amount'} > 0 )
    && !( ( $mckutils::query{'transflags'} eq 'recurring' ) && ( $mckutils::feature{'recurringSkipAdjustment'} == 1 ) ) ) {
    ## Check if convfee or COA is setup on account
    if ( $mckutils::accountFeatures->get('convfee') ) {
      my %result = &mckutils::convfee();
      if ( $result{'surcharge'} ) {    ## Fee is a surcharge add it to subtotal
        $mckutils::query{'card-amount'} += $result{'feeamt'};
        $mckutils::query{'surcharge'} = $result{'feeamt'};
      } else {                         ### Conv Fee is not a surcharge
        if ( $result{'feeamt'} > 0 ) {
          $mckutils::query{'conv_fee_amt'}      = $result{'feeamt'};
          $mckutils::query{'conv_fee_acct'}     = $result{'feeacct'};
          $mckutils::query{'conv_fee_failrule'} = $result{'failrule'};
        }
      }
    } elsif ( $COA->getEnabled()
      || $mckutils::accountFeatures->get('cardcharge') ) {
      my %result = &mckutils::cardcharge();
      if ( !&overrideAdjustment() ) {

        # Surcharge Model || Optional Model
        if ( $result{'surcharge'} || $result{'optional'} ) {    ## Fee is a surcharge or optional, add it to subtotal
          $mckutils::query{'baseAmount'} = $mckutils::query{'card-amount'};
          $mckutils::query{'card-amount'} += $result{'feeamt'};
          $mckutils::query{'surcharge'} = $result{'feeamt'};
        }

        # Instant Discount Model
        elsif ( $result{'Discount'} ) {                         ## Fee is a discount subtract it from subtotal
          if ( ( $result{'feeamt'} < 0 )
            && ( $mckutils::query{'card-amount'} > 0 )
            && ( $mckutils::query{'card-amount'} > ( $result{'feeamt'} * -1 ) ) ) {
            $mckutils::query{'card-amount'} += $result{'feeamt'};
            $mckutils::query{'discount'} = $result{'feeamt'};
          }
        }

        # Intelligent Rate / New Conv Fee Models
        elsif ( $result{'fee'} ) {                              ### Conv Fee is not a surcharge
          if ( $result{'feeamt'} > 0 ) {
            $mckutils::query{'conv_fee_amt'}      = $result{'feeamt'};
            $mckutils::query{'conv_fee_acct'}     = $result{'feeacct'};
            $mckutils::query{'conv_fee_failrule'} = $result{'failrule'};
          }
        }

        # All Other Models
        else {
          $mckutils::query{'card-amount'} += $result{'feeamt'};
          $mckutils::query{'feeamt'} = $result{'feeamt'};
        }
      }
    } elsif ( $mckutils::accountFeatures->get('conv_fee') ) {
      my ( $feeamt, $feeacct, $failrule ) = &mckutils::conv_fee();
      if ( $feeamt > 0 ) {
        $mckutils::query{'conv_fee_amt'}      = $feeamt;
        $mckutils::query{'conv_fee_acct'}     = $feeacct;
        $mckutils::query{'conv_fee_failrule'} = $failrule;
      }
    }
  }

  if ( $mckutils::query{'currency'} eq "" ) {
    $mckutils::query{'currency'} = "usd";
  }

  ## DCP  20081114  to support Vermont Systems
  if ( $mckutils::query{'badcard-link'} =~ /VSI\\rectrac/i ) {
    $mckutils::query{'client'} = "rectrac";
  }

  if ( $mckutils::query{'client'} eq "cart32" ) {
    my @array = %mckutils::query;
    %mckutils::query = &cart32(@array);
  } elsif ( $mckutils::query{'client'} eq "ewallet" ) {
    &wallet();
  } elsif ( $mckutils::query{'client'} eq "shopsite" ) {
    &shopsite();
  } elsif ( $mckutils::query{'client'} eq "courtpay" ) {
    &courtpay();
  }

  $mckutils::query{'easycart'}   = $mckutils::query{'easycart'} + 0;
  $mckutils::query{'shipinfo'}   = $mckutils::query{'shipinfo'} + 0;
  $mckutils::query{'IPaddress'}  = $remote_ip;
  $mckutils::query{'User-Agent'} = $ENV{'HTTP_USER_AGENT'};
  $mckutils::query{'orderID'}    = $mckutils::orderID;

  if ( ( $mckutils::query{'User-Agent'} =~ /java/i )
    || ( $mckutils::query{'javaapiversion'} ne "" ) ) {
    open( JAVADEBUG, ">>/home/p/pay1/database/debug/javaapi_version.txt" );
    print JAVADEBUG "$mckutils::query{'publisher-name'}, ";
    if ( $mckutils::query{'User-Agent'} =~ /pnpjavaa/ ) {
      print JAVADEBUG "$mckutils::query{'User-Agent'}\n";
    } elsif ( $mckutils::query{'javaapiversion'} ne "" ) {
      print JAVADEBUG "$mckutils::query{'javaapiversion'}\n";
    } else {
      print JAVADEBUG "$mckutils::query{'User-Agent'}\n";
    }

    #use Datalog
    my %logdata = ();
    $logdata{'publisher-name'} = $mckutils::query{'publisher-name'};
    $logdata{'User-Agent'}     = $mckutils::query{'User-Agent'};
    if ( $mckutils::query{'javaapiversion'} ne "" ) {
      $logdata{'javaapiversion'} = $mckutils::query{'javaapiversion'};
    }
    my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
    $logger->log( \%logdata );
  }

  if ( ( ( $mckutils::query{'client'} eq "planetpay" ) || ( $mckutils::query{'enabledcc'} ne "" ) )
    && ( $mckutils::query{'mode'} !~ /^(forceauth)$/ )
    && ( $mckutils::query{'dccoptout'} ne "Y" ) ) {
    my ($test);
    my $dccbin = substr( $mckutils::query{'card-number'}, 0, 10 );
    $dccbin =~ s/[^0-9]//g;

    my $dbh = &miscutils::dbhconnect("pnpmisc");

    my $sth = $dbh->prepare(
      qq{
          select currency
          from bin_currency
          where startbin<=?
          and endbin>=?
          and currency<>'840'
       }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
    $sth->execute( "$dccbin", "$dccbin" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
    ($test) = $sth->fetchrow;
    $sth->finish;

    if (
      ( $mckutils::query{'publisher-name'} eq "pnpdemo" )
      && ( $mckutils::query{'card-number'} =~
        /(4025241600000007|4000000000000002|5100040000000004|4000000500000007|5100120000000004|4000010200000001|5100060000000002|4000020000000000|5100070000000001|4000030300000009|5100100000000006|4000040000000008|5100110000000005|4012001011000003|4123009780009788|5451408260008261)/
      )
      ) {
      $test = "test";
    }

    if ( $test ne "" ) {
      my $ga            = new PlugNPay::GatewayAccount( $mckutils::query{'publisher-name'} );
      my $dccusername   = $ga->getDCCAccount();
      my $merchant_bank = $ga->getMerchantBank();

      my $test2 = "1";
      if ( $merchant_bank ne "" ) {
        my $cardtype = &miscutils::cardtype( $mckutils::query{'card-number'} );
      }

      if ( ( $dccusername ne "" )
        && ( $test2 ne "" )
        && ( !-e "/home/p/pay1/batchfiles/stopdcc.txt" ) ) {
        my $dccGA = new PlugNPay::GatewayAccount($dccusername);
        $merchant_bank = $dccGA->getMerchantBank();

        $mckutils::query{'origacct'}       = $mckutils::query{'publisher-name'};
        $mckutils::query{'publisher-name'} = $dccusername;
        $mckutils::query{'merchant'}       = $mckutils::query{'publisher-name'};
        $mckutils::query{'dcc'}            = "yes";
        $mckutils::dcc                     = "yes";
      } else {
        $mckutils::query{'dcc'} = "no";
        $mckutils::dcc = "no";
      }

      ###  Added 20040206 by DCP to address a test account for Humbolt Bank
      if ( ( $merchant_bank =~ /humbolt/i )
        && ( $mckutils::dcc eq "yes" ) ) {
        if ( ( $dccbin =~ /^4/ )
          && ( -e "/home/p/pay1/batchfiles/planetpay/humboltvisa.txt" ) ) {
          $mckutils::query{'publisher-name'} = $mckutils::query{'origacct'};
          $mckutils::query{'merchant'}       = $mckutils::query{'publisher-name'};
          $mckutils::query{'dcc'}            = "no";
          $mckutils::dcc                     = "no";
        } elsif ( ( $dccbin =~ /^5/ ) && ( $test eq "036" ) ) {
          $mckutils::query{'publisher-name'} = $mckutils::query{'origacct'};
          $mckutils::query{'merchant'}       = $mckutils::query{'publisher-name'};
          $mckutils::query{'dcc'}            = "no";
          $mckutils::dcc                     = "no";
        }
      }
    }

    $dbh->disconnect;
  }
  ## Generic Filter
  my @alphanum_filter = ( 'dccinfo', 'dccoptout', 'authtype' );
  foreach my $var (@alphanum_filter) {
    if ( exists $mckutils::query{$var} ) {
      $mckutils::query{$var} =~ s/[^0-9a-zA-Z\,]//g;
    }
  }

  # SSN filter
  if ( exists $mckutils::query{'ssnum'} ) {
    $mckutils::query{'ssnum'} =~ s/[^0-9]//g;
    $mckutils::query{'ssnum'} = substr( $mckutils::query{'ssnum'}, 0, 20 );
    $mckutils::filteredSSN = ( 'X' x ( length( $mckutils::query{'ssnum'} ) - 4 ) ) . substr( $mckutils::query{'ssnum'}, -4, 4 );
  }

  # Account number filter
  if ( exists $mckutils::query{'accountnum'} ) {
    $mckutils::query{'accountnum'} =~ s/[^0-9]//g;
    $mckutils::query{'accountnum'} =
      substr( $mckutils::query{'accountnum'}, 0, 20 );
    $mckutils::filteredAN = ( 'X' x ( length( $mckutils::query{'accountnum'} ) ) ) . substr( $mckutils::query{'accountnum'}, -4, 4 );
  }

  # Routing number filter
  if ( exists $mckutils::query{'routingnum'} ) {
    $mckutils::query{'routingnum'} =~ s/[^0-9]//g;
    $mckutils::query{'routingnum'} =
      substr( $mckutils::query{'routingnum'}, 0, 9 );
    $mckutils::filteredRN = ( 'X' x ( length( $mckutils::query{'routingnum'} ) ) ) . substr( $mckutils::query{'routingnum'}, -4, 4 );
  }

  # Accttype filter
  if ( $mckutils::query{'accttype'} ne "" ) {
    $mckutils::query{'accttype'} =~ s/[^a-zA-Z]//g;
    $mckutils::query{'accttype'} =~ tr/A-Z/a-z/;
  } else {
    $mckutils::query{'accttype'} = 'credit';
  }

  # Cardissuenum filter
  if ( exists $mckutils::query{'cardissuenum'} ) {
    $mckutils::query{'cardissuenum'} =~ s/[^0-9]//g;
  }

  # Cardissuenum filter
  if ( exists $mckutils::query{'cardstartdate'} ) {
    $mckutils::query{'cardstartdate'} =~ s/[^0-9\/]//g;
  }

  my @card_data_found = ();

  # Card number filter
  if ( exists $mckutils::query{'card-number'} ) {
    my $i = 0;
    $mckutils::query{'card-number'} =~ s/[^0-9]//g;
    $mckutils::query{'card-number'} =
      substr( $mckutils::query{'card-number'}, 0, 20 );
    $mckutils::filteredCC = ( 'X' x ( length( $mckutils::query{'card-number'} ) ) ) . substr( $mckutils::query{'card-number'}, -4, 4 );
    foreach my $key ( keys %mckutils::query ) {
      next
        if ( inArray( lc $key, [ 'card-number', 'magstripe', 'track1', 'track2', 'card_num', 'cardnumber', 'magensacc', 'mpgiftcard', 'emvtags' ] ) );
      next if ( length( $mckutils::query{'card-number'} ) < 13 );

      if ( $mckutils::query{$key} =~ /$mckutils::query{'card-number'}/ ) {
        push( @card_data_found, $key );
        $mckutils::query{$key} =~ s/$mckutils::query{'card-number'}/CardDataFound/g;
      }
      if ( $key =~ /$mckutils::query{'card-number'}/ ) {
        my $tmpval = $mckutils::query{$key};
        delete $mckutils::query{$key};
        $key =~ s/$mckutils::query{'card-number'}/CardDataFoundKey/g;
        $key .= $i;
        $mckutils::query{$key} = $tmpval;
        push( @card_data_found, $key );
        $i++;
      }
    }
    if ( $#card_data_found >= 0 ) {
      my $time = gmtime(time);
      open( DEBUG, ">>/home/p/pay1/database/debug/carddata_found_in_otherfields.txt" );
      print DEBUG "TIME:$time, RA:$remote_ip, SCRIPT:$ENV{'SCRIPT_NAME'}, PID:$$, UN:$mckutils::query{'publisher-name'},  ";
      foreach my $var (@card_data_found) {
        print DEBUG "$var:";
      }
      print DEBUG "\n";
      close(DEBUG);

      #use Datalog
      my %logdata = ();
      foreach my $var (@card_data_found) {
        $logdata{$var} = $var;
      }
      my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
      $logger->log(
        { 'TIME'      => $time,
          'RA'        => $remote_ip,
          'SCRIPT'    => $ENV{'SCRIPT_NAME'},
          'PID'       => $$,
          'UN'        => $mckutils::query{'publisher-name'},
          'card_data' => \%logdata
        }
      );
    }
  }

  # Expiration Date Filter
  if ( exists $mckutils::query{'card-exp'} ) {
    $mckutils::query{'card-exp'} =~ /^(\d{1,2}).*?(\d{1,2})$/;
    $mckutils::query{'month-exp'} = $1;
    $mckutils::query{'year-exp'}  = $2;
  } else {
    $mckutils::query{'month-exp'} =
      substr( $mckutils::query{'month-exp'}, 0, 2 );
    $mckutils::query{'year-exp'} =
      substr( $mckutils::query{'year-exp'}, -2, 2 );
  }

  $mckutils::query{'month-exp'} =~ s/[^0-9]//;
  $mckutils::query{'year-exp'} =~ s/[^0-9]//;
  $mckutils::query{'card-exp'} = sprintf( '%02d/%02d', $mckutils::query{'month-exp'}, $mckutils::query{'year-exp'} );

  # Currency filter
  if ( exists $mckutils::query{'currency'} ) {
    $mckutils::query{'currency'} =~ tr/A-Z/a-z/;
    $mckutils::query{'currency'} =~ s/[^a-z]//g;
    $mckutils::query{'currency'} =
      substr( $mckutils::query{'currency'}, 0, 3 );
  }

  # Transflags filter
  if ( exists $mckutils::query{'transflags'} ) {
    $mckutils::query{'transflags'} =~ tr/A-Z/a-z/;
  }

  # Card Amount Filter
  if ( exists $mckutils::query{'card-amount'} ) {
    $mckutils::query{'card-amount'} =~ s/[^0-9\.]//g;
    $mckutils::query{'card-amount'} =
      sprintf( "%.2f", $mckutils::query{'card-amount'} );
    if ( $mckutils::query{'currency'} ne "usd" ) {
      if ( length( $mckutils::query{'card-amount'} ) > 12
        || $accountFeatures->get('highflg') eq '1' ) {
        $mckutils::query{'card-amount'} =
          substr( $mckutils::query{'card-amount'}, -12 );
      }
    } else {
      if ( length( $mckutils::query{'card-amount'} ) > 9 ) {
        $mckutils::query{'card-amount'} =
          substr( $mckutils::query{'card-amount'}, -9 );
      }
    }
  }

  # Email Address Filter
  if ( exists $mckutils::query{'email'} ) {
    $mckutils::query{'email'} = substr( $mckutils::query{'email'}, 0, 50 );
    $mckutils::query{'email'} =~ s/\;/\,/g;
    $mckutils::query{'email'} =~ s/[^_0-9a-zA-Z\-\@\.\,\+\#\&\*]//g;
    $mckutils::query{'email'} =~ tr/A-Z/a-z/;
    my $emtst = $mckutils::query{'email'};
    if ( ( $emtst =~ /\@place\.com/i )
      || ( $emtst =~ /\@yourdomain\.com/i )
      || ( $emtst =~ /\@company\.com/i )
      || ( $emtst =~ /\@notmail\.com/i ) ) {
      $mckutils::query{'email'} = "trash\@plugnpay.com";
    }
  }

  # Publisher Email Address Filter
  if ( exists $mckutils::query{'publisher-email'} ) {
    $mckutils::query{'publisher-email'} =
      substr( $mckutils::query{'publisher-email'}, 0, 50 );
    $mckutils::query{'publisher-email'} =~ s/\;/\,/g;
    $mckutils::query{'publisher-email'} =~ s/[^_0-9a-zA-Z\-\@\.\,]//g;
    my $emtst = $mckutils::query{'publisher-email'};
    if ( ( $emtst =~ /\@place\.com/i )
      || ( $emtst =~ /\@yourdomain\.com/i )
      || ( $emtst =~ /\@company\.com/i )
      || ( $emtst =~ /\@notmail\.com/i ) ) {
      $mckutils::query{'publisher-email'} = "trash\@plugnpay.com";
    }
  }

  #check cc-email vars and set to cc-mail
  if ( ( $mckutils::query{'cc-email'} ne "" )
    && ( $mckutils::query{'cc-mail'} eq "" ) ) {
    $mckutils::query{'cc-mail'} = $mckutils::query{'cc-email'};
    delete $mckutils::query{'cc-email'};
  }
  if ( exists $mckutils::query{'cc-mail'} ) {
    $mckutils::query{'cc-mail'} =
      substr( $mckutils::query{'cc-mail'}, 0, 100 );
    $mckutils::query{'cc-mail'} =~ s/\;/\,/g;
    $mckutils::query{'cc-mail'} =~ s/[^_0-9a-zA-Z\-\@\.\,]//g;
  }

  # Misc. Filters
  if ( $mckutils::query{'easycart'} ne "" ) {
    $mckutils::query{'easycart'} =~ s/[^0-9]//g;
    $mckutils::query{'easycart'} =
      substr( $mckutils::query{'easycart'}, 0, 1 );
  }
  if ( $mckutils::query{'card-cvv'} ne "" ) {
    $mckutils::query{'card-cvv'} =~ s/[^0-9]//g;
    $mckutils::query{'card-cvv'} =
      substr( $mckutils::query{'card-cvv'}, 0, 4 );
  }

  my $ffcnholder = $mckutils::query{'card-name'};

  if ( exists $mckutils::query{'card-name'} ) {
    if ( ( $mckutils::query{'card-name'} =~ /^configid/i )
      && ( $mckutils::query{'transflags'} =~ /test/i ) ) {
      $mckutils::query{'card-name'} =~ s/[^(?:\P{L}\p{L}*)+0-9\.\'\=\_]/ /g;
    } else {
      $mckutils::query{'card-name'} =~ s/[^(?:\P{L}\p{L}*)+0-9\.\']/ /g;
    }
  }

  if ( ( $mckutils::query{'publisher-name'} =~ /^(friendfind6)$/ )
    && ( $ffcnholder ne "$mckutils::query{'card-name'}" ) ) {
    my $filteredcn = $ffcnholder;
    $filteredcn =~ s/[^(?:\P{L}\p{L}*)+0-9\.\']/ /g;
    my $now = gmtime(time);
    open( FFDEBUG, ">>/home/p/pay1/database/debug/ff_cardname_debug.txt" );
    print FFDEBUG "DATE:$now, UN:$mckutils::query{'publisher-name'}, OID:$mckutils::orderID, ORIGCN:$ffcnholder, LANGCN:$filteredcn, FILTCN:$mckutils::query{'card-name'}\n";
    close(FFDEBUG);

    #use Datalog
    my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
    $logger->log(
      { 'DATE'   => $now,
        'UN'     => $mckutils::query{'publisher-name'},
        'OID'    => $mckutils::orderID,
        'ORIGCN' => $ffcnholder,
        'LANGCN' => $filteredcn,
        'FILTCN' => $mckutils::query{'card-name'}
      }
    );
  }

  if ( exists $mckutils::query{'card-city'} ) {
    $mckutils::query{'card-city'} =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;
  }
  if ( exists $mckutils::query{'card-state'} ) {
    $mckutils::query{'card-state'} =~ s/[^a-zA-Z\' ]/ /g;
  }
  if ( exists $mckutils::query{'card-zip'} ) {
    $mckutils::query{'card-zip'} =~ s/[^a-zA-Z\'0-9 ]/ /g;
    $mckutils::query{'card-zip'} =
      substr( $mckutils::query{'card-zip'}, 0, 11 );
  }
  if ( exists $mckutils::query{'card-country'} ) {
    $mckutils::query{'card-country'} =~ s/[^a-zA-Z\' ]/ /g;
  }
  if ( exists $mckutils::query{'card-address1'} ) {
    $mckutils::query{'card-address1'} =~ s/[\r\n]//;
    $mckutils::query{'card-address1'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if ( exists $mckutils::query{'card-address2'} ) {
    $mckutils::query{'card-address2'} =~ s/[\r\n]//;
    $mckutils::query{'card-address2'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if ( exists $mckutils::query{'city'} ) {
    $mckutils::query{'city'} =~ s/[^a-zA-Z0-9\.\-\' ]/ /g;
  }
  if ( exists $mckutils::query{'state'} ) {
    $mckutils::query{'state'} =~ s/[^a-zA-Z\' ]/ /g;
  }
  if ( exists $mckutils::query{'zip'} ) {
    $mckutils::query{'zip'} =~ s/[^a-zA-Z\'0-9 ]/ /g;
  }
  if ( exists $mckutils::query{'country'} ) {
    $mckutils::query{'country'} =~ s/[^a-zA-Z\' ]/ /g;
  }
  if ( exists $mckutils::query{'address1'} ) {
    $mckutils::query{'address1'} =~ s/[\r\n]//;
    $mckutils::query{'address1'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }
  if ( exists $mckutils::query{'address2'} ) {
    $mckutils::query{'address2'} =~ s/[\r\n]//;
    $mckutils::query{'address2'} =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\ \#\'\,]/ /g;
  }

  if ( exists $mckutils::query{'referrer'} ) {
    $mckutils::query{'referrer'} =~ s/[^_a-zA-Z0-9\.\@\-\/\:]/ /g;
  }
  if ( exists $mckutils::query{'phone'} ) {
    $mckutils::query{'phone'} =~ s/\)/\-/g;
    $mckutils::query{'phone'} =~ s/[^0-9\-]//g;
  }
  if ( exists $mckutils::query{'ipaddress'} ) {
    $mckutils::query{'ipaddress'} =~ s/[^0-9\.]//g;
    if ( $mckutils::query{'ipaddress'} !~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/ ) {
      $mckutils::query{'ipaddress'} = "";
    }
  }
  if ( exists $mckutils::query{'marketdata'} ) {
    $mckutils::query{'marketdata'} =
      substr( $mckutils::query{'marketdata'}, 0, 50 );
  }
  if ( exists $mckutils::query{'cashback'} ) {
    $mckutils::query{'cashback'} =~ s/[^0-9\.]//g;
  }

  # Find max # of items

  $mckutils::max = 0;
  my ($key);
  foreach $key ( sort keys %mckutils::query ) {
    if ( $key =~ /^(supplieremail)/ ) {
      $mckutils::drop_ship_flag = 1;
    }
    if ( ( $key =~ /^(quantity)/ ) && ( $mckutils::query{$key} > 0 ) ) {
      my $temp = substr( $key, 8 );
      if ( $mckutils::max < $temp ) {
        $mckutils::max = $temp;
      }
    }
  }

  if ( ( $mckutils::query{'acct_code4'} eq "" )
    && ( $mckutils::query{'plan'} ne "" )
    && ( $mckutils::query{'uname'} ne "" ) ) {
    my ($database);
    if ( $mckutils::query{'merchantdb'} ne "" ) {
      $database = $mckutils::query{'merchantdb'};
    } else {
      $database = $mckutils::query{'publisher-name'};
    }
    $database =~ s/[^0-9a-zA-Z]//g;
    $mckutils::query{'acct_code4'} = "$database:$mckutils::query{'uname'}";
  }

  %mckutils::countries = %constants::countries;

  %mckutils::US_CN_states = ( %constants::USstates, %constants::USterritories, %constants::USCNprov );

  %mckutils::avs_responses = (
    'Y', [ '5', 'Street and Postal Code match.' ],                                                   'X', [ '5', 'Exact Match - Address and Nine digit ZIP.' ],
    'D', [ '5', 'Street addresses and postal codes match for international transaction.' ],          'F', [ '5', 'Street addresses & postal codes match for international transaction (UK only).' ],
    'M', [ '5', 'Street addresses and postal codes match for international transaction.' ],          'A', [ '4', 'Address matches, ZIP does not.' ],
    'B', [ '4', 'Street addresses match for international transaction; postal code not verified.' ], 'W', [ '3', 'Nine digit ZIP match, Address does not.' ],
    'Z', [ '3', 'Five digit ZIP matches, address does not.' ],                                       'P', [ '3', 'Postal codes match for international transaction; street address not verified.' ],
    'E', [ '2', 'Address verification not allowed for card type.' ],                                 'R', [ '2', 'Retry - System Unavailable.' ],
    'S', [ '2', 'Card Type Not Supported.' ],                                                        'U', [ '2', 'US Address Information Unavailable.' ],
    'G', [ '2', 'International Address Information Unavailable.' ],                                  'C', [ '1', 'Street & postal code not verified for international transaction.' ],
    'I', [ '1', 'Address information not verified for international transaction.' ],                 'N', [ '0', 'Neither Address nor ZIP matches.' ],
  );

  return [], $type;
}

sub savorder {
  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('startSavorder');
  }

  if ( $mckutils::result{'Duplicate'} eq "yes" ) {
    return;
  }

  if ( $mckutils::accountFeatures->get('skipordersummaryflg') == 1 ) {
    return;
  }

  my ( $datestr, $timestr ) = &miscutils::gendatetime_only();

  my $merrloc = $mckutils::result{'aux-msg'} . $mckutils::result{'MErrLoc'} . $mckutils::result{'MErrMsg'};
  if ( $mckutils::feature{'mapmerrloc'} ne "" ) {
    $merrloc = $mckutils::query{"$mckutils::feature{'mapmerrloc'}"};
  }

  $merrloc = substr( $merrloc, 0, 199 );
  my $cardnum        = substr( $mckutils::query{'card-number'},                                                 0, 4 ) . '**' . substr( $mckutils::query{'card-number'}, -4, 4 );
  my $cardexp        = substr( $mckutils::query{'card-exp'},                                                    0, 9 );
  my $ipaddress      = substr( $mckutils::query{'IPaddress'},                                                   0, 79 );
  my $useragent      = substr( $mckutils::query{'User-Agent'},                                                  0, 79 );
  my $successlink    = substr( $mckutils::query{'success-link'},                                                0, 79 );
  my $publisheremail = substr( $mckutils::query{'publisher-email'},                                             0, 49 );
  my $email          = substr( $mckutils::query{'email'},                                                       0, 49 );
  my $cardaddr       = substr( "$mckutils::query{'card-address1'}" . " " . "$mckutils::query{'card-address2'}", 0, 79 );
  my $cardname       = substr( $mckutils::query{'card-name'},                                                   0, 39 );
  my $cardcompany    = substr( $mckutils::query{'card-company'},                                                0, 39 );
  my $cardcity       = substr( $mckutils::query{'card-city'},                                                   0, 39 );
  my $cardstate      = substr( $mckutils::query{'card-state'},                                                  0, 19 );
  my $cardzip        = substr( $mckutils::query{'card-zip'},                                                    0, 11 );
  my $cardcountry    = substr( $mckutils::query{'card-country'},                                                0, 19 );
  my $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $mckutils::query{'card-amount'} );
  my $cardamount = substr( $price, 0, 19 );

  #$cardamount = sprintf("%.2f", $cardamount);
  my $tax        = substr( $mckutils::query{'tax'},        0, 7 );
  my $shipping   = substr( $mckutils::query{'shipping'},   0, 7 );
  my $acct_code  = substr( $mckutils::query{'acct_code'},  0, 25 );
  my $acct_code2 = substr( $mckutils::query{'acct_code2'}, 0, 25 );
  my $acct_code3 = substr( $mckutils::query{'acct_code3'}, 0, 26 );
  my $acct_code4 = substr( $mckutils::query{'acct_code4'}, 0, 25 );

  my $morderid    = substr( $mckutils::query{'order-id'},    0, 23 );
  my $name        = substr( $mckutils::query{'shipname'},    0, 39 );
  my $shipcompany = substr( $mckutils::query{'shipcompany'}, 0, 39 );
  my $address1    = substr( $mckutils::query{'address1'},    0, 39 );
  my $address2    = substr( $mckutils::query{'address2'},    0, 39 );
  my $city        = substr( $mckutils::query{'city'},        0, 39 );
  my $state       = substr( $mckutils::query{'state'},       0, 39 );
  my $zip         = substr( $mckutils::query{'zip'},         0, 13 );
  my $country     = substr( $mckutils::query{'country'},     0, 13 );
  my $phone       = substr( $mckutils::query{'phone'},       0, 29 );
  my $shipphone   = substr( $mckutils::query{'shipphone'},   0, 29 );
  my $fax         = substr( $mckutils::query{'fax'},         0, 29 );
  my $referrer    = substr( $mckutils::query{'referrer'},    0, 39 );
  my $easycart    = substr( $mckutils::query{'easycart'},    0, 1 );
  my $plan        = substr( $mckutils::query{'plan'},        0, 10 );
  my $subacct     = substr( $mckutils::query{'subacct'},     0, 11 );
  my $customa     = substr( $mckutils::query{'customa'},     0, 39 );
  my $ship_type   = substr( $mckutils::query{'ship-type'},   0, 39 );
  my $shipmethod  = substr( $mckutils::query{'shipmethod'},  0, 39 );
  my $billcycle   = substr( $mckutils::query{'billcycle'},   0, 3 );

  if ( $customa eq "" ) {
    my $tmpaa = "$mckutils::query{'shipmethod'} $mckutils::query{'ship-type'}";
    $customa = substr( $tmpaa, 0, 39 );
  }

  my ($cardextra);

  if ( ( $mckutils::query{'paymethod'} eq "onlinecheck" )
    or ( $mckutils::query{'paymethod'} eq "check" ) ) {
    $mckutils::query{'card-number'} = "$mckutils::query{'routingnum'} $mckutils::query{'accountnum'}";
    $cardextra = $mckutils::query{'checknum'};
    $cardextra = substr( $cardextra, 0, 7 );
  }

  my ( $enccardnumber, $encryptedDataLen );
  my $cardnumber = $mckutils::query{'card-number'};

  $cardnumber = $mckutils::query{'card-number'};
  $cardnumber = substr( $cardnumber, 0, 6 ) . '****' . substr( $cardnumber, -4 );

  my ($authresult);
  if ( $mckutils::query{'fraudholdstatus'} eq "hold" ) {
    $authresult = "hold";
  } else {
    $authresult = "$result{'FinalStatus'}";
  }

  my $dbh_order = &miscutils::dbhconnect("pnpdata");
  %mckutils::info = ( %mckutils::query, %mckutils::result );

  my $dataToStore = {
    username       => $mckutils::query{'publisher-name'},
    orderid        => $mckutils::orderID,
    card_name      => $cardname,
    card_company   => $cardcompany,
    card_addr      => $cardaddr,
    card_city      => $cardcity,
    card_state     => $cardstate,
    card_zip       => $cardzip,
    card_country   => $cardcountry,
    amount         => $cardamount,
    tax            => $tax,
    shipping       => $shipping,
    trans_date     => $datestr,
    trans_time     => $timestr,
    result         => $authresult,
    descr          => $merrloc,
    acct_code      => $acct_code,
    acct_code2     => $acct_code2,
    acct_code3     => $acct_code3,
    acct_code4     => $acct_code4,
    morderid       => $morderid,
    shipname       => $name,
    shipcompany    => $shipcompany,
    shipaddr1      => $address1,
    shipaddr2      => $address2,
    shipcity       => $city,
    shipstate      => $state,
    shipzip        => $zip,
    shipcountry    => $country,
    phone          => $phone,
    shipphone      => $shipphone,
    fax            => $fax,
    email          => $email,
    plan           => $plan,
    billcycle      => $billcycle,
    easycart       => $easycart,
    ipaddress      => $ipaddress,
    useragent      => $useragent,
    referrer       => $referrer,
    card_number    => $cardnum,
    card_exp       => $cardexp,
    successlink    => $successlink,
    shipinfo       => $mckutils::query{'shipinfo'},
    publisheremail => $publisheremail,
    avs            => $result{'avs-code'},
    duplicate      => $result{'Duplicate'},
    enccardnumber  => $enccardnumber,
    length         => $encryptedDataLen,
    cardextra      => $cardextra,
    subacct        => $subacct,
    customa        => $customa
  };

  eval {
    my $ordersSaver = new PlugNPay::Transaction::Saver::Legacy();
    $ordersSaver->storeTransactionOrderSummaryMCKUtils($dataToStore);
  };
  if ($@) {
    &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr\n\ndied with: $@", %mckutils::query, %mckutils::result );
  }

  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('postInsertOrdersummary')->write();
  }

  if ( ( $result{'Duplicate'} eq "" )
    && ( $mckutils::query{'easycart'} == 1 ) ) {

    my $sth_check = $dbh_order->prepare(
      qq{
          select orderid
          from orderdetails
          where orderid=?
          and username=?
    }
    );
    $sth_check->execute( "$mckutils::orderID", "$mckutils::query{'publisher-name'}" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query, %mckutils::result );
    my ($checkorderid) = $sth_check->fetchrow;
    $sth_check->finish;

    if ( $checkorderid eq "" ) {
      my ($i);
      for ( $i = 1 ; $i <= $mckutils::max ; $i++ ) {
        my $item        = substr( $mckutils::query{"item$i"},        0, 23 );
        my $quantity    = substr( $mckutils::query{"quantity$i"},    0, 5 );
        my $cost        = substr( $mckutils::query{"cost$i"},        0, 9 );
        my $description = substr( $mckutils::query{"description$i"}, 0, 79 );
        my $customa     = substr( $mckutils::query{"customa$i"},     0, 19 );
        my $customb     = substr( $mckutils::query{"customb$i"},     0, 19 );
        my $customc     = substr( $mckutils::query{"customc$i"},     0, 19 );
        my $customd     = substr( $mckutils::query{"customd$i"},     0, 19 );
        my $custome     = substr( $mckutils::query{"custome$i"},     0, 19 );
        my $unit        = substr( $mckutils::query{"unit$i"},        0, 9 );

        my ($today) = &miscutils::gendatetime_only();

        if ( $mckutils::query{"quantity$i"} > 0 ) {
          my $sth_details = $dbh_order->prepare(
            qq{
              insert into orderdetails
              (username,trans_date,orderid,item,quantity,cost,description,
                     customa,customb,customc,customd,custome,unit)
              values (?,?,?,?,?,?,?,?,?,?,?,?,?)
          }
          );
          $sth_details->execute( "$mckutils::query{'publisher-name'}",
            "$today", "$mckutils::orderID", "$item", "$quantity", "$cost", "$description", "$customa", "$customb", "$customc", "$customd", "$custome", "$unit" )
            or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query, %mckutils::result );
          $sth_details->finish;
        }
      }
      if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
        new PlugNPay::Logging::Performance('postInsertOrderdetail');
      }
    }
  }

  $dbh_order->disconnect;

}

sub upsell_dbase {
  my $publishername = $mckutils::query{'publisher-name'};
  $publishername =~ s/[^0-9a-zA-Z]//g;
  &sysutils::filelog( "append", ">>/home/p/pay1/database/$publishername.upsell.txt" );
  open( UPSELLBASE, ">>/home/p/pay1/database/$publishername.upsell.txt" );
  print UPSELLBASE "TIME:$mckutils::time>";
  print UPSELLBASE $mckutils::query{'orderID'} . ">";
  print UPSELLBASE $mckutils::query{'IPaddress'} . ">";
  print UPSELLBASE $mckutils::query{'referrer'} . ">";
  print UPSELLBASE $mckutils::query{'card-amount'} . ">";
  print UPSELLBASE $mckutils::query{'upsellord'} . "\n";
  close(UPSELLBASE);
}

sub database {

  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  if ( -e "/home/pay1/outagefiles/useDataLog.txt" ) {
    &datalog();
  }

  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('startDatabase');
  }

  my %database = ( %mckutils::result, %mckutils::query );

  my $time = gmtime(time);
  my ($file_path);
  my ($today) = &miscutils::gendatetime_only();
  my $mnth = substr( $today, 4, 2 );

  my $publishername = $mckutils::query{'publisher-name'};
  $publishername =~ s/[^0-9a-zA-Z]//g;
  my $dir = substr( $publishername, 0, 1 );
  $dir =~ tr/A-Z/a-z/;
  $file_path = "/home/p/pay1/database/$dir/$publishername$mnth.txt";
  &sysutils::filelog( "append", ">>$file_path" );
  my $etime = time() - $mckutils::time;
  open( DATABASE, ">>$file_path" );
  print DATABASE "TIME:$time, ETIME:$etime, RA:$remote_ip, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, ";
  print DATABASE "PORT:$ENV{'SERVER_PORT'}, PID:$$, CT:$mckutils::cardtype, RM:$ENV{'REQUEST_METHOD'}, TMPLATE:$mckutils::templatePath, ";

  %database = &log_filter( \%database );
  foreach my $key ( sort keys %database ) {
    if ( ( $database{'client'} eq "mm" ) && ( $key eq "Sign" ) ) {
      print DATABASE "$key:Signature Present, ";
    } elsif ( $key =~ /^(message)$/i ) {
      print DATABASE "$key:XXXX, ";
    } else {
      print DATABASE "$key:$database{$key}, ";
    }
  }
  foreach my $key ( sort keys %mckutils::feature ) {
    print DATABASE "F:$key:$mckutils::feature{$key}, ";
  }
  foreach my $key ( sort keys %mckutils::fconfig ) {
    print DATABASE "FC:$key:$mckutils::fconfig{$key}, ";
  }
  print DATABASE "$mckutils::freqcnt";
  print DATABASE "\n";
  close(DATABASE);

  $mckutils::query{'elapsedTimePurchase'} = $etime;

  &savorder();

  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('postSavorder');
  }
}

sub datalog {

  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('startDatabase');
  }

  my %database = ( %mckutils::result, %mckutils::query );

  my $time  = gmtime(time);
  my $etime = time() - $mckutils::time;

  my %filteredQuery  = &log_filter( \%mckutils::query );
  my %filteredResult = &log_filter( \%mckutils::result );
  my %features       = %mckutils::feature;
  my %fraudConfig    = %mckutils::fconfig;

  foreach my $key ( keys %features ) {
    if ( $features{$key} eq '' ) {
      delete $features{$key};
    }
  }

  foreach my $key ( keys %fraudConfig ) {
    if ( $fraudConfig{$key} eq '' ) {
      delete $fraudConfig{$key};
    }
  }

  foreach my $key ( keys %filteredResult ) {
    $filteredQuery{$key} = $filteredResult{$key};
  }

  $filteredQuery{'derivedCardType'} = $mckutils::cardtype;

  # convert numbers to ... numbers.
  foreach my $key ( 'amountcharged', 'card-amount', 'year-exp', 'month-exp', 'auth_date', 'pt_subtotal' ) {
    eval { $filteredQuery{$key} = $filteredQuery{$key} + 0; };
  }

  # this can be long so we just get the first 100 characters of it for logging.
  if ( $filteredQuery{'message'} ne '' ) {
    $filteredQuery{'message'} =
      substr( $filteredQuery{'message'}, 0, 100 ) . '...';
  }

  my $dataToLog = {
    dataFormat      => 'legacy',
    merchant        => $filteredQuery{'merchant'},
    logTime         => $time,
    startTime       => $mckutils::time,
    duration        => $etime,
    remoteAddress   => $remote_ip,
    script          => $ENV{'SCRIPT_NAME'},
    host            => $ENV{'SERVER_NAME'},
    port            => $ENV{'SERVER_PORT'},
    pid             => $ENV{'SERVER_PORT'},
    template        => $mckutils::templatePath,
    transactionData => \%filteredQuery,
    features        => \%features,
    fraudConfig     => \%fraudConfig
  };

  my $dataLogger = new PlugNPay::Logging::DataLog( { collection => 'merchantTransactionLogs' } );
  my ($json) = $dataLogger->log($dataToLog);

  eval {
    if ($json) {
      my ($date) = miscutils::gendatetime_only();

      my $merchant = lc $filteredQuery{'merchant'};
      $merchant =~ s/[^a-z0-9_]//g;
      my $merchantPrefix  = substr( $merchant, 0, 2 );
      my $merchantLogPath = '/home/pay1/logs/merchant/' . $date . '/' . $merchantPrefix . '/';
      my $merchantLogFile = $merchant . '.' . $date . '.log';

      if ( !-d $merchantLogPath ) {
        system( 'mkdir -p ' . $merchantLogPath );
      }

      my $fh;
      open( $fh, '>>', $merchantLogPath . $merchantLogFile );
      print $fh $json . "\n";
      close($fh);
    }
  };

  $mckutils::query{'elapsedTimePurchase'} = $etime;

}

sub purchase {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my $type = shift;
  my ($purchasetype) = @_;
  my ( $addr, $country, $amount, $price );

  # Variables to monitor prcesses times.
  my ( $total, $start, $timeresult, $tresult, $credit, $fraud, $a );

  if ( -e "/home/p/pay1/outagefiles/returnproblem.txt" ) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "System Down forMaintenance.";
    $result{'resp-code'}   = "P150";
    %mckutils::result      = %result;
    return %result;
  }

  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('startPurchase');
  }

  %result              = ();
  %mckutils::result    = ();
  @miscutils::timetest = ();
  my %receipt = ();

  $mckutils::timetest[ ++$#mckutils::timetest ] = "start_purchase";
  $mckutils::timetest[ ++$#mckutils::timetest ] = time();

  my $dbh = &miscutils::dbhconnect("pnpmisc");

  $mckutils::timetest[ ++$#mckutils::timetest ] = "post_pnpdata_connect";
  $mckutils::timetest[ ++$#mckutils::timetest ] = time();

  my $ga              = new PlugNPay::GatewayAccount( $mckutils::query{'publisher-name'} );
  my $processor       = $ga->getCardProcessor();
  my $tdsprocessor    = $ga->getTDSProcessor();
  my $chkprocessor    = $ga->getCheckProcessor();
  my $walletprocessor = $ga->getWalletProcessor();

  my $reseller      = $ga->getReseller();
  my $testmode      = $ga->isTestModeEnabled();
  my $status        = $ga->getStatus();
  my $cards_allowed = $ga->getCardsAllowed();
  my $dccusername   = $ga->getDCCAccount();
  my $agentcode     = $ga->getAgentCode();
  my $startdate     = $ga->getStartDate();
  my $features      = $ga->getFeatures();
  my $fraud_config  = $ga->getFraudConfig();      #string

  my $email = $ga->getBillingContact()->getEmailAddress();

  # processor account related settings
  my ( $proc_type, $currency, $retailflag );
  eval {
    my $cardProcessorAccount = new PlugNPay::Processor::Account(
      { gatewayAccount => "$ga",
        processorName  => $processor
      }
    );
    $proc_type  = $cardProcessorAccount->getSettingValue("authType");
    $currency   = $cardProcessorAccount->getSettingValue("currency");
    $retailflag = $cardProcessorAccount->getIndustry();
  };

  my $mainContact = $ga->getMainContact();
  my $merchemail  = $mainContact->getEmailAddress();
  my %receipt;
  if ( inArray( $mckutils::query{'publisher-name'}, [ 'jhewica', 'jhtnica', 'jhcnica' ] ) ) {
    my $receiptGatewayAccount = new PlugNPay::GatewayAccount( $mckutils::query{'acct_code'} );
    my $receiptMainContact    = $receiptGatewayAccount->getMainContact();
    $receipt{'receipt-company'}  = $receiptMainContact->getCompany();
    $receipt{'receipt-address1'} = $receiptMainContact->getAddress1();
    $receipt{'receipt-address2'} = $receiptMainContact->getAddress2();
    $receipt{'receipt-city'}     = $receiptMainContact->getCity();
    $receipt{'receipt-state'}    = $receiptMainContact->getState();
    $receipt{'receipt-zip'}      = $receiptMainContact->getPostalCode();
    $receipt{'receipt-country'}  = $receiptMainContact->getCountry();
    $receipt{'receipt-phone'}    = $receiptMainContact->getPhone();
  } else {
    $receipt{'receipt-company'}  = $mainContact->getCompany();
    $receipt{'receipt-address1'} = $mainContact->getAddress1();
    $receipt{'receipt-address2'} = $mainContact->getAddress2();
    $receipt{'receipt-city'}     = $mainContact->getCity();
    $receipt{'receipt-state'}    = $mainContact->getState();
    $receipt{'receipt-zip'}      = $mainContact->getPostalCode();
    $receipt{'receipt-country'}  = $mainContact->getCountry();
    $receipt{'receipt-phone'}    = $mainContact->getPhone();
  }

  %mckutils::feature = %{ $features->getFeatures() };

  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    ## Log metaData
    new PlugNPay::Logging::Performance('logMetadata')->addMetadata(
      { 'orderID'      => $mckutils::orderID,
        'username'     => $mckutils::query{'publisher-name'},
        'processor'    => $processor,
        'chkprocessor' => $chkprocessor
      }
    );
  }

  if ( $reseller =~ /^(premier1)$/ ) {
    $mckutils::query{'marketdata'} =
      substr( $receipt{'receipt-company'}, 0, 12 );
  }

  if ( $agentcode =~ /natl|ff/i ) {
    $mckutils::feature{'bindetails'} = 1;
  }

  my $populateReceiptData = 0;
  if ( $chkprocessor =~ /^telecheck/
    && inArray( $mckutils::query{'accttype'}, [ 'checking', 'savings' ] ) ) {
    foreach my $key ( keys %receipt ) {
      $mckutils::query{$key} = $receipt{$key};    # overwrite
    }
  } elsif ( inArray( $mckutils::query{'receipt_type'}, [ 'simple', 'itemized', 'pos_itemized', 'pos_simple' ] )
    || inArray( $mckutils::query{'receipt-type'}, [ 'simple', 'itemized', 'pos_itemized', 'pos_simple' ] ) ) {
    foreach my $key ( keys %receipt ) {
      $mckutils::query{$key} ||= $receipt{$key};    # copy if empty
    }
  }

  $mckutils::company_name = $receipt{'receipt-company'};

  if ( $agentcode =~ /^(ff)$/i ) {
    my %feature         = ();
    my $accountFeatures = new PlugNPay::Features( 'ffmaster', 'general' );
    my $ff_features     = $accountFeatures->getFeatureString();

    if ( $ff_features ne "" ) {
      my @array = split( /\,/, $ff_features );
      foreach my $entry (@array) {
        my ( $name, $value ) = split( /\=/, $entry );
        $feature{$name} = $value;
      }
      if ( $feature{'dupchklist'} ne "" ) {
        $mckutils::feature{'dupchklist'} = $feature{'dupchklist'};
      }
    }
  }

  ### DCP 20100422
  if ( $mckutils::query{'transitiontype'} =~ /GET|POST/i ) {
    $mckutils::query{'transition'}     = 1;
    $mckutils::query{'transitiontype'} = lc $mckutils::query{'transitiontype'};

    # the following still used in final for branching
    $mckutils::feature{'transition'}     = 1;
    $mckutils::feature{'transitiontype'} = lc $mckutils::query{'transitiontype'};
  } elsif ( $mckutils::query{'transitiontype'} eq "hidden" ) {
    $mckutils::feature{'transition'} = 0;
  }

  ### DCP 20100114
  if ( ( $mckutils::feature{'skipsummaryflg'} == 1 )
    && ( $mckutils::query{'path_cgi'} =~ /pay\.cgi$/ )
    && ( $mckutils::cardtype ne "failure" ) ) {
    $mckutils::query{'card-type'} = $mckutils::cardtype;
  }

  if ( $mckutils::query{'client'} =~ /^(rectrac)$/ ) {
    $mckutils::feature{'expandedmsk'} = "1";
  }

  ### DCP 20090508
  ### JT 20110603 - extended 'merchantdb' regex filter to support numeric character
  if ( ( exists $mckutils::query{'merchantdb'} )
    && ( $ENV{'SCRIPT_NAME'} =~ /\/auth\.cgi$/ ) ) {
    $mckutils::query{'merchantdb'} =~ tr/A-Z/a-z/;
    $mckutils::query{'merchantdb'} =~ s/[^a-z0-9]//g;
    if (
      ( $mckutils::feature{'altmerchantdb'} =~ /$mckutils::query{'merchantdb'}/ )
      || ( ( $reseller eq "aaronsin" )
        && ( $mckutils::query{'merchantdb'} eq "aaronsinc" ) )
      || ( ( $reseller eq "homesmrt" )
        && ( $mckutils::query{'merchantdb'} eq "homesmrtin" ) )
      ) {

      # allow access to alternative membership database...
    } else {
      delete $mckutils::query{'merchantdb'};
    }
  }

  if ( ( $mckutils::query{'checktype'} eq "" )
    && ( $mckutils::feature{'default_sec_code'} ne "" ) ) {
    $mckutils::feature{'default_sec_code'} =~ s/[^a-zA-Z0-9]//g;
    $mckutils::query{'checktype'} = $mckutils::feature{'default_sec_code'};
  }

  ### DCP 20090513
  if ( exists $mckutils::query{'card-name'} ) {
    if ( ( $mckutils::processor =~ /^(wirecard)$/ )
      || ( $mckutils::query{'lang'} ne "" ) ) {
      ##  Do nothing, name already filtered to extended Char set in NEW.
    } else {
      $mckutils::query{'card-name'} =~ s/[^a-zA-Z\'0-9\.]/ /g;
    }
  }

  my $defaultValues = new PlugNPay::Transaction::DefaultValues();
  %mckutils::query = %{ $defaultValues->setLegacyDefaultValues( $mckutils::query{'merchant'}, \%mckutils::query ) };

  ## Added 20060915 DCP to add support for FifthThird DCC
  if ( ( $mckutils::feature{'dccflg'} == 1 )
    && ( $processor =~ /^(fifththird)$/ ) ) {
    $mckutils::dcc = "yes";
    $mckutils::query{'dcc'} = "yes";
  }

  if ( ( $reseller eq "planetp2" )
    && ( $processor =~ /^(fifththird)$/ )
    && ( $mckutils::feature{'curr_allowed'} ne "" )
    && ( $mckutils::feature{'multicurrency'} != 1 ) ) {
    $mckutils::feature{'multicurrency'} = "1";
  }

  ## Added 20080712 DCP to add support for PSL Issue when card types are retricted
  if ( ( $mckutils::feature{'cardsallowed'} == 1 )
    && ( $processor =~ /^(psl)$/ )
    && ( $mckutils::query{'transflags'} =~ /issue/i ) ) {
    delete $mckutils::feature{'cardsallowed'};
  }

  if ( ( $processor =~ /^(epx)$/ )
    && ( $mckutils::query{'card-zip'} =~ /^00000/ )
    && ( length( $mckutils::query{'card-zip'} ) > 10 ) ) {
    $mckutils::query{'card-zip'} =
      substr( $mckutils::query{'card-zip'}, 5 );
  }

  if ( ( $processor =~ /^(mercury)$/ )
    && ( $mckutils::query{'mpgiftcard'} ne "" )
    && ( $mckutils::query{'card-number'} eq "" ) ) {
    $mckutils::cardtype             = "pl";
    $mckutils::query{'card-number'} = $mckutils::query{'mpgiftcard'};
    $mckutils::query{'card-cvv'}    = $mckutils::query{'mpcvv'};
    if ( $mckutils::query{'transflags'} ne "" ) {
      if ( $mckutils::query{'transflags'} !~ /gift/ ) {
        $mckutils::query{'transflags'} .= ",gift";
      }
    } else {
      $mckutils::query{'transflags'} = "gift";
    }
  }

  if ( ( $chkprocessor =~ /^(echo|alliancesp|paymentdata)$/ )
    && ( $mckutils::query{'client'} eq "quikstor" )
    && ( $mckutils::query{'checktype'} eq "" ) ) {
    $mckutils::query{'checktype'} = "PPD";
  }

  ### 20110223 DCP as per request of vermont
  if ( ( $processor =~ /^(paytechtampa)$/ )
    && ( $reseller =~ /^(vermont|vermont2)$/ )
    && ( $mckutils::query{'transflags'} =~ /recurring/ )
    && ( $mckutils::query{'transflags'} !~ /moto/ ) ) {
    $mckutils::query{'transflags'} .= ",moto";
  }

  if ( $reseller =~ /^(paynisc|payntel|siipnisc|siiptel|teretail|elretail)$/ ) {
    $mckutils::query{'niscflg'} = 1;
    if ( $mckutils::query{'acct_code4'} eq "" ) {
      if ( $mckutils::query{'x_cust_id'} =~ /^IVR\-/i ) {
        $mckutils::query{'acct_code4'} = "IVR";
        $mckutils::query{'x_cust_id'} =~ s/^IVR\-//g;
      } elsif ( $mckutils::query{'x_cust_id'} =~ /^CR\-/i ) {
        $mckutils::query{'acct_code4'} = "CR";
        $mckutils::query{'x_cust_id'} =~ s/^CR\-//g;
      } elsif ( $mckutils::query{'x_cust_id'} =~ /^KIO\-/i ) {
        $mckutils::query{'acct_code4'} = "KIO";
        $mckutils::query{'x_cust_id'} =~ s/^KIO\-//g;
      } elsif ( $mckutils::query{'x_cust_id'} =~ /^EBI\-/i ) {
        $mckutils::query{'acct_code4'} = "EBI";
        $mckutils::query{'x_cust_id'} =~ s/^EBI\-//g;
      }

      if ( $mckutils::query{'x_invoice_num'} =~ /^CR/i ) {
        $mckutils::query{'acct_code4'} = "CR";
        $mckutils::query{'x_invoice_num'} =~ s/^CR//g;
      }

    }
    if ( $mckutils::query{'accttype'} =~ /^(checking|savings)$/ ) {
      if ( $mckutils::query{'acct_code4'} =~ /^(EBI)$/i ) {
        $mckutils::query{'checktype'} = "WEB";
      }
    }
    if ( $mckutils::query{'acct_code'} eq "" ) {
      if ( $mckutils::query{'x_cust_id'} ne "" ) {
        $mckutils::query{'acct_code'} = $mckutils::query{'x_cust_id'};
      } elsif ( $mckutils::query{'acct_number'} ne "" ) {
        $mckutils::query{'acct_code'} = $mckutils::query{'acct_number'};
      }
    }
    if ( $mckutils::query{'acct_code2'} eq "" ) {
      if ( $mckutils::query{'x_bill_cycle'} ne "" ) {
        $mckutils::query{'acct_code2'} = $mckutils::query{'x_bill_cycle'};
      } elsif ( $mckutils::query{'bill_cycle'} ne "" ) {
        $mckutils::query{'acct_code2'} = $mckutils::query{'bill_cycle'};
      }
    }
    if ( $mckutils::query{'acct_code3'} eq "" ) {
      if ( $mckutils::query{'order-id'} ne "" ) {
        $mckutils::query{'acct_code3'} = $mckutils::query{'order-id'};
      } elsif ( $mckutils::query{'invoice_num'} ne "" ) {
        $mckutils::query{'acct_code3'} = $mckutils::query{'invoice_num'};
      }
    }
    my $nametst = $mckutils::query{'card-name'};
    $nametst =~ s/[^a-zA-Z0-9]//g;
    if ( ( length($nametst) == 0 )
      && ( $mckutils::query{'card-company'} ne "" ) ) {
      $mckutils::query{'card-name'} = $mckutils::query{'card-company'};
    }
  }

  if ( ( ( $mckutils::feature{'conv_fee'} ne "" ) || ( $mckutils::feature{'convfee'} ne "" ) )
    && ( $mckutils::query{'acct_code3'} eq "" ) ) {
    ### DCP 20080710  - Placeholder for Conv. Fee Processing.
    $mckutils::query{'acct_code3'} = "ConvFeeP";
  }

  if ( $mckutils::query{'acct_code4'} eq "" ) {
    $ENV{'SCRIPT_NAME'} =~ /([a-z\.0-9]+\.cgi)$/;
    $mckutils::query{'acct_code4'} = $1;
  }

  if ( $currency eq "" ) {
    $currency = "usd";
  }

  if ( $mckutils::query{'currency'} eq "" ) {
    $mckutils::query{'currency'} = $currency;
  }

  ###  Over ride submitted currency with setup currency if the following conditions are not met.
  if ( ( $processor !~ /^(pago|atlantic|planetpay|fifththird|testprocessor|rbc|wirecard|cal|catalunya)$/ )
    && ( $mckutils::feature{'procmulticurr'} != 1 )
    && ( $mckutils::feature{'convertcurrency'} !~ /$mckutils::query{'currency'}/ ) ) {
    $mckutils::query{'currency'} = $currency;
  }

  if ( $processor eq "cayman" ) {
    my $cay_us_exchange_rate = "0.82";
    my $cardbin = substr( $mckutils::query{'card-number'}, 0, 6 );
    if ( $cardbin =~ /(417944|423382|431367|434682|441647|445024|445025|454611)/ ) {
      if ( $currency ne "kyd" ) {
        $mckutils::query{'publisher-name'} = $dccusername;
      }
      if ( $mckutils::query{'currency'} ne "kyd" ) {
        $mckutils::query{'card-amount'} = sprintf( "%0.2f", $mckutils::query{'card-amount'} * $cay_us_exchange_rate );
        $mckutils::query{'currency'} = "kyd";
      }
    }
  }

  ### DCP 20091030  support for default to milstar
  if ( ( substr( $mckutils::query{'card-number'}, 0, 5 ) =~ /^(60194|60191)$/ )
    && ( $mckutils::feature{'defaultmilstar'} == 1 ) ) {
    $mckutils::cardtype = "MS";
    if ( ( $mckutils::query{'transflags'} !~ /milstar/ ) ) {
      if ( exists $mckutils::query{'transflags'} ) {
        $mckutils::query{'transflags'} .= ",milstar";
      } else {
        $mckutils::query{'transflags'} = "milstar";
      }
    }
  } elsif ( ( substr( $mckutils::query{'card-number'}, 0, 6 ) =~ /^(603571)$/ )
    && ( $mckutils::feature{'defaultgift'} == 1 ) ) {
    $mckutils::cardtype = "pl";
    if ( ( $mckutils::query{'transflags'} !~ /gift/ ) ) {
      if ( exists $mckutils::query{'transflags'} ) {
        $mckutils::query{'transflags'} .= ",gift";
      } else {
        $mckutils::query{'transflags'} = "gift";
      }
    }
  }

  ## DCP 20050415 - Added to support Omni 3750 POS for PAGO.
  if ( ( $processor =~ /^(pago)$/ ) && ( $mckutils::query{'posflag'} == 1 ) ) {
    ## As per Pago.  If merchant is using POS, then fake the address information.
    if ( $mckutils::query{'card-address'} eq "" ) {
      $mckutils::query{'card-address'} = "1 CARD PRESENT";
    }
    if ( $mckutils::query{'card-city'} eq "" ) {
      $mckutils::query{'card-city'} = "CARD PRESENT";
    }
    if ( $mckutils::query{'card-name'} eq "" ) {
      $mckutils::query{'card-name'} = "CARD PRESENT";
    }
    if ( $mckutils::query{'card-zip'} eq "" ) {
      $mckutils::query{'card-zip'} = "00000";
    }
    if ( $mckutils::query{'card-country'} eq "" ) {
      $mckutils::query{'card-country'} = "US";
    }
  }

  if ( ( $mckutils::feature{'pubemail'} ne "" )
    && ( $mckutils::query{'publisher-email'} eq "" ) ) {
    $mckutils::feature{'pubemail'} =
      substr( $mckutils::feature{'pubemail'}, 0, 50 );
    $mckutils::feature{'pubemail'} =~ s/\;/\,/g;
    $mckutils::feature{'pubemail'} =~ s/[^_0-9a-zA-Z\-\@\.\,]//g;
    my $position = index( $mckutils::feature{'pubemail'}, "\@" );
    my $position1 = rindex( $mckutils::feature{'pubemail'}, "\." );
    my $elength   = length( $mckutils::feature{'pubemail'} );
    my $pos1      = $elength - $position1;

    if ( ( $position < 1 )
      || ( $position1 < $position )
      || ( $position1 >= $elength - 2 )
      || ( $elength < 5 )
      || ( $position > $elength - 5 ) ) {
      ## Do Nothing
      ## pubemail looks invalid
    } else {
      $mckutils::query{'publisher-email'} = $mckutils::feature{'pubemail'};
    }
  }

  ##  Custome Tweak for NISC added DCP 20041213
  if ( ( $mckutils::query{'publisher-name'} eq "cottonelec" )
    && ( $mckutils::query{'accttype'} =~ /^(checking|savings)$/ ) ) {
    $mckutils::query{'publisher-email'} = "onlinepayments\@cottonelectric.com";
    $mckutils::feature{'sndemail'}      = "merchant";
  }
  if ( $mckutils::query{'publisher-name'} eq "tricountye" ) {
    $mckutils::query{'publisher-email'} = "kbernard\@tec.coop";
    $mckutils::feature{'sndemail'}      = "merchant";
  }
  if ( $mckutils::query{'publisher-name'} eq "consolidat2" ) {
    $mckutils::query{'publisher-email'} = "nsalyer\@conelec.com";
    $mckutils::feature{'sndemail'}      = "merchant";
  }
  if ( $mckutils::query{'publisher-name'} eq "flatheadel" ) {
    $mckutils::query{'publisher-email'} = "carol.vanluven\@flatheadelectric.com";
    $mckutils::feature{'sndemail'}      = "merchant";
  }

  if ( ( $mckutils::query{'publisher-name'} eq "safetysack" )
    && ( $mckutils::query{'card-name'} =~ /^\d/ ) ) {
    $mckutils::query{'card-name'} =~ "Deleted PCI";
  }

  ##  Custome Tweak for NISC added DCP 20050113  Fixed on 20050126
  if ( ( $reseller =~ /^(siipnisc|siiptel)$/ )
    && ( $mckutils::query{'transflags'} !~ /recurring/ ) ) {
    if ( exists $mckutils::query{'transflags'} ) {
      $mckutils::query{'transflags'} .= ",recurring";
    } else {
      $mckutils::query{'transflags'} = "recurring";
    }
  }

  ## Custome Tweak for Owens and Minor added DCP 20070803
  if ( ( $processor eq "global" )
    && ( $mckutils::query{'publisher-name'} =~ /^om/ )
    && ( exists $mckutils::query{'partialponumber'} )
    && ( exists $mckutils::query{'username'} ) ) {
    $mckutils::query{'reportdata'} = substr( $mckutils::query{'username'}, 0, 8 ) . "\-$mckutils::query{'partialponumber'}";
    $mckutils::query{'acct_code'} = $mckutils::query{'reportdata'};
  }

  ## DCP - eWallet/eCard/Loyalty  20050206
  if ( ( !exists $mckutils::query{'ew_customer_id'} )
    && ( $mckutils::feature{'loyaltyprog'} == 1 ) ) {
    require ewallet;
    my @array   = %mckutils::query;
    my $ewallet = ewallet->new(@array);
    if ( $ewallet::ew_customer_id ne "" ) {
      $mckutils::query{'ew_customer_id'} = $ewallet::ew_customer_id;
    }
  }

  ### Non-Secure Log
  if ( ( $ENV{'SERVER_PORT'} =~ /^(80)$/ )
    && ( $ENV{'SCRIPT_NAME'} ne "" )
    && ( $ENV{'SCRIPT_NAME'} =~ /\.cgi$/ ) ) {
    my $time = gmtime(time);
    open( DEBUG, ">>/home/p/pay1/database/debug/non_ssl.txt" );
    print DEBUG "TIME:$time, RA:$remote_ip, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, ";
    print DEBUG "PORT:$ENV{'SERVER_PORT'}, PID:$$, RM:$ENV{'REQUEST_METHOD'}, ";
    print DEBUG "USERNAME:$mckutils::query{'publisher-name'}\n";
    close(DEBUG);

    #use Datalog
    my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
    $logger->log(
      { 'TIME'     => $time,
        'RA'       => $remote_ip,
        'SCRIPT'   => $ENV{'SCRIPT_NAME'},
        'HOST'     => $ENV{'SERVER_NAME'},
        'PORT'     => $ENV{'SERVER_PORT'},
        'PID'      => $$,
        'RM'       => $ENV{'REQUEST_METHOD'},
        'USERNAME' => $mckutils::query{'publisher-name'}
      }
    );

    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "Invalid Protocol - Data sent via http instead of https.";
    $result{'resp-code'}   = "P151";
    %mckutils::result      = %result;
    return %result;

  }

  ## Block non-usd trans for multicurrency on cards other than Visa/MC
  if ( ( $mckutils::query{'transflags'} =~ /multicurrency/ )
    && ( $mckutils::cardtype !~ /VISA|MSTR/i )
    && ( $mckutils::query{'currency'} ne "usd" )
    && ( $processor =~ /^(planetpay|fifththird|testprocessor)$/ ) ) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "Invalid Card Type/Currency Combination.";
    $result{'resp-code'}   = "P150";
    %mckutils::result      = %result;
    return %result;
  }

  ## DCP - Add support for account to be return only
  if ( $proc_type eq "returnonly" ) {
    my $message = "Your current account status allows for issuing returns and/or credits only. <p>Please contact Technical Support if you believe this to be in error.";
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "Account status returns only.";
    $result{'resp-code'}   = "P149";
    %mckutils::result      = %result;
    return %result;

  }

  if ( ( exists $mckutils::query{'ew_customer_id'} )
    && ( $mckutils::query{'ewstatus'} eq "problem" ) ) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "$mckutils::query{'ewmsg'}";
    $result{'resp-code'}   = "P149";
    %mckutils::result      = %result;
    return %result;
  }

  if ( ( $mckutils::feature{'curr_allowed'} ne "" )
    && ( $processor =~ /^(pago|atlantic|planetpay|ncb|fifththird|rbc|wirecard|cal)$/ )
    && ( $mckutils::feature{'curr_allowed'} !~ /$mckutils::query{'currency'}/i ) ) {
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "Currency Type Not Supported.";
    $result{'resp-code'}   = "P49";
    %mckutils::result      = %result;
    return %result;
  }

  ## Suspected Hack Return BadCard
  if ( $remote_ip =~ /(83\.149\.113\.151|217\.118\.66\.232|67\.165\.246\.136)/ ) {
    $result{'FinalStatus'} = "badcard";
    $result{'MStatus'}     = "badcard";
    $result{'MErrMsg'}     = "Declined.";
    $result{'resp-code'}   = "P646";
    %mckutils::result      = %result;
    return %result;
  }

  ## Security Check - Beta
  my %security = &security_check( $mckutils::query{'publisher-name'}, $mckutils::query{'publisher-password'}, $remote_ip );
  if ( $security{'flag'} != 1 ) {
    $result{'FinalStatus'}      = "problem";
    $result{'MErrMsg'}          = $security{'MErrMsg'};
    $result{'resp-code'}        = $security{'resp-code'};
    $mckutils::query{'MErrMsg'} = $security{'MErrMsg'};
    %mckutils::result           = %result;
    return %result;
  }

  ## DCP - Add support for Magensa Errors
  if ( ( $mckutils::query{'magensacc'} ne "" )
    && ( $mckutils::query{'StatusCode'} ne "1000" ) ) {
    my ($errmsg);
    delete $mckutils::query{'card-number'};
    if ( $mckutils::query{'StatusCode'} =~ /^H/ ) {

      # CBI - Added for clarification of errors from customers
      $errmsg = "Input Validation Error - Please contact Technical Support.  Please provide them with error code: " . $mckutils::query{'StatusCode'};
    } elsif ( $mckutils::query{'StatusCode'} =~ /^Y097$/ ) {
      $errmsg = "Possible duplicate transaction.  Please check via the transaction admin area.";
      $result{'Duplicate'} = "yes";
    } elsif ( $mckutils::query{'StatusCode'} =~ /^(Y093|Y094|Y096)$/ ) {
      $errmsg = "Invalid or corrupted magstripe data.";
    } else {
      $errmsg = "$mckutils::query{'StatusMsg'}";
    }
    $result{'FinalStatus'} = "problem";
    $result{'MStatus'}     = "problem";
    $result{'MErrMsg'}     = "$errmsg";
    $result{'resp-code'}   = "$mckutils::query{'StatusCode'}";
    %mckutils::result      = %result;
    return %result;
  }

  if ( ( $mckutils::feature{'multicurrency'} == 1 )
    && ( $mckutils::query{'transflags'} !~ /multicurrency/ ) ) {
    if ( exists $mckutils::query{'transflags'} ) {
      $mckutils::query{'transflags'} .= ",multicurrency";
    } else {
      $mckutils::query{'transflags'} = "multicurrency";
    }
  }

  if ( $mckutils::feature{'convertcurrency'} ne "" ) {
    my %rates = split( '\|', $mckutils::feature{'convertcurrency'} );
    if ( exists $rates{ $mckutils::query{'currency'} } ) {
      my $currencyObj = new PlugNPay::Currency( $mckutils::query{'currency'} );
      $mckutils::query{'native_amt'}  = $mckutils::query{'card-amount'};
      $mckutils::query{'native_curr'} = $mckutils::query{'currency'};
      my $conv_rate = $rates{ $mckutils::query{'currency'} };
      $mckutils::query{'card-amount'} = $currencyObj->format( ( $mckutils::query{'card-amount'} / $conv_rate + .0001 ), { digitSeparator => '' } );
      $mckutils::query{'currency'} = $currency;
    }
  }

  $mckutils::processor       = $processor;
  $mckutils::walletprocessor = $walletprocessor;
  $mckutils::reseller        = $reseller;
  $cards_allowed =~ tr/a-z/A-Z/;
  $cards_allowed =~ s/[^A-Z\|]//g;

  $mckutils::timetest[ ++$#mckutils::timetest ] = "post_customer_select";
  $mckutils::timetest[ ++$#mckutils::timetest ] = time();

  if ( $mckutils::buypassfraud eq "yes" ) {
    $fraud_config = "";
    $mckutils::query{'nofraudcheck'} = "yes";
  }

  if ( $fraud_config ne "" ) {
    my @array = split( /\,/, $fraud_config );
    foreach my $entry (@array) {
      my ( $name, $value ) = split( /\=/, $entry );
      $mckutils::fconfig{$name} = $value;
    }
  }

  ## DCP 20091221
  if ( exists $mckutils::query{'dupchkwin'} ) {
    $mckutils::query{'dupchkwin'} =~ s/[^0-9]//g;
    $mckutils::fconfig{'dupchktime'} = $mckutils::query{'dupchkwin'};
  }

  if ( ( ( $mckutils::feature{'recexpflg'} == 1 ) || ( $mckutils::fconfig{'recexpflg'} == 1 ) )
    && ( $mckutils::query{'transflags'} =~ /recurring|recinitial/ ) ) {
    my $card_exp = $mckutils::query{'card-exp'};
    my $yearexp  = substr( $card_exp, 3, 2 );
    my $monthexp = substr( $card_exp, 0, 2 );
    $yearexp = "20" . $yearexp;
    my $cardexp    = $yearexp . $monthexp;
    my ($today)    = &miscutils::gendatetime_only();
    my $todaymonth = substr( $today, 0, 6 );
    if ( $todaymonth > $cardexp ) {
      ##Card has expired bump exp date by 1 year from today;
      my $year = sprintf( "%04s", substr( $today, 0, 4 ) + 1 );
      $mckutils::query{'card-exp'} = $monthexp . "/" . substr( $year, 2, 2 );
      $mckutils::query{'expbumped'} = 1;
    }
  }

  if ( ( $mckutils::query{'cvv_ign'} eq "yes" )
    || ( $mckutils::query{'cvv-ign'} eq "yes" ) ) {
    if ( $mckutils::source eq "virtterm" ) {
      $mckutils::fconfig{'cvv_ign'} = "1";
    } else {
      $mckutils::query{'cvv_ign'} = "invalid source";
    }
  }

  if ( ( $retailflag eq 'retail' )
    && ( $mckutils::query{'transflags'} !~ /retail/ ) ) {
    if ( exists $mckutils::query{'transflags'} ) {
      $mckutils::query{'transflags'} .= ",retail";
    } else {
      $mckutils::query{'transflags'} = "retail";
    }
  }

  $mckutils::timetest[ ++$#mckutils::timetest ] = "post_fraudtrack_settings";
  $mckutils::timetest[ ++$#mckutils::timetest ] = time();

  if (
       ($testmode)
    && ( $mckutils::query{'card-name'} =~ /^(pnptest|pnp test|cardtest|card test|force success)/i )
    && ( $mckutils::query{'card-number'} =~
      /^(4111111111111111|4025241600000007|4025241600000007|4000000000000002|5100040000000004|4000000500000007|5100120000000004|4000010200000001|5100060000000002|4000020000000000|5100070000000001|4000030300000009|5100100000000006|4000040000000008|5100110000000005)$/
    )
    ) {
    if ( $mckutils::query{'card-name'} =~ /^(force success)/i ) {
      $result{'FinalStatus'}       = "success";
      $result{'MStatus'}           = "success";
      $result{'auth-code'}         = "TSTAUTH";
      $result{'avs-code'}          = "U";
      $result{'resp-code'}         = "00";
      $result{'MErrMsg'}           = "00:";
      $result{'cvvresp'}           = "M";
      $main::result{'FinalStatus'} = "success";
      $main::result{'MStatus'}     = "success";
      $main::result{'avs-code'}    = "U";
      &receiptcc();
    } elsif ( $mckutils::query{'card-amount'} == 1025 ) {    ## Bad Card Response
      $result{'FinalStatus'}       = "badcard";
      $result{'MStatus'}           = "badcard";
      $result{'auth-code'}         = "";
      $result{'MErrMsg'}           = "Referral: Call voice center";
      $result{'resp-code'}         = "P30";
      $main::result{'FinalStatus'} = "badcard";
      $main::result{'MStatus'}     = "badcard";
    } elsif ( $mckutils::query{'card-amount'} == 1026 ) {    ## AVS Rejection
      $result{'FinalStatus'}       = "badcard";
      $result{'MStatus'}           = "badcard";
      $result{'auth-code'}         = "";
      $result{'MErrMsg'}           = "Sorry, the billing address you entered does not match the address on record for this credit card or your address information is unavailable for verification.";
      $result{'avs-code'}          = "U";
      $result{'resp-code'}         = "P01";
      $main::result{'FinalStatus'} = "badcard";
      $main::result{'MStatus'}     = "badcard";
    } elsif ( $mckutils::query{'card-amount'} == 1027 ) {    ## Expired Card
      $result{'FinalStatus'}       = "badcard";
      $result{'MStatus'}           = "badcard";
      $result{'auth-code'}         = "";
      $result{'MErrMsg'}           = "Card has expired";
      $result{'resp-code'}         = "P57";
      $main::result{'FinalStatus'} = "badcard";
      $main::result{'MStatus'}     = "badcard";
    } elsif ( $mckutils::query{'card-amount'} == 1028 ) {    ## CVV Failure
      $result{'FinalStatus'}       = "badcard";
      $result{'MStatus'}           = "badcard";
      $result{'auth-code'}         = "";
      $result{'cvvresp'}           = "N";
      $result{'MErrMsg'}           = "Sorry, the CVV2/CVC2 number entered does not match the number on the credit card.";
      $result{'resp-code'}         = "P02";
      $main::result{'FinalStatus'} = "badcard";
      $main::result{'MStatus'}     = "badcard";
    } elsif ( $mckutils::query{'card-amount'} == 1029 ) {    ## Luhn 10 Failure
      $result{'FinalStatus'}       = "badcard";
      $result{'MStatus'}           = "badcard";
      $result{'auth-code'}         = "";
      $result{'MErrMsg'}           = "Card number failed luhn10 check";
      $result{'resp-code'}         = "P55";
      $main::result{'FinalStatus'} = "badcard";
      $main::result{'MStatus'}     = "badcard";
    } elsif ( $mckutils::query{'card-amount'} == 1030 ) {    ## Missing CVV
      $result{'FinalStatus'}       = "badcard";
      $result{'MStatus'}           = "badcard";
      $result{'auth-code'}         = "";
      $result{'MErrMsg'}           = "Invalid Credit Card CVV2/CVC2 Number.";
      $result{'resp-code'}         = "P56";
      $main::result{'FinalStatus'} = "badcard";
      $main::result{'MStatus'}     = "badcard";
    } elsif ( ( $mckutils::query{'card-amount'} > 1000 )
      && ( $mckutils::query{'card-amount'} <= 2000 ) ) {     ## Bad Card Response
      $result{'FinalStatus'}       = "badcard";
      $result{'MStatus'}           = "badcard";
      $result{'auth-code'}         = "";
      $result{'MErrMsg'}           = "Insufficient Funds";
      $result{'resp-code'}         = "P30";
      $main::result{'FinalStatus'} = "badcard";
      $main::result{'MStatus'}     = "badcard";
    } elsif ( ( $mckutils::query{'card-amount'} > 2000 ) ) {    ## Problem Response
      $result{'FinalStatus'}       = "problem";
      $result{'MStatus'}           = "problem";
      $result{'auth-code'}         = "";
      $result{'MErrMsg'}           = "No response from processor";
      $result{'resp-code'}         = "P35";
      $main::result{'FinalStatus'} = "problem";
      $main::result{'MStatus'}     = "problem";
    } else {
      $result{'FinalStatus'}       = "success";
      $result{'MStatus'}           = "success";
      $result{'auth-code'}         = "TSTAUTH";
      $result{'avs-code'}          = "U";
      $result{'resp-code'}         = "00";
      $result{'MErrMsg'}           = "00:";
      $result{'cvvresp'}           = "M";
      $main::result{'FinalStatus'} = "success";
      $main::result{'MStatus'}     = "success";
      $main::result{'avs-code'}    = "U";

      if ( $mckutils::query{'client'} eq "easycart" ) {

        #&delete_easycart();
      }
      if ( ( $mckutils::dcc eq "yes" )
        && ( $mckutils::query{'publisher-name'} =~ /^(planettest|testplanet)$/ )
        && ( $mckutils::query{'card-number'} eq "4025241600000007" ) ) {

        #my @array = %mckutils::query;
        my @array = ( %mckutils::query, %result );
        %result = ( %result, &dccmsg(@array) );
      }
      if (
        ( $mckutils::feature{'multicurrency'} == 1 )
        && ( $mckutils::query{'card-number'} =~
          /^(4025241600000007|4000000000000002|5100040000000004|4000000500000007|5100120000000004|4000010200000001|5100060000000002|4000020000000000|5100070000000001|4000030300000009|5100100000000006|4000040000000008|5100110000000005)/
        )
        ) {
        my @array = %mckutils::query;
        %result = ( %result, &parse_multicurrency(@array) );
      }
      &receiptcc();
    }
    if ( $mckutils::processor eq "psl" ) {
      $result{'redirecturl'} = $mckutils::query{"$result{'FinalStatus'}\-link"};
      $result{'redirecturl'} .= "?publisher-name=$mckutils::query{'publisher-name'}";
      $result{'redirecturl'} .= "&transflags=$mckutils::query{'transflags'}";
      $result{'redirecturl'} .= "&orderID=$mckutils::query{'orderID'}";
      $result{'redirecturl'} .= "&client=$mckutils::query{'client'}";
    }

    $result{'currency'}         = $mckutils::query{'currency'};
    $result{'tran_in_testmode'} = "yes";
    $mckutils::pnp_debug        = "yes";
    %mckutils::result           = %result;

    my $digests = resp_hash( \%mckutils::feature, \%mckutils::query, \%mckutils::result, $mckutils::convfeeflag );
    $mckutils::query{'resphash'}        = $digests->{'md5Sum'};
    $mckutils::query{'resphash_sha256'} = $digests->{'sha256Sum'};

    return %result;
  } elsif (
    ($testmode)
    && ( ( $mckutils::query{'card-name'} =~ /^(pnptest|pnp test|cardtest|card test)/i )
      || ( $processor =~ /^test/i ) )
    && ( $mckutils::query{'routingnum'} eq "999999992" )
    ) {
    $mckutils::query{'card-number'} =
      $mckutils::query{'routingnum'} . " " . $mckutils::query{'accountnum'};
    if ( ( $mckutils::query{'card-amount'} > 1000 )
      && ( $mckutils::query{'card-amount'} < 2000 ) ) {    ## Bad Card Response
      $result{'FinalStatus'}       = "badcard";
      $result{'MStatus'}           = "badcard";
      $result{'MErrMsg'}           = "Insufficient Funds";
      $result{'resp-code'}         = "P30";
      $main::result{'FinalStatus'} = "badcard";
      $main::result{'MStatus'}     = "badcard";
    } elsif ( ( $mckutils::query{'card-amount'} > 2000 ) ) {    ## Problem Response
      $result{'FinalStatus'}       = "problem";
      $result{'MStatus'}           = "problem";
      $result{'MErrMsg'}           = "No response from processor";
      $result{'resp-code'}         = "P35";
      $main::result{'FinalStatus'} = "problem";
      $main::result{'MStatus'}     = "problem";
    } else {
      $result{'FinalStatus'}       = "success";
      $result{'MStatus'}           = "success";
      $result{'resp-code'}         = "00";
      $main::result{'FinalStatus'} = "success";
      $main::result{'MStatus'}     = "success";
    }
    &receiptcc();
    $mckutils::pnp_debug = "yes";
    %mckutils::result    = %result;

    my $digests = resp_hash( \%mckutils::feature, \%mckutils::query, \%mckutils::result, $mckutils::convfeeflag );
    $mckutils::query{'resphash'}        = $digests->{'md5Sum'};
    $mckutils::query{'resphash_sha256'} = $digests->{'sha256Sum'};

    return %result;
  }

  if ( ( $mckutils::dcc eq "yes" )
    && ( $mckutils::query{'publisher-name'} =~ /^(planettest|testplanet)$/ )
    && ( $mckutils::query{'card-number'} =~ /(4025241600000007)/ ) ) {
    $result{'FinalStatus'}       = "success";
    $result{'MStatus'}           = "success";
    $result{'auth-code'}         = "TSTAUTH";
    $result{'avs-code'}          = "U";
    $main::result{'FinalStatus'} = "success";
    $main::result{'MStatus'}     = "success";
    $main::result{'avs-code'}    = "U";

    #my @array = %mckutils::query;
    my @array = ( %mckutils::query, %result );
    %result = ( %result, &dccmsg(@array) );
    %mckutils::result = %result;
    return %result;
  }

  if (
       ( ( $reseller =~ /^(cardread)$/ ) || ( $mckutils::feature{'cardsallowed'} == 1 ) )
    && ( $cards_allowed ne "" )
    && ( ( $mckutils::query{'paymethod'} ne "onlinecheck" )
      && ( $mckutils::query{'accttype'} eq "credit" )
      && ( $mckutils::query{'card-number'} ne "" ) )
    ) {
    my $cardtype = &miscutils::cardtype( $mckutils::query{'card-number'} );
    if ( $cards_allowed !~ /$cardtype/ ) {
      $result{'FinalStatus'} = "problem";
      $result{'MStatus'}     = "problem";
      $result{'MErrMsg'}     = "Card Type Not Supported, $cardtype";
      $result{'resp-code'}   = "P49";
      %mckutils::result      = %result;
      return %result;
    }
  }

  if ( ( $processor =~ /^(wirecard)$/ )
    && ( $mckutils::query{'transflags'} =~ /avsonly/ ) ) {
    $mckutils::query{'card-amount'} = "0.10";
  } elsif ( ( $processor =~ /^(rbs)$/ )
    && ( $mckutils::query{'transflags'} =~ /avsonly/ )
    && ( $mckutils::query{'magstripe'} ne "" ) ) {
    delete $mckutils::query{'magstripe'};
  }

  # Check if purchase type should be 'storedata'
  my $storeDataInfo = {
    'allowStoreData' => $mckutils::feature{'allow_storedata'},
    'storeData'      => $mckutils::query{'storedata'},
    'paymentMethod'  => $mckutils::query{'paymethod'},
    'allowInvoice'   => $mckutils::feature{'allow_invoice'},
    'allowFreePlans' => $mckutils::feature{'allow_freeplans'},
    'plan'           => $mckutils::query{'plan'},
    'cardAmount'     => $mckutils::query{'card-amount'},
    'transFlags'     => $mckutils::query{'transflags'}
  };
  if ( &isStoreData($storeDataInfo) ) {
    $purchasetype = "storedata";
  }

  if ( $purchasetype eq "storedata" ) {
    $mckutils::trans_type = "storedata";
  } else {
    $mckutils::trans_type = "auth";
  }

  $start = time();

  %fraud::fraud_config = ();
  $fraud::exemptflag   = "";

  if ( ( $fraud_config ne "" ) ) {
    $mckutils::timetest[ ++$#mckutils::timetest ] = "pre_fraudtrack";
    $mckutils::timetest[ ++$#mckutils::timetest ] = time();

    require fraud;
    my @array = %mckutils::query;
    $mckutils::fraudtrack = fraud->new( $fraud_config, $status, @array );
    @array                = %mckutils::query;
    %result               = $mckutils::fraudtrack->preauth_fraud_screen(@array);

    $mckutils::timetest[ ++$#mckutils::timetest ] = "post_fraudtrack";
    $mckutils::timetest[ ++$#mckutils::timetest ] = time();

    if ( $result{'FinalStatus'} =~ /fraud/i ) {
      my $now = gmtime(time);
      my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
      my $mo = sprintf( "%02d", $mon + 1 );

      &sysutils::filelog( "append", ">>/home/p/pay1/database/debug/fraud_debug$mo.txt" );
      open( FRAUD, ">>/home/p/pay1/database/debug/fraud_debug$mo.txt" );
      print FRAUD
        "DATE:$now, OID:$mckutils::query{'orderID'}, UN:$mckutils::query{'publisher-name'}, IP:$mckutils::query{'IPaddress'}, SN:$ENV{'SCRIPT_NAME'}, FS:$result{'FinalStatus'}, MErrMSg:$result{'MErrMsg'}, FC:$fraud_config\n";
      close(FRAUD);
      %mckutils::result = %result;
      return %result;
    } elsif ( exists $result{'iTransactResp'} ) {
      if ( ( $ENV{'SCRIPT_NAME'} =~ /pnpremote/ ) ) {
        return %result;
      } else {
        print header( -type => 'text/html' );    #### DCP 20100712
                                                 #print "Content-Type: text/html\r\n\r\n";
        print "$result{'iTransactResp'}";
        exit;
      }
    } elsif ( $result{'dupchkstatus'} =~ /^(success)$/ ) {
      &receiptcc();

      $result{'FinalStatus'} = $result{'dupchkstatus'};
      $result{'auth-code'}   = $result{'dupchkauthcode'};
      $result{'resp-code'}   = "00";
      %mckutils::result      = %result;

      my $digests = resp_hash( \%mckutils::feature, \%mckutils::query, \%mckutils::result, $mckutils::convfeeflag );
      $mckutils::query{'resphash'}        = $digests->{'md5Sum'};
      $mckutils::query{'resphash_sha256'} = $digests->{'sha256Sum'};

      return %result;
    }
  } elsif ( ( $status eq "live" )
    && ( $mckutils::query{'nofraudcheck'} ne "yes" )
    && ( $mckutils::query{'card-number'} ne "4111111111111111" )
    && ( $mckutils::query{'paymethod'} !~ /^(invoice|web900)$/ ) ) {

    $mckutils::timetest[ ++$#mckutils::timetest ] = "pre_checkfraud";
    $mckutils::timetest[ ++$#mckutils::timetest ] = time();

    my $fraudstatus = &checkfraud();
    my $fraud       = time();

    if ( $fraudstatus eq "failure" ) {
      $result{'FinalStatus'} = "badcard";
      $result{'MStatus'}     = "failure";
      %mckutils::result      = %result;

      my $digests = resp_hash( \%mckutils::feature, \%mckutils::query, \%mckutils::result, $mckutils::convfeeflag );
      $mckutils::query{'resphash'}        = $digests->{'md5Sum'};
      $mckutils::query{'resphash_sha256'} = $digests->{'sha256Sum'};

      return %result;
    }

    $mckutils::timetest[ ++$#mckutils::timetest ] = "post_checkfraud";
    $mckutils::timetest[ ++$#mckutils::timetest ] = time();

  }

  if ( ( $walletprocessor =~ /feed/ )
    && ( $mckutils::query{'paymethod'} eq "mocapay" ) ) {
    $mckutils::query{'accttype'} = "feed";
  }

  $mckutils::timetest[ ++$#mckutils::timetest ] = "fraud_check";
  $mckutils::timetest[ ++$#mckutils::timetest ] = time();

  my @extrafields = ();
  if ( $processor eq "authorizenet" ) {
    @extrafields = ( 'description', $mckutils::query{'description1'}, 'phone', $mckutils::query{'phone'}, 'fax', $mckutils::query{'fax'}, );
  } elsif ( $processor eq "psl" ) {
    if ( $mckutils::query{'transflags'} =~ /load/ ) {
      my (%input) = (%mckutils::query);
      my ( $sub_str1, $sub_str2 );
      foreach my $key ( keys %input ) {
        if ( $key !~ /^(publisher-name|orderID|transflags)$/i ) {
          next;
        }
        my $name  = $key;
        my $value = $input{$key};
        $name =~ s/([^ \w*])/sprintf("%%%2.2X",ord($1))/ge;
        $value =~ s/([^ \w*])/sprintf("%%%2.2X",ord($1))/ge;
        $name =~ s/ /+/g;
        $value =~ s/ /+/g;
        if ( $value ne "" ) {
          $sub_str1 .= "$name=$value";
          $sub_str1 .= '&';
        }
      }
      $sub_str1 .= "client=psl";
      if ( $mckutils::query{'success-link'} !~ /(htm|html)^/i ) {
        $mckutils::query{'success-link'} .= "?$sub_str1";

        #$mckutils::query{'success-link'} =~ s/([^ \w*])/sprintf("%%%2.2X",ord($1))/ge;
      }
      if ( $mckutils::query{'badcard-link'} !~ /(htm|html)^/i ) {
        $mckutils::query{'badcard-link'} .= "?$sub_str1" . "&pslstatus=badcard";

        #$mckutils::query{'badcard-link'} =~ s/([^ \w*])/sprintf("%%%2.2X",ord($1))/ge;
      }
      foreach my $key ( keys %input ) {
        if ( $key =~ /^(card-number|card_number|card-exp|card_exp|card-cvv|card_cvv|passcode)$/i ) {
          next;
        }
        my $name  = $key;
        my $value = $input{$key};
        $name =~ s/([^ \w*])/sprintf("%%%2.2X",ord($1))/ge;
        $value =~ s/([^ \w*])/sprintf("%%%2.2X",ord($1))/ge;
        $name =~ s/ /+/g;
        $value =~ s/ /+/g;
        if ( $value ne "" ) {
          $sub_str2 .= "$name=$value";
          $sub_str2 .= '&';
        }
      }
      $sub_str2 .= "client=psl";
      my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
      my $date = sprintf( "%04d%02d%02d", $year + 1900, $mon + 1, $mday );

      my $dbh = &miscutils::dbhconnect("pnpmisc");

      my $sth = $dbh->prepare(
        qq{
          insert into psldata
          (trans_date,username,orderid,qrydata)
          values (?,?,?,?)
      }
      );
      $sth->execute( "$date", "$mckutils::query{'publisher-name'}", "$mckutils::query{'orderID'}", "$sub_str2" )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
      $sth->finish;
      $dbh->disconnect;
    }
    if ( $mckutils::query{'transflags'} =~ /issue/i ) {
      @extrafields = (
        'dateofbirth', "$mckutils::query{'dateofbirth'}", 'walletid',  $mckutils::query{'walletid'},  'passcode',   $mckutils::query{'passcode'},
        'challenge',   $mckutils::query{'challenge'},     'response',  $mckutils::query{'response'},  'transflags', 'issue',
        'phone',       $mckutils::query{'phone'},         'ipaddress', $mckutils::query{'IPaddress'}, 'phonetype',  $mckutils::query{'phonetype'}
      );
    } else {
      @extrafields = (
        'walletid',  $mckutils::query{'walletid'},  'passcode',     $mckutils::query{'passcode'}, 'badcard-link', $mckutils::query{'badcard-link'},
        'ipaddress', $mckutils::query{'ipaddress'}, 'success-link', $mckutils::query{'success-link'}
      );
    }
  } elsif ( $processor eq "wirecard" ) {
    @extrafields = ( 'jobid', $mckutils::query{'jobid'}, 'paresponse', $mckutils::query{'paresponse'} );
  } elsif ( $processor eq "pago" ) {
    @extrafields = ( 'cardissuenum', $mckutils::query{'cardissuenum'}, 'cardstartdate', $mckutils::query{'cardstartdate'} );

    if ( ( $mckutils::cardtype =~ /^(SOLO|SWTCH)$/ )
      && ( $mckutils::query{'transflags'} !~ /^capture$/ ) ) {
      if ( exists $mckutils::query{'transflags'} ) {
        $mckutils::query{'transflags'} .= ",capture";
      } else {
        $mckutils::query{'transflags'} = "capture";
      }
    }
  } elsif ( ( $processor eq "barclays" )
    && ( $mckutils::cardtype =~ /^(SWTCH|SOLO)$/ ) ) {
    @extrafields = ( 'cardissuenum', $mckutils::query{'cardissuenum'}, 'cardstartdate', $mckutils::query{'cardstartdate'} );
  } elsif ( $processor =~ /^(surefire|village)$/ ) {
    @extrafields = ( 'ipaddress', $mckutils::query{'ipaddress'}, 'phone', $mckutils::query{'phone'} );
  } elsif ( $processor eq "cal" ) {
    @extrafields = ( 'phone', $mckutils::query{'phone'} );
  }

  if ( $processor =~ /^(barclays)$/ ) {
    @extrafields = ( @extrafields, 'securitylevel', $mckutils::query{'securitylevel'} );
  }

  if ( $retailflag eq 'petroleum' ) {
    @extrafields = (
      @extrafields,               'drivernum', $mckutils::query{'drivernum'}, 'odometer',   $mckutils::query{'odometer'},   'vehiclenum', $mckutils::query{'vehiclenum'}, 'jobnum',
      $mckutils::query{'jobnum'}, 'deptnum',   $mckutils::query{'deptnum'},   'licensenum', $mckutils::query{'licensenum'}, 'userdata',   $mckutils::query{'userdata'},   'userid',
      $mckutils::query{'userid'}, 'devseqnum', $mckutils::query{'devseqnum'}, 'pin',        $mckutils::query{'pin'},        'deviceid',   $mckutils::query{'deviceid'},   'pumpid',
      $mckutils::query{'pumpid'}
    );
  }

  if ( ( $chkprocessor ne "" )
    && ( $mckutils::query{'accttype'} =~ /^(checking|savings)$/ ) ) {
    if ( $mckutils::query{'acctclass'} =~ /^business$/i ) {
      $mckutils::query{'checktype'} = "CCD";
    }
    @extrafields = ( 'acctclass', $mckutils::query{'acctclass'} );
  }
  if ( ( $chkprocessor =~ /^(globaletel)$/ )
    && ( $mckutils::query{'accttype'} =~ /^(checking|savings)$/ )
    && ( $mckutils::query{'checktype'} =~ /^(CCD)$/ ) ) {
    $mckutils::query{'commcardtype'} = "business";
  }

  if ( $mckutils::query{'paymethod'} eq "web900" ) {
    @extrafields = ( 'FinalStatus', $mckutils::query{'FinalStatus'}, 'plan', $mckutils::query{'plan'}, 'web900-pin', $mckutils::query{'web900-pin'} );
  }

  if ( $processor eq "fdmsomaha" ) {
    @extrafields = ( 'descrcodes', $mckutils::query{'descrcodes'}, 'retailterms', $mckutils::query{'retailterms'} );
  }

  if ( $processor eq "global" ) {
    @extrafields = ( 'reportdata', $mckutils::query{'reportdata'} );
  }

  if ( $processor eq "kwikpay" ) {
    for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {
      my $item        = substr( $mckutils::query{"item$i"},        0, 23 );
      my $quantity    = substr( $mckutils::query{"quantity$i"},    0, 5 );
      my $cost        = substr( $mckutils::query{"cost$i"},        0, 9 );
      my $description = substr( $mckutils::query{"description$i"}, 0, 79 );
      my $vatrate     = substr( $mckutils::query{"vatrate$i"},     0, 19 );
      push @extrafields, ( "item$i", "$item", "quantity$i", "$quantity", "cost$i", "$cost", "description$i", "$description", "vatrate$i", "$vatrate" );
    }
    @extrafields = (
      @extrafields,              'address1', $mckutils::query{'address1'}, 'address2', $mckutils::query{'address2'}, 'city',        $mckutils::query{'city'}, 'state',
      $mckutils::query{'state'}, 'zip',      $mckutils::query{'zip'},      'country',  $mckutils::query{'country'},  'shipvatrate', $mckutils::query{'shipvatrate'}
    );
  }

  if ( $mckutils::query{'transflags'} =~ /level3/ ) {
    my ($tax);
    for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {
      $tax += $mckutils::query{"customb$i"};
      my $item        = substr( $mckutils::query{"item$i"},        0, 23 );
      my $quantity    = substr( $mckutils::query{"quantity$i"},    0, 5 );
      my $cost        = substr( $mckutils::query{"cost$i"},        0, 9 );
      my $description = substr( $mckutils::query{"description$i"}, 0, 79 );
      my $customa     = substr( $mckutils::query{"customa$i"},     0, 19 );
      my $customb     = substr( $mckutils::query{"customb$i"},     0, 19 );
      my $customc     = substr( $mckutils::query{"customc$i"},     0, 19 );
      my $unit        = substr( $mckutils::query{"unit$i"},        0, 3 );
      push @extrafields,
        ( "item$i", "$item", "quantity$i", "$quantity", "cost$i", "$cost", "description$i", "$description", "customa$i", "$customa", "customb$i", "$customb", "customc$i", "$customc", "unit$i", "$unit" );
    }
    if ( $mckutils::query{'tax'} eq "" ) {
      $mckutils::query{'tax'} = sprintf( "%.2f", $tax );
    }
  } elsif ( $processor eq "paytechtampa" ) {
    for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {
      my $item        = $mckutils::query{"item$i"};
      my $quantity    = $mckutils::query{"quantity$i"};
      my $cost        = $mckutils::query{"cost$i"};
      my $description = $mckutils::query{"description$i"};
      my $unit        = $mckutils::query{"unit$i"};
      push @extrafields, ( "item$i", "$item", "quantity$i", "$quantity", "cost$i", "$cost", "description$i", "$description", "unit$i", "$unit" );
    }
    @extrafields = (
      @extrafields,                  'deviceid', $mckutils::query{'deviceid'}, 'vehiclenum', $mckutils::query{'vehiclenum'}, 'drivernum',
      $mckutils::query{'drivernum'}, 'pumpid',   $mckutils::query{'pumpid'},   'odometer',   $mckutils::query{'odometer'}
    );
  }

  if ( $processor eq "globalc" ) {
    if ( $mckutils::query{'paymenttype'} eq "invoice" ) {
      for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {
        my $item        = substr( $mckutils::query{"item$i"},        0, 23 );
        my $quantity    = substr( $mckutils::query{"quantity$i"},    0, 5 );
        my $cost        = substr( $mckutils::query{"cost$i"},        0, 9 );
        my $description = substr( $mckutils::query{"description$i"}, 0, 79 );
        my $vatrate     = substr( $mckutils::query{"vatrate$i"},     0, 19 );
        push @extrafields, ( "item$i", "$item", "quantity$i", "$quantity", "cost$i", "$cost", "description$i", "$description", "vatrate$i", "$vatrate" );
      }
    }

    if ( $mckutils::query{'paymenttype'} =~ /^(invoice|bank|check)$/ ) {
      @extrafields = ( @extrafields, 'invoicenumber', $mckutils::query{'invoicenumber'}, 'invoicetype', $mckutils::query{'invoicetype'}, 'invoicedate', $mckutils::query{'invoicedate'} );
    }

    if ( $mckutils::query{'paymenttype'} eq "check" ) {

    }

    if ( $mckutils::query{'paymenttype'} eq "debit" ) {
      my %payidNR = ( 'NL', '701', 'DE', '702', 'AT', '703', 'FR', '704', 'UK', '705', 'BE', '706', 'CH', '707', 'IT', '708', 'ES', '709' );
      my %payidRC = ( 'NL', '711', 'DE', '712', 'AT', '713', 'FR', '714', 'UK', '715', 'BE', '716', 'CH', '717', 'IT', '718', 'ES', '799' );

      if ( $mckutils::query{'transflags'} =~ /recurring/ ) {
        $mckutils::query{'paymentproductid'} = $payidRC{"$mckutils::query{'card-country'}"};
      } else {
        $mckutils::query{'paymentproductid'} = $payidNR{"$mckutils::query{'card-country'}"};
      }

      @extrafields = ( @extrafields, 'bankcode', $mckutils::query{'bankcode'}, 'bankname', $mckutils::query{'bankname'} );
      if ( $mckutils::query{'paymentproductid'} =~ /^(704|708|709|714|718|719)$/ ) {
        @extrafields = ( @extrafields, 'branchcode', $mckutils::query{'branchcode'}, 'bankcheckdigit', $mckutils::query{'bankcheckdigit'} );
      }
      if ( $mckutils::query{'paymentproductid'} =~ /^(705|706|715|716)$/ ) {
        @extrafields = ( @extrafields, 'authorisationid', $mckutils::query{'authorisationid'} );
      }
      if ( $mckutils::query{'paymentproductid'} =~ /^(707|708|709|717|718|719)$/ ) {
        @extrafields = ( @extrafields, 'customerbankstreet', $mckutils::query{'customerbankstreet'} );
      }
      if ( $mckutils::query{'paymentproductid'} =~ /^(707|708|717|718)$/ ) {
        @extrafields = ( @extrafields, 'customerbanknumber', $mckutils::query{'customerbanknumber'} );
      }
      if ( $mckutils::query{'paymentproductid'} =~ /^(707|708|709|717|718|719)$/ ) {
        @extrafields = ( @extrafields, 'customerbankzip', $mckutils::query{'customerbankzip'}, 'customerbankcity', $mckutils::query{'customerbankcity'} );
      }
      if ( $mckutils::query{'paymentproductid'} =~ /^(708|718)$/ ) {
        @extrafields = ( @extrafields, 'bankfiliale', $mckutils::query{'bankfiliale'}, 'bankagenzia', $mckutils::query{'bankagenzia'} );
      }
      if ( $mckutils::query{'paymentproductid'} =~ /^(709|719)$/ ) {
        @extrafields = ( @extrafields, 'domicilio', $mckutils::query{'domicilio'}, 'provincia', $mckutils::query{'provincia'} );
      }
    }
    if ( $mckutils::query{'paymenttype'} =~ /^(invoice|bank|check|debit)$/ ) {
      @extrafields = (
        @extrafields,                 'company',  $mckutils::query{'company'},  'companydata', $mckutils::query{'companydata'}, 'address1',
        $mckutils::query{'address1'}, 'address2', $mckutils::query{'address2'}, 'city',        $mckutils::query{'city'},        'state',
        $mckutils::query{'state'},    'zip',      $mckutils::query{'zip'},      'country',     $mckutils::query{'country'},     'paymentproductid',
        $mckutils::query{'paymentproductid'}
      );
    }
  }

  if ( $walletprocessor eq "onepay" ) {
    @extrafields = ( 'termurl', $mckutils::query{'termurl'}, 'merchantid', $mckutils::query{'merchantid'}, 'message', $mckutils::query{'?message'} );
    if ( $mckutils::query{'?message'} ne "" ) {
      $mckutils::query{'accttype'} = "wallet";
    }
  } elsif ( $walletprocessor =~ /feed/ ) {
    @extrafields = ( 'promocode', $mckutils::query{'promocode'} );
  }

  if ( $processor =~ /^(cyberfns)$/ ) {
    @extrafields = ( 'url', $mckutils::query{'url'}, 'phone', $mckutils::query{'phone'} );
  } elsif ( $processor =~ /^(emerchantpay)/ ) {
    @extrafields = ( 'ipaddress', $mckutils::query{'ipaddress'} );
  } elsif ( $processor =~ /^(psl)$/ ) {
    @extrafields = ( @extrafields, 'dateofbirth', $mckutils::query{'dateofbirth'} );
  } elsif ( $processor =~ /^(newtek)$/ ) {

    # add code to split name into f and l name
    my ( $shipfname, $shiplname ) =
      split( ' ', $mckutils::query{'shipname'}, 2 );
    @extrafields = (
      @extrafields,                 'card-address1', $mckutils::query{'card-address1'}, 'card-address2', $mckutils::query{'card-address2'}, 'shipfname',
      $shipfname,                   'shiplname',     $shiplname,                        'shipcompany',   $mckutils::query{'shipcompany'},   'address1',
      $mckutils::query{'address1'}, 'address2',      $mckutils::query{'address2'},      'city',          $mckutils::query{'city'},          'state',
      $mckutils::query{'state'},    'country',       $mckutils::query{'country'},       'zip',           $mckutils::query{'zip'}
    );
  }

  if ( ( $walletprocessor =~ /^(seqr)$/ )
    && ( $mckutils::query{'paymethod'} eq 'seqr' ) ) {
    @extrafields = ();
    my %seqrHash = %mckutils::query;
    delete $seqrHash{'card-name'};
    delete $seqrHash{'card-address'};
    delete $seqrHash{'card-country'};
    delete $seqrHash{'order-id'};
    push( @extrafields, 'receipt_title', $mckutils::query{'receipt-company'}, %seqrHash );
  }

  if ( $mckutils::query{'accttype'} =~ /^(checking|savings)$/ ) {
    $mckutils::query{'accountnum'} =~ s/[^0-9]//g;
    $mckutils::query{'routingnum'} =~ s/[^0-9]//g;
    if ( ( $chkprocessor =~ /^telecheck/ )
      && ( $mckutils::query{'micr'} =~ /[toaduTOADU]/ ) ) {
      $mckutils::query{'card-number'} = $mckutils::query{'micr'};
    } elsif ( ( $chkprocessor =~ /^(globaletel|securenetach)$/ )
      && ( $mckutils::query{'micr'} =~ /[toaduTOADU]/ ) ) {
      $mckutils::query{'card-number'} = "$mckutils::query{'micr'},$mckutils::query{'routingnum'},$mckutils::query{'accountnum'}";
    } else {
      $mckutils::query{'card-number'} = $mckutils::query{'routingnum'} . " " . $mckutils::query{'accountnum'};
    }
    if ( $mckutils::query{'verification'} =~ /^no$/i ) {
      $mckutils::query{'acct_code3'} = "noverify";
    }

    @extrafields = ( 'checktype', $mckutils::query{'checktype'}, 'checknum', $mckutils::query{'checknum'} );
    if ( $chkprocessor eq "firstamer" ) {
      @extrafields = (
        'checknum',     $mckutils::query{'checknum'},     'dateofbirth', $mckutils::query{'dateofbirth'}, 'socsecnum', $mckutils::query{'socsecnum'},
        'licensestate', $mckutils::query{'licensestate'}, 'licensenum',  $mckutils::query{'licensenum'}
      );
    } elsif ( $chkprocessor eq "telecheckftf" ) {
      @extrafields =
        ( @extrafields, 'termid', $mckutils::query{'termid'}, 'clerkid', $mckutils::query{'clerkid'}, 'licensestate', $mckutils::query{'licensestate'}, 'licensenum', $mckutils::query{'licensenum'} );
    } elsif ( $chkprocessor eq "telecheck" ) {
      if ( $mckutils::query{'acctclass'} eq 'business' ) {
        $mckutils::query{'commcardtype'} = $mckutils::query{'acctclass'};
      }
      @extrafields = (
        @extrafields,                      'termid',        $mckutils::query{'termid'},       'storenum',   $mckutils::query{'storenum'},   'clerkid',
        $mckutils::query{'clerkid'},       'licensestate',  $mckutils::query{'licensestate'}, 'licensenum', $mckutils::query{'licensenum'}, 'card-address1',
        $mckutils::query{'card-address1'}, 'card-address2', $mckutils::query{'card-address2'}
      );
    }
  }

  if ( $mckutils::query{'3dclient'} =~ /^(cardcomm)$/ ) {
    @extrafields = ( 'cavv', "$mckutils::query{'cavv'}", 'eci', $mckutils::query{'eci'}, 'xid', $mckutils::query{'xid'}, 'cavvalgorithm', $mckutils::query{'cavvalgorithm'} );
  }
  if ( $tdsprocessor =~ /^(payvision3ds)/ ) {
    @extrafields = ( 'paresponse', $mckutils::query{'paresponse'} );
  }

  if ( $mckutils::query{'publisher-name'} =~ /^(ncbtest|cwecomairj|cwecomairu|cwtestairj|cwtestairu|cwecomgifj|cwecomgifu|cwecomutij|cwecomutiu)$/ ) {
    @extrafields = ( 'testeci', "$mckutils::query{'testeci'}", 'testmccentry', $mckutils::query{'testmccentry'}, 'testposentry', $mckutils::query{'testposentry'} );
  }

  if ( ( $mckutils::query{'publisher-name'} =~ /testncb|ncbjamaica/ )
    && ( $mckutils::query{'accttype'} eq "credit" ) ) {
    @extrafields = ( 'testhost', $mckutils::query{'testhost'}, 'testposentry', $mckutils::query{'testposentry'} );
  }

  if ( $mckutils::query{'transflags'} eq "hsa" ) {
    my @hasfields = ( 'healthamt', 'rxamt', 'visionamt', 'dentalamt', 'clinicalamt', 'copayamt' );
    foreach my $var (@hasfields) {
      if ( exists $mckutils::query{$var} ) {
        $mckutils::query{$var} =~ s/[^0-9\.]//g;
        push( @extrafields, $var, $mckutils::query{$var} );
      }
    }
  }

  if ( $mckutils::query{'pnpdatasrc'} eq "emv" ) {
    my @emvfields =
      ( 'ksn', 'pindata', 'macblock', 'emvversion', 'serialnum', 'checkdigit', 'origrefnumber', 'reason', 'gratuity', 'emvtags', 'tracenum', 'authencode', 'devtype', 'reporttype', 'report' );
    foreach my $var (@emvfields) {
      if ( exists $mckutils::query{$var} ) {
        $mckutils::query{$var} =~ s/[^a-zA-Z0-9\._\<\>,]//g;
        push( @extrafields, $var, $mckutils::query{$var} );
      }
    }
  }

  if ( $processor =~ /emv$/ ) {
    $mckutils::query{'terminalnum'} =~ s/[^0-9]//g;
    if ( $mckutils::query{'terminalnum'} eq "" ) {
      $mckutils::query{'terminalnum'} = '00099';
    }
    push( @extrafields, 'terminalnum', $mckutils::query{'terminalnum'} );
  }

  ## DCP - ECARD
  if ( $mckutils::query{'card-type'} =~ /^(pl_|sv_)/i ) {
    @extrafields = ( 'card_type', $mckutils::query{'card-type'}, 'descriptor', "$mckutils::query{'descriptor'}" );
  }

  $addr = $mckutils::query{'card-address1'} . " " . $mckutils::query{'card-address2'};
  $addr = substr( $addr, 0, 50 );
  $addr =~ s/[ \t]+$//;
  $amount  = $mckutils::query{'card-amount'};
  $price   = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $amount );
  $country = substr( $mckutils::query{'card-country'}, 0, 2 );

  $mckutils::timetest[ ++$#mckutils::timetest ] = "pre_sendmserver1";
  $mckutils::timetest[ ++$#mckutils::timetest ] = time();

  ## DCP 20081115  Fix Problem Wire Card has with international characters in name field.
  my $tmpname = $mckutils::query{'card-name'};
  $tmpname =~ s/[^a-zA-Z\'0-9\.]/ /g;
  my $card_number = $mckutils::query{'card-number'};

  if ( ( $mckutils::query{'paymethod'} eq 'masterpass' )
    || ( $mckutils::query{'paymethod'} eq 'amexExpressCheckout' ) ) {
    if ( ( $ENV{'HTTP_COOKIE'} ne "" ) ) {
      my (@cookies) = split( '\;', $ENV{'HTTP_COOKIE'} );
      foreach my $var (@cookies) {
        my ( $name, $value ) = split( '=', $var );
        $name =~ s/ //g;
        $mckutils::cookie{$name} = $value;
      }
      my $credit_card_number = "";
      if ( $mckutils::query{'paymethod'} eq 'masterpass' ) {
        my $cookie_value    = uri_unescape( $mckutils::cookie{"masterpass"} );
        my $mpcookieJSON    = JSON::XS::decode_json($cookie_value);
        my $payment_session = $mpcookieJSON->{'pt_payment_session'};

        my $masterPass = new PlugNPay::Client::Masterpass();
        $credit_card_number = $masterPass->retrieveMasterpassCreditCardNumber($payment_session);
      } elsif ( $mckutils::query{'paymethod'} eq 'amexExpressCheckout' ) {
        my $cookie_value    = uri_unescape( $mckutils::cookie{"amexExpressCheckout"} );
        my $mpcookieJSON    = JSON::XS::decode_json($cookie_value);
        my $payment_session = $mpcookieJSON->{'pt_payment_session'};

        my $amexExpress = new PlugNPay::Client::AmexExpress();
        $credit_card_number = $amexExpress->retrieveAmexExpressCreditCardNumber($payment_session);
      }
      $mckutils::query{'card-number'} = $credit_card_number;
    }
  }

  if ( $mckutils::query{'paymethod'} eq 'goCart' ) {
    if ( $mckutils::query{'pt_client_response'} ne '' ) {
      push( @extrafields, 'pt_client_response', $mckutils::query{'pt_client_response'} );
    }
    if ( $mckutils::query{'order-id'} ne '' ) {
      push( @extrafields, 'pt_order_classifier', $mckutils::query{'order-id'} );
    }
  }

  my %sendMServerData = (
    'accttype'      => $mckutils::query{'accttype'},
    'paymethod'     => $mckutils::query{'paymethod'},
    'order-id'      => $mckutils::orderID,
    'acct_code'     => $mckutils::query{'acct_code'},
    'acct_code2'    => $mckutils::query{'acct_code2'},
    'acct_code3'    => $mckutils::query{'acct_code3'},
    'acct_code4'    => $mckutils::query{'acct_code4'},
    'amount'        => $price,
    'card-number'   => $mckutils::query{'card-number'},
    'card-name'     => $tmpname,
    'card-address'  => $addr,
    'card-city'     => $mckutils::query{'card-city'},
    'card-state'    => $mckutils::query{'card-state'},
    'card-zip'      => $mckutils::query{'card-zip'},
    'card-country'  => $country,
    'phone'         => $mckutils::query{'phone'},
    'card-exp'      => $mckutils::query{'card-exp'},
    'card-cvv'      => $mckutils::query{'card-cvv'},
    'subacct'       => $mckutils::query{'subacct'},
    'surcharge'     => $mckutils::query{'surcharge'},
    'transflags'    => $mckutils::query{'transflags'},
    'magstripe'     => $mckutils::query{'magstripe'},
    'commcardtype'  => $mckutils::query{'commcardtype'},
    'tax'           => $mckutils::query{'tax'},
    'ponumber'      => $mckutils::query{'ponumber'},
    'cavv'          => "$mckutils::query{'cavv'}",
    'eci'           => $mckutils::query{'eci'},
    'xid'           => $mckutils::query{'xid'},
    'refnumber'     => $mckutils::query{'refnumber'},
    'cavvalgorithm' => $mckutils::query{'cavvalgorithm'},
    'marketdata'    => $mckutils::query{'marketdata'},
    'freeform'      => $mckutils::query{'freeform'},
    'dccinfo'       => $mckutils::query{'dccinfo'},
    'dccoptout'     => $mckutils::query{'dccoptout'},
    'cashback'      => $mckutils::query{'cashback'},
    'email'         => $mckutils::query{'email'},
    'origorderid'   => $mckutils::query{'origorderid'},
    'ipaddress'     => $mckutils::query{'ipaddress'},
    'prevorderid'   => $mckutils::query{'prevorderid'}
  );

  my %extraFieldsMap = @extrafields;
  %sendMServerData = ( %sendMServerData, %extraFieldsMap );
  $sendMServerData{'__full_transaction_data__'} = \%mckutils::query;

  %result = &miscutils::sendmserver( $mckutils::query{'publisher-name'}, "$mckutils::trans_type", %sendMServerData );

  ## StoreData Temp Fix -- DCP 20170423
  if ( $mckutils::trans_type eq "storedata"
    || $mckutils::query{'paymethod'} eq 'goCart' ) {
    if ( $mckutils::query{'paymethod'} eq 'goCart'
      && $result{'FinalStatus'} ne 'success' ) {
      &genhtml( undef, "Error. " . $result{'MErrMsg'} );
      exit;
    } else {
      $result{'FinalStatus'} = 'success';
    }
  }

  if ( $result{'amount'} ne "" ) {
    $mckutils::query{'amountcharged'} = $result{'amount'};
    $mckutils::query{'amountcharged'} =~ s/[^0-9\.]//g;
  } else {
    $mckutils::query{'amountcharged'} = $mckutils::query{'card-amount'};
  }

  if ( ( $mckutils::accountFeatures->get('enableToken') == 1 )
    && ( $mckutils::query{'card-number'} ne "" ) ) {    ###  Temporary until token server fully operational 20170405
    my $cc = new PlugNPay::Token();
    $result{'token'}                 = $cc->getToken( $mckutils::query{'card-number'} );
    $mckutils::query{'paymentToken'} = $result{'token'};
  }

  &receiptcc();

  if ( ( $mckutils::processor =~ /^(planetpay|testprocessor|fifththird)$/ )
    && ( $mckutils::query{'transflags'} =~ /multicurrency/ ) ) {
    my @array = ( %mckutils::query, %result );
    %result = ( %result, &parse_multicurrency(@array) );
  }

  if ( ( $chkprocessor eq "alliance" )
    && ( $result{'FinalStatus'} eq "pending" ) ) {
    $result{'FinalStatus'} = "success";
  }

  if ( $mckutils::processor eq "fdms" ) {
    $result{'invoicerefnum'} = substr( $result{'auth-code'}, 33, 10 );
  }

  if ( ( $chkprocessor eq "telecheckftf" )
    && ( $mckutils::query{'accttype'} =~ /^(checking|savings)$/ )
    && ( $result{'resp-code'} eq "83" ) ) {
    $mckutils::query{'badcard-link'} = "https://pay1.plugnpay.com/admin/fdis-ny_vt.cgi";
    $result{'FinalStatus'}           = 'badcard';
    $result{'MErrMsg'}               = "Please renter License / ID Number";
  } elsif ( ( $chkprocessor eq "telecheckftf" )
    && ( $mckutils::query{'accttype'} =~ /^(checking|savings)$/ )
    && ( $result{'chkstatus'} eq "deposit" )
    && ( $mckutils::query{'publisher-name'} =~ /^(jhew)/ ) ) {
    $result{'FinalStatus'} = 'badcard';
    $result{'MErrMsg'}     = "Bank Does Not Support ECA.";
  }

  if (
    ( $mckutils::query{'publisher-name'} =~
      /^(americanfa1|heathcares|healthyliv2|directdisc1|discountsa1|smartshopp1|leisuretim2|myleisurea|discopuntt|24hourroad|unlimitedl1|shopsmarts|americasch|contactcen|ronallenas|americaspu|identiityt1|prepaidleg|familyheal1|healthcare6|healthyliv1|directdisc|discountsa|smartshopp|leisuretim1|americanfa2|healthcare8|healthyliv4|directdisc3|discountsa2|smartshopp2|leisuretim3|myleisures|idtheftpro|discounttr1|prepaidleg2|shopsmarts1|discountdi|leisuresav|livehealth|strategias|strategiac4|strategiac2|strategiam|strategiac1|strategiac3|strategiac)/
    )
    && ( $result{'resp-code'} =~ /^(96|98|E)$/ )
    ) {
    $result{'FinalStatus'} = 'badcard';
  }

  if ( $walletprocessor eq "onepay" ) {
    delete $result{'order-id'};
    my %data = &miscutils::getquery( $result{'querystr'} );
    foreach my $key ( keys %data ) {
      if ( $key eq "order-id" ) {
        $result{'orderID'} = $data{'order-id'};
      } elsif ( $key eq "amount" ) {
        $data{'amount'} =~ /^(\w{3}) (.*)$/;
        ( $result{'currency'}, $result{'card-amount'} ) = ( $1, $2 );
      } else {
        $result{$key} = $data{$key};
      }
    }
    delete $result{'querystr'};
  }

  $mckutils::timetest[ ++$#mckutils::timetest ] = "post_sendmserver";
  $mckutils::timetest[ ++$#mckutils::timetest ] = time();

  $result{'card-number'} = substr( $mckutils::query{'card-number'}, 0, 4 );

  %mckutils::result = %result;

  $timeresult = time();

  if ( $result{'FinalStatus'} eq "success" ) {
    ##  Added 20061005 to bypass fraud etc... for pass1 of 2 pass DCC
    if ( ( $mckutils::dcc eq "yes" )
      && ( $result{'acct_code4'} eq "RATELKUP" ) ) {

      #my @array = %mckutils::query;
      my @array = ( %mckutils::query, %result );
      %result = ( %result, &dccmsg(@array) );
      return %result;
    }

    $mckutils::timetest[ ++$#mckutils::timetest ] = "start_success";
    $mckutils::timetest[ ++$#mckutils::timetest ] = time();

    ## Modified 20071029 to exempt transflags=recurring
    if ( ( ( $fraud::fraud_config{'cvv_avs'} != 1 ) || ( $result{'cvvresp'} ne "M" ) )
      && ( $fraud::exemptflag != 1 )
      && ( $mckutils::query{'accttype'} eq "credit" )
      && ( $mckutils::query{'paymethod'} !~ /^(invoice|web900)$/ )
      && ( $mckutils::query{'transflags'} !~ /recurring/ )
      && ( $purchasetype ne "storedata" ) ) {
      if (
        ( $mckutils::query{'app-level'} ne "" )
        && (
          ( $fraud::fraud_config{'cvv_3dign'} != 1 )
          || ( ( $mckutils::query{'paresponse'} eq "" )
            && ( $mckutils::query{'cavv'} eq "" ) )
           )
        ) {
        $mckutils::timetest[ ++$#mckutils::timetest ] = "pre_cvvavs_void";
        $mckutils::timetest[ ++$#mckutils::timetest ] = time();

        &avs_void($processor);

        $mckutils::timetest[ ++$#mckutils::timetest ] = "post_cvvavs_void";
        $mckutils::timetest[ ++$#mckutils::timetest ] = time();
      }
    }

    ## Modified 20071029 to exempt transflags=recurring
    if ( ( $mckutils::query{'card-cvv'} ne "" )
      && ( $result{'cvvresp'} ne "M" )
      && ( $mckutils::cardtype !~ /^(AMEX)$/ )
      && ( $fraud::fraud_config{'cvv_xpl'} == 1 )
      && ( $result{'FinalStatus'} eq "success" )
      && ( $fraud::exemptflag != 1 )
      && ( $mckutils::query{'transflags'} !~ /recurring/ )
      && ( $purchasetype ne "storedata" ) ) {
      if (
        ( $fraud::fraud_config{'cvv_3dign'} != 1 )
        || ( ( $mckutils::query{'paresponse'} eq "" )
          && ( $mckutils::query{'cavv'} eq "" ) )
        ) {
        $mckutils::timetest[ ++$#mckutils::timetest ] = "pre_cvv_void";
        $mckutils::timetest[ ++$#mckutils::timetest ] = time();

        my $scriptname = $ENV{'SCRIPT_NAME'};
        $scriptname =~ /.*\/(.*?\.cgi)/;
        $scriptname = $1;
        $mckutils::query{'acct_code4'} = "CVV mismatch.:$scriptname:$mckutils::query{'IPaddress'}";
        my $voidstatus = &void();
        if ( $voidstatus eq "success" ) {
          $result{'errdetails'} = "card-cvv\|CVV2/CVC2 number does not match.$mckutils::cardtype.";
          $result{'MErrMsg'}    = "Sorry, the CVV2/CVC2 number entered does not match the number on the credit card.";
          $result{'resp-code'}  = "P02";
        }
        $mckutils::timetest[ ++$#mckutils::timetest ] = "post_cvv_void";
        $mckutils::timetest[ ++$#mckutils::timetest ] = time();
      }
    }
    ## Modified  20060713 to add $mckutils::fconfig{'cvv_ign'} != 1 to support VT
    ## Modified 20071029 to exempt transflags=recurring
    if ( ( $mckutils::query{'card-cvv'} ne "" )
      && ( $result{'cvvresp'} eq "N" )
      && ( $result{'FinalStatus'} eq "success" )
      && ( $fraud::exemptflag != 1 )
      && ( $fraud::fraud_config{'cvv_ign'} != 1 )
      && ( $mckutils::fconfig{'cvv_ign'} != 1 )
      && ( $mckutils::query{'transflags'} !~ /recurring/ ) ) {

      if (
        ( $fraud::fraud_config{'cvv_3dign'} != 1 )
        || ( ( $mckutils::query{'paresponse'} eq "" )
          && ( $mckutils::query{'cavv'} eq "" ) )
        ) {
        $mckutils::timetest[ ++$#mckutils::timetest ] = "pre_cvv2_void";
        $mckutils::timetest[ ++$#mckutils::timetest ] = time();

        my $scriptname = $ENV{'SCRIPT_NAME'};
        $scriptname =~ /.*\/(.*?\.cgi)/;
        $scriptname = $1;
        $mckutils::query{'acct_code4'} = "CVV mismatch.:$scriptname:$mckutils::query{'IPaddress'}";
        my $voidstatus = &void();
        if ( $voidstatus eq "success" ) {
          $result{'errdetails'} = "card-cvv\|CVV2/CVC2 number does not match.";
          $result{'MErrMsg'}    = "Sorry, the CVV2/CVC2 number entered does not match the number on the credit card.";
          $result{'resp-code'}  = "P02";
        }

        $mckutils::timetest[ ++$#mckutils::timetest ] = "post_cvv2_void";
        $mckutils::timetest[ ++$#mckutils::timetest ] = time();
      }
    }

    $mckutils::timetest[ ++$#mckutils::timetest ] = "post_void";
    $mckutils::timetest[ ++$#mckutils::timetest ] = time();

    if ( ( $fraud_config ne "" )
      && ( $result{'FinalStatus'} eq "success" ) ) {
      $mckutils::timetest[ ++$#mckutils::timetest ] = "pre_postauth_fraud";
      $mckutils::timetest[ ++$#mckutils::timetest ] = time();

      my (%res);
      my @array = ( %mckutils::query, %result );
      %res = $mckutils::fraudtrack->postauth_fraud_screen(@array);

      $mckutils::timetest[ ++$#mckutils::timetest ] = "post_postauth_fraud";
      $mckutils::timetest[ ++$#mckutils::timetest ] = time();

      if ( $res{'FinalStatus'} eq "fraud" ) {
        my $scriptname = $ENV{'SCRIPT_NAME'};
        $scriptname =~ /.*\/(.*?\.cgi)/;
        $scriptname = $1;
        $mckutils::query{'acct_code4'} = "Fraudtrack postauth.:$scriptname:$mckutils::query{'IPaddress'}";
        my $voidstatus = &void();
        if ( $voidstatus eq "success" ) {
          $result{'MErrMsg'}     = "Sorry, the transaction failed Cybersource Fraud Test and was voided.";
          $result{'FinalStatus'} = "fraud";
          $result{'MStatus'}     = "failure";
          $result{'resp-code'}   = "P03";
        }

        $mckutils::timetest[ ++$#mckutils::timetest ] = "post_postauth_fraud_void";
        $mckutils::timetest[ ++$#mckutils::timetest ] = time();

      }
    }

    $mckutils::timetest[ ++$#mckutils::timetest ] = "post_postauthfraud";
    $mckutils::timetest[ ++$#mckutils::timetest ] = time();

    ## DCP 20100520 - Default handling of partial auth
    if ( ( $mckutils::query{'transflags'} =~ /partial/i )
      && ( $mckutils::feature{'partialresp'} eq "void" )
      && ( $result{'amount'} =~ /[a-z]{3} / ) ) {
      my $tstamt = substr( $result{'amount'}, 4 );
      if ( $tstamt < $mckutils::query{'card-amount'} ) {
        ###  Void
        $result{'FinalStatus'} = "badcard";
        $result{'resp-code'}   = "51";
        $result{'MErrMsg'}     = "Partial Auth less than original amount.  Auto Void.";
        my $acct_code4 = "partial_auth_autovoid";

        my (%result1);
        for ( my $i = 1 ; $i <= 5 ; $i++ ) {
          if ( ( $mckutils::trans_type eq "auth" )
            && ( $mckutils::proc_type eq "authcapture" ) ) {
            %result1 = &miscutils::sendmserver(
              $mckutils::query{'publisher-name'},
              "return", 'acct_code', $mckutils::query{'acct_code'},
              'acct_code4', "$acct_code4", 'amount', "$result{'amount'}", 'order-id', "$mckutils::orderID"
            );
          } else {
            %result1 = &miscutils::sendmserver(
              $mckutils::query{'publisher-name'},
              "void", 'acct_code', $mckutils::query{'acct_code'},
              'acct_code4', "$acct_code4", 'txn-type', 'marked', 'amount', "$result{'amount'}", 'order-id', "$mckutils::orderID"
            );

          }
          last if ( $result1{'FinalStatus'} eq "success" );
        }
      }
    }

    ###  DCP  - Moved here from above to allow PostAuth Fraud Checking as well. Niche
    if ( $result{'FinalStatus'} eq "success" ) {
      if ( $mckutils::query{'fraudholdstatus'} eq "hold" ) {
        &setholdstatus();
      }
    }

    ###  MP GiftCard Reload
    if ( ( $mckutils::query{'transflags'} =~ /reload/ )
      && ( $mckutils::query{'mpgiftcard'} ne "" )
      && ( $processor =~ /^(mercury)$/ )
      && ( $result{'FinalStatus'} eq "success" ) ) {
      my %result = &mpgift_reload();
    }

    if ( ( $result{'FinalStatus'} eq "success" )
      && ( $mckutils::query{'promoid'} ne "" )
      && ( $mckutils::query{'discnt'} > 0 ) ) {
      my $dbh = &miscutils::dbhconnect("merch_info");

      # DEBUG NOTE: Cannot test gift cert code using test mode (cardtest & pnptest will not use this code) Must do tests with a real card!

      # get coupon usage count & usage limit
      my $sth = $dbh->prepare(
        qq{
          select use_count,use_limit
          from promo_coupon
          where username=? and promoid=?
          and subacct=?
          }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
      $sth->execute( "$mckutils::query{'publisher-name'}", "$mckutils::query{'promoid'}", "$mckutils::query{'subacct'}" )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
      my ( $cnt, $limit ) = $sth->fetchrow;
      $sth->finish;

      $cnt++;    # increase usage count by one

      # if it's a gift cert coupon, deduct the discount from the available coupon balance
      if ( ( $limit =~ /\.\d{2}$/ ) ) {
        my (%result1);

        # Need to be sure we are actually deducting the correct $ amount from the limit. (check for order tampering)
        if ( $limit < $mckutils::query{'discnt'} ) {

          # force a badcard rejection when discount total exceeds the limit on the gift cert
          $result{'FinalStatus'}       = "badcard";
          $result{'MStatus'}           = "badcard";
          $result{'auth-code'}         = "";
          $result{'MErrMsg'}           = "Discount exceeds available gift certificate balance.";
          $result{'resp-code'}         = "P100";
          $main::result{'FinalStatus'} = "badcard";
          $main::result{'MStatus'}     = "badcard";

          # tampering detected, reject order
          my $emailer = new PlugNPay::Email('legacy');
          $emailer->setGatewayAccount( $mckutils::query{'publisher-name'} );
          $emailer->setFormat('text');
          $emailer->setTo("turajb\@plugnpay.com");
          $emailer->setFrom("mckutils\@plugnpay.com");
          $emailer->setSubject("Gift Certificate Usage Tampering Detected - $mckutils::query{'publisher-name'}");
          my $email_msg = "UN: $mckutils::query{'publisher-name'}\n";
          $email_msg .= "IP: $remote_ip\n\n";
          $email_msg .= "Tampering has been detected on transaction orderID $mckutils::query{'orderID'}\n";
          $email_msg .= "Discount \$$mckutils::query{'discnt'} exceeds available gift certificate balance \$$limit.\n\n";
          $email_msg .= "The order has been rejected & the discount \$ amount was not deducted form the gift certificate coupon.\n";
          $emailer->setContent($email_msg);
          $emailer->send();

          if ( $mckutils::query{'paymenthod'} !~ /invoice/i ) {
            %result1 = &miscutils::sendmserver(
              $mckutils::query{'publisher-name'},
              "void", 'acct_code', $mckutils::query{'acct_code'},
              'acct_code4', "$mckutils::query{'acct_code4'}",
              'txn-type', 'marked', 'amount', "$mckutils::query{'card-amount'}",
              'order-id', "$mckutils::query{'orderID'}"
            );
          }
          %mckutils::result = %result;
        } else {

          # discount total is with $ limit of gift cert
          # so calculate order total to see if it matches what was sent in...
          my $order_total = 0;

          # add in each item to the order total
          for ( my $i = 1 ; $i <= $mckutils::query{'max'} ; $i++ ) {
            if ( ( $mckutils::query{"item$i"} ne "" )
              && ( $mckutils::query{"cost$i"} > 0.00 )
              && ( $mckutils::query{"quantity$i"} > 0 )
              && ( $mckutils::query{"description$i"} ne "" ) ) {
              $order_total += ( $mckutils::query{"cost$i"} * $mckutils::query{"quantity$i"} );
            }
          }
          $order_total += $mckutils::query{"shipping"};    # add in shipping fee
          $order_total += $mckutils::query{"tax"};         # add in sales tax
          $order_total -= $mckutils::query{'discnt'};      # subtract coupon discount

          $order_total = sprintf( "%0.2f", $order_total );

          # now check to see if the order totals match what was sent in & what was calculated...
          if ( $order_total != $mckutils::query{'card-amount'} ) {

            # tampering detected, reject order
            my $emailer = new PlugNPay::Email('legacy');
            $emailer->setGatewayAccount( $mckutils::query{'publisher-name'} );
            $emailer->setFormat('text');
            $emailer->setTo("turajb\@plugnpay.com");
            $emailer->setFrom("mckutils\@plugnpay.com");
            $emailer->setSubject("Gift Certificate Usage Tampering Detected - $mckutils::query{'publisher-name'}");
            my $email_msg = "UN: $mckutils::query{'publisher-name'}\n";
            $email_msg .= "IP: $remote_ip\n\n";
            $email_msg .= "Tampering has been detected on transaction orderID $mckutils::query{'orderID'}\n";
            $email_msg .= "The recalculated order total \$$order_total, does not match the card-amount \$$mckutils::query{'card-amount'} submitted.\n\n";
            $email_msg .= "The order has been rejected & the discount \$ amount was not deducted form the gift certificate coupon.\n";
            $emailer->setContent($email_msg);
            $emailer->send();

            # force a badcard rejection
            $result{'FinalStatus'}       = "badcard";
            $result{'MStatus'}           = "badcard";
            $result{'auth-code'}         = "";
            $result{'MErrMsg'}           = "Gift certificate discount does not match order.";
            $result{'resp-code'}         = "P101";
            $main::result{'FinalStatus'} = "badcard";
            $main::result{'MStatus'}     = "badcard";

            #$mckutils::success = "no";

            %mckutils::result = %result;

            if ( $mckutils::query{'paymenthod'} !~ /invoice/i ) {
              %result1 = &miscutils::sendmserver(
                $mckutils::query{'publisher-name'},
                "void", 'acct_code', $mckutils::query{'acct_code'},
                'acct_code4', "$mckutils::query{'acct_code4'}",
                'txn-type', 'marked', 'amount', "$mckutils::query{'card-amount'}",
                'order-id', "$mckutils::query{'orderID'}"
              );
            }

            %mckutils::result = %result;
          } else {

            # no tampering detected, so figure out what the new gift certificate balance should be
            $limit -= $mckutils::query{'discnt'};
            if ( $limit < 0 ) {
              $limit = 0.00;
            }
            $limit = sprintf( "%0.2f", $limit );
          }
        }
      }

      # update coupon usage count & usage limit
      $sth = $dbh->prepare(
        qq{
          update promo_coupon
          set use_count=?,use_limit=?
          where username=? and promoid=?
          and subacct=?
      }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
      $sth->execute( "$cnt", "$limit", "$mckutils::query{'publisher-name'}", "$mckutils::query{'promoid'}", "$mckutils::query{'subacct'}" )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
      $sth->finish;

      $dbh->disconnect;
    }

    if ( $result{'FinalStatus'} eq "success" ) {

      # communicate the result of the transaction to Masterpass.
      if ( $mckutils::query{'paymethod'} eq 'masterpass' ) {
        my $authCode = substr( $result{'auth-code'}, 0, 6 );
        my $masterPass = new PlugNPay::Client::Masterpass();
        $masterPass->masterpassLog($authCode);
      }
      if ( ( ( ( $proc_type eq "authpostauth" ) && ( $mckutils::postauthflag ne "no" ) ) || ( $mckutils::query{'authtype'} eq "authpostauth" ) )
        && ( $mckutils::query{'paymethod'} !~ /^(invoice|web900)$/ )
        && ( $proc_type ne "authcapture" )
        && ( $purchasetype ne "storedata" )
        && ( $result{'merchfraudlev'} != 2 )
        && ( $mckutils::query{'transflags'} !~ /avsonly|capture/i )
        && ( $result{'transflags'} !~ /capture/i ) ) {
        my (%result2);
        my @extrafields = ();
        if ( ( $mckutils::industrycode eq "restaurant" )
          && ( $mckutils::query{'gratuity'} > 0 ) ) {
          @extrafields = ( 'gratuity', $mckutils::query{'gratuity'} );
          $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $mckutils::query{'card-amount'} + $mckutils::query{'gratuity'} );

        }
        %result2 = &miscutils::sendmserver(
          $mckutils::query{'publisher-name'},
          "postauth", 'accttype', $mckutils::query{'accttype'},
          'acct_code', $mckutils::query{'acct_code'},
          'acct_code4', $mckutils::query{'acct_code4'},
          'order-id', $mckutils::orderID, 'amount', $price, @extrafields
        );

        $result{'postauthstatus'} = $result2{'FinalStatus'};

        $mckutils::timetest[ ++$#mckutils::timetest ] = "post_postauth";
        $mckutils::timetest[ ++$#mckutils::timetest ] = time();
      }

      $mckutils::success = "yes";
      if ( $mckutils::query{'upsellord'} ne "" ) {
        &upsell_dbase();
      }
      &cookie();
      if ( ( $mckutils::dcc eq "yes" ) && ( $result{'dccinfo'} ne "" ) ) {
        my @array = ( %mckutils::query, %result );
        %result = ( %result, &dccmsg(@array) );
      }

      if ( $mckutils::drop_ship_flag == 1 ) {
        &drop_ship_parse();
      }
      ## Commented Out by DCP 20070310
      ## Added back by DCP 20081126
      if ( $mckutils::query{'CertiTaxID'} ne "" ) {
        &CertiTaxFinal();
      }
    }
  } elsif ( $result{'FinalStatus'} eq "badcard" ) {
    if ( $result{'MErrMsg'} =~ /stolen|No such issuer/i ) {
      my @array = %mckutils::query;
      &fraud_database(@array);
    }
    $mckutils::success = "no";
  } else {
    my (%result1);
    if ( $result{'MErrMsg'} =~ /failed to respond in a timely manner/i ) {
      if ( ( $mckutils::trans_type eq "auth" )
        && ( $proc_type eq "authcapture" ) ) {
        %result1 = &miscutils::sendmserver( $mckutils::query{'publisher-name'}, "return", 'acct_code', $mckutils::query{'acct_code'}, 'amount', "$price", 'order-id', "$mckutils::orderID" );
      } else {
        %result1 =
          &miscutils::sendmserver( $mckutils::query{'publisher-name'}, "void", 'acct_code', $mckutils::query{'acct_code'}, 'txn-type', 'marked', 'amount', "$price", 'order-id', "$mckutils::orderID" );
      }
    }
    $mckutils::success = "no";

    #&problem_log();
    &support_email();
  }

  ## if tran was routed store account name tran was processed with.
  if ( $mckutils::query{'preRoutedAccount'} ne "" ) {
    $mckutils::query{'processedAccount'} = $mckutils::query{'publisher-name'};
  }
  ## Check for current tran status and change un back as appropriate
  if ( ( $result{'FinalStatus'} ne "success" )
    && ( $mckutils::query{'preRoutedAccount'} ne "" ) ) {
    $mckutils::query{'publisher-name'} = $mckutils::query{'preRoutedAccount'};
    $mckutils::query{'merchant'}       = $mckutils::query{'preRoutedAccount'};
  }

  my $start_trantime = $miscutils::timetest[1];
  my $end_trantime   = $miscutils::timetest[$#miscutils::timetest];
  my $delta_trantime = $end_trantime - $start_trantime;

  if ( -e "/home/p/pay1/outagefiles/logtran_times.txt" ) {    ###  DCP 20100826
    &record_time2();
  }

  %mckutils::result = %result;

  my $digests = resp_hash( \%mckutils::feature, \%mckutils::query, \%mckutils::result, $mckutils::convfeeflag );
  $mckutils::query{'resphash'}        = $digests->{'md5Sum'};
  $mckutils::query{'resphash_sha256'} = $digests->{'sha256Sum'};

  return %result;
}

sub record_time {

  #return;
  my ($times) = @_;
  my (%times) = ( %$times, %miscutils::timetest );
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  my $mo = sprintf( "%02d", $mon + 1 );
  &sysutils::filelog( "append", ">>/home/p/pay1/database/debug/tran_times$mo.txt" );
  open( TIMES, ">>/home/p/pay1/database/debug/tran_times$mo.txt" );
  my ($oldtime);
  print TIMES "1:$mckutils::query{'publisher-name'}, OID:$mckutils::orderID\n";
  my ($a);

  foreach my $key ( sort keys %times ) {
    if ( $oldtime eq "" ) {
      $oldtime = $key;
    }
    $a = $key;
    my $delta = $a - $oldtime;
    print TIMES "$times{$key}:$delta\n";
  }
  my $tottime = $a - $oldtime;
  print TIMES "TOTTIME:$tottime\n";
  print TIMES "\n\n";
  close(TIMES);
}

sub record_time2 {
  my @timetest1 = @miscutils::timetest;

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  my $mo = sprintf( "%02d", $mon + 1 );
  &sysutils::filelog( "append", ">>/home/p/pay1/database/debug/tran_times$mo.txt" );
  open( TIMES, ">>/home/p/pay1/database/debug/tran_times$mo.txt" );

  print TIMES "1:$mckutils::query{'publisher-name'}, OID:$mckutils::orderID\n";

  for ( my $i ; $i <= @mckutils::timetest ; $i++ ) {
    my $etime = $mckutils::timetest[ $i + 1 ] - $mckutils::timetest[0];
    print TIMES "$mckutils::timetest[$i]:$mckutils::timetest[$i+1]:$etime\n";
    $i++;
  }
  print TIMES "\n";

  for ( my $i ; $i <= @miscutils::timetest ; $i++ ) {
    print TIMES "$miscutils::timetest[$i]:$miscutils::timetest[$i+1]\n";
    $i++;
  }

  my ( $oldtime, $flag );
  my ($a);
  for ( my $i ; $i <= @timetest1 ; $i++ ) {
    my $tag = $timetest1[$i];
    if ( $oldtime eq "" ) {
      $oldtime = $timetest1[ $i + 1 ];
    }
    if ( $timetest1[ $i + 1 ] > 1 ) {
      $a = $timetest1[ $i + 1 ];
    }
    my $delta = $a - $oldtime;
    print TIMES "$tag:$delta\n";
    $i++;
  }
  my $tottime = $a - $oldtime;
  print TIMES "TOTTIME:$tottime\n";
  print TIMES "\n\n";
  close(TIMES);
}

sub gotolocation {
  if ( ( $mckutils::result{'FinalStatus'} eq "fraud" )
    && ( $mckutils::query{'fraud-link'} eq "" ) ) {
    $mckutils::result{'FinalStatus'} = "badcard";
  }
  print "Location: " . $mckutils::query{"$mckutils::result{'FinalStatus'}-link"} . "\r\n\r\n";
}

sub genwml {
  my $type = shift;
  my ($message) = @_;
  &support_email("other");
  print "Content-Type: text/vnd.wap.wml\r\n\r\n";
  print "<?xml version=\"1.0\"?>\n";
  print "<!DOCTYPE wml PUBLIC \"-//WAPFORUM//DTD WML 1.1//EN\" \"http://www.wapforum.org/DTD/wml_1.1.xml\">\n";
  print "<wml>\n";
  print "<card id=\"thankyou\">\n";
  print "<do type=\"accept\" label=\"Continue\"> \n";
  print "  <go href=\"#input1\"> \n";
  print "  </go>\n";
  print "</do>\n";
  print "<p>\n";
  print $message . "\n";
  print "</p>\n";
  print "</card>\n";
  print "</wml>";

}

sub genmobile {
  my ($message) = @_;

  print header( -type => 'text/html' );
  print "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n";
  print "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n";
  print "<head>\n";
  print "  <title>Plug n Pay</title>\n";
  print "  <meta name=\"viewport\" content=\"width=320; initial-scale=1.0; maximum-scale=1.0; user-scalable=0;\"/>\n";
  print "  <link rel=\"apple-touch-icon\" href=\"/javascript/iui/pnpicon.png\" />\n";
  print "  <meta name=\"apple-touch-fullscreen\" content=\"YES\" />\n";
  print "  <style type=\"text/css\" media=\"screen\">\@import \"/javascript/iui/iui.css\";</style>\n";
  print "</head>\n";

  print "<body>\n";
  print "  <div class=\"toolbar\">\n";
  print "  </div>\n";
  print "      <h2>Transaction Results</h2>\n";
  print "      <fieldset>\n";
  print "          <div class=\"row\">\n";
  print "              <div class=\"rightlabel\">$message</div>\n";
  print "          </div>\n";
  print "      </fieldset>\n";
  print "</body>\n";
  print "</html>\n";

}

sub genhtml {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my $type = shift;
  my ( $message, $autoclose, %cookie ) = @_;
  my ( $onload, $boundary, $filename, @cookie );

  if ( $autoclose eq "yes" ) {
    $onload = "self.close()\;";
  }

  if ( $remote_ip eq "96.56.10.121" ) {
    my $i = 0;
    foreach my $key ( keys %cookie ) {
      $cookie[$i] = cookie( -name => "$key", -value => "$cookie{$key}" );
    }
    print header( -cookie => [@cookie] );
  }

  if ( ( $mckutils::feature{'storeresults'} ne "" )
    && ( $mckutils::query{'returnresults'} eq "yes" ) ) {
    $onload = &storeresults();
  }

  if ( ( $mckutils::feature{'contenttype'} ne "" )
    && ( $mckutils::query{'returnresults'} eq "yes" ) ) {
    $boundary = &contenttype();
  } else {
    print header( -type => 'text/html' );    #### DCP 20100712
  }

  print "<html>\n";
  print "<head>\n";
  print "<title>Payment Server</title>\n";

  if ( $ENV{'SCRIPT_NAME'} =~ /admin\// ) {

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
  }

  ## 07/05/08 - Added 'css-link' support, for custom CSS file using on online receipts.
  if ( $mckutils::feature{'css-link'} ne "" ) {
    print "<link href=\"$mckutils::feature{'css-link'}\" type=\"text/css\" rel= \"stylesheet\">\n";
  } elsif ( ( $mckutils::query{'receipt_type'} ne "" )
    || ( $mckutils::query{'receipt-type'} ne "" ) ) {
    print "<link href=\"/css/style_receipt.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  }

  print "</head>\n";

  if (
    ( ( $mckutils::query{'receipt_type'} ne "" ) || ( $mckutils::query{'receipt-type'} ne "" ) )
    && ( ( $mckutils::query{'print_receipt'} eq "yes" )
      || ( $mckutils::query{'print-receipt'} eq "yes" ) )
    ) {
    print "<body bgcolor=\"#ffffff\" onLoad=\"window.print();\">\n";
  } else {
    print "<body bgcolor=\"#ffffff\" $onload>\n";
  }

  if ( $mckutils::query{'image-link'} ne "" ) {
    print "<div align=center>\n";
    print "<img src=\"$mckutils::query{'image-link'}\">\n";
    print "</div>\n";
  }

  print "<p>\n";
  if ( ( $mckutils::query{'receipt_type'} =~ /^pos_/ )
    || ( $mckutils::query{'receipt-type'} =~ /^pos_/ ) ) {
    print $message . "\n";
  } else {
    print "<div align=center class=info>\n";
    print "<font size=+1>\n";
    print $message . "\n";
    print "</font>\n";
    if ( $message =~ /Could not connect socket/ ) {
      print "<p>Try backing up and hitting the \"Submit\" button again.</p>\n";
    }
    print "</div>\n";
    print "</p>\n";
  }

  print "</body>\n";
  print "</html>\n";

  if ( $mckutils::feature{'contenttype'} ne "" ) {
    print "$boundary\n";
  }

}

# mo' bettah name than genhtml2
sub displayHtml {
  my $html = shift;

  print header( -type => 'text/html' );
  print $html;
}

# still chillin just to cya TODO add metric or log or somethin to track calls to this
sub genhtml2 {
  shift;    # :|
  return displayHtml(shift);
}

sub gotocgi {
  my ( $pairs, %input );
  %input = ();
  $pairs = "";

  ### At this point in code publisher-name can be either publisher_name or publisher-name
  ##  What is constant is merchant.
  ## Changing all reference to var  merchant so logging works properly.
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  my $now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
  my $curmonth = sprintf( "%02d", $mon + 1 );

  if ( $mckutils::result{'FinalStatus'} ne "success" ) {
    $mckutils::query{'MErrMsg'}     = $mckutils::result{'MErrMsg'};
    $mckutils::query{'success'}     = $mckutils::mckutils::success;
    $mckutils::query{'auth-code'}   = $mckutils::result{'auth-code'};
    $mckutils::query{'avs-code'}    = $mckutils::result{'avs-code'};
    $mckutils::query{'cvvresp'}     = $mckutils::result{'cvvresp'};
    $mckutils::query{'auth-msg'}    = $mckutils::result{'auth-msg'};
    $mckutils::query{'pnpid'}       = $mckutils::cookie{'pnpid'};
    $mckutils::query{'FinalStatus'} = $mckutils::result{'FinalStatus'};
    $mckutils::query{'resp-code'}   = $mckutils::result{'resp-code'};
    if ( exists $mckutils::result{'due-amount'} ) {
      $mckutils::query{'due-amount'} = $mckutils::result{'due-amount'};
    }
    delete $mckutils::query{'bcommonname'};
    delete $mckutils::query{'scommonname'};
    delete $mckutils::query{'orderID'};
  } else {
    $mckutils::query{'success'}     = $mckutils::success;
    $mckutils::query{'MErrMsg'}     = "";
    $mckutils::query{'resp-code'}   = $mckutils::result{'resp-code'};
    $mckutils::query{'auth-code'}   = $mckutils::result{'auth-code'};
    $mckutils::query{'avs-code'}    = $mckutils::result{'avs-code'};
    $mckutils::query{'cvvresp'}     = $mckutils::result{'cvvresp'};
    $mckutils::query{'auth-msg'}    = $mckutils::result{'auth-msg'};
    $mckutils::query{'FinalStatus'} = $mckutils::result{'FinalStatus'};
  }
  $mckutils::query{'id'} = $mckutils::orderID;

  if ( exists $main::result{'FinalStatusCF'} ) {
    $mckutils::query{'auth-codeCF'}   = $main::result{'auth-codeCF'};
    $mckutils::query{'FinalStatusCF'} = $main::result{'FinalStatusCF'};
    $mckutils::query{'MErrMsgCF'}     = $main::result{'MErrMsgCF'};
    $mckutils::query{'orderIDCF'}     = $main::result{'orderIDCF'};
    $mckutils::query{'convfeeamt'}    = $main::result{'convfeeamt'};
  }

  if ( exists $mckutils::query{'accountnum'} ) {
    $mckutils::query{'accountnum'} = $mckutils::filteredAN;
  }

  if ( ( exists $mckutils::query{'ssnum'} )
    && ( $mckutils::feature{'sendssn'} != 1 ) ) {
    $mckutils::query{'ssnum'} = $mckutils::filteredSSN;
  }

  if ( ( $mckutils::query{'client'} =~ /coldfusion/i )
    || ( $mckutils::query{'CLIENT'} =~ /coldfusion/i ) ) {
    my @array = %mckutils::query;
    %input = &miscutils::output_cold_fusion(@array);
  } else {
    %input = %mckutils::query;
  }

  if ( exists $mckutils::result{'refnumber'} ) {
    $input{'refnumber'} = $mckutils::result{'refnumber'};
  }

  foreach my $key ( keys %input ) {
    if ( ( $key =~ /^customname(\d+)/ )
      && ( $input{$key} ne "" )
      && ( $input{"customvalue$1"} ne "" ) ) {
      $input{ $input{$key} } = $input{"customvalue$1"};
    }
  }
  if ( $mckutils::feature{'suppress_custom'} == 1 ) {
    foreach my $key ( keys %input ) {
      if ( $key =~ /^customname(\d+)|customvalue(\d+)/ ) {
        delete $input{$key};
      }
    }
  }

  if ( exists $input{'auth-code'} ) {
    $input{'auth-code'} = substr( $input{'auth-code'}, 0, 6 );
  }

  if ( exists $input{'auth_code'} ) {
    $input{'auth_code'} = substr( $input{'auth_code'}, 0, 6 );
  }

  # create array of parameters we don't want to send
  my @deleteParameters = ( 'year-exp', 'year_exp', 'month-exp', 'month_exp', 'max', 'pass', 'attempts', 'User-Agent' );
  push @deleteParameters, ( 'acct_code3', 'acct_code4', $result{'FinalStatus'} . '-link', $result{'FinalStatus'} . '_link' );
  push @deleteParameters, ( 'card-number', 'card_number', 'card-cvv', 'card_cvv', 'magstripe', 'magensacc', 'mpgiftcard', 'mpcvv' );

  # delete the parameters we don't want to send back
  foreach my $parameter (@deleteParameters) {
    if ( exists $input{$parameter} ) {
      delete $input{$parameter};
    }
  }

  my $postLink = undef;
  if ( $mckutils::result{'FinalStatus'} eq "fraud" ) {
    $postLink = $mckutils::query{'badcard-link'};
  } else {
    $postLink = $mckutils::query{"$mckutils::result{'FinalStatus'}-link"};
  }
  $postLink =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\|]/x/g;

  my $xmlPairs  = undef;
  my $jsonPairs = undef;

  # if we are responding with XML, get the "pairs" string as XML
  if ( $mckutils::feature{'response_format'} eq "XML" ) {
    require xmlparse2;    # done this way to prevent subroutine redefined errors
    $xmlparse2::version = 2;
    my @array = %input;
    my $message .= &xmlparse2::output_xml( '1', @array );
    $xmlPairs = &xmlparse2::xml_wrapper( $message, $mckutils::query{'publisher-name'} );
  } else {

    # convert parameters to new payscreens if that's where they came from
    if ( $input{'customname99999999'} eq 'payscreensVersion'
      && $input{'customvalue99999999'} eq '2'
      && $mckutils::feature{'forceLegacy'} eq "" ) {
      delete $input{'customname99999999'};
      delete $input{'customvalue99999999'};

      # do this so we send back a masked card number in pt_card_number
      $input{'card-number'} = $input{'receiptcc'};

      my $api = new PlugNPay::API('payscreens');
      %input = %{ $api->convertLegacyParameters( \%input ) };

      # delete empty values as they are read only if passed
      foreach my $parameter ( keys %input ) {
        if ( $input{$parameter} eq '' ) {
          delete $input{$parameter};
        }
      }

      PlugNPay::DBConnection::cleanup();
    }

    # url encode the parameters we do want to send back
    my %encodedInput;
    foreach my $parameter ( keys %input ) {
      $encodedInput{ uri_escape($parameter) } =
        uri_escape( $input{$parameter} );
    }

    # generate QueryString in case we need to post back to payscreens
    $pairs =
      join( '&', map { $_ . '=' . $encodedInput{$_} } keys %encodedInput );

    # generate JSON query string if the response format is JSON
    if ( $mckutils::feature{'response_format'} eq 'JSON' ) {
      $jsonPairs = JSON::XS::encode_json( \%encodedInput );
    }
  }

  # get our server name so we can see if we are posting back to ourselves.
  my $serverName = $ENV{'SERVER_NAME'};

  # create a copy of the link we are posting to so we can strip out everything but the domain name
  my $postLinkCheck = $postLink;
  $postLinkCheck =~ s/https?:\/\/(.*?)[:\/].*/$1/;

  # if we are not posting back to ourselves, use the xml pairs or json pairs if they exist, default to normal query string
  if ( lc $serverName ne lc $postLinkCheck ) {
    $pairs = $xmlPairs || $jsonPairs || $pairs;
  }

  ##  DCP 20101020 Proxy through apps1
  my (%result1);
  my $rl = new PlugNPay::ResponseLink( $mckutils::query{'merchant'}, $postLink, $pairs, 'post', 'meta' );
  if ( $ENV{'PNP_RESPONSELINK_DIRECT'} eq 'TRUE' ) {
    $rl->setRequestMode('DIRECT');
  }
  $rl->doRequest();
  my $response        = $rl->getResponseContent;
  my %headers         = $rl->getResponseHeaders;
  my %responseAPIData = $rl->getResponseAPIData;

  my $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $mckutils::query{'amountcharged'} );
  if ( $responseAPIData{'action'} eq "postauth" ) {
    ## Do postauth
    %result1 = &miscutils::sendmserver(
      $mckutils::query{'merchant'}, "postauth",                     'accttype', $mckutils::query{'accttype'}, 'acct_code', $mckutils::query{'acct_code'},
      'acct_code4',                 $mckutils::query{'acct_code4'}, 'order-id', $mckutils::orderID,           'amount',    $price
    );

    $mckutils::result{'postauthstatus'} = $result1{'FinalStatus'};
  } elsif ( $responseAPIData{'action'} eq "void" ) {
    ## Do Void
    if ( ( $mckutils::trans_type eq "auth" )
      && ( $mckutils::proc_type eq "authcapture" ) ) {
      %result1 = &miscutils::sendmserver(
        $mckutils::query{'merchant'},
        "return", 'acct_code', $mckutils::query{'acct_code'},
        'acct_code4', "$mckutils::query{'acct_code4'}",
        'amount', "$price", 'order-id', "$mckutils::orderID"
      );
    } else {
      %result1 = &miscutils::sendmserver(
        $mckutils::query{'merchant'},
        "void", 'acct_code', $mckutils::query{'acct_code'},
        'acct_code4', "$mckutils::query{'acct_code4'}",
        'txn-type', 'marked', 'amount', "$price", 'order-id', "$mckutils::orderID"
      );
    }
    $mckutils::result{'voidstatus'} = $result1{'FinalStatus'};
  }

  if ( $mckutils::query{'client'} =~ /^(ipadkiosk)$/i ) {
    $mckutils::result{'linkstatus'} = "";
    &hiddeniframe();
    exit;
  }

  &output_generic( $response, %headers );
}

sub gotoprivatecgi {
  my $pairs = "";

  $mckutils::query{'success'}   = $mckutils::success;
  $mckutils::query{'MErrMsg'}   = $result{'MErrMsg'};
  $mckutils::query{'resp-code'} = $result{'resp-code'};
  $mckutils::query{'id'}        = $mckutils::orderID;
  $mckutils::query{'badcard'}   = 1;

  foreach my $key ( keys %mckutils::query ) {
    if ( $key =~ /^(card-cvv|card_cvv)$/ ) {
      next;
    }
    $_ = $mckutils::query{$key};
    $_ =~ s/([^a-zA-Z0-9_\-.])/uc sprintf("%%%02x",ord($1))/eg;

    if ( $pairs ne "" ) {
      $pairs = "$pairs\&$key=$_";
    } else {
      $pairs = "$key=$_";
    }
  }

  $_ = $mckutils::query{"$result{'FinalStatus'}-link"};
  s/[^a-zA-Z0-9_\.\/ \@:\-]/x/g;

  if ( ( $mckutils::socketflag == 1 )
    || ( $mckutils::feature{'socketflag'} == 1 ) ) {
    &miscutils::formpostpl( $_, $pairs );
  } else {
    &miscutils::formpost( $_, $pairs );
  }
}

sub ups_track {
  my ( $i, $a, $b, $c, $check, $position );
  my $ups_shipper_no = $mckutils::query{'ups-shipper-no'};

  my $ups_service_code = $mckutils::query{'ups-service-code'};
  my $ups_invoice_no   = $mckutils::query{'invoice-no'};
  my $ups_partial      = $ups_shipper_no . $ups_service_code . $ups_invoice_no;

  $_ = $ups_partial;
  tr/WXE/456/;

  for ( $i = 0 ; $i <= 15 ; $i++ ) {
    $a = $a + substr( $_, $i,     1 );
    $b = $b + substr( $_, $i + 1, 1 );
    $i++;
  }

  $a        = ( $b * 2 ) + $a;
  $b        = $a / 10;
  $position = rindex( $b, '.' );
  if ( $position > 0 ) {
    $c = length($b) - $position;
    $b = substr( $b, 0, $c );
  }
  $b = ( ( $b + 1 ) * 10 ) - $a;
  if ( $b == 10 ) {
    $check = 0;
  } else {
    $check = $b;
  }
  $mckutils::query{'ups-track'} = "1Z $ups_shipper_no $ups_service_code $ups_invoice_no $check";
}

sub checkfraud {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my ($ipaddr2);
  if ( ( $ENV{'SCRIPT_NAME'} =~ /pnpremote|systech|xml/ ) ) {
    $ipaddr2 = $mckutils::query{'ipaddress'};
    $mckutils::query{'IPaddress'} = $mckutils::query{'ipaddress'};
  } else {
    $ipaddr2 = $remote_ip;
  }

  if ( ( $mckutils::query{'paymethod'} !~ /^(invoice|web900|onlinecheck|seqr)$/ )
    && ( $mckutils::query{'accttype'} eq "credit" )
    && ( $mckutils::query{'card-number'} ne "" )
    && ( $mckutils::fconfig{'negative'} ne "skip" ) ) {
    my $cardnumber = $mckutils::query{'card-number'};
    my $md5        = new MD5;
    $md5->add("$cardnumber");
    my $cardnumber_md5 = $md5->hexdigest();

    my $dbh_fraud   = &miscutils::dbhconnect("pnpmisc");
    my $qstr        = "select enccardnumber,trans_date,card_number,username,descr from fraud where enccardnumber=? ";
    my @placeholder = ("$cardnumber_md5");
    if ( $mckutils::fconfig{'negative'} eq "self" ) {
      $qstr .= "and username=? ";
      push( @placeholder, "$mckutils::query{'publisher-name'}" );
    }
    my $sth_fraud = $dbh_fraud->prepare(qq{$qstr});
    $sth_fraud->execute(@placeholder);
    my ( $test, $orgdate, $fraudnumber, $username, $reason ) = $sth_fraud->fetchrow;
    $sth_fraud->finish;
    $dbh_fraud->disconnect;

    if ( $test ne "" ) {
      my $fcardnumber = substr( $mckutils::query{'card-number'}, 0, 4 ) . '**' . substr( $mckutils::query{'card-number'}, length($cardnumber) - 2, 2 );
      $result{'FraudMsg'}  = "Card Number: $fraudnumber:$fcardnumber, submitted on $orgdate was found in the Master Fraud Database";
      $result{'MErrMsg'}   = "We are sorry, but this credit card number has been flagged and can not be used to access this service.";
      $result{'resp-code'} = "P66";
      return "failure";
    }
  }

  my @fraudip = ( '194.133.122.44', '139.92.34.', '199.203.109.251', '202.146.244.', '202.146.253.', '202.152.13.', '212.189.236.', '141.165.1.62' );
  my ($var);
  foreach $var (@fraudip) {
    if ( $mckutils::query{'IPaddress'} =~ $var ) {
      $result{'FraudMsg'}  = "IP Address: $mckutils::query{'IPaddress'}, has been flagged as a possible source of fraud.";
      $result{'MErrMsg'}   = "We are sorry, but this charge can not be processed at this time.";
      $result{'resp-code'} = "P67";
      my @array = %mckutils::query;
      &fraud_database(@array);
      &support_email();
      return "failure";
    }
  }

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  my $datestr2 = sprintf( "%04d%02d%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min );
  my $datestr3 = time();

  ###

  if ( $ipaddr2 ne "" ) {
    my ( $test, $fraudcount );
    my $dbh = &miscutils::dbhconnect("fraudtrack");

    my $sth = $dbh->prepare(
      qq{
        insert into freq_log
        (ipaddr,rawtime,trans_time)
        values (?,?,?)
    }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
    $sth->execute( "$ipaddr2", "$datestr3", "$datestr2" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
    $sth->finish;

    my $timetest = $datestr3 - 3600;

    $sth = $dbh->prepare(
      qq{
        select ipaddr
        from freq_log
        where ipaddr=? and rawtime>?
    }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
    $sth->execute( "$ipaddr2", "$timetest" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr" );
    $sth->bind_columns( undef, \($test) );

    while ( $sth->fetch ) {
      if ( $test !~ /0\.0\.0\.0/ ) {
        $fraudcount++;
      }
    }
    $sth->finish;

    $dbh->disconnect;

    if ( ( $fraudcount >= 5 )
      && ( $ENV{'SCRIPT_NAME'} !~ /(smps\.cgi|virtualterm\.cgi)$/ ) ) {
      $result{'MErrMsg'}   = "Sorry, maximum number of attempts has been exceeded.";
      $result{'resp-code'} = "P65";
      return "failure";
    } else {
      return "success";
    }
  }
}

sub planetpayment {
  my ( $html, $confirm );
  my (%input) = ( %mckutils::query, %mckutils::result );

  print header( -type => 'text/html' );    #### DCP 20100712

  if ( $input{'dcctype'} eq "twopass" ) {
    my $path_dcc     = "$mckutils::path_web/dcc/dcc_popup_twopass.html";
    my $path_dcc_cgi = "https://" . $ENV{'SERVER_NAME'} . $ENV{'SCRIPT_NAME'};
    $html = "<form method=\"post\" action=\"$path_dcc_cgi\" name=\"DCC\">";
    foreach my $key ( sort keys %input ) {
      if ( $key =~ /^(dccmsg|orderID|mode|publisher-name)$/ ) {
        next;
      }
      $html .= "<input type=\"hidden\" name=\"$key\" value=\"$input{$key}\">\n";
    }
    $html .= "<input type=\"hidden\" name=\"dccpass\" value=\"1\">\n";
    $html .= $input{'dccmsg'};

    $path_dcc =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    &sysutils::filelog( "read", "$path_dcc" );
    open( HTML, "$path_dcc" );
    while (<HTML>) {
      if ( $_ =~ /\[PNP_PAIRS\]/ ) {
        s/\[PNP_PAIRS\]/$html/;
      }
      if ( $_ =~ /\[PNP_CONFIRM\]/ ) {
        s/\[PNP_CONFIRM\]/$confirm/;
      }
      print "$_";
    }

  } else {
    my $path_dcc     = "$mckutils::path_web/dcc/dcc_popup.html";
    my $path_dcc_cgi = "https://$ENV{'SERVER_NAME'}/dcc/dcc_optout.cgi";
    $html = "<form method=\"post\" action=\"$path_dcc_cgi\" name=\"DCC\" target=\"Payment_Main\">";
    foreach my $key ( sort keys %input ) {
      if ( $key =~ /^(dccmsg|orderID|mode|publisher-name)$/ ) {
        next;
      }
      $html .= "<input type=\"hidden\" name=\"$key\" value=\"$input{$key}\">\n";
    }
    $html .= "<input type=\"hidden\" name=\"dccpass\" value=\"1\">\n";
    $html .= $input{'dccmsg'};

    $path_dcc =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    &sysutils::filelog( "read", "$path_dcc" );
    open( HTML, "$path_dcc" );
    while (<HTML>) {
      if ( $_ =~ /\[PNP_PAIRS\]/ ) {
        s/\[PNP_PAIRS\]/$html/;
      }
      if ( $_ =~ /\[PNP_CONFIRM\]/ ) {
        s/\[PNP_CONFIRM\]/$confirm/;
      }
      print "$_";
    }

  }

  exit;
}

sub sftcrtpost {
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  my $now = sprintf( "%04d%02d%02d %02d\:%02d\:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
  open( DEBUGFILE, ">>/home/p/pay1/database/debug/softcart_still_in_use.txt" );
  print DEBUGFILE "DATE:$now, UN:$mckutils::query{'publisher-name'}, PID:$$\n";
  close(DEBUGFILE);

  #use Datalog
  my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
  $logger->log(
    { 'DATE' => $now,
      'UN'   => $mckutils::query{'publisher-name'},
      'PID'  => $$
    }
  );

  my ( %input, $pairs );
  $input{'cardname'}             = $mckutils::query{'card-name'};
  $input{'CCType'}               = $mckutils::query{'card-type'};
  $input{'ShipName'}             = $mckutils::query{'shipname'};
  $input{'ShipAddress1'}         = $mckutils::query{'address1'};
  $input{'ShipAddress2'}         = $mckutils::query{'address2'};
  $input{'ShipCity'}             = $mckutils::query{'city'};
  $input{'ShipState'}            = $mckutils::query{'state'};
  $input{'ShipZIP'}              = $mckutils::query{'zip'};
  $input{'ShipCountry'}          = $mckutils::query{'country'};
  $input{'DayPhone'}             = $mckutils::query{'phone'};
  $input{'NitePhone'}            = $mckutils::query{'fax'};
  $input{'Email_addr'}           = $mckutils::query{'email'};
  $input{'Name'}                 = $mckutils::query{'card-name'};
  $input{'Address1'}             = $mckutils::query{'card-address1'};
  $input{'Address2'}             = $mckutils::query{'card-address2'};
  $input{'City'}                 = $mckutils::query{'card-city'};
  $input{'State'}                = $mckutils::query{'card-state'};
  $input{'ZIP'}                  = $mckutils::query{'card-zip'};
  $input{'Country'}              = $mckutils::query{'card-country'};
  $input{'ShippingInstructions'} = $mckutils::query{'comments'};
  $input{'TotalShipping'}        = $mckutils::query{'shipping'};
  $input{'TotalTax'}             = $mckutils::query{'tax'};

  $input{'cc_name'}         = $mckutils::query{'card-name'};
  $input{'bill_to_name'}    = $mckutils::query{'card-name'};
  $input{'bill_to_street1'} = $mckutils::query{'card-address1'};
  $input{'bill_to_street2'} = $mckutils::query{'card-address2'};
  $input{'bill_to_city'}    = $mckutils::query{'card-city'};
  $input{'bill_to_state'}   = $mckutils::query{'card-state'};
  $input{'bill_to_zip'}     = $mckutils::query{'card-zip'};
  $input{'bill_to_country'} = $mckutils::query{'card-country'};
  $input{'bill_to_phone'}   = $mckutils::query{'phone'};
  $input{'bill_to_email'}   = $mckutils::query{'email'};

  my ($key);
  foreach $key ( keys %input ) {
    $_ = $input{$key};
    s/(\W)/'%' . unpack("H2",$1)/ge;
    if ( $pairs ne "" ) {
      $pairs = "$pairs\&$key=$_";
    } else {
      $pairs = "$key=$_";
    }
  }

  $mckutils::query{'success-link'} = $mckutils::query{'path-softcart'} . $mckutils::query{'path-postorder'} . "?T";
  if ( $mckutils::query{'sessionid'} ne "" ) {
    $_ = $mckutils::query{'success-link'} . "\+" . $mckutils::query{'storename'} . "\+" . $mckutils::query{'sessionid'};
  } else {
    $_ = $mckutils::query{'success-link'} . "\+" . $mckutils::query{'storename'} . "\+" . $mckutils::query{'order-id'};
  }

  if ( ( $mckutils::socketflag == 1 )
    || ( $mckutils::feature{'socketflag'} == 1 ) ) {
    &miscutils::formpostpl( $_, $pairs );
  } else {
    &miscutils::formpost( $_, $pairs );
  }
  exit;

}

sub avs_void {
  my ($processor) = @_;

  ###  NOTE:  Any non-alpha AVS response is converted to a 'U'.
  my $amount = $mckutils::query{'card-amount'};
  my $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $amount );
  my ( $avs_void_flag, $i3, $avs_level, $cardtype );
  my $avs = substr( $result{'avs-code'}, 0, 3 );
  $avs =~ s/[^A-Z]//g;
  $avs = substr( $avs, -1, 1 );

  if ( $avs eq "" ) {
    $avs = "U";

    #&support_email('other');
  }

  my $app_level = $mckutils::query{'app-level'};

  $cardtype = &miscutils::cardtype( $mckutils::query{'card-number'} );

  if ( ( ( $app_level < 0 ) || ( $app_level eq "" ) )
    && ( $mckutils::feature{'AVS'} ne "" ) ) {    #set avs response codes to allow
    my ($avsmatchflag);
    my @array = split( /\:/, $mckutils::feature{'AVS'} );
    foreach my $entry (@array) {
      last if ( $avsmatchflag == 1 );
      my ( $ctype, @allowed ) = split( /\|/, $entry );
      if ( ( $ctype eq $cardtype ) || ( $ctype eq "ALL" ) ) {
        foreach my $var (@allowed) {
          if ( $var eq $avs ) {
            $avsmatchflag = 1;
            last;
          }
        }
      }
    }
    if ( $avsmatchflag != 1 ) {
      $avs_void_flag = 1;
    }
  } elsif ( ( $app_level < 0 ) && ( $mckutils::feature{'AVSR'} ne "" ) ) {    #set avs reponse codes to reject
    my ($avsmatchflag);
    my @array = split( /\:/, $mckutils::feature{'AVSR'} );
    foreach my $entry (@array) {
      last if ( $avsmatchflag == 1 );
      my ( $ctype, @allowed ) = split( /\|/, $entry );
      if ( ( $ctype eq $cardtype ) || ( $ctype eq "ALL" ) ) {
        foreach my $var (@allowed) {
          if ( $var eq $avs ) {
            $avs_void_flag = 1;
            last;
          }
        }
      }
    }
  } else {

    if ( ( $app_level eq "7" ) && ( $mckutils::result{'cvvresp'} eq "M" ) ) {
      return;
    }

    #print "AVS:$avs:APP:$app_level:<br>\n";

    if ( $avs =~ /^(Y|X|D|M|F)$/ ) {
      $avs_level = 5;
    } elsif ( $avs =~ /^(A|B)$/ ) {
      $avs_level = 4;
    } elsif ( $avs =~ /^(W|Z|P)$/ ) {
      $avs_level = 3;
    } elsif ( $avs =~ /^(U|G|C)$/ ) {
      $avs_level = 2;
    } elsif ( $avs =~ /^(S|R)$/ ) {
      $avs_level = 1;
    } else {
      $avs_level = 0;
    }

    if ( $app_level eq "6" ) {
      if ( ( $avs_level !~ /5|2|1/ ) ) {
        $avs_void_flag = 1;
      }
    } elsif ( $avs_level < $app_level ) {
      $avs_void_flag = 1;
    }
  }
  if (
    ( $avs_void_flag == 1 )
    && ( ( $mckutils::feature{'avshold'} == 1 )
      || ( $mckutils::fconfig{'avshold'} == 1 ) )
    ) {
    $mckutils::query{'fraudholdstatus'} = "hold";
    $mckutils::query{'fraudholdmsg'}    = "AVS Failure:$avs";
  } elsif ( $avs_void_flag == 1 ) {
    my $scriptname = $ENV{'SCRIPT_NAME'};
    $scriptname =~ /.*\/(.*?\.cgi)/;
    $scriptname = $1;
    $mckutils::query{'acct_code4'} = "AVS failure.:$scriptname:$mckutils::query{'IPaddress'}";

    my ( $i, %result1, @pairs, $operation );

    if ( ( $mckutils::trans_type eq "auth" )
      && ( $mckutils::proc_type eq "authcapture" ) ) {
      @pairs =
        ( $mckutils::query{'publisher-name'}, "return", 'acct_code', $mckutils::query{'acct_code'}, 'acct_code4', "$mckutils::query{'acct_code4'}", 'amount', "$price", 'order-id', "$mckutils::orderID" );

      $operation = "return";
    } else {
      @pairs = (
        $mckutils::query{'publisher-name'},
        "void", 'acct_code', $mckutils::query{'acct_code'},
        'acct_code4', "$mckutils::query{'acct_code4'}",
        'txn-type', 'marked', 'amount', "$price", 'order-id', "$mckutils::orderID"
      );

      $operation = "void";
    }

    my $finalstatusTest = "";
    for ( $i = 1 ; $i <= 5 ; $i++ ) {
      %result1 = &miscutils::sendmserver(@pairs);
      last if ( $result1{'FinalStatus'} eq "success" );
      my ( undef, $trans_date, $timestr ) = &miscutils::gendatetime();
      if ( $operation eq "void" ) {
        $finalstatusTest = &checkTranStatus( $mckutils::query{'publisher-name'}, $trans_date, $mckutils::orderID, $operation );
        if ( $finalstatusTest ne "" ) {
          last;
        }
      } else {
        &miscutils::mysleep(1);
      }
    }
    if ( ( $result1{'FinalStatus'} eq "success" )
      || ( $finalstatusTest ne "" ) ) {
      $result{'FinalStatus'} = "badcard";
      $result{'MErrMsg'}     = "Sorry, the billing address you entered does not match the address on record for this credit card or your address information is unavailable for verification.";
      $result{'resp-code'}   = "P01";
    } else {
      $mckutils::query{'acct_code4'} = "AVS void failure.:$scriptname:$mckutils::query{'IPaddress'}";
      $result{'MErrMsg'}             = "AVS Check failed, Automatic Void Failed.";
    }
  }
}

sub void {
  if ( ( $mckutils::feature{'cvvhold'} == 1 )
    || ( $mckutils::fconfig{'cvvhold'} == 1 ) ) {
    $mckutils::query{'fraudholdstatus'} = "hold";
    $mckutils::query{'fraudholdmsg'}    = "CVV2 Failure:$result{'cvvresp'}";
    return;
  }

  my ( $i, $voidstatus, %result1, $operation );
  my $amount = $mckutils::query{'card-amount'};
  my $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $amount );

  if ( ( $mckutils::trans_type eq "auth" )
    && ( $mckutils::proc_type eq "authcapture" ) ) {
    $operation = 'return';
  } else {
    $operation = 'void';
  }

  my $finalstatusTest = "";
  for ( $i = 1 ; $i <= 5 ; $i++ ) {
    %result1 = &miscutils::sendmserver(
      $mckutils::query{'publisher-name'},
      $operation, 'acct_code', $mckutils::query{'acct_code'},
      'acct_code4', "$mckutils::query{'acct_code4'}",
      'txn-type', 'marked', 'amount', "$price", 'order-id', "$mckutils::orderID"
    );

    last if ( $result1{'FinalStatus'} eq "success" );
    my ( undef, $trans_date, $timestr ) = &miscutils::gendatetime();
    if ( $operation eq "void" ) {
      $finalstatusTest = &checkTranStatus( $mckutils::query{'publisher-name'}, $trans_date, $mckutils::orderID, $operation );
      if ( $finalstatusTest ne "" ) {
        last;
      }
    } else {
      &miscutils::mysleep(1);
    }
  }

  if ( ( $result1{'FinalStatus'} eq "success" )
    || ( $finalstatusTest ne "" ) ) {
    $result{'aux-msg'}     = $result1{'aux-msg'};
    $result{'MStatus'}     = "failure";
    $result{'FinalStatus'} = "badcard";
    $mckutils::success     = "no";
    $voidstatus            = "success";
  } else {
    my $time = gmtime(time);
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
    my $mo = sprintf( "%02d", $mon + 1 );
    &sysutils::filelog( "append", ">>/home/pay1/database/debug/void_debug$mo.txt" );
    open( VOID, ">>/home/p/pay1/database/debug/void_debug$mo.txt" );
    print VOID "$time, ";
    print VOID "$mckutils::query{'publisher-name'}\t$mckutils::orderID\t$price\t$mckutils::query{'acct_code'}\t$mckutils::query{'acct_code4'}, ";
    foreach my $key ( sort keys %result1 ) {
      print VOID "K:$key:$result1{$key}, ";
    }
    print VOID "\n";
    close(VOID);
  }
  return $voidstatus;
}

sub checkTranStatus {
  my ( $username, $trans_date, $orderid, $operation ) = @_;

  my $qstr = "select finalstatus ";
  $qstr .= "from trans_log FORCE INDEX(PRIMARY) ";
  $qstr .= "where orderid=? ";
  $qstr .= "and trans_date=? ";
  $qstr .= "and username=? ";
  $qstr .= "and operation=? ";

  my $dbh = &miscutils::dbhconnect( "pnpdata", "", "$mckutils::query{'publisher-name'}" );    ## Trans_Log
  my $sth = $dbh->prepare(qq{$qstr})
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %remote::query );
  $sth->execute( $orderid, $trans_date, $username, $operation )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %remote::query );
  my ($finalstatus) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  return $finalstatus;
}

sub support_email {
  my ($reason) = @_;
  if ( ( $mckutils::result{'MErrMsg'} =~ /Amount less than or equal to 0.00/i )
    || ( $mckutils::result{'MErrMsg'} =~ /Expiration/i )
    || ( $mckutils::result{'MErrMsg'} =~ /Missing or empty mandatory field/ )
    || ( $mckutils::result{'MErrMsg'} =~ /not configured to perform the requested/i )
    || ( $mckutils::result{'MErrMsg'} =~ /You have a pending transaction/i ) ) {
  } elsif ( $reason eq "other" ) {
    my $emailer = new PlugNPay::Email('legacy');
    $emailer->setGatewayAccount( $mckutils::query{'publisher-name'} );
    $emailer->setFormat('text');
    $emailer->setTo("dprice\@plugnpay.com");
    $emailer->setFrom("mckutils\@plugnpay.com");
    $emailer->setSubject("AVS Check");
    my $email_msg = "PUB: $mckutils::query{'publisher-name'}\n";
    $email_msg .= "AVS: $mckutils::result{'avs-code'}\n";
    $email_msg .= "USERAGENT: $ENV{'HTTP_USER_AGENT'} \n";

    foreach my $key ( sort keys %mckutils::result ) {
      $email_msg .= "$key\=$mckutils::result{$key}\n";
    }
    $emailer->setContent($email_msg);
    $emailer->send();
  } elsif ( $reason eq "fraud" ) {
    my $emailer = new PlugNPay::Email('legacy');
    $emailer->setGatewayAccount( $mckutils::query{'publisher-name'} );
    $emailer->setFormat('text');
    $emailer->setTo("dprice\@plugnpay.com");
    $emailer->setFrom("frauddbase\@plugnpay.com");
    $emailer->setSubject("Fraud Reject");
    my $email_msg = "PUB: $mckutils::query{'publisher-name'}\n";
    $email_msg .= "USERAGENT: $ENV{'HTTP_USER_AGENT'} \n";

    foreach my $key ( sort keys %mckutils::result ) {
      $email_msg .= "$key\=$mckutils::result{$key}\n";
    }
    $emailer->setContent($email_msg);
    $emailer->send();
  }
}

sub hiddeniframe {
  &hyphen_to_underscore();
  my %query = ( %mckutils::query, %mckutils::result );
  delete $query{'auth-code'};
  my $resp = "";

  if ( exists $query{'auth_code'} ) {
    $query{'auth_code'} = substr( $query{'auth_code'}, 0, 6 );
  }

  foreach my $key ( sort keys %query ) {
    if (
      ( $key !~ /^card.number/i )

      #&& ($key !~ /^card.exp/i)
      && ( $key !~ /.link$/i )
      && ( $key !~ /merch.txn/i )
      && ( $key !~ /cust.txn/i )
      && ( $key !~ /month.exp/i )
      && ( $key !~ /year.exp/i )
      && ( $key !~ /card.cvv/i )
      && ( $key !~ /publisher.password/i )
      && ( $key !~ /magstripe/i )
      && ( $key ne "" )
      ) {
      $query{$key} =~ s/(\W)/'%' . unpack("H2",$1)/ge;
      my $k = $key;
      $k =~ s/(\W)/'%' . unpack("H2",$1)/ge;
      if ( $resp ne "" ) {
        $resp .= "\&$k\=$query{$key}";
      } else {
        $resp .= "$k\=$query{$key}";
      }
    }
  }
  $resp .= "\&a=b";
  my $length = length($resp);
  if (0) {
    my $time = gmtime(time);
    open( DATABASE, ">>/home/p/pay1/database/debug/hiddenframe_debug.txt" );
    print DATABASE "TIME:$time, UN:$mckutils::query{'publisher-name'}, SCRIPT:$ENV{'SCRIPT_NAME'}, PID:$$\n";
    print DATABASE "RESP:$resp\n";
    close(DATABASE);
  }

  print header( -type => 'text/html', -Content_length => "$length" );
  print "$resp\n";
  exit;
}

sub transition {
  my (@pairs) = @_;

  # take the last value off the @pairs list, that's the value for alwaysUsePost
  # ugly hack for compatibility
  my $alwaysUsePost = pop @pairs;


  my %allData = ( %mckutils::query, %mckutils::result );

  my %subset = map { $_ => $allData{$_} } @pairs;

  print header( -type => 'text/html' );
  my $html;
  eval {
    $html = PlugNPay::Legacy::MckUtils::Transition::transitionPage( \%subset, \%allData, $alwaysUsePost );
    my $psa                    = new PlugNPay::PayScreens::Assets();
    my $assetsMigratedTemplate = $psa->migrateTemplateAssets(
      { username => $allData{'publisher-name'} || $allData{'publisher_name'} || $allData{'merchant'},
        templateSections => { html => $html }
      }
    );
    $html = $assetsMigratedTemplate->{'html'};
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({ collection => 'transition' });
    $logger->log({
      message => 'Transition page error',
      error => $@,
      username => $allData{'publisher-name'} || $allData{'publisher_name'} || $allData{'merchant'}
    });
  }

  if (!defined $html || $html eq '') {
    my $logger = new PlugNPay::Logging::DataLog({ collection => 'transition' });
    $logger->log({
      message => 'Transition page failure, output is blank',
      error => '$html is blank',
      username => $allData{'publisher-name'} || $allData{'publisher_name'} || $allData{'merchant'}
    });
  }

  print $html;
  exit;
}

sub easycart {
  my (@pairs) = @_;
  my ( $var, %input, $key, $sub_str );
  foreach $var (@pairs) {
    $input{$var} = $mckutils::query{$var};
  }
  foreach $key ( keys %input ) {
    my $name  = $key;
    my $value = $input{$key};
    $name =~ s/([^ \w\-.*])/sprintf("%%%2.2X",ord($1))/ge;
    $value =~ s/([^ \w\-.*])/sprintf("%%%2.2X",ord($1))/ge;
    $name =~ s/ /+/g;
    $value =~ s/ /+/g;
    $sub_str .= "$name=$value";
    $sub_str .= '&';
  }

  print header( -type => 'text/html' );    #### DCP 20100712
  print "<html>\n";
  print "<head>\n";
  print "<title>Secure/Unsecure Transition</title>\n";
  print "<META http-equiv=\"refresh\" content=\"5\; URL=$mckutils::query{'success-link'}\?function=thankyou\&$sub_str\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<font size=+1>\n";
  print "The Secure Portion of your transaction has completed Successfully.\n";
  print "</font>\n";
  print "<p>\n";
  print "<font size=+1>If you experience a delay, please <a href=\"$mckutils::query{'success-link'}\?function=thankyou\&$sub_str\">CLICK HERE.</a></font>\n";
  print "</body>\n";
  print "</html>\n";
  exit;
}

sub fraud_database {
  my (%query1) = @_;
  my ( $trans_date, $trans_time ) = &miscutils::gendatetime_only();
  my $cardnumber = $query1{'cardnumber'};
  my $username   = $query1{'publisher-name'};
  my $reason     = "Potential Fraud";
  my $now        = $trans_date;

  my $md5 = new MD5;
  $md5->add($cardnumber);
  my $cardnumber_md5 = $md5->hexdigest();
  $cardnumber = substr( $cardnumber, 0, 4 ) . '**' . substr( $cardnumber, length($cardnumber) - 2, 2 );

  my $dbh_fraud = &miscutils::dbhconnect("pnpmisc");
  my $sth       = $dbh_fraud->prepare(
    qq{
    select enccardnumber,trans_date,card_number
    from fraud
    where enccardnumber=?
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query1 );
  $sth->execute("$cardnumber_md5")
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query1 );
  my ( $test, $orgdate, $cardnumber1 ) = $sth->fetchrow;
  $sth->finish;

  if ( $test eq "" ) {
    my $sth_insert = $dbh_fraud->prepare(
      qq{
      insert into fraud
      (enccardnumber,username,trans_date,descr,card_number)
      values (?,?,?,?,?)
    }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %query1 );
    $sth_insert->execute( "$cardnumber_md5", "$username", "$now", "$reason", "$cardnumber" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %query1 );
    $sth_insert->finish;

    #$message = $message . "Credit Card Number,$cardnumber, has been successfully added to the Fraud Database.<br>\n";
  }
  $dbh_fraud->disconnect;

  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  my $mo = sprintf( "%02d", $mon + 1 );
  &sysutils::filelog( "append", ">>/home/p/pay1/database/debug/fraud_attempts$mo.txt" );
  open( FRAUDBASE, ">>/home/p/pay1/database/debug/fraud_attempts$mo.txt" );
  my $time = gmtime(time);
  print FRAUDBASE $time . ">";
  print FRAUDBASE $query1{'publisher-name'} . ">";
  print FRAUDBASE $query1{'IPaddress'} . ">";
  print FRAUDBASE $query1{'User-Agent'} . ">";
  print FRAUDBASE $query1{'referrer'} . ">";
  print FRAUDBASE $query1{'card-name'} . ">";
  print FRAUDBASE $query1{'card-address1'} . ">";
  print FRAUDBASE $query1{'card-address2'} . ">";
  print FRAUDBASE $query1{'card-city'} . ">";
  print FRAUDBASE $query1{'card-state'} . ">";
  print FRAUDBASE $query1{'card-zip'} . ">";
  print FRAUDBASE $query1{'card-country'} . ">";
  my $tmpCC = substr( $query1{'card-number'}, 0, 6 ) . ( 'X' x ( length( $query1{'card-number'} ) - 8 ) ) . substr( $query1{'card-number'}, -2 );    # Format: first6, X's, last2
  print FRAUDBASE $tmpCC . ">";
  print FRAUDBASE $query1{'card-exp'} . ">";
  print FRAUDBASE $query1{'card-amount'} . ">";
  print FRAUDBASE $query1{'order-id'} . ">";
  print FRAUDBASE $mckutils::orderID . ">";
  print FRAUDBASE $query1{'success-link'} . ">";
  print FRAUDBASE $query1{'publisher-email'} . ">";
  print FRAUDBASE $query1{'email'} . ">";
  print FRAUDBASE $query1{'phone'} . ">";
  print FRAUDBASE $query1{'name'} . ">";
  print FRAUDBASE $query1{'address1'} . " " . $query1{'address2'} . ">";
  print FRAUDBASE $query1{'city'} . ">";
  print FRAUDBASE $query1{'state'} . ">";
  print FRAUDBASE $query1{'zip'} . ">";
  print FRAUDBASE $result{'avs-code'} . ">";
  print FRAUDBASE $result{'Duplicate'} . ">";
  print FRAUDBASE %mckutils::query . ">\n";
  close(FRAUDBASE);
}

sub final {
  my $problemMessage =
    "There seems to be a problem with your payment. " . "Please\nuse the \"back\" button to verify the information you supplied. " . "If\nyou feel it is correct please call the company for help.\n";
  if ( $mckutils::query{'customname99999999'} eq 'payscreensVersion'
    && $mckutils::query{'customvalue99999999'} eq '2'
    && $mckutils::feature{'forceLegacy'} eq "underscore" ) {
    &mckutils::hyphen_to_underscore();
    $mckutils::query{'convert'} = 'underscores';
  }
  ## Revert card-amount back to original amount submitted
  $mckutils::query{'card-amount'} = $mckutils::submitted_amount;

  if ( $mckutils::query{'client'} =~ /^(hiddeniframe)$/i ) {
    &hiddeniframe();
    exit;
  }

  my $selfHiddenPost = -e "/home/pay1/etc/mckutils/self_hidden_post" ? 1 : 0;

  # Delete magensa swipe data from the db
  if ( $mckutils::query{'magensacc'} ne "" ) {
    my $cc = new PlugNPay::CreditCard();
    my $ksn = $cc->getKSNFromSwipeData( $mckutils::query{'magensacc'}, $mckutils::query{'swipedevice'} );
    if ( $cc->magensaSwipeExists($ksn) ) {
      $cc->deleteMagensaSwipeData($ksn);
    }
  }

  if ( $mckutils::result{'FinalStatus'} eq "success" ) {
    if ( ( ( $mckutils::query{'client'} eq "planetpay" ) || ( $mckutils::query{'enabledcc'} ne "" ) )
      && ( $mckutils::query{'dccpass'} != 1 ) ) {
      &planetpayment();
    }
    if ( $mckutils::query{'client'} eq "softcart" ) {
      &sftcrtpost();
    } elsif ( $mckutils::query{'client'} eq "payperview" ) {
      &payperview();
    } elsif ( $mckutils::query{'client'} =~ /^Qstore$/i ) {
      my @qstore = (
        'card-name',          'card-address1', 'card-address2', 'card-city', 'card-state', 'card-province', 'card-zip', 'card-country',
        'cust_bill_comments', 'card-type',     'FinalStatus',   'auth-code', 'MErrMsg',    'avs-code',      'orderID',  'intheq_session_id'
      );
      &transition(@qstore);
    } elsif ( $mckutils::query{'client'} eq "dansie" ) {
      ## DCP 20050323
      if ( $mckutils::feature{'transition'} ) {
        &transition();
      } else {
        &gotolocation();
      }
    } elsif ( $mckutils::query{'success-link'} =~ /\.(htm|shtml)/ ) {
      if ( $mckutils::feature{'transition'} == 1 ) {
        &transition();
      } else {
        &gotolocation();
      }
    } elsif ( $mckutils::query{'success-link'} eq "" ) {
      if ( $ENV{'HTTP_USER_AGENT'} =~ /UP.Browser/ ) {
        &genwml( "", "Thank you for your order." );
      } elsif ( ( $mckutils::query{'receipt_type'} =~ /simple|itemized|pos_itemized|pos_simple/i )
        || ( $mckutils::query{'receipt-type'} =~ /simple|itemized|pos_itemized|pos_simple/i ) ) {

        # try to generate receipt
        my $receipt = &receipt();
        if ( !defined $receipt || $receipt eq '' ) {

          # TODO refactor so these get rendered by the new PlugNPay::Legacy::MckUtils::Receipt receipt code.
          if ( ( $mckutils::query{'receipt_type'} =~ /^pos_/i )
            || ( $mckutils::query{'receipt-type'} =~ /^pos_/i ) ) {
            $receipt = pos_template();
          } else {
            $receipt = thankyou_template();
          }

          # regenerate receipt with template content
          $receipt = receipt( { templateContent => $receipt } );

          my $psa                    = new PlugNPay::PayScreens::Assets();
          my $assetsMigratedTemplate = $psa->migrateTemplateAssets(
            { username => $mckutils::query{'publisher-name'} || $mckutils::query{'publisher_name'} || $mckutils::query{'merchant'},
              templateSections => { template => $receipt }
            }
          );
          $receipt = $assetsMigratedTemplate->{'template'};

          # display filled in template to user
          &genhtml( "", "$receipt" );
        } else {
          my $psa                    = new PlugNPay::PayScreens::Assets();
          my $assetsMigratedTemplate = $psa->migrateTemplateAssets(
            { username => $mckutils::query{'publisher-name'} || $mckutils::query{'publisher_name'} || $mckutils::query{'merchant'},
              templateSections => { template => $receipt }
            }
          );
          $receipt = $assetsMigratedTemplate->{'template'};

          displayHtml($receipt);
        }
      } else {
        if ( $mckutils::query{'close_on_success'} eq "yes" ) {
          &genhtml( undef, "Thank you for your order.", 'yes' );
        } else {
          &genhtml( undef, "Thank you for your order." );
        }
      }
    } else {
      return transitionOrGoToCgi(
        { query         => \%mckutils::query,
          result        => \%mckutils::result,
          transition    => $mckutils::feature{'transition'},
          statusToCheck => 'success',
          successValue  => $mckutils::success
        }
      );
    }
  } elsif ( ( $mckutils::result{'FinalStatus'} eq "badcard" )
    || ( $mckutils::result{'FinalStatus'} eq "fraud" ) ) {
    if (
      ( $mckutils::query{'client'} =~ /rectrac|quikstor/ )
      && ( ( $mckutils::query{'badcard-link'} =~ /payment\/pay.cgi$/ )
        || ( $mckutils::query{'badcard-link'} eq "" ) )
      ) {
      my $message = "Sorry, your payment request can not be processed at this time for the following reason:<p>\n $mckutils::result{'MErrMsg'}<p>\n";
      $message .= "Please close window, fix error and resubmit transaction.";
      &genhtml( undef, $message );
    } elsif ( $mckutils::query{'badcard-link'} =~ /\.(htm|shtml)/ ) {
      &gotolocation();
    } elsif ( $mckutils::query{'badcard-link'} eq "" ) {
      if ( ( $mckutils::query{'receipt_type'} =~ /simple|itemized|pos_itemized|pos_simple/i )
        || ( $mckutils::query{'receipt-type'} =~ /simple|itemized|pos_itemized|pos_simple/i ) ) {
        my $receipt = &receipt();
        if ( $receipt eq "" ) {
          $receipt = $problemMessage;
        }
        &displayHtml($receipt);
      } else {
        if ( $mckutils::query{'client'} =~ /^(mobile)$/ ) {
          &genmobile($problemMessage);
        } else {
          &genhtml( undef, $problemMessage );
        }
      }
    } else {
      return transitionOrGoToCgi(
        { query          => \%mckutils::query,
          result         => \%mckutils::result,
          transition     => $mckutils::feature{'transition'},
          statusToCheck  => 'badcard',
          successValue   => $mckutils::success,
          selfHiddenPost => $selfHiddenPost
        }
      );
    }
  } else {
    my $problemReasonMessage = "Sorry, your payment request can not be processed at this time for the following reason:\n $mckutils::result{'MErrMsg'}\n";
    if ( $mckutils::result{'resp-code'} eq 'P112' ) {
      &genhtml( undef, $problemReasonMessage );
    } elsif ( $mckutils::query{'problem-link'} =~ /\.htm/ ) {
      &gotolocation();
    } elsif ( $mckutils::query{'problem-link'} eq "" ) {
      if ( ( $mckutils::query{'receipt_type'} =~ /simple|itemized|pos_itemized|pos_simple/i )
        || ( $mckutils::query{'receipt-type'} =~ /simple|itemized|pos_itemized|pos_simple/i ) ) {
        my $receipt = &receipt();
        if ( $receipt eq "" ) {
          $receipt = $problemMessage;
        }
        &displayHtml($receipt);
      } else {
        if ( $mckutils::query{'client'} =~ /^(mobile)$/ ) {
          &genmobile($problemReasonMessage);
        } else {
          &genhtml( undef, $problemReasonMessage );
        }
      }
    } else {
      return transitionOrGoToCgi(
        { query          => \%mckutils::query,
          result         => \%mckutils::result,
          transition     => $mckutils::feature{'transition'},
          statusToCheck  => 'problem',
          successValue   => $mckutils::success,
          selfHiddenPost => $selfHiddenPost
        }
      );
    }
  }

  ### DWW good enough for now maybe move into email?
  ### DCP Loyalty Program  - add to presignup table.
  if ( ( $mckutils::feature{'loyaltyprog'} == 1 )
    && ( $mckutils::query{'loyaltysubscribe'} == 1 ) ) {
    require ewallet;
    my @array   = %mckutils::query;
    my $payment = ewallet->new(@array);
    my %result  = $payment->preregister_loyalty("auth");
  }

}

sub transitionOrGoToCgi {
  my $input = shift;

  my $query          = $input->{'query'};
  my $result         = $input->{'result'};
  my $transition     = $input->{'transition'};
  my $statusToCheck  = $input->{'statusToCheck'};
  my $successValue   = $input->{'successValue'};
  my $selfHiddenPost = $input->{'selfHiddenPost'};
  my $alwaysUsePost  = 0;

  my $statusLink = sprintf( '%s-link', $statusToCheck );

  my $gatewayRedirect = isSelfPost( $query->{$statusLink} );

  if ( $transition == 1 || ( $gatewayRedirect && !$selfHiddenPost ) ) {
    $query->{'success'} = $successValue;

    if ($gatewayRedirect) {    # required for postback to /pay or pay.cgi
      $alwaysUsePost                     = 1;
      $query->{'skipTransitionTemplate'} = 1;
      $query->{'orderID'}                = '';
    }

    my %data = ( %{$query}, %{$result} );

    my @fieldNames = keys %data;

    my $fields = filterTransitionOrGoToCgiFields({ 
      fieldNames      => \@fieldNames,
      gatewayRedirect => $gatewayRedirect
    });

    &transition( @{$fields}, $alwaysUsePost );
  } else {
    &gotocgi();
  }
}

sub filterTransitionOrGoToCgiFields {
  my $input           = shift;
  my $inputFieldNames = $input->{'fieldNames'};
  my $gatewayRedirect = $input->{'gatewayRedirect'};

  my @filteredFieldNames;

  foreach my $field ( sort @{$inputFieldNames} ) {
    if ( $gatewayRedirect && $field =~ /.link$/i ) {
      push @filteredFieldNames, $field;
    } elsif ( $field !~ /.link$/i
      && $field !~ /^card.number/i
      && $field !~ /^card.cvv/i
      && $field !~ /merch.txn/i
      && $field !~ /cust.txn/i
      && $field !~ /month.exp/i
      && $field !~ /year.exp/i
      && $field !~ /magstripe/i
      && $field !~ /mpgiftcard/i
      && $field !~ /mpcvv/i
      && $field !~ /magensacc/i ) {
      push @filteredFieldNames, $field;
    }
  }

  return \@filteredFieldNames;
}

sub isSelfPost {
  my $link = shift;

  # if the link is local
  if ($link =~ /^\//) {
    return 1;
  }

  return $link =~ /(plugnpay|icommercegateway|penzpay|pay-gate|spheralink|noblept|paywithcardx)\.(com|net)/;
}

sub receipt {
  my $input = shift;

  my $templateContent = $input->{'templateContent'};
  my $ruleIds = $input->{'ruleIds'} || [];    # an arrayref of receipt rules to check

  # avoid using package variables mmmkay
  my %q = ( %mckutils::query, %mckutils::result );
  if ( $q{'convert'} =~ /underscores/i ) {
    %q = &miscutils::underscore_to_hyphen(%q);
  }

  my $reseller     = $mckutils::reseller;
  my $tableContent = &create_table_for_template(%q);    # create product table data

  return PlugNPay::Legacy::MckUtils::Receipt::getReceipt(
    { mckutils_merged => \%q,
      reseller        => $reseller,
      tableContent    => $tableContent,
      ruleIds         => $ruleIds,
      templateContent => $templateContent
    }
  );
}

sub pnptest() {
  if ( $mckutils::query{'card-name'} =~ /^(pnptest|pnp test|cardtest|card test)$/ ) {
    $mckutils::result{'FinalStatus'} = "success";
    $mckutils::result{'MStatus'}     = "success";
    $mckutils::query{'success'}      = "yes";
    $mckutils::success               = "yes";
    $mckutils::pnp_debug             = "yes";
    $mckutils::result{'auth-code'}   = "TSTAUT";
    return %mckutils::result;
  }
}

sub problem_log {
  my $publishername = $mckutils::query{'publisher-name'};
  $publishername =~ s/[^0-9a-zA-Z]//g;
  &sysutils::filelog( "append", ">>/home/p/pay1/database/debug/$publishername\_problem.txt" );
  open( DATA, ">>/home/p/pay1/database/debug/$publishername\_problem.txt" );
  my $time = localtime(time);
  print DATA $time . ">";
  print DATA $mckutils::query{'IPaddress'} . ">";
  print DATA $mckutils::query{'User-Agent'} . ">";
  print DATA $mckutils::query{'card-name'} . ">";
  print DATA $mckutils::query{'card-address1'} . ">";
  print DATA $mckutils::query{'card-address2'} . ">";
  print DATA $mckutils::query{'card-city'} . ">";
  print DATA $mckutils::query{'card-state'} . ">";
  print DATA $mckutils::query{'card-zip'} . ">";
  print DATA $mckutils::query{'card-country'} . ">";
  print DATA $mckutils::query{'card-amount'} . ">";
  print DATA $mckutils::query{'order-id'} . ">";
  print DATA $mckutils::orderID . ">";
  print DATA $mckutils::query{'success-link'} . ">";
  print DATA $mckutils::query{'email'} . ">";
  print DATA " ";
  print DATA %mckutils::result;
  print DATA "\n";

}

sub getinfo {
  my (%info);
  my $dbh_info = &miscutils::dbhconnect("$mckutils::query{'publisher-name'}");
  my $sth_info = $dbh_info->prepare(
    qq{
          select name,address1,address2,city,state,zip,country,monthly,email
          from customer
          where username=? and password=?
  }
  );
  $sth_info->execute( "$mckutils::query{'username'}", "$mckutils::query{'password'}" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query, %mckutils::result );
  ( $info{'name'}, $info{'address1'}, $info{'address2'}, $info{'city'}, $info{'state'}, $info{'zip'}, $info{'country'}, $info{'monthly'}, $info{'email'} ) = $sth_info->fetchrow;
  $sth_info->finish;
  $dbh_info->disconnect;
  return %info;
}

sub cart32 {
  my (%query1) = @_;
  for ( my $k = 1 ; $k <= $query1{'NumberOfItems'} ; $k++ ) {
    $query1{"item$k"}        = substr( $query1{"Item$k"}, 0, 4 ) . $k;
    $query1{"cost$k"}        = $query1{"Price$k"};
    $query1{"quantity$k"}    = $query1{"Qty$k"};
    $query1{"description$k"} = $query1{"Item$k"};
    $query1{"option$k"}      = $query1{"Option$k"};
  }
  $query1{'card-name'} = "$query1{'card-fname'} $query1{'card-lname'}";
  if ( ( $query1{'shipfname'} ne "" ) && ( $query1{'shiplname'} ne "" ) ) {
    $query1{'shipname'} = "$query1{'shipfname'} $query1{'shiplname'}";
    $query1{'shipinfo'} = 1;
  }
  return %query1;
}

sub shopsite {
  $mckutils::query{'card-number'}    = $mckutils::query{'ccNum'};
  $mckutils::query{'card-zip'}       = $mckutils::query{'ZIP'};
  $mckutils::query{'card-amount'}    = $mckutils::query{'amount'};
  $mckutils::query{'card-exp'}       = substr( $mckutils::query{'expDate'}, 0, 2 ) . "/" . substr( $mckutils::query{'expDate'}, 2, 2 );
  $mckutils::query{'publisher-name'} = $mckutils::query{'vendorID'};

}

sub courtpay {
  ## Map Custome Fields Here

  if ( ( ( substr( $mckutils::query{'publisher-name'}, 0, 2 ) eq "ut" ) || ( $mckutils::query{'publisher-name'} =~ /^(cavespring)$/ ) )
    && ( $ENV{'SCRIPT_NAME'} !~ /\/courtpay\//i ) ) {
    $mckutils::query{'shipname'}              = "$mckutils::query{'x-firstname'} $mckutils::query{'x-lastname'}";
    $mckutils::query{'shipphone'}             = $mckutils::query{'x-phone'};
    $mckutils::query{'customa'}               = $mckutils::query{'x-email'};
    $mckutils::query{'shipaddr1'}             = $mckutils::query{'x-address1'};
    $mckutils::query{'shipaddr2'}             = $mckutils::query{'x-address2'};
    $mckutils::query{'shipcity'}              = $mckutils::query{'x-city'};
    $mckutils::query{'shipstate'}             = $mckutils::query{'x-state'};
    $mckutils::query{'shipzip'}               = $mckutils::query{'x-postalcode'};
    $mckutils::query{'acct_code2'}            = $mckutils::query{'x-reconnect'};
    $mckutils::query{'x-defendantfirstname'}  = $mckutils::query{'x-firstname'};
    $mckutils::query{'x-defendantlastname'}   = $mckutils::query{'x-lastname'};
    $mckutils::query{'x-defendantphone'}      = $mckutils::query{'x-phone'};
    $mckutils::query{'x-defendantemail'}      = $mckutils::query{'x-email'};
    $mckutils::query{'x-defendantaddress1'}   = $mckutils::query{'x-address1'};
    $mckutils::query{'x-defendantaddress2'}   = $mckutils::query{'x-address2'};
    $mckutils::query{'x-defendantcity'}       = $mckutils::query{'x-city'};
    $mckutils::query{'x-defendantstate'}      = $mckutils::query{'x-state'};
    $mckutils::query{'x-defendantpostalcode'} = $mckutils::query{'x-postalcode'};
    $mckutils::query{'descr'}                 = $mckutils::query{'x-notes'};
  } else {
    $mckutils::query{'shipname'}   = "$mckutils::query{'x-defendantfirstname'} $mckutils::query{'x-defendantlastname'}";
    $mckutils::query{'shipphone'}  = $mckutils::query{'x-defendantphone'};
    $mckutils::query{'customa'}    = $mckutils::query{'x-defendantemail'};
    $mckutils::query{'shipaddr1'}  = $mckutils::query{'x-defendantaddress1'};
    $mckutils::query{'shipaddr2'}  = $mckutils::query{'x-defendantaddress2'};
    $mckutils::query{'shipcity'}   = $mckutils::query{'x-defendantcity'};
    $mckutils::query{'shipstate'}  = $mckutils::query{'x-defendantstate'};
    $mckutils::query{'shipzip'}    = $mckutils::query{'x-defendantpostalcode'};
    $mckutils::query{'acct_code2'} = $mckutils::query{'x-dob'};
    $mckutils::query{'descr'}      = $mckutils::query{'x-notes'};
  }

  if ( $mckutils::query{'card-name'} eq "" ) {
    $mckutils::query{'card-name'} = "$mckutils::query{'card_fname'} $mckutils::query{'card_lname'}";
  }
}

sub wallet {
  my ( $addr3, $stitle, $sfname, $smname, $slname, $shipaddr2, $shipaddr3, $enccardnumber, $length, $shipemail );
  my $dbh_wallet = &miscutils::dbhconnect("wallet");
  my $sth        = $dbh_wallet->prepare(
    qq{
       select name,addr1,addr2,addr3,city,state,zip,country,enccardnumber,length,cardexp
       from billing
       where username=? and commonname=?
  }
  ) or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$mckutils::query{'Ecom_Subscriber_Username'}", "$mckutils::query{'Ecom_Payment_Common_Name'}" ) or die "Can't execute: $DBI::errstr";
  ( $mckutils::query{'card-name'}, $mckutils::query{'card-address1'}, $mckutils::query{'card-address2'}, $addr3,
    $mckutils::query{'card-city'}, $mckutils::query{'card-state'},    $mckutils::query{'card-zip'},      $mckutils::query{'card-country'},
    $enccardnumber,                $length,                           $mckutils::query{'card-exp'}
  )
    = $sth->fetchrow;
  $sth->finish;
  $mckutils::query{'card-number'} = &rsautils::rsa_decrypt_file( $enccardnumber, $length, "print enccardnumber 497", "/home/p/pay1/pwfiles/keys/key" );

  $sth = $dbh_wallet->prepare(
    qq{
       select title,sfname,smname,slname,shipaddr1,shipaddr2,shipaddr3,
              shipcity,shipstate,shipzip,shipcountry,shipphone,shipemail
       from shipping
       where username=? and commonname=?
  }
  ) or die "Can't prepare: $DBI::errstr";
  $sth->execute( "$mckutils::query{'Ecom_Subscriber_Username'}", "$mckutils::query{'Ecom_ShipTo_Common_Name'}" ) or die "Can't execute: $DBI::errstr";
  ( $stitle,                     $sfname,                   $smname,                  $slname,                   $mckutils::query{'address1'},
    $shipaddr2,                  $shipaddr3,                $mckutils::query{'city'}, $mckutils::query{'state'}, $mckutils::query{'zip'},
    $mckutils::query{'country'}, $mckutils::query{'phone'}, $shipemail
  )
    = $sth->fetchrow;
  $sth->finish;
  $dbh_wallet->disconnect;

  $mckutils::query{'shipname'} = "$stitle $sfname $smname $slname";
  $mckutils::query{'address2'} = "$shipaddr2 $shipaddr3";
  $mckutils::query{'shipping'} = $mckutils::query{"$mckutils::query{'Ecom_ShipTo_Common_Name'}_shipping"};
  $mckutils::query{'tax'}      = $mckutils::query{"$mckutils::query{'Ecom_ShipTo_Common_Name'}_tax"};

  #$mckutils::query{'card-amount'} = $mckutils::query{'subtotal'} + $mckutils::query{'shipping'} + $mckutils::query{'tax'};

  if ( $mckutils::query{'wfunction'} eq "purchecash" ) {
    $mckutils::query{'item1'}        = "eCash";
    $mckutils::query{'cost1'}        = $mckutils::query{'card-amount'};
    $mckutils::query{'description1'} = "eCash Purchase";
    $mckutils::query{'quantity1'}    = "1";
  }
}

sub test_success {
  if ( $mckutils::result{'FinalStatus'} ne "success" ) {
    $mckutils::query{'MErrMsg'}   = $mckutils::result{'MErrMsg'};
    $mckutils::query{'orderID'}   = "";
    $mckutils::query{'resp-code'} = $mckutils::result{'resp-code'};
  } else {
    $mckutils::query{'success'}   = $mckutils::success;
    $mckutils::query{'MErrMsg'}   = "";
    $mckutils::query{'auth-code'} = $mckutils::result{'auth-code'};
    $mckutils::query{'avs-code'}  = $mckutils::result{'avs-code'};
    $mckutils::query{'resp-code'} = $mckutils::result{'resp-code'};
  }
  $mckutils::query{'id'} = $mckutils::orderID;
  print header( -type => 'text/html' );    #### DCP 20100712
  print "<html>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<font size=+1>\n";
  print "<form method=\"post\" action=\"$mckutils::query{\"$mckutils::result{'FinalStatus'}\-link\"}\"><br>\n";
  my $a = $mckutils::query{"$mckutils::result{'FinalStatus'}-link"};
  $a =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\|]/x/g;
  print "<test URL=\"$a\">\n";

  print "<table>\n";
  foreach my $key ( sort keys %mckutils::query ) {
    if ( ( $key ne "card-number" )
      && ( $key ne "card-exp" )
      && ( $key !~ /^card.cvv/i )
      && ( $key ne "max" )
      && ( $key ne "pass" )
      && ( $key ne "$result{'FinalStatus'}-link" )
      && ( $key ne 'User-Agent' ) ) {
      print "<tr><td>$key:</td><td><input type=\"text\" name=\"$key\" value=\"$mckutils::query{$key}\"></td></tr>\n";
    }
  }
  print "</table>\n";
  print "<input type=\"submit\" value=\"Submit\">\n";

  print "</form>\n";
  print "</body>\n";
  print "</html>\n";
  exit;
}

sub cookie {
  if ( $mckutils::query{'cookie_pw1'} ne "" ) {
    my $id  = $mckutils::query{'email'} . $mckutils::orderid . $mckutils::query{'card-address1'} . $$ . $mckutils::query{'card-name'};
    my $md5 = new MD5;
    $md5->add("$id");
    my $pnpid = $md5->hexdigest();
    &update_express_record($pnpid);
    print "Set-Cookie: pnpid=$pnpid; path=/; expires=Wednesday, 01-Jan-10 23:00:00 GMT; host=.$mckutils::domain; secure; \n";
  }
}

sub update_express_record {
  my ($pnpid) = @_;
  my $cardbin = substr( $mckutils::query{'card-number'}, 0, 6 );
  my ($baddr3);
  my $cardtype = &miscutils::cardtype( $mckutils::query{'card-number'} );

  my %length_hash = (
    'card-name', '39', 'card-address1', '39', 'card-address2', '39', 'card-country', '2',  'card-city', '22', 'card-state', '2',
    'card-zip',  '13', 'shipname',      '39', 'address1',      '39', 'address2',     '39', 'city',      '39', 'state',      '2',
    'zip',       '13', 'country',       '2',  'phone',         '15', 'fax',          '10', 'email',     '59'
  );

  foreach my $testvar ( keys %length_hash ) {
    if ( ( exists $mckutils::query{$testvar} )
      && ( length( $mckutils::query{$testvar} ) > $length_hash{$testvar} ) ) {
      $mckutils::query{$testvar} =
        substr( $mckutils::query{$testvar}, 0, $length_hash{$testvar} );
    }
  }

  my $dbh = &miscutils::dbhconnect('wallet');
  my $sth = $dbh->prepare(
    qq{
       select walletid
       from subscriber
       where  walletid=?
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
  $sth->execute("$pnpid")
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
  my ($id) = $sth->fetchrow;
  $sth->finish;
  if ( $id ne "" ) {
    my $sth = $dbh->prepare(
      qq{
        update subscriber set name=?,email=?,password=?
        where walletid=?
      }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
    $sth->execute( "$mckutils::query{'card-name'}", "$mckutils::query{'email'}", "$mckutils::query{'cookie_pw1'}", "$pnpid" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
    $sth->finish;
  } else {
    my $sth = $dbh->prepare(
      qq{
        insert into subscriber
        (walletid,name,email,password)
        values (?,?,?,?)
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
    $sth->execute( $pnpid, $mckutils::query{'card-name'}, $mckutils::query{'email'}, $mckutils::query{'cookie_pw1'} )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
    $sth->finish;
  }
  my $cardnumber = $mckutils::query{'card-number'};
  my ( $enccardnumber, $length ) = &rsautils::rsa_encrypt_card( $cardnumber, '/home/p/pay1/pwfiles/keys/key' );
  $cardnumber = substr( $cardnumber, 0, 4 ) . "**" . substr( $cardnumber, -2 );

  $sth = $dbh->prepare(
    qq{
       select commonname
       from billing
       where  walletid=? and commonname='express'
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
  $sth->execute("$pnpid")
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
  my ($commonname) = $sth->fetchrow;
  $sth->finish;

  if ( $commonname ne "" ) {
    my $sth = $dbh->prepare(
      qq{
        update billing set name=?,addr1=?,addr2=?,addr3=?,city=?,state=?,zip=?,country=?,
                           cardtype=?,cardnumber=?,enccardnumber=?,length=?,cardexp=?
        where walletid=? and commonname='express'
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
    $sth->execute(
      $mckutils::query{'card-name'},  $mckutils::query{'card-address1'}, $mckutils::query{'card-address2'}, $baddr3,   $mckutils::query{'card-city'},
      $mckutils::query{'card-state'}, $mckutils::query{'card-zip'},      $mckutils::query{'card-country'},  $cardtype, $cardnumber,
      $enccardnumber,                 $length,                           $mckutils::query{'card-exp'},      "$pnpid"
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
    $sth->finish;
  } else {
    my $sth = $dbh->prepare(
      qq{
        insert into billing
        (walletid,commonname,name,addr1,addr2,addr3,city,state,zip,country,cardtype,cardnumber,
        enccardnumber,length,cardexp)
        values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
    $sth->execute(
      $pnpid,    "express",                     $mckutils::query{'card-name'},  $mckutils::query{'card-address1'}, $mckutils::query{'card-address2'},
      $baddr3,   $mckutils::query{'card-city'}, $mckutils::query{'card-state'}, $mckutils::query{'card-zip'},      $mckutils::query{'card-country'},
      $cardtype, $cardnumber,                   $enccardnumber,                 $length,                           $mckutils::query{'card-exp'}
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
    $sth->finish;
  }

  if ( $mckutils::query{'shipinfo'} eq "1" ) {
    my ( $sfname, $slname, $stuff ) =
      split( ' ', $mckutils::query{'shipname'} );
    my $sth = $dbh->prepare(
      qq{
       select commonname
       from shipping
       where  walletid=? and commonname='express'
    }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
    $sth->execute("$pnpid")
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
    my ($commonname) = $sth->fetchrow;
    $sth->finish;

    if ( $commonname ne "" ) {
      my $sth = $dbh->prepare(
        qq{
          update shipping set sfname=?,slname=?,shipaddr1=?,shipaddr2=?,shipaddr3=?,
                              shipcity=?,shipstate=?,shipzip=?,shipcountry=?,shipphone=?,shipemail=?
          where walletid=? and commonname='express'
      }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
      $sth->execute(
        $sfname,                   "$slname $stuff",        $mckutils::query{'address1'}, $mckutils::query{'address2'}, $mckutils::query{'address3'}, $mckutils::query{'city'},
        $mckutils::query{'state'}, $mckutils::query{'zip'}, $mckutils::query{'country'},  $mckutils::query{'phone'},    $mckutils::query{'email'},    "$pnpid"
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
      $sth->finish;
    } else {
      my $sth = $dbh->prepare(
        qq{
        insert into shipping
        (walletid,commonname,sfname,slname,shipaddr1,shipaddr2,shipaddr3,
        shipcity,shipstate,shipzip,shipcountry,shipphone,shipemail)
        values (?,?,?,?,?,?,?,?,?,?,?,?,?)
        }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
      $sth->execute(
        $pnpid,                       "express",                $sfname,                   "$slname $stuff",        $mckutils::query{'address1'}, $mckutils::query{'address2'},
        $mckutils::query{'address3'}, $mckutils::query{'city'}, $mckutils::query{'state'}, $mckutils::query{'zip'}, $mckutils::query{'country'},  $mckutils::query{'phone'},
        $mckutils::query{'email'}
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
      $sth->finish;
    }
  }
  $dbh->disconnect;
}

sub test_softcrt {
  my (%input);
  if ( $result{'FinalStatus'} ne "success" ) {
    $mckutils::query{'MErrMsg'}   = $result{'MErrMsg'};
    $mckutils::query{'orderID'}   = "";
    $mckutils::query{'resp-code'} = $result{'resp-code'};
  } else {
    $mckutils::query{'success'}   = $mckutils::success;
    $mckutils::query{'MErrMsg'}   = "";
    $mckutils::query{'auth-code'} = $result{'auth-code'};
    $mckutils::query{'avs-code'}  = $result{'avs-code'};
    $mckutils::query{'resp-code'} = $result{'resp-code'};

  }
  $mckutils::query{'id'} = $mckutils::orderID;

  $input{'cardname'}             = $mckutils::query{'card-name'};
  $input{'CCType'}               = $mckutils::query{'card-type'};
  $input{'ShipName'}             = $mckutils::query{'shipname'};
  $input{'ShipAddress1'}         = $mckutils::query{'address1'};
  $input{'ShipAddress2'}         = $mckutils::query{'address2'};
  $input{'ShipCity'}             = $mckutils::query{'city'};
  $input{'ShipState'}            = $mckutils::query{'state'};
  $input{'ShipZIP'}              = $mckutils::query{'zip'};
  $input{'ShipCountry'}          = $mckutils::query{'country'};
  $input{'DayPhone'}             = $mckutils::query{'phone'};
  $input{'NitePhone'}            = $mckutils::query{'fax'};
  $input{'Email_addr'}           = $mckutils::query{'email'};
  $input{'Name'}                 = $mckutils::query{'card-name'};
  $input{'Address1'}             = $mckutils::query{'card-address1'};
  $input{'Address2'}             = $mckutils::query{'card-address2'};
  $input{'City'}                 = $mckutils::query{'card-city'};
  $input{'State'}                = $mckutils::query{'card-state'};
  $input{'ZIP'}                  = $mckutils::query{'card-zip'};
  $input{'Country'}              = $mckutils::query{'card-country'};
  $input{'ShippingInstructions'} = $mckutils::query{'comments'};
  $input{'TotalShipping'}        = $mckutils::query{'shipping'};
  $input{'TotalTax'}             = $mckutils::query{'tax'};

  $mckutils::query{'success-link'} = $mckutils::query{'path-softcart'} . $mckutils::query{'path-postorder'} . "?T";

  if ( $mckutils::query{'sessionid'} ne "" ) {
    $_ = $mckutils::query{'success-link'} . "\+" . $mckutils::query{'storename'} . "\+" . $mckutils::query{'sessionid'};
  } else {
    $_ = $mckutils::query{'success-link'} . "\+" . $mckutils::query{'storename'} . "\+" . $mckutils::query{'order-id'};
  }

  print header( -type => 'text/html' );    #### DCP 20100712
  print "<html>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<font size=+1>\n";
  print "<form method=\"post\" action=\"$_\"><br>\n";
  print "<table>\n";
  my ($key);

  foreach $key ( keys %input ) {
    $_ = $input{$key};
    print "<tr><td>$key:</td><td><input type=\"text\" name=\"$key\" value=\"$_\"></td></tr>\n";
  }

  #      s/(\W)/'%' . unpack("H2",$1)/ge;
  print "</table>\n";
  print "<input type=\"submit\" value=\"Submit\">\n";

  print "</form>\n";
  print "</body>\n";
  print "</html>\n";
  exit;
}

sub referrer_check {
  my ($domain_check) = @_;
  my $referrer_domain = $ENV{'HTTP_REFERER'};
  my ( $dom_sec, $dom_min, $dom_hour, $dom_mday, $dom_mon, $dom_yyear, $dom_wday, $dom_yday, $dom_isdst ) = localtime(time);
  my $domain_today = sprintf( "%04d%02d%02d", $dom_yyear + 1900, $dom_mon + 1, $dom_mday );
  open( DOMAINS, ">>/home/p/pay1/database/domain_check.txt" );
  print DOMAINS "$domain_today:$domain_check:$referrer_domain\n";
  close(DOMAINS);
  if ( ( $referrer_domain !~ /plugnpay.com/ )
    && ( $referrer_domain !~ /$domain_check/i )
    && ( $referrer_domain !~ /aol.com/ ) ) {
    my $response_message = "Access to this page was from an un-authorized source.<p>  Please use the back button and resubmit the form again.";
    &response_page( $response_message, $referrer_domain, $domain_check );
    exit;
  }
}

sub response_page {
  my ( $response_message, $referrer_domain, $domain_check ) = @_;
  print header( -type => 'text/html' );    #### DCP 20100712
  print "<html>\n";
  print "<head>\n";
  print "<title>Un-Authorized Access $referrer_domain:$domain_check</title>\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\">\n";
  print "<div align=center>\n";
  print "<p>\n";
  print "<font size=+2>$response_message</font>\n";
  print "</body>\n";
  print "</html>\n";

  exit;
}

sub underscore_to_hyphen {
  my $time = gmtime(time);

  my ($key);
  foreach $key ( keys %mckutils::query ) {
    if ( ( $key !~ /acct_code|receipt_type|cvv_ign/ ) && ( $key =~ /\_/ ) ) {
      $_ = $mckutils::query{$key};
      $mckutils::query{$key} = "";
      $key =~ tr/\_/\-/;
      $mckutils::query{$key} = $_;
    }
  }
  $mckutils::query{'publisher-name'} =~ s/[^0-9a-zA-Z]//g;
  $mckutils::query{'publisher-name'} =
    substr( $mckutils::query{'publisher-name'}, 0, 12 );
}

sub hyphen_to_underscore {
  my ( $key, $temp );
  foreach $key ( keys %mckutils::query ) {
    if ( ( $key ne "acct_code" )
      && ( $key =~ /\-/ )
      && ( $key !~ /-link/ ) ) {
      $temp = $mckutils::query{$key};
      delete $mckutils::query{$key};
      $key =~ tr/\-/\_/;
      $mckutils::query{$key} = $temp;
    }
  }
  foreach $key ( keys %mckutils::result ) {
    if ( $key =~ /\-/ ) {
      $temp = $mckutils::result{$key};
      $key =~ tr/\-/\_/;
      $mckutils::query{$key} = $temp;
    }
  }
}

sub payperview {
  my ($expire) = @_;
  $mckutils::query{'username'} = $mckutils::query{'uname'};
  $mckutils::query{'password'} = $mckutils::query{'passwrd1'};
  $mckutils::query{'end'}      = $expire;
  $mckutils::query{'mode'}     = "new";
  my $md5 = new MD5;
  $md5->add("$mckutils::query{'uname'}:$mckutils::query{'realm'}:$mckutils::query{'passwrd1'}");
  $mckutils::query{'enc_password'} = $md5->hexdigest();
  &gotocgi();
}

sub delete_easycart {
  my $expires = gmtime( time() - 1 * 3600 );
  my ($i);
  for ( $i = 1 ; $i <= $mckutils::max ; $i++ ) {
    my $item = $mckutils::query{"item$i"};
    if ( $mckutils::cookie{"ezcrt_$item"} > 0 ) {
      print "Set-Cookie: ezcrt_$item=0; path=/; expires=$expires; domain=.$mckutils::domain\r\n";
    }
  }
}

sub payment_plans {
  my (%query1) = @_;
  my ( $stuff, $database );
  ( $query1{'plan'}, $stuff ) = split( ':', $query1{'plan'} );

  if ( $query1{'merchantdb'} ne "" ) {
    $database = $query1{'merchantdb'};
  } else {
    $database = $query1{'publisher-name'};
  }
  $database =~ s/[^0-9a-zA-Z]//g;

  my $path_plans = "$mckutils::path_web/payment/recurring/$database/admin/paymentplans.txt";
  my ( $parseflag, $i );
  if ( -e $path_plans ) {
    &sysutils::filelog( "read", "$path_plans" );
    open( PAYPLANS, "$path_plans" ) || die "Cannot Open payment Plans\n\n";
    my (@fields);
    while (<PAYPLANS>) {
      chop;
      my @data = split('\t');
      if ( substr( $data[0], 0, 1 ) eq "\!" ) {
        $parseflag = 1;
        (@fields) = (@data);
        $fields[0] = substr( $data[0], 1 );
        next;
      }
      if ( $parseflag == 1 ) {
        my ($i);
        foreach my $var (@fields) {
          $var =~ tr/A-Z/a-z/;

          #if (($data[$i] ne "") && ($var ne "plan")) {
          if ( $var ne "plan" ) {
            $query1{$var}             = $data[$i];
            $mckutils::payplans{$var} = $data[$i];
          }
          $i++;
        }
        $main::recurringfee = $query1{'recurringfee'};
        $main::months       = $query1{'months'};
        $main::days         = $query1{'days'};
        $main::purchaseid   = $query1{'purchaseid'};
        $main::minutes      = $query1{'minutes'};

        %mckutils::recurring = %query1;

        if ( $main::minutes ne "" ) {
          my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( time() + $main::minutes );
          $query1{'endtime'} = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
        }

        if ( $query1{'rquantity'} > 1 ) {
          $query1{'card-amount'}               = sprintf( "%.2f", $query1{'card-amount'} * $query1{'rquantity'} );
          $mckutils::recurring{'recurringfee'} = sprintf( "%.2f", $mckutils::recurring{'recurringfee'} * $query1{'rquantity'} );
          if ( $query1{'balance'} > 0 ) {
            $query1{'balance'} = sprintf( "%.2f", $query1{'balance'} * $query1{'rquantity'} );
          }
        }

        my ( $plan, $stuff ) = split( ':', $query1{'planid'} );
        if ( ( $fields[0] =~ /plan/i ) && ( $query1{'plan'} eq $plan ) ) {
          $query1{'plan'} = $query1{'planid'};
          last;
        }
      }
    }
  }
  if ( exists $query1{'card-amount'} ) {
    $query1{'card-amount'} =~ tr/A-Z/a-z/;
    if ( $query1{'card-amount'} =~ /^[a-z]{3} .+/ ) {
      ( $query1{'currency'}, $query1{'card-amount'} ) =
        split( / /, $query1{'card-amount'} );
    }
    $query1{'card-amount'} =~ s/[^0-9\.]//g;
    $query1{'card-amount'} = sprintf( "%.2f", $query1{'card-amount'} );
  }
  return %query1;
}

sub merchant_email {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my $now = gmtime( time() );
  open( DEBUG, ">>/home/p/pay1/database/debug/merchant_email_debug.txt" );
  print DEBUG "DATE:$now, IP:$remote_ip, SCRIPT:$ENV{'SCRIPT_NAME'}, PID:$$, RM:$ENV{'REQUEST_METHOD'}, UN:$mckutils::query{'publisher-name'}\n";
  close(DEBUG);

  #use Datalog
  my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
  $logger->log(
    { 'DATE'   => $now,
      'IP'     => $remote_ip,
      'SCRIPT' => $ENV{'SCRIPT_NAME'},
      'PID'    => $$,
      'RM'     => $ENV{'REQUEST_METHOD'},
      'UN'     => $mckutils::query{'publisher-name'}
    }
  );

  my ( $desc, $qnty, $cost, $item );
  my $bcc = "";

  if ( $result{'FinalStatus'} eq "success" ) {
    if ( ( $bcc ne "" ) && ( $mckutils::query{'ff-email'} ne "" ) ) {
      $bcc = $bcc . ", $mckutils::query{'ff-email'}";
    } elsif ( $mckutils::query{'ff-email'} ne "" ) {
      $bcc = $mckutils::query{'ff-email'};
    }
  }

  if ( ( $mckutils::query{'cc-email'} ne "" )
    && ( $mckutils::query{'cc-mail'} eq "" ) ) {
    $mckutils::query{'cc-mail'} = $mckutils::query{'cc-email'};
  }

  my $reseller = new PlugNPay::Reseller($mckutils::reseller);

  #check for duplicate order before we email the merchant
  if ( $result{'Duplicate'} ne "yes" ) {
    my $emailer = new PlugNPay::Email('legacy');
    $emailer->setGatewayAccount( $mckutils::query{'publisher-name'} );
    $emailer->setFormat('text');

    $emailer->setTo( $mckutils::query{'publisher-email'} );
    if ( $mckutils::query{'cc-mail'} ne "" ) {
      $emailer->setCC( $mckutils::query{'cc-mail'} );
    }
    if ( $bcc ne "" ) {
      $emailer->setBCC($bcc);
    }
    if ( $mckutils::query{'email'} ne "" ) {
      $emailer->setFrom( $mckutils::query{'email'} );
    } else {
      if ( $mckutils::reseller eq "electro" ) {
        $emailer->setFrom("paymentserver\@eci-pay.com");
      } else {
        my $emailDomain = $reseller->getEmailDomain();
        $emailer->setFrom("paymentserver\@$emailDomain");
      }
    }
    if ( $mckutils::query{'subject'} ne "" ) {
      $emailer->setSubject("$mckutils::query{'subject'} $mckutils::query{'card-name'} $result{'FinalStatus'}");
    } else {
      $emailer->setSubject("$mckutils::esub - $mckutils::query{'card-name'} $result{'FinalStatus'} notification");
    }

    my $merchmail = "Merchant Order ID: $mckutils::query{'order-id'}\n";
    if ( $mckutils::query{'agent'} ne "" ) {
      $merchmail .= "SalesAgent: $mckutils::query{'agent'}\n";
    }
    $merchmail .= "Transaction Order ID: $mckutils::orderID\n";
    $merchmail .= "\nBilling Address:\n";
    $merchmail .= $mckutils::query{'card-name'} . "\n";
    if ( $mckutils::query{'card-company'} ne "" ) {
      $merchmail .= "\n";
      $merchmail .= "Company: $mckutils::query{'card-company'}\n";
    }
    $merchmail .= $mckutils::query{'card-address1'} . "\n";
    if ( $mckutils::query{'card-address2'} ne "" ) {
      $merchmail .= $mckutils::query{'card-address2'} . "\n";
    }
    if ( $mckutils::query{'card-state'} ne "" ) {
      $merchmail .= $mckutils::query{'card-city'} . ", " . $mckutils::US_CN_states{ $mckutils::query{'card-state'} } . " " . $mckutils::query{'card-zip'} . "\n";
    } else {
      $merchmail .= $mckutils::query{'card-city'} . ", " . $mckutils::query{'card-zip'} . "\n";
    }
    $merchmail .= $mckutils::countries{ $mckutils::query{'card-country'} } . "\n\n";
    $merchmail .= $mckutils::query{'card-prov'} . "\n";
    if ( $mckutils::query{'shipinfo'} == 1 ) {
      $merchmail .= "\nShipping Address:\n";
      $merchmail .= $mckutils::query{'shipname'} . "\n";
      $merchmail .= $mckutils::query{'address1'} . "\n";
      if ( $mckutils::query{'address2'} ne "" ) {
        $merchmail .= $mckutils::query{'address2'} . "\n";
      }
      if ( $mckutils::query{'state'} ne "" ) {
        $merchmail .= $mckutils::query{'city'} . "," . $mckutils::US_CN_states{ $mckutils::query{'state'} } . " " . $mckutils::query{'zip'} . "\n";
      } else {
        $merchmail .= $mckutils::query{'city'} . "," . $mckutils::query{'zip'} . "\n";
      }
      $merchmail .= $mckutils::query{'province'} . "\n";
      $merchmail .= $mckutils::countries{ $mckutils::query{'country'} } . "\n\n";
    }
    $merchmail .= $mckutils::query{'email'} . "\n";
    $merchmail .= $mckutils::query{'phone'} . "\n";
    $merchmail .= $mckutils::query{'fax'} . "\n\n";

    if ( ( $mckutils::query{'passwrd1'} ne "" )
      && ( $mckutils::query{'uname'} ne "" )
      && ( $mckutils::sendpwinfo eq "yes" ) ) {
      $merchmail .= "\nUsername: $mckutils::query{'uname'}\nPassword: $mckutils::query{'passwrd1'}\n\n";
      $merchmail .= "\n";
    }

    if ( $mckutils::query{'easycart'} eq "1" ) {
      my $purchase_table = Text::Table->new( 'MODEL NO.', 'QTY', 'CHARGE', 'DESCRIPTION' );
      for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {
        if ( $mckutils::query{"quantity$i"} > 0 ) {
          $purchase_table->add( $mckutils::query{"item$i"}, $mckutils::query{"quantity$i"}, $mckutils::query{"cost$i"}, $mckutils::query{"description$i"} );
        }
      }
      $merchmail .= $purchase_table;
    }

    if ( $mckutils::query{'subtotal'} ne "" ) {
      $merchmail .= sprintf "Subtotal:  %.2f\n", $mckutils::query{'subtotal'};
    }
    if ( $mckutils::query{'discnt'} > 0.01 ) {
      $merchmail .= sprintf "Discount:  (%.2f)\n", $mckutils::query{'discnt'};
    }
    if ( $mckutils::query{'tax'} > 0.01 ) {
      $merchmail .= sprintf "Tax:  %.2f\n", $mckutils::query{'tax'};
    }
    if ( $mckutils::query{'shipping'} ne "" ) {
      $merchmail .= sprintf "Shipping:  %.2f\n", $mckutils::query{'shipping'};
    }

    $merchmail .= sprintf "Total:  %.2f\n", $mckutils::query{'card-amount'};

    if ( $mckutils::query{'comments'} ne "" ) {
      $mckutils::query{'comments'} =~ s/\&quot\;/\"/g;
      if ( $mckutils::query{'comm-title'} ne "" ) {
        $merchmail .= $mckutils::query{'comm-title'} . "\n";
      } else {
        $merchmail .= "Comments \&/or Special Instructions:\n";
      }
      $merchmail .= $mckutils::query{'comments'} . "\n\n";
    }

    if ( $result{'FinalStatus'} eq "success" ) {
      if ( $mckutils::query{'paymethod'} eq "check" ) {

      } elsif ( $mckutils::query{'paymethod'} eq "onlinecheck" ) {
        $merchmail .= "Payment Method: Online Check\n";
      } else {
        if ( $mckutils::trans_type ne "storedata" ) {
          if ( $mckutils::query{'paymethod'} eq "onlinecheck" ) {
            $merchmail .= "Electronic Debit was successful\n";
          } else {
            $merchmail .= "Credit Card Authorization was successful\n";
            my $temp = substr( $result{'auth-code'}, 0, 6 );
            $merchmail .= "Authorization Code: $temp\n";
            my %cvv_hash = ( 'M', 'Match', 'N', 'Did not match.', 'P', 'Not able to be processed.', 'U', 'Unavailable for checking.', 'X', 'Unavailable for checking.' );
            if ( $result{'cvvresp'} ne "" ) {
              $merchmail .= "CVV2/CVC2 - Response Code: $cvv_hash{$result{'cvvresp'}}\n";
            }

            my $avs = substr( $result{'avs-code'}, 0, 3 );
            $avs = substr( $avs, -1, 1 );
            $merchmail .= "AVS - Response Code:$avs\n";

            my %avs_hash = (
              'A', 'Address matches, ZIP does not.',          'E', 'Ineligible transaction.',                   'N', 'Neither Address nor ZIP matches.',
              'R', 'Retry - System Unavailable.',             'S', 'Card Type Not Supported.',                  'U', 'Address Information Unavailable.',
              'W', 'Nine digit ZIP match, Address does not.', 'X', 'Exact Match - Address and Nine digit ZIP.', 'Y', 'Address and 5 digit ZIP match.',
              'Z', 'Five digit ZIP matches, address does not.'
            );
            $merchmail .=
              ${ $mckutils::avs_responses{$avs} }[1] . "\n";

            #$merchmail .= $avs_hash{$avs} . "\n";
            $merchmail .= "Card Type: $mckutils::query{'card-type'}\n";
          }
        }
      }
      if ( $mckutils::pnp_debug eq "yes" ) {
        $merchmail .= "WARNING: THIS TRANSACTION HAS BEEN FORCED SUCCESSFUL FOR \n";
        $merchmail .= "DEBUGGING AND TESTING PURPOSES ONLY.  IF THIS IS NOT YOUR INTENT PLEASE CONTACT \n";
        $merchmail .= "THE TECHNICAL SUPPORT STAFF IMMEDIATELY. \n";
      }

      my $cf = new PlugNPay::Util::CardFilter( $mckutils::query{'card-number'} );

      if ( $mckutils::query{'showextrafields'} ne "no" ) {
        foreach my $key ( sort keys %mckutils::query ) {
          my ( $field_name, $field_value ) =
            $cf->filterPair( $key, $mckutils::query{$key}, 1 );
          if ( ( $key !~ /^(FinalStatus|success|auth-code|auth_date)$/ )
            && ( $key !~ /MErrMsg/ )
            && ( $key !~ /card-/ )
            && ( $key !~ /^(phone|fax|email)$/ )
            && ( $key !~ /^(shipinfo|shipsame|shipname|address1|address2|city|state|zip|country)$/ )
            && ( $key !~ /^(shipping|tax|taxrate|taxstate|subtotal)$/ )
            && ( $key !~ /^(currency|year-exp|month-exp|magstripe|TrakData|track|x_track|card-number|card_num|cardnumber|magensacc|emvtags)/i )
            && ( $key !~ /^(accountnum|routingnum|checknum|accttype)$/ )
            && ( $key !~ /^(publisher-name|publisher-password|merchant|User-Agent|referrer)$/ )
            && ( $key !~ /^(publisher-email|cc-mail|from-email|subject|message|dontsndmail)$/ )
            && ( $mckutils::query{$key} ne "subject-email" )
            && ( $key !~ /^(comm-title|comments|order-id)$/ )
            && ( $key !~ /^(orderid)/i )
            && ( $key !~ /^(path_cgi|path-softcart|path-postorder)$/ )
            && ( $key !~ /^(pnppassword|pnpusername)$/ )
            && ( $key !~ /^cookie_pw\d/ )
            && ( $key !~ /item|quantity|cost|description/ )
            && ( $key !~ /^(easycart|max|pass|image-link|image-placement)$/ )
            && ( $key !~ /^(required|requirecompany|nocountrylist|nofraudcheck|app-level|client|client1|acct_code4)$/ )
            && ( $key !~ /^(success-link|badcard-link|problem-link)$/ )
            && ( $key !~ /^(submit|return)$/ )
            && ( $mckutils::query{$key} ne "continue" )
            && ( $key !~ /^(merchantdb|billcycle|passwrd1|passwrd2)$/ )
            && ( $key !~ /roption|plan/ )
            && ( $key !~ /^(pnp-query|storename|sname|slink|area|x|y)$/ )
            && ( $key !~ /^(test-wgt|total-wgt|total-cnt)$/ )
            && ( $mckutils::query{$key} ne "" ) ) {
            $merchmail .= "Merchant Variable: $field_name: $field_value\n";
          }
        }
      } else {
        foreach my $var (@mckutils::emailextrafields) {
          my ( $field_name, $field_value ) =
            $cf->filterPair( $var, $mckutils::query{$var}, 1 );
          $merchmail .= "Merchant Variable: $field_name: $field_value}\n";
        }
      }
    }
    if ( $result{'FinalStatus'} eq "badcard" ) {
      if ( $mckutils::query{'paymethod'} eq "onlinecheck" ) {
        $merchmail .= "Electronic Debit failed: $result{'MErrMsg'}\n";
      } else {
        $merchmail .= "Credit Card Authorization failed: Bad Card: $result{'MErrMsg'}\n";
      }
    } elsif ( $result{'FinalStatus'} ne "success" ) {
      if ( $result{'MErrMsg'} =~ /Could not connect socket to the Merchant Payment Server/i ) {
        $result{'MErrMsg'} = "The processor for this merchant is currently experiencing temporary delays.  Please try again in a few minutes.";
      } elsif ( $result{'MErrMsg'} =~ /Payment Server Host failed to respond/i ) {
        $result{'MErrMsg'} = "The processor for this merchant is currently experiencing temporary delays.  Please try again in a few minutes.";
      } elsif ( $result{'MErrMsg'} =~ /Error while reading message from CyberCash Gateway/i ) {
        $result{'MErrMsg'} = "The processor for this merchant is currently experiencing temporary delays.  Please try again in a few minutes.";
      }
      if ( $mckutils::query{'paymethod'} eq "onlinecheck" ) {
        $merchmail .= "Electronic Debit failed: $result{'MErrMsg'}\n";
      } else {
        $merchmail .= "Credit Card Authorization failed: $result{'MErrMsg'}\n";
      }
    }

    $emailer->setContent($merchmail);
    $emailer->send();
  }
}

sub CertiTaxFinal {
  my (%certitax);
  my $url = "https://webservices.esalestax.net/CertiTAX.NET/CertiCalc.asmx/Commit";

  if ( ( $mckutils::feature{'certitax'} eq "" )
    || ( $mckutils::query{'CertiTaxID'} eq "" ) ) {
    return;
  }
  my ( $serialNumber, $merchantID, $service_level, $nexus ) =
    split( '\|', $mckutils::feature{'certitax'} );

  $certitax{'SerialNumber'} = $serialNumber;
  $certitax{'ReferredId'}   = $mckutils::query{'referredid'};

  my @certtaxids = split( '\|', $mckutils::query{'CertiTaxID'} );

  foreach my $taxid (@certtaxids) {
    $taxid =~ s/[^0-9]//g;
    $certitax{'CertiTAXTransactionId'} = $taxid;
    ### Perform Web Services Request
    my $pairs = "";
    foreach my $key ( keys %certitax ) {
      $_ = $certitax{$key};
      s/(\W)/'%' . unpack("H2",$1)/ge;
      if ( $pairs ne "" ) {
        $pairs = "$pairs\&$key=$_";
      } else {
        $pairs = "$key=$_";
      }
    }
    my $host = "webservices.esalestax.net";
    my $port = "443";
    my $path = "/CertiTAX.NET/CertiCalc.asmx/Commit";

    my ( $resp, $response, %headerhash ) = &miscutils::post_https_low( "$host", "$port", "$path", '', $pairs );
    if ( $mckutils::query{'CertiTaxDebug'} == 1 ) {
      my $time = gmtime(time);
      open( DEBUG, ">>/home/p/pay1/database/debug/CertTax_debug.txt" );
      print DEBUG "TIME:$time, FINAL MERCH:$mckutils::query{'publisher-name'}, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, URL:$url\n";
      print DEBUG "SEND:$pairs\n";
      print DEBUG "RETURN:$resp\n";
      my %logdata = ();
      foreach my $key ( sort keys %headerhash ) {
        print DEBUG "$key:$headerhash{$key}, ";
        $logdata{$key} = $headerhash{$key};
      }
      print DEBUG "\n\n";
      close(DEBUG);

      #use Datalog
      my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
      $logger->log(
        { 'TIME'        => $time,
          'FINAL MERCH' => $mckutils::query{'publisher-name'},
          'SCRIPT'      => $ENV{'SCRIPT_NAME'},
          'HOST'        => $ENV{'SERVER_NAME'},
          'URL'         => $url,
          'SEND'        => $pairs,
          'RETURN'      => $resp,
          'headerhash'  => \%logdata
        }
      );
    }

    if ( $headerhash{'ResponseStatus'} =~ /200 OK/ ) {
      $mckutils::query{'CertiTAXCommitStatus'} = "success";
    } else {
      $mckutils::query{'CertiTAXCommitStatus'} = "problem";
    }
  }
}

sub fulfillment {
  my ( $itemid, $product );
  my $dbh = &miscutils::dbhconnect("merch_info");

  my $sth = $dbh->prepare(
    qq{
        select itemid,product
        from fulfillment
        where username=? and orderid=?
        }
  ) or die "Can't do: $DBI::errstr";
  $sth->execute( "$mckutils::query{'publisher-name'}", "$mckutils::query{'orderID'}" )
    or die "Can't execute: $DBI::errstr";
  ( $itemid, $product ) = $sth->fetchrow;
  $sth->finish;

  if ( $itemid eq "" ) {
    my $sth = $dbh->prepare(
      qq{
        select itemid,product
        from fulfillment
        where username=? and sku=? and orderid='available'
        }
    ) or die "Can't do: $DBI::errstr";
    $sth->execute( "$mckutils::query{'publisher-name'}", "$mckutils::query{'item1'}" )
      or die "Can't execute: $DBI::errstr";
    ( $itemid, $product ) = $sth->fetchrow;
    $sth->finish;

    $sth = $dbh->prepare(
      qq{
       update fulfillment
       set orderid=?
       where username='$mckutils::query{'publisher-name'}' and sku='$mckutils::query{'item1'}' and itemid='$itemid'
       }
    ) or die "Can't prepare: $DBI::errstr";
    $sth->execute("$mckutils::query{'orderID'}");
    $sth->finish;
  }

  $dbh->disconnect;

  return $product;
}

sub fulfillment1 {
  my ( $itemid, $product, @product, $cnt );
  my $dbh = &miscutils::dbhconnect("merch_info");

  my $sth = $dbh->prepare(
    qq{
        select itemid,product
        from fulfillment
        where username=? and orderid=?
        }
  ) or die "Can't do: $DBI::errstr";
  $sth->execute( "$mckutils::query{'publisher-name'}", "$mckutils::query{'orderID'}" )
    or die "Can't execute: $DBI::errstr";
  my $rv = $sth->bind_columns( undef, \( $itemid, $product ) );
  while ( $sth->fetch ) {

    #@product = (@product,$product);
    $product[ ++$#product ] = "$product";
  }

  #($itemid,$product) = $sth->fetchrow;
  $sth->finish;

  my $itemcnt = 0;
  if ( !exists $mckutils::query{'max'} ) {
    $itemcnt = $mckutils::max;
  } else {
    $itemcnt = $mckutils::query{'max'};
  }
  if ( $itemid eq "" ) {
    for ( my $i = 1 ; $i <= $itemcnt ; $i++ ) {
      my ($cnt);
      if ( $mckutils::query{"quantity$i"} < 1 ) {
        next;
      }
      my $item = $mckutils::query{"item$i"};
      my $sth  = $dbh->prepare(
        qq{
          select itemid,product
          from fulfillment
          where username=? and sku=? and orderid='available'
          }
      ) or die "Can't do: $DBI::errstr";
      $sth->execute( "$mckutils::query{'publisher-name'}", "$item" )
        or die "Can't execute: $DBI::errstr";
      my $rv = $sth->bind_columns( undef, \( $itemid, $product ) );
      while ( $sth->fetch ) {
        $cnt++;

        #@product = (@product,$product);
        $product[ ++$#product ] = "$product:$i";
        if ( $itemid ne "" ) {
          my $sth1 = $dbh->prepare(
            qq{
             update fulfillment
             set orderid=?
             where username=? and itemid=?
             }
          ) or die "Can't prepare: $DBI::errstr";
          $sth1->execute( "$mckutils::query{'orderID'}", "$mckutils::query{'publisher-name'}", "$itemid" );
          $sth1->finish;
        }
        last if ( $cnt >= $mckutils::query{"quantity$i"} );
      }
      $sth->finish;
    }
  }
  $dbh->disconnect;

  return @product;

}

# Duplicated for the most part in remote.pm - Need to evaluate best place for this subroutine. 01/23/2002
sub mimic_authnet_input {
  my (%query) = @_;
  $query{'card-number'} = $query{'ccNum'};
  $query{'card-zip'}    = $query{'ZIP'};
  $query{'card-amount'} = $query{'amount'};
  my ( $mo, $yr ) = split( '/', $query{'x_Exp_Date'} );
  if ( length($mo) == 1 ) {
    $query{'card-exp'} = "0$mo" . "/" . substr( $query{'x_Exp_Date'}, -2 );
  } else {
    $query{'card-exp'} = "$mo" . "/" . substr( $query{'x_Exp_Date'}, -2 );
  }
  $query{'publisher-name'} = $query{'x_merchant'};
  $query{'card-name'}      = "$query{'x_Card_Name'}";
  $query{'card-address1'}  = $query{'x_Address'};
  $query{'card-number'}    = $query{'x_Card_Num'};
  $query{'card-city'}      = $query{'x_City'};
  $query{'card-state'}     = $query{'x_State'};
  $query{'card-zip'}       = $query{'x_Zip'};
  $query{'card-country'}   = $query{'x_Country'};
  $query{'orderID'}        = $query{'x_InvoiceNum'};
  $query{'card-amount'}    = $query{'x_Amount'};
  $query{'shipname'}       = "$query{'x_Ship_to_First_Name'} $query{'x_Ship_To_Last_Name'}";
  $query{'address1'}       = $query{'x_Ship_To_Address'};
  $query{'city'}           = $query{'x_Ship_To_City'};
  $query{'state'}          = $query{'x_Ship_To_State'};
  $query{'zip'}            = $query{'x_Ship_To_Zip'};
  $query{'country'}        = $query{'x_Ship_To_Country'};
  $query{'phone'}          = $query{'x_Phone'};
  $query{'email'}          = $query{'x_Email'};

  if ( ( $query{'x_ADC_Relay_Response'} =~ /^true$/i )
    && ( exists $query{'x_ADC_URL'} ) ) {
    $query{'success-link'} = $query{'x_ADC_URL'};
    $query{'problem-link'} = $query{'x_ADC_URL'};
    $query{'badcard-link'} = $query{'x_ADC_URL'};
  }

  return %query;
}

sub goBackToPayscreens {
  my $postLink            = @_[0];
  my $serverName          = $ENV{'SERVER_NAME'};
  my $uri                 = URI->new($postLink);

  my $finalStatusLinkHost;
  if ($uri->can("host")) {
    $finalStatusLinkHost = $uri->host;
  } else {
    # local links do not have a host name, so set finalStatusLinkHost as serverName
    $finalStatusLinkHost = $serverName;
  }

  return $serverName eq $finalStatusLinkHost;
}

sub output_generic {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my ( $message, %headers ) = @_;
  my ( $header, $respcode );

  # Delete payscreens cookie (by setting expired cookie) so it can't be reused
  my $query  = new CGI();
  my $cookie = $query->cookie(
    -name    => 'payscreens',
    -value   => '',
    -expires => '-1d',
    -path    => '/',
    -host    => $ENV{'HTTP_HOST'}
  );

  if ( ref($message) ne '' ) {
    if ( $mckutils::result{'FinalStatus'} eq 'success' ) {
      $message = "Your transaction was successful, but there was an error generating the response page.";
    } else {
      $message = "Your transaction was not successful.  In addition, there was an error generating the response page.";
    }
  }

  my $postLink = undef;
  if ( $mckutils::result{'FinalStatus'} eq "fraud" ) {
    $postLink = $mckutils::query{'badcard-link'};
  } else {
    $postLink = $mckutils::query{"$mckutils::result{'FinalStatus'}-link"};
  }
  $postLink =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\|]/x/g;

  # Generate new payscreens cookie if not success and going back to payscreens
  my $finalStatus         = $mckutils::result{'FinalStatus'};
  my $goBackToPayscreens  = &goBackToPayscreens($postLink);

  if ( $finalStatus ne 'success' && $goBackToPayscreens ) {
    my $time       = new PlugNPay::Sys::Time('unix');
    my $cookieData = {
      'username'          => $mckutils::query{'publisher-name'},
      'time'              => $time,
      'ipAddress'         => $remote_ip,
      'payscreensVersion' => 'mcktuils'
    };
    my $cookieObject = new PlugNPay::PayScreens::Cookie();
    $cookie = $cookieObject->createEncryptedCookie(
      { 'name'  => 'payscreens',
        'value' => $cookieData,
        'host'  => $ENV{'HTTP_HOST'}
      }
    );
  }

  if ( ( $headers{'httpresponse'} =~ /302/ )
    && ( $headers{'location'} =~ /^https?\:\/\// ) ) {
    $header  = "Location: $headers{'location'}";
    $message = "";
  } elsif ( $respcode =~ /^(afdfdf|afdfds)$/ ) {
    $header = "";
  } else {
    $header = $query->header( -cookie => $cookie );
  }

  if (0) {
    my $mytime = localtime( time() );
    open( TMPFILE, ">>/home/p/pay1/database/debug/formpostproxy2A.txt" );
    print TMPFILE "$mytime,  RA:$remote_ip,  PID:$$, UN:$mckutils::query{'publisher-name'}, RPROXY:$mckutils::feature{'formpostproxy'}\n";
    foreach my $key ( sort keys %headers ) {
      print TMPFILE "Key:$key,$headers{$key}\n";
    }
    print TMPFILE "HEADER:$header:\n";
    print TMPFILE "MESSAGE:$message:\n";
    close(TMPFILE);
  }

  print "$header\n\n";
  print "$message";
  exit;
}

sub output_authnet {

  if ( $mckutils::result{'FinalStatus'} eq "success" ) {
    $mckutils::query{'x_response_code'} = "1";
    $mckutils::query{'x_auth_code'}     = $mckutils::result{'auth-code'};

    #code of 1 is authorization, others are declines or errors, reason in x_response_reason_text)";
  } else {
    $mckutils::query{'x_response_code'}        = "0";
    $mckutils::query{'x_response_reason_text'} = $mckutils::result{'MErrMsg'};
  }
  $mckutils::query{'x_amount'}   = $mckutils::query{'card-amount'};
  $mckutils::query{'x_avs_code'} = $mckutils::result{'avs-code'};
  $mckutils::query{'x_trans_id'} = $mckutils::query{'orderID'};
  ( $mckutils::query{'x_first_name'}, $mckutils::query{'x_last_name'} ) =
    split( / /, $mckutils::query{'card-name'} );
  ( $mckutils::query{'x_ship_to_first_name'}, $mckutils::query{'x_ship_to_last_name'} ) = split( / /, $mckutils::query{'shipname'} );

  my @delete_array = (
    'orderID',         'card-number', 'card-exp',           'card-amount',    'card-name', 'card-address1', 'card-address2', 'card-city',
    'card-state',      'card-zip',    'card-country',       'publisher-name', 'shipname',  'address1',      'city',          'state',
    'zip',             'country',     'phone',              'email',          'MErrMsg',   'auth-code',     'auth-msg',      'merchant',
    'easycart',        'auth_date',   'publisher-password', 'shipinfo',       'currency',  'mode',          'month-exp',     'year-exp',
    'publisher-email', 'card-cvv',    'referrer',           'User-Agent',     'IPaddress', 'x_Card_Num'
  );

  if ( ( $mckutils::query{'x_ADC_Relay_Response'} =~ /^true$/i )
    && ( exists $mckutils::query{'x_ADC_URL'} ) ) {
    foreach my $var (@delete_array) {
      delete $mckutils::query{$var};
      delete $mckutils::result{$var};
    }
    $mckutils::query{'success-link'} = $mckutils::query{'x_ADC_URL'};
    $mckutils::query{'badcard-link'} = $mckutils::query{'x_ADC_URL'};
    $mckutils::query{'problem-link'} = $mckutils::query{'x_ADC_URL'};
    $mckutils::query{'fraud-link'}   = $mckutils::query{'x_ADC_URL'};

    &final();
    exit;
  } elsif ( ( ( $mckutils::query{'x_ADC_Delim_Data'} =~ /^true$/i ) && ( $mckutils::query{'x_ADC_URL'} =~ /^false$/i ) )
    || ( $mckutils::query{'client'} =~ /^(dydacomp|dallasmust)$/ ) ) {

    my @resp1 = (
      'x_response_code',      'x_response_subcode',  'x_response_reason_code', 'x_response_reason_text', 'x_auth_code',    'x_avs_code',
      'x_trans_id',           'x_invoice_num',       'x_description',          'x_amount',               'x_method',       'x_type',
      'x_cust_id',            'x_first_name',        'x_last_name',            'x_company',              'x_address',      'x_city',
      'x_state',              'x_zip',               'x_country',              'x_phone',                'x_fax',          'x_email',
      'x_ship_to_first_name', 'x_ship_to_last_name', 'x_ship_to_company',      'x_ship_to_address',      'x_ship_to_city', 'x_ship_to_state',
      'x_ship_to_zip',        'x_ship_to_country',   'x_tax',                  'x_duty',                 'x_freight',      'x_tax_exempt',
      'x_po_num',             'x_MD5_hash',          'x_cvv2_resp_code'
    );

    my %resp2 = (
      'x_response_code',        "$mckutils::query{'x_response_code'}",      'x_response_subcode',     '',
      'x_response_reason_code', "$mckutils::query{'respcode'}",             'x_response_reason_text', "$mckutils::query{'x_response_reason_text'}",
      'x_auth_code',            "$mckutils::query{'x_auth_code'}",          'x_avs_code',             "$mckutils::result{'avs-code'}",
      'x_trans_id',             "$mckutils::query{'orderID'}",              'x_invoice_num',          "$mckutils::query{'order-id'}",
      'x_description',          '',                                         'x_amount',               "$mckutils::query{'x_amount'}",
      'x_method',               '',                                         'x_type',                 '',
      'x_cust_id',              '',                                         'x_first_name',           "$mckutils::query{'x_first_name'}",
      'x_last_name',            "$mckutils::query{'x_last_name'}",          'x_company',              "$mckutils::query{'card-company'}",
      'x_address',              "$mckutils::query{'card-address1'}",        'x_city',                 "$mckutils::query{'card-city'}",
      'x_state',                "$mckutils::query{'card-state'}",           'x_zip',                  "$mckutils::query{'card-zip'}",
      'x_country',              "$mckutils::query{'card-country'}",         'x_phone',                "$mckutils::query{'phone'}",
      'x_fax',                  "$mckutils::query{'fax'}",                  'x_email',                "$mckutils::query{'email'}",
      'x_ship_to_first_name',   "$mckutils::query{'x_ship_to_first_name'}", 'x_ship_to_last_name',    "$mckutils::query{'x_ship_to_last_name'}",
      'x_ship_to_company',      "$mckutils::query{'company'}",              'x_ship_to_address',      "$mckutils::query{'address1'}",
      'x_ship_to_city',         "$mckutils::query{'city'}",                 'x_ship_to_state',        "$mckutils::query{'state'}",
      'x_ship_to_zip',          "$mckutils::query{'zip'}",                  'x_ship_to_country',      "$mckutils::query{'country'}",
      'x_tax',                  "$mckutils::query{'tax'}",                  'x_duty',                 '',
      'x_freight',              "$mckutils::query{'shipping'}",             'x_tax_exempt',           '',
      'x_po_num',               '',                                         'x_MD5_hash',             '',
      'x_cvv2_resp_code',       "$mckutils::query{'cvvresp'}"
    );

    my ($resp);

    foreach my $var (@resp1) {
      $resp .= "$resp2{$var},";
    }

    my $length = length($resp);

    #print "Content-Length: $length\r\n";
    #if (! exists $ENV{'MOD_PERL'}) {
    #  print "Content-Length: $length\r\n";
    #}

    #print "Content-Type: text/html\r\n\r\n";
    print header( -type => 'text/html', -Content_length => "$length" );    ### DCP 20100719
    print "$resp\n";

    exit;
  }
}

sub mimic_authnet_output {

}

sub shopdata {
  my $j = 1;
  my ( $subtotal, $taxsubtotal, $totalcnt, $totalwgt );
  my ( @item, @description, @quantity, @cost, @weight, @ext, @taxable );
  if ( $mckutils::query{'subtotal'} > 0 ) {
    $mckutils::query{'subtotal'} = 0;
  }
  if ( $mckutils::query{'totalwgt'} > 0 ) {
    $mckutils::query{'totalwgt'} = 0;
  }
  if ( $mckutils::query{'taxsubtotal'} > 0 ) {
    $mckutils::query{'taxsubtotal'} = 0;
  }
  for ( my $i = 1 ; $i <= 1000 ; $i++ ) {
    if ( $mckutils::query{"quantity$i"} > 0 ) {
      $item[$j]        = $mckutils::query{"item$i"};
      $description[$j] = $mckutils::query{"description$i"};
      $quantity[$j]    = $mckutils::query{"quantity$i"};
      $quantity[$j] =~ s/[^0-9\.]//g;
      $cost[$j] = $mckutils::query{"cost$i"};
      $cost[$j] =~ s/[^0-9\.\-]//g;
      $weight[$j]    = $mckutils::query{"weight$i"};
      $mckutils::max = $j;
      $ext[$j]       = ( $cost[$j] * $quantity[$j] );
      $mckutils::query{'subtotal'} += ( $quantity[$j] * $cost[$j] );

      # put taxable field into array for later use
      $taxable[$j] = $mckutils::query{"taxable$i"};

      if ( $mckutils::query{"taxable$i"} !~ /N/i ) {
        $mckutils::query{'taxsubtotal'} +=
          ( $quantity[$j] * $cost[$j] );
      }

      $totalcnt += $quantity[$j];
      if ( $weight[$j] > 0 ) {

        #$totalwgt += ($quantity[$j] * $weight[$j]);
        $mckutils::query{'totalwgt'} += ( $quantity[$j] * $weight[$j] );
      }
      $j++;
    }
    delete $mckutils::query{"item$i"};
    delete $mckutils::query{"quantity$i"};
    delete $mckutils::query{"cost$i"};
    delete $mckutils::query{"description$i"};
    delete $mckutils::query{"weight$i"};
  }

  $mckutils::query{'subtotal'} =
    sprintf( "%.2f", $mckutils::query{'subtotal'} );
  $mckutils::query{'taxsubtotal'} =
    sprintf( "%.2f", $mckutils::query{'taxsubtotal'} );

  $mckutils::query{'ordrcnt'} = $j;
  for ( my $i = 1 ; $i <= $j ; $i++ ) {
    $mckutils::query{"item$i"}        = $item[$i];
    $mckutils::query{"quantity$i"}    = $quantity[$i];
    $mckutils::query{"cost$i"}        = $cost[$i];
    $mckutils::query{"description$i"} = $description[$i];
    $mckutils::query{"weight$i"}      = $weight[$i];
  }
}

sub calculate_discnt {
  my (@discountarray) = $mckutils::query{'promoid'};

  if ( $mckutils::query{'promoid'} eq "" ) {
    return;
  }

  my ( $temp, $promoid, $promocode, $limit, $count, $cnt, $expires, $status, $discounttotal, $errmsg, @codes );
  my ( $discount, $disctype, $usetype, $minpurchase, $sku );

  my ( undef, $datestr, $timestr ) = &miscutils::gendatetime();

  my $qstr = "select promoid,promocode,use_limit,use_count,expires,status from promo_coupon ";
  $qstr .= "where username=? ";
  my @placeholder = ("$mckutils::query{'publisher-name'}");

  foreach my $promoid (@discountarray) {
    $promoid =~ s/[^0-9a-zA-Z ]//g;
    $temp .= "promoid=? or ";
    push( @placeholder, "$promoid" );
  }
  $temp = substr( $temp, 0, length($temp) - 3 );

  $qstr .= "and ($temp) ";

  if ( $mckutils::query{'subacct'} ne "" ) {
    $qstr .= "and subacct=? ";
    push( @placeholder, "$mckutils::query{'subacct'}" );
  }

  #print "QSTR:$qstr<br>\n";

  my $dbh = &miscutils::dbhconnect('merch_info');

  my $sth = $dbh->prepare(qq{$qstr}) or die "Can't do: $DBI::errstr";
  $sth->execute(@placeholder) or die "Can't do: $DBI::errstr";
  $sth->bind_columns( undef, \( $promoid, $promocode, $limit, $count, $expires, $status ) );
  while ( $sth->fetch ) {

    #print "BBB: ID:$promoid, CD:$promocode, LM:$limit, CNT:$count, EXP:$expires, ST:$status, DATE:$datestr<br>\n";
    if ( $expires < $datestr ) {
      $errmsg .= "Coupon Code:$promoid, Offer expired.|";
      next;
    } elsif ( $status =~ /cancel/ ) {
      $errmsg .= "Coupon Code:$promoid, Offer canceled.|";
      next;
    } elsif ( ( $count > $limit ) && ( $limit ne "" ) ) {
      $errmsg .= "Coupon Code:$promoid, Use count exceeded.|";
      next;
    }
    $cnt++;
    push @codes, $promocode;
  }

  $sth->finish;

  if ( $cnt < 1 ) {
    $dbh->disconnect();
    return;
  }

  $qstr = "select discount,disctype,usetype,status,minpurchase,sku from promo_offers ";
  $qstr .= "where username=? ";
  @placeholder = ("$mckutils::query{'publisher-name'}");

  $temp = "";
  foreach my $promocode (@codes) {

    #print "A:$promocode<br>\n";
    $temp .= "promocode='$promocode' or ";
  }
  $temp = substr( $temp, 0, length($temp) - 3 );

  $qstr .= "and ($temp) ";

  if ( $mckutils::query{'subacct'} ne "" ) {
    $qstr .= "and subacct=? ";
    push( @placeholder, "$mckutils::query{'subacct'}" );
  }

  $sth = $dbh->prepare(qq{$qstr})
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", 'QSTR', $qstr, %mckutils::query );
  $sth->execute(@placeholder)
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", 'QSTR', $qstr, %mckutils::query );
  $sth->bind_columns( undef, \( $discount, $disctype, $usetype, $status, $minpurchase, $sku ) );
  while ( $sth->fetch ) {
    $sku =~ s/[^a-zA-Z0-9\-\_\ \*]//g;
    $sku =~ s/\*/\./g;

    #print "DSCNT:$discount, DSCTYPE:$disctype, USETYPE:$usetype, ST:$status, MINP:$minpurchase, SKU:$sku<br>\n";
    if ( $expires < $datestr ) {
      $errmsg .= "Coupon Code:$promoid, Offer expired.|";
      next;
    }
    if ( $sku ne "" ) {
      for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {

        #print "VAR:$var<br>\n";
        if ( ( $mckutils::query{"item$i"} =~ /$sku/ )
          && ( $mckutils::query{'subtotal'} > $minpurchase )
          && ( $status !~ /cancel/ ) ) {
          if ( $disctype eq "cert" ) {
            $discounttotal += $mckutils::query{"cost$i"} * $mckutils::query{"quantity$i"};
          } elsif ( $disctype eq "amt" ) {
            $discounttotal += $discount * $mckutils::query{"quantity$i"};
          } elsif ( $disctype eq "pct" ) {
            $discounttotal += ( $mckutils::query{"cost$i"} * $discount ) * $mckutils::query{"quantity$i"};
          }
        }
      }
      last;
    } else {
      if ( ( $mckutils::query{'subtotal'} > $minpurchase )
        && ( $status !~ /cancel/ ) ) {
        if ( $disctype eq "amt" ) {
          $discounttotal += $discount;
        } elsif ( $disctype eq "pct" ) {
          $discounttotal += ( $mckutils::query{'subtotal'} * $discount );
        }
        last;
      }
    }
  }
  $sth->finish;

  $dbh->disconnect();

  if ( $discounttotal > $mckutils::query{'subtotal'} ) {
    $discounttotal = $mckutils::query{'subtotal'};
    $mckutils::query{'subtotal'} = 0;
  } else {
    $mckutils::query{'subtotal'} -= $discounttotal;
  }

  if ( $discounttotal > 0 ) {
    $mckutils::query{'discnt'} = sprintf( "%.2f", $discounttotal );
  }

  return $discounttotal;
}

sub recurring_record {
  my ($database);
  if ( $mckutils::query{'merchantdb'} ne "" ) {
    $database = $mckutils::query{'merchantdb'};
  } else {
    $database = $mckutils::query{'publisher-name'};
  }
  my $dbh_cust = &miscutils::dbhconnect("$database");
  my $sth      = $dbh_cust->prepare(
    qq{
       select password
       from customer
       where username=? and password=?
  }
  ) or die "Can't prepare: $DBI::errstr";
  $sth->execute( $mckutils::query{'username'}, $mckutils::query{'password'} )
    or die "Can't execute: $DBI::errstr";
  my ($password) = $sth->fetchrow;
  $sth->finish;
  $dbh_cust->disconnect;

  if ( $password ne "" ) {
    $mckutils::recurring{'match'} = 1;
    $mckutils::query{'uname'}     = $mckutils::query{'username'};
    $mckutils::query{'passwrd1'}  = $password;
  }
}

sub call_remote {
  if ( $mckutils::query{'success-link'} =~ /^http/ ) {
    if ( $mckutils::query{'success-link'} !~ /\.html?$/ ) {
      my $hasher = new PlugNPay::Util::Hash();
      $hasher->add( $mckutils::query{'passwrd1'} );
      $mckutils::query{'passwrd1'} = $hasher->bcrypt();
      if ( $mckutils::feature{'bcrypt_php_compat'} ) {
        $mckutils::query{'passwrd1'} =~ s/^\$2a/\$2y/;
      }

      my ($pairs);
      my %param =
        ( 'username', "$mckutils::query{'uname'}", 'password', "$mckutils::query{'passwrd1'}", 'end', "$mckutils::recurring{'expire'}", 'purchaseid', "$mckutils::query{'purchaseid'}", 'mode', 'new' );
      my @addlparams = split( '\|', $mckutils::recurring{'addlparams'} );
      foreach my $var (@addlparams) {
        %param = ( %param, $var, "$mckutils::query{$var}" );
      }
      foreach my $key ( keys %param ) {
        my $name  = $key;
        my $value = $param{$key};
        $name =~ s/([^ \w*])/sprintf("%%%2.2X",ord($1))/ge;
        $value =~ s/([^ \w*])/sprintf("%%%2.2X",ord($1))/ge;
        $name =~ s/ /+/g;
        $value =~ s/ /+/g;
        if ( $value ne "" ) {
          $pairs .= "$name=$value\&";
        }
      }
      my ( $response, %headers );
      my $postLink = undef;
      $postLink = $mckutils::query{'success-link'};
      $postLink =~ s/[^a-zA-Z0-9_\.\/\@:\-\~\?\&\=\|]/x/g;
      my (%result1);
    my $rl = new PlugNPay::ResponseLink( $mckutils::query{'merchant'}, $postLink, $pairs, 'post', 'meta' );
      $rl->doRequest();
      $response = $rl->getResponseContent;
      %headers  = $rl->getResponseHeaders;

      &output_generic( "$response", "%headers" );
    } else {
      &final();
    }
  } else {
    ## Response for invalid success-link here
    $mckutils::query{'success-link'} = '';
    &final();
  }
}

sub strdata {
  my ($database);

  if ( $mckutils::query{'merchantdb'} ne "" ) {
    $database = $mckutils::query{'merchantdb'};
  } else {
    $database = $mckutils::query{'publisher-name'};
  }

  my $time = time();
  my ( $eday, $emonth, $eyear, $sday, $smonth, $syear );
  if ( ( $mckutils::feature{'rec_localtime'} == 1 )
    && ( $mckutils::feature{'settletimezone'} ne "" ) ) {
    ( undef, undef, undef, $sday, $smonth, $syear ) =
      gmtime( $time + ( $mckutils::feature{'settletimezone'} * 3600 ) );
  } else {
    ( undef, undef, undef, $sday, $smonth, $syear ) = gmtime($time);
  }
  $smonth = $smonth + 1;
  $syear  = $syear + 1900;

  # extend membership, when username's membership is still active
  if ( ( $mckutils::query{'username'} ne "" )
    && ( $mckutils::query{'password'} ne "" )
    && ( $mckutils::query{'renewal'} eq "yes" ) ) {
    my @now = ();
    if ( ( $mckutils::feature{'rec_localtime'} == 1 )
      && ( $mckutils::feature{'settletimezone'} ne "" ) ) {
      @now =
        gmtime( $time + ( $mckutils::feature{'settletimezone'} * 3600 ) );
    } else {
      @now = gmtime($time);
    }
    my $today =
      sprintf( "%04d%02d%02d", $now[5] + 1900, $now[4] + 1, $now[3] );
    my $today_time = &cal2sec( 0, 0, 0, $now[3], $now[4] + 1, $now[5] + 1900 );    # enddate in GMT Epoch Seconds

    # get enddate of existing username
    my $dbh_cust = &miscutils::dbhconnect("$database");
    my $sth      = $dbh_cust->prepare(
      qq{
        select enddate
        from customer
        where username=? and password=?
      }
    ) or die "Can't prepare: $DBI::errstr";
    $sth->execute( "$mckutils::query{'username'}", "$mckutils::query{'password'}" )
      or die "Can't execute: $DBI::errstr";
    my ($enddate) = $sth->fetchrow;
    $sth->finish;
    $dbh_cust->disconnect;

    # now figure out weather membership is active or expired
    if ( $enddate >= $today ) {

      # when membership is active, figure out how many days are remaining on membership
      my $end_year  = substr( $enddate, 0, 4 );
      my $end_month = substr( $enddate, 4, 2 );
      my $end_day   = substr( $enddate, 6, 2 );
      my $end_time = &cal2sec( 0, 0, 0, $end_day, $end_month, $end_year );    # enddate in GMT Epoch Seconds

      my $days_left = ( $end_time - $today_time ) / 86400;                    # 1 Day = 86400 Seconds
      $days_left = ceil($days_left);

      # add that amount of time to the the payment plans days field
      $mckutils::recurring{'days'} = $mckutils::recurring{'days'} + $days_left;
    }
  }

  if ( ( $mckutils::feature{'rec_localtime'} == 1 )
    && ( $mckutils::feature{'settletimezone'} ne "" ) ) {
    ( undef, undef, undef, $eday, $emonth, $eyear ) = gmtime( $time + ( $mckutils::recurring{'days'} * 3600 * 24 ) + ( $mckutils::feature{'settletimezone'} * 3600 ) );
  } else {
    ( undef, undef, undef, $eday, $emonth, $eyear ) =
      gmtime( $time + ( $mckutils::recurring{'days'} * 3600 * 24 ) );
  }
  $emonth = $emonth + $mckutils::recurring{'months'};
  $eyear  = $eyear + 1900 + ( ( $emonth - ( $emonth % 12 ) ) / 12 );
  $emonth = ( $emonth % 12 ) + 1;

  $mckutils::recurring{'expire'} = sprintf( "%04d%02d%02d", $eyear, $emonth, $eday );

  my $monthday = substr( $mckutils::recurring{'expire'}, 4, 4 );
  if ( ( ( $monthday > "0930" ) && ( $monthday < "1001" ) )
    || ( ( $monthday > "0430" ) && ( $monthday < "0501" ) )
    || ( ( $monthday > "0630" ) && ( $monthday < "0701" ) )
    || ( ( $monthday > "1130" ) && ( $monthday < "1201" ) )
    || ( ( $monthday > "0228" ) && ( $monthday < "0301" ) ) ) {
    my $expiremonth = substr( $mckutils::recurring{'expire'}, 4, 2 ) + 1;
    if ( $expiremonth > 12 ) {
      $mckutils::recurring{'expire'} = sprintf( "%04d%02d%02d", substr( $mckutils::recurring{'expire'}, 0, 4 ) + 1, $expiremonth - 12, 1 );
    } else {
      $mckutils::recurring{'expire'} = sprintf( "%04d%02d%02d", substr( $mckutils::recurring{'expire'}, 0, 4 ), $expiremonth, 1 );
    }
  }
  $mckutils::recurring{'start'} = sprintf( "%04d%02d%02d", $syear, $smonth, $sday );

  my $cc            = new PlugNPay::CreditCard( $mckutils::query{'card-number'} );
  my $shacardnumber = $cc->getCardHash();

  my ( $enccardnumber, $encryptedDataLen ) = &rsautils::rsa_encrypt_card( $mckutils::query{'card-number'}, "/home/p/pay1/pwfiles/keys/key" );

  $mckutils::query{'card-number'} = substr( $mckutils::query{'card-number'}, 0, 4 ) . '**' . substr( $mckutils::query{'card-number'}, length( $mckutils::query{'card-number'} ) - 2, 2 );

  my %length_hash = (
    'username', '54', 'plan',     '19', 'name',      '39', 'addr1',     '39', 'addr2',    '39', 'balance',      '8',  'country', '39', 'billcycle',   '9',  'startdate',  '9',
    'enddate',  '9',  'city',     '39', 'state',     '39', 'zip',       '13', 'monthly',  '8',  'cardnumber',   '26', 'exp',     '10', 'orderid',     '22', 'purchaseid', '19',
    'password', '15', 'shipname', '39', 'shipaddr1', '39', 'shipaddr2', '39', 'shipcity', '39', 'shipstate',    '39', 'shipzip', '13', 'shipcountry', '39', 'phone',      '15',
    'fax',      '10', 'email',    '39', 'status',    '10', 'acct_code', '25', 'order-id', '22', 'billusername', '23'
  );

  my %map_hash = (
    'name',      'card-name',  'addr1',   'card-address1', 'addr2',       'card-address2', 'country',   'card-country', 'city',     'card-city',
    'state',     'card-state', 'zip',     'card-zip',      'shipaddr1',   'address1',      'shipaddr2', 'address2',     'shipcity', 'city',
    'shipstate', 'state',      'shipzip', 'zip',           'shipcountry', 'country',       'monthly',   'recurringfee'
  );

  my ( $db_name, $db_length, $balanceflag, $billunflag );

  my $dbh = &miscutils::dbhconnect("$database");

  my ($a);
  my $sth = $dbh->prepare(
    qq{
    describe customer
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
  $sth->execute()
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
  $sth->bind_columns( undef, \( $db_name, $db_length, $a, $a, $a, $a ) );

  while ( $sth->fetch ) {
    $db_name = lc $db_name;
    $db_length =~ s/[^0-9]//g;
    if ( $db_length > 5 ) {
      $length_hash{$db_name} = $db_length - 1;
    }
    if ( $db_name eq "balance" ) {
      $balanceflag = 1;
    }
    if ( $db_name eq "billusername" ) {
      $billunflag = 1;
    }
  }
  $sth->finish();

  if ( ( $mckutils::query{'currency'} ne "" )
    && ( $length_hash{'monthly'} >= 11 ) ) {
    my $amount = $mckutils::query{'recurringfee'};
    $mckutils::query{'recurringfee'} = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $amount );
  }

  foreach my $testvar ( keys %length_hash ) {
    if ( exists $map_hash{$testvar} ) {
      if ( length( $mckutils::query{ $map_hash{$testvar} } ) > $length_hash{$testvar} ) {
        $mckutils::query{ $map_hash{$testvar} } = substr( $mckutils::query{ $map_hash{$testvar} }, 0, $length_hash{$testvar} );
      }
    } else {
      if ( length( $mckutils::query{$testvar} ) > $length_hash{$testvar} ) {
        $mckutils::query{$testvar} = substr( $mckutils::query{$testvar}, 0, $length_hash{$testvar} );
      }
    }
  }

  if ( $mckutils::recurring{'match'} == 1 ) {
    if ( $mckutils::result{'Duplicate'} ne "yes" ) {
      $enccardnumber = &smpsutils::storecardnumber( $database, $mckutils::query{'username'}, 'strdata', $enccardnumber, 'rec' );

      my $sth = $dbh->prepare(
        qq{
            update customer set enddate=?,cardnumber=?,exp=?,enccardnumber=?,length=?,status='active',plan=?,billcycle=?,monthly=?,balance=?,purchaseid=?
            where username=?
            }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
      $sth->execute(
        "$mckutils::recurring{'expire'}", "$mckutils::query{'card-number'}", "$mckutils::query{'card-exp'}",  "$enccardnumber",
        "$encryptedDataLen",              "$mckutils::query{'plan'}",        "$mckutils::query{'billcycle'}", "$mckutils::query{'recurringfee'}",
        "$mckutils::query{'balance'}",    "$mckutils::query{'purchaseid'}",  "$mckutils::query{'username'}"
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
      $sth->finish;

      my $sth_billing = $dbh->prepare(
        qq{
            insert into billingstatus
            (username,trans_date,amount,orderid,descr,result)
            values (?,?,?,?,?,?)
      }
      ) or die "Can't prepare: $DBI::errstr";
      $sth_billing->execute(
        "$mckutils::query{'username'}",
        "$mckutils::recurring{'start'}",
        "$mckutils::query{'card-amount'}",
        "$mckutils::query{'orderID'}", "Renewal", "$mckutils::result{'FinalStatus'}"
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
      $sth_billing->finish;
    }
  } else {
    if ( $mckutils::result{'Duplicate'} ne "yes" ) {

      $enccardnumber = &smpsutils::storecardnumber( $database, $mckutils::query{'uname'}, 'strdata', $enccardnumber, 'rec' );

      my $sth = $dbh->prepare(
        qq{
        insert into customer
        (username,orderid,purchaseid,plan,password,name,addr1,addr2,city,state,zip,country,shipname,shipaddr1,shipaddr2,shipcity,shipstate,shipzip,shipcountry,phone,fax,email,startdate,enddate,monthly,cardnumber,enccardnumber,length,exp,billcycle,lastbilled,status,acct_code,shacardnumber,balance,billusername)
        values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        }
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
      $sth->execute(
        $mckutils::query{'uname'},            "$mckutils::query{'orderID'}",   "$mckutils::query{'purchaseid'}",  "$mckutils::query{'plan'}",
        $mckutils::query{'passwrd1'},         $mckutils::query{'card-name'},   $mckutils::query{'card-address1'}, $mckutils::query{'card-address2'},
        $mckutils::query{'card-city'},        $mckutils::query{'card-state'},  $mckutils::query{'card-zip'},      $mckutils::query{'card-country'},
        $mckutils::query{'shipname'},         $mckutils::query{'address1'},    $mckutils::query{'address2'},      $mckutils::query{'city'},
        $mckutils::query{'state'},            $mckutils::query{'zip'},         $mckutils::query{'country'},       $mckutils::query{'phone'},
        $mckutils::query{'fax'},              $mckutils::query{'email'},       $mckutils::recurring{'start'},     $mckutils::recurring{'expire'},
        $mckutils::recurring{'recurringfee'}, $mckutils::query{'card-number'}, "$enccardnumber",                  "$encryptedDataLen",
        $mckutils::query{'card-exp'},         $mckutils::query{'billcycle'},   $mckutils::recurring{'start'},     $mckutils::query{'status'},
        "$mckutils::query{'acct_code'}",      "$shacardnumber",                "$mckutils::query{'balance'}",     "$mckutils::query{'billacct'}"
        )
        or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
      $sth->finish;
    }
  }

  if ( ( $mckutils::query{'publisher-name'} =~ /^(boudin)$/ )
    && ( $mckutils::query{'commcardtype'} ne "" ) ) {
    my $sth = $dbh->prepare(
      qq{
      update customer set commcardtype=?,ponumber=?
      where username=?
    }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
    $sth->execute( "business", "$mckutils::query{'ponumber'}", "$mckutils::query{'uname'}" )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query );
    $sth->finish;
  }

  $dbh->disconnect;
}

sub email {
  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('startEmail');
  }

  my %info_hash = ();
  $info_hash{'query'}            = \%mckutils::query;
  $info_hash{'result'}           = \%mckutils::result;
  $info_hash{'feature'}          = \%mckutils::feature;
  $info_hash{'fraud_config'}     = \%fraud::fraud_config;
  $info_hash{'emailextrafields'} = \@mckutils::emailextrafields;
  $info_hash{'reseller'}         = $mckutils::reseller;
  $info_hash{'esub'}             = $mckutils::esub;

  my $emailconf = emailconfutils->new( \%info_hash );

  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('postEmailConf');
  }

  # send customer confirmation if non-duplicate as defined by fraud.pm
  my $dupchkstatus = $mckutils::result{'dupchkstatus'};
  if ( !defined $dupchkstatus || $dupchkstatus eq '' ) {
    $emailconf->send_email("conf");
  }

  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('postSendCustomerEmail');
  }

  # send merchant confirmation
  # 09/15/10 - permits selective sending of merchant confirmations, based on FinalStatus.
  # When not defined, all emails are sent to merchant, regradless of FinalStatus
  if ( ( $mckutils::feature{'sndemailstatus'} ne "" )
    && ( $mckutils::result{'FinalStatus'} !~ /^($mckutils::feature{'sndemailstatus'})$/i ) ) {
    return;
  } else {
    $emailconf->send_email("merch");
  }

  if ( $mckutils::accountFeatures->get('enhancedLogging') == 1 ) {
    new PlugNPay::Logging::Performance('postSendMerchantEmail');
  }
}

sub pick_template {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my $time = gmtime(time);
  open( DEBUG, ">>/home/p/pay1/database/debug/pick_template_subroutine.txt" );
  print DEBUG "TIME:$time, RA:$remote_ip, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, ";
  print DEBUG "PORT:$ENV{'SERVER_PORT'}, PID:$$, CT:$mckutils::cardtype, RM:$ENV{'REQUEST_METHOD'}\n";
  close(DEBUG);

  #use Datalog
  my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
  $logger->log(
    { 'TIME'   => $time,
      'RA'     => $remote_ip,
      'SCRIPT' => $ENV{'SCRIPT_NAME'},
      'HOST'   => $ENV{'SERVER_NAME'},
      'PORT'   => $ENV{'SERVER_PORT'},
      'PID'    => $$,
      'CT'     => $$mckutils::cardtype,
      'RM'     => $ENV{'REQUEST_METHOD'}
    }
  );

  my ($email_type) = @_;

  # controls what email template is opened for parsing
  my $message_to_use = "";

  # used to count the number of items the user has purchased
  # and to choose the proper email template.  This is probably done some
  # where else and possibly could be moved out of here.
  my $quantity_total = 0;

  my $path_mark           = "/home/p/pay1/markfiles/";
  my $email_template_path = "$mckutils::path_webtxt/emailconf/templates/";

  # contains items and there values and is used for
  # the item test to choose an email template
  my %item_list = ();

  my $emailconftablespace = "emailconf";

  # get an array together of items and total quantity to be used in deciding
  # which template to use
  foreach my $key ( sort keys %mckutils::query ) {
    if ( $key =~ /item/ ) {
      $item_list{$key} = $mckutils::query{$key};
    } elsif ( $key =~ /quantity/ ) {
      $quantity_total += $mckutils::query{$key};
    }
  }

  my $dbh_email = &miscutils::dbhconnect($emailconftablespace);

  my %templatehash = ();

  #the file name of the template stored in $email_template_path
  my $body;

  # rules for deciding which template to use
  my $include;

  # type confirmation or marketing
  my $type;

  # type of email to send HTML or Text
  my $emailformat;

  # weighting of template used for deciding which template to use
  my $weight;

  # delay for sending marketing emails
  my $delay;

  # ?
  my $data;

  my $sth_email = $dbh_email->prepare(
    qq{
       select body,include,type,emailtype,weight,delay,data
       from emailconf
       where username in (?,?) and type=?
       order by include desc
  }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckkutils::query );
  $sth_email->execute( $mckutils::query{'subacct'}, $mckutils::query{'publisher-name'}, $email_type )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query );
  $sth_email->bind_columns( undef, \( $body, $include, $type, $emailformat, $weight, $delay, $data ) );

  my $found_subacct = "no";
  while ( $sth_email->fetch ) {
    $body =~ s/\r//g;
    if ( ( $body =~ /$mckutils::query{'subacct'}/ )
      && ( $mckutils::query{'subacct'} ne "" ) ) {
      $found_subacct = "yes";
    }
    $templatehash{$body}{'include'}     = $include;
    $templatehash{$body}{'type'}        = $type;
    $templatehash{$body}{'emailformat'} = $emailformat;
    $templatehash{$body}{'weight'}      = $weight;
    $templatehash{$body}{'delay'}       = $delay;
    $templatehash{$body}{'data'}        = $data;
  }
  $sth_email->finish;
  $dbh_email->disconnect;

  if ( $found_subacct eq "yes" ) {
    for $body ( keys %templatehash ) {
      if ( $body =~ /$mckutils::query{'publisher-name'}/ ) {
        delete $templatehash{$body};
      }
    }
  }    # end found_subacct if
       # done creating %templatehash

  # really convulted sort used here to take care of sorting of include statements
  # first quantity then item then cost should hit.  based on mast algs in perl p117
  foreach $body ( reverse sort { return $templatehash{$a}{'include'} cmp $templatehash{$b}{'include'} } keys %templatehash ) {
    if ( $message_to_use eq "" ) {
      my ( $what, $operator, $value, $subject ) =
        split( /\:/, $templatehash{$body}{'include'} );

      if ( $what eq "paymethod" ) {
        if ( $mckutils::query{'paymethod'} eq $value ) {
          $message_to_use = $body;
          last;
        }
      } elsif ( $what eq "item" ) {

        # foreach goes through list of items purchased and compares the include
        # test to see if it matches if it does it sets message_to_use and dumps
        # out of the test item loop
        foreach my $testitem ( keys %item_list ) {
          if ( $item_list{$testitem} eq $value ) {
            $message_to_use = $body;
            last;
          }
        }
      } elsif ( $what eq "plan" ) {
        if ( $mckutils::query{'plan'} eq $value ) {
          $message_to_use = $body;
          last;
        }
      } elsif ( $what eq "order-id" ) {
        if ( $mckutils::query{'order-id'} eq $value ) {
          $message_to_use = $body;
          last;
        }
      } elsif ( $what eq "subacct" ) {
        if ( $mckutils::query{'subacct'} eq $value ) {
          $message_to_use = $body;
          last;
        }
      } elsif ( $what eq "quantity" ) {
        if ( $operator eq "lt" ) {
          if ( $quantity_total < $value ) {
            $message_to_use = $body;
            last;
          }
        } elsif ( $operator eq "gt" ) {
          if ( $quantity_total > $value ) {
            $message_to_use = $body;
            last;
          }
        } elsif ( $operator eq "eq" ) {
          if ( $quantity_total == $value ) {
            $message_to_use = $body;
            last;
          }
        }
      } elsif ( $what eq "cost" ) {
        if ( $operator eq "lt" ) {
          if ( $mckutils::query{'card-amount'} < $value ) {
            $message_to_use = $body;
            last;
          }
        } elsif ( $operator eq "gt" ) {
          if ( $mckutils::query{'card-amount'} > $value ) {
            $message_to_use = $body;
            last;
          }
        } elsif ( $operator eq "eq" ) {
          if ( $mckutils::query{'card-amount'} == $value ) {
            $message_to_use = $body;
            last;
          }
        }    # end operator if
      }    # end what if
    }    # end message to use if
  }    # end foreach body loop

  # if we haven't found a match we use pnp default email message
  # this needs to be fixed no worky
  if ( $message_to_use eq "" ) {
    if ( $email_type eq "conf" ) {
      $message_to_use = "email.msg";
    } elsif ( $email_type eq "merch" ) {
      $message_to_use = "merchant.msg";
    }
    $templatehash{$message_to_use}{'include'}     = "none";
    $templatehash{$message_to_use}{'type'}        = $email_type;
    $templatehash{$message_to_use}{'emailformat'} = "text";
    $templatehash{$message_to_use}{'weight'}      = "";
    $templatehash{$message_to_use}{'delay'}       = "0,none";
    my $path_file = "$mckutils::path_webtxt/emailconf/templates/$message_to_use";
    $path_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    &sysutils::filelog( "read", "$path_file" );
    open( INFILE, "$path_file" );

    while (<INFILE>) {
      $templatehash{$message_to_use}{'data'} .= $_;
    }
    close INFILE;
  }

  return $templatehash{$message_to_use};
}

sub generate_email {    ###  480 Lines
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my $time = gmtime(time);
  open( DEBUG, ">>/home/p/pay1/database/debug/generate_email_subroutine.txt" );
  print DEBUG "TIME:$time, RA:$remote_ip, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, ";
  print DEBUG "PORT:$ENV{'SERVER_PORT'}, PID:$$, CT:$mckutils::cardtype, RM:$ENV{'REQUEST_METHOD'}\n";
  close(DEBUG);

  #use Datalog
  my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
  $logger->log(
    { 'TIME'   => $time,
      'RA'     => $remote_ip,
      'SCRIPT' => $ENV{'SCRIPT_NAME'},
      'HOST'   => $ENV{'SERVER_NAME'},
      'PORT'   => $ENV{'SERVER_PORT'},
      'PID'    => $$,
      'CT'     => $$mckutils::cardtype,
      'RM'     => $ENV{'REQUEST_METHOD'}
    }
  );

  my ($templatehash) = @_;
  if ( !defined $templatehash ) {
    return;
  }
  my $parseflag = "";

  my (%suppress_if_blank);
  if ( $mckutils::feature{'suppress'} eq "yes" ) {
    my @suppress_if_blank = ( 'agent', 'order-id', 'subtotal' );
    foreach my $var (@suppress_if_blank) {
      $suppress_if_blank{$var} = 1;
    }
  }

  # message body
  my $message      = "";
  my @productarray = ();
  my @looparray    = ();
  my ($pnploopcnt);

  my $bcc = "custmail\@plugnpay.com";

  if ( ( $mckutils::query{'cc-email'} ne "" )
    && ( $mckutils::query{'cc-mail'} eq "" ) ) {
    $mckutils::query{'cc-mail'} = $mckutils::query{'cc-email'};
  }

  if ( $mckutils::reseller eq "paybyweb" ) {
    $mckutils::query{'ff-email'} = "pnpmerchants\@paybyweb.com";
  }

  if ( $mckutils::result{'FinalStatus'} eq "success" ) {
    $bcc = $bcc . ", $mckutils::query{'ff-email'}";
  }

  my $reseller = new PlugNPay::Reseller($mckutils::reseller);

  #start getting the email together for the customer
  if ( ( $mckutils::result{'FinalStatus'} eq "success" )
    || ( $templatehash->{'type'} eq "merch" ) ) {

    # variables to hold values until they are set in emailObj
    my $emailFrom;
    my $emailTo;
    my $emailBCC;
    my $emailCC;
    my $emailSubject;

    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setGatewayAccount( $mckutils::query{'publisher-name'} );

    my $position = index( $mckutils::query{'email'}, "\@" );
    if (
      (    ( $position > 1 )
        && ( length( $mckutils::query{'email'} ) > 5 )                   # is this supposed to be some half assed email validation?
        && ( $position < ( length( $mckutils::query{'email'} ) - 5 ) )
      )
      || ( $templatehash->{'type'} eq "merch" )
      ) {
      if ( $templatehash->{'emailformat'} eq "html" ) {

        # add extra header junk for HTML email
        $message .=
          "Content-Type: text/html; name=\"mail.htm\"\nContent-Disposition: inline\; filename=\"mail.htm\"\nContent-Transfer-Encoding: quoted-printable\nMime-Version: 1.0\nX-Mailer: MIME-tools 4.104 (Entity 4.117)\n";
      }

      if ( $templatehash->{'type'} eq "merch" ) {
        $emailTo = $mckutils::query{'publisher-email'};
      } else {
        $emailTo = $mckutils::query{'email'};
      }

      if ( $templatehash->{'type'} eq "conf" ) {
        if ( $mckutils::query{'from-email'} ne "" ) {
          $emailFrom = $mckutils::query{'from-email'};
        } else {
          $emailFrom = $mckutils::query{'publisher-email'};
        }
      } else {
        if ( $mckutils::query{'email'} ne "" ) {
          $emailFrom = $mckutils::query{'email'};
        } else {
          if ( $mckutils::reseller eq "electro" ) {
            $emailFrom = 'paymentserver@eci-pay.com';
          } elsif ( $mckutils::reseller eq "paymentd" ) {
            $emailFrom = 'support@paymentdata.com';
          } else {
            my $emailDomain = $reseller->getEmailDomain();
            $emailFrom = "paymentserver\@$emailDomain";
          }
        }
      }

      if ( ( $mckutils::query{'cc-mail'} ne "" )
        && ( $templatehash->{'type'} eq "merch" ) ) {
        $emailCC = "$mckutils::query{'cc-mail'}";
      }

      if ( ( $bcc ne "" ) && ( $templatehash->{'type'} eq "merch" ) ) {
        $emailBCC = "$bcc";
      }

      my $dup = "";
      if ( $mckutils::result{'Duplicate'} eq "yes" ) {
        $dup = " - Resend";
      }

      my ( $what, $type, $name, $subject ) =
        split( /\:/, $templatehash->{'include'}, 4 );
      chomp $subject;

      if ( $subject ne "" ) {
        $emailSubject = "$subject $dup";
      } elsif ( ( $mckutils::query{'subject-email'} ne "" )
        && ( $templatehash->{'type'} eq "conf" ) ) {
        $emailSubject = "$mckutils::query{'subject-email'} $dup";
      } elsif ( ( $mckutils::query{'subject'} ne "" )
        && ( $templatehash->{'type'} eq "merch" ) ) {
        $emailSubject = "$mckutils::query{'subject'} $mckutils::query{'card-name'} $mckutils::result{'FinalStatus'}";
      } else {
        if ( $templatehash->{'type'} eq "conf" ) {
          $emailSubject = "Purchase Confirmation $dup";
        } elsif ( $templatehash->{'type'} eq "merch" ) {
          $emailSubject = "$mckutils::esub - $mckutils::query{'card-name'} $mckutils::result{'FinalStatus'} notification $dup";
        }
      }

      $emailObj->setTo($emailTo);
      $emailObj->setFrom($emailFrom);
      $emailObj->setCC($emailCC)   if $emailCC;
      $emailObj->setBCC($emailBCC) if $emailBCC;
      $emailObj->setSubject($emailSubject);

      if ( $mckutils::result{'Duplicate'} eq "yes" ) {
        $message .= "This is a resend of your confirmation email.\n\n";
      }

      my @message_data = split( /(\n)/, $templatehash->{'data'} );
      my $begin_flag   = "0";
      my $line         = "";
      my ($blanklineflag);
      my ($email_purchase_header);
    MSGLINE: foreach $line (@message_data) {
        if ( $line !~ /\w/ ) {
          $blanklineflag = 1;
        } else {
          $blanklineflag = 0;
        }
        if ( $begin_flag ne "1" ) {
          my $parsecount = 0;
          while ( $line =~ /\[pnp_([0-9a-zA-Z-+_]*)\]/ ) {
            my $query_field = $1;
            $parsecount += 1;
            if ( $mckutils::query{$query_field} ne "" ) {
              if ( ( $query_field eq "card-number" )
                || ( $query_field eq "card_number" ) ) {
                $line =~ s/\[pnp_$query_field\]/$mckutils::filteredCC/;
              } elsif ( $query_field eq "accountnum" ) {
                $line =~ s/\[pnp_$query_field\]/$mckutils::filteredAN/;
              } elsif ( $query_field eq "routingnum" ) {
                $line =~ s/\[pnp_$query_field\]/$mckutils::filteredRN/;
              } elsif ( ( $query_field eq "card-exp" )
                || ( $query_field eq "card_exp" ) ) {
                $line =~ s/\[pnp_$query_field\]//;
              } elsif ( $query_field eq "ssnum" ) {
                $line =~ s/\[pnp_$query_field\]/$mckutils::filteredSSN/;
              } elsif ( $query_field eq "discnt" ) {
                if ( $mckutils::query{$query_field} eq "" ) {
                  next;
                }
                $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $mckutils::query{$query_field})/e;
              } elsif ( $query_field eq "subtotal" ) {
                $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $mckutils::query{$query_field})/e;
              } elsif ( $query_field eq "tax" ) {
                $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $mckutils::query{$query_field})/e;
              } elsif ( $query_field eq "shipping" ) {
                $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $mckutils::query{$query_field})/e;
              } else {
                $line =~ s/\[pnp_$query_field\]/$mckutils::query{$query_field}/;
              }
            } else {
              if ( $line =~ /\[pnp_date\]|\[pnp_date([+-])([0-9]*)\]/ ) {
                my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst );
                if ( ( $1 eq "" ) && ( $2 eq "" ) ) {
                  ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
                  $line =~ s/\[pnp_date\]|\[pnp_date([+-])([0-9]*)\]/sprintf("%02d\/%02d\/%04d",$mon+1,$mday,$year+1900)/e;
                } elsif ( ( $1 eq "+" ) && ( $2 ne "" ) ) {
                  ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time() + ( $2 * 24 * 3600 ) );
                  $line =~ s/\[pnp_date\]|\[pnp_date([+-])([0-9]*)\]/sprintf("%02d\/%02d\/%04d",$mon+1,$mday,$year+1900)/e;
                } elsif ( ( $1 eq "-" ) && ( $2 ne "" ) ) {
                  ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time() - ( $2 * 24 * 3600 ) );
                  $line =~ s/\[pnp_date\]|\[pnp_date([+-])([0-9]*)\]/sprintf("%02d\/%02d\/%04d",$mon+1,$mday,$year+1900)/e;
                }
              } elsif ( $query_field eq "discnt" ) {
                if ( $mckutils::query{$query_field} eq "" ) {
                  next MSGLINE;
                }
              }
            }
            if ( $parsecount >= 10 ) {
              next MSGLINE;
            }
          }    # end while
        }    # end begin_flag if
        if ( $line =~ /\[email_([^\W]*)_begin\]/ ) {
          if ( ( $1 eq "shipping" )
            && ( $mckutils::query{'shipinfo'} ne "0" ) ) {
            next MSGLINE;
          } else {
            $begin_flag = "1";
            next MSGLINE;
          }
        }
        if ( $line =~ /\[email_([^\W]*)_end\]/ ) {
          $begin_flag = "0";
          next MSGLINE;
        }
        if ( ( $line =~ /\[email_purchase_header\]/ )
          && ( $mckutils::query{'easycart'} eq "1" ) ) {
          $email_purchase_header = 'omit';
          next MSGLINE;
        }
        if ( ( $line =~ /\[email_purchase_table\]/ )
          && ( $mckutils::query{'easycart'} eq "1" ) ) {
          if ( $templatehash->{'emailformat'} eq "html" ) {
            $message .= "<table>\n";
            if ( $email_purchase_header ne 'omit' ) {
              $message .= "<TR align=left><TH>MODEL NO.</TH>      <TH>QTY</TH>   <TH> CHARGE</TH>   <TH>DESCRIPTION</TH></TR>\n";
            }

            $line = "";
            for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {
              if ( $mckutils::query{"quantity$i"} > 0 ) {
                $message .=
                    "<TR align=left><TD>"
                  . $mckutils::query{"item$i"}
                  . "</TD>      <TD>"
                  . $mckutils::query{"quantity$i"}
                  . "</TD>     <TD>"
                  . sprintf( "%.2f", ( $mckutils::query{"cost$i"} * $mckutils::query{"quantity$i"} ) )
                  . "</TD>      <TD>"
                  . $mckutils::query{"description$i"}
                  . "</TD></TR>\n";
              }    # end quantity if
            }
            $message .= "</table>\n";
          }    # end html if
          else {
            my @purchase_table_header;
            if ( $email_purchase_header ne 'omit' ) {
              @purchase_table_header = ( 'MODEL NO.', 'QTY', 'CHARGE', 'DESCRIPTION' );
            }
            my $purchase_table = Text::Table->new(@purchase_table_header);

            $line = "";
            for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {
              if ( $mckutils::query{"quantity$i"} > 0 ) {
                $purchase_table->add( $mckutils::query{"item$i"}, $mckutils::query{"quantity$i"}, $mckutils::query{"cost$i"}, $mckutils::query{"description$i"} );
              }    # end quantity if
            }    # end for max loop
            $message .= $purchase_table;
          }    # end text else
        }    # end email_purchase_table if
        elsif ( $line =~ /\[email_purchase_table\]/ ) {
          $line = "";
        }

        if ( ( $templatehash->{'type'} eq "merch" )
          && ( $line =~ /\[email_merchant_variables\]/ ) ) {
          if ( $mckutils::query{'comments'} ne "" ) {
            $mckutils::query{'comments'} =~ s/\&quot\;/\"/g;
            if ( $mckutils::query{'comm-title'} ne "" ) {
              $message .= $mckutils::query{'comm-title'} . "\n";
            } else {
              $message .= "Comments \&/or Special Instructions:\n";
            }
            $message .= $mckutils::query{'comments'} . "\n\n";
          }

          if ( $mckutils::result{'FinalStatus'} eq "success" ) {
            if ( $mckutils::query{'paymethod'} eq "check" ) {
            } elsif ( $mckutils::query{'paymethod'} eq "onlinecheck" ) {
              $message .= "Payment Method: Online Check\n";
            } else {
              if ( $mckutils::trans_type ne "storedata" ) {
                if ( $mckutils::query{'paymethod'} eq "onlinecheck" ) {
                  $message .= "Electronic Debit was successful\n";
                } else {
                  $message .= "Credit Card Authorization was successful\n";
                  $message .= "Authorization Code: " . substr( $mckutils::result{'auth-code'}, 0, 6 ) . "\n";
                  my %cvv_hash = ( 'M', 'Match', 'N', 'Did not match.', 'P', 'Not able to be processed.', 'U', 'Unavailable for checking.', 'X', 'Unavailable for checking.' );
                  if ( ( $mckutils::result{'cvvresp'} ne "" )
                    && ( $mckutils::query{'card-cvv'} ne "" ) ) {
                    $message .= "CVV2/CVC2 - Response Code: $cvv_hash{$mckutils::result{'cvvresp'}}\n";
                  }
                  my $avs = substr( $mckutils::result{'avs-code'}, 0, 3 );
                  $avs = substr( $avs, -1, 1 );
                  $message .= "AVS - Response Code:$avs\n";
                  $message .= ${ $mckutils::avs_responses{$avs} }[1] . "\n";
                  $message .= "Card Type: $mckutils::query{'card-type'}\n";
                }
              }
            }

            if ( $mckutils::pnp_debug eq "yes" ) {
              $message .= "WARNING: THIS TRANSACTION HAS BEEN FORCED SUCCESSFUL FOR \n";
              $message .= "DEBUGGING AND TESTING PURPOSES ONLY.  IF THIS IS NOT YOUR INTENT PLEASE CONTACT \n";
              $message .= "THE TECHNICAL SUPPORT STAFF IMMEDIATELY. \n";
            }

            my $cf = new PlugNPay::Util::CardFilter( $mckutils::query{'card-number'} );

            if ( $mckutils::query{'showextrafields'} ne "no" ) {
              foreach my $key ( sort keys %mckutils::query ) {
                my ( $field_name, $field_value ) = $cf->filterPair( $key, $mckutils::query{$key}, 1 );
                if ( ( $key !~ /^(FinalStatus|success|auth-code|auth_date)$/ )
                  && ( $key !~ /MErrMsg/ )
                  && ( $key !~ /card-/ )
                  && ( $key !~ /^(phone|fax|email)$/ )
                  && ( $key !~ /^(shipinfo|shipsame|shipname|address1|address2|city|state|zip|country)$/ )
                  && ( $key !~ /^(shipping|tax|taxrate|taxstate|subtotal)$/ )
                  && ( $key !~ /^(currency|year-exp|month-exp|magstripe|TrakData|track|x_track|card-number|card_num|cardnumber|magensacc|emvtags)/i )
                  && ( $key !~ /^(accountnum|routingnum|checknum|accttype)$/ )
                  && ( $key !~ /^(publisher-name|publisher-password|merchant|User-Agent|referrer)$/ )
                  && ( $key !~ /^(publisher-email|cc-mail|from-email|subject|message|dontsndmail)$/ )
                  && ( $mckutils::query{$key} ne "subject-email" )
                  && ( $key !~ /^(comm-title|comments|order-id)$/ )
                  && ( $key !~ /^(orderid)/i )
                  && ( $key !~ /^(path_cgi|path-softcart|path-postorder)$/ )
                  && ( $key !~ /^(pnppassword|pnpusername)$/ )
                  && ( $key !~ /^cookie_pw\d/ )
                  && ( $key !~ /item|quantity|cost|description/ )
                  && ( $key !~ /^(easycart|max|pass|image-link|image-placement)$/ )
                  && ( $key !~ /^(required|requirecompany|nocountrylist|nofraudcheck|app-level|client|client1|acct_code4)$/ )
                  && ( $key !~ /^(success-link|badcard-link|problem-link)$/ )
                  && ( $key !~ /^(submit|return)$/ )
                  && ( $mckutils::query{$key} ne "continue" )
                  && ( $key !~ /^(merchantdb|billcycle|passwrd1|passwrd2)$/ )
                  && ( $key !~ /roption|plan/ )
                  && ( $key !~ /^(pnp-query|storename|sname|slink|area|x|y)$/ )
                  && ( $key !~ /^(test-wgt|total-wgt|total-cnt)$/ )
                  && ( $mckutils::query{$key} ne "" ) ) {
                  $message .= "Merchant Variable: $field_name: $field_value\n";
                }
              }
            } else {
              foreach my $var (@mckutils::emailextrafields) {
                my ( $field_name, $field_value ) = $cf->filterPair( $var, $mckutils::query{$var}, 1 );
                $message .= "Merchant Variable: $field_name: $field_value\n";
              }
            }
          }
          if ( $mckutils::result{'FinalStatus'} eq "badcard" ) {
            if ( $mckutils::query{'paymethod'} eq "onlinecheck" ) {
              $message .= "Electronic Debit failed: $mckutils::result{'MErrMsg'}\n";
            } else {
              $message .= "Credit Card Authorization failed: Bad Card: $mckutils::result{'MErrMsg'}\n";
            }
          } elsif ( $mckutils::result{'FinalStatus'} ne "success" ) {
            if ( $mckutils::result{'MErrMsg'} =~ /Payment Server Host failed to respond/i ) {
              $mckutils::result{'MErrMsg'} = "The processor for this merchant is currently experiencing temporary delays.  Please try again in a few minutes.";
            }

            if ( $mckutils::query{'paymethod'} eq "onlinecheck" ) {
              $message .= "Electronic Debit failed: $mckutils::result{'MErrMsg'}\n";
            } else {
              $message .= "Credit Card Authorization failed: $mckutils::result{'MErrMsg'}\n";
            }
          }
          $line = "";
        }
        if ( ( $line =~ /\[products\]/ )
          && ( $mckutils::query{'easycart'} eq "1" ) ) {
          $line      = "";
          $parseflag = 1;
          next MSGLINE;
        }    # end email_purchase_table if
             # [products] tag is used for fulfillment
        elsif ( $line =~ /\[\/products\]/ ) {
          $line      = "";
          $parseflag = 0;
          for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {
            foreach my $product_line (@productarray) {
              my $parsecount = 0;
              while ( $product_line =~ /\[prod\_([0-9a-zA-Z-+]*)\]/ ) {
                my $query_field = $1;
                $parsecount += 1;
                if ( $mckutils::query{"$query_field$i"} ne "" ) {
                  $product_line =~ s/\[prod\_([0-9a-zA-Z-+]*)\]/$mckutils::query{"$query_field$i"}/;
                }
                if ( $parsecount >= 20 ) {
                  next MSGLINE;
                }
              }
              $message .= $product_line;
            }    # end quantity if
          }    # end for max loop
        } elsif ( $parseflag == 1 ) {
          $productarray[ ++$#productarray ] = "$line";
          next MSGLINE;
        }

        if ( ( $line =~ /\[emailloop_([0-9a-zA-Z-+_]*)\]/ ) ) {
          $line       = "";
          $parseflag  = 2;
          $pnploopcnt = $mckutils::query{$1};
          next MSGLINE;
        }    # end email_purchase_table if
             # [products] tag is used for fulfillment
        elsif ( $line =~ /\[\/emailloop\]/ ) {
          $line      = "";
          $parseflag = 0;
          for ( my $i = 1 ; $i <= $pnploopcnt ; $i++ ) {
            foreach my $loop_line (@looparray) {
              my $product_line = $loop_line;
              my $parsecount   = 0;
              while ( $product_line =~ /\[loopline_([0-9a-zA-Z-+_]*)\]/ ) {
                my $query_field = $1;
                $parsecount += 1;
                if ( $mckutils::query{"$query_field$i"} ne "" ) {
                  $product_line =~ s/\[loopline_$query_field\]/$mckutils::query{"$query_field$i"}/;
                }
                if ( $parsecount >= 20 ) {
                  next MSGLINE;
                }
              }
              $message .= $product_line;
            }    # end quantity if
          }    # end for max loop
        } elsif ( $parseflag == 2 ) {
          $looparray[ ++$#looparray ] = "$line";
          next MSGLINE;
        }

        if ( $begin_flag eq "0" ) {
          $message .= $line;
        }
      }    # end MSGLINE while

      if ( $fraud::fraud_config{'bounced'} >= 1 ) {
        $message .= "\n\n\nTRACKID:$mckutils::orderID:$mckutils::query{'auth_date'}:$mckutils::query{'plan'}";
      }

      $emailObj->setContent($message);
      $emailObj->send();

# hmm ? # $sth_email->execute("$message_time","$mckutils::query{'publisher-name'}","pending","$templatehash->{'emailformat'}","$message") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr",%mckkutils::query);
    }    # end position email if
  }
}

sub dccmsg {
  my (%query) = @_;
  my (%result);
  my %currencyUSDSYM = ( 'AUD', 'A$', 'CAD', 'C$', 'EUR', '&#8364;', 'GBP', '&#163;', 'JPY', '&#165;', 'USD', '$', 'FRF', '&#8355;', 'CHF', 'CHF' );
  my %currency840SYM = ( '036', 'A$', '124', 'C$', '978', '&#8364;', '826', '&#163;', '392', '&#165;', '997', '$', '250', '&#8355;', '756', 'CHF' );

  my ( $merch_curr, $card_curr, $native_amt, $conv_rate, $exponent );

  $merch_curr = $query{'currency'};
  $merch_curr =~ tr/a-z/A-Z/;

  if ( $query{'dccinfo'} =~ /^[a-zA-Z]/ ) {
    if ( $query{'dccinfo'} =~ /\,/ ) {
      ( undef, undef, $card_curr, $conv_rate, $exponent ) =
        split( /\,/, $query{'dccinfo'} );
    } else {
      $card_curr = substr( $query{'dccinfo'}, 13, 3 );
      $conv_rate = substr( $query{'dccinfo'}, 16, 10 ) + 0;
      $exponent  = substr( $query{'dccinfo'}, 26, 1 );
    }
  } else {
    if ( $query{'dccinfo'} =~ /\,/ ) {
      ( undef, $card_curr, $conv_rate, $exponent ) =
        split( /\,/, $query{'dccinfo'} );
    } else {
      $card_curr = substr( $query{'dccinfo'}, 12, 3 );
      $conv_rate = substr( $query{'dccinfo'}, 15, 10 ) + 0;
      $exponent  = substr( $query{'dccinfo'}, 25, 1 );
    }
  }

  #my $card_curr = substr($result{'dccinfo'},12,3);
  ##my $native_amt = substr($result{'dccinfo'},0,12);
  #my $conv_rate = substr($result{'dccinfo'},15,10) + 0;
  #my $exponent = substr($result{'dccinfo'},25,1);

  if (
    ( $query{'publisher-name'} =~ /^(planettest|testplanet)$/ )
    && ( $query{'card-number'} =~
      /(4025241600000007|4000000000000002|5100040000000004|4000000500000007|5100120000000004|4000010200000001|5100060000000002|4000020000000000|5100070000000001|4000030300000009|5100100000000006|4000040000000008|5100110000000005)/
    )
    ) {
    #if (($query{'publisher-name'} eq "planettest") && ($query{'card-number'} eq "4025241600000007")) {
    $merch_curr = "USD";
    if ( $query{'card-number'} =~ /(4025241600000007|4000000500000007|5100120000000004)/ ) {    ## GBP
      $card_curr = "826";
      $conv_rate = "0525028070";
      $exponent  = 9;
    } elsif ( $query{'card-number'} =~ /(4000010200000001|5100060000000002)/ ) {                ## AUD
      $card_curr = "036";
      $conv_rate = "0001342795";
      $exponent  = 6;
    } elsif ( $query{'card-number'} =~ /(4000020000000000|5100070000000001)/ ) {                ## EUR
      $card_curr = "978";
      $conv_rate = "0000784972";
      $exponent  = 6;
    } elsif ( $query{'card-number'} =~ /(4000030300000009|5100100000000006)/ ) {                ## CAD
      $card_curr = "124";
      $conv_rate = "0001120446";
      $exponent  = 6;
    } elsif ( $query{'card-number'} =~ /(4000040000000008|5100110000000005)/ ) {                ## JPY
      $card_curr = "392";
      $conv_rate = "0116820000";
      $exponent  = 6;
    }
    if ( $query{'publisher-name'} =~ /^(testplanet)$/ ) {
      $result{'dcctype'} = "twopass";
      $result{'dccinfo'} = "000000000000$card_curr$conv_rate$exponent";
    }
  }

  $conv_rate = ( $conv_rate / ( 10**$exponent ) );

  my $currencyObj = new PlugNPay::Currency($card_curr);
  $result{'native_sym'} = $currency840SYM{$card_curr};
  $result{'merch_sym'}  = $currencyUSDSYM{$merch_curr};
  my $cur = lc( $currencyObj->getThreeLetter() );

  $native_amt = $currencyObj->format( $mckutils::query{'card-amount'} * $conv_rate + .0001, { digitSeparator => '' } );

  $result{'native_amt'} = $native_amt;
  $result{'conv_rate'}  = $conv_rate;

  $result{'native_isocur'}   = $currencyObj->getCurrencyCode();
  $result{'merchant_isocur'} = $merch_curr;

  if ( $mckutils::query{'dccoptout'} ne "" ) {
    if ( $mckutils::query{'dccoptout'} =~ /^Y$/i ) {
      my $html = "Amount Charged: $result{'merch_sym'} $mckutils::query{'card-amount'}\n";
      $result{'dccemailmsg'} = $html;
    } elsif ( $mckutils::query{'dccoptout'} =~ /^N$/i ) {
      $result{'card-amount'}          = $native_amt;
      $result{'currency'}             = $cur;
      $mckutils::query{'card-amount'} = $native_amt;
      $mckutils::query{'currency'}    = $cur;

      my $html = "Local Amount: $result{'merch_sym'} $mckutils::query{'card-amount'}\n";
      $html .= "Conversion Rate*: $result{'conv_rate'}  $result{'merchant_isocur'}/$result{'native_isocur'}\n";
      $html .= "Transaction Amount in Transaction Currency: $result{'native_isocur'} $result{'native_amt'} \n\n";
      if ( $mckutils::cardtype eq "VISA" ) {
        $html .= "*This rate, which includes a 3% service charge, is comparable to the ";
        $html .= "rate and fees we estimate your credit card issuer would have ";
        $html .= "charged you on your card statement if you chose to pay in US \$. I ";
        $html .= "acknowledge that this service is provided by this merchant for my ";
        $html .= "convenience, that I have been offered a choice of currencies, and ";
        $html .= "that my choice is final. ";
      } elsif ( $mckutils::cardtype eq "MSTR" ) {
        $html .= "*I have chosen not to use the Mastercard currency conversion process and agree that I will ";
        $html .= "have no recourse against Mastercard concerning the currency conversion or its disclosure. ";
      }
      $result{'dccemailmsg'} = $html;
    }
    $mckutils::query{'dccemailmsg'} = $result{'dccemailmsg'};
  } else {
    if ( $result{'dcctype'} eq "twopass" ) {
      my ($account);
      if ( exists $mckutils::query{'origacct'} ) {
        $account = $mckutils::query{'origacct'};
      } else {
        $account = $mckutils::query{'publisher-name'};
      }
      my $html = "<p>As a convenience to our international customers, this purchase can be made in your home currency.<p>\n";
      $html .= "Today\'s exchange rate from $mckutils::query{'currency'} is $conv_rate.<p>\n";
      $html .= "Please select the amount you wish to pay.  Please note that your choice will be final.<p>\n";

      $html .= "<input type=radio name=\"dccoptout\" value=\"N\" checked> $result{'native_sym'} $native_amt<br>\n";
      $html .= "<input type=radio name=\"dccoptout\" value=\"Y\"> $result{'merch_sym'} $query{'card-amount'}\n";
      $html .= "<input type=\"hidden\" name=\"publisher-name\" value=\"$account\"> \n";

      $result{'dccmsg'} = $html;

      $html = "As a convenience to our international customers, this purchase can be made in your home currency. \n";
      $html .= "Today\'s exchange rate from $mckutils::query{'currency'} is $conv_rate.<p>\n";
      $html .= "Please select the amount you wish to pay.  Please note that your choice will be final.<p>\n";

      $result{'dccmsgsimple'} = $html;

      $html = "As a convenience to our international:";
      $html .= "customers, this purchase can be made:";
      $html .= "in your home currency.:";
      $html .= "Today\'s exch. rate from $mckutils::query{'currency'} is $conv_rate:";
      $html .= "Please select the amt you wish to pay.:";
      $html .= "Your choice will be final.:";

      $result{'dccposmsg'} = $html;
    } else {
      my $html = "<input type=radio name=\"dccoptout\" value=\"N\" checked> $result{'native_sym'} $native_amt<br>\n";
      $html .= "<input type=radio name=\"dccoptout\" value=\"Y\"> $result{'merch_sym'} $query{'card-amount'}\n";
      $html .= "<input type=\"hidden\" name=\"publisher-name\" value=\"$mckutils::query{'publisher-name'}\"> \n";
      $html .= "<input type=\"hidden\" name=\"mode\" value=\"dccoptout\"> \n";
      $html .= "<input type=\"hidden\" name=\"orderID\" value=\"$mckutils::query{'orderID'}\"> \n";

      $html .= "<p>As a convenience to our international customers, if you choose to pay for this transaction in your local currency, \n";
      $html .= "we will convert it at a rate of $conv_rate, a rate competitive to that which would otherwise be charged by your card provider. \n";
      $html .= "By choosing your local currency, you understand that $cur will be the transaction currency and your choice will be final.<p>\n";
      $result{'dccmsg'} = $html;

      $html = "As a convenience to our international customers, if you choose to pay for this transaction in your local currency, \n";
      $html .= "we will convert it at a rate of $conv_rate, a rate competitive to that which would otherwise be charged by your card provider. \n";

      $result{'dccmsgsimple'} = $html;
    }
  }

  return %result;

}

sub parse_multicurrency {
  my (%query) = @_;
  my (%result);
  my %currencyUSDSYM = ( 'AUD', 'A$', 'CAD', 'C$', 'EUR', '&#8364;', 'GBP', '&#163;', 'JPY', '&#165;', 'USD', '$', 'FRF', '&#8355;', 'CHF', 'CHF' );
  my %currency840SYM = ( '036', 'A$', '124', 'C$', '978', '&#8364;', '826', '&#163;', '392', '&#165;', '997', '$', '250', '&#8355;', '756', 'CHF' );

  my $merch_curr = $query{'currency'};
  $merch_curr =~ tr/a-z/A-Z/;

  my ( $card_curr, $native_amt, $conv_rate, $exponent );

  if ( $query{'dccinfo'} =~ /^[a-zA-Z]/ ) {
    if ( $query{'dccinfo'} =~ /\,/ ) {
      ( undef, undef, $card_curr, $conv_rate, $exponent ) =
        split( /\,/, $query{'dccinfo'} );
    } else {
      $card_curr = substr( $query{'dccinfo'}, 13, 3 );
      $conv_rate = substr( $query{'dccinfo'}, 16, 10 ) + 0;
      $exponent  = substr( $query{'dccinfo'}, 26, 1 );
    }
  } else {
    if ( $query{'dccinfo'} =~ /\,/ ) {
      ( undef, $card_curr, $conv_rate, $exponent ) =
        split( /\,/, $query{'dccinfo'} );
    } else {
      $card_curr = substr( $query{'dccinfo'}, 12, 3 );
      $conv_rate = substr( $query{'dccinfo'}, 15, 10 ) + 0;
      $exponent  = substr( $query{'dccinfo'}, 25, 1 );
    }
  }

  ## DCP 20101209

  if (
    ( $query{'card-number'} =~
      /(4025241600000007|4000000000000002|5100040000000004|4000000500000007|5100120000000004|4000010200000001|5100060000000002|4000020000000000|5100070000000001|4000030300000009|5100100000000006|4000040000000008|5100110000000005)/
    )
    ) {
    $merch_curr = "USD";
    if ( $query{'currency'} =~ /gbp/i ) {
      $card_curr = "826";
      $conv_rate = "0001889060";
      $exponent  = 6;
    } elsif ( $query{'currency'} =~ /aud/i ) {
      $card_curr = "036";
      $conv_rate = "0000744715";
      $exponent  = 6;
    } elsif ( $query{'currency'} =~ /eur/i ) {
      $card_curr = "978";
      $conv_rate = "0000127393";
      $exponent  = 5;
    } elsif ( $query{'currency'} =~ /cad/i ) {
      $card_curr = "124";
      $conv_rate = "0000892501";
      $exponent  = 6;
    } elsif ( $query{'currency'} =~ /jpy/i ) {
      $card_curr = "392";
      $conv_rate = "0000008488";
      $exponent  = 6;
    } else {
      $card_curr = "978";
      $conv_rate = "0000127393";
      $exponent  = 5;
    }
  }
  $conv_rate = ( $conv_rate / ( 10**$exponent ) );

  my $currencyObj = new PlugNPay::Currency($card_curr);
  $result{'native_sym'} = $currency840SYM{$card_curr};
  $result{'merch_sym'}  = $currencyUSDSYM{$merch_curr};

  $native_amt = $currencyObj->format( $mckutils::query{'card-amount'} * $conv_rate + .0001, { digitSeparator => '' } );

  $result{'native_amt'} = $native_amt;
  $result{'conv_rate'}  = $conv_rate;

  $result{'native_isocur'} = $currencyObj->getCurrencyCode();

  return %result;

}

sub thankyou_template {
  my %query = ( %mckutils::query, %mckutils::result );
  if ( $query{'convert'} =~ /underscores/i ) {
    %query = &miscutils::underscore_to_hyphen(%query);
  }

  return thankyou_template_query( \%query );
}

sub thankyou_template_query {
  my $queryRef = shift;
  my %query    = %{$queryRef};

  my $data = "";

  $data .= "<div align=center>\n";

  ## pre-generate merchant contact section
  my $data_merch = "";
  if ( ( $mckutils::feature{'vtreceipt_company'} == 1 )
    || ( $query{'receipt-company'} ne "" ) ) {
    $data_merch .= "<div align=\"center\">\n";
    if ( $query{'receipt-company'} ne "" ) {
      $data_merch .= "<p><font size=+1><b>[pnp_receipt-company]</b></font>\n";
    }
    if ( $query{'receipt-address1'} ne "" ) {
      $data_merch .= "<br><font size=+1>[pnp_receipt-address1]</font>\n";
    }
    if ( $query{'receipt-address2'} ne "" ) {
      $data_merch .= "<br><font size=+1>[pnp_receipt-address2]</font>\n";
    }
    if ( $query{'receipt-city'} ne "" ) {
      $data_merch .= "<br><font size=+1>[pnp_receipt-city], [pnp_receipt-state] [pnp_receipt-zip] [pnp_receipt-country]</font>\n";
    }
    $data .= "<br>&nbsp;\n";
    if ( $query{'receipt-phone'} ne "" ) {
      $data_merch .= "<br><font size=-1>Phone: [pnp_receipt-phone]</font>\n";
    }
    if ( $query{'receipt-fax'} ne "" ) {
      $data_merch .= "<br><font size=-1>Fax: [pnp_receipt-fax]</font>\n";
    }
    if ( $query{'receipt-email'} ne "" ) {
      $data_merch .= "<br><font size=-1>Email: [pnp_receipt-email]</font>\n";
    }
    if ( $query{'receipt-url'} ne "" ) {
      $data_merch .= "<br><font size=-1>[pnp_receipt-url]</font>\n";
    }
    $data_merch .= "</div>\n";
  }

  ## pre-generate customer section
  my $data_cust = "";
  if ( ( $query{'card-name'} ne "" ) || ( $query{'card-company'} ne "" ) ) {
    $data_cust .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 0px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
    $data_cust .= "<legend style=\"padding: 0px 8px;\"><b>Billing Address</b></legend>\n";
    $data_cust .= "<p>";
    if ( $query{'card-name'} ne "" ) {
      $data_cust .= "[pnp_card-name]<br>\n";
    }
    if ( $query{'card-company'} ne "" ) {
      $data_cust .= "[pnp_card-company]<br>\n";
    }
    if ( $query{'title'} ne "" ) {
      $data_cust .= "[pnp_title]<br>\n";
    }
    if ( $query{'card-address1'} ne "" ) {
      $data_cust .= "[pnp_card-address1]<br>\n";
    }
    if ( $query{'card-address2'} ne "" ) {
      $data_cust .= "[pnp_card-address2]<br>\n";
    }
    if ( $query{'card-city'} ne "" ) {
      $data_cust .= "[pnp_card-city] \n";
    }
    if ( ( $query{'card-state'} ne "" )
      && ( $query{'card-state'} ne "ZZ" ) ) {
      $data_cust .= "[pnp_card-state] \n";
    }
    if ( $query{'card-prov'} ne "" ) {
      $data_cust .= "[pnp_card-prov] \n";
    }
    if ( $query{'card-zip'} ne "" ) {
      $data_cust .= "[pnp_card-zip] \n";
    }
    if ( $query{'card-country'} ne "" ) {
      $data_cust .= "[pnp_card-country]\n";
    }
    $data_cust .= "</p>\n";

    if ( ( $query{'phone'} ne "" )
      || ( $query{'fax'} ne "" )
      || ( $query{'email'} ne "" ) ) {
      $data_cust .= "<p>\n";
      if ( $query{'phone'} ne "" ) {
        $data_cust .= "Phone: [pnp_phone]<br>\n";
      }
      if ( $query{'fax'} ne "" ) {
        $data_cust .= "Fax: [pnp_fax]<br>\n";
      }
      if ( $query{'email'} ne "" ) {
        $data_cust .= "Email: [pnp_email]<br>\n";
      }
      $data_cust .= "</p>\n";
    }

    $data_cust .= "</fieldset>\n";
  }

  ## pre-generate shipping section
  my $data_ship = "";
  if ( ( $query{'shipname'} ne "" ) || ( $query{'shipcompany'} ne "" ) ) {
    $data_ship .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 0px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
    $data_ship .= "<legend style=\"padding: 0px 8px;\"><b>Shipping Address</b></legend>\n";
    $data_ship .= "<p>";
    if ( $query{'shipname'} ne "" ) {
      $data_ship .= "[pnp_shipname]<br>\n";
    }
    if ( $query{'shipcompany'} ne "" ) {
      $data_ship .= "[pnp_shipcompany]<br>\n";
    }
    if ( $query{'address1'} ne "" ) {
      $data_ship .= "[pnp_address1]<br>\n";
    }
    if ( $query{'address2'} ne "" ) {
      $data_ship .= "[pnp_address2]<br>\n";
    }
    if ( $query{'city'} ne "" ) {
      $data_ship .= "[pnp_city] \n";
    }
    if ( ( $query{'state'} ne "" ) && ( $query{'state'} ne "ZZ" ) ) {
      $data_ship .= "[pnp_state] \n";
    }
    if ( $query{'province'} ne "" ) {
      $data_ship .= "[pnp_province] \n";
    }
    if ( $query{'zip'} ne "" ) {
      $data_ship .= "[pnp_zip] \n";
    }
    if ( $query{'country'} ne "" ) {
      $data_ship .= "[pnp_country]\n";
    }
    $data_ship .= "</p>\n";

    if ( ( $query{'shipphone'} ne "" )
      || ( $query{'shipfax'} ne "" )
      || ( $query{'shipemail'} ne "" ) ) {
      $data_ship .= "<p>\n";
      if ( $query{'shipphone'} ne "" ) {
        $data_ship .= "Phone: [pnp_shipphone]<br>\n";
      }
      if ( $query{'shipfax'} ne "" ) {
        $data_ship .= "Fax: [pnp_shipfax]<br>\n";
      }
      if ( $query{'shipemail'} ne "" ) {
        $data_ship .= "Email: [pnp_shipemail]<br>\n";
      }
      $data_ship .= "</p>\n";
    }

    $data_ship .= "</fieldset>\n";
  }

  ## pre-generate query info
  my $data_info = "";
  $data_info .= "<fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 0px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
  $data_info .= "<legend style=\"padding: 0px 8px;\"><b>Order Details</b></legend>\n";
  $data_info .= "<p>Order Date: [pnp_order-date]\n";
  $data_info .= "<br>OrderID: [pnp_orderID]\n";
  if ( $query{'order-id'} =~ /\w/ ) {
    $data_info .= "<br>Merchant ID: [pnp_order-id]\n";
  }
  $data_info .= "</p>\n";
  $data_info .= "</fieldset>\n";

  # start generating the actual query's HTML
  if ( $data_merch ne "" ) {
    $data .= $data_merch;
  }

  $data .= "<table width=\"700\">\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=\"4\"><font size=+1><b>Order Receipt</b></font>\n";
  $data .= "<br>Please print or save this as your receipt.\n";
  $data .= "<br>&nbsp;</td>\n";
  $data .= "  </tr>\n";
  $data .= "  <tr>\n";
  $data .=
    "    <td colspan=\"4\" class=\"quote\">If you have a problem please email us at <a href=\"mailto:[pnp_publisher-email]\">[pnp_publisher-email]</a>.<br>Please give your full name, order ID number, and the exact nature of the problem.</td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  $data .= "    <td colspan=\"4\"><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";

  $data .= "  <tr>\n";
  if ( ( $data_cust ne "" ) && ( $data_ship eq "" ) ) {
    $data .= "    <td colspan=\"2\" width=\"50%\" height=\"100%\">$data_cust</td>\n";
    $data .= "    <td colspan=\"2\" width=\"50%\" height=\"100%\">$data_info</td>\n";
  } elsif ( ( $data_cust eq "" ) && ( $data_ship ne "" ) ) {
    $data .= "    <td colspan=\"2\" width=\"50%\" height=\"100%\">$data_ship</td>\n";
    $data .= "    <td colspan=\"2\" width=\"50%\" height=\"100%\">$data_info</td>\n";
  } else {
    $data .= "    <td colspan=\"2\" width=\"50%\" height=\"100%\"> &nbsp; </td>\n";
    $data .= "    <td colspan=\"2\" width=\"50%\" height=\"100%\">$data_info</td>\n";
  }
  $data .= "  </tr>\n";

  if ( ( $data_cust ne "" ) && ( $data_ship ne "" ) ) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=\"2\" width=\"50%\" height=\"100%\">$data_cust</td>\n";
    $data .= "    <td colspan=\"2\" width=\"50%\" height=\"100%\">$data_ship</td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "  <tr>\n";
  $data .= "    <td colspan=\"4\"><hr width=\"100%\"></td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  $data .= "[TABLE]\n";

  $data .= "<table width=\"700\">\n";
  if ( $query{'easycart'} == 1 ) {
    $data .= "  <tr>\n";
    $data .= "    <td colspan=\"4\"><hr width=\"100%\"></td>\n";
    $data .= "  </tr>\n";
  }

  $data .= "  <tr>\n";
  $data .=
    "    <td width=\"77%\"><fieldset style=\"width: 97%; height: 95%; position: relative; border: 1px solid; margin: none; padding: 0px 5px 0px; background: #eeeeee; -moz-border-radius: 10px;\">\n";
  $data .= "<legend style=\"padding: 0px 8px;\"><b>Payment Details</b></legend>\n";

  if ( $query{'paymethod'} eq "onlinecheck" ) {
    $data .= "<p><b>Routing #:</b> [pnp_filteredRN]\n";
    $data .= "<br><b>Account #:</b> [pnp_filteredAN]\n";
  } else {
    $data .= "<p><b>Card #:</b> [pnp_receiptcc]\n";
    $data .= "<br><b>Card Exp:</b> [pnp_card-exp]\n";
    $data .= "<br><b>Card Type:</b> [pnp_card-type]\n";

    my $authcode = substr( $query{'auth-code'}, 0, 6 );

    $data .= "<br><b>Approval Code:</b> $authcode\n";
  }

  if ( ( $query{'acct_code'} ne "" )
    || ( $query{'acct_code2'} ne "" )
    || ( $query{'acct_code3'} ne "" )
    || ( $query{'acct_code4'} ne "" ) ) {
    $data .= "<p>\n";
    if ( $query{'acct_code'} ne "" ) {
      $data .= "<b>Acct Code:</b> [pnp_acct_code]<br>\n";
    }
    if ( $query{'acct_code2'} ne "" ) {
      $data .= "<br><b>Acct Code2:</b> [pnp_acct_code2]<br>\n";
    }
    if ( $query{'acct_code3'} ne "" ) {
      $data .= "<br><b>Acct Code3:</b> [pnp_acct_code3]<br>\n";
    }
    if ( $query{'acct_code4'} ne "" ) {
      $data .= "<br><b>Acct Code4:</b> [pnp_acct_code4]<br>\n";
    }
    $data .= "</p>\n";
  }
  $data .= "</fieldset></td>\n";
  $data .= "</table>\n";

  if ( $query{'keyswipe'} eq "yes" ) {
    $data .= "<table width=\"700\">\n";
    $data .= "  <tr>\n";
    $data .= "    <td colspan=\"2\"><hr width=\"100%\"></td>\n";
    $data .= "  </tr>\n";

    $data .= "  <tr>\n";
    $data .= "    <td colspan=2>&nbsp;<br>&nbsp;</td>\n";
    $data .= "  </tr>\n";

    $data .= "  <tr>\n";
    $data .= "    <td colspan=2 align=left><b>Signature:</b> _______________________________________________________</td>\n";
    $data .= "  </tr>\n";

    $data .= "  <tr>\n";
    $data .= "    <td colspan=2>&nbsp;<br>&nbsp;</td>\n";
    $data .= "  </tr>\n";
    $data .= "</table>\n";
  }

  $data .= "</td>\n";
  $data .= "  </tr>\n";
  $data .= "</table>\n";

  $data .= "<span class=\"noprint\">\n";
  $data .= "<p><form><input type=\"button\" name=\"print_button\" value=\"Print Page\" onclick=\"window.print();\"></form>\n";

  if ( $query{'receipt_link'} ne "" ) {
    $data .= "<p>To return to site, <a href=\"$query{'receipt_link'}\">CLICK HERE</a>.\n";
  } elsif ( $query{'receipt-link'} ne "" ) {
    $data .= "<p>To return to site, <a href=\"$query{'receipt-link'}\">CLICK HERE</a>.\n";
  }
  $data .= "</span>\n";

  $data .= "</div>\n";

  return $data;
}

sub create_table_for_template {
  my (%query) = @_;
  my $template_table = "";

  $template_table .= "<table width=\"700\" class=\"invoice\">\n";

  if ( ( ( $query{'receipt_type'} eq "itemized" ) || ( $query{'receipt-type'} eq "itemized" ) )
    && ( $query{'easycart'} == 1 ) ) {

    # build itemized product table
    $template_table .= "  <tr bgcolor=\"#f4f4f4\">\n";
    $template_table .= "    <th valign=\"top\" align=\"left\"><p>Product Name</p></th>\n";
    $template_table .= "    <th valign=\"top\" align=\"left\"><p>Qty</p></th>\n";
    $template_table .= "    <th valign=\"top\" align=\"left\"><p>Item \#</p></th>\n";
    $template_table .= "    <th valign=\"top\" align=\"left\"><p>Unit Price</p></th>\n";
    $template_table .= "    <th valign=\"top\" align=\"left\"><p>Price</p></th>\n";
    $template_table .= "  </tr>\n";

    for ( $a = 0 ; $a <= 1000 ; $a++ ) {
      if ( $query{"item$a"} ne "" ) {

        #if (($query{"item$a"} ne "") && ($query{"cost$a"} ne "") && ($query{"description$a"} ne "") && ($query{"quantity$a"} ne "")) {
        $query{"cost$a"} =
          sprintf( "%.2f", $query{"cost$a"} );    # format cost
        my $temp = $query{"cost$a"} * $query{"quantity$a"};    # calculate item total
        $temp = sprintf( "%.2f", $temp );                      # format total

        $template_table .= "  <tr>\n";
        $template_table .= "    <td align=\"left\">$query{\"description$a\"}</td>\n";
        $template_table .= "    <td align=\"left\">$query{\"quantity$a\"}</td>\n";
        $template_table .= "    <td align=\"left\">$query{\"item$a\"}</td>\n";
        $template_table .= "    <td align=\"right\">$query{'currency_symbol'}$query{\"cost$a\"}</td>\n";
        $template_table .= "    <td align=\"right\">$query{'currency_symbol'}$temp</td>\n";
        $template_table .= "  </tr>\n";
      }
    }
  } else {    # defaults to 'simple' receipt_type
              # build simple response
    $template_table .= "  <tr>\n";
    $template_table .= "    <td align=\"center\" colspan=\"5\">Thank You For Your Order.</td>\n";
    $template_table .= "  </tr>\n";
  }

  $template_table .= "  <tr>\n";
  $template_table .= "    <td colspan=\"5\"><hr></td>\n";
  $template_table .= "  </tr>\n";

  if ( $query{'discount'} ne "" ) {
    $query{'discount'} = sprintf( "%.2f", $query{'discnt'} );
    $template_table .= "  <tr>\n";
    $template_table .= "    <td align=\"right\" colspan=\"4\"><b>Discount:&nbsp;</b></td>\n";
    $template_table .= "    <td align=\"right\">$query{'currency_symbol'}$query{'discnt'}</td>\n";
    $template_table .= "  </tr>\n";
  }

  $query{'shipping'} = sprintf( "%.2f", $query{'shipping'} );
  if ( $query{'shipping'} > 0 ) {
    $template_table .= "  <tr>\n";
    $template_table .= "    <td align=\"right\" colspan=\"4\"><b>Shipping:&nbsp;</b></td>\n";
    $template_table .= "    <td align=\"right\">$query{'currency_symbol'}$query{'shipping'}</td>\n";
    $template_table .= "  </tr>\n";
  }

  if ( $query{'handling'} ne "" ) {
    $query{'handling'} = sprintf( "%.2f", $query{'handling'} );
    $template_table .= "  <tr>\n";
    $template_table .= "    <td align=\"right\" colspan=\"4\"><b>Handling:&nbsp;</b></td>\n";
    $template_table .= "    <td align=\"right\">$query{'currency_symbol'}$query{'handling'}</td>\n";
    $template_table .= "  </tr>\n";
  }

  if ( $query{'tax'} ne "" ) {
    $query{'tax'} = sprintf( "%.2f", $query{'tax'} );
    $template_table .= "  <tr>\n";
    $template_table .= "    <td align=\"right\" colspan=\"4\"><b>Sales Tax:&nbsp;</b></td>\n";
    $template_table .= "    <td align=\"right\">$query{'currency_symbol'}$query{'tax'}</td>\n";
    $template_table .= "  </tr>\n";
  }

  $query{'card-amount'} = sprintf( "%.2f", $query{'card-amount'} );
  $template_table .= "  <tr>\n";
  $template_table .= "    <td align=\"right\"colspan=\"4\"><b>Order Total:&nbsp;</b></td>\n";
  $template_table .= "    <td align=\"right\">$query{'currency_symbol'}$query{'card-amount'}</td>\n";
  $template_table .= "  </tr>\n";
  if ( ( $query{'native_amt'} ne "" ) && ( $query{'dccoptout'} eq "N" ) ) {
    $template_table .= "  <tr>\n";
    $template_table .= "    <td align=\"right\"colspan=\"4\"><b>Amount to be charged:&nbsp;</b></td>\n";
    $template_table .= "    <td align=\"right\">$query{'native_isocur'}$query{'native_amt'}</td>\n";
    $template_table .= "  </tr>\n";
  }

  if ( $mckutils::feature{'ask_gratuity'} == 1 ) {
    $template_table .= "  <tr>\n";
    $template_table .= "    <td align=\"right\"colspan=\"4\"><b>Gratuity:&nbsp;</b></td>\n";
    $template_table .= "    <td align=\"right\">____________________</td>\n";
    $template_table .= "  </tr>\n";

    $template_table .= "  <tr>\n";
    $template_table .= "    <td align=\"right\"colspan=\"4\"><b>Total \+ Gratuity:&nbsp;</b></td>\n";
    $template_table .= "    <td align=\"left\">____________________</td>\n";
    $template_table .= "  </tr>\n";
  }

  $template_table .= "</table>\n";

  return $template_table;
}

sub pos_template {
  my %query = ( %mckutils::query, %mckutils::result );
  if ( $query{'convert'} =~ /underscores/i ) {
    %query = &miscutils::underscore_to_hyphen(%query);
  }

  return pos_template_query( \%query );
}

sub pos_template_query {
  my $queryRef = shift;
  my %query    = %{$queryRef};

  my $template_data = "";

  ## Added DCP 20041217
  $template_data .= "<div align=\"left\">\n";

  $template_data .= "<font size=+1><b>Order Receipt</b></font>\n";

  if ( $query{'receipt-company'} ne "" ) {
    $template_data .= "<p><font size=+1><b>[pnp_receipt-company]</b></font>\n";
  }
  if ( $query{'receipt-address1'} ne "" ) {
    $template_data .= "<br><font size=+1>[pnp_receipt-address1]</font>\n";
  }
  if ( $query{'receipt-address2'} ne "" ) {
    $template_data .= "<br><font size=+1>[pnp_receipt-address2]</font>\n";
  }
  if ( $query{'receipt-city'} ne "" ) {
    $template_data .= "<br><font size=+1>[pnp_receipt-city], [pnp_receipt-state] [pnp_receipt-zip] [pnp_receipt-country]</font>\n";
  }
  $template_data .= "<br>&nbsp;\n";
  if ( $query{'receipt-phone'} ne "" ) {
    $template_data .= "<br><font size=-1>Phone: [pnp_receipt-phone]</font>\n";
  }
  if ( $query{'receipt-fax'} ne "" ) {
    $template_data .= "<br><font size=-1>Fax: [pnp_receipt-fax]</font>\n";
  }
  if ( $query{'receipt-email'} ne "" ) {
    $template_data .= "<br><font size=-1>Email: [pnp_receipt-email]</font>\n";
  }
  if ( $query{'receipt-url'} ne "" ) {
    $template_data .= "<br><font size=-1>[pnp_receipt-url]</font>\n";
  }
  $template_data .= "</div>\n";

  $template_data .= "<p><b>Order Date:</b> [pnp_order-date]\n";
  $template_data .= "<br><b>Order ID:</b> [pnp_orderID]\n";
  if ( $query{'order-id'} ne "" ) {
    $template_data .= "<br><b>Merchant ID:</b> [pnp_order-id]\n";
  }

  $template_data .= "<p><hr>\n";
  $template_data .= "[TABLE]\n";

  if ( ( ( $query{'receipt_type'} =~ /pos_itemized/i ) || ( $query{'receipt-type'} =~ /pos_itemized/i ) )
    && ( $query{'easycart'} == 1 ) ) {
    $template_data .= "<p><hr>\n";
    $template_data .= "<br>[pnp_card-name]\n";
    $template_data .= "<br>[pnp_card-address1]\n";
    if ( $query{'card-address2'} ne "" ) {
      $template_data .= "<br>[pnp_card-address2]\n";
    }
    $template_data .= "<br>[pnp_card-city],\n";
    $template_data .= "<br>[pnp_card-state] [pnp_card-zip] [pnp_card-country]\n";

    if ( $query{'phone'} ne "" ) {
      $template_data .= "<p>Phone: [pnp_phone]\n";
    }
    if ( $query{'fax'} ne "" ) {
      $template_data .= "<br>Fax: [pnp_fax]\n";
    }
    $template_data .= "<br>Email: [pnp_email]\n";
  }

  $query{'card-amount'} = sprintf( "%.2f", $query{'card-amount'} );
  $template_data .= "<p><b>Order Total:</b> $query{'currency_symbol'}$query{'card-amount'}\n";
  if ( ( $query{'receipt_type'} !~ /pos_itemized/i )
    && ( $query{'receipt-type'} !~ /pos_itemized/i ) ) {
    $template_data .= "<br>Name: [pnp_card-name]\n";
  }
  if ( $query{'paymethod'} eq "onlinecheck" ) {
    $template_data .= "<br><b>Routing #:</b> [pnp_filteredRN]\n";
    $template_data .= "<br><b>Account #:</b> [pnp_filteredAN]\n";
  } else {
    $template_data .= "<br><b>Card #:</b> [pnp_receiptcc]\n";
    $template_data .= "<br><b>Card Exp:</b> [pnp_card-exp]\n";
  }
  if ( $query{'card-type'} ne "" ) {
    $template_data .= "<br><b>Card Type:</b> [pnp_card-type]\n";
  }

  my $authcode = substr( $query{'auth-code'}, 0, 6 );

  $template_data .= "<br><b>Approval Code: $authcode</b>\n";

  ## Modified DCP 20041217
  $template_data .= "<div align=\"left\">\n";

  $template_data .= "<p><b>X</b>__________________________________\n";
  $template_data .= "<br><font class=\"signature\" size=-1>Signature</font>\n";

  $template_data .=
    "<p><font class=\"signature\" size=-1>By signing above, you (the card member) acknowledges receipt of goods and/or services in the amount of the total shown  herein and  agrees to perform the obligations set forth by the card member's agreement with the issuer.</font>\n";
  $template_data .= "<p>Thank You\n";

  # add print button
  $template_data .= "<script language=\"JavaScript\"><!--\n";
  $template_data .= "if (document.layers && (self.innerHeight == 0 && self.innerWidth == 0)) {\n";
  $template_data .= "     // printing\n";
  $template_data .= "}\n";
  $template_data .= "else {\n";
  $template_data .= "    document.write('<form><input type=\"button\" value=\"Print Receipt\" onClick=\"window.print();\"><\/form>');\n";
  $template_data .= "}\n";
  $template_data .= "//--></script>\n";

  if ( $query{'receipt_link'} ne "" ) {
    $template_data .= "<p>To return to site, <a href=\"$query{'receipt_link'}\">CLICK HERE</a>.\n";
  } elsif ( $query{'receipt-link'} ne "" ) {
    $template_data .= "<p>To return to site, <a href=\"$query{'receipt-link'}\">CLICK HERE</a>.\n";
  }
  $template_data .= "</div>\n";

  return $template_data;
}

sub drop_ship_parse {
  my ( %supplier_email, @attributes );
  my %item_data = ();

  if ( $mckutils::query{'easycart'} ne "" ) {

    my @cart_header = split( /\|/, $mckutils::query{'cart_hdr'} );

    for ( my $i = 1 ; $i <= $mckutils::max ; $i++ ) {
      if ( ( $mckutils::query{"quantity$i"} > 0 )
        && ( $mckutils::query{"supplieremail$i"} =~ /\@/ ) ) {

        my $supplieremail = $mckutils::query{"supplieremail$i"};
        $supplieremail =~ tr/A-Z/a-z/;

        my %item_hash = ();
        foreach my $var (@cart_header) {
          if ( $var eq "null" ) {
            next;
          }
          $item_hash{"$var"} = $mckutils::query{"$var$i"};
        }

        $item_hash{'description'} = $mckutils::query{"description$i"};
        $item_hash{'quantity'}    = $mckutils::query{"quantity$i"};
        $item_hash{'cost'}        = $mckutils::query{"cost$i"};
        $item_hash{'item'}        = $mckutils::query{"item$i"};

        $item_data{$supplieremail}[ ++$#{ $item_data{$supplieremail} } ] =
          \%item_hash;
      }
    }
  }

  foreach my $supplieremail ( keys %item_data ) {
    &drop_ship_email( $supplieremail, @{ $item_data{$supplieremail} } );
  }
}

sub drop_ship_email {
  my ( $supplieremail, @input ) = @_;

  if ( $result{'Duplicate'} ne "yes" ) {
    my $emailObj = new PlugNPay::Email('legacy');
    $emailObj->setGatewayAccount( $mckutils::query{'publisher-name'} );
    $emailObj->setTo($supplieremail);
    $emailObj->setCC( $mckutils::query{'publisher-email'} );
    $emailObj->setFrom( $mckutils::query{'publisher-email'} );
    if ( $mckutils::query{'dropship-subject'} ne "" ) {
      $emailObj->setSubject("$mckutils::query{'subject'} $mckutils::query{'card-name'} $result{'FinalStatus'}");
    } else {
      $emailObj->setSubject("$mckutils::query{'card-name'} Shipment Notification");
    }
    my $email_msg = '';
    $email_msg .= "Merchant Order ID: $mckutils::query{'order-id'}\n";
    if ( $mckutils::query{'agent'} ne "" ) {
      $email_msg .= "SalesAgent: $mckutils::query{'agent'}\n";
    }
    $email_msg .= "Transaction Order ID: $mckutils::orderID\n";
    $email_msg .= "\nBilling Address:\n";
    $email_msg .= $mckutils::query{'card-name'} . "\n";
    if ( $mckutils::query{'card-company'} ne "" ) {
      $email_msg .= "\n";
      $email_msg .= "Company: $mckutils::query{'card-company'}\n";
    }
    $email_msg .= $mckutils::query{'card-address1'} . "\n";
    if ( $mckutils::query{'card-address2'} ne "" ) {
      $email_msg .= $mckutils::query{'card-address2'} . "\n";
    }
    if ( $mckutils::query{'card-state'} ne "" ) {
      $email_msg .= $mckutils::query{'card-city'} . ", " . $mckutils::US_CN_states{ $mckutils::query{'card-state'} } . " " . $mckutils::query{'card-zip'} . "\n";
    } else {
      $email_msg .= $mckutils::query{'card-city'} . ", " . $mckutils::query{'card-zip'} . "\n";
    }
    $email_msg .= $mckutils::countries{ $mckutils::query{'card-country'} } . "\n\n";
    $email_msg .= $mckutils::query{'card-prov'} . "\n";
    if ( $mckutils::query{'shipinfo'} == 1 ) {
      $email_msg .= "\nShipping Address:\n";
      $email_msg .= $mckutils::query{'shipname'} . "\n";
      $email_msg .= $mckutils::query{'address1'} . "\n";
      if ( $mckutils::query{'address2'} ne "" ) {
        $email_msg .= $mckutils::query{'address2'} . "\n";
      }
      $email_msg .= $mckutils::query{'city'} . "," . $mckutils::US_CN_states{ $mckutils::query{'state'} } . " " . $mckutils::query{'zip'} . "\n";
      $email_msg .= $mckutils::query{'province'} . "\n";
      $email_msg .= $mckutils::countries{ $mckutils::query{'country'} } . "\n\n";
    }
    $email_msg .= $mckutils::query{'email'} . "\n";
    $email_msg .= $mckutils::query{'phone'} . "\n";
    $email_msg .= $mckutils::query{'fax'} . "\n\n";

    if ( $mckutils::query{'easycart'} ne "" ) {
      my $purchase_table = Text::Table->new( 'MODEL NO.', 'QTY', 'CHARGE', 'DESCRIPTION', '' );
      for ( my $i = 0 ; $i <= $#input ; $i++ ) {
        if ( $input[$i]->{"quantity"} > 0 ) {
          my $purchase_attributes = '';
          foreach my $attribute ( keys %{ $input[$i] } ) {
            if ( $attribute =~ /^(description|quantity|cost|item|supplieremail)$/ ) {
              next;
            }
            my $value = $input[$i]->{"$attribute"};
            my $label = $attribute;
            substr( $label, 0, 1 ) =~ tr/a-z/A-Z/;
            $purchase_attributes .= "$label: $value\n";
          }
          $purchase_table->add( $input[$i]->{"item"}, $input[$i]->{"quantity"}, $input[$i]->{"cost"}, $input[$i]->{"description"}, $purchase_attributes );
        }
      }
      $email_msg .= $purchase_table;
    }

    if ( $mckutils::query{'shipmethod'} ne "" ) {
      $email_msg .= "Shipmethod: $mckutils::query{'shipmethod'} $mckutils::query{'ship-type'} $mckutils::query{'serviceLevelCode'}\n";
    }

    if ( $mckutils::query{'comments'} ne "" ) {
      $mckutils::query{'comments'} =~ s/\&quot\;/\"/g;
      $mckutils::query{'comments'} =~ s/\n\./\n /g;
      if ( $mckutils::query{'comments'} eq "\." ) {
        $mckutils::query{'comments'} = "";
      }
      if ( $mckutils::query{'comm-title'} ne "" ) {
        $email_msg .= "$mckutils::query{'comm-title'}\n";
      } else {
        $email_msg .= "Comments \&/or Special Instructions:\n";
      }
      $email_msg .= "$mckutils::query{'comments'}\n\n";
    }

    if ( $mckutils::pnp_debug eq "yes" ) {
      $email_msg .= "WARNING: THIS TRANSACTION HAS BEEN FORCED SUCCESSFUL FOR \n";
      $email_msg .= "DEBUGGING AND TESTING PURPOSES ONLY.  IF THIS IS NOT YOUR INTENT PLEASE CONTACT \n";
      $email_msg .= "THE PLUG AND PAY TECHNICAL SUPPORT STAFF IMMEDIATELY AT support\@$mckutils::domain. \n";
    }

    $emailObj->setContent($email_msg);
    $emailObj->send();
  }
}

sub security_check {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  ## BETA - DCP 20050823

  ## DCP 20050914 - Need to remove password/hash protection on Vertual Terminal Auths.

  my ( $username, $password, $remoteaddr ) = @_;
  my ( $ipaddr,   %result,    $login,      $test,       $sec_mode,     %secreq );
  my ( $check_ip, $check_pwd, $check_hash, $check_sec,  $check_script, $check_src, $check_encrypt );
  my ( $hashtest, $pwtest,    $iptest,     $scripttest, $srctest,      $encrypttest, $netmask );

  ## Since security is being performed on primary tran, no need to do it on conv. fee tran
  if ( $mckutils::convfeeflag == 1 ) {
    $result{'flag'} = 1;
    return %result;
  }

  if ( $mckutils::skipsecurityflag == 1 ) {
    $result{'flag'} = 1;
    return %result;
  }

  $username =~ s/[^a-zA-Z0-9]//g;

  $sec_mode = "auth";

  if ( exists $mckutils::feature{'auth_sec_req'} ) {
    my @secreq = split( /\|/, $mckutils::feature{'auth_sec_req'} );
    foreach my $var (@secreq) {
      if ( $var ne "" ) {
        $secreq{$var} = 1;
      }
    }
  }

  if ( exists $secreq{'ip'} ) {
    $check_ip = 1;
  }

  if ( ( exists $secreq{'rmt_ip'} )
    && ( $ENV{'SCRIPT_NAME'} =~ /pnpremote|xml|posremote/ ) ) {
    $check_ip = 1;
  }

  if ( ( exists $secreq{'pwd'} )
    && ( $ENV{'SCRIPT_NAME'} !~ /smps|virtual|auth/ ) ) {
    $check_pwd = 1;
  }

  my $scriptName = $ENV{'SCRIPT_NAME'};
  $scriptName =~ s/.*\///;
  if ( $secreq{"hash:$scriptName"} || $secreq{'hash'} ) {
    $check_hash = 1 if $scriptName !~ /^\/admin/;
  }

  if ( ( exists $secreq{'encrypt'} )
    && ( $ENV{'SCRIPT_NAME'} !~ /smps|virtual/ ) ) {
    $check_encrypt = 1;
  }

  ##  Need to add ability to check which scripts are allowed to process transactions for account.
  ## Choices need to include.  smps, virt_term, merchant.cgi, remote, collect batch, anything custom

  if ( exists $secreq{'script'} ) {
    $check_script = 1;
  }

  ## Simplfied Version of Script Check.  Checks src
  if ( $mckutils::feature{'auth_sec_dis'} ne "" ) {
    $check_src = 1;
  }

  if ( $check_script == 1 ) {
    my (@array)     = split( '\|', $mckutils::feature{'auth_sec_script'} );
    my @scriptpaths = split( '/',  $ENV{'SCRIPT_NAME'} );
    my $scriptname  = $scriptpaths[$#scriptpaths];
    if ( $mckutils::feature{'auth_sec_script'} !~ /$scriptname/i ) {
      $scripttest = "failure";
      $result{'error_log'} = "$mckutils::feature{'auth_sec_script'}:$scriptname|";
    }
  }

  if ( $check_src == 1 ) {
    my (@array)     = split( '\|', $mckutils::feature{'auth_sec_dis'} );
    my @scriptpaths = split( '/',  $ENV{'SCRIPT_NAME'} );
    my $scriptname  = pop(@scriptpaths);
    if ( ( $scriptname =~ /smps\.cgi|virtualterm\.cgi/ )
      && ( $mckutils::feature{'auth_sec_dis'} =~ /vrt/ ) ) {    ## Src is smps
      $srctest = "failure";
      $result{'error_log'} .= "$mckutils::feature{'auth_sec_dis'}:$scriptname|";
    } elsif ( ( $scriptname =~ /remotepos/ )
      && ( $mckutils::feature{'auth_sec_dis'} =~ /pos/ ) ) {    ## Src is remotepos
      $srctest = "failure";
      $result{'error_log'} .= "$mckutils::feature{'auth_sec_dis'}:$scriptname|";
    } elsif ( ( $scriptname =~ /pnpremote/ )
      && ( $mckutils::feature{'auth_sec_dis'} =~ /rmt/ ) ) {    ## Src is remote client
      $srctest = "failure";
      $result{'error_log'} .= "$mckutils::feature{'auth_sec_dis'}:$scriptname|";
    } elsif ( $scriptname =~ /auth\.cgi|$mckutils::query{'publisher-name'}\.cgi/ ) {
      my $ss_version = '0';                                     # assume not smart screens based
      if ( ( $mckutils::query{'customname99999999'} eq 'payscreensVersion' )
        && ( $mckutils::query{'customvalue99999999'} =~ /^(1|2)$/ ) ) {
        $ss_version = $mckutils::query{'customvalue99999999'};    # set smart screens version, when announced
      }
      ## dir = Src is direct (all methods)
      ## ss1 = Src is smart screens v1
      ## ss2 = Src is smart screens v1
      ## dm = Src is direct method (only)
      if (
        ( $mckutils::feature{'auth_sec_dis'} =~ /dir/ )
        || ( ( $mckutils::feature{'auth_sec_dis'} =~ /ss1/ )
          && ( $ss_version == '1' ) )
        || ( ( $mckutils::feature{'auth_sec_dis'} =~ /ss2/ )
          && ( $ss_version == '2' ) )
        || ( ( $mckutils::feature{'auth_sec_dis'} =~ /dm/ )
          && ( $ss_version == '0' ) )
        ) {
        $srctest = "failure";
        $result{'error_log'} .= "$mckutils::feature{'auth_sec_dis'}:$scriptname|";
      }
    } elsif ( ( $mckutils::query{'acct_code4'} =~ /Collect Batch/ )
      && ( $mckutils::feature{'auth_sec_dis'} =~ /upl/ ) ) {    # Collect/Upload Batch
      $srctest = "failure";
      $result{'error_log'} .= "$mckutils::feature{'auth_sec_dis'}:CollectBatch|";
    } elsif ( ( $scriptname =~ /pnpremote/ )
      && ( $mckutils::feature{'auth_sec_dis'} =~ /xtstx/ ) ) {    ## Src is remote client
      ## Log Failures
      my $time = gmtime(time);
      my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
      my $mo = sprintf( "%02d", $mon + 1 );
      open( DEBUG, ">>/home/p/pay1/database/debug/auth_sec_log_tst$mo.txt" );
      print DEBUG "TIME:$time, UN:$username, OID:$mckutils::query{'orderID'}, RA:$remote_ip, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, PID:$$, ";
      print DEBUG
        "SECREQ:$mckutils::feature{'auth_sec_req'}, SRCDIS:$mckutils::feature{'auth_sec_dis'}, PWTST:$pwtest, IPTST:$iptest, SCRP:$scripttest, HASH:$hashtest, SRC:$srctest, ERRLOG:$result{'error_log'} \n";
      close(DEBUG);

      #use Datalog
      my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
      $logger->log(
        { 'TIME'   => $time,
          'UN'     => $username,
          'OID'    => $$mckutils::query{'orderID'},
          'RA'     => $remote_ip,
          'SCRIPT' => $ENV{'SCRIPT_NAME'},
          'HOST'   => $ENV{'SERVER_NAME'},
          'PORT'   => $ENV{'SERVER_PORT'},
          'PID'    => $$,
          'SECREQ' => $mckutils::feature{'auth_sec_req'},
          'SRCDIS' => $mckutils::feature{'auth_sec_dis'},
          'PWTST'  => $pwtest,
          'IPTST'  => $iptest,
          'SCRP'   => $scripttest,
          'HASH'   => $hashtest,
          'SRC'    => $srctest,
          'ERRLOG' => $result{'error_log'}
        }
      );
    }
  }

  if ( $check_hash == 1 ) {

    # clean up transaction time for use with PlugNPay::Sys::Time
    $mckutils::query{'transacttime'} =~ s/[^0-9]//g;
    $mckutils::query{'transacttime'} =
      substr( $mckutils::query{'transacttime'}, 0, 14 );

    # feature contains timeout, secret, and then fields (in that order), pipe separated
    my (@fieldsAndStuff) = split( '\|', $mckutils::feature{'authhashkey'} );
    my $timeout          = shift @fieldsAndStuff;
    my $secret           = shift @fieldsAndStuff;
    my @fields           = @fieldsAndStuff;

    # filter timeout to digits only
    $timeout =~ s/[^0-9]//g;

    # create time objects for startTime, endTime based on input
    my $startTime = new PlugNPay::Sys::Time();
    my $endTime = new PlugNPay::Sys::Time();

    $startTime->fromFormat('gendatetime',$mckutils::query{'transacttime'});
    $endTime->fromFormat('gendatetime',$mckutils::query{'transacttime'});

    # subject 1 minute from timeout to account for clock differences
    $startTime->subtractMinutes(1);

    # add timeout from feature setting to end time
    $endTime->addMinutes($timeout);

    my %sourceData = %mckutils::query;

    my $cardAmount  = $mckutils::query{'card-amount'} + 0;
    my $currencyObj = new PlugNPay::Currency( uc( $mckutils::query{'currency'} ) );
    $cardAmount = $currencyObj->format( $cardAmount, { digitSeparator => '' } );
    $sourceData{'card-amount'} = $cardAmount;

    # this supports MD5 and SHA256 for validation
    my $validateStatus = PlugNPay::Merchant::VerificationHash::Digest::validate(
      { type     => 'inbound',
        settings => {
          fields     => \@fields,
          sortFields => 1,
          secret     => $secret,
          timeout    => $timeout
        },
        sourceData => \%sourceData,
        startTime  => $startTime,
        endTime    => $endTime,
        digest     => $mckutils::query{'authhash'},
        hashTimeString => $mckutils::query{'transacttime'}
      }
    );

    if ( !$validateStatus ) {
      $hashtest = "failure";
      $result{'error_log'} .= "$mckutils::query{'authhash'}:<nothing to see here>|";
    }
  }


  ##  NOTE:  20071108  DCP
  ##  See if process.pl can set ENV Script name as a better way to know script is process.pl instead of relying on Acct_code4 which maybe able to be faked.
  if ( ( $check_ip == 1 )
    && ( $mckutils::query{'acct_code4'} !~ /Collect Batch/ ) ) {    ##  Begin Check_IP Loop  exempt Collect Batch auths.
    my $dbh = &miscutils::dbhconnect("pnpmisc");

    my $ip = NetAddr::IP->new("$remoteaddr");
    $remoteaddr =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/;
    my $testip = "$1\.$2\.$3\.\%";

    my $sth = $dbh->prepare(
      qq{
        select ipaddress,netmask
        from ipaddress
        where username=?
        and ipaddress LIKE ?
        }
      )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
    $sth->execute( $username, $testip )
      or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr" );
    $sth->bind_columns( undef, \( $ipaddr, $netmask ) );
    while ( $sth->fetch ) {

      if ( ( $netmask < 24 ) || ( $netmask > 32 ) ) {
        $netmask = "32";
      }
      if ( $ip->within( NetAddr::IP->new("$ipaddr/$netmask") ) ) {
        last;    ### IP IN RANGE;
      } else {
        $ipaddr = "";
      }
    }
    $sth->finish;
    $dbh->disconnect;

    if ( $ipaddr eq "" ) {
      $iptest = "failure";
      $result{'error_log'} .= "$remoteaddr:$ipaddr|";
    }
  }    ## END IP Check

  if ( $check_encrypt == 1 ) {
    ###  Check that encdata contains all required fields.
    my @encrequired = split( '\|', $mckutils::feature{'encrequired'} );
    my $errmsg = "";
    foreach my $var (@encrequired) {
      if ( !exists $mckutils::encquery{$var} ) {
        ##  Problem - Required Data Missing
        $errmsg .= "$var,";
      }
      if ( $errmsg ne "" ) {
        $encrypttest = "failure";
        $result{'error_log'} .= "missing:$errmsg|";
      }
    }
    ###  Check that transaction timestamp falls within allowed window.
    if ( exists $mckutils::encquery{'timestamp'} ) {
      $mckutils::encquery{'timestamp'} =~ s/[^0-9]//g;
      $mckutils::encquery{'timestamp'} =
        substr( $mckutils::encquery{'timestamp'}, 0, 14 );
      ## Get Current System Time in GMT
      my $systime = time();
      ## Convert transacttime to System Time
      my $transacttime = &miscutils::strtotime( $mckutils::encquery{'timestamp'} );
      ## if Submitted Transaction Time is older than current time minus allowd time window or if Submitted Transaction Time is newer than 2 minutes of current time
      ## reject
      if ( ( $transacttime < ( $systime - ( $mckutils::feature{'timewindow'} * 60 ) ) )
        || ( $transacttime > ( $systime + ( 2 * 60 ) ) ) ) {
        $encrypttest = "failure";
        $result{'error_log'} .= "Timestamp:$transacttime:$systime|";
      }
    }
  }

  if ( ( $pwtest eq "failure" )
    || ( $iptest eq "failure" )
    || ( $scripttest eq "failure" )
    || ( $hashtest eq "failure" )
    || ( $srctest eq "failure" )
    || ( $encrypttest eq "failure" ) ) {
    if ( $pwtest eq "failure" ) {
      $result{'resp-code'} = "P91";
      $result{'MErrMsg'}   = "Missing/incorrect password";
    } elsif ( $iptest eq "failure" ) {
      $result{'resp-code'} = "P93";
      $result{'MErrMsg'}   = "IP Not registered to username. Please register $remoteaddr in your security admin area.";
    } elsif ( $scripttest eq "failure" ) {
      $result{'resp-code'} = "P110";
      $result{'MErrMsg'}   = "Invalid Payment Script. Please register script name in your security admin area.";
    } elsif ( $hashtest eq "failure" ) {
      $result{'resp-code'} = "P111";
      $result{'MErrMsg'}   = "Invalid value for passed Security Hash. Please check value for shared hash key in your security admin area.";
    } elsif ( $srctest eq "failure" ) {
      $result{'resp-code'} = "P112";
      $result{'MErrMsg'}   = "Invalid source for processing script.";
    } elsif ( $encrypttest eq "failure" ) {
      $result{'resp-code'} = "P113";
      $result{'MErrMsg'}   = "Encrypted Payload missing required data or Payload has expired.";
    }
    $result{'flag'} = 0;
    ## Log Failures
    my $time = gmtime(time);
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
    my $mo = sprintf( "%02d", $mon + 1 );

    open( DEBUG, ">>/home/p/pay1/database/debug/auth_sec_log$mo.txt" );
    print DEBUG "TIME:$time, UN:$username, OID:$mckutils::query{'orderID'}, RA:$remote_ip, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, PORT:$ENV{'SERVER_PORT'}, PID:$$, ";
    print DEBUG
      "SECREQ:$mckutils::feature{'auth_sec_req'}, SRCDIS:$mckutils::feature{'auth_sec_dis'}, PWTST:$pwtest, IPTST:$iptest, SCRP:$scripttest, HASH:$hashtest, SRC:$srctest, ERRLOG:$result{'error_log'} \n";
    close(DEBUG);

    #use Datalog
    my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
    $logger->log(
      { 'TIME'   => $time,
        'UN'     => $username,
        'OID'    => $$mckutils::query{'orderID'},
        'RA'     => $remote_ip,
        'SCRIPT' => $ENV{'SCRIPT_NAME'},
        'HOST'   => $ENV{'SERVER_NAME'},
        'PORT'   => $ENV{'SERVER_PORT'},
        'PID'    => $$,
        'SECREQ' => $mckutils::feature{'auth_sec_req'},
        'SRCDIS' => $mckutils::feature{'auth_sec_dis'},
        'PWTST'  => $pwtest,
        'IPTST'  => $iptest,
        'SCRP'   => $scripttest,
        'HASH'   => $hashtest,
        'SRC'    => $srctest,
        'ERRLOG' => $result{'error_log'}
      }
    );
  } else {
    $result{'flag'} = 1;
  }

  return %result;

}

sub sresponse {

  # Simplified Response Code
  # A - Approved
  # C - Call Issuer
  # D - Declined
  # P - Pick up Card
  # X - Expired Card
  # E - Other Error
  my $responseCode = $mckutils::result{'resp-code'};
  my $processor    = $mckutils::processor;
  my $mapObject    = new PlugNPay::Processor::ResponseCode();

  return $mapObject->getSimplifiedResponseCode( $processor, $responseCode );
}

sub setholdstatus {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  delete $mckutils::query{'authtype'};
  $result{'frauderrmsg'} = $mckutils::query{'fraudholdmsg'};

  if ( $mckutils::feature{'setholdbetaflg'} != 1 ) {
    $result{'avs-code'} = "0";
    return;
  }

  $result{'fraudstatus'} = "hold";
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime(time);
  my $description = substr( $result{'frauderrmsg'}, 0, 49 );
  my $transtime = sprintf( "%04d%02d%02d%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
  my $ipaddress = $remote_ip;
  my $username  = $mckutils::query{'publisher-name'};
  my $orderid   = $mckutils::query{'orderID'};

  my $debug_fraudhold = 1;
  if ( $debug_fraudhold == 1 ) {
    my $time    = gmtime(time);
    my %logdata = ();             #use datalog
    open( DEBUG, ">>/home/p/pay1/database/debug/fraudhold.txt" );
    print DEBUG "TIME:$time, RA:$remote_ip, SCRIPT:$ENV{'SCRIPT_NAME'}, HOST:$ENV{'SERVER_NAME'}, ";
    print DEBUG "PORT:$ENV{'SERVER_PORT'}, PID:$$, RM:$ENV{'REQUEST_METHOD'}, ";

    foreach my $key ( sort keys %mckutils::query ) {
      my $s = $mckutils::query{$key};
      if ( $key =~ /card_num|cardnumber|card-num/i ) {
        my $tmpCC = substr( $s, 0, 6 ) . ( 'X' x ( length($s) - 8 ) ) . substr( $s, -2 );    # Format: first6, X's, last2
        print DEBUG "Q:$key:$tmpCC, ";
        $logdata{$key} = $tmpCC;
      } elsif ( ( $key =~ /^(TrakData|magstripe)$/ ) && ( $s ne "" ) ) {
        print DEBUG "Q:$key:Data Present:" . substr( $s, 0, 6 ) . "****" . "0000" . ", ";
        $logdata{$key} = "Data Present:" . substr( $s, 0, 6 ) . "****" . "0000";
      } elsif ( $key =~ /(card_code|password|cvv)/i ) {
        my $aaaa = $s;
        $aaaa =~ s/./X/g;
        print DEBUG "Q:$key:$aaaa, ";
        $logdata{$key} = $aaaa;
      } else {
        print DEBUG "Q:$key:$s, ";
        $logdata{$key} = $s;
      }
    }
    foreach my $key ( sort keys %result ) {
      my $s = $result{$key};
      if ( $key =~ /card_num|cardnumber|card-num/i ) {
      } elsif ( ( $key =~ /^(TrakData|magstripe)$/ ) && ( $s ne "" ) ) {
      } elsif ( $key =~ /(card_code|password|cvv)/i ) {
      } else {
        print DEBUG "R:$key:$s, ";
        $logdata{$key} = $s;
      }
    }
    print DEBUG "\n";
    close(DEBUG);

    #use Datalog
    my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
    $logger->log(
      { 'TIME'   => $time,
        'RA'     => $remote_ip,
        'SCRIPT' => $ENV{'SCRIPT_NAME'},
        'HOST'   => $ENV{'SERVER_NAME'},
        'PORT'   => $ENV{'SERVER_PORT'},
        'PID'    => $$,
        'RM'     => $ENV{'REQUEST_METHOD'},
        'Q'      => \%logdata
      }
    );
  }

  my ( undef, $transdate, $timestr ) = &miscutils::gendatetime(-300);
  ## Freeze Transaction
  my $dbhpnp = &miscutils::dbhconnect( "pnpdata", "", "$mckutils::query{'publisher-name'}" );

  my $sth = $dbhpnp->prepare(
    qq{
      update trans_log
      set finalstatus='hold'
      where trans_date>=?
      and username=?
      and orderid=?
      and operation='auth'
      and finalstatus='success'
    }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query, 'username', $username );
  $sth->execute( "$transdate", "$username", "$orderid" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query, 'username', $username );
  $sth->finish;

  $sth = $dbhpnp->prepare(
    qq{
      update operation_log
      set lastopstatus='hold'
      where trans_date>=?
      and username=?
      and orderid=?
      and authstatus='success'
      and lastopstatus='success'
    }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query, 'username', $username );
  $sth->execute( "$transdate", "$username", "$orderid" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query, 'username', $username );
  $sth->finish;

  $dbhpnp->disconnect;

  my $action = "tran. frozen";
  my $dbh    = &miscutils::dbhconnect("pnpmisc");
  my $sth2   = $dbh->prepare(
    qq{
    insert into risk_log
    (username,orderid,trans_time,ipaddress,action,description)
    values (?,?,?,?,?,?)
    }
    )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't prepare: $DBI::errstr", %mckutils::query, 'username', $username );
  $sth2->execute( "$username", "$orderid", "$transtime", "$ipaddress", "$action", "$description" )
    or &miscutils::errmail( __LINE__, __FILE__, "Can't execute: $DBI::errstr", %mckutils::query, 'username', $username );
  $sth2->finish;
  $dbh->disconnect;

}

sub mpgift_reload {
  ## Step 1 - Reload MP.
  my $price = sprintf( "%3s %.2f", "$mckutils::query{'currency'}", $mckutils::query{'card-amount'} );
  my $addr = $mckutils::query{'card-address1'} . " " . $mckutils::query{'card-address2'};
  $addr = substr( $addr, 0, 50 );
  my $country    = substr( $mckutils::query{'card-country'}, 0, 2 );
  my $trans_type = 'credit';
  my ($orderid)  = &miscutils::incorderid($mckutils::orderID);
  my $transflags = 'reload';
  my $acct_code4 = "MPGift Reload:$mckutils::query{'mpgiftcard'}";

  my %result = &miscutils::sendmserver(
    $mckutils::query{'publisher-name'}, "$trans_type",                  'accttype',     $mckutils::query{'accttype'},
    'order-id',                         $orderid,                       'acct_code',    $mckutils::query{'acct_code'},
    'acct_code2',                       $mckutils::query{'acct_code2'}, 'acct_code3',   $mckutils::query{'acct_code3'},
    'acct_code4',                       $acct_code4,                    'amount',       $price,
    'card-number',                      $mckutils::query{'mpgiftcard'}, 'card-cvv',     $mckutils::query{'mpcvv'},
    'card-name',                        $mckutils::query{'card-name'},  'card-address', $addr,
    'card-city',                        $mckutils::query{'card-city'},  'card-state',   $mckutils::query{'card-state'},
    'card-zip',                         $mckutils::query{'card-zip'},   'card-country', $country,
    'card-exp',                         $mckutils::query{'card-exp'},   'subacct',      $mckutils::query{'subacct'},
    'transflags',                       $transflags,                    'magstripe',    $mckutils::query{'magstripe'},
    'marketdata',                       $mckutils::query{'marketdata'}
  );

  if ( $result{'FinalStatus'} ne "success" ) {
    my $acct_code4 = "MPGift Void";
    ## Reload Failed - Void original Auth
    my %result1 = &miscutils::sendmserver(
      $mckutils::query{'publisher-name'},
      "void", 'acct_code', $mckutils::query{'acct_code'},
      'acct_code4', "$mckutils::acct_code4", 'txn-type', 'marked', 'amount', "$price", 'order-id', "$mckutils::orderID"
    );

    ## Return Problem Response.
    if ( $result1{'FinalStatus'} ne "success" ) {
      $result{'MErrMsg'}     = "MP Gift Reload failed, Automatic Void Failed.";
      $result{'FinalStatus'} = "problem";
    } else {
      $result{'MErrMsg'}     = "MP Gift Reload failed, Purchase Successfully Voided.";
      $result{'FinalStatus'} = "problem";
    }
  }
  return %result;
}

sub conv_fee {
  my ( %feerules, @feerules, $feeamt );

  ## Rule Format FAILRULE: TYPE: FEEACCT: AMT|PERCENT|FIXED: AMT|PERCENT|FIXED: AMT|PERCENT|FIXED ....
  ## FAILRULE = IGN or VOID  IGN = leave primary transaction alone if Conv Fee tran fails. (default)  VOID = Void primary if Conv Fee fails.
  ## TYPE =  STEP, FULL or SUBMT   STEP  applies fee depending on amount in each fee bucket.  FULL applies fee to full amount. SUBMT, Fee is SUBMiTted with tran
  ## FEEACT = Account to run conv. fee charge through

  #$mckutils::feature{'conv_fee'} = "IGN:STEP:FEEACCT:100.00|.025|1.00:400|.0225|1.00:800|.0215|1.00:all|.02|1.00";

  my ($feerules);

  if ( $mckutils::query{'accttype'} =~ /(checking|savings)/ ) {
    $feerules = $mckutils::feature{'conv_fee_ach'};
  } else {
    $feerules = $mckutils::feature{'conv_fee'};
  }

  if ( $mckutils::feature{'conv_fee_authtype'} eq "authpostauth" ) {
    $mckutils::query{'authtype'} = 'authpostauth';
  }

  $feerules =~ s/[^a-zA-Z0-9\.\:\|]//g;
  @feerules = split( '\:', $feerules );

  my $failrule = shift(@feerules);
  $failrule =~ s/[^a-zA-Z0-9]//g;

  my $ruletype = shift(@feerules);
  $ruletype =~ s/[^a-zA-Z0-9]//g;

  my $fee_acct = shift(@feerules);
  $fee_acct =~ s/[^a-zA-Z0-9]//g;
  $fee_acct =~ tr/A-Z/a-z/;

  ## Calculate Fee Amt
  if ( ( $ruletype =~ /^SUBMT$/i ) || ( $mckutils::query{'convfeeamt'} > 0 ) ) {
    $feeamt = $mckutils::query{'convfeeamt'};
  }
  ## RuleType = STEP
  elsif ( $ruletype =~ /^STEP$/i ) {
    my ( $oldamt, $calcamt );
    my $tstamt = $mckutils::query{'card-amount'};
    foreach my $bucket (@feerules) {
      my ( $amt, $per, $fix ) = split( '\|', $bucket );
      if ( ( $amt =~ /^ALL$/i )
        || ( $amt > $mckutils::query{'card-amount'} ) ) {
        $feeamt += ( ( $mckutils::query{'card-amount'} - $oldamt ) * $per ) + $fix;
        $feeamt = sprintf( "%.2f", $feeamt + 0.0001 );
        $tstamt -= $amt;
        last;
      } elsif ( $mckutils::query{'card-amount'} >= $amt ) {
        $calcamt = $amt - $oldamt;
        $feeamt += ( ( $amt - $oldamt ) * $per ) + $fix;
        $feeamt = sprintf( "%.2f", $feeamt + 0.0001 );
        if ( $mckutils::query{'card-amount'} - $amt < .01 ) {
          last;
        }
      }
      $oldamt = $amt;
    }
  }
  ## RuleType = FULL
  else {
    foreach my $bucket (@feerules) {
      my ( $amt, $per, $fix ) = split( '\|', $bucket );
      if ( ( $amt =~ /^ALL$/i )
        || ( $amt >= $mckutils::query{'card-amount'} ) ) {
        $feeamt = ( $mckutils::query{'card-amount'} * $per ) + $fix;
        $feeamt = sprintf( "%.2f", $feeamt + 0.0001 );
        last;
      }
    }
  }

  #&database();

  return $feeamt, $fee_acct, $failrule;
}

sub convfee {
  my ( $feetype, %cf_result );

  if ( $mckutils::query{'accttype'} =~ /(checking|savings)/ ) {
    $feetype = 'ach';
  } elsif ( $mckutils::query{'accttype'} =~ /^(seqr)$/ ) {    #### SeEt to allow future feetypes to be added
    $feetype = $mckutils::query{'accttype'};
  } else {
    $feetype = 'credit';
  }

  my $cf = new PlugNPay::ConvenienceFee( $mckutils::query{'publisher-name'} );

  my %result = $cf->getConvenienceFees( $mckutils::query{'card-amount'} );

  if ( $cf->isSurcharge() ) {
    $cf_result{'surcharge'} = 1;
  }

  $cf_result{'failrule'} = $cf->getFailureMode();
  $cf_result{'feeacct'}  = $cf->getChargeAccount();

  my $cc = new PlugNPay::CreditCard( $mckutils::query{'card-number'} );

  my $cardCategory    = $cc->getCardCategory();
  my $defaultCategory = $result{'defaultCategory'};
  if ( $cardCategory eq '' ) {
    $cardCategory = $defaultCategory;
  }
  if ( $feetype eq "ach" ) {
    $cardCategory = "standard";
  }

  if ( defined $result{'fees'}{$feetype}{$cardCategory} ) {
    $cf_result{'feeamt'} = $result{'fees'}{$feetype}{$cardCategory};
  } else {
    $cf_result{'feeamt'} = $result{'fees'}{$feetype}{$defaultCategory};
  }
  $mckutils::adjustmentFlag++;

  return %cf_result;
}

sub cardcharge {
  my ( $feetype, %cf_result );

  if ( $mckutils::query{'accttype'} =~ /(checking|savings)/
    || $mckutils::query{'paymethod'} eq "onlinecheck" ) {
    $feetype = 'ach';
  } elsif ( $mckutils::query{'accttype'} =~ /^(seqr)$/ ) {    #### SeEt to allow future feetypes to be added
    if ( $mckutils::query{'SEQRPass'} > 0 ) {
      return;
    }
    $feetype = $mckutils::query{'accttype'};
  } else {
    $feetype = 'credit';
  }

  my $COA = new PlugNPay::COA( $mckutils::query{'publisher-name'} );

  if ( $COA->isFee() ) {
    $cf_result{'fee'} = 1;
  } elsif ( $COA->isSurcharge() ) {
    my %states = ( %constants::USstates, %constants::USterritories );
    if ( exists $states{ uc( $mckutils::query{'card-state'} ) } ) {
      my $stateObj = new PlugNPay::Country::State();
      $stateObj->setState( uc( $mckutils::query{'card-state'} ) );
      if ( $COA->getCheckCustomerState()
        && !$stateObj->getCanSurcharge() ) {
        return;
      }
    }
    $cf_result{'surcharge'} = 1;
  } elsif ( $COA->isDiscount() ) {
    $cf_result{'Discount'} = 1;
  } elsif ( $COA->isOptional() ) {
    $cf_result{'optional'} = 1;
  }

  $cf_result{'feeacct'} = $COA->getChargeAccount();

  if ( $mckutils::query{'paymethod'} eq "seqr" ) {
    my $adjustmentData = $COA->get( '00000', $mckutils::query{'card-amount'}, $mckutils::query{'orderID'} );
    $cf_result{'feeamt'} = $adjustmentData->{'seqrAdjustment'};
  } elsif ( $feetype eq 'ach' ) {
    my $adjustmentData = $COA->get( '000000000', $mckutils::query{'card-amount'}, $mckutils::query{'orderID'} );
    $cf_result{'feeamt'} = $adjustmentData->{'achAdjustment'};
  } else {
    $cf_result{'feeamt'} = $COA->getAdjustment( substr( $mckutils::query{'card-number'}, 0, 9 ), $mckutils::query{'card-amount'}, $mckutils::query{'orderID'} );
  }
  $cf_result{'failrule'} = $COA->getFailureRule();

  if ( $COA->getAdjustmentIsTaxable() ) {
    if ( ( $cf_result{'surcharge'} == 1 )
      && ( $mckutils::query{'tax'} > 0 )
      && ( $cf_result{'feeamt'} > 0 ) ) {
      ### Calc Effective Tax Rate.
      my $effective_tax_rate = $mckutils::query{'tax'} / ( $mckutils::query{'card-amount'} - $mckutils::query{'tax'} );
      my $tax_on_surcharge = $cf_result{'feeamt'} * $effective_tax_rate;
      ### Update tax field and add to surcharge fee
      $mckutils::query{'tax'} =
        sprintf( "%.2f", $mckutils::query{'tax'} + $tax_on_surcharge );
      $cf_result{'feeamt'} =
        sprintf( "%.2f", $cf_result{'feeamt'} + $tax_on_surcharge );
    } elsif ( ( $cf_result{'Discount'} == 1 )
      && ( $mckutils::query{'tax'} > 0 )
      && ( $cf_result{'feeamt'} < 0 ) ) {
      ### Calc Effective Tax Rate.
      my $effective_tax_rate = $mckutils::query{'tax'} / ( $mckutils::query{'card-amount'} - $mckutils::query{'tax'} );
      my $tax_on_discount = $cf_result{'feeamt'} * $effective_tax_rate;
      ### Update tax field and add to surcharge fee
      $mckutils::query{'tax'} =
        sprintf( "%.2f", $mckutils::query{'tax'} + $tax_on_discount );
    }
  }
  $mckutils::adjustmentFlag++;

  return %cf_result;
}

sub taxcalc {

  #  James - 04/19/2000 @ 4:05 pm - Do not change the ($payutils::query{'tax'} < 0.001) calculation
  #  This to work with items that are to have a $0.00 dollar amount.
  #  * Note: the item price must be set $0.001 in order to work correctly.

  my ($taxable_state);
  if ( $mckutils::feature{'certitax'} ne "" ) {
    &certitaxcalc();
  } elsif ( ( $mckutils::query{'notax'} != 1 )
    && ( $mckutils::query{'tax'} < 0.001 )
    && ( $mckutils::query{'taxstate'} ne "" )
    && ( $mckutils::query{'taxrate'} ne "" ) ) {
    my @taxstate = split( /\||\,/, $mckutils::query{'taxstate'} );
    my @taxrate  = split( /\||\,/, $mckutils::query{'taxrate'} );
    if ( $mckutils::query{'taxbilling'} eq "yes" ) {
      $taxable_state = $mckutils::query{'card-state'};
    } else {
      if ( $mckutils::query{'state'} ne "" ) {
        $taxable_state = $mckutils::query{'state'};
      } else {
        $taxable_state = $mckutils::query{'card-state'};
      }
    }

    my $k = 0;
    if ( $mckutils::query{'taxstate'} eq "all" ) {
      if ( $mckutils::query{'taxship'} eq "no" ) {
        $mckutils::query{'tax'} =
          ($mckutils::taxsubtotal) * $taxrate[$k];
      } else {
        $mckutils::query{'tax'} = ( $mckutils::taxsubtotal + $mckutils::query{'shipping'} ) * $taxrate[$k];
      }
    } else {
      foreach my $var (@taxstate) {
        if ( ( $taxrate[$k] > 0 ) && ( $taxable_state =~ /$var/i ) ) {
          if ( $mckutils::query{'taxship'} eq "no" ) {
            $mckutils::query{'tax'} =
              ($mckutils::taxsubtotal) * $taxrate[$k];
          } else {
            $mckutils::query{'tax'} = ( $mckutils::taxsubtotal + $mckutils::query{'shipping'} ) * $taxrate[$k];
          }
        }
        $k++;
      }
    }
    $mckutils::query{'tax'} = &Round( $mckutils::query{'tax'} );
  }
}

sub certitaxcalc {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my (%certitax);

  if ( ( $mckutils::feature{'certitax'} eq "" )
    || ( $mckutils::query{'skiptaxcalc'} == 1 ) ) {
    return;
  }
  ## Comment out later  DCP  200812101
  $mckutils::query{'CertiTaxDebug'} = 1;

  $certitax{'ReferredId'} = "$mckutils::query{'referredid'}";
  $certitax{'Location'}   = "$mckutils::query{'locationid'}";
  if ( $payutils::query{'calculatetax'} =~ /^(true|false)$/i ) {
    $certitax{'CalculateTax'} = $mckutils::query{'calculatetax'};
  } else {
    $certitax{'CalculateTax'} = "True";
  }
  if ( $payutils::query{'ConfirmAddress'} =~ /^(true|false)$/i ) {
    $certitax{'ConfirmAddress'} = $mckutils::query{'ConfirmAddress'};
  } else {
    $certitax{'ConfirmAddress'} = "false";
  }
  if ( $payutils::query{'defaultproductcode'} =~ /[0-9]/ ) {
    $certitax{'DefaultProductCode'} = $mckutils::query{'defaultproductcode'};
  } else {
    $certitax{'DefaultProductCode'} = "0";
  }

  $certitax{'TaxExemptCertificate'} = "$mckutils::query{'TaxExemptCertificate'}";
  $certitax{'TaxExemptIssuer'}      = "$mckutils::query{'TaxExemptIssuer'}";
  $certitax{'TaxExemptReason'}      = "$mckutils::query{'TaxExemptReason'}";

  #my $clientIP = "webservices.esalestax.net";
  #my $clientPort = "443";
  #my $clientPath = "/CertiTAX.NET/CertiCalc.asmx/Calculate";

  my $url = "https://webservices.esalestax.net/CertiTAX.NET/CertiCalc.asmx/Calculate";

  my ( $company, $taxable_addr1, $taxable_addr2, $taxable_city, $taxable_county, $taxable_state, $taxable_zip, $taxable_country, $taxable_name );
  my ( $totalAmount, $lineItem );

  my ( $serialNumber, $merchantID, $service_level, $nexus, $breakdwnflg ) =
    split( '\|', $mckutils::feature{'certitax'} );

  $certitax{'SerialNumber'} = $serialNumber;

  if ( $nexus !~ /^(POD|POB|POS|POSH)$/ ) {
    $certitax{'Nexus'} = "POD";
  } else {
    $certitax{'Nexus'} = $nexus;
  }
  $certitax{'MerchantTransactionId'} = "$mckutils::query{'orderID'}";

  $service_level = "";
  if ( $mckutils::query{'taxbilling'} eq "yes" ) {
    $taxable_name   = $mckutils::query{'card-name'};
    $taxable_addr1  = $mckutils::query{'card-address1'};
    $taxable_addr2  = $mckutils::query{'card-address2'};
    $taxable_city   = $mckutils::query{'card-city'};
    $taxable_county = "";
    $taxable_state  = $mckutils::query{'card-state'};
    $taxable_zip    = $mckutils::query{'card-zip'};
  } else {
    if ( ( $mckutils::query{'state'} ne "" )
      && ( $mckutils::query{'zip'} ne "" ) ) {
      $taxable_name   = $mckutils::query{'shipname'};
      $taxable_addr1  = $mckutils::query{'address1'};
      $taxable_addr2  = $mckutils::query{'address2'};
      $taxable_city   = $mckutils::query{'city'};
      $taxable_county = "";
      $taxable_state  = $mckutils::query{'state'};
      $taxable_zip    = $mckutils::query{'zip'};
    } else {
      $taxable_name   = $mckutils::query{'card-name'};
      $taxable_addr1  = $mckutils::query{'card-address1'};
      $taxable_addr2  = $mckutils::query{'card-address2'};
      $taxable_city   = $mckutils::query{'card-city'};
      $taxable_county = "";
      $taxable_state  = $mckutils::query{'card-state'};
      $taxable_zip    = $mckutils::query{'card-zip'};
    }
  }

  $certitax{'Name'}       = "$taxable_name";
  $certitax{'Street1'}    = "$taxable_addr1";
  $certitax{'Street2'}    = "$taxable_addr2";
  $certitax{'City'}       = "$taxable_city";
  $certitax{'County'}     = "$taxable_county";
  $certitax{'State'}      = "$taxable_state";
  $certitax{'PostalCode'} = "$taxable_zip";
  $certitax{'Nation'}     = "$taxable_country";

  if ( $taxable_zip eq "" ) {
    return;
  }

  if ( $service_level eq "lineitem" ) {
    my ($j);
    if ( $mckutils::query{'easycart'} == 1 ) {
      for ( $j = 1 ; $j <= $mckutils::max ; $j++ ) {
        my $cost = sprintf( "%.2f", $mckutils::quantity[$j] * $mckutils::cost[$j] );
        $cost =~ s/[^0-9]//g;
        $lineItem .= "{$j,$mckutils::item[$j],$mckutils::quantity[$j],$cost}";
      }
      if ( $mckutils::query{'taxship'} ne "no" ) {
        $j++;
        my $shipping = $mckutils::query{'shipping'};
        $shipping =~ s/[^0-9]//g;
        $lineItem .= "{$j,SHIP,1,$shipping}";
      }
    } else {
      $totalAmount = $mckutils::taxsubtotal;
      $totalAmount = sprintf( "%.2f", $totalAmount );
      $totalAmount =~ s/[^0-9]//g;
      $lineItem = "{1,TOTAL,1,$totalAmount}";
    }
  } else {
    my ($subtotal);
    if ( $mckutils::query{'easycart'} == 1 ) {
      $subtotal = $mckutils::taxsubtotal;
    } else {
      $subtotal = $mckutils::query{'subtotal'};
    }
    $totalAmount = $subtotal;
    $totalAmount = sprintf( "%.2f", $totalAmount );
    $totalAmount =~ s/[^0-9\.]//g;
  }

  $certitax{'ShippingCharge'} = "$mckutils::query{'shipping'}";
  $certitax{'HandlingCharge'} = "$mckutils::query{'handling'}";
  if ( $certitax{'ShippingCharge'} == 0 ) {
    $certitax{'ShippingCharge'} = "0";
  }
  if ( $certitax{'HandlingCharge'} == 0 ) {
    $certitax{'HandlingCharge'} = 0;
  }

  $certitax{'Total'} = "$totalAmount";
  ### Perform Web Services Request
  my $pairs = "";
  foreach my $key ( keys %certitax ) {
    $_ = $certitax{$key};
    s/(\W)/'%' . unpack("H2",$1)/ge;
    if ( $pairs ne "" ) {
      $pairs = "$pairs\&$key=$_";
    } else {
      $pairs = "$key=$_";
    }
  }

  my $resp = &miscutils::formpost_raw( $url, $pairs );

  if ( $resp =~ /xml version/i ) {
    require XML::Simple;

    my @taxdetails = (
      'CityTaxAuthority', 'CountyTaxAuthority', 'LocalTaxAuthority', 'NationalTaxAuthority', 'OtherTaxAuthority', 'StateTaxAuthority',
      'CityTax',          'CountyTax',          'LocalTax',          'NationalTax',          'OtherTax',          'StateTax'
    );

    my $parser = XML::Simple->new();
    my $xmldoc = $parser->XMLin( $resp, SuppressEmpty => 1 );
    $mckutils::query{'CertiTaxID'} = $xmldoc->{CertiTAXTransactionId};
    $mckutils::query{'tax'}        = $xmldoc->{TotalTax};
    if ( ( $breakdwnflg == 1 )
      || ( $mckutils::query{'certitaxdetail'} == 1 ) ) {
      foreach my $element (@taxdetails) {
        if ( defined $xmldoc->{$element} ) {
          $mckutils::query{"$element"} = $xmldoc->{"$element"};
        } else {
          $mckutils::query{"$element"} = "";
        }
      }
    }
  } else {
    $mckutils::query{'taxcalcerror'} = "$resp";
  }

  if ( $mckutils::query{'CertiTaxDebug'} == 1 ) {
    my $time = gmtime(time);
    open( DEBUG, ">>/home/p/pay1/database/debug/CertTax_debug.txt" );
    print DEBUG "TIME:$time, RA:$remote_ip, MERCH:$mckutils::query{'publisher-name'}, SCRIPT:$ENV{'SCRIPT_NAME'}, ";
    print DEBUG "HOST:$ENV{'SERVER_NAME'}, URL:$url INPUT VAR: ";
    print DEBUG "SEND:$pairs\n";
    print DEBUG "RETURN:$resp\n\n";
    close(DEBUG);

    #use Datalog
    my $logger = new PlugNPay::Logging::DataLog( { collection => 'mckutils_strict' } );
    $logger->log(
      { 'TIME'   => $time,
        'RA'     => $remote_ip,
        'MERCH'  => $mckutils::query{'publisher-name'},
        'SCRIPT' => $ENV{'SCRIPT_NAME'},
        'HOST'   => $ENV{'SERVER_NAME'},
        'URL'    => $url,
        'SEND'   => $pairs,
        'RETURN' => $resp
      }
    );
  }
}

sub input_swipe {
  my (%query) = @_;
  my ( $tracklevel, $data, $track1data, $track2data, $name );

  if ( $query{'magstripe'} =~ /.*\%\b(.*)?\?\;?(.*)\??/i ) {
    $tracklevel = 1;
    $track1data = $1;
    $track2data = $2;
  } elsif ( $query{'magstripe'} =~ /^\;(.*)\?$/ ) {
    $track2data = $1;
    $tracklevel = 2;
  }
  if ( $tracklevel == 1 ) {
    ( $query{'card-number'}, $name, $data ) = split( /\^/, $track1data );
    $query{'card-exp'} = substr( $data, 2, 2 ) . substr( $data, 0, 2 );
    if ( $query{'card-name'} eq "" ) {
      $query{'card-name'} = $name;
    }
  } elsif ( $tracklevel == 2 ) {
    ( $query{'card-number'}, $data ) = split( /=/, $track2data );
    $query{'card-exp'} = substr( $data, 2, 2 ) . substr( $data, 0, 2 );
  }
  return %query;
}

sub Round {
  my $item = shift(@_);

  my $temp1 = ( int( $item * 100 ) * 10 );
  my $temp2 = int( $item * 1000 );
  my $temp3 = $temp2 - $temp1;               #get tenths of a pennie

  my $trunc = 0;                             #round down
  if ( $temp3 >= 5 ) {
    $trunc = 10;                             #round up
  }
  my $value = ( $temp1 + $trunc ) / 1000;
  my $retval = sprintf( "%.2f", $value );

  return ($retval);
}

sub contenttype {
  my ( $pairs, %input );
  %input = ();
  $pairs = "";
  my ( $ct_ext, $ct_format ) =
    split( '\:', $mckutils::feature{'contenttype'} );

  if ( $mckutils::result{'FinalStatus'} ne "success" ) {
    $mckutils::query{'MErrMsg'}     = $mckutils::result{'MErrMsg'};
    $mckutils::query{'success'}     = $mckutils::mckutils::success;
    $mckutils::query{'auth-code'}   = $mckutils::result{'auth-code'};
    $mckutils::query{'avs-code'}    = $mckutils::result{'avs-code'};
    $mckutils::query{'auth-msg'}    = $mckutils::result{'auth-msg'};
    $mckutils::query{'pnpid'}       = $mckutils::cookie{'pnpid'};
    $mckutils::query{'FinalStatus'} = $mckutils::result{'FinalStatus'};
    $mckutils::query{'resp-code'}   = $mckutils::result{'resp-code'};
    if ( exists $mckutils::result{'due-amount'} ) {
      $mckutils::query{'due-amount'} = $mckutils::result{'due-amount'};
    }
    delete $mckutils::query{'bcommonname'};
    delete $mckutils::query{'scommonname'};
    delete $mckutils::query{'orderID'};
  } else {
    $mckutils::query{'success'}     = $mckutils::success;
    $mckutils::query{'MErrMsg'}     = "";
    $mckutils::query{'resp-code'}   = $mckutils::result{'resp-code'};
    $mckutils::query{'auth-code'}   = $mckutils::result{'auth-code'};
    $mckutils::query{'avs-code'}    = $mckutils::result{'avs-code'};
    $mckutils::query{'auth-msg'}    = $mckutils::result{'auth-msg'};
    $mckutils::query{'FinalStatus'} = $mckutils::result{'FinalStatus'};
  }
  $mckutils::query{'id'} = $mckutils::orderID;

  if ( exists $mckutils::query{'accountnum'} ) {
    $mckutils::query{'accountnum'} = $mckutils::filteredAN;
  }

  if ( exists $mckutils::query{'ssnum'} ) {
    $mckutils::query{'ssnum'} = $mckutils::filteredSSN;
  }

  if ( ( $mckutils::query{'client'} =~ /coldfusion/i )
    || ( $mckutils::query{'CLIENT'} =~ /coldfusion/i ) ) {
    my @array = %mckutils::query;
    %input = &miscutils::output_cold_fusion(@array);
  } else {
    %input = %mckutils::query;
  }

  if ( exists $input{'auth-code'} ) {
    $input{'auth-code'} = substr( $input{'auth-code'}, 0, 6 );
  }
  if ( exists $input{'auth_code'} ) {
    $input{'auth_code'} = substr( $input{'auth_code'}, 0, 6 );
  }

  if ( $ct_format eq "xml" ) {
    ### Need to Generate XML response here
  } else {
    foreach my $key ( keys %input ) {
      if ( ( $key ne "year-exp" )
        && ( $key ne "month-exp" )
        && ( $key ne "max" )
        && ( $key ne "pass" )
        && ( $key ne "attempts" )
        && ( $key ne "$result{'FinalStatus'}-link" )
        && ( $key ne 'User-Agent' )
        && ( $key ne 'acct_code3' )
        && ( $key ne 'acct_code4' ) ) {
        if ( ( ( $key =~ /^(card-number|card-exp)$/ ) && ( $mckutils::sendcc == 1 ) )
          || ( $key !~ /^(card-number|card-exp|card-cvv|month-exp|year-exp|card_cvv|card_number|month_exp|year_exp)$/ ) ) {
          $_ = $input{$key};
          s/(\W)/'%' . unpack("H2",$1)/ge;
          if ( $pairs ne "" ) {
            $pairs = "$pairs\&$key=$_";
          } else {
            $pairs = "$key=$_";
          }
        }
      }
    }
  }

  my $boundary = "----=_NextPart_XXXXXXXXXXXXXXXXXXXXXXXXXXXx";

  print "MIME-Version: 1.0\n";
  print "Content-Type: multipart/mixed; boundary=\"$boundary\"\n\n";
  print "$boundary\n";
  print "Content-Disposition: inline; filename=\"results.$ct_ext\"\n";
  print "Content-Type: application/$ct_ext\n\n";
  print "$pairs\n";
  print "$boundary\n";
  print "Content-Type: text/html;charset=iso-8859-1\n\n";

  return $boundary;
}

sub storeresults {
  my ( $filename, $pairs, $message, %input );
  %input = ();
  $pairs = "";

  my $path_base = "/home/p/pay1/private/tranresults/";
  my $path_cgi  = "/results.cgi";

  my ( $ct_ext, $ct_format ) =
    split( '\:', $mckutils::feature{'storeresults'} );

  if ( $mckutils::result{'FinalStatus'} ne "success" ) {
    $mckutils::query{'MErrMsg'}     = $mckutils::result{'MErrMsg'};
    $mckutils::query{'success'}     = $mckutils::mckutils::success;
    $mckutils::query{'auth-code'}   = $mckutils::result{'auth-code'};
    $mckutils::query{'avs-code'}    = $mckutils::result{'avs-code'};
    $mckutils::query{'auth-msg'}    = $mckutils::result{'auth-msg'};
    $mckutils::query{'pnpid'}       = $mckutils::cookie{'pnpid'};
    $mckutils::query{'FinalStatus'} = $mckutils::result{'FinalStatus'};
    $mckutils::query{'resp-code'}   = $mckutils::result{'resp-code'};
    if ( exists $mckutils::result{'due-amount'} ) {
      $mckutils::query{'due-amount'} = $mckutils::result{'due-amount'};
    }
    delete $mckutils::query{'bcommonname'};
    delete $mckutils::query{'scommonname'};
    delete $mckutils::query{'orderID'};
  } else {
    $mckutils::query{'success'}     = $mckutils::success;
    $mckutils::query{'MErrMsg'}     = "";
    $mckutils::query{'resp-code'}   = $mckutils::result{'resp-code'};
    $mckutils::query{'auth-code'}   = $mckutils::result{'auth-code'};
    $mckutils::query{'avs-code'}    = $mckutils::result{'avs-code'};
    $mckutils::query{'auth-msg'}    = $mckutils::result{'auth-msg'};
    $mckutils::query{'FinalStatus'} = $mckutils::result{'FinalStatus'};
  }
  $mckutils::query{'id'} = $mckutils::orderID;

  if ( exists $mckutils::query{'accountnum'} ) {
    $mckutils::query{'accountnum'} = $mckutils::filteredAN;
  }

  if ( exists $mckutils::query{'ssnum'} ) {
    $mckutils::query{'ssnum'} = $mckutils::filteredSSN;
  }

  if ( ( $mckutils::query{'client'} =~ /coldfusion/i )
    || ( $mckutils::query{'CLIENT'} =~ /coldfusion/i ) ) {
    my @array = %mckutils::query;
    %input = &miscutils::output_cold_fusion(@array);
  } else {
    %input = %mckutils::query;
  }

  ## Add Masked CN
  my ($cardnumber);
  if ( $mckutils::query{'convert'} =~ /underscores/i ) {
    $cardnumber = $mckutils::query{'card_number'};
  } else {
    $cardnumber = $mckutils::query{'card-number'};
  }
  my $first4 = substr( $cardnumber, 0, 4 );
  my $last4  = substr( $cardnumber, -4 );
  my $CClen  = length($cardnumber);
  $cardnumber =~ s/./\*/g;
  $cardnumber = $first4 . substr( $cardnumber, 4, $CClen - 8 ) . $last4;
  if ( $mckutils::query{'convert'} =~ /underscores/i ) {
    $input{'card_number'} = $cardnumber;
  } else {
    $input{'card-number'} = $cardnumber;
  }

  if ( exists $input{'auth-code'} ) {
    $input{'auth-code'} = substr( $input{'auth-code'}, 0, 6 );
  }
  if ( exists $input{'auth_code'} ) {
    $input{'auth_code'} = substr( $input{'auth_code'}, 0, 6 );
  }

  $input{'orderID'} = $mckutils::query{'id'};

  my $errmsg = $mckutils::query{'MErrMsg'};

  if ( $ct_format =~ /^xml$/i ) {
    ### Need to Generate XML response here
    require xmlparse2;
    my @array = (%input);
    $message .= &xmlparse2::output_xml( '1', @array );
    $message = &xmlparse2::xml_wrapper( $message, $input{'publisher-name'} );
  } else {
    foreach my $key ( keys %input ) {
      if ( ( $key !~ /^card.number/i )
        && ( $key !~ /.link$/i )
        && ( $key !~ /merch.txn/i )
        && ( $key !~ /cust.txn|User.Agent|card.allowed|receipt.type|confemailtemplate/i )
        && ( $key !~ /month.exp/i )
        && ( $key !~ /year.exp/i )
        && ( $key !~ /card.cvv/i )
        && ( $key !~ /publisher\-password/i )
        && ( $key !~ /magstripe/i )
        && ( $key !~ /^MErrMsg$/i )
        && ( $key !~ /path.*cgi/i )
        && ( $key !~ /image.placement/i )
        && ( $key ne "" ) ) {
        $_ = $input{$key};
        s/(\W)/'%' . unpack("H2",$1)/ge;
        if ( $pairs ne "" ) {
          $pairs = "$pairs\&$key=$_";
        } else {
          $pairs = "$key=$_";
        }
      }
    }
    $errmsg =~ s/(\W)/'%' . unpack("H2",$1)/ge;
    if ( $errmsg ne "" ) {
      if ( $mckutils::query{'client'} =~ /^(coldfusion|miva)/i ) {
        $pairs .= "\&MERRMSG=$errmsg";
      } else {
        $pairs .= "\&MErrMsg=$errmsg";
      }
    }
    $message = $pairs;
  }

  ### Generate Random File Name
  my $size = 40;
  my @alphanumeric = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
  $filename = join '', map $alphanumeric[ rand @alphanumeric ], 0 .. $size;

  ### Write Data to file
  my $content = <<"EOF";
Content-Disposition: inline; filename="results.$ct_ext"
Content-Type: application/$ct_ext

$message
EOF

  my $wdf = new PlugNPay::WebDataFile();
  $wdf->writeFile(
    { storageKey => 'transactionResults',
      fileName   => "$filename\.txt",
      content    => $content
    }
  );

  my $onload = "onLoad=\"window.location.href=\'$path_cgi/results.$ct_ext\?$filename\';return true;\" ";

  return $onload;

}

sub cal2sec {

  # converts date to seconds (in GMT Epoch Seconds)
  my ( $seconds, $minutes, $hours, $day, $month, $year ) = @_;

  # $day is day in month (1-31)
  # $month is month in year (1-12)
  # $year is four-digit year (e.g. 1967)
  # $hours, $minutes and $seconds represent UTC time

  #use Time::Local;
  my $time = timegm( $seconds, $minutes, $hours, $day, $month - 1, $year - 1900 );

  return ($time);
}

sub receiptcc {
  my %masklength = ( 'ach', 40, 'credit', 20 );
  my ($paymentType);
  if ( $mckutils::query{'accttype'} =~ /^(checking|savings)$/ ) {
    $paymentType = 'ach';
  } else {
    $paymentType = 'credit';
  }
  ## Or do we just not chop?  Is it necessary?
  my $receiptcc =
    substr( $mckutils::query{'card-number'}, 0, $masklength{$paymentType} );

  if ( $mckutils::feature{'expandedmsk'} == 1 ) {
    $mckutils::query{'receiptcc'} = substr( $receiptcc, 0, 6 ) . ( 'X' x ( length($receiptcc) - 10 ) ) . substr( $receiptcc, -4 );    # Format: first6, X's, last4
  } else {
    $mckutils::query{'receiptcc'} =
      ( 'X' x ( length($receiptcc) - 4 ) ) . substr( $receiptcc, -4, 4 );
  }

  if ( $mckutils::feature{'returnCardHash'} == 1 ) {
    ####  DCP 20151006  - Upgrade in future to use merchant provided salt and SHA256
    my $cc = new PlugNPay::CreditCard( $mckutils::query{'card-number'} );
    $mckutils::query{'cardhash'} = $cc->getCardHash();
  }

  return;
}

sub formpostproxy {
  my $env       = new PlugNPay::Environment();
  my $remote_ip = $env->get('PNP_CLIENT_IP');

  my ( $url, $querystring, $username, $method ) = @_;
  $url =~ s/(\W)/'%' . unpack("H2",$1)/ge;
  $querystring =~ s/(\W)/'%' . unpack("H2",$1)/ge;
  my $addr  = "https://10.150.6.80/successlink2.cgi";
  my $pairs = "url=$url&method=$method&username=$username&querystring=$querystring";

  my (%headers);
  my $ua = new LWP::UserAgent;
  $ua->agent( "AgentName/0.1 " . $ua->agent );
  $ua->timeout(60);

  my $req = new HTTP::Request POST => $addr;
  $req->content_type('application/x-www-form-urlencoded');
  $req->content($pairs);

  my $res = $ua->request($req);

  my $response = $res->content;
  $response =~ /^(\-\-\=\=PNPBOUNDARY--\w+)/;
  my $boundary = $1;
  $response =~ s/$boundary\n//;
  my ( $headers, $body ) = split( /$boundary/, $response );

  my @headers = split( /\n/, $headers );    ###  Obtain headers from response.
  foreach my $var (@headers) {
    my ( $key, $val ) = split( /\: /, $var );
    if ( $key eq "" ) {
      next;
    }
    $key =~ tr/A-Z/a-z/;
    $headers{$key} = "$val";                ### Obtain value for header in response.
  }

  if ( ( $headers{'httpresponse'} =~ /302/ )
    && ( $headers{'location'} !~ /^https?\:\/\//i ) ) {
    $url =~ s/%(..)/pack('c',hex($1))/eg;
    $url =~ /^(https?\:\/\/[a-z0-9\-\.]+)\/(.*)/i;
    my $domain = $1;
    my $path   = $2;

    my ( $newpath, $newrootpath );

    if (1) {
      my @urlpath       = split( /\//, $path );
      my @redirect_path = split( /\//, $headers{'location'} );
      print "DOM:$domain, PATH:$path<br>\n";
      ## drop script name.
      pop @urlpath;
      foreach my $var (@redirect_path) {
        print "VAR:$var<br>\n";
        if ( $var eq ".." ) {
          my $test = pop @urlpath;

          #print "POPED:$test\n";
          next;
        } elsif ( $var eq "." ) {
          ## Do nothing
          next;
        } elsif ( $var eq "" ) {

        } else {
          $newpath .= "/$var";
        }

        #print "NEWPATH:$newpath<br>\n";
      }
      if ( $headers{'location'} =~ /^\// ) {
        $newrootpath = "";
      } else {
        foreach my $var (@urlpath) {

          #print "URLVAR:$var\n";
          $newrootpath .= "/$var";
        }
      }
    }
    $headers{'location'} = $domain . $newrootpath . $newpath;
  }

  if (0) {
    my $mytime = localtime( time() );
    open( TMPFILE, ">>/home/p/pay1/database/debug/formpostproxy2.txt" );
    print TMPFILE "$mytime,  RA:$remote_ip,  PID:$$, URL:$url, QS:$querystring, UN:$username, METH:$method, PAIRS:$pairs\n";
    foreach my $key ( sort keys %headers ) {
      print TMPFILE "Key:$key,$headers{$key}\n";
    }
    print TMPFILE "RESP:$response:\n";
    print TMPFILE "BODY:$body\n";
    close(TMPFILE);
  }

  return $body, %headers;
}

sub check_service {

  # Checks to see if merchant is subscribed for a given premium service
  # Used by API modes which interact with premium services, to ensure only subscribed premium services are allowed
  # Requires merchant username & service name to check.
  # Function returns "yes", "no", or "problem" for whether merchant is subscribed to given service
  # - For 'yes' responses, includes what's set our pnpsetups table, so we can use it to determin a specific level/version of the service (i.e. for membership)
  # - For 'no' responses, includes an error message that can be passed onto the end-user.
  # - For 'problem' responses, includes an error message indicating what went wrong.

  my ( $merchant, $service ) = @_;

  $merchant =~ s/[^a-zA-Z0-9]//g;
  $merchant = lc($merchant);
  if ( $merchant eq "" ) {
    return ( "problem", "Missing merchant/publisher name." );
  }

  $service =~ s/[^a-zA-Z0-9]//g;
  $service = lc($service);
  if ( $service !~ /^(membership|download|fraudtrack|coupon|fulfillment|affiliate|easycart|billpay)$/ ) {
    return ( "problem", "Invalid service name." );
  }

  my $dbh = &miscutils::dbhconnect("pnpmisc");
  my $sth = $dbh->prepare(
    qq{
      select $service
      from pnpsetups
      where username=?
    }
  ) or die "Can't prepare: $DBI::errstr";
  $sth->execute("$merchant") or die "Can't execute: $DBI::errstr";
  my $test = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  if ( $test ne "" ) {
    return ( "yes", "$test" );
  } else {
    return ( "no", "Account not configured for this service. Please contact your sales rep to subscribe for this service." );
  }
}

sub retrieve_pairs {
  my ($pairsref) = @_;
  my %pairs = ();
  my ( $name, $value, $valtxt );
  my $datafound = 0;
  my $dbh       = &miscutils::dbhconnect("pnpmisc");
  my $sth       = $dbh->prepare(
    qq{
      select name,value,valtxt
      from paypairs
      where rowref=?
    }
  );
  $sth->execute("$pairsref");
  $sth->bind_columns( undef, \( $name, $value, $valtxt ) );

  while ( $sth->fetch ) {
    if ( $valtxt ne "" ) {
      $value = $valtxt;
    }
    $name =~ s/%(..)/pack('c',hex($1))/eg;
    $value =~ s/%(..)/pack('c',hex($1))/eg;
    $pairs{$name} = $value;
    $datafound = 1;
  }
  $sth->finish;
  $dbh->disconnect;
  return $datafound, %pairs;
}

sub resp_hash {
  my ( $feature, $query_hash, $result_hash, $convfee_flag ) = @_;

  # this is here to not overwrite resphash if a conv fee tran occurs!
  if ( ( $feature->{'hashkey'} ne "" ) && ( $convfee_flag != 1 ) ) {
    my ($cardAmount);
    if ( $query_hash->{'card-amount'} eq "" ) {
      $cardAmount = "0.00";
    } else {
      $cardAmount = $query_hash->{'card-amount'};
    }

    my @fieldsAndStuff = split( '\|', $feature->{'hashkey'} );
    my $secret         = shift @fieldsAndStuff;
    my @fields         = @fieldsAndStuff;

    my %allData = ( %{$query_hash}, %{$result_hash} );
    $allData{'card-amount'} = $cardAmount;

    my $digestData = PlugNPay::Merchant::VerificationHash::Digest::createDigestData(
      { sortFields => 0,
        fields     => \@fields,
        sourceData => \%allData
      }
    );

    my $digests = PlugNPay::Merchant::VerificationHash::Digest::digest(
      { secret     => $secret,
        digestData => $digestData
      }
    );

    return $digests;
  }

  return {
    md5Sum => $query_hash->{'resphash'},
    sha256Sum => $query_hash->{'resphash_sha256'}
  };
}

sub logFeesIfApplicable {
  my $type           = shift;
  my $query          = shift;
  my $result         = shift;
  my $adjustmentFlag = shift;
  my $convFeeAccount = shift;
  my $convFeeOrderId = shift;

  if ( !$adjustmentFlag ) {
    return;
  }

  if ( $result->{'Duplicate'} eq 'yes' ) {
    return;
  }

  return &logFees( $type, $query, $result, $convFeeAccount, $convFeeOrderId );

}

sub publisherNameFromQuery {
  my $query = shift;
  return
       $query->{'publisher-name'}
    || $query->{'publisher_name'}
    || $query->{'merchant'}
    || $query->{'x_merchant'};
}

sub logFees {
  my $type           = shift;
  my $query          = shift;
  my $result         = shift;
  my $convFeeAccount = shift;
  my $convFeeOrderId = shift;
  my ( $transaction, $baseAmount, $fee );

  # make a copy of query so we don't mess it up
  my %queryCopy = %{$query};
  $query = \%queryCopy;

  # ensure publisher_name is set from one of its possible alternative keys, as that's what api uses
  $query->{'publisher_name'} = publisherNameFromQuery($query);

  if ( !defined $query->{'publisher_name'}
    || $query->{'publisher_name'} eq '' ) {
    return;
  }

  my $COA = new PlugNPay::COA( $query->{'publisher_name'} );

  if ( $COA->isSurcharge() ) {
    $fee        = sprintf( "%0.2f", $query->{'surcharge'} );
    $baseAmount = sprintf( "%0.2f", $query->{'card-amount'} - $fee + .00001 );
  } elsif ( $COA->isFee() ) {
    $fee = sprintf( "%0.2f", $result->{'convfeeamt'} );
    $baseAmount = $query->{'card-amount'};
  } elsif ( $COA->isOptional() ) {
    $fee        = sprintf( "%0.2f", $query->{'surcharge'} );
    $baseAmount = sprintf( "%0.2f", $query->{'card-amount'} - $fee + .00001 );
  }

  my $api = new PlugNPay::API('api_payment');
  $api->setLegacyParameters($query);

  if ( $query->{'accttype'} =~ /^(checking|savings)$/ ) {
    $transaction = new PlugNPay::Transaction( 'auth', 'ach' );
  } else {
    $transaction = new PlugNPay::Transaction( 'auth', 'card' );
  }

  my $mapper = new PlugNPay::Transaction::MapAPI();
  $mapper->map( $api => $transaction );

  my $adjustmentLog = new PlugNPay::Transaction::Logging::Adjustment();
  $adjustmentLog->setGatewayAccount( $transaction->getGatewayAccount() );
  $adjustmentLog->setOrderID( $transaction->getOrderID() );
  $adjustmentLog->setBaseAmount($baseAmount);
  $adjustmentLog->setAdjustmentTotalAmount($fee);
  my $hexID = $result{'pnp_transaction_id'};
  if ($hexID) {
    my $id = new PlugNPay::Util::UniqueID();
    $id->fromHex($hexID);
    $adjustmentLog->setPNPTransactionID( $id->inBinary() );
  }

  if ( ( $COA->isFee() ) && ( defined $query->{'convfeeamt'} ) ) {
    $adjustmentLog->setAdjustmentGatewayAccount($convFeeAccount);
    $adjustmentLog->setAdjustmentOrderID($convFeeOrderId);
  }

  $adjustmentLog->log();

  return;
}

sub log_filter {
  my ($hash) = @_;
  my %logdata = ();
  foreach my $key ( keys %$hash ) {
    $$hash{$key} =~ s/(\n|\r)//g;
    if ( $key =~ /card.*num|accountnum|acct_num|ccno/i ) {
      $logdata{$key} = substr( $$hash{$key}, 0, 6 ) . ( 'X' x ( length( $$hash{$key} ) - 8 ) ) . substr( $$hash{$key}, -2 );    # Format: first6, X's, last2
    } elsif ( ( $key =~ /^(TrakData|magstripe)$/i )
      && ( $$hash{$key} ne "" ) ) {
      $logdata{$key} =
        "Data Present:" . substr( $$hash{$key}, 0, 6 ) . "****" . "0000";
    } elsif ( ( $key =~ /^(data)$/i ) && ( $$hash{$key} ne "" ) ) {
      $logdata{$key} = "Batch File Present";
    } elsif ( $key eq "cvvresp" ) {
      $logdata{$key} = $$hash{$key};
    } elsif ( $key =~ /(cvv|pass.*w.*d|x_tran_key|card.code)/i ) {
      $logdata{$key} = $$hash{$key};
      $logdata{$key} =~ s/./X/g;
    } elsif ( ( $key =~ /^(ssnum|ssnum4)$/i )
      || ( $key =~ /^($smps::feature{'mask_merchant_variables'})$/ ) ) {
      $logdata{$key} = ( 'X' x ( length( $$hash{$key} ) - 4 ) ) . substr( $$hash{$key}, -4, 4 );
    } elsif ( $key eq "auth-code" ) {
      $logdata{$key} = substr( $$hash{$key}, 0, 6 );
    } else {
      my ( $key1, $val ) = &logfilter_in( $key, $$hash{$key} );
      $logdata{$key1} = $val;
    }
  }
  return %logdata;
}

sub logfilter_in {
  my ( $key, $val ) = @_;

  if ( $key =~ /^(orderid|refnumber|certitaxid)$/i ) {
    return ( $key, $val );
  }

  if ( $key =~ /([3-7]\d{13,19})/ ) {
    $key =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  if ( $val =~ /([3-7]\d{12,19})/ ) {
    $val =~ s/([3-7]\d{13,19})/&logfilter_sub($1)/ge;
  }

  return ( $key, $val );
}

sub logfilter_sub {
  my ($stuff) = @_;

  my $luhntest = &miscutils::luhn10($stuff);
  if ( $luhntest eq "success" ) {
    $stuff =~ s/./X/g;
  }

  return $stuff;
}

sub storeRespLinkData {
  my ($logData) = @_;
  my ($pairs);

  # create array of parameters we don't want to send
  my @deleteParameters = (
    'year-exp', 'year_exp', 'month-exp', 'month_exp', 'max', 'pass', 'attempts', 'customname99999999', 'customvalue99999999', 'acct_code4', 'card-number', 'card_number', 'card-cvv', 'card_cvv',
    'magstripe', 'magensacc', 'mpgiftcard', 'mpcvv'
  );

  # delete the parameters we don't want to send back
  foreach my $parameter (@deleteParameters) {
    delete $$logData{$parameter};
  }

  if ( $$logData{'accttype'} eq "credit" ) {

    # do this so we send back a masked card number in pt_card_number
    $$logData{'card-number'} = $$logData{'receiptcc'};
  } elsif ( $$logData{'accttype'} =~ /^(checking|savings)$/ ) {
    ##  Should we be masking routing number ?
    $$logData{'accountnum'} = ( 'X' x ( length( $$logData{'accountnum'} ) ) ) . substr( $$logData{'accountnum'}, -4, 4 );
  } else {
    ## Area they any other acct types we should be masking
  }

  my $logData = { &log_filter($logData) };

  my $api = new PlugNPay::API('payscreens');
  $logData = $api->convertLegacyParameters($logData);
  PlugNPay::DBConnection::cleanup();

  # flag this data set as being for reporting purposes
  $$logData{'reportingData'} = "1";

  # add param to indicate processing script source
  my $tranSource  = "";
  my @scriptpaths = split( '/', $ENV{'SCRIPT_NAME'} );
  my $scriptname  = pop(@scriptpaths);
  if ( $scriptname =~ /smps\.cgi|virtual/ ) {
    $tranSource = 'vrt';
  } elsif ( $scriptname =~ /remotepos/ ) {
    $tranSource = 'remotePOS';
  } elsif ( $scriptname =~ /pnpremote/ ) {
    $tranSource = 'remoteClient';
  } elsif ( $scriptname =~ /auth\.cgi|$mckutils::query{'publisher-name'}\.cgi/ ) {
    $tranSource = 'direct';
  } elsif ( $scriptname =~ /Collect Batch/ ) {
    $tranSource = "collectBatch";
  } else {
    $tranSource = 'unknown';
  }
  $$logData{'tranSource'} = $tranSource;

  # add param to indicate LOGIN if applicable
  if ( $ENV{'LOGIN'} ne "" ) {
    $$logData{'LOGIN'} = $ENV{'LOGIN'};
  }

  # url encode the parameters we want to log
  my %encodedInput;
  foreach my $parameter ( keys %$logData ) {
    $encodedInput{ uri_escape($parameter) } =
      uri_escape( $$logData{$parameter} );
  }

  # generate QueryString
  $pairs =
    join( '&', map { $_ . '=' . $encodedInput{$_} } keys %encodedInput );

  my $rl = new PlugNPay::ResponseLink( $$logData{'pb_merchant'}, '', $pairs, 'post', 'meta' );
  $rl->doRequest();

  return;
}

sub overrideAdjustment {
  my $coa      = new PlugNPay::COA( $mckutils::query{'publisher-name'} );
  my $username = new PlugNPay::Username("rc_$mckutils::query{'publisher-name'}");

  if ( $mckutils::query{'override_adjustment'} == 1 ) {
    if ( $coa->getCustomerCanOverride()
      || $username->verifyPassword( $mckutils::query{'publisher-password'} ) ) {
      return 1;
    }
  }
  return 0;
}

sub tds {
  my $type        = shift;
  my ($tdsresult) = @_;
  my %tdsresult   = ();
  if ( ref($tdsresult) =~ /^hash$/i ) {
    %tdsresult = %{$tdsresult};
  }

  if ( ( $tdsresult{'tdsfinal'} == 1 ) && ( $tdsresult{'status'} eq "N" ) ) {

    # Not allowed to continue transaction
    $result{'FinalStatus'} = "problem";
    $result{'MErrMsg'}     = $tdsresult{'descr'};
    $result{'tds_status'}  = $tdsresult{'status'};
  } elsif ( $tdsresult{'tdsfinal'} == 1 ) {

    # continue transaction, status empty or status=U up to merchant
    $result{'FinalStatus'} = $tdsresult{'FinalStatus'};
    $result{'refnumber'}   = $tdsresult{'refnumber'};
    $result{'auth-code'}   = substr( $tdsresult{'auth-code'}, 0, 6 );
    $result{'avs-code'}    = $tdsresult{'avs-code'};

    $mckutils::query{'cavv'} = $tdsresult{'cavv'};
    $mckutils::query{'xid'}  = $tdsresult{'xid'};
    $mckutils::query{'eci'}  = $tdsresult{'eci'};
  } else {

    # merchant and cardholder enrolled. creating authentication request.
    my $price = sprintf( "%s %.2f", $mckutils::query{'currency'}, $mckutils::query{'card-amount'} );
    my $addr = $mckutils::query{'card-address1'} . " " . $mckutils::query{'card-address2'};
    $addr = substr( $addr, 0, 50 );
    my $country = substr( $mckutils::query{'card-country'}, 0, 2 );

    %tdsresult = &tds::authenticate(
      $mckutils::query{'publisher-name'}, $tdsresult{'querystr'},          'order-id',  $mckutils::query{'orderID'},
      'card-number',                      $mckutils::query{'card-number'}, 'card-exp',  $mckutils::query{'card-exp'},
      'card-cvv',                         $mckutils::query{'card-cvv'},    'card-name', $mckutils::query{'card-name'},
      'card-address',                     $addr,                           'card-city', $mckutils::query{'card-city'},
      'card-state',                       $mckutils::query{'card-state'},  'card-zip',  $mckutils::query{'card-zip'},
      'card-country',                     $country,                        'phone',     $mckutils::query{'phone'},
      'email',                            $mckutils::query{'email'},       'termurl',   $mckutils::query{'termurl'},
      'merchanturl',                      $mckutils::query{'merchanturl'}, 'amount',    $price
    );
    if ( $tdsresult{'status'} eq "Y" ) {

      # this web page gets printed on the customers browser
      $tdsresult{'FinalStatus'} = "success";
      $tdsresult{'tdsauthreq'}  = $tdsresult{'pareq'};
    } elsif ( $tdsresult{'status'} eq "N" ) {

      # person not enrolled, up to merchant
      $tdsresult{'eci'} = "06";
      if ( $tdsresult{'refnumber'} ne "" ) {
        $mckutils::query{'refnumber'} = $tdsresult{'refnumber'};
      }
    } elsif ( $tdsresult{'descr'} ne "" ) {

      # something went wrong, up to merchant
      $tdsresult{'eci'}      = "06";
      $result{'FinalStatus'} = "problem";
      $result{'MErrMsg'}     = $tdsresult{'descr'};
      $result{'tds_status'}  = $tdsresult{'status'};
    } else {

      # merchant not enrolled in 3dsecure
      $tdsresult{'eci'} = "07";
    }
  }

  my $time      = gmtime(time);
  my %logResult = %tdsresult;
  delete $logResult{'querystr'};
  my $dataToLog = {
    dataFormat    => 'legacy',
    merchant      => $mckutils::query{'publisher-name'},
    orderID       => $mckutils::query{'orderID'},
    logTime       => $time,
    remoteAddress => $remote::remoteaddr,
    script        => $ENV{'SCRIPT_NAME'},
    host          => $ENV{'SERVER_NAME'},
    port          => $ENV{'SERVER_PORT'},
    pid           => $ENV{'SERVER_PORT'},
    tdsresult     => \%logResult,
  };

  my $dataLogger = new PlugNPay::Logging::DataLog( { collection => 'debugLogsTDS' } );
  my $json = $dataLogger->log($dataToLog);

  if ( !exists $tdsresult{'FinalStatus'} ) {
    %result = &purchase( 'self', "auth" );
  } else {
    %result = %tdsresult;
  }

  return %result;
}

sub isStoreData {
  my $data        = shift;
  my $isStoreData = 0;

  my $allowStoreData = $data->{'allowStoreData'};
  my $storeData      = $data->{'storeData'};
  my $paymentMethod  = $data->{'paymentMethod'};
  my $allowInvoice   = $data->{'allowInvoice'};
  my $allowFreePlans = $data->{'allowFreePlans'};
  my $plan           = $data->{'plan'};
  my $cardAmount     = $data->{'cardAmount'};
  my $transFlags     = $data->{'transFlags'};

  if ( $allowStoreData && $storeData ) {    # use store data if 'storedata' is passed
    $isStoreData = 1;
  } elsif ( ( $paymentMethod =~ /invoice/i ) && $allowInvoice ) {    # use store data for invoices
    $isStoreData = 1;
  } elsif ( $allowFreePlans
    && ( $plan ne '' )
    && ( $cardAmount == 0.00 )
    && ( $transFlags !~ /avsonly/ ) ) {                              # use store data for free membership plans
    $isStoreData = 1;
  } elsif ( $paymentMethod eq 'goCart' ) {                           # use store data for GoCart transactions
    $isStoreData = 1;
  }

  return $isStoreData;
}

1;
