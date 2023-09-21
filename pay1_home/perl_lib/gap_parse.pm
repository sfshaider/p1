#!/usr/local/bin/perl
$| = 1;

package gap_parse;

require 5.001;

#CheckOut Template
#www.gap.com

my %cardtype = ('Visa','01','Mastercard','02','Amex','03','Discover','04');

sub init {
  $input{'addurl'} = "ProductConfirm.asp";
  my @array = %input;
  return @array;
}


sub  checkout {
  my (%query,%products) = @_;
  foreach $key (keys %products) {
    &add(%query,$key,$products{$key})
  }
  &billing();
  &shipping();
  &checkout_remote();
}

#Add to Cart
sub add {
  my (%query,$quantity,$product) = @_;
  $input{'url'} = "http://www.gap.com/onlinestore/gapstore/ProductConfirm.asp";
  $input{'args'} = $query{'args'};
  $input{'attributes'} = $query{'attributes'};
  my @array = %input;
  return @array;
}

#Billing
sub billing {
  $input{'url'} = "https://www.gap.com/onlinestore/gapstore/Order-bill.asp";
  $input{'args'}=$query{'args'};
  $input{'POSTED'} = "TRUE";
  $input{'bill_fst_nm'} = $query{'card-fname'};
  $input{'bill_mid_ini'} = $query{'card-mname'};
  $input{'bill_lst_nm'} = $query{'card-lname'};
  $input{'bill_addr_ln1_txt'} = $query{'card-address1'};
  $input{'bill_addr_ln2_txt'} = $query{'card-address2'};
  $input{'bill_city_nm'} = $query{'card-city'};
  $input{'bill_st_prov_cd'} = $query{'card-state'};
  $input{'bill_addr_pstl_cd'} = $query{'card-zip'};
  $input{'dy_phn_nm'} = $query{'phone'};
  $input{'eml_id'} = $query{'email'};
  $input{'bill_ctry_nm'} = "USA";
  $input{'shipviastandard'} = "checked"
}

#Shipping Info
sub shipping {
  $input{'url'} = "https://www.gap.com/onlinestore/gapstore/order-ship.asp";
  $input{'args'} = "sid=$query{'sid'}";
  $input{'shp_ctry_nm'} = "USA";
  $input{'POSTED'} = "TRUE";
  $input{'ShipToCount'} = "1";
  $input{'NKNM0'} = "you";
  $input{'addr_typ_seq_nbr0'} = "0";
  $input{'shp_fst_nm0'} = $query{'fname'};
  $input{'shp_mid_ini0'} = $query{'mname'};
  $input{'shp_lst_nm0'} = $query{'lname'};
  $input{'shp_addr_ln1_txt0'} = $query{'address1'};
  $input{'shp_addr_ln2_txt0'} = $query{'address2'};
  $input{'shp_city_nm0'} = $query{'city'};
  $input{'shp_st_prov_cd0'} = $query{'state'};
  $input{'shp_addr_pstl_cd0'} = $query{'zip'};
  $input{'shp_phn_nm0'} = $query{'phone2'};
}

#MISC ...
#gift_cd0 00=no gift packaging, 01=unassembled Gap gift boxes, 02=premium gift box ($3.00 per box)
#GFT_RCPT_IND0'} = VALUE=CHECKED>include a gift receipt with this shipment
#GftMsg0'} = CHECKED include a gift message with this shipment
#spd_shp_tier_id 7=standard shipping & handling,S=overnight shipping & handling(continental U.S. street addresses only)
#DLVR_SIGN_RQM_IND'} = CHECKED select checkbox to require signature

#Check Out
sub checkout_remote {
  $input{'url'} = "https://www.gap.com/onlinestore/gapstore/Order-Summary.ASP";
  $input{'args'} = "sid=KGWX98UAUXS12G6B00A3H20T8BLV0GUB";
  $input{'POSTED'} = "TRUE";
  $input{'promo_code'} = "id=promo_codea";
  $input{'cc_cd'} = $conversion{$query{'card-type'}};
  $input{'cc_number'} = $query{'card-number'};
  $input{'month'} = $query{'exp-mo'};
  $input{'year'} = $query{'exp-year'};
}


