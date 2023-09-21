package PlugNPay::Partners::AuthVia::Conversation;

use strict;
use base "PlugNPay::Partners::AuthVia::Authorization";
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::Util::UniqueID;
use PlugNPay::Die qw(fail);
use JSON::XS;
use Types::Serialiser;
=pod
 Why Conversations?

 Conversations are a great way to hand off complex use cases to AuthVia to solve with a customer. 
 Our platform enables a cross channel intelligent engagement with a customer. 
 Conversations satisfy not just a direct use case, but the accessory use cases around it.
 To say it more directly, when you create a payment topic with a customer, they can pay, with multiple payment methods,
 but also request more information, request assistance or update information in the context of that payment task.
 You tell us the complexity involved, we can build an intelligent workflow around it.

 Conversations are created within the tenancy of a merchant and assigned to a customer.
 Any resulting transactions and messages relating to that conversation are also associated to it.

 Breakdown: Conversations handle the entire process, nothing to be done by PNP. Conversations will create a customer, create payment methods, create transaction, etc.
=cut

our $_tokenData;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->{'scope_list'} = ['conversations:create', 'conversations:update', 'conversations:read', 'merchants:read'];

  return $self;
}

=pod 
  Creates new conversation
  
  INPUT:  {
    'phoneNumber' == customer mobile phone number
    'emailAddress' (optional) == customer email address
    'name' (optional) == customer name
    'customerID' (optional) == pnp customer identifier
    'contextData' == data for conversation, i.e. payments need subhash {'amount' => '1.00', 'description' => 'water bill'}
    'topic' == what is the conversation about, i.e. payment
    'deadline' (optional) ==  how long until conversation automoves to failed state   
  }

  OUTPUT: {
    authviaID == id of the conversation from authvia
    status == status of transaction (in-progress, resolved, failed)
    customerData == a hash of data to identify customer
  }

  RAW REQUEST:
  curl -H 'Authorization: Bearer YOUR_TOKEN' -H "Content-type: application/json" -d '{
    "topic": "payment",
    "with": {
        "ref": "YOUR_ID_FOR_CUSTOMER"
    },
    "context": {
    	"amount" : "100.00",
      "description" : "Water Bill",
    }
  }' 'https://api.authvia.com/v3/conversations'

  RAW RESPONSE: 
  {
    "id": "4ce36cdb-ba62-41bf-8c4a-4d4e4ebf1aa5",
    "topic": "payment",
    "status": "in-progress",
    "with": {
        "ref": "YOUR_ID_FOR_CUSTOMER",
        "name": "John Charger",
        "addresses": [
          {
            "type": "mobilePhone",
            "value": "+1xxxxxxxxxx"
          }
        ]
    },
    "context": {
        "amount": "100.00",
      	"description": "Water Bill"
    }
  }
=cut
sub create {
  my $self = shift;
  my $data = shift;
  my $merchant = $self->getGatewayAccount();

  if (!defined $merchant) {
    fail('No merchant set when creating AuthVia conversation!');
  }

  my $validated = _validatePhoneNumber($data->{'phoneNumber'});
  my $customerInfo = {'addresses' => [{
    'type' => 'mobilePhone',
    'value' => $validated
  }]};

  if ($data->{'emailAddress'}) {
    # Must LC email addresses because uppercased emails cause AV to blow up?
    push @{$customerInfo->{'addresses'}}, {'type' => 'email', 'value' => lc($data->{'emailAddress'})};
  }

  my $newCustID = $self->generateCustomerID();
  $customerInfo->{'ref'} = $data->{'customerID'} ? $data->{'customerID'} : $newCustID;
  $customerInfo->{'name'} = $data->{'name'} if $data->{'name'};

  my $requestData = {
    'topic'    => $data->{'conversationTopic'} || 'payment',
    'with'     => $customerInfo,
    'context'  => $data->{'contextData'},
    'realtime' => Types::Serialiser::true
  };

  if ($data->{'deadline'}) {
    $requestData->{'expiration'} = $data->{'deadline'};
  }

  my $now = new PlugNPay::Sys::Time()->nowInFormat('unix'); 
  my $tokenData = $_tokenData->{$self->getGatewayAccount()};
  my $shouldGetNewToken = 0;
  if (ref($tokenData) ne 'HASH') {
    $shouldGetNewToken = 1;
  } elsif ($tokenData->{'token'} == '' || !defined $tokenData->{'token'}) {
    $shouldGetNewToken = 1;
  } elsif ($tokenData->{'expirationTime'} <= $now) {
    $shouldGetNewToken = 1;
  }

  if ($shouldGetNewToken) {
    $tokenData = $self->getAuthorizationToken($self->getGatewayAccount());
    $_tokenData->{$self->getGatewayAccount()} = $tokenData;
  }
  my $response = $self->_doRequest('POST', {
    'endpoint' => 'conversations',
    'headers'  => {'Authorization' => 'Bearer ' . $tokenData->{'token'}}, 
    'requestData' => $requestData});
  if (!defined $response->{'id'} || $response->{'id'} eq '') {
    $self->log({'error' => 'Failed to start conversation', 'merchant' => $self->getGatewayAccount(), 'response' => $response->{'message'}});
    die 'Text2Pay did not start a valid conversation';
  }

  my $conversationID = $response->{'id'};
  $self->save($data->{'phoneNumber'}, $newCustID, $conversationID, $response);

  my $dataToReturn = {
    'authViaId'    => $response->{'id'},
    'status'       => $response->{'status'},
    'customerData' => $response->{'with'}
  };

  return $dataToReturn;
}

