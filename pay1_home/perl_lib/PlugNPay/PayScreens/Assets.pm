package PlugNPay::PayScreens::Assets;

use strict;
use MIME::Base64;
use PlugNPay::ResponseLink;
use PlugNPay::Reseller;
use PlugNPay::Logging::DataLog;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub upload {
  my $self = shift;
  my $input = shift;

  my $status = new PlugNPay::Util::Status(0);

  my $assetType = $input->{'assetType'};
  my $content = $input->{'content'};
  my $contentType = $input->{'contentType'};
  my $gatewayAccount = $input->{'gatewayAccount'};
  my $alternate = $input->{'alternate'};
  my $url;
  if (defined $alternate) {
    $url = sprintf('http://%s/v1/%s/%s/%s/%s', 'assets.local', 'pay', $gatewayAccount, $assetType, $alternate);
  } else {
    $url = sprintf('http://%s/v1/%s/%s/%s', 'assets.local', 'pay', $gatewayAccount, $assetType);
  }
  my $base64Content = encode_base64($content);

  my $requestContent = {
    content => $base64Content,
    contentType => $contentType
  };

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL($url);
  $rl->setRequestMode('DIRECT');
  $rl->setRequestMethod('PUT');
  $rl->setRequestContentType('application/json');
  $rl->setRequestData($requestContent);
  $rl->setResponseAPIType('json');
  $rl->doRequest();

  my %responseAPIData = $rl->getResponseAPIData();
  if ($responseAPIData{'message'} eq 'success') {
    $status->setTrue();
  } else {
    $status->setFalse();
    $status->setError($responseAPIData{'message'});
  }

  my $sameHostUrl = _sameHostUrlFromUrls($responseAPIData{'urls'});

  my $data = {
    status => $status,
    object => $responseAPIData{'object'},
    bucket => $responseAPIData{'bucket'},
    urls => $responseAPIData{'urls'},
    sameHostUrl => $sameHostUrl
  };
  return $data;
}

sub download {
  my $self = shift;
  my $input = shift;

  my $status = new PlugNPay::Util::Status(0);
  
  my $gatewayAccount = $input->{'gatewayAccount'};
  my $path = $input->{'assetPath'};

  my $url = sprintf('http://%s/%s/%s/%s', 'assets.local', 'merchant', $gatewayAccount, $path);

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL($url);
  $rl->setRequestMode('DIRECT');
  $rl->setRequestMethod('GET');
  $rl->setRequestContentType('application/json');
  $rl->doRequest();

  my $content = $rl->getResponseContent();
  my %headers = $rl->getResponseHeaders();
  my $contentType = $headers{'Content-Type'};
  if ($rl->getStatusCode() =~ /^2\d\d/) {
    $status->setTrue();
  } else {
    $status->setFalse();
    $status->setError("failed to download asset");
  }

  my $data = {
    status => $status,
    content => $content,
    contentType => $contentType
  };
  return $data;
}

sub getAssetUrls {
  my $self = shift;
  my $input = shift;

  my $assetType = $input->{'assetType'};
  my $gatewayAccount = $input->{'gatewayAccount'};
  my $alternate = $input->{'alternate'};

  my $url;
  if (defined $alternate && $alternate ne '') {
    $url = sprintf('http://%s/v1/%s/%s/%s/%s', 'assets.local', 'pay', $gatewayAccount, $assetType, $alternate);
  } else {
    $url = sprintf('http://%s/v1/%s/%s/%s', 'assets.local', 'pay', $gatewayAccount, $assetType);
  }

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL($url);
  $rl->setRequestMode('DIRECT');
  $rl->setRequestMethod('GET');
  $rl->setResponseAPIType('json');
  $rl->doRequest();

  my %responseAPIData = $rl->getResponseAPIData();

  my $sameHostUrl = _sameHostUrlFromUrls($responseAPIData{'urls'});

  my $data = {
    object => $responseAPIData{'object'},
    bucket => $responseAPIData{'bucket'},
    urls => $responseAPIData{'urls'},
    sameHostUrl => $sameHostUrl
  };
  return $data;
}

