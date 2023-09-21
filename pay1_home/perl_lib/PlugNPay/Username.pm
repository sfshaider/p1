package PlugNPay::Username;

# this module is mostly redundant.
# login emails are set/get via this
# all other functions are basically wrappers for calls to PlugNPay::Authentication::Login
#
# The Plan (the first two are complete as of writing this comment)
#   1) add code to load login email from userauth service, if not present, load from pnpmisc.sub_email (the latter is current behavior)
#   2) add code to set login email in *both* service and pnpmisc
#   3) sync all emails to logindb.acl_login from pnpmisc.sub_email
#   4) remove code to load from pnpmisc.sub_email

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Sys::Time;
use PlugNPay::Email::Sanitize;
use PlugNPay::Authentication::Login;
use PlugNPay::Util::Array qw(inArray);

use overload '""' => 'getUsername';

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $username = lc shift;
  $self->setUsername($username);

  return $self;
}

sub setUsername {
  my $self = shift;
  my $username = shift;
  $username =~ s/[^a-zA-Z0-9_]//g;
  $self->{'username'} = $username;
}

sub getUsername {
  my $self = shift;
  return lc($self->{'username'});
}

sub getUsernameAsEntered {
  my $self = shift;
  return $self->{'username'};
}

sub setGatewayAccount {
  my $self = shift;
  my $gatewayAccount = shift;
  $self->{'gatewayAccount'} = $gatewayAccount;
}

sub setRealm {
  my $self = shift;
  my $realm = shift;
  $self->{'realm'} = uc $realm;
}

sub getRealm {
  my $self = shift;

  my $realm = $self->{'realm'} || defaultRealmForLogin($self->getUsername());
  return uc($realm);
}

sub getGatewayAccount {
  my $self = shift;
  
  my $login = new PlugNPay::Authentication::Login({
    login => $self->getUsername()
  });
  $login->setRealm('PNPADMINID');

  my $result = $login->getLoginInfo();
  if ($result) {
    my $loginInfo = $result->get('loginInfo');
    return $loginInfo->{'account'};
  }

  die('failed to load login info from service for login "' . $self->getUsername() . '"');
}

sub isMainLogin {
  my $self = shift;
  return $self->getGatewayAccount() eq $self->getUsername() ? 1 : 0;
}

sub setPassword {
  my $self = shift;
  my $password = shift;

  my $login = new PlugNPay::Authentication::Login({
    login => $self->getUsername()
  });

  my $realm = $self->getRealm() || defaultRealmForLogin($self->getUsername());
  $login->setRealm($realm);

  my $result = $login->setPassword({
    password => $password
  });

  return $result;
}

sub setPasswordHash {
  my $self = shift;
  # does nothing
}

sub getPasswordHash {
  my $self = shift;
  # returns nothing
}

sub setPasswordSalt {
  my $self = shift;
  # does nothing
}

sub getPasswordSalt {
  my $self = shift;
  # returns nothing
}

sub setPasswordType {
  my $self = shift;
  # does nothing
}

sub getPasswordType {
  my $self = shift;
  # returns nothing
}

sub setSecurityLevel {
  my $self = shift;
  my $securityLevel = shift;
  
  my $login = new PlugNPay::Authentication::Login({
    login => $self->getUsername()
  });
  $login->setRealm('PNPADMINID');
  
  return $login->setSecurityLevel({
    securityLevel => $securityLevel
  });
}

sub getSecurityLevel {
  my $self = shift;
  my $login = new PlugNPay::Authentication::Login();
  $login->setRealm('PNPADMINID');

  my $result = $login->getLoginInfo({
    login => $self->getUsername()
  });
  if ($result) {
    my $loginInfo = $result->get('loginInfo');
    return $loginInfo->{'securityLevel'};
  }
  
  die('failed to load login info from service');
}

sub verifyPassword {
  my $self = shift;
  my $password = shift;
  my $realm = shift || 'PNPADMINID';

  my $authentication = new PlugNPay::Authentication();
  return $authentication->validateLogin({
    generateCookie => 0,
    login => $self->getUsername(),
    password => $password,
    realm => $realm
  });
}

sub setTemporaryPasswordFlag {
  my $self = shift;
  my $flag = (shift(@_) ? 1 : 0);
  
  my $login = new PlugNPay::Authentication::Login({
    login => $self->getUsername()
  });
  $login->setRealm('PNPADMINID');

  return $login->setTemporaryPasswordMarker();
}

sub getTemporaryPasswordFlag {
  my $self = shift;
  
  my $login = new PlugNPay::Authentication::Login();
  $login->setRealm('PNPADMINID');

  my $result = $login->getLoginInfo({
    login => $self->getUsername()
  });
  if ($result) {
    my $loginInfo = $result->get('loginInfo');
    return $loginInfo->{'passwordIsTemporary'} ? 1 : 0;
  }
  
  die('failed to load login info from service');
}

