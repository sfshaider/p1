package PlugNPay::API::REST;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::API::REST::Format;
use PlugNPay::API::REST::ResponseCode;
use PlugNPay::CGI;
use Apache2::RequestUtil;
use Apache2::RequestRec ();
use PlugNPay::Logging::DataLog;
use PlugNPay::API::REST::Context;
use PlugNPay::Util::StackTrace;
use PlugNPay::API::REST::Format;
use PlugNPay::Util::Memcached;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  $self->{'memcached'} = new PlugNPay::Util::Memcached('API-REST');

  my $root = shift;
  if (defined $root) {
    $self->setRoot($root);
  } else {
    die('API Root must be defined in initializer!');
  }

  my $options = shift;
  if (defined $options && ref($options) eq 'HASH') {
    $self->setContext($options->{'context'}) if defined $options->{'context'};
    $self->setMockRequest($options->{'mockRequest'}) if defined $options->{'mockRequest'};
  }


  $self->_init();

  if ($ENV{'DEVELOPMENT'} eq 'TRUE') {
    my $logger = new PlugNPay::Logging::DataLog({ collection => 'rest-development' });
    $logger->log($self);
  }

  return $self;
}

# sets a mock request for testing.  See PlugNPay::API::MockRequest
# Only allows it to be set if $ENV{'DEVELOPMENT'} = 'TRUE'!!!!
sub setMockRequest {
  my $self = shift;
  my $mockRequest = shift;
  if ($ENV{'DEVELOPMENT'} eq 'TRUE') {
    $self->{'mockRequest'} = $mockRequest;
  }
}

sub setAsKeyAuthentication {
  my $self = shift;
  $self->{'authenticationType'} = 'apiKey';
}

sub setAsSessionAuthentication {
  my $self = shift;
  $self->{'authenticationType'} = 'session';
}

sub getAuthenticationType {
  my $self = shift;
  return $self->{'authenticationType'};
}

sub setError {
  my $self = shift;
  my $error = shift;
  $self->{'error'} = $error;
}

sub getError {
  my $self = shift;
  return $self->{'error'};
}

sub hasError {
  my $self = shift;
  return (defined $self->{'error'} ? 1 : 0);
}

sub setResponseCode {
  my $self = shift;
  my $code = shift;
  $self->{'code'} = $code;
}

sub getResponseCode {
  my $self = shift;
  return $self->{'code'};
}

sub _init {
  my $self = shift;

  my $r;
  eval {
    $r = $self->{'mockRequest'} || Apache2::RequestUtil->request;
  };

  if ($r) {
    my $resource = $r->the_request;
    $resource =~ s/.*? (.*?) .*/$1/;
    $resource =~ s/\/[\/]*/\//g;
    $resource = substr($resource,length($self->getRoot()));
    my @resourceDataArray = split('\/',$resource);

    # remove the leading empty string if the resource starts with /.
    if ($resource =~ /^\//) {
      shift @resourceDataArray;
    }

    my $resourcePath = $self->_parseResourcePath(\@resourceDataArray);
    my $resourceData = $self->_parseResourceData(\@resourceDataArray);
    my $resourceDataArray = $self->_parseResourceDataArray(\@resourceDataArray);
    my $resourceOptions = $self->_parseResourceOptions(\@resourceDataArray);
    my $resourceOptionsArray = $self->_parseResourceOptionsArray(\@resourceDataArray);
    my $action = $self->_parseAction($r->method);

    my $aprHeaders = $r->headers_in;
    my %headers = %{\%$aprHeaders};

    my $cgi = new PlugNPay::CGI();
    my $data;
    eval { # if this dies, whatever.  $data stays blank if $r->mockContent is undefined. that's cool.
      $data = $cgi->getRaw() || $r->mockContent;
    };
    $self->setResourcePath($resourcePath);
    $self->setResourceData($resourceData);
    $self->setResourceDataArray($resourceDataArray);
    $self->setResourceOptions($resourceOptions);
    $self->setResourceOptionsArray($resourceOptionsArray);
    $self->setAction($action);
    $self->setRequestHeaders(\%headers);
    $self->setRequestContent($data);
  }
}

