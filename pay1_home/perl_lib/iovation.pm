#!/usr/local/bin/perl

package iovation;

use strict;
use XML::Simple;
use XML::Writer;
use LWP::UserAgent;



sub check_transaction {
  my ($query,$subscriberid,$subscriberaccount,$subscriberpasscode) = @_;
  my (%result,%req,%error,$res,$resp);
  my $url = "https://ci-snare.iovation.com/api/CheckTransaction";
  my $output = "";
  my $agent = "SOAP::Lite/Perl/v0.710.8";
  my $contype = "text/xml";

  if ($$query{'iobb'} eq "") {
    return;
  }
  my $xml_request = XML::Writer->new(OUTPUT => \$output, NEWLINES => 0);
  
  $xml_request->xmlDecl("UTF-8");
  $xml_request->startTag('soap:Envelope',
              'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
              'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/',
              'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema',
              'soap:encodingStyle' => 'http://schemas.xmlsoap.org/soap/encoding/',
              'xmlns:soap' => 'http://schemas.xmlsoap.org/soap/envelope/');

  $xml_request->startTag('soap:Body');

  $xml_request->startTag('CheckTransaction',
                'xmlns' => "$url");

  $xml_request->startTag('subscriberref',
                'xsi:type' => 'xsd:string');
  $xml_request->characters('1');
  $xml_request->endTag('subscriberref');

  $xml_request->startTag('accountcode',
                'xsi:type' => 'xsd:string');
  $xml_request->characters("$$query{'username'}");
  $xml_request->endTag('accountcode');

  $xml_request->startTag('enduserip',
                'xsi:type' => 'xsd:string');
  $xml_request->characters("$$query{'ipaddress'}");
  $xml_request->endTag('enduserip');

  $xml_request->startTag('beginblackbox',
               'xsi:type' => 'xsd:string');
  $xml_request->characters("$$query{'iobb'}");
  $xml_request->endTag('beginblackbox');

  $xml_request->startTag('type',
                'xsi:type' => 'xsd:string');
  $xml_request->characters('default');
  $xml_request->endTag('type');

  $xml_request->startTag('subscriberid',
               'xsi:type' => 'xsd:string');
  $xml_request->characters("$subscriberid");
  $xml_request->endTag('subscriberid');

  $xml_request->startTag('subscriberaccount',
                'xsi:type' => 'xsd:string');
  $xml_request->characters("$subscriberaccount");
  $xml_request->endTag('subscriberaccount');

  $xml_request->startTag('subscriberpasscode',
                'xsi:type' => 'xsd:string');
  $xml_request->characters("$subscriberpasscode");
  $xml_request->endTag('subscriberpasscode');


  $xml_request->endTag('CheckTransaction');

  $xml_request->endTag('soap:Body');

  $xml_request->endTag('soap:Envelope');
  $xml_request->end;

  my $ua = new LWP::UserAgent;
  $ua->agent($agent);
  $ua->timeout(5);

  my $req = new HTTP::Request POST => $url;
  $req->content_type($contype);
  $req->content($output);

  my $res = $ua->request($req);

  if ($res->is_success) {
     $resp =  $res->content;
  }
  else {
    # handle a bad post here??
  }

  my(%res);

  open (IOVATE,">>/home/p/pay1/database/debug/iovation_debug.txt");
  print IOVATE "REQ:$output\n";
  print IOVATE "RESP:$resp\n\n";
  close(IOVATE);

  if ($resp =~ /xml version/i) {
    require XML::Simple;
    my $parser = XML::Simple->new();
    my $xmldoc = $parser->XMLin($resp);

    $res{'ioresult'} = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:CheckTransactionResponse'}->{'namesp1:result'}->{'content'};
    $res{'reason'} = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:CheckTransactionResponse'}->{'namesp1:reason'}->{'content'};;
    $res{'devicealias'} = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:CheckTransactionResponse'}->{'namesp1:devicealias'}->{'content'};;
    $res{'trackingnumber'} = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:CheckTransactionResponse'}->{'namesp1:trackingnumber'}->{'content'};;
    $res{'endblackbox'} = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:CheckTransactionResponse'}->{'namesp1:endblackbox'}->{'content'};;
  }

  return %res;

}

