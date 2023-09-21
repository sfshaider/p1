package PlugNPay::Partners::AuthVia::Merchant;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::ResponseLink::Microservice;
use JSON::XS;
use PlugNPay::Die qw(fail die);
use PlugNPay::Util::Hash;
use PlugNPay::Security::JWT;
use PlugNPay::Util::UniqueID;
use base "PlugNPay::Partners::AuthVia::Authorization";

our $authorizationData;
our $_transactionEndpoint;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->{'scope_list'} = ['merchants:create','merchants:update','merchants:read'];

  return $self;
}

sub getServiceTransactionEndpoint {
  if (!defined $_transactionEndpoint || $_transactionEndpoint eq '') {
    $_transactionEndpoint = 'api.dev.gateway-assets.com' || $ENV{'AUTHVIA_TRANS_URL'} || PlugNPay::AWS::ParameterStore::getParameter('/SERVICE/AUTHVIA/URL/TRANSACTION');
  }

  return $_transactionEndpoint;
}

=pod
  Creates a merchant with authvia

  INPUT: merchant name (example "testmerch")
  OUTPUT: 
  {
    "id": "369c876f-f304-4949-80e0-31d95a07bc5b"
    "profile": {
       "name": "Super Merchant",
       "description": "Selling only the greatest things!",
       "logo": "https://www.somedomain.com/images/logo.png",
       "website": "https://www.somedomain.com/"
    }, 
    "contacts": [
      {
       "purpose": "help",
       "type": "email",
       "value": "test@test.com",
       "name": "Emailia"
      },
      {
       "purpose": "business",
       "type": "mobile-phone",
       "value": "+11111111111",
       "name": "Phony Phil"
      },
    ]
  }

  cURL request:
  curl -XPOST -H 'Authorization: Bearer YOUR_TOKEN' -H "Content-type: application/json" -d '{
    "profile": {
       "name": "Super Merchant",
       "description": "Selling only the greatest things!",
       "logo": "https://www.somedomain.com/images/logo.png",
       "website": "https://www.somedomain.com/"
     }, 
    "contacts": [
    {
     "purpose": "help",
     "type": "email",
     "value": "test@test.com",
       "name": "Emailia"
      },
      {
       "purpose": "business",
       "type": "mobile-phone",
       "value": "+11111111111",
       "name": "Phony Phil"
      },
    ]
  }' 'https://api.authvia.com/v3/merchants'
=cut

sub create {
  my $self = shift;
  my $merchant = $self->getGatewayAccount();

  if (!$merchant) {
    fail('Merchant name not set for AuthVia merchant create!');
  }

  my $idLoader = new PlugNPay::GatewayAccount::InternalID();
  my $internalId = $idLoader->getIdFromUsername($merchant);
  die 'unable to find merchant identifier' if ($internalId eq '' || !defined $internalId);

  my $token = $self->generateAuthorizationRequest();
  my $response = $self->_modifyMerchantData('POST', $merchant, $token);

  my $savedJWT = 0;
  my $savedMerchant = 0;
  if (!exists $response->{'error'}) {
    #Send JWT
    my $productResponse;
    eval {
      $productResponse = $self->addProduct($merchant,$response->{'id'},$token);
    };

    if ($@ || ref($productResponse->{'response'}) ne 'HASH') {
      $self->log({'message' => 'failed to send jwt to authvia', 'error' => $@ || 'no response received', 'merchant' => $merchant, 'response' => $productResponse});
    }

    my $pnpToken = $productResponse->{'jwtToken'};

    #save merchant to database
    my $serviceResponse = $self->_saveMerchant($merchant, $response);
    $savedMerchant = $serviceResponse->{'error'} == 0;

    #save product/pnp-jwt to database
    $savedJWT = $self->_saveJWT($merchant, $internalId, $productResponse);
  }

  $response->{'savedMerchant'} = $savedMerchant;
  $response->{'savedPNPMerchantJWT'} = $savedJWT;
  return $response;
}

sub _saveMerchant { 
  my $self = shift;
  my $merchant = shift;
  my $response = shift;

  my $url = $self->getServiceURL() . "/merchant";
  my $partnerRowId = $self->getClientRowId();

  my $saveData = {
    authViaMerchantId => $response->{'id'},
    pnpUsername       => $merchant,
    status            => $response->{'status'},
    partnerClientId   => $partnerRowId
  };

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setContent($saveData);
  $ms->setMethod('POST');
  $ms->setURL($url);
  $ms->setContentType('application/json');
  $ms->doRequest();
  my $serviceResponse = $ms->getDecodedResponse();

  return $serviceResponse;
}

