package PlugNPay::AWS::S3::Object::ObjectProxy;

use strict;
use JSON::XS;
use XML::Simple;
use MIME::Base64;
use Types::Serialiser;
use Encode qw(encode decode);
use PlugNPay::Die;
use PlugNPay::Util::Status;
use PlugNPay::Logging::DataLog;
use PlugNPay::AWS::ParameterStore qw(getParameter);
use PlugNPay::ResponseLink::Microservice;
use PlugNPay::ConfigService;


our $__cachedHost;
our $TRUE;
our $FALSE;


sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  initBooleans();

  my $bucketName = shift;
  if ($bucketName) {
    $self->setBucketName($bucketName);
  }

  return $self;
}

sub initBooleans {
  if (!defined $TRUE) {
    my $json = new JSON::XS();
    $TRUE = Types::Serialiser::true;
    $FALSE = Types::Serialiser::false;
  }
}

sub getServiceHost {
   if (!$__cachedHost) {
    my $envServiceHost = $ENV{'PNP_S3_PROXY_SERVICE'};

    my $configServiceHost;
    if ($envServiceHost eq '') {
      my $configService = new PlugNPay::ConfigService();
      my $config = $configService->getConfig({
        apiVersion => 1,
        name => 'pay1',
        formatVersion => 1
      });

      $configServiceHost = $config->{'s3Service'}{'host'};
      if ($configServiceHost eq '') {
        die("Failed to load s3 proxy service host info from config service");
      }
    }
    $__cachedHost = $envServiceHost || $configServiceHost;
    $__cachedHost =~ s/\/+$//;
  } 

  return $__cachedHost;
}

sub setObjectName {
  my $self = shift;
  my $objectName = shift;
  $self->{'objectName'} = $objectName;
}

sub getObjectName {
  my $self = shift;
  return $self->{'objectName'};
}

sub setBucketName {
  my $self = shift;
  my $bucketName = shift;
  $self->{'bucketName'} = $bucketName;
}

sub getBucketName {
  my $self = shift;
  return $self->{'bucketName'};
}

sub setContentType {
  my $self = shift;
  my $contentType = shift;
  $self->{'contentType'} = $contentType;
}

sub getContentType {
  my $self = shift;
  return $self->{'contentType'};
}

sub setContent {
  my $self = shift;
  my $content = shift;
  $self->{'content'} = $content;
}

sub setEncType {
  my $self = shift;
  my $encType = shift;
  $self->{'encType'} = $encType;
}

sub getEncType {
  my $self = shift;
  return $self->{'encType'};
}

sub setEncKey {
  my $self = shift;
  my $encKey = shift;
  $self->{'encKey'} = $encKey;
}

sub getEncKey {
  my $self = shift;
  return $self->{'encKey'};
}

sub setAcl {
  my $self = shift;
  my $acl = shift;
  $self->{'acl'} = $acl;
}

# right now the acl can only be set upon Create
# it can not currently be read by the proxy
# this here for completeness/to match the setAcl
sub getAcl {
  my $self = shift;
  return $self->{'acl'};
}

sub getAutoFormattedContent {
  my $self = shift;

  my $content = $self->{'content'};
  my $contentType = $self->{'contentType'};

  if ($contentType && (ref($content) eq 'HASH' || ref($content) eq 'ARRAY')) {
    if (lc($contentType) =~ /json$/) {
      $content = encode_json($content);
    } elsif (lc($contentType) =~ /xml$/) {
      my $xmlBuilder = XML::Simple->new('KeepRoot' => 1,
                                        'XMLDecl' => 1,
                                        'NoAttr' => 1,
                                        'ForceArray' => qr/_list$/);
      $content = $xmlBuilder->XMLout($content, 'KeyAttr' => {});
    }
  }

  return $content;
}

sub getContent {
  my $self = shift;
  return $self->{'content'};
}

sub setExpireTime {
  my $self = shift;
  my $expireTime = shift; # in hours
  $self->{'expireTime'} = $expireTime * 60 * 60;
}

