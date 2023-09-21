#!/bin/env perl

use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::UI::HTML;
use PlugNPay::Environment;
use PlugNPay::UI::Template;
use PlugNPay::Reseller::Admin;
use PlugNPay::Reseller::FAQ;
use PlugNPay::Reseller::Helpdesk;

my $htmlBuilder = new PlugNPay::UI::HTML();
my $faq = new PlugNPay::Reseller::FAQ();
my $env = new PlugNPay::Environment();
my %params = $env->getQuery('reseller_faq');
my $template = new PlugNPay::UI::Template('reseller/admin/help','index');
my $resellerAdmin = new PlugNPay::Reseller::Admin();
my $gatewayAccount = $env->get('PNP_USER');

####################################
# Below this point builds the page #
# It is done section by section    #
####################################
  
#Open Tickets
my $helpdesk = new PlugNPay::Reseller::Helpdesk($gatewayAccount);
my $data = $helpdesk->getTickets();
my @cols = ({'name'=>'Ticket','type'=>'string'},
            {'name'=>'Email','type'=>'string'},
            {'name'=>'Subject','type'=>'string'},
            {'name'=>'Status','type'=>'string'},
            {'name'=>'Replies','type'=>'string'},
            {'name'=>'View Ticket','type'=>'string'});

my $options = {'data' => $helpdesk->prepareForGoogleTable($data),'columns' => \@cols,id=>'myTicketTable'};
my $table = $htmlBuilder->buildTable($options);
my $ticketListTemplate = new PlugNPay::UI::Template('reseller/admin/help/index/','ticket_list');
$ticketListTemplate->setVariable('myTicketTable',$table);

#FAQ Area
my $faqAreaTemplate = new PlugNPay::UI::Template('reseller/admin/help/index/','faq');
my $sections = $faq->getSections();
my $sectionOptions = $htmlBuilder->selectOptions({ first => 'all', selected => 'all', selectOptions => $sections });
#my $searchDropdown = $FAQ->selectBuilder("<select name='searchDropdown' class='reseller-input-control'>\n",$sections);
$faqAreaTemplate->setVariable('sectionOptions',$sectionOptions);

#New Ticket Area
my $newTicketTemplate = new PlugNPay::UI::Template('reseller/admin/help/index/','new_ticket');
$newTicketTemplate->setVariable('pt_gateway_account',$gatewayAccount);
my $topic = { 1 => 'Support',
              2 => 'Accounting',
              4 => 'Billing Presentment',
              5 => 'Sales'};
$options = { 'selectOptions' => $topic, selected => '1'};

#Dealing with POST to page
if (defined $params{'ps_helpdesk_subject'} || defined $params{'ps_helpdesk_description'}){
  $newTicketTemplate->setVariable('showNewTicket','true');
  $newTicketTemplate->setVariable('helpdesk_subject',$params{'ps_helpdesk_subject'});
  $newTicketTemplate->setVariable('helpdesk_description',$params{'ps_helpdesk_description'});
  if ( defined $params{'ps_helpdesk_topic'} ){
    $options->{'selected'} = $params{'ps_helpdesk_topic'};
  } else {
    $options->{'selected'} = 1;
  }
}

#Finalizing New Ticket area
$newTicketTemplate->setVariable('topic_id', $htmlBuilder->selectOptions($options));

#build Template
$template->setVariable('pt_gateway_account',$gatewayAccount);
$template->setVariable('FAQSearchSection',$faqAreaTemplate->render());
$template->setVariable('myTicketArea',$ticketListTemplate->render());
$template->setVariable('helpdesk',$newTicketTemplate->render());

#build Header
my $headTagsTemplate = new PlugNPay::UI::Template('reseller/admin/help','index.head');

#Add to Main page frame!
my $mainTemplate = $resellerAdmin->getTemplate();
$mainTemplate->setVariable('content', $template->render());
$mainTemplate->setVariable('headTags', $headTagsTemplate->render());
my $html = $mainTemplate->render();

#####################################
# Our page is ready to be sent out  #
#####################################
print 'content-type:text/html',"\n\n";
print $html;

exit;