sub _saveJWT {
  my $self = shift;
  my $merchant = shift;
  my $internalId = shift;
  my $productResponse = shift;
  my $productId = $productResponse->{'response'}{'id'};
  my $uuid = $productResponse->{'uuid'};
  my $token = $productResponse->{'token'};

  if (!defined $productId || $productId eq '') {
    return 0;
  }

  if (!defined $token || $token eq '') {
    return 0;
  }

  if (!defined $uuid || $uuid eq '') {
    return 0;
  }

  my $url = $self->getServiceURL() . "/security/token";
  my $saveData = {
    username  => $merchant,
    productId => $productId,
    uuid      => $uuid,
    token     => $token
  };

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setContent($saveData);
  $ms->setMethod('POST');
  $ms->setURL($url);
  $ms->setContentType('application/json');
  $ms->doRequest();
  my $serviceResponse = $ms->getDecodedResponse();

  return $serviceResponse->{'error'} == 0;
}

sub _modifyMerchantData {
  my $self = shift;
  my $method = shift;
  my $username = shift;
  my $options = shift || {};
  my $gaObject = new PlugNPay::GatewayAccount($username);
  my $token = $self->generateAuthorizationRequest();

  my $contactList = [];
  my $contact = $gaObject->getMainContact();
  
  if ($contact->getEmailAddress()) {
    push @{$contactList}, {
      'value'   => $contact->getEmailAddress(),
      'type'    => 'email',
      'purpose' => 'business',
      'name'    => $contact->getFullName()
    }
  }

  if ($contact->getPhone()) {
    my $phone = $contact->getPhone();
    $phone =~ s/[^\d]//g;
    if (length($phone) == 10 && $contact->getCountry() =~ /^(US|USA|CA|CAN)$/i) { #might need to deal with this
      $phone = '+1' . $phone;
    }

    push @{$contactList}, {
      'value'   => $phone,
      'type'    => 'phone',
      'purpose' => 'business',
      'name'    => $contact->getFullName()
    }
  }

  my $merchant = {
    'profile' => {
      'name' => $gaObject->getCompanyName()
    },
    'contacts' => $contactList
  };

  my $website = $gaObject->getURL();
  if ($website =~ /^https:\/\//i) {
    $merchant->{'profile'}{'website'} = $website;
  }
  
  my $data = {
    'endpoint' => $options->{'endpoint'} || 'merchants',
    'requestData' => $merchant,
    'headers' => {'Authorization' => 'Bearer ' . $token->{'token'}}
  };

  my $response = $self->_doRequest($method, $data);

  return $response;
}

=pod
  What are Products?
  "A Product on your merchant account/business allows you to configure and enable features such as payments, to receive payments via a variety of payment methods/platforms.
   Other features include messaging."

   AuthVia wants us to send our JWT (for API authentication on our end) and the processing endpoint with products
=cut

sub addProduct {
  my $self = shift;
  my $merchant = shift;
  my $authViaMerchantId = shift;
  my $authToken = shift;
  if (!defined $merchant || !defined $authViaMerchantId) {
    die 'missing required merchant info for creating AuthVia JWT';
  }

  my $uid = new PlugNPay::Util::UniqueID();
  my $uniqueIdentifier = $uid->generate();

  my $jwtToken = &PlugNPay::Security::JWT::generate({
    'secretType' => 'HS256',
    'claims'     => { 'gatewayAccount' => $merchant, 'provider' => 'authvia', 'id' => $uniqueIdentifier }
  });

  my $json = {
    'line' => 'payments',
    'product' => 'creditcard',
    'provider' => 'plugnpay',
    'config' => {
      'token'  => $jwtToken,
      'host' => $self->getServiceTransactionHost(),
      'merchantId' => $merchant
    }
  };

  my $requestData = {
    'endpoint' => 'merchants/' . $authViaMerchantId . '/products',
    'requestData' => $json,
    'headers' => {'Authorization' => 'Bearer ' . $authToken->{'token'}}
  };

  my $response = $self->_doRequest('POST', $requestData);
  return {'response' => $response, 'token' => $jwtToken, 'uuid' => $uniqueIdentifier};
}

sub getProducts {
  my $self = shift;
  my $merchant = $self->getGatewayAccount();

  if (!defined $merchant || $merchant eq '') {
    die 'no merchant name set for loading';
  }

  my $authToken = $self->generateAuthorizationRequest();
  my $authViaMerchantId = $self->load($merchant)->{'authViaMerchantId'};
  my $json = {
    'username'          => $merchant,
    'authViaMerchantId' => $authViaMerchantId,
    'authToken'         => $authToken
  };

  my $url = $self->getServiceURL() . '/products/list';
  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setURL($url);
  $ms->setMethod('POST');
  $ms->setContentType('application/json');
  $ms->setContent($json);
  $ms->doRequest();
  my $response = $ms->getDecodedResponse();
  if ($response->{'error'}) {
    $self->log({'error' => $response->{'errorMessage'}, 'merchant' => $merchant, 'authViaMerchantId' => $authViaMerchantId});
  }

  return $response;
}

