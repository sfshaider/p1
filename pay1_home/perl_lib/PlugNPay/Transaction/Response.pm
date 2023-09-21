package PlugNPay::Transaction::Response;

use strict;

use PlugNPay::Util::Array;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  my $transaction = shift;
  $self->setTransaction($transaction);

  return $self;
}

sub setTransaction {
  my $self = shift;
  my $transaction = shift;

  $self->{'transaction'} = $transaction;
}

sub getTransaction {
  my $self = shift;
  return $self->{'transaction'};
}

sub setRawResponse {
  my $self = shift;
  my $responseHashRef = shift;
  $self->{'rawResponse'} = $responseHashRef;
  # convert legacy response info to new response object settings
  $self->setDuplicate($responseHashRef->{'Duplicate'});
  $self->setStatus($responseHashRef->{'FinalStatus'});
  $self->setErrorMessage($responseHashRef->{'MErrMsg'});
  $self->setFraudMessage($responseHashRef->{'FraudMsg'});
  $self->setFraudLogId($responseHashRef->{'fraudLogId'});
  $self->setReferenceNumber($responseHashRef->{'refnumber'} || $responseHashRef->{'processor_reference_id'});
}

sub _setResponseField {
  my $self = shift;
  my $field = shift;
  my $value = shift;
  $self->{'responseData'}{$field} = $value;
}

sub _getResponseField {
  my $self = shift;
  my $field = shift;
  return $self->{'responseData'}{$field};
}

sub setStatus {
  my $self = shift;
  my $status = shift;
  $self->_setResponseField('status',$status);
}

sub getStatus {
  my $self = shift;
  return $self->_getResponseField('status') || $self->_getResponseField('FinalStatus');
}

sub setErrorMessage {
  my $self = shift;
  my $errorMessage = shift || '';
  # $self->_setResponseField('errorMessage',$errorMessage);
  $self->setMessage($errorMessage);
}

sub getErrorMessage {
  my $self = shift;
  # because if it's successful, it is *not* an error message!
  return !inArray($self->getStatus(),['success','pending']) ? $self->_getResponseField('message') || '' : '';
}

sub setMessage {
  my $self = shift;
  my $message = shift || '';
  $self->_setResponseField('message',$message);
}

# legacy processors store approval responses in MErrMsg, which maps to errorMessage,
# so return that if message is not set.
sub getMessage {
  my $self = shift;
  return $self->_getResponseField('message') || '';
}

sub getAVSResponse {
  my $self = shift;
  return $self->{'rawResponse'}{'avs-code'};
}

sub setAVSResponse {
  my $self = shift;
  my $response = shift;

  $self->{'rawResponse'}{'avs-code'} = $response;
}

sub getSecurityCodeResponse {
  my $self = shift;
  return $self->{'rawResponse'}{'cvvresp'};
}

sub setSecurityCodeResponse {
  my $self = shift;
  my $response = shift;

  $self->{'rawResponse'}{'cvvresp'} = $response;
}

sub setPostAuthResponse {
  my $self = shift;
  my $postAuthResponse = shift;
  $self->{'postAuthResponse'} = $postAuthResponse;
}

sub getPostAuthResponse {
  my $self = shift;
  return $self->{'postAuthResponse'};
}

sub getAuthorizationCode {
  my $self = shift;
  my $authorizationCode = $self->{'rawResponse'}{'auth-code'};
  $authorizationCode = substr($authorizationCode,0,6);
  return $authorizationCode;
}

sub setAuthorizationCode {
  my $self = shift;
  my $code = shift;

  $self->{'rawResponse'}{'auth-code'} = $code;
}

sub getFraudMessage {
  my $self = shift;
  return $self->_getResponseField('fraudMessage') || {};
}

sub setFraudMessage {
  my $self = shift;
  my $fraudMessage = shift;
  $self->_setResponseField('fraudMessage',$fraudMessage);
}

sub getDuplicate {
  my $self = shift;
  return ($self->_getResponseField('duplicate') eq 'yes') ? 1 : 0;
}

sub setDuplicate {
  my $self = shift;
  my $duplicate = shift;
  $self->_setResponseField('duplicate',($duplicate ? 'yes' : ''));
}

sub setReferenceNumber {
  my $self = shift;
  my $refnumber = shift;

  $self->_setResponseField('refnumber', $refnumber);
}

sub getReferenceNumber {
  my $self = shift;
  return $self->_getResponseField('refnumber');
}

sub getFraudLogId {
  my $self = shift;
  return $self->_getResponseField('fraudLogId') || {};
}

sub setFraudLogId {
  my $self = shift;
  my $fraudLogId = shift;
  $self->_setResponseField('fraudLogId',$fraudLogId);
}

1;
