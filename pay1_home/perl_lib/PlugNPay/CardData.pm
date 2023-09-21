package PlugNPay::CardData;

use strict;
use Time::HiRes;
use PlugNPay::Logging::DataLog;
use PlugNPay::Logging::Alert;
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::AWS::ParameterStore;
use PlugNPay::Util::Status;
use PlugNPay::Debug;
use PlugNPay::Die;
use PlugNPay::Metrics;

our $cachedServer;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  if (!$cachedServer) {
    my $env = $ENV{'PNP_CARDDATA_SERVICE'};
    $cachedServer = $env || PlugNPay::AWS::ParameterStore::getParameter('/CARDDATA/SERVER',1);
    $cachedServer =~ s/\/+$//;
  }

  return $self;
}

sub getOrderCardData {
  my $self = shift;

  my $input = shift;

  my $request = {};
  $request->{'realm'} = 'order';
  $request->{'identifier'} = $input->{'orderID'};
  $request->{'username'} = $input->{'username'};
  $request->{'suppressAlert'} = $input->{'suppressAlert'};
  $request->{'suppressError'} = $input->{'suppressError'};

  my $data = $self->_doRequest($request, 'GET');

  return $data->{'response'}{'cardData'};
}

sub insertOrderCardData {
  my $self = shift;

  my $input = shift;

  my $transDate = $input->{'transDate'};
  if (!$transDate) {
    $transDate = new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd_gm');
  }

  my $request = {};
  $request->{'realm'} = 'order';
  $request->{'identifier'} = $input->{'orderID'};
  $request->{'username'} = $input->{'username'};
  $request->{'cardData'} = $input->{'cardData'};
  $request->{'transDate'} = $transDate;
  my $data = $self->_doRequest($request, 'POST');

  return $data->{'response'}{'status'};
}

sub getRecurringCardData {
  my $self = shift;

  my $input = shift;

  my $request = {};
  $request->{'realm'} = 'recurring';
  $request->{'identifier'} = lc($input->{'customer'});
  $request->{'username'} = $input->{'username'};
  $request->{'suppressAlert'} = $input->{'suppressAlert'};
  $request->{'suppressError'} = $input->{'suppressError'};
  
  my $data = $self->_doRequest($request, 'GET');

  return $data->{'response'}{'cardData'};
}

sub insertRecurringCardData {
  my $self = shift;

  my $input = shift;

  my $request = {};
  $request->{'realm'} = 'recurring';
  $request->{'username'} = $input->{'username'};
  $request->{'cardData'} = $input->{'cardData'};
  $request->{'identifier'} = lc($input->{'customer'});
  $request->{'suppressAlert'} = $input->{'suppressAlert'};
  $request->{'suppressError'} = $input->{'suppressError'};

  my $data = $self->_doRequest($request, 'POST');
  return $data->{'response'}{'status'};
}

sub removeRecurringCardData {
  my $self = shift;

  my $input = shift;

  my $request = {};
  $request->{'realm'} = 'recurring';
  $request->{'username'} = $input->{'username'};
  $request->{'identifier'} = lc($input->{'customer'});
  $request->{'suppressError'} = $input->{'suppressError'};

  my $data = $self->_doRequest($request, 'DELETE');

  return $data->{'response'}{'status'};
}

sub getBillpayCardData {
  my $self = shift;

  my $input = shift;

  my $request = {};
  $request->{'realm'} = 'billpay';
  $request->{'username'} = lc($input->{'customer'});
  $request->{'identifier'} = $input->{'profileID'};
  $request->{'suppressAlert'} = $input->{'suppressAlert'};
  $request->{'suppressError'} = $input->{'suppressError'};
  my $data = $self->_doRequest($request, 'GET');

  return $data->{'response'}{'cardData'};
}

sub insertBillpayCardData {
  my $self = shift;

  my $input = shift;

  my $request = {};
  $request->{'realm'} = 'billpay';
  $request->{'username'} = $input->{'customer'};
  $request->{'cardData'} = $input->{'cardData'};
  $request->{'identifier'} = lc($input->{'profileID'});
  my $data = $self->_doRequest($request, 'POST');

  return $data->{'response'}{'status'};
}

sub getErrorType {
  my $self = shift;
  return $self->{'errorType'};
}

sub _doRequest {
  my $self = shift;

  my $rStatus = new PlugNPay::Util::Status(1);

  my $data = shift || {};
  my $action = uc(shift) || 'GET';
  if ($data->{'realm'} && $data->{'username'} && $data->{'identifier'}) {
    my $link = new PlugNPay::ResponseLink::Microservice();
    $link->setTimeout(7);
    my $url = $cachedServer  . '/v1/' . $data->{'realm'} . '/' . $data->{'username'} . '/' . $data->{'identifier'};
    $link->setURL($url);
    $link->setMethod($action);
    my $postData = {};

    if ($action eq 'POST') {
      # add card data
      $postData->{'cardData'} = $data->{'cardData'};

      # add trans date if present
      if ($data->{'transDate'}) {
        $postData->{'transDate'} = $data->{'transDate'};
      }

      $link->setContent($postData);
    }

    debug({ cardDataRequestContent => $postData, cardDataUrl => $url, method => $action }, { stackTrace => 1 });

    # start time for calculating request duration
    my $metrics = new PlugNPay::Metrics();
    my $start = $metrics->timingStart();

    my $status = $link->doRequest();

    $metrics->timingEnd({
      metric => 'service.carddata.duration',
      start => $start
    });

    if (!$status) {
      if ($link->getResponseCode() eq '404') {
        $self->{'errorType'} = 'notfound';
      } else {
        $self->{'errorType'} = 'failure';
      }
    } else {
      $self->{'errorType'} = undef;
    }

    my $response = {};
    eval {
      $response = $link->getDecodedResponse();
    };
    if (($@ || !$status) && !$data->{'suppressError'} && $self->{'errorType'} != 'notfound') {
      die 'Invalid response from Card Data microservice';
    }

    debug({ cardDataStatusCode => $link->getResponseCode(), cardDataResponseContent => $response });

    if (!$status && !$data->{'suppressAlert'} && $self->{'errorType'} != 'notfound') {
      my $serviceErrors = $link->getErrors();
      my $alerter = new PlugNPay::Logging::Alert();
      my $error = 'A error response occurred when sending request to CardData Microservice. Response Code: ' . $link->setResponseCode() . '  -- Response: ' . $link->getRawResponse() . "\n\nURL: $url\n\nErrors: " . join(', ',@{$serviceErrors});
      $alerter->alert(7,$error);

      my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'microservice-carddata' });
      $logger->log({ 'realm' => $data->{'realm'}, 'username' => $data->{'username'}, 'identifier' => $data->{'identifier'}, 'error' => $error });
    }

    $rStatus->set('status', 'success');
    $rStatus->set('response', $response);
    return $rStatus;
  } else {
    my $logger = new PlugNPay::Logging::DataLog({'collection' => 'microservice-general'});
    $logger->log({'realm' => $data->{'realm'}, 'username' => $data->{'username'}, 'identifier' => $data->{'identifier'}});
    $rStatus->setFalse();
    $rStatus->set('status','failure');
    $rStatus->set('response',{'error' =>'Invalid request data', 'status' => 'failure'});
    return $rStatus;
  }
}

1;
