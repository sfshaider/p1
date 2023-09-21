package PlugNPay::Util::Encryption::LegacyKey;
our $__moduleDigest = "cf2af7ee83099e9693627d8cb528ca97d89e17361c7cfd8d605bc239ddb7d899";

use strict;

use JSON::XS qw(encode_json decode_json);
use Time::HiRes;
use Fcntl;

use PlugNPay::Die;
use PlugNPay::AWS::ParameterStore;
use PlugNPay::AWS::S3::Object::Simple;
use PlugNPay::Logging::DataLog;
use PlugNPay::Sys::Time;
use PlugNPay::Util::Cache::LRUCache;
use PlugNPay::Util::Encryption::AES;
use PlugNPay::Util::Encryption::Random;
use PlugNPay::Util::Status;

our $cache;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  if (!$cache) {
    $cache = new PlugNPay::Util::Cache::LRUCache(36); # why not keep all the keys? (technically 26 would be enough)
  }

  return $self;
}

sub setLoadedVia {
  my $self = shift;
  my $via = shift;
  $self->{'loadedVia'} = $via;
}

sub getLoadedVia {
  my $self = shift;
  return $self->{'loadedVia'};
}

# Mutators and Accessors #
sub getBucketName {
  my $self = shift;

  return &PlugNPay::AWS::ParameterStore::getParameter('/S3/BUCKET/ENCRYPTION_KEY', 0);
}

sub setActiveKey {
  my $self = shift;
  my $activeKey = shift;
  $self->{'activeKey'} = $activeKey;
}

sub getActiveKey {
  my $self = shift;
  return $self->{'activeKey'};
}

sub setEncryptedActiveKey {
  my $self = shift;
  my $encryptedActiveKey = shift;
  $self->{'encryptedActiveKey'} = $encryptedActiveKey;
}

sub getEncryptedActiveKey {
  my $self = shift;
  return $self->{'encryptedActiveKey'};
}

sub setKeyFile {
  my $self = shift;
  my $keyFile = shift;
  $self->{'keyFile'} = $keyFile;
}

sub getKeyFile {
  my $self = shift;
  return $self->{'keyFile'};
}

sub setKeyEncryptionKey {
  my $self = shift;
  my $keyEncryptionKey = shift;
  $self->{'keyEncryptionKey'} = $keyEncryptionKey;
}

sub getKeyEncryptionKey {
  my $self = shift;
  return $self->{'keyEncryptionKey'};
}

sub setInitializationVector {
  my $self = shift;
  my $initializationVector = shift;
  $self->{'initializationVector'} = $initializationVector;
}

sub getInitializationVector {
  my $self = shift;
  return $self->{'initializationVector'};
}

# Key Generation and Retrival #
sub generateKey {
  my $self = shift;
  my $identifier = shift;

  if (!defined $identifier) {
    die 'Invalid key name' . "\n";
  }

  my $aes = new PlugNPay::Util::Encryption::AES();
  my $randomKey = PlugNPay::Util::Encryption::Random::random(32); # 32 * 8 = 256!
  my $randomKeyEncryptionKey = PlugNPay::Util::Encryption::Random::random(16); # 16 * 8 = 128!
  my $initializationVector = PlugNPay::Util::Encryption::Random::random(16); # 16 * 8 = 128!
  my $testCard = '4111111111111111';
  my $encryptedKey = $aes->encryptWithIV($randomKeyEncryptionKey,$initializationVector,$randomKey);

  # Test key #
  my $testCardEncrypted = $aes->encryptWithIV($randomKey,$initializationVector,$testCard);
  if ($testCard != $aes->decryptWithIV($randomKey,$initializationVector,$testCardEncrypted)) {
    die 'Decrypted data does not match encrypted data' . "\n"
  }

  # Test KEK #
  my $decryptedKey = $aes->decryptWithIV($randomKeyEncryptionKey,$initializationVector,$encryptedKey);
  if ($decryptedKey != $randomKey) {
    die 'Generated key encryption key error' . "\n";
  }

  return {
    'encryptedKey' => $encryptedKey,
    'keyEncryptionKey' => $randomKeyEncryptionKey,
    'initializationVector' => $initializationVector,
    'key' => $randomKey,
    'name' => $identifier
  };
}

