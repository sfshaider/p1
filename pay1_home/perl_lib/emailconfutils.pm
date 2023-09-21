package emailconfutils;

use pnp_environment;
use constants qw(%avs_responses %cvv_hash);
use miscutils;
use Text::Table;
use Tie::IxHash;
use sysutils;
use PlugNPay::Util::CardFilter;
use PlugNPay::Email;
use PlugNPay::Logging::Performance;
use PlugNPay::Features;
use PlugNPay::Reseller;
use PlugNPay::Currency;
use strict;

sub new {
  my $type = shift;

  my ($info) = @_;  

  # layout for info?
  #  $info->{'query'} = \%query;
  #  $info->{'result'} = \%result;
  #  $info->{'feature'} = \%feature;
  #  $info->{'reseller'} = $reseller;
  #  $info->{'emailextrafields'} = \@emailextrafields;
  $emailconfutils::query = $info->{'query'};
  $emailconfutils::result = $info->{'result'};
  $emailconfutils::feature = $info->{'feature'};
  $emailconfutils::fraud_config = $info->{'fraud_config'};
  $emailconfutils::reseller = $info->{'reseller'};
  $emailconfutils::emailextrafields = $info->{'emailextrafields'};
  $emailconfutils::esub = $info->{'esub'};
  $emailconfutils::email_template_path = &pnp_environment::get('PNP_WEB_TXT') . "/emailconf/templates/";
  $emailconfutils::emailconftablespace = "emailconf";
  $emailconfutils::max = 0;
  $emailconfutils::resellerData = new PlugNPay::Reseller($emailconfutils::reseller);
  $emailconfutils::accountFeatures = new PlugNPay::Features($emailconfutils::query{'publisher-name'},'general');

  return [], $type;
}