my $actions = {
  'post'    => 'create',
  'put'     => 'update',
  'get'     => 'read',
  'delete'  => 'delete',
  'options' => 'options'
};


sub _parseAction {
  my $self = shift;
  my $method = lc shift;

  return $actions->{$method};
}

sub _parseMethod {
  my $self = shift;
  my $action = lc shift;
  my %rActions = reverse %{$actions};

  return $rActions{$action};
}

sub _parseResourcePath {
  my $self = shift;
  my $arrayRef = shift;

  my @resourcePath;
  foreach my $key (@{$arrayRef}) {
    next if $key eq '';
    last if $key eq '!query';
    last if substr($key,0,1) eq '!';
    push @resourcePath,$key if $key !~ /^:/;
  }

  return \@resourcePath;
}

# Any path element preceded with a : is a data value for the previous path element,
# (with the exception of option elements which are marked by !)
# Example:
# /api/merchant/:chrisinc/coa/
# will create a key of 'merchant' with a value of 'chrisinc'
sub _parseResourceData {
  my $self = shift;
  my $arrayRef = shift;

  my $resourceData;
  my $lastKey;
  foreach my $key (@{$arrayRef}) {
    next if $key eq '';
    last if substr($key,0,1) eq '!';
    if (substr($key,0,1) eq ':') {  # if the component is a value
      if (not defined $resourceData->{$lastKey}) {
        $resourceData->{$lastKey} = substr($key,1);
      }
    } else {
      $resourceData->{$key} = undef;
      $lastKey = $key;
    }
  }

  return $resourceData;
}

sub _parseResourceDataArray {
  my $self = shift;
  my $arrayRef = shift;

  my $resourceData = {};
  my $currentKey;
  foreach my $key (@$arrayRef) {
    next if $key eq '';
    last if substr($key, 0, 1) eq '!';
    if (substr($key, 0, 1) eq ':') {
      push @{$resourceData->{$currentKey}}, substr($key, 1);
    } else {
      $resourceData->{$key} = [];
      $currentKey = $key;
    }
  }

  return $resourceData;
}

# The ! character signals the start of a chain of options.
# Example:
# /api/risktrak/summary/!pagelength/:100/query/:'text1'/:'text2'
# will create a key value pair of pagelength => 100 and query => [text1, text2]
# note that single elements are not in an array where as multiple elements are.

sub _parseResourceOptions {
  my $self = shift;
  my $arrayRef = shift;

  my %resourceOptions;

  my $isOption = 0; # starts as false
  my $lastKey = '';
  foreach my $key (@{$arrayRef}) {

    if (!$isOption && substr($key, 0, 1) eq '!') {   # if the key is an option
      $isOption = 1;             # set it to true
      next;
    }

    if ($isOption) {
      if (substr($key, 0, 1) eq ':') {      # if previous key is an option...
        if ($resourceOptions{$lastKey} eq undef) {      # if the hash is empty, insert the value
          $resourceOptions{$lastKey} = substr($key, 1);
        } else {            # if it's not empty...
          if (ref($resourceOptions{$lastKey}) eq 'ARRAY') {   # if it's an array, push value to array
            push @{$resourceOptions{$lastKey}}, substr($key, 1);
          } else {                # if it's not an array, make an array
            my $oldKey = $resourceOptions{$lastKey};
            $resourceOptions{$lastKey} = [$oldKey, substr($key, 1)];
          }
        }
      } else {
        my $filter = $key;
        $filter =~ s/^!//g;
        $lastKey = $filter;        # save the key for later
        $resourceOptions{$lastKey} = undef;      # initialize hash for the given key
      }
    }
  }

  return \%resourceOptions;
}

# This does the same as the previous function except now single elements are also in an array
# Example:
# /api/risktrak/summary/!pagelength/:100/query/:'text1'/:'text2'
# will create a key value pair of pagelength => [100] and query => [text1, text2]

