package PlugNPay::ResponseLink;

use strict;
use CGI;
use URI::Escape;
use miscutils;
use PlugNPay::Util::MetaTag;
use JSON::XS;
use LWP::UserAgent;
use HTTP::Request;
use XML::Simple;
use PlugNPay::Logging::DataLog;
use PlugNPay::Util::Array qw(inArray);
use PlugNPay::ResponseLink::LocalProxy;
use PlugNPay::ResponseLink::LocalProxy::Request;

our $cachedServer;

# Usage:
#  my $rl = new PlugNPay::ResponseLink();
#  # then set values
#  $rl->setUsername($username);
#  $rl->setRequestURL($url);
#  $rl->setRequestContentType($contentType);
#  $rl->setRequestMode('PROXY'); # DIRECT is available for INTERNAL USE ONLY!!!
#  ...
#
#    or
#
#  my $rl = new PlugNPay::ResponseLink($username,$url,$querystringOrHashReference,$method,$responseAPIType,$requestContentType);
#
#
# Then:
#  $rl->doRequest();
#  my $responseContent = $rl->getResponseContent
#  my %responseAPIData = $rl->getResponseAPIData
#
#    or
#
#  $rl->addRequestHeader($headerName,$headerValue); #Optional
#  $rl->doAPIRequest();
#  my $responseContent = $rl->getResponseContent();
#  my %responseAPIData = $rl->getResponseAPIData();

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my ($username,$url,$data,$method,$responseAPIType,$requestContentType) = @_;

  # set information if it was passed
  $self->setUsername($username);
  $self->setRequestURL($url);
  $self->setRequestData($data);
  $self->setRequestMethod($method);
  $self->setResponseAPIType($responseAPIType);
  $self->setRequestContentType($requestContentType);

  $self->{'error'} = [];

  return $self;
}

# set the url to make the request to
sub setRequestURL {
  my $self = shift;
  my $url = shift;
  $self->{'url'} = $url;
}

sub getRequestURL {
  my $self = shift;
  return $self->{'url'};
}

# set the data to send to the url, either as a prebuilt querystring or as a hash reference
sub setRequestData {
  my $self = shift;
  my $data = shift;

  # if $data is a hash reference, build the query string from it
  if (ref($data) eq 'HASH') {
    if ($self->getRequestContentType() eq 'application/json') {
      eval {
        $self->{'data'} = encode_json($data);
      };

      if ($@) {
        $self->{'data'} = $data;
      }
    } elsif ($self->getRequestContentType() =~/application\/xml|text\/xml/i) {
      my $xmlBuilder = XML::Simple->new(KeepRoot => 0, XMLDecl => 1, NoAttr => 1, ForceArray => qr/_list$/);
      my $xml = $xmlBuilder->XMLout($data,KeyAttr => {});
      $self->{'data'} = $xml;
    } else {
      my %dataHash = %{$data};
      $self->{'data'} = join('&',map {
        $_ .= '=' . URI::Escape::uri_escape($dataHash{$_});
      } sort keys %dataHash);
    }
  } # otherwise if $data is not a reference, it is supposed to be a premade query string
  elsif (!ref($data)) {
    $self->{'data'} = $data;
  }
}

sub setRequestContentType {
  my $self = shift;
  my $requestContentType = shift;
  $self->{'requestContentType'} = $requestContentType;
}

sub getRequestContentType {
  my $self = shift;
  return $self->{'requestContentType'};
}


sub getRequestData {
  my $self = shift;
  return $self->{'data'};
}

# set the username making the request
sub setUsername {
  my $self = shift;
  my $username = lc shift;
  $username =~ s/[^a-z0-9_]//;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return $self->{'username'};
}

# set the method of the request (POST or GET, default to POST)
sub setRequestMethod {
  my $self = shift;
  my $method = shift;
  $method =~ s/^(POST|GET|PATCH|PUT|DELETE|OPTIONS)$/$1/;

  # post by default;
  if ($method eq '') {
    $method = 'POST';
  }

  $self->{'method'} = $method;
}

sub getRequestMethod {
  my $self = shift;
  return $self->{'method'} || 'POST';
}

# Only use DIRECT mode for INTERNAL connections or connections to Processors or Partners
# to avoid going through the successlink proxy.
# It's available so sensitive data won't get logged in the successlink server.
sub setRequestMode {
  my $self = shift;
  my $mode = uc shift;
  $mode =~ s/^(PROXY|DIRECT)$/$1/;

  # proxy by default
  if ($mode eq '') {
    $mode = 'PROXY';
  }

  $self->{'mode'} = $mode;
}

sub setInsecure {
  my $self = shift;
  $self->{'insecure'} = 1;
}

sub unsetInsecure {
  my $self = shift;
  $self->{'insecure'} = undef;
}

sub getRequestMode {
  my $self = shift;

  if ($self->{'mode'} eq '') {
    $self->{'mode'} = 'PROXY';
  }

  if ($ENV{'DEVELOPMENT'} eq 'TRUE') {
    $self->{'mode'} = 'DIRECT';
  } 

  return $self->{'mode'};
}

