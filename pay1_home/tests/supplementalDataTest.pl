#!/bin/env perl
use strict;
use lib $ENV{'PNP_PERL_LIB'};
use PlugNPay::Order::SupplementalData;
use PlugNPay::Logging::ApacheLogger;
use Data::Dumper;

my ($response,$supplementalData);

$supplementalData = new PlugNPay::Order::SupplementalData('');

my $data = {
  'items' => [
    {
    'merchant_id'       => 50,
    'order_id'          => "5BE5C2A035F27022E44411E88036AF6DC2518698765",
    'transaction_date'  => "2018-03-15T16:18:30Z",
    'supplemental_data' => {
      'aid'              => 'A00000000031010',
      'cvm'              => 'Signature',
      'tsi'              => 'E800',
      'application_name' => 'MASTERCARD',
      'testArray'        => [
          400,
          {
            'object'  => 1,
            'testing' => 'testing object inside array',
            3         => 'Fox'
          },
          [
            "trying again",
            500,
            12,
            {
              "Another one" => 55,
            }
          ]
        ]
    }
    }
  ]
};

## Insert data test ##

$response = $supplementalData->insertSupplementalData($data);

print Dumper($response);

# fixed for T1211
$response = $supplementalData->getSupplementalData({
  'orders' =>  [{
	         "merchant_id" =>  "1",
		 "order_ids" =>  [
                     '2019080614134200052',
                     '2019080614110200052'
		   ]
		}]   
});

print Dumper($response);

# fixed for T1211
$response = $supplementalData->getSupplementalData({
	'merchant_ids' => ['1'],
        'dates' => ['2019-08-01','2019-08-06']
});

print Dumper($response);

# new test, this works for T1211
$response = $supplementalData->getNormalizedSupplementalData({
        'merchant_ids' => ['1'],
        'dates' => ['2019-08-01','2019-08-06']
});

print Dumper($response);
