package PlugNPay::ResponseLink::RequestLog;

use strict;
use JSON::XS;
use URI::Escape;
use HTTP::Request;
use LWP::UserAgent;
use PlugNPay::ResponseLink;

#################### Using RequestLog.pm ########################
#                                                               #
#  my $log = new PlugNPay::ResponseLink::RequestLog($username); #
#                                                               #
# Init wit GatewayAccount name that the request used            #
# Can also use $log->setGatewayAccount($username);              #
#                                                               #
#  $log->addRequestID(1); #adds a single 'request id' at a time #
#  $log->addRequestID(2);                                       #
#                                                               #
# Or you can set the whole array at once,                       #
# This WILL remove previously added IDs                         #
#                                                               #
#  my $array = (1,2,3);                                         #
#  my $arrayRef = \@array;                                      #
#  $log->setRequestIDs($arrayRef); MUST PASS ARRAY REF!         #
#                                                               #
# Or, to search by date range: don't need to add both,          #
# This is in 'db' format, as describe in Time.pm,               #
# You can use that to format if you'd like                      #
#                                                               #
#  $log->setStartDate('2014-01-01 00:00:00');                   #
#  $log->setEndDate('2016-01-01 12:26:00');                     #
#                                                               #
#################################################################    

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $username = shift;
  $self->setGatewayAccount($username);

  return $self;
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub getGatewayAccount {
  my $self = shift;
  return $self->{'gatewayAccount'};
}

sub setRequestIDs {
  my $self = shift;
  my $requestIDs = shift;
  $self->{'request_ids'} = $requestIDs;
}

sub getRequestIDs {
  my $self = shift;
  return $self->{'request_ids'};
}

sub addRequestID {
  my $self = shift;
  my $id = shift;
  my $ids = $self->getRequestIDs();
  if (!defined $ids || ref($ids) ne 'ARRAY') {
    @{$ids} = ();
  }

  push @{$ids},$id;
  $self->setRequestIDs($ids);
}

sub setStartDate {
  my $self = shift;
  my $startDate = shift;
  $self->{'startDate'} = $startDate;
}

sub getStartDate {
  my $self = shift;
  return $self->{'startDate'};
}

sub setEndDate {
  my $self = shift;
  my $endDate = shift;
  $self->{'endDate'} = $endDate;
}

sub getEndDate {
  my $self = shift;
  return $self->{'endDate'};
}

sub setRequestTimeout {
  my $self = shift;
  my $requestTimeout = shift;
  $self->{'requestTimeout'} = $requestTimeout;
}

sub getRequestTimeout {
  my $self = shift;
  return $self->{'requestTimeout'};
}

sub setResponseData {
  my $self = shift;
  my $responseData = shift;
  $self->{'responseData'} = $responseData;
}

sub getResponseData {
  my $self = shift;
  return $self->{'responseData'};
}

sub setKeyNames {
  my $self = shift;
  my $keyNames = shift;
  $self->{'keyNames'} = $keyNames;
}

sub getKeyNames {
  my $self = shift;
  return $self->{'keyNames'};
}

sub addKeyName {
  my $self = shift;
  my $name = shift;
  my $names = $self->getKeyNames();
  if (!defined $names || ref($names) ne 'ARRAY') {
    @{$names} = ();
  }

  push @{$names},$name;
  $self->setKeyNames($names);
}

sub formatURLData {
  my $self = shift;
  my $username = (defined $self->getGatewayAccount() ? $self->getGatewayAccount() : $ENV{'PNP_REMOTE_USER'});
  my $url = $ENV{'PNP_PROXY_SERVER'} . '/!/username/:' . $username;

  my $ids = $self->getRequestIDs();
  if (defined $ids) {
   my $idString = join(',',@{$ids});
    $url .= '/ids/:' . uri_escape($idString);
  }

  my $keyNames = $self->getKeyNames();
  if (defined $keyNames) {
    my $keyNameString = join(',',@{$keyNames});
    $url .= '/pairnames/:' . uri_escape($keyNameString);
  }
  
  if (defined $self->getStartDate()) {
    $url .= '/startdate/:' . uri_escape($self->getStartDate()) if defined $self->getStartDate();
  }

  if (defined $self->getEndDate()) {
    $url .= '/enddate/:' . uri_escape($self->getEndDate()) if defined $self->getEndDate();
  }
  
  return $url;
}

sub getLogs {
  my $self = shift;
  my $url = $self->formatURLData();
  my $userAgent = new LWP::UserAgent;
  $userAgent->agent('RequestLog');
  $userAgent->timeout($self->getRequestTimeout());

  # Start request
  my $request = new HTTP::Request(GET => $url);
  $request->header(accept => 'application/json');
  my $response = $userAgent->request($request);
  my $data;
  if ($response->is_success()) {
    eval{
      my $JSON = JSON::XS->new->utf8->decode($response->decoded_content());
      $data = $JSON->{'content'}{'data'};
      $self->setRequestKeys($data->{'content'}{'data'}{'data'}{'requestContentKeys'});
    };

    if ($@) {
      print $@;
      $data = $response->decoded_content;
    }
   
    $self->setResponseData($data);
  }  else {
    $data = {'status' => 'failure', 'message'=>$response->message};
  }
  
  return $data;
}

sub setRequestKeys {
  my $self = shift;
  my $requestKeys = shift;
  $self->{'requestKeys'} = $requestKeys;
}

sub getRequestKeys {
  my $self = shift;
  return $self->{'requestKeys'};
}

1;
