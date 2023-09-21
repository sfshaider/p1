package PlugNPay::API::REST::Responder::Reseller::Merchant::Service::Request;

use strict;
use PlugNPay::GatewayAccount;
use PlugNPay::Reseller::Chain;
use PlugNPay::Reseller::Helpdesk;
use JSON::XS qw(decode_json);

use URI qw();

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData{
  my $self = shift;
  my $ga = new PlugNPay::GatewayAccount($self->getResourceData()->{'merchant'});
  my $reseller = $self->getGatewayAccount();
  my $chain = new PlugNPay::Reseller::Chain($reseller);
  my $action = $self->getAction();

  if ($action eq 'create' && ($reseller eq $ga->getReseller() || $chain->hasDescendant($ga->getReseller()))) {
    $self->setResponseCode(200);
    return $self->_create();
  } else {
    $self->setResponseCode(501);
    return {};
  }
}

sub _create {
  my $self = shift;
  my $resourceData = $self->getResourceData();
  my $service = $resourceData->{'service'};
  my $ga = $resourceData->{'merchant'};
  if (!$ga) {
    $self->setResponseCode(422);
    $self->setErrorMessage('Unable to determine api client account');
  }

  # if the service is fraudtrak2, turn it on
  # other services need to go through helpdesk
  if ($service eq 'fraudtrak2') {
    my $svcs = new PlugNPay::GatewayAccount::Services($ga);
    $svcs->setFraudTrack(1);
    $svcs->save();
    $self->setResponseCode(201);
    return {}
  } else {
    # the data is a querystring of the following:
    # pnp_user (username)
    # email (reseller email or merchant email depending on where it's being called from)
    # source ("reseller"?)
    # priorityId (priority for "normal"?)
    # subject ("new recurring setup")
    my $reseller = $self->getGatewayAccount();
    my $resellerObj = new PlugNPay::GatewayAccount($reseller);
    my $email = $resellerObj->getMainContact()->getEmailAddress();
    my $hdData = {
      pnp_user => "$ga",
      email => 'noreply@plugnpay.com',
      source => 'reseller',
      topicId => 1, # 1 is support, 2 is accounting
      priorityId => 2, # 2 is "normal"
      message => $reseller . ' requested set up for account: ' . $ga
    };

    my $subjectMappings = {
      recurring => 'recurring setup requested',
      recurringwithpasswordmanagement => 'recurring with password management setup requested',
      passwordmanagement => 'password management setup requested',
      membership => 'membership setup requested',
      billpay => 'billpay setup requested'
    };

    $hdData->{'subject'} = $subjectMappings->{$service};

    my $url = URI->new('', 'http');
    $url->query_form(%{$hdData});
    my $data = $url->query;
    my $ticketCreationSuccessful = 0;
    my $hd = new PlugNPay::Reseller::Helpdesk();
    eval {
      my $info = $hd->newTicket($data);
      $ticketCreationSuccessful = $info->{'status'} ? 1 : 0;
    };
    if ($@) {
      # log the error
      $self->log({
        message => "failed to create ticket on helpdesk",
        error => $@,
        url => $hd->getURL(),
        data => $hd->getData(),
        method => $hd->getMethod()
      });
    };
    if ($ticketCreationSuccessful) {
      my $svc = new PlugNPay::GatewayAccount::Services::Service({ handle => $service });
      my $gaObj = new PlugNPay::GatewayAccount($ga);
      my $svcreq = new PlugNPay::GatewayAccount::Services::Requested({ gatewayAccount => $gaObj });
      $svcreq->request({ service => $svc });
      $self->setResponseCode(201);
      return {};
    } else {
      $self->setResponseCode(500);
      return {};
    }
  }
}


1;
