package PlugNPay::Client::Masterpass;

use strict;
use JSON::XS;
use PlugNPay::Processor::ID;
use PlugNPay::Util::UniqueID;
use PlugNPay::Logging::Alert;
use PlugNPay::Processor::SocketConnector;
use PlugNPay::Environment;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;

  my $options = shift || {};

  my $env = new PlugNPay::Environment();
  my $serverName = $options->{'serverName'} || $env->get('PNP_SERVER_NAME');
  $self->{'callbackServer'} = $serverName;

  return $self;
}

#call to masterpass API via masterpass procesor to otain a requesttoken.
#The request token is needed in call to masterpass.client.checkout() which brings up the lightbox
sub getRequestTokenFromProcessor {
  my $self = shift;
  my %transactionData = ();
  $transactionData{'actionType'}='request_token';
   
  #calling java processor  
  my $requestToken = $self->runRequest(\%transactionData);
 
  #return $requestToken;
  if (ref($requestToken) eq 'HASH') {
    return $requestToken->{'msg'};
  } else {
    return undef;
  }
}

#constructs and returns an url for pay
sub getActionURL {
  my $self = shift;
  return "https://" . $self->{'callbackServer'} . "/pay/";
}


#constructs and returns call back url 
sub getCallbackURL {
  my $self = shift;
  return "https://" . $self->{'callbackServer'} . "/payment/masterpassresponse.cgi";
}

#constructs and returns call back url 
sub getTokenCGIURL {
  my $self = shift;
  return "https://" . $self->{'callbackServer'} . "/payment/masterpasstoken.cgi";
}

#call to Masterpass API to communicate the result of the transaction to Masterpassi, via Masterpass processor
sub masterpassLog {
  my $self = shift;
  my $approvalCode = shift;

  my %transactionData = ();
  $transactionData{'actionType'}='log_transaction';
  $transactionData{'card-amount'}=$mckutils::query{'card-amount'};
  $transactionData{'auth-date'}=$mckutils::query{'auth_date'};
  $transactionData{'pt-masterpass-consumer-key'}=$mckutils::query{'pt-masterpass-consumer-key'};  
  $transactionData{'pt-masterpass-trans-id'}=$mckutils::query{'pt-masterpass-trans-id'};  
  $transactionData{'pt-masterpass-approval-code'}=$approvalCode; 
  $transactionData{'auth_date_time'}=POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime(time()));;
	 
  #calling java processor  
  my $resultJson = $self->runRequest(\%transactionData);
  if (ref($resultJson) eq 'HASH') {
    return $resultJson->{'msg'};
  } else {
    return undef;
  }
}


#puts data in JSON with specified section for sending to processor
sub createJSONRequest {
  my $self = shift;
	
  my %transactionData = %{shift()};
  my $requestID = new PlugNPay::Util::UniqueID()->inHex();
  my $transactionID = new PlugNPay::Util::UniqueID()->inHex();
  my $requestHashID = new PlugNPay::Util::UniqueID()->inHex();
  my $messageID = new PlugNPay::Util::UniqueID()->inHex();
	
  
  #update transactionData 
  $transactionData{'pnp_transaction_id'} = $transactionID;
  $transactionData{'requestType'} = 'request';
  $transactionData{'notes'} = '';
  

  #putting sensitiveData together
  my %sensitiveTransactionData = ();
  
  #putting additionalMerchantData together
  my %additionalMerchantData = ();
	
  #  sample: <originUrl>https://backenddev-anhtram.plugnpay.com/pay/</originUrl>
  #  sample: <oauth_callback>https://backenddev-anhtram.plugnpay.com/payment/masterpassresponse.cgi</oauth_callback>
  $additionalMerchantData{'originUrl'} = "https://" . $self->{'callbackServer'} . "/pay";
  $additionalMerchantData{'oauth_callback'} = $self->getCallbackURL();
  
  my %requestHashValues = ();
  $requestHashValues{'priority'}=5;
  $requestHashValues{'processor'}='masterpass';
  $requestHashValues{'type'}='request';
  $requestHashValues{'transactionData'}={%transactionData};
  $requestHashValues{'sensitiveTransactionData'}={%sensitiveTransactionData};
  $requestHashValues{'additionalMerchantData'}={%additionalMerchantData};
  $requestHashValues{'requestID'} = $requestID;
  
  my %requestHash = (); 
  $requestHash{$requestHashID} = {%requestHashValues};
  
  #put all data together in JSON with sections
  my %queryForProcessor= ();
  $queryForProcessor{'messageID'} = $messageID;
  #request
  $queryForProcessor{'requests'} = {%requestHash};
  
  return %queryForProcessor;
};

