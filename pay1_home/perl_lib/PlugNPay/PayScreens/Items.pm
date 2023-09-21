package PlugNPay::PayScreens::Items;

use PlugNPay::UI::Template;
use POSIX;
use strict;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;

  return $self;
}

# Refactor this to use PlugNPay::Template;
sub generateItemHTML {
  my $self = shift;
  my $itemDataRef = shift;
  my $settings = shift;
  my $taxRate = $settings->{'taxRate'} || 0; # Default to no tax
  my $shippingCost = $settings->{'shippingCost'} || 0; # Default to no shipping
  my $display = $settings->{'display'} || 0; # default to not display
  my $precision = $settings->{'precision'} || 2;

  my $itemHeaderTemplate = new PlugNPay::UI::Template();
  $itemHeaderTemplate->setCategory('/payscreens/items/');
  $itemHeaderTemplate->setName('item_header');

  my $itemRowTemplate = new PlugNPay::UI::Template();
  $itemRowTemplate->setCategory('/payscreens/items/');
  $itemRowTemplate->setName('item_row');

  my $hiddenFieldTemplate = new PlugNPay::UI::Template();
  $hiddenFieldTemplate->setCategory('/payscreens/items/');
  $hiddenFieldTemplate->setName('item_hidden_field');

  my $tableRows = $itemHeaderTemplate->render();
  my $hiddenFields = '';

  my $calculatedData = $self->calculateCosts({taxRate => $taxRate, shippingCost=> $shippingCost, itemData => $itemDataRef, precision => $precision});

  foreach my $itemNumber (keys %{$calculatedData->{'items'}}) {
    my $identifier =   $calculatedData->{'items'}{$itemNumber}{'identifier'};
    my $cost =         $calculatedData->{'items'}{$itemNumber}{'cost'};
    my $quantity =     $calculatedData->{'items'}{$itemNumber}{'quantity'};
    my $description =  $calculatedData->{'items'}{$itemNumber}{'description'};
    my $taxable =      $calculatedData->{'items'}{$itemNumber}{'taxable'};
    my $extendedCost = $calculatedData->{'items'}{$itemNumber}{'extendedCost'};

    # build the html for the hidden fields
    foreach my $field (keys %{$calculatedData->{'items'}{$itemNumber}}) {
      $hiddenFieldTemplate->setVariable('fieldName',$field);
      $hiddenFieldTemplate->setVariable('fieldValue',$itemDataRef->{$field});
      $hiddenFieldTemplate->setVariable('itemNumber',$itemNumber);
      $hiddenFields .= $hiddenFieldTemplate->render();
      $hiddenFieldTemplate->reset();
    }

    $itemRowTemplate->setVariable('itemCost',$cost);
    $itemRowTemplate->setVariable('itemDescription',$description);
    $itemRowTemplate->setVariable('itemID',$identifier);
    $itemRowTemplate->setVariable('itemExtendedCost',$extendedCost);
    $itemRowTemplate->setVariable('itemQuantity',$quantity);

    $tableRows .= $itemRowTemplate->render();
    $itemRowTemplate->reset();
  }

  my $tableViewHTML = '<div id="itemizationSection" class="section">';
  $tableViewHTML   .= $tableRows . $hiddenFields;

  my $totalTemplate = '';
  $totalTemplate .= '	<div id="TOTALTYPE_total_row">' . "\n";
  $totalTemplate .= '		<span class="TOTALTYPE_total"></span>' . "\n";
  $totalTemplate .= '		<span class="TOTALTYPE_total_amount"><span class="currency_symbol"></span><span class="number">TOTALAMOUNT</span></span>' . "\n";
  $totalTemplate .= '	</div>' . "\n";

  my $totalExtendedCost = $calculatedData->{'totalExtendedCost'};;
  my $total = $calculatedData->{'total'};
  my $tax = $calculatedData->{'tax'};
  my $shipping = $calculatedData->{'shipping'};
  
  # create row for extended cost subtotal
  my $totalExtendedCostRow = $totalTemplate;
  $totalExtendedCostRow =~ s/TOTALTYPE/extended_cost/g;
  $totalExtendedCostRow =~ s/TOTALAMOUNT/$totalExtendedCost/;

  # create field for pt_subtotal based on calculations
  my $hiddenFieldsHTML .= qq{	<input type="hidden" name="pt_subtotal" id="pt_subtotal" value="$totalExtendedCost">};

  if (keys %{$calculatedData->{'items'}} > 0) {
    $hiddenFieldsHTML .= q|
	<script>
		jQuery('document').ready(function() {
			PayScreens.setInputValue('pt_transaction_amount','| . sprintf('%.2f',($total)) . q|');
			PayScreens.setInputValue('pt_tax_amount','| . sprintf('%.2f',($tax)) . q|');
			PayScreens.setInputValue('pt_shipping_amount','| . sprintf('%.2f',($shipping)) . q|');
	      });
	</script>
	|;
  }

  # create row for total tax subtotal
  my $totalTaxRow = $totalTemplate;
  $totalTaxRow =~ s/TOTALTYPE/tax/g;
  $totalTaxRow =~ s/TOTALAMOUNT/$tax/;

  # create row for shipping
  my $shippingRow = $totalTemplate;
  $shippingRow =~ s/TOTALTYPE/shipping/g;
  $shippingRow =~ s/TOTALAMOUNT/$shipping/g;

  # create row for grand total
  my $grandTotalRow = $totalTemplate;
  $grandTotalRow =~ s/TOTALTYPE/grand/g;
  $grandTotalRow =~ s/TOTALAMOUNT/$total/;

  # add the total rows to the html
  $tableViewHTML .= $totalExtendedCostRow;
  $tableViewHTML .= $totalTaxRow;
  $tableViewHTML .= $shippingRow;
  $tableViewHTML .= $grandTotalRow;

  # close up the table view
  $tableViewHTML .= '	<div style="clear: both"></div></div>' . "\n";

  my $html = '';

  if ($display) {
    $html .= $tableViewHTML;
  }

  $html .= $hiddenFieldsHTML;

  return $html;
}