sub getExpireTime {
  my $self = shift;
  return $self->{'expireTime'} || $ENV{'AWS_PRESIGN_EXPIRE_TIME'} || 3600;
}

sub readObject {
  my $self = shift;

  # clear content and content type
  $self->setContent();
  $self->setContentType();

  my $bucketName = $self->{'bucketName'};
  my $objectName = $self->{'objectName'};

  if (!$bucketName || !$objectName) {
    die('Missing required data to create object.');
  }

  my $host = getServiceHost();
  my $url = sprintf('%s/v1/s3/%s/%s',$host,$bucketName,$objectName);

  my $response = $self->_doRequest({
    method => 'GET',
    url => $url
  });

  my $content = '';
  my $contentType = '';

  my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'aws_s3_object' });
  my %logMessageBase = (
      bucketName => $bucketName,
      objectName => $objectName
  );

  if ($response->{'error'}) {
    my $error = sprintf('Error response for %s/%s from s3 proxy, error: %s', $bucketName,$objectName, $response->{'error'});
    $logger->log({
      %logMessageBase,
      error => $error
    });
    die($error);
  } else {
    my $base64Content = $response->{'base64Content'};
    $contentType = $response->{'contentType'};


    eval {
      $content = decode_base64($base64Content);
      if ($contentType =~ /utf-8/i) {
        $content = decode('UTF-8',$content, Encode::FB_CROAK);
      }
    };
    
    if ($@) {
      my $error = sprintf('Error decoding base64 content for %s/%s, error: %s',$bucketName,$objectName,$@);
      $logger->log({
        %logMessageBase,
        'error'      => $error
      });
      die($error);
    }
  }

  $self->setContentType($content);
  $self->setContentType($contentType);

  if (wantarray) { # Since this was already returning array need to keep for compatibility
    return $content,$contentType;
  }

  return {'content' => $content, 'contentType' => $contentType};
}

sub createObject {
  my $self = shift;
  my $input = shift;

  my $requestSignedUrl = $input->{'requestSignedUrl'} ? 1 : 0;

  my $bucketName  = $self->{'bucketName'};
  my $objectName  = $self->{'objectName'};
  my $content     = $self->getAutoFormattedContent();
  my $contentType = $self->{'contentType'} || 'text/plain';
  my $encType     = $self->{'encType'};
  my $encKey      = $self->{'encKey'};
  my $acl         = $self->{'acl'};

  if (!$bucketName || !$objectName || !$content || !$contentType) {
    die('Missing required data to create object.');
  }

  my $status = new PlugNPay::Util::Status(1);

  my $host = getServiceHost();
  my $url = sprintf('%s/v1/s3/%s/%s',$host,$bucketName,$objectName);

  if ($contentType =~ /utf-8/i) {
    $content = encode('UTF-8',$content, Encode::FB_CROAK);
  }
  
  my $requestContent = {
    'bucketName'    => $bucketName,
    'objectName'    => $objectName,
    'base64Content' => encode_base64($content),
    'contentType'   => $contentType,
    'encType'       => $encType,
    'encKey'        => $encKey,
    'acl'           => $acl
  };

  if ($requestSignedUrl) {
    $requestContent->{'getPresignedUrl'} = $TRUE;
  };

  my $response = $self->_doRequest({
    method => 'PUT',
    url => $url,
    content => $requestContent
  });

  if ($response->{'error'}) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'aws_s3_object' });
    $logger->log({
      'bucketName' => $bucketName,
      'objectName' => $objectName,
      'error'      => $response->{'error'}
    });

    $status->setFalse();
    $status->setError($response->{'error'});
  }

  return $status;
}

