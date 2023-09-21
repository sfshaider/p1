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
  my @request = split(' ',$resource);
  if ($request[1] eq '/admin/api/doc/') {
    $doc->setRootPath('/admin/api');
    print $doc->responseCodes();
  } else {
    my $resourceData = substr($request[1],length('/admin/api/doc'));

    if ($resourceData =~ /\/$/) {
      chop($resourceData);
    }

    $doc->setResourcePath($resourceData);
    $doc->setRootPath('/admin/api');
    print $doc->loadPage();
  } 
}  else {
  print '';
}

1;
