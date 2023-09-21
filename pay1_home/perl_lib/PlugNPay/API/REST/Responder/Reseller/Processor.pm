package PlugNPay::API::REST::Responder::Reseller::Processor;

use strict;

use PlugNPay::Processor;
use PlugNPay::Processor::Settings;
use PlugNPay::Processor::Settings::Options;

use base 'PlugNPay::API::REST::Responder';

sub _getOutputData {
  my $self = shift;

  my $shortName = $self->getResourceData()->{'processor'};

  if ($shortName) {
    my $data = {};

    my $processor = new PlugNPay::Processor({shortName => $shortName});
    my $processorFields = new PlugNPay::Processor::Settings($processor->getID());

    $data->{'shortName'} = $processor->getShortName();
    $data->{'name'} = $processor->getName();
    $data->{'type'} = lc $processor->getProcessorType();
    my $fields = $processorFields->getSettings();
    my @fieldOutput; 
    foreach ( sort { $a->{'displayOrder'} <=> $b->{'displayOrder'} } @{$fields} ){
      my $field = {
        id => $_->{'id'}, 
        required => $_->{'required'}, 
        settingName => $_->{'setting'}, 
        displayName => $_->{'displayName'},
        displayOrder => $_->{'displayOrder'}
      };

      if ($processorFields->getHasOptions($_->{'setting'})) {
        my $settingsOptions = new PlugNPay::Processor::Settings::Options();
        $settingsOptions->setSettingID($_->{'id'});
        my $options = $settingsOptions->getOptions();
        if (defined $options){
          $field->{'options'} = $options;
          $field->{'multipleOptions'} = $_->{'multipleOptions'};
        }
      }
      
      if ($_->{'display'}) {
        push @fieldOutput, $field;
      }
    }
    $data->{'settings'} = \@fieldOutput;
  
    $self->setResponseCode(200);
    return { processor => $data };
  } else {
    my $data = [];
    my $info = PlugNPay::Processor::processorList();
  
    foreach my $processor (@{$info}) {
      my $procData = {};
      $procData->{'shortName'} = $processor->{'shortName'};
      $procData->{'name'} = $processor->{'name'};
      $procData->{'type'} = $processor->{'type'};
      push @{$data},$procData;
    }
    $self->setResponseCode(200);
    return { processors => $data };
  }
}

1;