sub pick_template {
  my $this = shift;
  my ($email_type) = @_;

  if ($emailconfutils::accountFeatures->get('enhancedLogging') == 1) {
    new PlugNPay::Logging::Performance('pickEmailTemplate');
  }

  # $message_to_use controls what email template is opened for parsing
  # $quantity total is used to count the number of items the user has purchased
  #   and to choose the proper email template.  This is probably done some
  #   where else and possibly could be moved out of here.
  # %item_list is a hash that contains items and there values and is used for 
  #   the item test to choose an email template
  # $body current template file name selected from the emailconf database
  # $include current test string for the current $body
  # %files_to_test used to temp store template file names and include test string
  #   so db handle can be dropped faster

  my $message_to_use = "";
  my $quantity_total = 0;
  my %item_list = ();
  $emailconfutils::max = 0;
  # get an array together of items and total quantity to be used in deciding
  # which template to use
  foreach my $key (sort keys %{$emailconfutils::query}) {
    if ($key =~ /^item/) {
      $emailconfutils::max++;
      $item_list{$key} = $emailconfutils::query->{$key};
    }
    elsif ($key =~ /^quantity/) {
      $quantity_total += $emailconfutils::query->{$key};
    }
  }

  # now connect to emailconf and pull template info out and stuff it into
  # %templatehash a hash of arrays
  # body is the file name of the template stored in $email_template_path
  # include rules for deciding which template to use
  # type confirmation or marketing
  # emailtype type of email to send HTML or Text
  # weight weighting of template used for deciding which template to use
  # delay delay for sending marketing emails

  my $dbh_email = &miscutils::dbhconnect($emailconfutils::emailconftablespace);

  my $found_subacct = "no";
  my %templatehash = ();
  my $sth_email = $dbh_email->prepare(qq{
       select username,body,include,type,emailtype,weight,delay,data,description
       from emailconf
       where username in (?,?) and type=?
       order by include desc
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth_email->execute($emailconfutils::query->{'subacct'},$emailconfutils::query->{'publisher-name'},$email_type) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr"); 
  while (my $data = $sth_email->fetchrow_hashref) {
    $data->{'body'} =~ s/\r//g;

    if (($emailconfutils::query->{'subacct'} ne "") && ($data->{'body'} =~ /$emailconfutils::query->{'subacct'}/)) {
      $found_subacct = "yes";
    }
    $templatehash{$data->{'body'}} = $data;
  }
  $sth_email->finish;
  $dbh_email->disconnect;

  if ($found_subacct eq "yes") {
    for my $body (keys %templatehash) {
      if ($templatehash{$body}->{'username'} eq $emailconfutils::query->{'publisher-name'}) {
        delete $templatehash{$body};
      }
    }
  } # end found_subacct if
  # done creating %templatehash

  # really convulted sort used here to take care of sorting of include statements
  # first quantity then item then cost should hit.  based on mast algs in perl p117
  foreach my $body (reverse sort {return $templatehash{$a}->{'include'} cmp $templatehash{$b}->{'include'}} keys %templatehash) {
    if ($message_to_use eq "") {
      my ($what,$operator,$value,$subject) = split(/\:/,$templatehash{$body}->{'include'});

      if ($what eq "paymethod") {
        if ($emailconfutils::query->{'paymethod'} eq $value) {
          $message_to_use = $body;
          last;
        }
      }
      elsif ($what eq "item") {
        # foreach goes through list of items purchased and compares the include
        # test to see if it matches if it does it sets message_to_use and dumps
        # out of the test item loop
        foreach my $testitem (keys %item_list) {
          if ($item_list{$testitem} eq $value) {
            $message_to_use = $body;
            last;
          }
        }
      } 
      elsif ($what eq "plan") {
        if ($emailconfutils::query->{'plan'} eq $value) {
          $message_to_use = $body;
          last;
        }
      }
      elsif ($what eq "order-id") {
        if ($emailconfutils::query->{'order-id'} eq $value) {
          $message_to_use = $body;
          last;
        }
      }
      elsif ($what eq "purchaseid") {
        if ($emailconfutils::query->{'purchaseid'} eq $value) {
          $message_to_use = $body;
          last;
        }
      }
      elsif ($what eq "subacct") {
        if ($emailconfutils::query->{'subacct'} eq $value) {
          $message_to_use = $body;
          last;
        }
      }
      elsif ($what eq "acct_code") {
        if ($emailconfutils::query->{'acct_code'} eq $value) {
          $message_to_use = $body;
          last;
        }
      }
      elsif ($what eq "acct_code2") {
        if ($emailconfutils::query->{'acct_code2'} eq $value) {
          $message_to_use = $body;
          last;
        }
      }
      elsif ($what eq "acct_code3") {
        if ($emailconfutils::query->{'acct_code3'} eq $value) {
          $message_to_use = $body;
          last;
        }
      }
      elsif ($what eq "quantity") {
        if ($operator eq "lt") {
          if ($quantity_total < $value) {
            $message_to_use = $body;
            last;
          }
        }
        elsif ($operator eq "gt") {
          if ($quantity_total > $value) {
            $message_to_use = $body;
            last;
          }
        }
        elsif ($operator eq "eq") {
          if ($quantity_total == $value) {
            $message_to_use = $body;
            last;
          } 
        }
      }
      elsif ($what eq "cost") {
        if ($operator eq "lt") {
          if ($emailconfutils::query->{'card-amount'} < $value) {
            $message_to_use = $body;
            last;
          }
        }
        elsif ($operator eq "gt") {
          if ($emailconfutils::query->{'card-amount'} > $value) {
            $message_to_use = $body;
            last;
          }
        }
        elsif ($operator eq "eq") {
          if ($emailconfutils::query->{'card-amount'} == $value) {
            $message_to_use = $body;
            last;
          }
        } # end operator if
      } # end what if
    } # end message to use if
  } # end foreach body loop 
 
  # if we haven't found a match we use pnp default email message
  # this needs to be fixed no worky
  if ($message_to_use eq "") {
    my %temphash = ();
    $message_to_use = $email_type . ".msg";

    $temphash{'include'} = "none";
    $temphash{'type'} = $email_type;
    $temphash{'emailtype'} = "text";
    $temphash{'weight'} = "";
    $temphash{'delay'} = "0,none";
    $templatehash{'description'} = "pnp default";
    my $path_file = "$emailconfutils::email_template_path$message_to_use";
    $path_file =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
    &sysutils::filelog("read","$path_file");
    open(INFILE,"$path_file");
    while (<INFILE>) {
      $temphash{'data'} .= $_;
    }
    close INFILE;
    $templatehash{$message_to_use} = \%temphash;
  }

  $emailconfutils::query->{$email_type . "emailtemplate"} = $templatehash{$message_to_use}->{'description'};


  if ($emailconfutils::accountFeatures->get('enhancedLogging') == 1) {
    new PlugNPay::Logging::Performance('postEmailTemplate');
  }

  return \%{$templatehash{$message_to_use}};
}  

# it is important that the INT_ variables are set in query before
# calling this.  Look at sub email for examples.
sub generate_email {
  my $this = shift;
  my ($template) = @_;

  if (!defined $template->{'data'}) {
    return;
  }

  if ($emailconfutils::accountFeatures->get('enhancedLogging') == 1) {
    new PlugNPay::Logging::Performance('generateEmail');
  }

  my $parseflag = "";
#  my (%suppress_if_blank);
#  if ($emailconfutils::feature->{'suppress'} eq "yes") {
#    my @suppress_if_blank = ('agent','order-id','subtotal');
#    foreach my $var (@suppress_if_blank) { 
#      $suppress_if_blank{$var} = 1; 
#    }
#  }

  # message body
  my $message = "";
  my @productarray = ();
  my @looparray = ();
  my ($pnploopcnt);

  #start getting the email together for the customer
  if (($emailconfutils::result->{'FinalStatus'} eq "success") || ($template->{'type'} eq "merch")) {
    my $position = index($emailconfutils::query->{'INT_to_email'},"\@");
    if ((($position > 1) && (length($emailconfutils::query->{'INT_to_email'}) > 5)
          && ($position < (length($emailconfutils::query->{'INT_to_email'})-5)))
          || ($template->{'type'} eq "merch")) {


      if ($emailconfutils::accountFeatures->get('enhancedLogging') == 1) {
        new PlugNPay::Logging::Performance('prePnPEmail');
      }

      my $emailer = new PlugNPay::Email();
      $emailer->setVersion('legacy');
      $emailer->setGatewayAccount($emailconfutils::query->{'publisher-name'});


      if ($emailconfutils::accountFeatures->get('enhancedLogging') == 1) {
        new PlugNPay::Logging::Performance('postPnPEmail');
      }

      if  ($template->{'emailtype'} eq "html") {
        # add extra header junk for HTML email
        $emailer->setFormat('html');
      }
      else {
        $emailer->setFormat('text');
      }

      $emailer->setTo($emailconfutils::query->{'INT_to_email'});
      if ($template->{'type'} eq "merch") {
        $emailer->setFrom($emailconfutils::resellerData->getNoReplyEmail());
      } else { 
        $emailer->setFrom($emailconfutils::query->{'INT_from_email'});
      }
      if ($emailconfutils::query->{'INT_cc_email'} ne "") {
        $emailer->setCC($emailconfutils::query->{'INT_cc_email'});
      }

      $emailer->setSubject($emailconfutils::query->{'INT_email_subject'});

      my $message .= '';

      #by here we are done with the mail header and are spitting the body out
      
      if ($emailconfutils::result->{'Duplicate'} eq "yes") {
        $message .= "This is a resend of your confirmation email.\n\n";
      }

      my @message_data = split(/\n/,$template->{'data'});
      my $begin_flag = "0";
      my $line = "";
      my ($email_purchase_header);
      my %email_hash = (%$emailconfutils::query,%$emailconfutils::result);
      MSGLINE: foreach $line (@message_data) {
        my $blanklineflag = 0;
        my $subbed = 0;
        $line =~ s/\r\n//g;
        if ($line !~ /\w/) {
          $blanklineflag = 1;
        }
        if ($begin_flag ne "1") {
          my $parsecount = 0;
          while ($line =~ /\[pnp\_([0-9a-zA-Z-+_]*)\]/) {
            my $query_field = $1;
            $parsecount++;
            if ($email_hash{$query_field} ne "") {
              $subbed++;
              if (($query_field eq "card-number") || ($query_field eq "card_number")) {
                my $card_number = $email_hash{'card-number'};
                $card_number =~ s/[^0-9]//g;
                $card_number = substr($email_hash{'card-number'},0,20);
                $card_number = ('X' x (length($card_number))) . substr($card_number,-4,4);
                $line =~ s/\[pnp\_([0-9a-zA-Z-+]*)\]/$card_number/;
              }
              elsif (($query_field eq "card-exp") || ($query_field eq "card_exp")) { 
                $line =~ s/\[pnp\_([0-9a-zA-Z-+]*)\]/$email_hash{$query_field}/; 
              }
              elsif ($query_field eq "filteredCC") {
                $line =~ s/\[pnp_$query_field\]/$mckutils::filteredCC/;
              }
              elsif ($query_field eq "accountnum") {
                $line =~ s/\[pnp_$query_field\]/$mckutils::filteredAN/;
              }
              elsif ($query_field eq "routingnum") {
                $line =~ s/\[pnp_$query_field\]/$mckutils::filteredRN/;
              }
              elsif ($query_field eq "auth-code") {
                $line =~ s/\[pnp_$query_field\]/substr($email_hash{'auth-code'},0,6)/e;
              }
              elsif ($query_field eq "ssnum") {
                $line =~ s/\[pnp_$query_field\]/$mckutils::filteredSSN/;
              }
              elsif ($query_field eq "discnt") {
                if ($email_hash{$query_field} eq "") {
                  next;
                }
                $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $email_hash{$query_field})/e;
              }
              elsif ($query_field eq "subtotal") {
                $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $email_hash{$query_field})/e;
              }
              elsif ($query_field eq "tax") {
                $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $email_hash{$query_field})/e;
              }
              elsif ($query_field eq "shipping") {
                $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $email_hash{$query_field})/e;
              }
              elsif ($query_field eq "handling") {
                $line =~ s/\[pnp_$query_field\]/sprintf("%.2f", $email_hash{$query_field})/e;
              }
              else {
                $line =~ s/\[pnp\_$query_field\]/$email_hash{$query_field}/;
              }
            }
            else {
              if ($line =~ /\[pnp_(order[-_])?(date)([+-][0-9]*)?\]/) {
                $subbed++;
                my $subkey = $1 . $2;
                if ($3 ne "") {
                  $subkey .= "\\$3"; 
                }
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time() + ($3*24*3600));
                $line =~ s/\[pnp_$subkey\]/sprintf("%02d\/%02d\/%04d",$mon+1,$mday,$year+1900)/e; 
              }
              elsif ($query_field eq "discnt") {
                if ($email_hash{$query_field} eq "") {
                  next MSGLINE;
                }
              }
              else {
                if (($subbed == 0) && ($emailconfutils::feature->{'suppress'} eq "yes")) {
                  my $next_position = index($line,"[pnp_",(index($line,"pnp_$query_field")));
                  if ($next_position == -1) {
                    next MSGLINE;  
                  }
                  else {
                    $line =~ s/\[pnp\_$query_field\]//;
                  }
                }  
                else {
                  $line =~ s/\[pnp\_$query_field\]//;
                }
              }
            }
            if ($parsecount >= 10) {
              next MSGLINE;
            }
          } # end while
        } # end begin_flag if
        if ($line =~ /\[email_([^\W]*)_begin\]/) {
          if (($1 eq "shipping") && ($emailconfutils::query->{'shipinfo'} ne "0")) {
            next MSGLINE;
          }
          else {
            $begin_flag = "1";
            next MSGLINE;
          }
        }
        if ($line =~ /\[email_([^\W]*)_end\]/) {
          $begin_flag = "0";
          next MSGLINE;
        }
        if (($line =~ /\[email_purchase_header\]/) && ($emailconfutils::query->{'easycart'} eq "1")) {
          $email_purchase_header = 'omit';
          next MSGLINE;
        }

        my $currencyObj = new PlugNPay::Currency($emailconfutils::query->{'currency'});
        if (($line =~ /\[email_purchase_table\]/) && ($emailconfutils::query->{'easycart'} eq "1")) {
          if ($template->{'emailtype'} eq "html") {
            $message .= "<table>\n";
            if ($email_purchase_header ne 'omit') {
              $message .= "<TR align=left><TH>MODEL NO.</TH>      <TH>QTY</TH>   <TH> CHARGE</TH>   <TH>DESCRIPTION</TH></TR>\n";
            }
            $line = "";
            for(my $i=1; $i<=$emailconfutils::max; $i++) {
              if ($emailconfutils::query->{"quantity$i"} > 0) {
                $message .= "<TR align=left><TD>" . $emailconfutils::query->{"item$i"} . "</TD>      <TD>" . $emailconfutils::query->{"quantity$i"} . "</TD>     <TD>" . sprintf("%.2f",($emailconfutils::query->{"cost$i"} * $emailconfutils::query->{"quantity$i"})) . "</TD>      <TD>" . $emailconfutils::query->{"description$i"} . "</TD></TR>\n";
              } # end quantity if
            }
            $message .= "</table>\n";
          } # end html if 
          else {
            my $decimalflg;
            for(my $i=1; $i<=$emailconfutils::max; $i++) {
              # if quantity contains a decimal value change the format a bit
              if ($emailconfutils::query->{"quantity$i"} =~ /\./) {
                $decimalflg = 1;
              }
              $emailconfutils::query->{"cost$i"} = $currencyObj->format($emailconfutils::query->{"cost$i"});
            }

            my @purchase_table_header;
            if ($email_purchase_header ne 'omit') {
              @purchase_table_header = ('MODEL NO.', 'QTY', 'CHARGE', 'DESCRIPTION');
            }
            my $purchase_table = Text::Table->new(@purchase_table_header);

            $line = "";
            for(my $i=1; $i<=$emailconfutils::max; $i++) {
              if ($emailconfutils::query->{"quantity$i"} > 0) {
                if ($decimalflg == 1) {
                  my $qty = sprintf("%.2f", $emailconfutils::query->{"quantity$i"});
                  $purchase_table->add($emailconfutils::query->{"item$i"}, $qty, $emailconfutils::query->{"cost$i"}, $emailconfutils::query->{"description$i"});
                }
                else {
                  $purchase_table->add($emailconfutils::query->{"item$i"}, $emailconfutils::query->{"quantity$i"}, $emailconfutils::query->{"cost$i"}, $emailconfutils::query->{"description$i"});
                }
              } # end quantity if
            } # end for max loop
            $message .= $purchase_table;
          } # end text else
        } # end email_purchase_table if
        elsif ($line =~ /\[email_purchase_table\]/) {
          $line = "";
        }

        if (($template->{'type'} eq "merch") && ($line =~ /\[email_merchant_variables\]/)) {
          if($emailconfutils::query->{'comments'} ne "") {
            $emailconfutils::query->{'comments'} =~ s/\&quot\;/\"/g;
            if ($emailconfutils::query->{'comm-title'} ne "") {
              $message .= $emailconfutils::query->{'comm-title'} . "\n";
            } else {
              $message .= "Comments \&/or Special Instructions:\n";
            }
            $message .= $emailconfutils::query->{'comments'} . "\n\n";
          }

          my $cf = new PlugNPay::Util::CardFilter($email_hash{'card-number'});

          my ($merchant_variables);
          if ($emailconfutils::query->{'showextrafields'} ne "no") {
            foreach my $key (sort keys %{$emailconfutils::query}) {
              my ($field_name, $field_value) = $cf->filterPair($key, $emailconfutils::query->{$key}, 1);
              if ( ($key !~ /^(FinalStatus|success|auth-code|auth_date)$/) && ($key !~ /MErrMsg/)
                && ($key !~ /card-/) && ($key !~ /^(phone|fax|email)$/)
                && ($key !~ /^(shipinfo|shipsame|shipname|address1|address2|city|state|zip|country)$/)
                && ($key !~ /^(shipping|tax|taxrate|taxstate|subtotal)$/)
                && ($key !~ /^(currency|year-exp|month-exp|magstripe|TrakData|track|x_track|card-number|card_num|cardnumber|magensacc|emvtags)/i)
                && ($key !~ /^(accountnum|routingnum|checknum|accttype)$/)
                && ($key !~ /^(publisher-name|publisher-password|merchant|User-Agent|referrer)$/)
                && ($key !~ /^(publisher-email|cc-mail|from-email|subject|message|dontsndmail)$/) && ($emailconfutils::query->{$key} ne "subject-email")
                && ($key !~ /^(comm-title|comments|order-id)$/) && ($key !~ /^(orderid)/i)
                && ($key !~ /^(path_cgi|path-softcart|path-postorder)$/)
                && ($key !~ /^(pnppassword|pnpusername)$/) && ($key !~ /^cookie_pw\d/)
                && ($key !~ /item|quantity|cost|description/)
                && ($key !~ /^(easycart|max|pass|image-link|image-placement)$/)
                && ($key !~ /^(required|requirecompany|nocountrylist|nofraudcheck|app-level|client|client1|acct_code4)$/)
                && ($key !~ /^(success-link|badcard-link|problem-link)$/)
                && ($key !~ /^(submit|return)$/) && ($emailconfutils::query->{$key} ne "continue")
                && ($key !~ /^(merchantdb|billcycle|passwrd1|passwrd2)$/) && ($key !~ /roption|plan/)
                && ($key !~ /^(pnp-query|storename|sname|slink|area|x|y)$/)
                && ($key !~ /^(test-wgt|total-wgt|total-cnt)$/) && ($key !~ /^INT_/)
                && ($key !~ /^x_(Bank|Password|Card|Exp|ADC|Login)$/i) && ($key !~ /^password/i)
                && ($emailconfutils::query->{$key} ne "")
               ) {
                if ($key !~ /^($emailconfutils::feature->{'omit_merchant_variables'})$/) {
                  if (($key =~ /^(ssnum|ssnum4)$/i) || ($key =~ /^($emailconfutils::feature->{'mask_merchant_variables'})$/)) {
                    # mask all but last 4 chars within field value, when necessary
                    $field_value = ('X' x (length($field_value)-4)) . substr($field_value,-4,4)
                  }
                  # display merchant variable, unless told to omit
                  $merchant_variables .= "Merchant Variable: $field_name: $field_value\n";
                }
              }
            }
          }
          else {
            foreach my $key (@{$emailconfutils::emailextrafields}) {
              if ($key !~ /^($emailconfutils::feature->{'omit_merchant_variables'})$/) {
                my ($field_name, $field_value) = $cf->filterPair($key, $emailconfutils::query->{$key}, 1);
                if (($key =~ /^(ssnum|ssnum4)$/i) || ($key =~ /^($emailconfutils::feature->{'mask_merchant_variables'})$/)) {
                  # mask all but last 4 chars within field value, when necessary
                  $field_value = ('X' x (length($field_value)-4)) . substr($field_value,-4,4)
                }
                # display merchant variable, unless told to omit
                $merchant_variables .= "Merchant Variable: $field_name: $field_value\n";
              }
            }
          }

          if ($emailconfutils::result->{'FinalStatus'} eq "success") {
            if ($emailconfutils::query->{'paymethod'} eq "check") {
            }
            elsif ($emailconfutils::query->{'paymethod'} eq "onlinecheck") {
              $message .= "Payment Method: Online Check\n";
            }
            else {
              if ($emailconfutils::result->{'trans_type'} ne "storedata") {
                if ($emailconfutils::query->{'paymethod'} eq "onlinecheck") {
                  $message .= "Electronic Debit was successful\n";
                }
                else {
                  $message .= "Credit Card Authorization was successful\n";
                  $message .= "Authorization Code: " .  substr($emailconfutils::result->{'auth-code'},0,6) . "\n";
                  if (($emailconfutils::result->{'cvvresp'} ne "") && ($emailconfutils::query->{'card-cvv'} ne "")) {
                    $message .= "CVV2/CVC2 - Response Code: $constants::cvv_hash{$emailconfutils::result->{'cvvresp'}}\n";
                  }
                  my $avs = substr($emailconfutils::result->{'avs-code'},0,3);
                  $avs = substr($avs,-1,1);
                  $message .= "AVS - Response Code:$avs\n";
                  $message .= ${$constants::avs_responses{$avs}}[1] . "\n";
                  $message .= "Card Type: $emailconfutils::query->{'card-type'}\n";
                }
              }
            }

            if ($emailconfutils::result->{'pnp_debug'} eq "yes"){
              $message .= "WARNING: THIS TRANSACTION HAS BEEN FORCED SUCCESSFUL FOR\n";
              $message .= "DEBUGGING AND TESTING PURPOSES ONLY.  IF THIS IS NOT YOUR INTENT PLEASE CONTACT\n";
              $message .= "THE TECHNICAL SUPPORT STAFF IMMEDIATELY.\n";
            }

            if ($merchant_variables ne "") {
              $message .= $merchant_variables;
            }
          }
          if ($emailconfutils::result->{'FinalStatus'} eq "badcard") {
            if ($emailconfutils::query->{'paymethod'} eq "onlinecheck") {
              $message .= "Electronic Debit failed: $emailconfutils::result->{'MErrMsg'}\n";
            }
            else {
              $message .= "Credit Card Authorization failed: Bad Card: $emailconfutils::result->{'MErrMsg'}\n";
            }

            if (($emailconfutils::feature->{'showmerchantvars'} == 1) && ($merchant_variables ne "")) {
              $message .= $merchant_variables;
            }
          }
          elsif ($emailconfutils::result->{'FinalStatus'} !~ /^(success|pending)$/) {
            if ($emailconfutils::result->{'MErrMsg'} =~ /Payment Server Host failed to respond/i) {
              $emailconfutils::result->{'MErrMsg'} = "The processor for this merchant is currently experiencing temporary delays.  Please try again in a few minutes.";
            }

            if ($emailconfutils::query->{'paymethod'} eq "onlinecheck") {
              $message .= "Electronic Debit failed: $emailconfutils::result->{'MErrMsg'}\n";
            }
            else {
              $message .= "Credit Card Authorization failed: $emailconfutils::result->{'MErrMsg'}\n";
            }

            if (($emailconfutils::feature->{'showmerchantvars'} == 1) && ($merchant_variables ne "")) {
              $message .= $merchant_variables;
            }
          }
          $line = "";
        }
        if (($line =~ /\[products\]/) && ($emailconfutils::query->{'easycart'} eq "1")) {
          $line = "";
          $parseflag = 1;
          next MSGLINE;
        } # end email_purchase_table if
        # [products] tag is used for fulfillment
        elsif ($line =~ /\[\/products\]/) {
          $line = "";
          $parseflag = 0;
          for(my $i=1; $i<=$emailconfutils::max; $i++) {
            foreach my $product_line (@productarray) {
              my $temp_pl = $product_line;
              my $parsecnt = 0; 
              while ($temp_pl =~ /\[prod\_([0-9a-zA-Z-+]*)\]/) {
                my $query_field = $1;
                $parsecnt++;
                if ($emailconfutils::query->{"$query_field$i"} ne "") {
                  $temp_pl =~ s/\[prod\_[0-9a-zA-Z-+]*\]/$emailconfutils::query->{"$query_field$i"}/;
                }
                if ($parsecnt >= 20) {
                  next MSGLINE;
                }
              }
              $message .= "$temp_pl\n";
            } # end quantity if
          } # end for max loop
        }
        elsif ($parseflag == 1) {
          $productarray[++$#productarray] = "$line";
          next MSGLINE;
        }

        if (($line =~ /\[emailloop_([0-9a-zA-Z-+_]*)\]/)) {
          $line = "";
          $parseflag = 2;
          $pnploopcnt = $mckutils::query{$1};
          next MSGLINE;
        } # end email_purchase_table if
        # [products] tag is used for fulfillment
        elsif ($line =~ /\[\/emailloop\]/) {
          $line = "";
          $parseflag = 0;
          for(my $i=1; $i<=$pnploopcnt; $i++) {
            foreach my $loop_line (@looparray) {
              my $product_line = $loop_line;
              my $parsecount = 0;
              while ($product_line =~ /\[loopline_([0-9a-zA-Z-+_]*)\]/) {
                my $query_field = $1;
                $parsecount += 1;
                if ($mckutils::query{"$query_field$i"} ne "") {
                  $product_line =~ s/\[loopline_$query_field\]/$mckutils::query{"$query_field$i"}/;
                }
                if ($parsecount >= 20) {
                  next MSGLINE;
                }
              }
              $message .= $product_line;
            } # end quantity if
          } # end for max loop
        }
        elsif ($parseflag == 2) {
          $looparray[++$#looparray] = "$line";
          next MSGLINE;
        }

        #if (($emailconfutils::feature->{'suppress'} eq "yes") && ($blanklineflag == 0) && ($line !~ /\w/)) {
        #  next MSGLINE;
        #}
        if ($begin_flag eq "0") {
          $message .= $line . "\n";
        }
      } # end MSGLINE while

      if ($emailconfutils::query->{'INT_TRACKID'} ne "") {
        $message .= $emailconfutils::query->{'INT_TRACKID'};
      }

      $emailer->setContent($message);

      my $status = "pending";

      if (! &isemailvalid($emailconfutils::query->{'INT_to_email'})) {
        $status = "problem";
      }
      else {   #####  DCP 20100712

        if ($emailconfutils::accountFeatures->get('enhancedLogging') == 1) {
          new PlugNPay::Logging::Performance('preEmailSend');
        }

        $emailer->send();

        if ($emailconfutils::accountFeatures->get('enhancedLogging') == 1) {
          new PlugNPay::Logging::Performance('postEmailSend');
        }

      }
    } # end position email if
  }
}

