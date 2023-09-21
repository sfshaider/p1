package PlugNPay::Client::AmexExpress;

use strict;
use PlugNPay::Processor::ID;
use PlugNPay::Processor::SocketConnector;
use JSON::XS;
use PlugNPay::Util::UniqueID;
use PlugNPay::Environment;

my $processor_name ='amexexpress';

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

#call to amexexpress checkout API via amexexpress procesor to decrypt data.
sub getDecryptedData() {
   my $self = shift;
   my $enc_data = shift;
    
   my %transactionData = ();
   $transactionData{'actionType'}='decrypt';
   $transactionData{'enc_data'}=$enc_data;
   
   #calling java processor  
   my $decryptedData = $self->runRequest(\%transactionData);
 
   return $decryptedData;
}

#generates and returns a unique id in format xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx
sub generate_hyphenated_requestID {
     my $pnp_requestID = new PlugNPay::Util::UniqueID()->inHex();
     
     my $str1 = substr $pnp_requestID, 0, 8;
     my $str2 = substr $pnp_requestID, 8, 4;
     my $str3 = substr $pnp_requestID, 12, 4;
     my $str4 = substr $pnp_requestID, 16, 12;
     my $requestID = $str1 . '-' . $str2 . '-' . $str3 . '-' . $str4;
     
     return $requestID;
}

sub setAmexRequestID {
  my $self = shift;
  my $requestID = shift;
  $self->{'amexRequestID'} = $requestID;
}

#contructs and returns a hyphenated unique id; also sets the hyphenated id to "amexRequestID"
sub getAmexRequestID {
  my $self = shift;
  if (!defined  $self->{'amexRequestID'}) {
     $self->setAmexRequestID($self->generate_hyphenated_requestID());
  }
  return $self->{'amexRequestID'}; 
}

#constructs and returns call back url 
sub getCallbackURL() {
  my $self = shift;
  return "https://" . $self->{'callbackServer'} . "/payment/amexexpressresponse.cgi";
}

#constructs and returns call back url 
sub getCookieCallbackURL() {
  my $self = shift;
  return "https://" . $self->{'callbackServer'} . "/payment/amexexpresscookie.cgi";
}

#puts data in JSON with specified section for sending to processor
sub createJSONRequest() {
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
	
  my %requestHashValues = ();
  $requestHashValues{'priority'}=5;
  $requestHashValues{'processor'}=$processor_name;
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
  my $processor_id = $util->getProcessorID($processor_name);
  
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
    $alert->alert(4,'AmexExpress socket connection failed, AmexExpress is unreachable');
  }
  
  my $responseStr = {};
  if ($response && length($response) != 0) {
    my $jsonResponse= JSON::XS->new->utf8->decode($response);
    if ($jsonResponse->{'rc'} eq "-1") { #error
      eval { # log to error log if we can
         Apache2::ServerRec::warn('Amexexpress::runRequest - ' . $jsonResponse->{'msg'}. '\n');
      };
    }
    
    $responseStr = $jsonResponse;
  }
  
  return $responseStr;
}


# DB Functions

sub loadAmexExpressKeys {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');

  my $sth = $dbs->prepare(q/
                            SELECT username,
                                   client_id 
                            FROM amex_express_key
                           /);
  $sth->execute();

  my $rows = $sth->fetchall_arrayref({});
  my $keys = {};
  foreach my $row (@{$rows}) {
    $keys->{$row->{'username'}} = $row->{'client_id'};
  }

  $self->{'client_id_map'} = $keys;
  
  return $keys;
}

sub getAmexClientIDFromUsername {
  my $self = shift; 
  my $username = shift;

  if (!defined $self->{'client_id_map'} || !defined $self->{'client_id_map'}{$username}) {
    $self->loadAmexExpressKeys();
  }

  return $self->{'client_id_map'}{$username};
}

#saves credit card number and $session_id to db
sub saveAmexExpressCreditCardNumber {
  my $self = shift;
  my $encrypted_card_number = shift;
  my $session_id = shift;

  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  
  my $sth = $dbs->prepare(q/ INSERT INTO amexexpress_creditcard (session_id, cardnumber)
                             VALUES (?,?)
                          /);

  $sth->execute($session_id, $encrypted_card_number);
  $sth->finish;

}


#retrieves credit card number 
sub retrieveAmexExpressCreditCardNumber {
  my $self = shift;
  my $session_id = shift;
  
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');

  my $sth = $dbs->prepare(q/ SELECT cardnumber 
                             FROM amexexpress_creditcard
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