sub _parseResourceOptionsArray {
  my $self = shift;
  my $arrayRef = shift;

  my %resourceOptions;

  my $isOption = 0; # starts as false
  my $lastKey = '';
  foreach my $key (@{$arrayRef}) {

    if (!$isOption && substr($key, 0, 1) eq '!') {       # if the key is an option
      $isOption = 1;             # set it to true
      next;
    }

    if ($isOption) {
      if (substr($key, 0, 1) eq ':') {      # if previous key is an option...
        push @{$resourceOptions{$lastKey}}, substr($key, 1);
      } else {
        $lastKey = $key;          # save the key for later
        $resourceOptions{$lastKey} = [];      # initialize hash for the given key
      }
    }
  }

  return \%resourceOptions;
}

sub setRoot {
  my $self = shift;
  my $root = shift;

  $self->{'root'} = $root;
}

sub getRoot {
  my $self = shift;
  return $self->{'root'};
}

sub setContext {
  my $self = shift;
  my $context = shift;
  $self->{'context'} = $context;
}

sub getContext {
  my $self = shift;
  return $self->{'context'} || 'public';
}

sub getResourceOptionsArray {
  my $self = shift;
  return $self->{'resourceOptionsArray'};
}

sub setResourceOptionsArray {
  my $self = shift;
  my $resourceOptionsArrayRef = shift;
  $self->{'resourceOptionsArray'} = $resourceOptionsArrayRef;
}

sub getResourceOptions {
  my $self = shift;
  return $self->{'resourceOptions'};
}

sub setResourceOptions {
  my $self = shift;
  my $resourceOptionsRef = shift;
  $self->{'resourceOptions'} = $resourceOptionsRef;
}

sub getResourceData {
  my $self = shift;
  return $self->{'resourceData'};
}

sub setResourceData {
  my $self = shift;
  my $resourceDataRef = shift;
  $self->{'resourceData'} = $resourceDataRef;
}

sub getResourceDataArray {
  my $self = shift;
  return $self->{'resourceDataArray'};
}

sub setResourceDataArray {
  my $self = shift;
  my $resourceDataRef = shift;
  $self->{'resourceDataArray'} = $resourceDataRef;
}

sub getResourcePath {
  my $self = shift;
  return $self->{'resourcePath'};
}

sub setResourcePath {
  my $self = shift;
  my $pathArrayRef = shift;
  $self->{'resourcePath'} = $pathArrayRef;
}

sub setAction {
  my $self = shift;
  my $action = shift;
  $self->{'action'} = $action;
}

sub getAction {
  my $self = shift;
  return $self->{'action'};
}

sub setRequestHeaders {
  my $self = shift;
  my $headersHashRef = shift;
  my %headers = map { lc $_ => $headersHashRef->{$_} } keys %{$headersHashRef};
  $self->{'headers'} = \%headers;
}

sub getRequestHeaders {
  my $self = shift;
  return $self->{'headers'};
}

sub getRequestHeader {
  my $self = shift;
  my $headerName = lc shift;
  return $self->getRequestHeaders()->{$headerName};
}

sub setRequestGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'requestGatewayAccount'} = $gatewayAccount;
}

sub getRequestGatewayAccount {
  my $self = shift;
  if (defined $self->{'requestGatewayAccount'}) {
    return $self->{'requestGatewayAccount'};
  } else {
    return $self->getRequestHeader('X-Gateway-Account');
  }
}

sub getRequestAPIKey {
  my $self = shift;
  return $self->getRequestHeader('X-Gateway-API-Key');
}

sub getRequestAPIKeyName {
  my $self = shift;
  return $self->getRequestHeader('X-Gateway-API-Key-Name');
}

sub getRequestContentType {
  my $self = shift;
  my $contentType = $self->getRequestHeader('content-type');
  $contentType =~ s/;.*//;
  return $contentType;
}

sub getResponseContentType {
  my $self = shift;
  my $acceptHeader = $self->getRequestHeader('accept');
  $acceptHeader =~ s/,.*//;
  return ($acceptHeader eq 'application/xml' || $acceptHeader eq 'text/xml') ? $acceptHeader : 'application/json';
}

sub setRequestContent {
  my $self = shift;
  my $content = shift;
  $self->{'requestContent'} = $content;
}