sub get_evidence {
  my ($query,$subscriberid,$subscriberaccount,$subscriberpasscode) = @_;
  my (%result,%req,%error,$res,$resp);
  my $url = "https://ci-snare.iovation.com/soap";
  my $output = "";
  my $agent = "SOAP::Lite/Perl/v0.710.8";
  my $contype = "text/xml";

#<message name="GetActiveEvidenceRequest">
#<part name="messageversion" type="xsd:string" />
#<part name="sequence" xsd:minOccurs="0" type="xsd:string" />
#<part name="subscriberid" type="xsd:string" />
#<part name="usercode" xsd:minOccurs="0" type="xsd:string" />
#<part name="devicealias" xsd:minOccurs="0" type="xsd:string" />
#<part name="adminusercode" type="xsd:string"/>
#</message>

  my $xml_request = XML::Writer->new(OUTPUT => \$output, NEWLINES => 0);
 
  $xml_request->xmlDecl("UTF-8");
  $xml_request->startTag('soap:Envelope',
              'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
              'xmlns:soapenc' => 'http://schemas.xmlsoap.org/soap/encoding/',
              'xmlns:xsd' => 'http://www.w3.org/2001/XMLSchema',
              'soap:encodingStyle' => 'http://schemas.xmlsoap.org/soap/encoding/',
              'xmlns:soap' => 'http://schemas.xmlsoap.org/soap/envelope/');

  $xml_request->startTag('soap:Body');

  $xml_request->startTag('GetActiveEvidenceRequest',
                'xmlns' => "$url");

  $xml_request->startTag('messageversion',
                'xsi:type' => 'xsd:string');
  $xml_request->characters('3.0');
  $xml_request->endTag('messageversion');

  $xml_request->startTag('sequence',
                'xsi:type' => 'xsd:string',
                'xsd:minOccurs' => '0');
  $xml_request->characters('1');
  $xml_request->endTag('sequence');

  $xml_request->startTag('subscriberid',
               'xsi:type' => 'xsd:string');
  $xml_request->characters("$subscriberid");
  $xml_request->endTag('subscriberid');

  $xml_request->startTag('usercode',
                'xsi:type' => 'xsd:string');
  $xml_request->characters("$$query{'username'}");
  $xml_request->endTag('usercode');

  $xml_request->startTag('devicealias',
               'xsi:type' => 'xsd:string');
  $xml_request->characters("$$query{'iobb'}");
  $xml_request->endTag('devicealias');

  ## Admin UserCode
  $xml_request->startTag('adminusercode',
                'xsi:type' => 'xsd:string');
  $xml_request->characters("$subscriberpasscode");
  $xml_request->endTag('adminusercode');


  $xml_request->endTag('GetActiveEvidenceRequest');

  $xml_request->endTag('soap:Body');

  $xml_request->endTag('soap:Envelope');
  $xml_request->end;

  my $ua = new LWP::UserAgent;
  $ua->agent($agent);
  $ua->timeout(5);

  my $req = new HTTP::Request POST => $url;
  $req->content_type($contype);
  $req->content($output);

  my $res = $ua->request($req);

  if ($res->is_success) {
     $resp =  $res->content;
  }
  else {
    # handle a bad post here??
  }

  my(%res);

  if ($resp =~ /xml version/i) {
    require XML::Simple;
    my $parser = XML::Simple->new();
    my $xmldoc = $parser->XMLin($resp);

    #<message name="GetActiveEvidenceResponse">
    #<part name="status" type="xsd:string" />
    #<part name="messageversion" type="xsd:string" />
    #<part name="sequence" xsd:nillable="true" type="xsd:string" />
    #<part name="evidencetypes" xsd:minOccurs="0" type="snare_types:evidenceListType" />
    #<evidencetypes>
    #<evidencetype>
    #<type xsi:type="xsd:string">1-4</type>
    #<description xsi:type="xsd:string">1-4 Return - NSF/ACH</description>
    #</evidencetype>
    #<evidencetype>
    #<type xsi:type="xsd:string">3-1</type>
    #<description xsi:type="xsd:string">3-1 Chat Abuse</description>
    #</evidencetype>
    #</evidencetypes>

    #</message>

    $res{'status'} = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:GetActiveEvidenceResponse'}->{'namesp1:status'}->{'content'};
    $res{'messageversion'} = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:GetActiveEvidenceResponse'}->{'namesp1:messageversion'}->{'content'};;
    $res{'sequence'} = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:GetActiveEvidenceResponse'}->{'namesp1:sequence'}->{'content'};;
    if (defined $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:GetActiveEvidenceResponse'}->{'namesp1:evidencetypes'}) {
      my ($type,$desc,$i);
      foreach my $key (keys %{$xmldoc->{'SOAP-ENV:Body'}->{'namesp1:GetActiveEvidenceResponse'}->{'namesp1:evidencetypes'}}) {
        $type = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:GetActiveEvidenceResponse'}->{'namesp1:evidencetypes'}->{'namesp1:evidencetype'}->{'type'}->{'content'};
        $desc = $xmldoc->{'SOAP-ENV:Body'}->{'namesp1:GetActiveEvidenceResponse'}->{'namesp1:evidencetypes'}->{'namesp1:evidencetype'}->{'description'}->{'content'};
        $res{'evidence'} .= "$type:$desc,";
      }
      chop $res{'evidence'};
    } # end defined product if
  }

  return %res;

}

1;