sub getAssetInfo {
  my $self = shift;
  my $input = shift;

  my $assetType = $input->{'assetType'};
  my $gatewayAccount = $input->{'gatewayAccount'};
  my $alternate = $input->{'alternate'};

  my $url;
  if (defined $alternate && $alternate ne '') {
    $url = sprintf('http://%s/v1/%s/info/%s/%s/%s', 'assets.local', 'pay', $gatewayAccount, $assetType, $alternate);
  } else {
    $url = sprintf('http://%s/v1/%s/info/%s/%s', 'assets.local', 'pay', $gatewayAccount, $assetType);
  }

  my $rl = new PlugNPay::ResponseLink();
  $rl->setRequestURL($url);
  $rl->setRequestMode('DIRECT');
  $rl->setRequestMethod('GET');
  $rl->setResponseAPIType('json');
  $rl->doRequest();

  my %responseAPIData = $rl->getResponseAPIData();

  my $status = new PlugNPay::Util::Status(1);
  if ($rl->getStatusCode() !~ /^2\d\d/) {
    $status->setFalse();
    $status->setError($responseAPIData{'message'});
  }

  my $sameHostUrl = _sameHostUrlFromUrls($responseAPIData{'urls'});

  my $data = {
    object => $responseAPIData{'object'},
    bucket => $responseAPIData{'bucket'},
    urls => $responseAPIData{'urls'},
    sameHostUrl => $sameHostUrl,
    contentType => $responseAPIData{'contentType'},
    size => $responseAPIData{'size'},
    status => $status
  };
  return $data;
}

# same input as upload but with an additional key of 'localFile'
sub migrate {
  my $self = shift;
  my $input = shift;
  # ensure content is not passed to this function
  delete $input->{'content'};

  my $localFile = $input->{'localFile'};

  my $status = new PlugNPay::Util::Status(1);

  # localFile is not present in input
  if (!$localFile) {
    $status->setFalse();
    $status->setError('localFile input is required to migrate an asset');
  }

  # file contains ..    <-- already dot dot... fail
  if ($status && $localFile =~ /\.\./) {
    $status->setFalse();
    $status->setError('directory traversal attempt detected in file name');
  }

  # file is not an asset...fail
  if ($status && $localFile !~ /^\/home\/(p\/)?pay1\/web\/logos\//) {
    $status->setFalse();
    $status->setError('file is not in a defined allowed asset path');
  }

  # if file does not exist...fail
  if ($status && !-e $localFile) {
    $status->setFalse();
    $status->setError('local file does not exist');
  }

  # file exists but is not readble...fail
  if ($status && -e $localFile && (!-f $localFile || !-r $localFile)) {
    $status->setFalse();
    $status->setError("file is not readable");
  }


  my $response;
  my $renamedFile = "$localFile.s3";
  my $localFileDir = $self->_dirFromFile($localFile);

  # if all is good so far, the file looks like it hasn't been migrated (no .s3 file) 
  # and the directory the file is in exists...
  if ($status && !-e $renamedFile && -e $localFileDir) {
    # one last check... is the directory writable?  if not...fail
    if ($status && !-w $localFileDir) {
      $status->setFalse();
      $status->setError('directory containing file to be migrated is not writable');
    }

    my %uploadInput;
    if ($status) {
      # create a copy of input to pass into _upload
      %uploadInput = %{$input};
      $uploadInput{'content'} = $self->_read($localFile);

      $response = $self->upload(\%uploadInput);
      if ($response->{'status'}) {
        # rename local file
        # checks above suggest it will not fail, but putting it in an eval anyway
        # only rename if asset type is not "other"
        if ($input->{'assetType'} ne 'other') {
          eval {
            rename($localFile,$renamedFile);
          };

          if ($@) {
            $status->setFalse();
            my $oneLineError = $@;
            $oneLineError =~ s/\n/; /g;
            $status->setError('An unexpected error occurred while renaming the file: ' + $oneLineError);
          }
        }
      } else {
        $status->setFalse();
        $status->setError($response->{'status'}->getError());
      }

      # we don't want to pass this back.  we have a separate return variable for status
      delete($response->{'status'});
    }
  } else {
    $response = $self->getAssetInfo($input);
    
    # overwrite the status with the response from getAssetInfo
    $status = $response->{'status'};
  }

  if (wantarray()) {
    return ($response,$status);
  }
  return $response;
}

sub _localFileExists {
  my $path = shift;
  return -e $path;
}

sub _read {
  my $self = shift;
  my $localFile = shift;

  # read the file
  my ($fh,$content);
  open($fh, '<', $localFile);
  sysread $fh, $content, -s $fh;
  close($fh);

  return $content;
}

sub _dirFromFile {
  my $self = shift;
  my $file = shift;
  my $dir = $file;
  $dir =~ s/(.*)\/.*?$/\1/;
  return $dir;
}

