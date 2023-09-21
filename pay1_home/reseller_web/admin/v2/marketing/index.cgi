#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::UI::Template;
use PlugNPay::Reseller::MarketingInfo;
use PlugNPay::Reseller::Admin;

my $marketingHead = new PlugNPay::UI::Template;
$marketingHead->setTemplate('/reseller/admin/MarketingInfo','marketing_info.head');

my $marketingInfo = new PlugNPay::Reseller::MarketingInfo;
my $content = $marketingInfo->buildPageHTML();

my $resellerAdmin = new PlugNPay::Reseller::Admin();
my $template = $resellerAdmin->getTemplate();

### Insert Content ###
$template->setVariable('title', 'Marketing Information');
$template->setVariable('headTags', $marketingHead->render());
$template->setVariable('content', $content);

my $html = $template->render();

print 'Content-type: text/html' . "\n\n";
print $html . "\n";
exit;