sub calculateCosts {
  my $self = shift;
  my $data = shift;

  my $taxRate = $data->{'taxRate'} || 0;
  my $shippingCost = $data->{'shippingCost'} || 0;
  my $itemData = $data->{'itemData'};
  my $precision = $data->{'precision'} || 2;

  my $itemOutputData = {};

  my $totalExtendedCost = 0;
  my $totalTaxableCost = 0;
  my $tax = 0;
  my $total = 0;

  # get unique ending numbers from item data
  my @numbers = map { $_ =~ s/.*?(\d+)$/$1/; $_; } keys %{$itemData};
  my @uniqueNumbers = keys %{{map { $_ => 1 } @numbers}};

  foreach my $number (@uniqueNumbers) {
    my $identifier  = $itemData->{'pt_item_identifier_' . $number};
    my $cost        = sprintf('%.2f',abs($itemData->{'pt_item_cost_' . $number}));
    my $quantity    = int($itemData->{'pt_item_quantity_' . $number});
    my $description = $itemData->{'pt_item_description_' . $number};
    my $taxable     = ($itemData->{'pt_item_is_taxable_' . $number} eq 'yes' ||
                       !defined $itemData->{'pt_item_is_taxable_' . $number} ? 1 : 0);


    # if quantity is zero, skip it
    if (int($quantity) <= 0) {
      next;
    }

    my $extendedCost = sprintf('%.0' . $precision . 'f',$cost * $quantity);

    $totalExtendedCost += $extendedCost;

    if ($taxable) {
      $totalTaxableCost += $extendedCost;
    }

    # populate output data
    $itemOutputData->{'items'}{$number} = { 
      identifier => $identifier, 
      cost => $cost, 
      extendedCost => $extendedCost, 
      quantity => $quantity, 
      description => $description, 
      is_taxable => $taxable
    };
  }

  my $totalTax = $totalTaxableCost * $taxRate;
  my $totalTaxIntegerPortion = int($totalTax);
  my $totalTaxFloatPortion = sprintf('%0.2f',(ceil(($totalTax - $totalTaxIntegerPortion) * 100)) / 100);

  $itemOutputData->{'totalExtendedCost'} = sprintf('%.0' . $precision . 'f',$totalExtendedCost);
  $itemOutputData->{'totalTaxableCost'}  = sprintf('%.0' . $precision . 'f',$totalTaxableCost);
  $itemOutputData->{'tax'}   = sprintf('%.0' . $precision . 'f',$totalTaxIntegerPortion + $totalTaxFloatPortion);
  $itemOutputData->{'shipping'} = sprintf('%.0' . $precision . 'f',$shippingCost);
  $itemOutputData->{'total'} = sprintf('%.0' . $precision . 'f',$totalExtendedCost + $itemOutputData->{'tax'} + $shippingCost);
  
  return $itemOutputData;
}


1;
