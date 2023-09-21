#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::API::REST::Documentation;
use Apache2::RequestUtil;

my $r;
eval {
  $r = Apache2::RequestUtil->request;
};

print 'content-type:text/html' . "\n\n"; 

if ($r) {
  my $doc = new PlugNPay::API::REST::Documentation();
  my $resource = $r->the_request;
  $resource =~ s/\/[\/]+/\//g;
  my @requestData = split(' ',$resource);
  if ($requestData[1] eq '/api/doc/') {
    $doc->setRootPath('/api');
    print $doc->responseCodes() . "\n";
  } else {
    my $resourceData = substr($requestData[1],length('/api/doc'));
    if ($resourceData =~ /\/$/) {
      chop($resourceData);
    }
    $doc->setResourcePath($resourceData);
    $doc->setRootPath('/api');
    print $doc->loadPage() . "\n";
  } 
}  else {
  print '<div>An Error Occurred</div>';
}

1;