sub getRequestContent {
  my $self = shift;
  return $self->{'requestContent'};
}

#Access-Control-Allow-Origin
sub setResponseACAOHeader {
  my $self = shift;
  $self->{'acaoHeader'} = shift;
}

sub getResponseACAOHeader {
  my $self = shift;
  return $self->{'acaoHeader'};
}

sub _respond {
  my $self = shift;
  my $code = shift;
  my $contentData = shift;
  my $options = shift;

  my $allowHeaders = 'Content-type,X-Gateway-Session';
  my $allowedMethods = 'post,put,delete,get,options';

  my $error =  $contentData->{'error'} || $self->getError();
  my %outputData;
  $outputData{'content'} = $contentData->{'content'} if defined $contentData->{'content'};
  $outputData{'alerts'} = $contentData->{'warning'} if defined $contentData->{'warning'};
  $outputData{'warnings'} = $self->getWarnings() if defined $self->getWarnings();
  $outputData{'error'}   = $error if defined $error;
  $outputData{'id'} = $contentData->{'id'} if defined $contentData->{'id'};

  my $outputLength = length($self->formatOutputData(\%outputData));
  my $contentType = $self->getResponseContentType();

  my $output = '';
  if (!$options->{'skipHeaders'}) {
    $output .= 'Content-type: ' . $contentType . "\n";
    $output .= 'Status: ' . $code . "\n";
    $output .= 'Access-Control-Allow-Origin: ' . $self->{'acaoHeader'} . "\n" if defined $self->{'acaoHeader'};
    $output .= 'Access-Control-Allow-Headers: ' . $allowHeaders . "\n" if defined $self->{'acaoHeader'};
    $output .= 'Access-Control-Allow-Methods: ' . $allowedMethods . "\n" if defined $allowedMethods;
    $output .= 'Content-Length: ' . $outputLength . "\n" if defined $outputLength;
    $output .= "\n";
  }
  $output .= $self->formatOutputData(\%outputData);

  return $output;
}

sub parseRequestContent {
  my $self = shift;
  my $schemaName = shift;
  my $responderName = shift || '';

  my $content = $self->getRequestContent();
  my $enforces = $self->willEnforceSchema();

  my $format = new PlugNPay::API::REST::Format();
  $format->setSchemaName($schemaName);

  if ($self->getAction() eq 'create') {
    $format->setSchemaMode('CREATE');
  } elsif ($self->getAction() eq 'update') {
    $format->setSchemaMode('UPDATE');
  } elsif ($self->getAction() eq 'options') {
    $format->setSchemaMode('OPTIONS');
  } elsif ($self->getAction() eq 'delete') {
    $format->setSchemaMode('DELETE');
  } else {
    $format->setSchemaMode('READ');
  }

  unless ($format->getSchemaMode() =~ /READ/) {
    my $contentType = $self->getRequestContentType();
    my $hasContent = 0;

    if ($contentType eq 'application/json') {
      $format->setJSON($content);
      $hasContent = 1;
    } elsif ($contentType eq 'application/xml') {
      $format->setXML($content);
      $hasContent = 1;
    }

    my $formatValidated = 0;
    eval {
       my $formatSettings = { 'username'      => $self->getRequestGatewayAccount(),
                              'enforced'      => $enforces,
                              'uri'           => $self->getRoot . '/' . join('/',@{$self->getResourcePath()}),
                              'responderName' => $responderName };
       $format->setSettings($formatSettings);
       $formatValidated = $format->validateData();
    };

    if ($@) {
      eval { # log to error log if we can
        my $logger = new PlugNPay::Logging::DataLog({'collection' => 'rest_error'});
        $logger->log({
          'package' => 'PlugNPay::API::REST',
          'function' => 'parseRequestContent',
          'status' => 'error',
          'errorMsg' => 'Format Failure: "' . $@ . '"',
        }, {
          stackTraceEnabled => 1
        });
      };
      $format->setError('Request format validation error.');
    }

    $self->setWarnings($format->getWarnings());

    #If error AND enforces schema constraints
    if ($hasContent && ($format->hasError() || !$formatValidated) && $enforces) {
      $self->setError($format->getError()); # copy any error from format to this object
      $self->setResponseCode('422');
    }
  }
  return $format->getData();
}

