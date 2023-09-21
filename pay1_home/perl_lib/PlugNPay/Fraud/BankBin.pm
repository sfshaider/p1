package PlugNPay::Fraud::BankBin;

use strict;
use PlugNPay::DBConnection;

# convert this to use the database

# ardef VISA
# Icaxrf Mastercard

my %regionArdef = ('1','USA','2','CAN','3','EUR','4','AP','5','LAC','6','SAMEA');
my %regionIcaxrf = ('1','USA','A','CAN','B','LAC','C','AP','D','EUR','E','SAMEA');

my %debitFlag = ('D','DBT','C','CRD','F','CHK');

my %ardefProductType = ('A','ATM','B','VISA-BUSINESS','C','VISA-CLASSIC','D','VISA-COMMERCE','E','ELECTRON','F','Visa-Check-Card2','G','Visa-Travel-Money','H','Visa-Infinite','H','Visa-Sig-Preferred',
               'J','Visa-Platinum','K','Visa-Signature','L','VISA-PRIVATE-LABEL','M','MASTERCARD','O','V-Signature-Business','P','VISA-GOLD','Q','VISA-Proprietary','R','CORP-T-E',
               'S','PURCHASING','T','TRAVEL-VOUCHER','V','VPAY','X','RESERVED-FUTURE','B','VISA-BIZ','H','VISA-BUSINESS','S','VISA-BUSINESS','O','VISA-BUSINESS');

my %ardefProductID = ('A','VS-TRADITIONAL','AX','VS-AMEX','B','VS-TRAD-REWARDS','C','VS-SIGNATURE','D','VS-SIG-PREFERRED','DI','VS-DISCOVER','E','VS-RESERVED-E','F','VS-RESERVED-F','G','VS-BUSINESS',
                 'G1','VS-SIG-BUSINESS','G2','VS-BUS-CHECK-CARD','H','VS-CHECK-CARD','I','VS-COMMERCE','J','VS-RESERVED-J','J1','VS-GEN-PREPAID','J2','VS-PREPAID-GIFT','J3','VS-PREPAID-HEALTH',
                 'J4','VS-PREPAID-COMM','K','VS-CORPORATE','K1','VS-GSA-CORP-TE','L','VS-RESERVED-L','M','VS-MASTERCARD','N','VS-RESERVED-N','O','VS-RESERVED-O','P','VS-RESERVED-P','Q','VS-PRIVATE',
                 'Q1','VS-PRIV-PREPAID','R','VS-PROPRIETARY','S','VS-PURCHASING','S1','VS-PURCH-FLEET','S2','VS-GSA-PURCH','S3','VS-GSA-PURCH-FLEET','T','VS-INTERLINK','U','VS-TRAVELMONEY','V','VS-RESERVED-V');

my %icaxrfProductType = ('MCC','norm','MCE','electronic','MCF','fleet','MGF','fleet','MPK','fleet','MNF','fleet','MCG','gold','MCP','purchasing','MCS','standard','MCU','standard','MCW','world',
               'MNW','world','MWE','world-elite','MCD','MC-debit','MDS','MC-debit','MDG','gold-debit','TCG','gold-debit','MDO','other-debit','MDH','other-debit','MDJ','other-debit',
               'MDP','platinum-debit','MDR','brokerage-debit','MXG','x-gold-debit','MXO','x-other-debit','MXP','x-platinum-debit','TPL','x-platinum-debit','MXR','x-brokerage-debit',
               'MXS','x-standard-debit','MPP','prepaid-debit','MPL','platinum','MCT','platinum','PVL','private-label','MAV','activation','MBE','electronic-bus','MWB','world-bus',
               'MAB','world-elite-bus','MWO','world-corp','MAC','world-elite-corp','MCB','distribution-card','MDP','premium-debit','MDT','business-debit','MDH','debit-other','MDJ','debit-other2',
               'MDL','biz-debit-other','MCF','mid-market-fleet','MCP','mid-market-pruch','MCO','mid-market-corp','MCO','corp-card','MEO','large-market-exe','MDQ','middle-market-corp',
               'MPC','small-bus-card','MPC','small-bus-card','MEB','exe-small-bus-card','MDU','x-debit-unembossed','MEP','x-premium-debit','MUP','x-premium-debit-ue','MGF','gov-comm-card',
               'MPK','gov-comm-card-pre','MNF','pub-sec-comm-card','MRG','prepaid-consumer','MPG','db-prepd-gen-spend','MRC','prepaid-electronic','MRW','prepaid-bus-nonus','MEF','elect-pmt-acct',
               'MBK','black','MPB','pref-biz','DLG','debit-gold-delayed','DLH','debit-emb-delayed','DLS','debit-st-delayed','DLP','debit-plat-delayed','MCV','merchant-branded',
               'MPJ','debit-gold-prepaid','MRJ','gold-prepaid','MRK','comm-public-sector','TBE','elect-bus-debit','TCB','bus-debit','TCC','imm-debit','TCE','elect-debit','TCF','fleet-debit',
               'TCO','corp-debit','TCP','purch-debit','TCS','std-debit','TCW','signia-debit','TNF','comm-pub-sect-dbt','TNW','new-world-debit','TPB','pref-bus-debit');


sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  $self = {};
  bless $self,$class;

  my $cardNumber = shift;

  if ($cardNumber ne "") {
    if (($cardNumber =~ /^5/) && ($self->checkIcaxrf($cardNumber))) {
      # checked master card bin
    } elsif ($self->checkArdef($cardNumber)) {
      # checked other card bin
    }
    else {
      return undef;
    }
  } else {
    return undef;
  }

  return $self;
}

