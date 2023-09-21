package PlugNPay::Partners::AuthVia::Pending;

use strict;
use warnings FATAL => 'all';

use JSON::XS;
use PlugNPay::Die;
use PlugNPay::ResponseLink;
use PlugNPay::Transaction::JSON;

sub postTransactionToAuthViaService {
  my $input = shift;

  my $conversationId = $input->{'conversationId'} or die('conversationId is required');
  my $transaction = $input->{'transaction'} or die('transaction is required');

  if (!ref($transaction) eq 'PlugNPay::Transaction') {
    die('transaction is not a PlugNPay::Transaction object');
  }

  my $client = _getAuthViaPendingClient();
  my $content = _buildAuthViaRequestJson({
    conversationId => $conversationId, 
    transaction => $transaction
  });

  my $merchant = $transaction->getGatewayAccountName();


  _sendData({
    merchant => $merchant,
    client => $client,
    content => $content
  });

  my $statusCode = $client->getStatusCode();
  if ($statusCode ne '200') {
    datalog({
      "message" => "invalid response from authvia service",
      "conversationId" => $conversationId,
      "url" => $client->getRequestURL(),
      "statusCode" => $statusCode,
      "content" => $client->getResponseContent()
    });
    return 0;
  }

  return 1;
}

sub _getAuthViaPendingClient {
  my $rl = new PlugNPay::ResponseLink();
  my $urlPrefix = &PlugNPay::AWS::ParameterStore::getParameter('/SERVICE/AUTHVIA/URL');
  $rl->setRequestURL($urlPrefix . '/pending');
  $rl->setRequestMethod('POST');
  $rl->setRequestMode('DIRECT');
  return $rl;
}

sub _buildAuthViaRequestJson {
  my $input = shift;

  my $conversationId = $input->{'conversationId'} or die('conversationId is required');
  my $transaction = $input->{'transaction'} or die('transaction is required');

  if (!ref($transaction) eq 'PlugNPay::Transaction') {
    die('transaction is not a PlugNPay::Transaction object');
  }

  my $formatter = new PlugNPay::Transaction::JSON();
  my $transactionData = $formatter->transactionToJSON($transaction);

  # add authviaConversationId to the data
  $transactionData->{'authViaConversationId'} = $conversationId;

  my $jsonData = {
    transactions => {
      transaction1 => $transactionData
    }
  };

  my $json = encode_json($jsonData);

  return $json;
}

sub _sendData {
  my $input = shift;

  my $merchant = $input->{'merchant'} or die('merchant is required');
  my $client = $input->{'client'} or die('client is required');
  my $content = $input->{'content'} or die('content is required');

  datalog({
    "message" => "sending pending data to authvia service",
    "content" => $client->getResponseContent(),
    "url" => $client->getRequestURL(),
  });

  $client->addHeader('X-Gateway-Account',$merchant);
  $client->setRequestContentType('application/json');
  $client->setRequestData($content);
  my $response = $client->doRequest();
  return $response;
}

sub datalog {
  my $logData = shift || {};

  new PlugNPay::Logging::DataLog({'collection' => 'integrations'})->log({'partner' => 'authvia', 'logData' => $logData});
}

1;