sub formatOutputData {
  my $self = shift;
  my $contentData = shift;

  my $format = new PlugNPay::API::REST::Format();
  $format->setData($contentData);

  my $contentType = $self->getResponseContentType();

  my $formattedData = '';

  if ($contentType eq 'application/xml') {
    $formattedData = $format->getXML();
  } else {
    $formattedData = $format->getJSON();
  }

  return $formattedData;
}

sub getResponder {
  my $self = shift;

  # short circuit if responder if already created
  if ($self->{'responder'}) {
    return $self->{'responder'};
  }

  $self->{'responder'} = $self->_loadResponder();

  my $responder = $self->{'responder'};		# makes the following code easier to read

  if (ref($responder)) {
    my $inputData = $self->parseRequestContent($responder->getSchemaName(), ref($responder));
    if ($inputData->{'requestOptions'}) {
      $responder->setRequestOptions($inputData->{'requestOptions'});
      delete $inputData->{'requestOptions'};
    }

    $responder->setAction($self->getAction());
    $responder->setContext($self->getContext());
    $responder->setResourceData($self->getResourceData());
    $responder->setResourceDataArray($self->getResourceDataArray());
    $responder->setResourcePath($self->getResourcePath());
    $responder->setResourceOptions($self->getResourceOptions());
    $responder->setResourceOptionsArray($self->getResourceOptionsArray());
    $responder->setInputData($inputData);
    $responder->setGatewayAccount($self->getRequestGatewayAccount());
  }

  return $responder;
}

sub respond {
  my $self = shift;
  my $options = shift;

  my $responder = $self->getResponder();

  my $_respondOptions = {
    skipHeaders => $options->{'skipHeaders'}
  };

  if (ref($responder)) {
    my $code;
    my $output;

    if (!$self->hasError()) {
      eval {
        $output = $responder->getOutputData();
        $code = $responder->getResponseCode();
      };

      my $responderError = $@;
      if ($responderError) {
        my $logger = new PlugNPay::Logging::DataLog({'collection' => 'rest_error'});
        $logger->log({
          'package' => 'PlugNPay::API::REST',
          'function' => 'respond',
          'status' => 'error',
          'errorMsg' => ref($responder) . ' Failure: ' . $responderError
        }, {
          stackTraceEnabled => 1
        });
        $self->setResponseCode(500);
      }

      $self->setError($responderError ? 'An internal error occurred.' : undef);

      if ($self->hasError()) {
        my $logger = new PlugNPay::Logging::DataLog({'collection' => 'rest_error'});
        $logger->log({
          'package' => 'PlugNPay::API::REST',
          'function' => 'respond',
          'status' => 'error',
          'errorMsg' => 'REST Error: [' . ref($responder) . '] ' . ($responderError || $self->getError())
        }, {
          stackTraceEnabled => 1
        });
      }
    } else {
      $code = $self->getResponseCode();
    }
    my $responseCodes = new PlugNPay::API::REST::ResponseCode();
    $responseCodes->setCode($code);
    my $responseCode = $code . ' ' . $responseCodes->getMessage();
    if ($self->getError() || substr($responseCode,0,1) eq '5') {
      $self->_respond($responseCode,{content => $output},$_respondOptions);
    } else {
      my $headerID = $self->getRequestHeader('Request-ID');
      $self->_respond($responseCode,{content => $output, id => $headerID},$_respondOptions);
    }
  } else {
    my $code = 501; # if we get a request for a url that does not have a responder,
                    # respond with 501 not implemented.
    my $responseCodes = new PlugNPay::API::REST::ResponseCode();
    $responseCodes->setCode($code);
    my $responseCode = $code . ' ' . $responseCodes->getMessage();
    $self->_respond($responseCode,{},$_respondOptions);
  }
}

