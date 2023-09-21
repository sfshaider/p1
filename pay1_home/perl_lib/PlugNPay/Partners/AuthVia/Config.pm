package PlugNPay::Partners::AuthVia::Config;

use strict;
use PlugNPay::AWS::ParameterStore qw(getParameter);

################################## Config #########################################
#                                                                                 #
# This module, going forward, can be used for any special data needed for authvia #
#                                                                                 #
###################################################################################

our $_authViaMicroserviceURL;

sub getServiceURL {
  if (!$_authViaMicroserviceURL) {
    $_authViaMicroserviceURL = &PlugNPay::AWS::ParameterStore::getParameter('/SERVICE/AUTHVIA/WEBSOCKET/URL');
  }
  return $_authViaMicroserviceURL;
}

1;