#calls processor with JSON request; returns responses from processor
sub runRequest {
  my $self = shift;
  my $transactionData = shift;

  my %queryForProcesor = $self->createJSONRequest($transactionData);
  
  my $util = new PlugNPay::Processor::ID();
  my $processor_id = $util->getProcessorID("masterpass");
  
  my $json = JSON::XS->new->utf8->encode(\%queryForProcesor);
  my $connector = new PlugNPay::Processor::SocketConnector();
	
  my $response;
  $SIG{ALARM} = sub { die 'Socket connection timeout'; };
  eval{
    alarm 10;
    $response = $connector->connectToProcessor($json,$processor_id);
    alarm 0;
  };
	
  if ($@) {
    $response = undef;
    my $alert = new PlugNPay::Logging::Alert();
    $alert->alert(4,'Masterpass socket connection failed, Masterpass is unreachable');
  }
  
  my $responseStr = {};
  if ($response && length($response) > 0) {
    my $jsonResponse = JSON::XS->new->utf8->decode($response);
    if ($jsonResponse->{'rc'} eq "-1") { #error
      eval { # log to error log if we can
         Apache2::ServerRec::warn('Masterpass::runRequest - ' . $jsonResponse->{'msg'}. '\n');
      };
    }
    $responseStr = $jsonResponse; 
  }
  
  return $responseStr;
}


# DB Functions

sub loadMasterpassKeys {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');

  my $sth = $dbs->prepare(q/
                            SELECT username,
                                   checkout_id 
                            FROM masterpass_key
                           /);
  $sth->execute();

  my $rows = $sth->fetchall_arrayref({});
  my $keys = {};
  foreach my $row (@{$rows}) {
    $keys->{$row->{'username'}} = $row->{'checkout_id'};
  }

  $self->{'checkout_id_map'} = $keys;
  
  return $keys;
}

sub getCheckoutIDFromUsername {
  my $self = shift; 
  my $username = shift;

  if (!defined $self->{'checkout_id_map'} || !defined $self->{'checkout_id_map'}{$username}) {
    $self->loadMasterpassKeys();
  }

  return $self->{'checkout_id_map'}{$username};
}



#saves encrypted credit card number and $session_id to db
sub saveMasterpassCheckoutInfo {
  my $self = shift;
  my $encrypted_cardnumber = shift;
  my $session_id = shift;
  
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  
  my $sth = $dbs->prepare(q/ INSERT INTO masterpass_creditcard (session_id, cardnumber)
                             VALUES (?,?)
                          /);

  $sth->execute($session_id, $encrypted_cardnumber);
  $sth->finish;

}


#retrieves encrypted credit card number from db and returns decrypted card number.
sub retrieveMasterpassCreditCardNumber {
  my $self = shift;
  my $session_id = shift;
  
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');

  my $sth = $dbs->prepare(q/ SELECT cardnumber 
                             FROM masterpass_creditcard
                             WHERE session_id=?
                         /);
  
  $sth->execute($session_id);

  my $rows = $sth->fetchall_arrayref({});
  
  $sth->finish;
  
  #retrieve encrytped card number from db
  my $encryptedCardNo = @{$rows}[0]->{'cardnumber'};
  
  my $card = new PlugNPay::CreditCard();
  
  #obtain decrypted card number
  my $decryptedCardNumber = $card->fromToken($encryptedCardNo);
  
  return $decryptedCardNumber;
}

1;