sub copyObject {
  my $self = shift;
  my $input = shift;

  my $requestSignedUrl = $input->{'requestSignedUrl'} ? 1 : 0;
  
  my $fromObject = $self->{'objectName'};
  my $fromBucket = $self->{'bucketName'};
  my $toObject = $input->{'toObject'} || $fromObject;
  my $toBucket = $input->{'toBucket'} || $fromBucket; # you got a benz, i got a busket, give me a dollar

  my $status = new PlugNPay::Util::Status(1);

  my $host = getServiceHost();
  my $url = sprintf('%s/v1/s3/%s/%s',$host,$toBucket,$toObject);

  my $requestContent = {
    'copyFromBucket' => $fromBucket,
    'copyFromObject' => $fromObject
  };

  if ($requestSignedUrl) {
    $requestContent->{'getPresignedUrl'} = $TRUE;
  };

  my $response = $self->_doRequest({
    method => 'PUT',
    url => $url,
    content => $requestContent
  });

  if ($response->{'error'}) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'aws_s3_object' });
    $logger->log({
      'bucketName' => $fromBucket,
      'objectName' => $fromObject,
      'error'      => $response->{'error'}
    });

    $status->setFalse();
    $status->setError($response->{'error'});
  }

  return $status;
}

sub deleteObject {
  my $self = shift;

  my $objectName = $self->{'objectName'};
  my $bucketName = $self->{'bucketName'};

  if (!$bucketName || !$objectName) {
    die('Missing required data to delete object.');
  }

  my $status = new PlugNPay::Util::Status(1);
  my $host = getServiceHost();
  my $url = sprintf('%s/v1/s3/%s/%s',$host,$bucketName,$objectName);

  my $response = $self->_doRequest({
    method => 'DELETE',
    url => $url
  });

  if ($response->{'error'}) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'aws_s3_object' });
    $logger->log({
      'bucketName' => $bucketName,
      'objectName' => $objectName,
      'error'      => $response->{'error'}
    });

    $status->setFalse();
    $status->setError($response->{'error'});
  }

  return $status;
}

sub getPresignedURL {
  my $self = shift;
  my $input = shift;

  my $duration = $input->{'duration'};

  my $objectName = $self->{'objectName'};
  my $bucketName = $self->{'bucketName'};
  my $duration ||= $self->getExpireTime() =~ /^\d+$/ ? $self->getExpireTime() : 0; # make sure it's an integer

  my $host = getServiceHost();
  my $url = sprintf('%s/v1/s3/%s/%s',$host,$bucketName,$objectName);

  my $requestContent = {
    'bucketName' => $bucketName,
    'objectName' => $objectName,
    'duration' => $duration,
    'getPresignedUrlOnly' => $TRUE,
  };

  my $response = $self->_doRequest({
    method => 'PUT',
    url => $url, 
    content => $requestContent
  });

  my $url = '';
  if ($response->{'error'}) {
    my $logger = new PlugNPay::Logging::DataLog({ 'collection' => 'aws_s3_object' });
    $logger->log({
      'bucketName' => $bucketName,
      'objectName' => $objectName,
      'error'      => $response->{'error'}
    });
  } else {
    $url = $response->{'preSignedUrl'};
  }

  return $url;
}

=pod
  function : PlugNPay::AWS::S3::Object::_doRequest
  purpose : does request to s3 service
  input : 
    - method : request method (i.e. GET, PUT, etc.)
    - url : Service URL
    - requestData : JSON body for request
  output : 
   response : decoded JSON response from service, changes depending on endpoint called
=cut
sub _doRequest {
  my $self = shift;
  my $input = shift;
  my $method = $input->{'method'};
  my $url = $input->{'url'};
  my $content = $input->{'content'};

  my $ms = new PlugNPay::ResponseLink::Microservice($url);
  $ms->setMethod($method);
  my $success = $ms->doRequest($content);

  my $response = {};
  if ($success) {
    $response = $ms->getDecodedResponse();
  } else {
    eval {
      $response = $ms->getDecodedResponse();
    };
    if ($@) {
      $response = {'status' => 'error', 'error' => $ms->getErrors()};
    }
  }

  return $response;
}

1;
