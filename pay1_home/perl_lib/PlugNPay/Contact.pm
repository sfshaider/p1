package PlugNPay::Contact;

use strict;
use PlugNPay::DBConnection;
use PlugNPay::Country;
use PlugNPay::Country::State;
use PlugNPay::Email::Sanitize;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  $self->{'errors'} = {};
  return $self;
}

sub setFirstName {
  my $self = shift;
  $self->_setInfo('firstName',shift || '');
  $self->_updateName();
}

sub getFirstName {
  my $self = shift;
  return $self->_getInfo('firstName');
}

sub setLastName {
  my $self = shift;
  $self->_setInfo('lastName',shift || '');
  $self->_updateName();
}

sub getLastName {
  my $self = shift;
  return $self->_getInfo('lastName');
}

sub _updateName {
  my $self = shift;
  $self->_setInfo('name',$self->_getInfo('firstName') . ' ' . $self->_getInfo('lastName'));
}

sub getFullName {
  my $self = shift;
  return $self->_getInfo('name') || $self->getFirstName() . ' ' . $self->getLastName();
}

sub setFullName {
  my $self = shift;
  my $name = shift;
  $self->_setInfo('name',$name);
}

sub getName {
  my $self = shift;
  return $self->_getInfo('name');
}

sub setCompany {
  my $self = shift;
  my $company = shift;
  $self->_setInfo('company',$company);
}

sub getCompany {
  my $self = shift;
  return $self->_getInfo('company');
}

sub setAddress1 {
  my $self = shift;
  $self->_setInfo('address1',shift || '');
}

sub getAddress1 {
  my $self = shift;
  return $self->_getInfo('address1');
}

sub setAddress2 {
  my $self = shift;
  $self->_setInfo('address2',shift || '');
}

sub getAddress2 {
  my $self = shift;
  return $self->_getInfo('address2');
}

sub setCity {
  my $self = shift;
  $self->_setInfo('city',shift || '');
}

sub getCity {
  my $self = shift;
  $self->_getInfo('city');
}

sub setState {
  my $self = shift;
  my $state = shift;
  $self->_setInfo('state/province',$state);
}

sub getState {
  my $self = shift;
  $self->_getInfo('state/province');
}

sub setProvince {
  my $self = shift;
  $self->setState(shift);
}

sub getProvince {
  my $self = shift;
  $self->getState(shift);
}

sub setInternationalProvince {
  my $self = shift;
  $self->_setInfo('internationalProvince',shift || '');
}

sub getInternationalProvince {
  my $self = shift;
  $self->_getInfo('internationalProvince');
}

sub setPostalCode {
  my $self = shift;
  my $postalCode = shift || '';
  $self->_setInfo('postalCode',$postalCode);
}

sub getPostalCode {
  my $self = shift;
  $self->_getInfo('postalCode');
}

sub setCountry {
  my $self = shift;
  my $code = shift;

  # this converts a three letter code to a two letter code
  my $country = new PlugNPay::Country($code);
  $code = $country->getTwoLetter();

  if ($code) {
    $self->_setInfo('country',$code);
    $self->{'errors'}{'Country'} = 0;
  } else {
    $self->{'errors'}{'Country'} = 1;
  }
}

sub getCountry {
  my $self = shift;
  $self->_getInfo('country');
}

sub setEmailAddress {
  my $self = shift;
  my $emailAddress = shift;
  my $type = shift || 'main';

  my $sanitize = new PlugNPay::Email::Sanitize();
  $emailAddress = $sanitize->sanitize($emailAddress);

  my $emails = $self->_getInfo('emailAddresses');

  if (!defined $emails) {
    $emails = {};
  }

  $emails->{$type} = $emailAddress;

  $self->_setInfo('emailAddresses',$emails);
}

sub getEmailAddress {
  my $self = shift;
  my $type = shift || 'main';

  if (!defined $self->_getInfo('emailAddresses')) {
    $self->_setInfo('emailAddresses',{});
  }

  $self->_getInfo('emailAddresses')->{$type};
}

sub setDayPhone {
  my $self = shift;
  $self->_setInfo('dayPhone',shift || '');
}

sub setPhone {
  my $self = shift;
  $self->setDayPhone(shift);
}

sub getPhone {
  my $self = shift;
  return $self->getDayPhone();
}

sub getDayPhone {
  my $self = shift;
  $self->_getInfo('dayPhone');
}

sub setEveningPhone {
  my $self = shift;
  $self->_setInfo('eveningPhone',shift || '');
}

sub getEveningPhone {
  my $self = shift;
  $self->_getInfo('eveningPhone');
}

sub setFax {
  my $self = shift;
  $self->_setInfo('fax',shift || '');
}

sub getFax {
  my $self = shift;
  $self->_getInfo('fax');
}

sub getErrors {
  my $self = shift;
  my $fieldName = lc shift;

  if ($fieldName eq 'all') {
    my $errors = 0;
    foreach my $error (keys %{$self->{'errors'}}){
      $errors += $self->{'errors'}{$error};
    }
    return $errors;
  } else {
    return $self->{'errors'}{$fieldName};
  }

}

### SPECIAL NOTE : COMPATIBILITY METHODS ####################################################################
# The following two methods are for backwards compatibility, since we store evening phone OR fax, not both. #
#############################################################################################################
sub setEveningPhoneOrFax {
  my $self = shift;
  $self->setEveningPhone(shift);
}

sub getEveningPhoneOrFax {
  my $self = shift;
  return $self->getEveningPhone() || $self->getFax();
}
#############################################################################################################
# END OF COMPATIBILITY METHODS ##############################################################################
#############################################################################################################

sub toHash {
  my $self = shift;
  return %{$self->{'info'}};
}

sub _setInfo {
  my $self = shift;
  my $key = shift;
  my $val = shift;
  $self->{'info'}{$key} = $val;
}

sub _getInfo {
  my $self = shift;
  my $key = shift;
  return $self->{'info'}{$key};
}

# country should always/only be set using the two letter or three letter code.
sub checkCountries {
  my $self = shift;
  my $country = shift;

  my $countryObj = new PlugNPay::Country();
  return $countryObj->exists($country);
}

sub checkState {
  my $self = shift;
  my $state = shift;

  my $stateObj = new PlugNPay::Country::State();
  $stateObj->setState($state);
  $stateObj->setName($state);

  return $stateObj->exists();
}

1;