#TODO: add update product stuff here, current implementation was not working so removed

=pod
 Changes merchant data with AuthVia, is a shell function essentially. GatewayAccount data must be modified, then call this.

 INPUT: Merchant name (i.e. "testmerch")
 OUTPUT: 
  {
    "id": "369c876f-f304-4949-80e0-31d95a07bc5b",
    "profile": {
       "name": "Super Merchant",
       "description": "Selling only the greatest things!",
       "logo": "https://www.somedomain.com/images/logo.png",
       "website": "https://www.somedomain.com/"
    }, 
    "contacts": [
      {
       "purpose": "help",
       "type": "email",
       "value": "test@test.com",
       "name": "Emailia"
      },
      {
       "purpose": "business",
       "type": "mobile-phone",
       "value": "+11111111111",
       "name": "Phony Phil"
      }
    ]
  }


 cURL request
 UPDATE: method: Patch
 {
  "profile": {
     "name": "Super Merchant",
     "description": "Selling only the greatest things!",
     "logo": "https://www.somedomain.com/images/logo.png",
     "website": "https://www.somedomain.com/"
  },
  "contacts": [
    {
     "purpose": "help",
     "type": "email",
     "value": "test@test.com",
     "name": "Emailia"
    },
    {
     "purpose": "business",
     "type": "mobile-phone",
     "value": "+11111111111",
     "name": "Phony Phil"
    },
  ]
 }
=cut

sub update {
  my $self = shift;
  my $username = $self->getGatewayAccount();

  if (!$username) {
    fail('No merchant name set for AuthVia merchant update request!');
  }

  my $authviaMerchData = $self->load($username);
  my $options = {'endpoint' => 'merchants/' . $authviaMerchData->{'authViaMerchantId'}};
  my $result = $self->_modifyMerchantData('PATCH', $username, $options);

  return $result;
}

#curl -XGET -H 'Authorization: Bearer YOUR_TOKEN' -H "Content-type: application/json" 'https://api.authvia.com/v3/merchants/{merchant-id}'

sub read {
  my $self = shift;
  my $username = $self->getGatewayAccount();

  if (!$username) {
    fail('No merchant name set for AuthVia merchant read request!');
  }

  my $token = $self->generateAuthorizationRequest();
  my $authviaMerchData = $self->load($username);
  my $result = $self->_doRequest('GET', {
    'endpoint' => 'merchants/' . $authviaMerchData->{'authViaMerchantId'},
    'headers' => {'Authorization' => 'Bearer ' . $token->{'token'}}
  });

  return $result;
}

sub isEnrolled {
  my $self = shift;
  my $merchant = shift || $self->getGatewayAccount();
  my $response = {};
  eval {
    my $url = $self->getServiceURL() . "/merchant/enrollment/username/" . $merchant;
    my $rl = new PlugNPay::ResponseLink::Microservice();
    $rl->setTimeout(5);
    $rl->setURL($url);
    $rl->setMethod('GET');
    my $wasSuccess = $rl->doRequest();
    if ($wasSuccess) {
      $response = $rl->getDecodedResponse();
    }
  };

  if ($@) {
    $self->log({'error' => $@, 'username' => $merchant, 'function' => 'isEnrolled'});
  }

  return $response->{'enrolled'} ? 1 : 0;
}

sub load {
  my $self = shift;
  my $loadData = shift;

  my $accountToLoad;
  my $paramString = '';
  if (ref($loadData) ne 'HASH') {
    $accountToLoad = $loadData || $self->getGatewayAccount();
  } else {
    if (exists $loadData->{'gatewayAccount'}) {
      $accountToLoad = $loadData->{'gatewayAccount'};
      delete $loadData->{'gatewayAccount'};
    }

    my @paramArr = ();
    foreach my $key (keys %{$loadData}) {
      push @paramArr, $key . '=' . $loadData->{$key};
    }
    if (@paramArr > 0) {
      $paramString = join('&',@paramArr);
    }
  }

  if (!defined $accountToLoad) {
     $accountToLoad = $self->getGatewayAccount();
  }
 
  my $url = $self->getServiceURL() . '/merchant/username/' . $accountToLoad;
  $url .= '?' . $paramString if defined $paramString && $paramString ne '';

  my $ms = new PlugNPay::ResponseLink::Microservice();
  $ms->setMethod('GET');
  $ms->setURL($url);
  $ms->doRequest();
  my $responseData = $ms->getDecodedResponse();
  my $loaded = $responseData;


  if (!defined $loaded) {
    fail('no merchant data loaded in AuthVia::Merchant::load');
  } elsif ($loaded->{'error'}) {
    die $loaded->{'errorMessage'};
  }

  return $loaded;
}

1;
