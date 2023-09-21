package PlugNPay::ResponseLink::LocalProxy::Response;

# Emulates some functionality of HTTP::Response

use strict;
use warnings FATAL => 'all';

use MIME::Base64;
use JSON::XS;

sub new {
  my $class = shift;
  my $self = {};

  bless $self,$class;

  my $input = shift;


  my $httpResponse = $input->{'response'};
  if (defined $httpResponse) {
    if (ref($httpResponse) eq 'HTTP::Response') {
      $self->setHttpResponse($httpResponse);
    } else {
      die('not an http response');
    }
  }

  my $options = $input->{'options'};
  if (defined $options) {
    if (ref($options) eq 'HASH') {
      $self->setOptions($options);
    } else {
      die('options is not a hashref');
    }
  }
  
  return $self;
}

sub setOptions {
  my $self = shift;
  my $options = shift;

  foreach my $option (keys %{$options}) {
    if (!inArray($option,['checkContentType'])) {
      die('invalid option: ' . $option);
    }
  }

  $self->{'options'} = $options;
}

sub setHttpResponse {
  my $self = shift;
  my $httpResponse = shift;

  my $proxyStatusCode = $httpResponse->code();
  if ($proxyStatusCode !~ /^2\d\d/) {
    $self->{'statusCode'} = $proxyStatusCode;
    $self->{'statusReason'} = 'proxy error';
    return
  }

  if ($self->{'options'}{'checkContentType'} && lc $httpResponse->header('content-type') !~ /^application\/json/) {
    die('unexpected content-type [' . $httpResponse->header('content-type') . '] returned from proxy');
  }

  my $body = $httpResponse->decoded_content;
  $self->_parseJsonBody($body);
}

sub _parseJsonBody {
  my $self = shift;
  my $body = shift;

  my $jsonDecoder = JSON::XS->new->ascii();

  # decode json body
  my $data = $jsonDecoder->decode($body);

  # decode base64 content value
  my $decodedContent;
  eval {
    $decodedContent = decode_base64($data->{'content'});
  };

  if ($@) {
    die('Invalid base64 content: ' . $@);
  }

  $self->{'headers'} = $data->{'headers'};
  $self->{'statusCode'} = $data->{'statusCode'};
  $self->{'statusReason'} = $data->{'status'};
  $self->{'content'} = $decodedContent;
}

sub getContent {
  my $self = shift;
  return $self->{'content'};
}

sub getHeaders {
  my $self = shift;
  my %headers = %{$self->{'headers'}};
  return \%headers;
}

sub getHeaderNames {
  my $self = shift;
  my @headerNames = keys %{$self->{'headers'} || {}};
  return \@headerNames;
}

sub getHeader {
  my $self = shift;
  my $headerName = shift;
  my $headerValues = [''];
  foreach my $potentialHeader (keys %{$self->{'headers'}}) {
    if (lc($potentialHeader) eq lc($headerName)) {
        $headerValues = $self->{'headers'}{$potentialHeader};
    }
  }
  return defined $headerValues->[0] ? $headerValues->[0] : '';
}

sub isSuccess {
  my $self = shift;
  my $statusCode = $self->getStatusCode();
  # treat status code as a string
  my $success = "$statusCode" =~ /^2\d\d/;
  return $success;
}

sub getStatusCode {
  my $self = shift;
  return $self->{'statusCode'} || 500;
}

sub getStatusReason {
  my $self = shift;
  return $self->{'statusReason'} || '';
}

sub getStatus {
  my $self = shift;
  my $status = sprintf('%s %s', $self->getStatusCode(), $self->getStatusReason());
  if ($status !~ /^\d\d\d/) {
    die("invalid status '$status'");
  }
  return $status;
}

1;