sub setRequestTimeout {
  my $self = shift;
  my $timeout = shift;
  $timeout =~ s/[^\d]//g;
  $self->{'timeout'} = $timeout;
}

sub getRequestTimeout {
  my $self = shift;
  return ($self->{'timeout'} || 30) + 0;
}

sub addHeader {
  my $self = shift;
  my $header = shift;
  my $value = shift;

  $self->{'headers'}{$header} = $value;
}

sub getHeaders {
  my $self = shift;
  return $self->{'headers'};
}

sub addRequestHeader {
  my $self = shift;
  my $header = lc(shift);
  my $value = shift;
  if ($header eq 'content-type') {
    $self->setRequestContentType($value);
  } else {
    push @{$self->{'request_headers'}}, {'name' => $header, 'value' => $value};
  }
}

sub getRequestHeaders {
  my $self = shift;
  return $self->{'request_headers'};
}

sub setRequestHeaders {
  my $self = shift;
  my $headerData = shift;

  if (ref($headerData) eq 'HASH') {
    foreach my $header ( keys %{$headerData}){
      $self->addRequestHeader($header,$headerData->{$header});
    }
  } elsif (ref($headerData) eq 'ARRAY') {
    foreach my $KVPair (@{$headerData}){
      $self->addRequestHeader($KVPair->{'name'},$KVPair->{'value'});
    }
  }
}

sub _setRequestFailed {
  my $self = shift;
  my $timedOut = shift;
  $self->{'timedOut'} = $timedOut;
}

sub requestFailed {
  my $self = shift;
  return ($self->{'timedOut'} ? 1 : 0);
}

sub setAPIMethod {
  my $self = shift;
  my $method = shift;
  $method =~ s/^(POST|GET|PUT|DELETE|OPTIONS)$/$1/;
  if ($method eq '' || !defined $method) {
    $method = 'POST';
  }

  $self->{'api_method'} = $method;
}

sub getAPIMethod {
  my $self = shift;
  return $self->{'api_method'} || 'POST';
}

# do the request
sub doRequest {
  my $self = shift;

  if ($self->getRequestMode() eq 'PROXY') {
    $self->doAPIRequest();
  } else {
    $self->doDirectRequest();
  }
}

sub doAPIRequest {
  my $self = shift;
  my $headerArray = $self->getRequestHeaders();

  my $data = {
      method => $self->getRequestMethod(),
      url => $self->getRequestURL(),
      content => $self->getRequestData(),
      headers => $headerArray,
      contentType => $self->getRequestContentType(),
      username => $self->getUsername()
  };

  my $JSON = JSON::XS->new->utf8->encode($data);

  my $method = $self->getAPIMethod();
  my $url = $self->getProxyServer();

  my $request = new PlugNPay::ResponseLink::LocalProxy::Request();
  $request->setMethod($method);
  $request->setUrl($url);
  $request->setContent($JSON);
  $request->addHeader('accept','application/json');

  my $localProxy = new PlugNPay::ResponseLink::LocalProxy();
  my $response = $localProxy->do($request);
  $self->handleResponse($response);
}

sub doDirectRequest {
  my $self = shift;

  if (!defined $self->{'url'} || $self->{'url'} eq '') {
    push(@{$self->{'error'}}, 'URL is null.');
  }

  if (inArray($self->{'method'},['post','put','delete']) && (!defined $self->{'data'} || $self->{'data'} eq '')) {
    push(@{$self->{'error'}}, 'Data is null.');
  }

  my $method = $self->getRequestMethod();
  my $url = $self->getRequestURL();
  my $data = $self->getRequestData();

  $self->_doRequest({
    method => $method,
    url => $url,
    data => $data
  });
}

sub _doRequest {
  my $self = shift;
  my $requestInfo = shift;

  my $method = lc $requestInfo->{'method'};
  my $url = $requestInfo->{'url'};
  my $data = $requestInfo->{'data'};
  my $contentType = ($self->getRequestContentType() ? $self->getRequestContentType() : 'application/x-www-form-urlencoded');
  # both these sets of headers get combined in the order of headers then request headers
  my $headers = $self->getHeaders();
  my $requestHeaders = $self->getRequestHeaders();

  if ($method eq 'get' && $data ne '') {
      $url .= '?' . $data;
  }

  my $request = new PlugNPay::ResponseLink::LocalProxy::Request();
  $request->setMethod($method);
  $request->setUrl($url);
  $request->setTimeoutSeconds($self->getRequestTimeout());
  if ($method ne 'get') {
    $request->setContent($data);
    $request->setContentType($contentType);
  }

  if (defined $headers && ref($headers) eq 'HASH') {
    foreach my $header (keys %{$headers}) {
      $request->addHeader($header,$headers->{$header});
    }
  }

  if (defined $requestHeaders && ref($requestHeaders) eq 'HASH') {
    foreach my $header (keys %{$requestHeaders}) {
      $request->addHeader($header,$requestHeaders->{$header});
    }
  }

  if ($self->{'insecure'}) {
    $request->setInsecure();
  }

  my $localProxy = new PlugNPay::ResponseLink::LocalProxy();
  my $debugStart = Time::HiRes::time();
  my $response = $localProxy->do($request);
  my $debugEnd = Time::HiRes::time();

  if ($ENV{'DEBUG_RESPONSELINK_DURATION'} eq 'TRUE') {
    my $duration = $debugEnd - $debugStart;
    print STDERR "RESPONSELINK: url: $url, duration: $duration seconds\n";
  }

  $self->handleResponse($response);
}