sub passwordIsExpired {
  my $self = shift;
  my $login = new PlugNPay::Authentication::Login();
  $login->setRealm('PNPADMINID');

  my $result = $login->getLoginInfo({
    login => $self->getUsername()
  });
  if ($result) {
    my $loginInfo = $result->get('loginInfo');
    return $loginInfo->{'passwordIsExpired'};
  }
  
  die('failed to load login info from service');
}

sub deleteUsername {
  my $self = shift;
  my $username = shift || $self->getUsername();
  my $gatewayAccount = shift || $self->getGatewayAccount();

  # usernames may not be deleted
  return 0;
}

sub setAccess {
  my $self = shift;
  my $directory_access = shift;
  
  my $login = new PlugNPay::Authentication::Login({
    login => $self->getUsername()
  });
  $login->setRealm('PNPADMINID');

  $login->setDirectories({
    directories => $directory_access
  });
}

sub getAccess {
  my $self = shift;
  
  my $login = new PlugNPay::Authentication::Login();
  $login->setRealm('PNPADMINID');

  my $result = $login->getLoginInfo({
    login => $self->getUsername()
  });
  if ($result) {
    my $loginInfo = $result->get('loginInfo');
    return $loginInfo->{'acl'};
  }
  
  die('failed to load login info from service');
}

sub addAccess {
  my $self = shift;
  my $dir = shift;

  my $login = new PlugNPay::Authentication::Login({
    login => $self->getUsername()
  });
  $login->setRealm('PNPADMINID');

  return $login->addDirectories({
    directories => [$dir]
  });
}

sub canAccess {
  my $self = shift;
  my $dir = shift;

  my $login = new PlugNPay::Authentication::Login();
  $login->setRealm('PNPADMINID');

  my $result = $login->getLoginInfo({
    login => $self->getUsername()
  });
  if ($result) {
    my $loginInfo = $result->get('loginInfo');
    return inArray($dir,$loginInfo->{'acl'});
  }
}

sub deleteAccess {
  my $self = shift;
  my $username = shift || $self->getUsername();
  my $dir = shift;

  my $login = new PlugNPay::Authentication::Login({
    login => $self->getUsername()
  });
  $login->setRealm('PNPADMINID');

  return $login->removeDirectories({
    directories => [$dir]
  });
}

sub setSubEmail {
  my $self = shift;
  my $email = shift;

  my $sanitize = new PlugNPay::Email::Sanitize();
  $email = $sanitize->sanitize($email);

  # the if the first fails don't update the second
  my $updatedService = $self->setSubEmailInService($email);
  
  if ($updatedService) {
    $self->setSubEmailInPnpMisc($email);
  }
}

sub setSubEmailInService {
  my $self = shift;
  my $email = shift;

  my $login = new PlugNPay::Authentication::Login({
    login => $self->getUsername()
  });
  $login->setRealm('PNPADMINID');

  return $login->setEmailAddress({
    emailAddress => $email
  });
}

sub getSubEmail {
  my $self = shift;
  my $username = shift || $self->getUsername();

  return $self->loadSubEmail($username);

  my $emailAddress = $self->loadSubEmail($username);

  my $sanitize = new PlugNPay::Email::Sanitize();
  $emailAddress = $sanitize->sanitize($emailAddress);

  return $emailAddress;
}

sub subEmailExists {
  my $self = shift;
  my $username = shift || $self->getUsername();
  my $dbh = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/SELECT count(username) as `exists`
                            FROM sub_email
                            WHERE username = ?/);
  $sth->execute($username) or die $DBI::ERRSTR;
  my $rows = $sth->fetchall_arrayref({});
  if($rows && $rows->[0]) {
    return $rows->[0]{'exists'};
  }
}

sub loadSubEmail {
  my $self = shift;
  my $username = shift || $self->getUsername();

  my $emailAddress = '';
  eval {
    $emailAddress = $self->loadSubEmailFromService($username);
  };

  if (!defined $emailAddress || $emailAddress eq '') {
    $emailAddress = $self->loadSubEmailFromPnpMisc($username);
  }

  return $emailAddress;
}

sub loadSubEmailFromService {
  my $self = shift;
  my $username = shift || $self->getUsername();

  my $login = new PlugNPay::Authentication::Login();
  $login->setRealm('PNPADMINID');

  my $result = $login->getLoginInfo({
    login => $username
  });

  my $emailAddress = '';
  if ($result) {
    my $loginInfo = $result->get('loginInfo');
    $emailAddress = $loginInfo->{'emailAddress'};
  }

  return $emailAddress;
}

sub loadSubEmailFromPnpMisc {
  my $self = shift;
  my $username = shift || $self->getUsername();

  my $emailAddress;

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc',q/
    SELECT email
    FROM sub_email
    WHERE username = ?
  /,[ $username ],{});
  if ($result->{'rows'}) {
    my $row = shift @{$result->{rows}};
    if (defined $row) {
      $emailAddress = $row->{'email'};
    }
  }

  return $emailAddress ||= '';
}