sub getPrivateLabelDomainList {
  my $self = shift;
  my $r = new PlugNPay::Reseller();
  my $privateLabelDomains = $r->getAdminDomainList();
  return $privateLabelDomains;
}

sub migrateTemplateAssets {
  my $self = shift;
  my $input = shift;
  my $username = $input->{'username'};
  my $templateSections = $input->{'templateSections'};

  # init random number generator using the time, username, and template as the seed
  srand(time()+$username + join('',values %{$templateSections}));

  my $features = new PlugNPay::Features($username,'general');

  my $thisServer = $ENV{'SERVER_NAME'}; # DO NOT USE $ENV{'HTTP_HOST'}, it is not safe

  # keep references to urls for assets as we iterate over the loop below
  my %assetUrls;

  my $staticContentServerSetting = _getStaticContentServerSetting($features);

  # remove references to this server and/or private label domains so that we can replace the url properly
  my $privateLabelDomains = $self->getPrivateLabelDomainList;
  push @{$privateLabelDomains},$thisServer;

  foreach my $section (keys %{$templateSections}) {
    my $sectionContent = $templateSections->{$section};
    my $updateOutput = _updateAssetsInHtml({
      html => $sectionContent,
      username => $username,
      privateLabelDomains => $privateLabelDomains,
      assetUrls => \%assetUrls,
      staticContentServerSetting => $staticContentServerSetting,
      existsFunction => sub {
        _localFileExists(@_);
      },
      migrationFunction => sub {
        $self->migrate(@_);
      },
      assetInfoFunction => sub {
        $self->getAssetInfo(@_);
      }
    });

    $templateSections->{$section} = $sectionContent;
  }

  return $templateSections;
}

sub migrateHtmlAssets {
  my $self = shift;
  my $input = shift;
  my $username = $input->{'username'};
  my $html = $input->{'html'};

  # init random number generator using the time, username, and html as the seed
  srand(time()+$username + $html);

  my $features = new PlugNPay::Features($username,'general');

  my $thisServer = $ENV{'SERVER_NAME'}; # DO NOT USE $ENV{'HTTP_HOST'}, it is not safe

  my $staticContentServerSetting = _getStaticContentServerSetting($features);

  my %assetUrls;

  # remove references to this server and/or private label domains so that we can replace the url properly
  my $privateLabelDomains = $self->getPrivateLabelDomainList;
  push @{$privateLabelDomains},$thisServer;

  $html = _updateAssetsInHtml({
    html => $html,
    username => $username,
    privateLabelDomains => $privateLabelDomains,
    assetUrls => \%assetUrls,
    staticContentServerSetting => $staticContentServerSetting,
    existsFunction => sub {
      _localFileExists(@_);
    },
    migrationFunction => sub {
      $self->migrate(@_);
    },
    assetInfoFunction => sub {
      $self->getAssetInfo(@_);
    }
  });

  return $html;
}

sub _getStaticContentServerSetting {
  my $features = shift;

  my $staticContentServerSetting = $features->get('staticContentServer') || $features->get('slashpayStaticContent') || undef;
  return $staticContentServerSetting;
}

sub _deriveAssetTypeFromPath {
  my $path = shift;
  my $assetType = 'other';

  if ($path eq 'logos') {
    $assetType = 'logo';
  } elsif ($path eq 'backgrounds') {
    $assetType = 'background';
  } elsif ($path eq 'css') {
    $assetType = 'css';
  }

  return $assetType;
}

sub _selectAssetUrl {
  my $sameHostUrl = shift;
  my $urls = shift;
  my $staticContentServerSetting = shift;

  my $url;

  if ($staticContentServerSetting eq 'sameHost') {
    $url = $sameHostUrl;
  } else {
    $url = $urls->[int(rand(@{$urls}))];
  }

  return $url;
}

