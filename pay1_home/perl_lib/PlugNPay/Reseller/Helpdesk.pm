package PlugNPay::Reseller::Helpdesk;

use strict;
use PlugNPay::UI::Template;
use PlugNPay::ResponseLink;

use JSON::XS;
use URI qw();

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  $self->setGatewayAccount(shift);
  $self->setResponseType('json');

  return $self;
}

###################
# Setters/Getters #
###################
sub setGatewayAccount {
  my $self = shift;
  $self->{'username'} = shift;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'username'};
}

#External URL
sub setURL {
  my $self = shift;
  $self->{'url'} = shift;
}

sub getURL {
  my $self = shift;
  return $self->{'url'};
}

#Request Method
sub setMethod {
  my $self = shift;
  $self->{'method'} = shift;
}

sub getMethod {
  my $self = shift;
  return $self->{'method'};
}

#Request Data
sub setData {
  my $self = shift;
  $self->{'data'} = shift;
}

sub getData {
  my $self = shift;
  return $self->{'data'};
}

#Response Data Type
sub setResponseType{
  my $self = shift;
  $self->{'type'} = shift;
}

#####################################
# Interact with Helpdesk Ticket API #
#####################################
sub getTickets{
  my $self = shift;
  my $data = shift;

  if (ref($data) ne 'HASH') {
    $data = {};
  }

  $data->{'username'} = $self->getGatewayAccount();

  $self->setData($data);
  $self->setMethod('GET');
  $self->setURL('https://helpdesk.plugnpay.com/hd/api/pnp_tickets.php');
  return $self->apiConnect();
}

# the data is a querystring of the following:
# pnp_user (username)
# email (reseller email or merchant email depending on where it's being called from)
# topicId (dept id for support?)
# source ("reseller"?)
# priorityId (priority for "normal"?)
# subject ("new recurring setup")
sub newTicket {
  my $self = shift;
  my $data = shift;

  # convert hashref input to query string
  if (ref($data) eq 'HASH') {
    my $url = URI->new('', 'http');
    $url->query_form(%{$data});
    $data = $url->query;
  }

  $self->setData($data);
  $self->setMethod('POST');
  $self->setURL('https://helpdesk.plugnpay.com/hd/api/pnp_openticket.php');
  my $response = $self->apiConnect();
  return $response;
}

sub apiConnect {
  my $self = shift;

  my $username = $self->{'username'};
  my $url = $self->{'url'};
  my $method = $self->{'method'};
  my $data = $self->{'data'};
  my $type = $self->{'type'};

  my $RSLink = new PlugNPay::ResponseLink($username,$url,$data,$method,$type);
  $RSLink->doRequest();

  my $tickets = JSON::XS->new->utf8->decode($RSLink->getResponseContent());

  return $tickets;
}

sub prepareForGoogleTable {
  my $self = shift;
  my $data = shift;
  my @rows;
  foreach my $ticket (@$data){
    my @row;

    push @row, $ticket->{'ticket'};
    push @row, $ticket->{'email'};
    push @row, $ticket->{'subject'};
    push @row, $ticket->{'status'};
    push @row, $ticket->{'pendingCustomerResponse'};
    if ($ticket->{'linkable'}){
      push @row, 'click';
    } else {
      push @row, '';
    }

    push @rows, \@row;
  }

  return \@rows;
}


1;