sub handleResponse {
  my $self = shift;
  my $response = shift;

  if ($self->getRequestMode eq 'DIRECT') {
    $self->setResponseContent($response->getContent());
    $self->_setRequestFailed(!$response->isSuccess());
    my @headerNames = $response->getHeaderNames();
    my %headers;
    foreach my $headerName (@headerNames) {
      $headers{$headerName} = $response->getHeader($headerName);
    }
    my $statusCode = $response->getStatusCode();
    $self->{'statusCode'} = $statusCode;
    my $reason = $response->getStatusReason();
    $headers{'_HTTP_STATUS'} ||= $statusCode;
    $headers{'_HTTP_REASON'} ||= $reason;
    $self->setResponseHeaders(\%headers);
    $self->parseResponse();
  } else {
    my $proxyContent = $response->getContent();
    my $proxyData = decode_json($proxyContent);
    my $content = $proxyData->{'content'}{'data'}{'content'};
    my $headers = $proxyData->{'content'}{'data'}{'headers'};
    $self->{'statusCode'} = $headers->{'_HTTP_CODE'};
    $self->setResponseContent($content);
    $self->setResponseHeaders($headers);
  }
}

# used to manually set the html to parse
sub setResponseContent {
  my $self = shift;
  $self->{'responseContent'} = shift;
  $self->{'responseContent'} =~ s/\n+$/\n/;  # get rid of any extra carriage returns at the end of the content
  $self->{'originalResponseContent'} = $self->{'responseContent'};
}

# used to manually set the headers to parse
sub setResponseHeaders {
  my $self = shift;
  $self->{'responseHeaders'} = shift;
}

# used to pull out response api data from the response stored in the object
# removes the response api data from the response in the process so it can be passed on to the client
sub parseResponse {
  my $self = shift;

  if ($self->{'responseAPIType'} eq 'meta') {
    # create a metatag object to parse out the metatag for the api
    my $mt = new PlugNPay::Util::MetaTag();
    $mt->loadDocument($self->{'responseContent'});
    my $tag = $mt->metaTagByName('gateway-response-api');

    if (defined $tag) {
      $self->{'responseAPIData'} = $tag->{'parameters'};
      $self->{'responseContent'} = join('',split($tag->{'raw'},$self->{'responseContent'}));
    }
  } elsif ($self->{'responseAPIType'} eq 'querystring') {
    my $responseContent = $self->{'responseContent'};
    $responseContent =~ s/^\n+(.*)/$1/;
    my %responseHash = CGI->new($responseContent)->Vars();
    $self->{'responseAPIData'} = \%responseHash;
  } elsif ($self->{'responseAPIType'} eq 'json') {
    my $responseContent = $self->{'responseContent'};
    eval {
      $self->{'responseAPIData'} = JSON::XS->new->utf8->decode($responseContent);
    };
  } elsif ($self->{'responseAPIType'} eq 'xml') {
    my $responseContent = $self->{'responseContent'};
    eval {
      $self->{'responseAPIData'} = XML::Simple->new->XMLin($responseContent);
    };
  }
}

# sets the method used to look for the response api data
sub setResponseAPIType {
  my $self = shift;
  my $type = shift;

  if (defined $type && $type ne '') {
    $type = lc $type;
    $type =~ s/^.*(none|meta|header|json|querystring|xml).*$/$1/;
  } else {
    # assume default type of none
    $type = 'none';
  }

  $self->{'responseAPIType'} = $type;
}

# gets a hash of the data in the response api
sub getResponseAPIData {
  my $self = shift;

  if (exists $self->{'responseAPIData'}) {
    if (wantarray()) {
      return %{$self->{'responseAPIData'}};
    }

    my %copy = %{$self->{'responseAPIData'}};

    return \%copy;
  } else {
    my %emptyHash;

    if (wantarray()) {
      return %emptyHash;
    }

    return \%emptyHash;
  }
}

# returns the response content
sub getResponseContent {
  my $self = shift;
  return $self->{'responseContent'};
}

sub getStatusCode {
  my $self = shift;
  return $self->{'statusCode'};
}

# returns the response headers
sub getResponseHeaders {
  my $self = shift;
  my $responseHeaders = $self->{'responseHeaders'} || {};
  return %{$responseHeaders};
}

# get errors
sub getErrors {
  my $self = shift;
  return @{$self->{'error'}};
}

sub getProxyServer {
  my $self = shift;

  if (!$cachedServer) {
    my $env = $ENV{'PNP_PROXY_SERVER'};
    $cachedServer = $env || PlugNPay::AWS::ParameterStore::getParameter('/PNP_WEB_PROXY/SERVER',1);
  }

  return $cachedServer;
}

1;