sub _updateAssetsInHtml {
  my $input = shift;

  my $html = $input->{'html'} || die('no content to update');
  my $username = $input->{'username'} || die('username not defined');
  my $privateLabelDomains = $input->{'privateLabelDomains'};
  my $assetUrls = $input->{'assetUrls'};
  my $staticContentServerSetting = $input->{'staticContentServerSetting'};

  my $existsFunction = $input->{'existsFunction'};
  if (ref($existsFunction) ne 'CODE') {
    die('existsFunction is not code');
  }

  my $migrationFunction = $input->{'migrationFunction'};
  if (ref($migrationFunction) ne 'CODE') {
    die('migrationFunction is not code');
  }

  my $assetInfoFunction = $input->{'assetInfoFunction'};
  if (ref($assetInfoFunction) ne 'CODE') {
    die('assetUrlsFunction is not code');
  }

  my $logger = new PlugNPay::Logging::DataLog({ collection => 'migrate_payutils_assets'});

  foreach my $server (@{$privateLabelDomains}) {
    $server =~ s/[^a-zA-Z0-9\.\-]//g;
    next if $server eq '';

    $html =~ s/https:\/\/$server(:\d+)?\//\//; 
  }

  # while we see a path to an asset...
  while ($html =~ /['"](\/logos\/.*?)['"]/) {
    my $location = $1;
    my $localFile = '/home/pay1/web' . $location;

    my $alternate;
    if ($location !~ /\/$username/ || $location !~ /^\/logos\/upload\// || $location =~ /_/) {
      if ($location !~ /_mobile/ && -e $localFile) {
        # non-standard asset...log, and create an alternate based on the name
        $logger->log({
          message => 'Non-standard asset found in template',
          localFile => $localFile,
          gatewayAccount => $username
        });
      }

      my @pathParts = split(/\//,$location);
      
      # if in logos/upload, file name is the last part of the path
      # otherwise use the path within logos as the alternate name
      if ($location =~ /^\/logos\/upload\//) {
        $alternate = pop @pathParts;
      } else {
        $alternate = join('__',@pathParts);
      }

      # if the filename starts with the username, remove it.
      my $usernamePrefix = $username . '_';
      $alternate =~ s/^$usernamePrefix//;

      # remove file extension from alternate name
      $alternate =~ s/\..*$//;
    }

    $location =~ /\/logos\/upload\/(\w+)/.*/;
    my $assetTypePath = $1;

    # derive correct asset type
    my $assetType = _deriveAssetTypeFromPath($assetTypePath);

    # if we have already replaced this asset type, re-use the url rather than calling the service to get another one
    if ($assetType ne 'other' && defined $assetUrls->{$assetType}) {
      my $url = $assetUrls->{$assetType};
      $html = _replaceAssetUrl($html,$url);
      next;
    }

    my $urls = [];
    my $sameHostUrl = '';

    # if the local file exists and it's a proper asset type, try and migrate it using the service
    # else: load the urls for the asset from the service
    if ($existsFunction->($localFile)) {
      my $contentType = undef;

      # only set content-type for css, image content types are auto detected by the asset service.
      if ($assetType eq 'css') {
        $contentType = 'text/css';
      }

      my $migrateInfo = {
        localFile => $localFile,
        assetType => $assetType,
        gatewayAccount => $username,
        contentType => $contentType
      };

      if (defined $alternate) {
        $migrateInfo->{'alternate'} = $alternate;
      }

      my ($migrateResponse,$migrateStatus) = $migrationFunction->($migrateInfo);

      # replace the url
      $urls = $migrateResponse->{'urls'};
      $sameHostUrl = $migrateResponse->{'sameHostUrl'};

      if (!$migrateStatus) {
        $logger->log({
          message => 'Failed to migrate asset',
          localFile => $localFile,
          gatewayAccount => $username,
          error => $migrateStatus->getError()
        });
      }
    } else {
      my $assetInfoRequest = {
        assetType => $assetType,
        gatewayAccount => $username,
      };

      if (defined $alternate) {
        $assetInfoRequest->{'alternate'} = $alternate;
      }

      # then get the urls that should work
      my $infoResponse = $assetInfoFunction->($assetInfoRequest);
      $urls = $infoResponse->{'urls'};
      $sameHostUrl = $infoResponse->{'sameHostUrl'};
    }

    # pick a random url from the urls for the asset
    my $url = _selectAssetUrl($sameHostUrl,$urls,$staticContentServerSetting);

    # set the url for the asset type so we can reuse it if necessary
    if ($assetType) {
      $assetUrls->{$assetType} = $url;
    }

    $html = _replaceAssetUrl($html,$url);
  }

  return $html;
}

sub _replaceAssetUrl {
  my $line = shift;
  my $url = shift;

  $line =~ s/['"][^'"]*?\/logos\/[^'"]*?['"]/'$url'/;
  return $line;
}

sub _sameHostUrlFromUrls {
  my $urls = shift;

  my $sameHostUrl = $urls->[0];
  $sameHostUrl =~ s/^https:\/\/.*?\///;
  $sameHostUrl = '/assets/' . $sameHostUrl;

  return $sameHostUrl;
}

1;
