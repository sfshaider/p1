package PlugNPay::WebDataFile;

# use for any files that you would "store on the webserver"
# NOT FOR LOG USE

# Last Updated 2020-02-14: Renamed package, removed automatic reupload if file wasn't in s3, adjusted warning accordingly.
# Original Version: Thanks @dmanitta!

use strict;
use warnings;
use PlugNPay::AWS::S3::Object::Simple;
use PlugNPay::AWS::ParameterStore;
use PlugNPay::Util::Status;

our $_settings_;
our $_storageKeyMaps_;
our $_logger_;

sub _collection_ {
  return 'web_data_file';
};

sub _defaultParameter_ {
  return "/WEBDATA/S3";
};

sub _get_logger_ {
  if (!defined $_logger_) {
    $_logger_ = new PlugNPay::Logging::DataLog({ 'collection' => _collection_ });
  }
  return $_logger_;
}

if (!$_settings_) {
  $_settings_ = {};
}

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $parameter = shift;
  $self->{'parameter'} = $parameter || _defaultParameter_;

  return $self;
}

##################
# Public Methods #
##################
sub readFile {
  my $self = shift;
  my $fileOptions = shift;

  my $logger = _get_logger_;

  if (ref($fileOptions) ne 'HASH') {
    my $message = sprintf('Invalid arguments passed to writeFile, expected "HASH", got "%s"', ref($fileOptions));
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  my $fileName   = $fileOptions->{'fileName'};
  my $subPrefix  = $fileOptions->{'subPrefix'};
  my $storageKey = $fileOptions->{'storageKey'};
  my $localPath  = $fileOptions->{'localPath'};
  my $getContentType = $fileOptions->{'getContentType'};
  my ($content,$contentType);

  # don't let paths be specified willy-nilly, map it to the proper storage key, if a storage key
  # doesn't exist, add it to the config 🐱
  eval {
    if ($localPath) {
      $storageKey = $self->_storageKeyFromLocalPath($localPath) || $storageKey;
    }
  };

  if (!(my $fileOk = $self->_fileNameOk($fileName))) {
    my $message = sprintf('Invalid/illegal filename; error %s',$fileOk->getError());
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  eval {
    ($content,$contentType) = $self->_loadFromS3({
      fileName   => $fileName,
      subPrefix  => $subPrefix,
      storageKey => $storageKey
    });
  };

  if ($@) {
    my $message = sprintf('Failed to load file from s3, error: %s',$@);
    $logger->log({
      message => $message,
      fileName => $fileName,
      subPrefix => $subPrefix,
      storageKey => $storageKey
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  if (!$content) {
    my $localPath;
    eval {
      ($content,$localPath) = $self->_loadFromLocalDirectory($storageKey, $subPrefix, $fileName);
    };

    my $s3Url = '';
    my $filePath = sprintf('%s/%s',$localPath,$fileName);

    if (defined $content && $content ne '') {
      eval {
        $s3Url = $self->writeFile({
          fileName   => $fileName,
          subPrefix  => $subPrefix,
          storageKey => $storageKey,
          content => $content
        });
      };

      if (!$@) {
        $logger->log({
          message    => sprintf('Copied local file up to s3: [%s/%s] => [%s]', $localPath, $fileName, $s3Url),
          localPath  => $localPath,
          fileName   => $fileName,
          s3Url      => $s3Url
        });
        $self->_renameLocalFile($storageKey, $subPrefix, $fileName);
      }
    } elsif ( -e sprintf('%s.s3', $filePath) ) {
      $self->_warnOfMissingObject($storageKey, $subPrefix, $fileName);
    }
  }

  if ($getContentType) {
    return $content,$contentType;
  }

  return $content;
}

# writes a file to the datastore
# arguments as $hashref
#   fileName    - the name of the "file"
#   subPrefix   - used to organize the cntents within the storage, such as by date.
#                 looks like a path with root being defined by the storage key
#   storageKey  - this defines where the data is stored
#   localPath   - this is for backwards compatibility, used to look up the storage key to be used
#   content     - the content of the "file"
#   contentType - the content type of the file as it would be if downloaded via a browser, i.e. 'text/plain; charset=utf-8'
sub writeFile {
  my $self = shift;
  my $fileOptions = shift;

  my $logger = _get_logger_;

  if (ref($fileOptions) ne 'HASH') {
    my $message = sprintf('Invalid arguments passed to writeFile, expected "HASH", got "%s"', ref($fileOptions));
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  my $fileName    = $fileOptions->{'fileName'};
  my $subPrefix   = $fileOptions->{'subPrefix'};
  my $storageKey  = $fileOptions->{'storageKey'};
  my $localPath   = $fileOptions->{'localPath'} || '';
  my $content     = $fileOptions->{'content'};
  my $contentType = $fileOptions->{'contentType'} || 'text/plain; charset=utf-8';

  # don't let paths be specified willy-nilly, map it to the proper storage key, if a storage key
  # doesn't exist, add it to the config 🐱
  eval {
    if ($localPath) {
      $storageKey = $self->_storageKeyFromLocalPath($localPath) || $storageKey;
    }
  };

  if ($@) {
    my $message = sprintf('Error deriving storage key; error %s',$@);
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  if (!(my $fileOk = $self->_fileNameOk($fileName))) {
    my $message = sprintf('Invalid/illegal filename; error %s',$fileOk->getError());
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  my $s3Object = new PlugNPay::AWS::S3::Object::Simple();
  my $storageInfo = $self->_getStorageInfo($storageKey);

  my $bucket = $storageInfo->{'bucket'};
  my $objectKey = $self->_objectKeyFrom($storageInfo->{'prefix'},$subPrefix,$fileName);

  my $putStatus;
  eval {
    $putStatus = $s3Object->put({
      bucket      => $bucket,
      object      => $objectKey,
      contentType => $contentType,
      data        => $content
    });
  };

  my $s3Url = sprintf('s3://%s/%s',$bucket,$objectKey);

  if ($@ || !$putStatus) {
    my $message = sprintf('Failed to write data to s3: [%s]', $s3Url);
    $logger->log({
      message     => $message,
      bucketName  => $bucket,
      objectName  => $objectKey,
      contentType => $contentType,
      error       => $@ || $putStatus->getError()
    },{
      failure => 1,
      alert   => 1,
      die => 1
    });
    die($message)
  }

  return $s3Url;
}

sub deleteFile {
  my $self = shift;
  my $fileOptions = shift;

  my $logger = _get_logger_;

  if (ref($fileOptions) ne 'HASH') {
    my $message = sprintf('Invalid arguments, expected "HASH" reference, got "%s"', ref($fileOptions));
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  my $fileName   = $fileOptions->{'fileName'};
  my $subPrefix = $fileOptions->{'subPrefix'};
  my $storageKey = $fileOptions->{'storageKey'};
  my $localPath  = $fileOptions->{'localPath'} || '';

  # don't let paths be specified willy-nilly, map it to the proper storage key, if a storage key
  # doesn't exist, add it to the config 🐱
  eval {
    if ($localPath) {
      $storageKey = $self->_storageKeyFromLocalPath($localPath) || $storageKey;
    }
  };

  if (!(my $fileOk = $self->_fileNameOk($fileName))) {
    my $message = sprintf('Invalid/illegal filename; error %s',$fileOk->getError());
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  my $s3Object = new PlugNPay::AWS::S3::Object::Simple();
  my $storageInfo = $self->_getStorageInfo($storageKey);

  my $bucket = $storageInfo->{'bucket'};
  my $objectKey = $self->_objectKeyFrom($storageInfo->{'prefix'},$subPrefix,$fileName);

  eval {
    $s3Object->delete({
      bucket => $bucket,
      object => $objectKey
    })
  };

  my $s3Url = sprintf('s3://%s/%s',$bucket,$objectKey);

  if ($@) {
    $logger->log({
      message => sprintf('Failed to delete file from s3: [%s];  error: %s', $s3Url, $@),
      bucket => $bucket,
      object => $objectKey
    },{
      failure => 1,
    });
  }

  $self->_deleteLocalFile($storageKey,$subPrefix,$fileName);
}



###################
# Private Methods #
###################
sub _loadFromS3 {
  my $self = shift;
  my $s3Info = shift;

  my $logger = _get_logger_;

  my $fileName = $s3Info->{'fileName'};
  my $subPrefix = $s3Info->{'subPrefix'};
  my $storageKey = $s3Info->{'storageKey'};

  if (!(my $fileOk = $self->_fileNameOk($fileName))) {
    my $message = sprintf('Invalid/illegal filename; error %s',$fileOk->getError());
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  my $s3Object = new PlugNPay::AWS::S3::Object::Simple();
  my $storageInfo = $self->_getStorageInfo($storageKey);
  my $fileData;

  my $bucket = $storageInfo->{'bucket'};
  my $objectKey = $self->_objectKeyFrom($storageInfo->{'prefix'},$subPrefix,$fileName);

  $objectKey = _cleanPath($objectKey);

  eval {
    $fileData = $s3Object->get({
      bucket => $bucket,
      object => $objectKey
    });
  };

  if ($@) {
    $logger->log({
      message => sprintf('File not found in s3;  [s3://%s/%s]', $bucket, $objectKey),
      bucket  => $bucket,
      object  => $objectKey,
      error   => $@
    },{
      failure => 1
    });
  }

  return $fileData;
}

  sub _loadFromLocalDirectory {
  my $self = shift;
  my $storageKey = shift;
  my $subPrefix = shift;
  my $fileName = shift;

  my $logger = _get_logger_;

  if (!(my $fileOk = $self->_fileNameOk($fileName))) {
    my $message = sprintf('Invalid/illegal filename; error %s',$fileOk->getError());
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  my $path = $self->_pathWithSubPrefix($storageKey,$subPrefix);

  my $f = sprintf('%s/%s',$path,$fileName);

  my $fileData;

  if ( -e $f && -f _ && -r _ ) {
    my $fh;
    open($fh,'<', $f) or die(sprintf('Failed to open file; [%s]', $f));
    sysread($fh, $fileData, -s $fh);
    close($fh);
  }

  return $fileData,$path;
}

sub _deleteLocalFile {
  my $self = shift;
  my $storageKey = shift;
  my $subPrefix = shift;
  my $fileName = shift;

  my $logger = _get_logger_;

  if (!(my $fileOk = $self->_fileNameOk($fileName))) {
    my $message = sprintf('Invalid/illegal filename; error %s',$fileOk->getError());
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  my $path = $self->_pathWithSubPrefix($storageKey,$subPrefix);
  my $f  = sprintf('%s/%s',$path,$fileName);
  my $fm = sprintf('%s/%s.s3',$path,$fileName);

  $self->_deleteFile($path,$f);
  $self->_deleteFile($path,$fm);
}

sub _deleteFile {
  my $self = shift;
  my $path = shift;
  my $fileWithPath = shift;
  my $logger = _get_logger_;

  eval {
    # allow status to remain 1 if the path does not exist.
    if ( -e $path ) {
      if ( -w $path ) {
        # allow status to remain 1 if the file does not exist.
        if ( -e $fileWithPath && -f _ ) {
          unlink($fileWithPath);
        }
      } else {
        $logger->log({
          message => sprintf('Failed to delete local file: [%s]; incorrect directory permissions', $fileWithPath),
          path => $path,
          fileWithPath => $fileWithPath
        },{
          failure => 1
        });
      }
    }
  };

  if ($@) {
    $logger->log({
      message => sprintf('Failed to delete local file: [%s]; unexpected error: %s', $fileWithPath, $@),
      path => $path,
      fileWithPath => $fileWithPath
    },{
      failure => 1
    });
  }
}

sub _renameLocalFile {
  my $self = shift;
  my $storageKey = shift;
  my $subPrefix = shift;
  my $fileName = shift;

  my $logger = _get_logger_;

  if (!(my $fileOk = $self->_fileNameOk($fileName))) {
    my $message = sprintf('Invalid/illegal filename; error %s',$fileOk->getError());
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  my $path = $self->_pathWithSubPrefix($storageKey,$subPrefix);

  my $f  = sprintf('%s/%s',$path,$fileName);
  my $fm = sprintf('%s/%s.s3',$path,$fileName);

  eval {
    if ( -w $path ) {
      if ( -e $f && -f $f && -r $f ) {
        rename($f, $fm);
      } else {
        $logger->log({
          message => sprintf('Failed to rename local file [%s] to [%s]; incorrect permissions on file', $f, $fm),
          path => $path,
          fileWithPath => $f
        },{
          failure => 1
        });
      }
    } else {
      $logger->log({
        message => sprintf('Failed to rename local file [%s] to [%s]; incorrect permissions on directory', $f, $fm),
        path => $path,
        fileWithPath => $f
      },{
        failure => 1
      });
    }
  };

  if ($@) {
    $logger->log({
      message => sprintf('Failed to rename local file [%s] to [%s]; unexpected error: %s', $f, $fm, $@)
    },{
      failure => 1
    });
  }
}

sub _objectKeyFrom {
  my $self = shift;
  my $prefix = shift;
  my $subPrefix = shift || '';
  my $fileName = shift;

  my $logger = _get_logger_;

  if (!(my $fileOk = $self->_fileNameOk($fileName))) {
    $logger->log({
      message => $fileOk->getError()
    },{
      failure => 1,
      stackTraceEnabled => 1
    });
    die(sprintf('Invalid/illegal file name: [%s]; error: %s', $fileName, $fileOk->getError()));
  }

  if ($subPrefix ne '') {
    $prefix = sprintf('%s/%s',$prefix,$subPrefix);
  }

  my $objectKey = sprintf('%s/%s',$prefix,$fileName);

  # clean the prefix
  $objectKey = _cleanPrefix($objectKey);

  # check to make sure prefix follows rules
  if (!(my $prefixOk = $self->_prefixOk($objectKey))) {
    my $message = sprintf('Invalid/illegal object key [%s]; error: %s', $objectKey, $prefixOk->getError());
    $logger->log({
      message => $message
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  return $objectKey;
}

sub _prefixOk {
  my $self = shift;
  my $prefix = shift;

  my $status = new PlugNPay::Util::Status(1);

  # do not allow empty prefix, prefix that starts with a slash, or prefix that starts with a space
  # or any character other than "a-zA-Z0-9_-\.\/"
  if (!defined $prefix || $prefix eq '' || substr($prefix,0,1) eq ' ' || substr($prefix,0,1) eq '\t') {
    $status->setFalse();
    $status->setError(sprintf('Prefix/Object may not be empty or contain only spaces;  prefix/object: [%s]', $prefix));
    return $status;
  }

  if (substr($prefix,0,1) eq '/') {
    $status->setFalse();
    $status->setError(sprintf('Prefix/Object may not start with a forward slash;  prefix/object: [%s]', $prefix));
    return $status;
  }

  if (index($prefix,'..') >= 0) {
    $status->setFalse();
    $status->setError(sprintf('Prefix/Object may not contain "..";  prefix/object: [%s]', $prefix));
    return $status;
  }

  if ($prefix =~ /[^a-zA-Z0-9_\-\/\.]/) {
    $status->setFalse();
    $status->setError(sprintf('Prefix/Object can only contain a-z, A-Z, 0-9, period, hyphens, and/or underscores;  prefix/object: [%s]', $prefix));
    return $status;
  }

  return $status;
}

# _pathOk checks to verify that a path is not a relative path, and that it actually exists.
sub _pathOk {
  my $self = shift;
  my $path = shift;

  my $status = new PlugNPay::Util::Status(1);

  if ($path eq '') {
    $status->setFalse();
    $status->setError('Empty path');
    return $status;
  }

  if (index($path,'..') >= 0) {
    $status->setFalse();
    $status->setError(sprintf('Path may not contain "..";  path: [%s]', $path));
    return $status;
  }

  if (substr($path,0,1) ne '/' || index($path,'..') >= 0) {
    $status->setFalse();
    $status->setError(sprintf('Relative paths are not permitted;  path: [%s]', $path));
    return $status;
  }

  return 1;
}

sub _fileNameOk {
  my $self = shift;
  my $fileName = shift;

  my $status = new PlugNPay::Util::Status(1);

  # do not allow empty filename or filename with only spaces
  if (!defined $fileName || $fileName eq '' || $fileName =~ /^\s+$/) {
    $status->setFalse();
    $status->setError(sprintf('File name can not be empty or contain only spaces;  fileName: [%s]', $fileName));
    return $status;
  }

  # do not allow forward slashes from file name
  if ($fileName =~ /\//) {
    $status->setFalse();
    $status->setError(sprintf('File name can not contain slashes; fileName: [%s]', $fileName));
    return $status;
  }

  return $status;
}

# _cleanPrefix has the same rules as _cleanPath but also removes a leading forward slash if present.
sub _cleanPrefix {
  my $prefix = shift || '';

  $prefix = _cleanPath($prefix);
  $prefix =~ s/^\///;
  return $prefix;
}

# _cleanPath removes double slashes from a path
sub _cleanPath {
  my $path = shift || '';

  $path =~ s/\/\/+/\//g; # remove repeated forward slashes
  $path =~ s/\/$//g;    # remove slash at end of path
  return $path;
}

sub _getSettings {
  my $parameter = shift;
  my $options = shift;

  my $force = $options->{'force'} || 0;

  my $logger = _get_logger_;

  if (!defined $parameter) {
    my $message = sprintf('Parameter argument is undefined.');
    $logger->log({
      {
        message           => $message,
      },{
        failure => 1,
        stackTraceEnabled => 1,
        die => 1
      }
    });
    die($message);
  }

  return $_settings_->{$parameter} if ($_settings_->{$parameter} && !$force);

  my $settings = PlugNPay::AWS::ParameterStore::getParameter($parameter);
  eval {
    require JSON::XS;
    $_settings_->{$parameter} = JSON::XS::decode_json($settings);
  };

  if ($@) {
    my $message = sprintf('Failed to parse settings for parameter: [%s]',$parameter);
    $logger->log({
      {
        message           => $message,
        parameterStoreKey => $parameter,
      },{
        failure => 1,
      }
    });
  }

  return $_settings_->{$parameter};
}

sub getStorageInfo {
  my $self = shift;
  return $self->_getStorageInfo(@_);
}

sub _getStorageInfo {
  my $self = shift;
  my $storageKey = shift;

  my $parameter = $self->{'parameter'};

  my $logger = _get_logger_;

  if (!$storageKey) {
    my $message = 'Missing required S3 data: storageKey!';
    $logger->log({
      message           => $message,
      parameterStoreKey => $parameter,
      storageKey        => $storageKey
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die $message;
  }

  my $settings = _getSettings($parameter);

  # if the storage key is not defined in the settings, refresh the settings cache.
  if (!defined $settings->{$storageKey}) {
    $settings = _getSettings($parameter, { force => 1 });

    # if the storage key is still not defined, log and die
    if (!defined $settings->{$storageKey}) {
      my $message = 'Storage key is not defined!';
      $logger->log({
        message           => $message,
        parameterStoreKey => $parameter,
        storageKey        => $storageKey
      },{
        failure => 1,
        stackTraceEnabled => 1,
        die => 1
      });
      die $message;
    }
  }

  my $storageSettings = $settings->{$storageKey};
  my $storageInfo = {
    bucket => $storageSettings->{'bucket'},
    prefix => $storageSettings->{'prefix'},
    localPath => $storageSettings->{'localPath'}
  };

  return $storageInfo;
}

sub _warnOfMissingObject {
  my $self = shift;
  my $storageKey = shift;
  my $subPrefix = shift;
  my $fileName = shift;

  my $parameter = $self->{'parameter'};

  my $logger = _get_logger_;

  my $path = $self->_pathWithSubPrefix($storageKey,$subPrefix);

  $logger->log({
    message    => sprintf('File appears to have been migrated to s3, but was not found in s3: [%s/%s]', $path, $fileName),
    fileName  => $fileName,
    localPath => $path,
    parameterStoreKey => $parameter,
    storageKey => $storageKey
  },{
    failure => 1
  });
}

sub _pathWithSubPrefix {
  my $self = shift;
  my $storageKey = shift;
  my $subPrefix = shift;

  my $storageInfo = $self->_getStorageInfo($storageKey);
  my $path = $storageInfo->{'localPath'} || '';

  my $logger = _get_logger_;

  if ($path eq '') {
    my $message = sprintf('No local path defined for storage key: [%s]', $storageKey);
    $logger->log({
      message    => $message,
      storageKey => $storageKey
    },{
      failure => 1,
      die => 1
    });
    die($message);
  }

  $path = sprintf('%s/%s',$path, $subPrefix || '');
  $path = _cleanPath($path);
  if (!(my $pathOk = $self->_pathOk($path))) {
    my $message = sprintf("Invalid/illegal path: [%s]; error: %s", $path, $pathOk->getError());
    $logger->log({
      message => $message,
      localPath => $path,
    },{
      failure => 1,
      stackTraceEnabled => 1,
      die => 1
    });
    die($message);
  }

  return $path;
}

sub _storageKeyFromLocalPath {
  my $self = shift;
  my $localPath = shift || '';
  my $parameter = $self->{'parameter'};

  return '' if (!$localPath);

  my $logger = _get_logger_;

  if (!defined $_storageKeyMaps_) {
    $_storageKeyMaps_ = {};
  }

  if (!defined $_storageKeyMaps_->{$parameter}) {
    $_storageKeyMaps_->{$parameter} = _generateStorageKeyMap($parameter);
  }

  $localPath = _cleanPath($localPath);

  if (!defined $_storageKeyMaps_->{$parameter}{$localPath}) {
    my $message = sprintf('No storage key found for local path: [%s]', $localPath);
    $logger->log({
      message    => $message,
      localPath => $localPath
    },{
      failure => 1,
      stackTraceEnabled => 1
    });
  }
  return $_storageKeyMaps_->{$parameter}{$localPath};
}

sub _generateStorageKeyMap {
  my $parameter = shift;
  my $ps = _getSettings($parameter);
  my %mapping = map { $ps->{$_}{'localPath'} || '' => $_ } keys %{$ps};
  delete $mapping{''}; # delete undefined mappings.
  return \%mapping;
}


1;