sub _uploadKey {
  my $self = shift;
  my $fileName = shift;
  my $fileData = shift;

  # unpack to hex before storing in s3
  my %keyFileHex = %{$fileData};
  $keyFileHex{'key'} = unpack('H*',$keyFileHex{'key'});
  $keyFileHex{'encryptedKey'} = unpack('H*',$keyFileHex{'encryptedKey'});
  $keyFileHex{'keyEncryptionKey'} = unpack('H*',$keyFileHex{'keyEncryptionKey'});
  $keyFileHex{'initializationVector'} = unpack('H*',$keyFileHex{'initializationVector'});

  my $data = encode_json(\%keyFileHex);

  my $uploader = new PlugNPay::AWS::S3::Object::Simple();
  my $result = $uploader->put({'object' => $fileName, 'bucket' => $self->getBucketName(), 'contentType' => 'application/json', 'data' => $data,
                               'encType' => 'aws:kms', 'encKey' => 'LegacyKeyStoreMaster'});

  return $result;
}

sub _downloadKey {
  my $self = shift;
  my $fileName = shift;
  my $downloader = new PlugNPay::AWS::S3::Object::Simple();
  my $data = $downloader->get({'object' => $fileName, 'bucket' => $self->getBucketName(), 'contentType' => 'application/json'});
  my $keyFile = undef;
  if ($data ne '') {
    my $keyFileHex = decode_json($data);
    my %keyFileCopy = %{$keyFileHex};
    # pack hex values that were stored in s3
    $keyFileCopy{'key'} = pack('H*',$keyFileCopy{'key'});
    $keyFileCopy{'encryptedKey'} = pack('H*',$keyFileCopy{'encrytpedKey'});
    $keyFileCopy{'keyEncryptionKey'} = pack('H*',$keyFileCopy{'keyEncryptionKey'});
    $keyFileCopy{'initializationVector'} = pack('H*',$keyFileCopy{'initializationVector'});
    $keyFile = \%keyFileCopy;
  }

  return $keyFile;
}

sub _getLocalDBKey {
  my $self = shift;
  my $keyDate = shift;
  my $encryptedKey = $self->_readLocalDek($keyDate);
  my ($initializationVector,$keyEncryptionKey) = $self->_readDatabaseKekAndIv($keyDate);

  my $aes = new PlugNPay::Util::Encryption::AES();
  my $decryptedKey = $aes->decryptWithIV($keyEncryptionKey,$initializationVector,$encryptedKey);
  $decryptedKey = substr($decryptedKey,0,32);

  if ($decryptedKey eq '') {
    return {};
  }

  my $data = {
                    name => $keyDate,
            encryptedKey => $encryptedKey,
        keyEncryptionKey => $keyEncryptionKey,
    initializationVector => $initializationVector,
                     key => $decryptedKey
  };

  return $data;
}

sub _readLocalDek {
  my $self = shift;
  my $keyDate = shift;

  my $basePath = '/home/pay1/keys/pwfiles/keys/key';

  my $keyPath;
  if ($keyDate eq 'recurring') {
    $keyPath = sprintf('%s/key.txt',$basePath);
  } else {
    $keyDate = substr($keyDate,0,6); # just year and month for folder containing key file.
    $keyPath = sprintf('%s/%s/key.txt',$basePath,$keyDate);
  }

  my ($fh,$data);
  open($fh,'<',$keyPath);
  sysread $fh,$data, -s $fh;
  close($fh);

  chomp $data;
  $data = pack('H*', $data);

  return $data;
}

sub _writeLocalDek {
  my $self = shift;
  my $keyDate = shift;
  my $data = shift;

  my $basePath = '/home/pay1/keys/pwfiles/keys/key';

  my $status = new PlugNPay::Util::Status(1);

  my $keyPath;
  if ($keyDate eq 'recurring') {

  } else {
    $keyDate = substr($keyDate,0,6); # just year and month for folder containing key file.
    $keyPath = sprintf('%s/%s/key.txt',$basePath,$keyDate);
  }

  if ( !-e $keyPath ) {
    my $fh;
    my $originalUmask = umask 0000;
    eval {
      my $dir = sprintf('%s/%s',$basePath,$keyDate);
      if (!-d $dir) {
        mkdir($dir, 0755);
      }
      sysopen($fh,$keyPath, O_CREAT|O_EXCL|O_WRONLY, 0644);
      my $unpacked = unpack('H*',$data);
      print $fh $unpacked;
      close($fh);
    };
    umask $originalUmask;
    if ($@) {
      $self->log({
        message => 'Failed to write local dek file',
        keyDate => $keyDate
      });
    }
  } else {
    $status->setFalse();
    $status->setError('Failed to write data encryption key file');
    $status->setErrorDetails('Key file already exists');
  }

  return $status;
}