sub setSubEmailInPnpMisc {
  my $self = shift;
  my $email = shift;
  my $username = $self->getUsername();

  my $dbs = new PlugNPay::DBConnection();
  $dbs->begin('pnpmisc');

  my $sth = $dbs->prepare('pnpmisc',q/
    INSERT INTO sub_email
      (username, email)
    VALUES (?,?)
        ON DUPLICATE KEY UPDATE email = VALUES(email)
  /);
  $sth->execute($username, $email) or die $DBI::errstr;

  $self->changelog();

  $dbs->commit('pnpmisc');
}

sub deleteSubEmail {
  my $self = shift;
  my $username = shift || $self->getUsername();

  my $dbs = new PlugNPay::DBConnection();

  my $sth = $dbs->prepare('pnpmisc',q/
    DELETE FROM sub_email
     WHERE username = ?
  /);
  $sth->execute($username) or die $DBI::errstr;

  return 1;
}

sub saveUsername {
  my $self = shift;
  return $self->save(@_);
}

sub save {
  my $self = shift;
  # does nothing, all setters are instantaneous

  return 1;
}

# DO NOT USE THIS FUNCTION, use setPassword() and setTemporaryPasswordFlag(), then call save()
sub updateTempPassword {
  # I said don't use it!
}

sub saveAccess {
  my $self = shift;
  # does nothing, setters are instantaneous
}

sub savePasswordHistory {
  my $self = shift;
  # does nothing, handled by service
}

sub checkPasswordHistory {
  my $self = shift;
  # invalid function call
  die('password history checked by service upon setting password');
}

sub didLogIn {
  my $self = shift;
  # does nothing, handled by service
}

sub failedLogIn {
  my $self = shift;
  # does nothing, handled by service
}

sub _getLockedPrefix {
  return 'locked ';
}

sub lock {
  my $self = shift;
  # handled automatically by service when failure count is > 5
}

sub unlock {
  my $self = shift;
  # handled by service
}

sub exists {
  my $self = shift;
  my $loginUsername = shift || $self->getUsername();

  my $login = new PlugNPay::Authentication::Login();
  $login->setRealm('PNPADMINID');

  my $result = $login->getLoginInfo({
    login => $loginUsername
  });

  return $result;
}

sub load {
  my $self = shift;
  # does nothing, getters load from service
}

sub loadGroup {
  my $self = shift;
  # does nothing
}

sub loadACL {
  my $self = shift;
  # does nothing
}

sub setACL {
  my $self = shift;
  my $acl = shift;

  # alias for setAccess
  $self->setAccess($acl);
}

sub getACL {
  my $self = shift;

  # alias for getAccess
  return $self->getAccess();
}

sub deleteACL {
  my $self = shift;
  
  # alias for deleteAccess
  return $self->deleteAccess(@_);
}

sub setValuesFromHashRef {
  my $self = shift;
  # no longer needed
}

sub changelog {
  my $self = shift;
  # to be handled by service
}

### this likely need to be moved elsewhere, but applying it here for the time being...
sub setSubFeatures {
  my $self = shift;
  my $features = shift; # allow hashRef or legacy features string format

  if (ref($features) ne 'HASH' && $features ne '') { # try legacy features string format
    $features = $self->parseFeatures($features);
  }

  my $login = new PlugNPay::Authentication::Login({
    login => $self->getUsername() 
  });
  $login->setRealm('PNPADMINID');
  
  return $login->setFeatures({
    features => $features
  });

}

sub getSubFeatures {
  my $self = shift;
  
  my $login = new PlugNPay::Authentication::Login();
  $login->setRealm('PNPADMINID');

  my $result = $login->getLoginInfo({
    login => $self->getUsername()
  });
  if ($result) {
    my $loginInfo = $result->get('loginInfo');
    return $loginInfo->{'features'};
  }

  die('failed to load login info from service');
}

sub parseFeatures {
  my $self = shift;
  my $featureString = shift;

  my $subFeatures;
  my @array = split(/\,/,$featureString);
  foreach my $entry (@array) {
    my($name,$value) = split(/\=/,$entry);
    $subFeatures->{$name} = $value;
  }
  return $subFeatures;
}

sub saveSubFeatures {
  my $self = shift;
  # does nothing, setter is instantaneous
}

sub isSameSubFeaturesString {
  ## return true/false, if new sub-features string matches what's on file
  my $self = shift;
  # do nothing, unused
}

sub defaultRealmForLogin {
  my $login = shift;

  if ($login =~ /^mobi_/) {
    return 'MOBILECLIENT'
  } elsif ($login =~ /^rc_/) {
    return 'REMOTECLIENT'
  } 
  
  return 'PNPADMINID';
}

1;