=pod
  Modify a conversation, with new information or to resolve it.
  Scope: conversations:update

  PATH PARAMS
  conversation-id* - The id returned, when a conversation was created.

  BODY PARAMS
  status - Optional. If provided, the only permitted value is 'resolved'.

  context - Optional. A series of key/value string pairs to feed the conversation with. 
           Some context values can be required based on the type of conversation. 
            If a key has null specified as the, it will be removed.

  curl -XPATCH -H 'Authorization: Bearer YOUR_TOKEN' -H "Content-type: application/json" -d '{
    "status": "resolved"
  }' 'https://api.authvia.com/v3/conversations/CONVERSATION_ID'
=cut
sub update {
  my $self = shift;
  my $conversationID = shift;
  my $options = shift;

  fail('No gateway account defined for AuthVia Conversation Update') if !defined $self->getGatewayAccount();

  fail('Unable to update conversation, conversation identifier not passed to update function') if !defined $conversationID;

  my $now = new PlugNPay::Sys::Time()->nowInFormat('unix');
  my $isExpired = $_tokenData->{$self->getGatewayAccount()}{'expirationTime'} <= $now;
  if (ref($_tokenData->{$self->getGatewayAccount()}) ne 'HASH' || $isExpired) {
    $_tokenData->{$self->getGatewayAccount()} = $self->getAuthorizationToken($self->getGatewayAccount());
  }

  my $token = $_tokenData->{$self->getGatewayAccount()};

  if (!defined $token->{'token'}) {
    fail('Unable to generate Authorization Token for AuthVia');
  }

  my $data = {};
  if ($options->{'context'}) {
    $data->{'context'} = $options->{'context'};
  }

  if ($options->{'status'} eq 'resolved' || $options->{'status'} eq 'success') {
    $data->{'status'} = 'resolved';
  }
  
  if (keys %{$data} > 0) {

    my $response = $self->_doRequest('PATCH', {
        'endpoint' => 'conversations/' . $conversationID,
        'requestData' => $data,
        'headers' => {'Authorization' => 'Bearer ' . $token->{'token'}}
      }
    );

    $self->updateConversation($conversationID,$response);
    return $response;
  } else {
    return {'message' => 'no data to update'}; 
  }
}

# curl -XGET -H 'Authorization: Bearer YOUR_TOKEN' -H "Content-type: application/json" 'https://api.authvia.com/v3/conversations/CONVERSATION_ID'
sub read {
  my $self = shift;
  my $conversationID = shift;

  # Now to check for some missing data...
  fail('No gateway account defined for AuthVia Conversation Read') if !defined $self->getGatewayAccount();
  fail('Unable to retrieve conversation, conversation identifier not passed to read function') if !defined $conversationID;

  my $now = new PlugNPay::Sys::Time()->nowInFormat('unix');
  if (ref($_tokenData->{$self->getGatewayAccount()}) ne 'HASH' || $_tokenData->{$self->getGatewayAccount()}{'expirationTime'} <= $now) {
    $_tokenData->{$self->getGatewayAccount()} = $self->getAuthorizationToken($self->getGatewayAccount());
  }

  my $response = $self->_doRequest('GET', {
      'endpoint'  => 'conversations/' . $conversationID,
      'headers'   => {'Authorization' => 'Bearer ' . $_tokenData->{$self->getGatewayAccount()}{'token'}}
    }
  );

  $self->updateConversation($conversationID, $response);

  return $response;
}