# anything that should be costomized for a reseller/merchant/template type should
# go in here.
sub send_email {
  my $this = shift;
  my ($template_type) = @_;
  my $template;

  if ($emailconfutils::accountFeatures->get('enhancedLogging') == 1) {
    new PlugNPay::Logging::Performance('preSend_Email');
  }

  if ($emailconfutils::query->{'sndemail'} =~ /(both|customer|merchant)/) {
    $emailconfutils::feature->{'sndemail'} = $emailconfutils::query->{'sndemail'};
  }

  if ($emailconfutils::feature->{'sndemail'} ne "none") {
    if (($emailconfutils::feature->{'sndemail'} eq "merchant") && ($emailconfutils::result->{'Duplicate'} ne "yes") && ($emailconfutils::query->{'publisher-email'} ne "") && ($template_type eq "merch")) {

      $template = $this->pick_template("merch");
    }
    if (($emailconfutils::feature->{'sndemail'} eq "customer") && ($template_type eq "conf")) {
      $template = $this->pick_template("conf");
    }
    if (($emailconfutils::feature->{'sndemail'} eq "both") || ($emailconfutils::feature->{'sndemail'} eq "")) {
      if (($emailconfutils::result->{'Duplicate'} ne "yes") && ($template_type eq "merch")) {
        $template = $this->pick_template("merch");
      }
      if (($emailconfutils::query->{'dontsndmail'} ne "yes") && ($template_type eq "conf")) {
        $template = $this->pick_template("conf");
      }
    }
  } # end sndemail if

  # make sure we're sending this email to someone
  if ($emailconfutils::query->{'INT_to_email'} eq "") {
    if ($template->{'type'} eq "merch") {
      $emailconfutils::query->{'INT_to_email'} = $emailconfutils::query->{'publisher-email'};
    }
    else {
      $emailconfutils::query->{'INT_to_email'} = $emailconfutils::query->{'email'};
    }
  } # end INT_to_email if

  # make sure we know where the email is coming from 
  if ($template ne "") {
    if ($emailconfutils::query->{'INT_from_email'} eq "") {
      if ($template->{'type'} eq "conf") {
        if ($emailconfutils::query->{'from-email'} ne "") {
          $emailconfutils::query->{'INT_from_email'} = $emailconfutils::query->{'from-email'};
        }
        else {
          $emailconfutils::query->{'INT_from_email'} = $emailconfutils::query->{'publisher-email'};
        }
      }
      else {
        if (($emailconfutils::query->{'email'} =~ /\@.+\..{2,}$/) && ($emailconfutils::feature->{'staticemailflg'} != 1)) {  ### DCP
          $emailconfutils::query->{'INT_from_email'} = $emailconfutils::query->{'email'};
        }
        else {
          if ($emailconfutils::reseller eq "electro") {
            $emailconfutils::query->{'INT_from_email'} = "paymentserver\@eci-pay.com";
          }
          elsif ($emailconfutils::reseller eq "paymentd") {
            $emailconfutils::query->{'INT_from_email'} = "support\@paymentdata.com";
          }
          else {
            if ($emailconfutils::resellerData->getNoReplyEmail() ne '') {
              $emailconfutils::query->{'INT_from_email'} = $emailconfutils::resellerData->getNoReplyEmail();
            }
            elsif ($emailconfutils::resellerData->getSupportEmail() ne '') {
              $emailconfutils::query->{'INT_from_email'} = $emailconfutils::resellerData->getSupportEmail();
            }
            else {
              $emailconfutils::query->{'INT_from_email'} = "paymentserver\@plugnpay.com";
            }
          }
        }
      }
    } # end INT_from_email if
  }

  # code to create subject
  my $dup = "";
  if ($emailconfutils::query->{'Duplicate'} eq "yes") {
    $dup = " - Resend";
  }

  if ($emailconfutils::query->{'INT_email_subject'} eq "") {
    my ($what,$type,$name,$subject) = split(/\:/,$template->{'include'},4);
    chomp $subject;

    if ($subject ne "") {
      $emailconfutils::query->{'INT_email_subject'} = "$subject $dup";
    }
    elsif (($emailconfutils::query->{'subject-email'} ne "") && ($template->{'type'} eq "conf")) {
      $emailconfutils::query->{'INT_email_subject'} = "$emailconfutils::query->{'subject-email'}$dup";
    }
    elsif (($emailconfutils::query->{'subject'} ne "") && ($template->{'type'} eq "merch")) {
      $emailconfutils::query->{'INT_email_subject'} = "$emailconfutils::query->{'subject'} $emailconfutils::query->{'card-name'} $emailconfutils::result->{'FinalStatus'}";
    }
    else {
      if ($template->{'type'} eq "conf") {
        $emailconfutils::query->{'INT_email_subject'} = "Purchase Confirmation$dup";
      }
      elsif ($template->{'type'} eq "merch") {
        my $esub = $emailconfutils::resellerData->getSubjectPrefixEmail();
        if ($esub eq "") {
          $esub = $emailconfutils::esub;
        }
        $emailconfutils::query->{'INT_email_subject'} = "$esub - $emailconfutils::query->{'card-name'} $emailconfutils::result->{'FinalStatus'} notification";
      }
      else {
        # this catches all other template types which require that a
        # subject be added to query
        $emailconfutils::query->{'INT_email_subject'} = "$emailconfutils::query->{'subject'}";
      }
    }
  }

  # added 12/22/2006 by drew to allow [pnp_*] in the subject
  my %email_hash = (%$emailconfutils::query,%$emailconfutils::result);
  if ($emailconfutils::query->{'INT_email_subject'} =~ /\[pnp_/) {
    # loop thru query items
    foreach my $item (keys %email_hash) {
      # check to see if the query item fits
      if ($emailconfutils::query->{'INT_email_subject'} =~ /\[pnp_$item\]/) {
        my $value = $email_hash{$item};
        # don't allow any sensitive data in the subject
        if (($item eq "card-number") || ($item eq "card_number") || ($item eq "accountnum") || ($item eq "routingnum")) {

          $value = "";
        }
        # filter out :
        $value =~ s/\://;
        # do the substitute in the line
        $emailconfutils::query->{'INT_email_subject'} =~ s/\[pnp_$item\]/$value/;
      }
    }
  }

  if (($emailconfutils::query->{'cc-email'} ne "") && ($emailconfutils::query->{'cc-mail'} eq "")) {
    $emailconfutils::query->{'cc-mail'} = $emailconfutils::query->{'cc-email'};
  }

  if ($emailconfutils::query->{'INT_cc_email'} eq "") {
   if (($emailconfutils::query->{'cc-mail'} ne "") && ($template->{'type'} eq "merch")) {
      $emailconfutils::query->{'INT_cc_email'} = "$emailconfutils::query->{'cc-mail'}";
    }
  }

  if (($emailconfutils::query->{'INT_bcc_email'} eq "") && ($template->{'type'} eq "merch")) {
    $emailconfutils::query->{'INT_bcc_email'} = "custmail\@plugnpay.com";
    $emailconfutils::query->{'INT_bcc_email'} = "";
 
    if ($emailconfutils::query->{'ff-email'} ne "") {
      if ($emailconfutils::query->{'INT_bcc_email'} ne "") {
        $emailconfutils::query->{'INT_bcc_email'} .= ", $emailconfutils::query->{'ff-email'}";
      }
      else {
        $emailconfutils::query->{'INT_bcc_email'} = "$emailconfutils::query->{'ff-email'}";
      }
    }
  }

  if (($emailconfutils::fraud_config->{'bounced'} >= 1) && ($template->{'type'} eq "conf")) {
    $emailconfutils::query->{'INT_TRACKID'} = "\n\n\nTRACKID:$emailconfutils::query->{'orderID'}:$emailconfutils::query->{'auth_date'}:$emailconfutils::query->{'plan'}";
  }

  # use to be in pick_template.  If no from or publisher set we don't send any  
  # emails out.  
  #if (($emailconfutils::query->{'INT_from_email'} eq "") || ($template eq "")) {
  if (($emailconfutils::query->{'INT_from_email'} !~ /\@.+\..{2,}$/) || ($template eq "")) {
    delete $emailconfutils::query->{'INT_from_email'};
    delete $emailconfutils::query->{'INT_to_email'};
    delete $emailconfutils::query->{'INT_cc_email'};
    delete $emailconfutils::query->{'INT_bcc_email'};
    delete $emailconfutils::query->{'INT_email_subject'};
    return;
  }
  else {
    $this->generate_email($template);
  }

  delete $emailconfutils::query->{'INT_from_email'};
  delete $emailconfutils::query->{'INT_to_email'};
  delete $emailconfutils::query->{'INT_cc_email'};
  delete $emailconfutils::query->{'INT_bcc_email'};
  delete $emailconfutils::query->{'INT_email_subject'};
}

sub isemailvalid {
  my ($test_email) = @_;

  my $at_position = index($test_email,"\@");
  my $dot_position = rindex($test_email,"\.");
  my $elength  = length($test_email);

  if (($at_position < 1)
      || ($dot_position < $at_position)
      || ($dot_position >= $elength - 2)
      || ($elength < 5)
      || ($at_position > $elength - 5)
  ) {
    return 0;
  }

  return 1;
} 


1;