sub _loadResponder {
  my $self = shift;

  my $root = $self->getRoot();
  my $context = $self->getContext();
  my $contextObj = new PlugNPay::API::REST::Context();
  $contextObj->setName($context);
  $contextObj->load();
  my $contextID = $contextObj->getID();
  my $resource = '/' . join('/',@{$self->getResourcePath()});
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'rest_error'});

  my $package;
  my $responderID;

  if (substr($resource,0,5) eq '/doc/') {
    $package = "PlugNPay::API::REST::Responder::Doc";
    $self->setResourcePath(substr($resource,4));
  } else {
    my $cacheKey = "loadResponder,$root,$contextID,$resource";

    my $data = $self->{'memcached'}->get($cacheKey);

    if ($data) {
      $package = $data->{'package'};
      $responderID = $data->{'api_responder_id'};
    } else {
      my $query = q/
        SELECT ar.package as package, ar.id as api_responder_id
          FROM api_responder ar, api_url au
        WHERE ar.id = au.responder_id
          AND au.root = ?
          AND au.context_id = ?
          AND au.resource = ?
      /;

      my @values = ($root,$contextID,$resource);

      my $dbs = new PlugNPay::DBConnection();
      my $sth = $dbs->prepare('pnpmisc',$query);

      $sth->execute(@values);
      my $results = $sth->fetchall_arrayref({});
      if ($results && $results->[0]) {
        $self->{'memcached'}->set($cacheKey,$results->[0], 300);
        $package = $results->[0]{'package'};
        $responderID = $results->[0]{'api_responder_id'};
      }
    }
  }


  my $responder;
  if ($package =~ /^PlugNPay/) {
    eval "require $package;";
    if ($@) {
      $logger->log({'package' => $package, 'message' => 'Package require error in REST: ' . $@});
    }

    eval {
      $responder = $package->new();
      $responder->setID($responderID);
      $responder->setAPIKeyName($self->getRequestAPIKeyName());
      $responder->setContextID($contextID);
      $responder->setAuthenticationType($self->getAuthenticationType());
    };

    if ($@) {
      $logger->log({'package' => $package, 'message' => 'Responder instance creation error: ' . $@});
    }

    if (ref($responder)) {
      return $responder;
    }
  }
}

sub allowsSessionAuth {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                           SELECT allows_session_auth
                           FROM api_url
                           WHERE root = ? AND context = ? AND resource = ?
                           /);
  $sth->execute($self->getRoot(),$self->getContext(), '/' . join('/',@{$self->getResourcePath()})) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  return $rows->[0]{'allows_session_auth'};
}

sub getSessionKey {
 my $self = shift;
  return $self->getRequestHeader('X-Gateway-Session');
}

sub setWarnings {
  my $self = shift;
  my $warnings = shift;
  $self->{'warnings'} = $warnings;
}

sub getWarnings {
  my $self = shift;
  return $self->{'warnings'};
}

sub willEnforceSchema {
  my $self = shift;
  my $root = $self->getRoot();
  my $context = $self->getContext();
  my $resource = '/' . join('/',@{$self->getResourcePath()});
  my $logger = new PlugNPay::Logging::DataLog({'collection' => 'rest_error'});

  my $cacheKey = "willEnforceSchema,$root,$context,$resource";

  my $data = $self->{'memcached'}->get($cacheKey);

  my $enforcesSchema = 0;

  if ($data) {
    $enforcesSchema = $data->{'enforce'};
  } else {
    my $query = q/
      SELECT ar.enforce_schema as enforce
      FROM api_responder ar, api_url au
      WHERE ar.id = au.responder_id
      AND au.root = ?
      AND au.context = ?
      AND au.resource = ?
    /;

    my @values = ($root, $context, $resource);
    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',$query);
    $sth->execute(@values) or $logger->log({'root' => $root, 'context' => $context, 'resource' => $resource, 'message' => 'Data load error in REST: ' . $DBI::errstr});
    my $rows = $sth->fetchall_arrayref({});

    if ($rows && $rows->[0]) {
      $self->{'memcached'}->set($cacheKey,$rows->[0],300);
      $enforcesSchema = $rows->[0]{'enforce'};
    }
  }

  return $enforcesSchema;
}

1;