=pod
 Adds message to existing conversation
 Example message addition:
 {\
    \"template\": \"TEMPLATE_NAME\",\
    \"context\": {\
   	\"amount\" : \"100.00\"\,
      \"description\" : \"Water Bill\"\
    }\
 }
=cut
sub addMessage {
  my $self = shift;
  my $conversationID = shift;
  my $messageData = shift;

  fail('No gateway account defined for AuthVia Conversation AddMessage') if !defined $self->getGatewayAccount();
  fail('Unable to add message, conversation identifier not passed to update function') if !defined $conversationID;
  fail('Unable to add message, missing message data') if ref($messageData) ne 'HASH';

  
  my $now = new PlugNPay::Sys::Time()->nowInFormat('unix');
  if (ref($_tokenData->{$self->getGatewayAccount()}) ne 'HASH' || $_tokenData->{$self->getGatewayAccount()}{'expirationTime'} <= $now) {
    $_tokenData->{$self->getGatewayAccount()} = $self->getAuthorizationToken($self->getGatewayAccount());
  }

  # NOTE: not using messageData in case there's extra fields, authvia returns error on extra data here
  my $data = {
    'template' => $messageData->{'template'},
    'context'  => $messageData->{'context'}
  };
  
  my $response = $self->_doRequest('POST', {
      'endpoint'    => 'conversations/' . $conversationID . '/messages',
      'requestData' => $data,
      'headers'     => {'Authorization' => 'Bearer ' . $_tokenData->{'token'}}
    }
  );

  return $response;
}

# Saves data from request
sub save {
  my $self = shift;
  my $phoneNumber = shift;
  my $customerId = shift;
  my $conversationId = shift;
  my $response = shift;
  my $merchant = $self->getGatewayAccount();
  my $data;

  eval {
    my $contextJSON;
    if (ref($response->{'context'}) eq 'HASH') {
      $contextJSON = encode_json($response->{'context'});
    }
    my $url = $self->getServiceURL() . '/conversation';

    $data = {
      conversationId => $conversationId,
      status         => $response->{'status'},
      merchant       => $merchant,
      phoneNumber    => $phoneNumber,
      context        => $contextJSON, 
      customerId     => $customerId,
      name           => $response->{'name'}
    };

    my $ms = new PlugNPay::ResponseLink::Microservice();
    $ms->setMethod('POST');
    $ms->setURL($url);
    $ms->setContent($data);
    my $status = $ms->doRequest();
    my $decodedResponse = $ms->getDecodedResponse();
    if (!$status || $decodedResponse->{'error'}) {
      die $decodedResponse->{'errorMessage'} || 'request to service failed';
    }
  };

  if ($@)  {
    $self->log({
      'error' => $@,
      'conversation' => $conversationId,
      'merchant' => $merchant,
      'customerId' => $customerId,
      'phoneNumber' => $phoneNumber
    });
  }
}

sub updateConversation {
  my $self = shift;
  my $conversationID = shift;
  my $response = shift;

  my $data = { 
    conversationId => $conversationID,
    merchant       => $self->getGatewayAccount()
  };
  my $shouldSend = 0;
  if (ref($response->{'context'}) eq 'HASH') {
    my $contextJSON = encode_json($response->{'context'});
    $data->{'context'} = $contextJSON;
    $shouldSend = 1;
  }
  
  if ($response->{'status'}) {
    $data->{'status'} = $response->{'status'} || 'resolved';
    $shouldSend = 1;
  }

  if (!$shouldSend) {
    return;
  }

  eval {
    my $url = $self->getServiceURL() . '/conversation';
    my $ms = new PlugNPay::ResponseLink::Microservice();
    $ms->setRequestMethod('PUT');
    $ms->setRequestURL($url);
    $ms->setRequestContentType('application/json');
    $ms->setRequestData($data);
    $ms->doRequest();
    my $response = $ms->getDecodedResponse();
  };

  if ($@) {
    $self->log({'error' => $@, 'conversation' => $conversationID, 'merchant' => $self->getGatewayAccount()});
  }
}

sub _validatePhoneNumber {
  my $phoneNum = shift;
  if (index($phoneNum, '+') == -1) {
    if (length($phoneNum) == 10) {
      $phoneNum = '1'. $phoneNum;
    }

    $phoneNum = '+' . $phoneNum; 
  } 

  return $phoneNum;
}

sub generateCustomerID {
  my $self = shift;
  my $id = new PlugNPay::Util::UniqueID()->inHex();
  return $id;
}

1;
