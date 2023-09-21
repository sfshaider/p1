#!/bin/env perl

use strict;

use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Reseller::Admin;
use PlugNPay::UI::HTML;
use PlugNPay::Processor;
use PlugNPay::Country;
use PlugNPay::Country::State;

my $resellerAdmin = new PlugNPay::Reseller::Admin();
my $template = $resellerAdmin->getTemplate();

# get head tags
my $headTagsTemplate = new PlugNPay::UI::Template();
$headTagsTemplate->setCategory('reseller/admin/merchants');
$headTagsTemplate->setName('index.head');

# get content template
my $contentTemplate = new PlugNPay::UI::Template();
$contentTemplate->setCategory('reseller/admin/merchants');
$contentTemplate->setName('index');

my $htmlBuilder = new PlugNPay::UI::HTML();

my $selectedCountry = 'US';

# set up country select options;
my $countryList = new PlugNPay::Country->getCountries();
my %countryOptions = map { $_->{'twoLetter'} => $_->{'commonName'} } @{$countryList};
my $countryOptionsHTML = $htmlBuilder->selectOptions({ selectOptions => \%countryOptions, selected => $selectedCountry });

# set up state select options:
my $stateList = new PlugNPay::Country::State->getStatesForCountry($selectedCountry);
my %stateOptions = map { $_->{'abbreviation'} => $_->{'commonName'} } @{$stateList};
my $stateOptionsHTML = $htmlBuilder->selectOptions({ selectOptions => \%stateOptions });

# get processors for each type
my %cardProcessors   = map { $_->{'shortName'} => $_->{'name'} } @{PlugNPay::Processor::processorList({ type => 'CARD',   display => 1})}; 
my %achProcessors    = map { $_->{'shortName'} => $_->{'name'} } @{PlugNPay::Processor::processorList({ type => 'ACH',    display => 1})}; 
my %tdsProcessors    = map { $_->{'shortName'} => $_->{'name'} } @{PlugNPay::Processor::processorList({ type => 'TDS',    display => 1})}; 
my %walletProcessors = map { $_->{'shortName'} => $_->{'name'} } @{PlugNPay::Processor::processorList({ type => 'WALLET', display => 1})}; 
my %emvProcessors    = map { $_->{'shortName'} => $_->{'name'} } @{PlugNPay::Processor::processorList({ type => 'EMV',    display => 1})}; 

# add "none" option
$cardProcessors{""} = 'None';
$achProcessors{""} = 'None';
$tdsProcessors{""} = 'None';
$walletProcessors{""} = 'None';
$emvProcessors{""} = 'None';

my @disabled = [''];

my $cardProcessorOptionsHTML   = $htmlBuilder->selectOptions({ selectOptions => \%cardProcessors, selected => '', first => '',disabled => \@disabled});
my $achProcessorOptionsHTML    = $htmlBuilder->selectOptions({ selectOptions => \%achProcessors, selected => '' , first => '',disabled => \@disabled});
my $tdsProcessorOptionsHTML    = $htmlBuilder->selectOptions({ selectOptions => \%tdsProcessors, selected => '' , first => '',disabled => \@disabled});
my $walletProcessorOptionsHTML = $htmlBuilder->selectOptions({ selectOptions => \%walletProcessors, selected => '', first => '',disabled => \@disabled});
my $emvProcessorOptionsHTML    = $htmlBuilder->selectOptions({ selectOptions => \%emvProcessors, selected => '' , first => '',disabled => \@disabled});

$contentTemplate->setVariable('companyCountryOptions',$countryOptionsHTML);
$contentTemplate->setVariable('companyStateOptions',$stateOptionsHTML);

$contentTemplate->setVariable('cardProcessorOptions',$cardProcessorOptionsHTML);
$contentTemplate->setVariable('achProcessorOptions',$achProcessorOptionsHTML);
$contentTemplate->setVariable('tdsProcessorOptions',$tdsProcessorOptionsHTML);
$contentTemplate->setVariable('walletProcessorOptions',$walletProcessorOptionsHTML);
$contentTemplate->setVariable('emvProcessorOptions',$emvProcessorOptionsHTML);

### Insert Content ###
$template->setVariable('headTags',$headTagsTemplate->render());
$template->setVariable('content',$contentTemplate->render());

my $html = $template->render();

print 'Content-type: text/html' . "\n\n";
print $html . "\n";