sub checkArdef {
  my $self = shift;
  my $cardNumber = shift;

  if ($cardNumber eq "") {
    return 0;
  }

  my $ardef_bin = substr($cardNumber,0,9);

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('fraudtrack');
  my $sth = $dbh->prepare(qq{
        select data
        from ardef
        where startbin<=?
        ORDER BY startbin DESC
        LIMIT 1
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute("$ardef_bin") or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  my ($ardef_data) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  # commented out code is for data that is there but not used
  #$self->{'bin_data'}{'end'} = substr($ardef_data,0,9);
  #$self->{'bin_data'}{'end'} =~ s/[^0-9]//g;
  #$self->{'bin_data'}{'start'} = substr($ardef_data,9,9);
  #$self->{'bin_data'}{'start'} =~ s/[^0-9]//g;

  $self->{'bin_data'}{'debitFlag'} = $debitFlag{substr($ardef_data,18,1)};
  $self->{'bin_data'}{'cardType'} =  substr($ardef_data,19,1);
  $self->{'bin_data'}{'region'} =  $regionArdef{substr($ardef_data,20,1)};
  $self->{'bin_data'}{'country'} =  substr($ardef_data,21,2);
  $self->{'bin_data'}{'productType'} = $ardefProductType{substr($ardef_data,23,1)};
  $self->{'bin_data'}{'productID'} = substr($ardef_data,24,2);
  if (exists $ardefProductID{$self->{'bin_data'}{'productID'}}) {
    $self->{'bin_data'}{'productID'} = $ardefProductID{$self->{'bin_data'}{'productID'}};
  }
  $self->{'bin_data'}{'chipCardFlag'} = substr($ardef_data,26,1);
  if ($self->{'bin_data'}{'productType'} =~ /prepaid/i) {
    $self->{'bin_data'}{'debitFlag'} = "PPD";
  }

  return 1;
}

sub checkIcaxrf {
  my $self = shift;
  my $cardNumber = shift;

  if ($cardNumber eq "") {
    return 0;
  }

  my $icaxrf_bin = substr($cardNumber,0,11) . "00000000000";
  $icaxrf_bin  = substr($icaxrf_bin,0,19);

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('fraudtrack');
  my $sth = $dbh->prepare(qq{
          select data
          from icaxrf
          where startbin<=?
          ORDER BY startbin DESC
          LIMIT 1
  }) or &miscutils::errmail(__LINE__,__FILE__,"Can't prepare: $DBI::errstr");
  $sth->execute($icaxrf_bin) or &miscutils::errmail(__LINE__,__FILE__,"Can't execute: $DBI::errstr");
  my ($icaxrf_data) = $sth->fetchrow;
  $sth->finish;
  $dbh->disconnect;

  # commented out code is parsing for data that is there but not used
  #$self->{'bin_data'}{'end'} = substr($icaxrf_data,0,19);
  #$self->{'bin_data'}{'end'} =~ s/[^0-9]//g;
  #$self->{'bin_data'}{'start'} = substr($icaxrf_data,19,19);
  #$self->{'bin_data'}{'start'} =~ s/[^0-9]//g;
  #$ica = substr($icaxrf_data,38,11);

  $self->{'bin_data'}{'region'} =  $regionIcaxrf{substr($icaxrf_data,49,1)};
  $self->{'bin_data'}{'country'} =  substr($icaxrf_data,50,3);

  #$electflg = substr($icaxrf_data,53,2);
  #$acquirer = substr($icaxrf_data,55,1);
  my $cardType = substr($icaxrf_data,56,3);
  #$mapping = substr($icaxrf_data,59,1);
  #$alm_part = substr($icaxrf_data,60,1);
  #$alm_date = substr($icaxrf_data,61,6);

  if ($cardType =~ /debit/i) {
    $self->{'bin_data'}{'debitFlag'} = "DBT";
  } elsif ($cardType  =~ /prepaid/i) {
    $self->{'bin_data'}{'debitFlag'} = "PPD";
  }

  $self->{'bin_data'}{'ProductType'} = $icaxrfProductType{$cardType};

  return 1;
}

sub getDebitFlag {
  my $self = shift;
  return $self->{'bin_data'}{'debitFlag'};
}

sub getCardType {
  my $self = shift;
  return $self->{'bin_data'}{'cardType'};
}

sub getRegion {
  my $self = shift;
  return $self->{'bin_data'}{'region'};
}

sub getCountry {
  my $self = shift;
  return $self->{'bin_data'}{'country'};
}

sub getProductType {
  my $self = shift;
  return $self->{'bin_data'}{'productType'};
}

sub getProductID {
  my $self = shift;
  return $self->{'bin_data'}{'productID'};
}

sub getChipCardFlag {
  my $self = shift;
  return $self->{'bin_data'}{'chipCardFlag'};
}

# ohno
# staticfunc?
sub getMatchedBinCountry {
  my $bin = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $select = q/
    SELECT country
      FROM master_bins
     WHERE binnumber = ?
  /;

  my $rows = [];
  eval {
    $rows = $dbs->fetchallOrDie('fraudtrack', $select, [$bin], {})->{'result'};
  };


  my $country = '';
  if (@{$rows} > 0) {
    $country = $rows->[0]{'country'};
  }

  return $country;
}


1;