sub _readDatabaseKekAndIv {
  my $self = shift;
  my $keyDate = shift;

  if ($keyDate eq 'recurring') {
    $keyDate = '01'; # why?!
  }

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc',q/
    SELECT passphrase FROM pnpkey WHERE trans_date=?
  /, [$keyDate],{});

  my $ivKEKCombo = '';
  my $rows = $result->{'result'};
  if ($rows && $rows->[0]) {
    $ivKEKCombo = $rows->[0]{'passphrase'}
  }

  my ($iv,$kek) = split(/ /,$ivKEKCombo);
  if (length($iv) == 32) {
    $iv = pack('H*',$iv);
    $kek = pack('H*',$kek);
  }

  return ($iv,$kek);
}

sub _writeDatabaseKekAndIv {
  my $self = shift;
  my $keyDate = shift;
  my $kek = shift;
  my $iv = shift;

  my $status = new PlugNPay::Util::Status(1);

  my $passphraseString = sprintf('%s %s',unpack('H*',$iv),unpack('H*',$kek));

  if ($keyDate eq 'recurring') {
    $keyDate = '01';
  }

  my $dbs = new PlugNPay::DBConnection();
  eval {
    my $result = $dbs->executeOrDie('pnpmisc',q/
      INSERT INTO pnpkey (trans_date, passphrase) VALUES (?,?)
    /, [$keyDate,$passphraseString]);
  };
  if ($@) {
    $status->setFalse();
    $status->setError('Failed to insert key encryption key and initializationVector into database');
    $status->setErrorDetails($@);
  }

  return $status;
}

sub generateMonthlyKey {
  my $self = shift;
  my $keyDate = shift;
  if (!$keyDate || !($keyDate =~ /^\d{8}$/ || $keyDate =~ /^\d{6}$/)) {
    $keyDate = substr(new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd'),0,6) . '01';
  }

  if (length($keyDate) == 6) {
    $keyDate = $keyDate . "01";
  }

  my $keyFile = {};
  my $status = new PlugNPay::Util::Status(1);

  # If this key already exists then do not generate a new one #
  if (!$self->keyExists($keyDate)) {
    # Create monthly key, validate key and KEK #
    eval {
      $keyFile = $self->generateKey($keyDate);
    };

    if ($@) {
      $status->setFalse();
      $status->setError('Failed to generate new key.');
      $status->setErrorDetails($@);
      $self->log({
        message => 'Failed to generate new key',
        errorMessage => $@,
        identifier => $keyDate
      });
    } elsif($status) {
      $cache->set($keyDate, $keyFile); #store new key to cache
      $status = $self->_uploadKey($keyDate, $keyFile);
      if ($status) {
        $self->_writeLocalDek($keyDate,$keyFile->{'encryptedKey'});
      }
      if ($status) {
        $self->_writeDatabaseKekAndIv($keyDate,$keyFile->{'keyEncryptionKey'},$keyFile->{'initializationVector'});
      }
    }
  } else {
    $status->setFalse();
    $status->setError('failed to generate key');
    $status->setErrorDetails('Key generation failed, key already exists');
  }

  return $status;
}

sub loadMonthlyKey {
  my $self = shift;
  my $keyName = shift;

  # Is yyyymm passed in? #
  my $yearMonth = $keyName;
  if ($yearMonth =~ /^\d{6}$/) {
    $yearMonth .= '01';
  } elsif ($yearMonth =~ /^\d{8}$/) {
    $yearMonth = substr($yearMonth,0,6) . '01';
  } elsif (!$yearMonth) {
    $yearMonth = substr(new PlugNPay::Sys::Time()->nowInFormat('yyyymmdd'),0,6) . '01';
  } else {
    die('Lame, bad argument.  YYYYMM, YYYYMMDD, or nothing at all!');
  }

  return $self->loadKey($yearMonth);
}

sub loadRecurringKey {
  my $self = shift;
  return $self->loadKey('');
}

sub loadKey {
  my $self = shift;
  my $yearMonth = shift;
  my $status = new PlugNPay::Util::Status(1);

  my ($keyName,$keyFileName);
  if (!$yearMonth) {
    $yearMonth = 'recurring';
    $keyName = 'recurring';
    $keyFileName = $keyName;
  } else {
    $keyFileName = $yearMonth;
    $keyName = substr($yearMonth,-8,6); # for logging
  }

  eval {
    # Check cache for key file #
    my $keyFile;
    if ($cache->contains($yearMonth)) {
      $self->setLoadedVia('cache');
      $keyFile = $cache->get($yearMonth);
    } else {
      my $startLoad = Time::HiRes::time();

      eval {
        $keyFile = $self->_downloadKey($keyFileName);
        if ($keyFile && $keyFile->{'key'} ne '') {
          $self->setLoadedVia('s3');
          my $endLoad = Time::HiRes::time();
          my $loadDuration = $endLoad - $startLoad;
          $self->log({
            message => 'Loaded key from s3',
            keyName => $keyName,
            via => $self->getLoadedVia(),
            duration => $loadDuration,
            fileName => $keyFileName,
            bucket => $self->getBucketName()
          });

          $cache->set($yearMonth,$keyFile);
        }
      };

      if (!$keyFile || !$keyFile->{'key'}) {
        $keyFile = $self->_getLocalDBKey($yearMonth);
        if ($keyFile->{'key'}) {
          $self->setLoadedVia('localDB');
          my $endLoad = Time::HiRes::time();
          my $loadDuration = $endLoad - $startLoad;
          $self->log({
            message => 'Loaded key from filesystem/database',
            keyName => $keyName,
            via => $self->getLoadedVia(),
            duration => $loadDuration
          });

          $cache->set($yearMonth,$keyFile);

          eval {
            my $exists = $self->_downloadKey($yearMonth);
            if (!$exists) { # only upload if it's not in s3 already.
              my $uploaded = $self->_uploadKey($yearMonth,$keyFile);
              if ($uploaded) {
                $self->log({
                  message => 'Uploaded key to s3',
                  keyName => $keyName,
                  yyyymmdd => $yearMonth
                });
              } else {
                $self->log({
                  message => 'Upload key to s3 failed',
                  keyName => $keyName,
                  yyyymmdd => $yearMonth,
                  error => $uploaded->getError(),
                  errorDetails => $uploaded->getErrorDetails()
                });
              }
            }
          };

          if ($@) {
            $self->log({
              message => 'Upload key to s3 failed',
              keyName => $keyName,
              yyyymmdd => $yearMonth,
              error => $@
            });
          }
        }
      }
    }

    $self->setKeyFile($keyFile);
    $self->setInitializationVector($keyFile->{'initializationVector'});
    $self->setKeyEncryptionKey($keyFile->{'keyEncryptionKey'});
    $self->setEncryptedActiveKey($keyFile->{'encryptedKey'});

    $self->setActiveKey($keyFile->{'key'});
  };

  if ($@) {
    $status->setFalse();
    $status->setError('Key load error');
    $status->setErrorDetails($@);
    $self->log({
      message => 'Key load error',
      errorMessage => $@,
      keyName => $yearMonth
    });
  }

  return $status;
}

sub keyExists {
  my $self = shift;
  my $keyIdentifier = shift;
  my $existed = 0;

  # First we should check the cache #
  if ($cache->contains($keyIdentifier)) {
    $existed = 1;
  }

  if (!$existed) {
    # Next we should check AWS #
    eval {
      my $keyFile = $self->_downloadKey($keyIdentifier); # dies on error, so on error, $isNew stays == 1
      if ($keyFile && $keyFile->{'key'}) {
        $existed = 1;
      }
    };
  }

  # finally check local/db
  if (!$existed) {
    eval {
      my $data = $self->_getLocalDBKey($keyIdentifier);
      if ($data->{'key'}) {
        $existed = 1;
      }
    };
  }

  return $existed;
}

sub log {
  my $self = shift;
  my $data = shift;
  new PlugNPay::Logging::DataLog({'collection' => 'encryption_key'})->log($data);
}

1;
