package PlugNPay::Reseller::Commissions;

use strict;
use PlugNPay::Reseller;
use PlugNPay::Sys::Time;
use PlugNPay::DBConnection;

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $reseller = shift;
  if (defined $reseller) {
    $self->setResellerAccount($reseller);
  }

  return $self;
}

sub setResellerAccount {
  my $self = shift;
  $self->{'reseller'} = shift;
}

sub getResellerAccount {
  my $self = shift;
  return $self->{'reseller'};
}

sub setStartDate {
  my $self = shift;
  my $year = shift;
  my $month = shift;
  if (length($month) < 2){
    $month = '0' . $month;
  }

  my $date = $year . $month . '01';
  $self->{'start_date'} = $date;
  
}

sub getStartDate {
  my $self = shift;
  return $self->{'start_date'};
}

sub setEndDate {
  my $self = shift;

  my $year = shift;
  my $month =  shift;
  if (length($month) < 2){
    $month = '0' . $month;
  }
  my $day = $self->getDays($month);

  my $date = $year . $month . $day;
  $self->{'end_date'} = $date;
}

sub getEndDate {
  my $self = shift;
  return $self->{'end_date'};
}

sub loadAccountInfo {
  my $self = shift;
  my $dbh = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $resellerAcct = shift;
  my $reseller = shift;
  my $sth;

  ###############################################
  # This code chunk was removed from main code! #
  # This way it will be easier to fix problems  # 
  ###############################################
 
  if ($resellerAcct =~ /^($reseller)$/) {
    $sth = $dbh->prepare(q/
        SELECT c.username,c.reseller,c.salescommission,c.monthlycommission,c.startdate,s.salesagent,c.transcommission,c.extracommission,c.monthly,c.extrafees
        FROM customers c,salesforce s
        WHERE (c.reseller IS NULL OR c.reseller <> ?)
        AND c.reseller=s.username
        ORDER BY s.salesagent,c.reseller,c.username
        /) or die "Can't prepare: $DBI::errstr";
    $sth->execute('plugnpay') or die "Can't execute: $DBI::errstr";
  } else {
    $sth = $dbh->prepare(q/
        SELECT username,reseller,salescommission,monthlycommission,startdate,transcommission,extracommission,monthly,extrafees
        FROM customers
        WHERE reseller=?
        ORDER BY username
        /) or die "Can't prepare: $DBI::errstr";
    $sth->execute($resellerAcct) or die "Can't execute: $DBI::errstr";
  }

  my $rows = $sth->fetchall_arrayref({});

  return $rows;
}

sub getCommissions {
  my $self = shift;
  my $output = {};
  my $time = new PlugNPay::Sys::Time();
  my $currentTime = $time->inFormat('yyyymmdd_gm');
  my $resellerAcct = $self->getResellerAccount();

  # use billingreport table or billingstatus table for this reseller
  my ($orderid,$trans_date,$amount,$paiddate,$descr,$trans_datestr,$monthlycommission,@salesarray,$years,$salescommission,$paiddatestr);
  my $paidamount = 0;
  my $myPaid = 0;

  # used to negate reseller query
  my $startdatestr = $self->getStartDate();
  my $enddatestr = $self->getEndDate();
  my $commission = 0;
  my $resellertotal = 0;
  my $resellercommission = 0;
  my $paidtotal = 0;
  my $commtotal = 0;
  my $resellerold = "";
  my $usernameold = "";
  
  # This code was directly ripped from reseller.pm (The bad one, not the good one)
  # I removed any output from this code, i.e. HTML prints

  # Most of this code is used to calculate remaining balance to be paid
  # So, most of it isn't used right now but could be necessary
  my $threeyearsago = $currentTime - 94608000; 
  my $twoyearsago = $currentTime - 63072000;

  ## Lets go on a magical voyage to the land of Resellers
  my $internalReseller = "karin|cprice|unplugged|michelle|barbara|scaldero|drew|scottm|jamest|mwilliams|dylaninc";
  my $rows = $self->loadAccountInfo($resellerAcct,$internalReseller);

  #For each user:
  foreach my $row (@$rows) {
    my $username = $row->{'username'};
    my $reseller = $row->{'reseller'};
    my $origsalescommission = $row->{'salescommission'};
    my $origmonthlycommission = $row->{'monthlycommission'};
    my $cstartdate = $row->{'startdate'};
    my $salesagent = $row->{'salesagent'};
    my $transcommission = $row->{'transcommission'};
    my $extracommission = $row->{'extracommission'};
    my $monthly_min = $row->{'monthly'};
    my $extrafees = $row->{'extrafees'};

    my $dbh = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
    my $sth = $dbh->prepare(q/
            SELECT orderid,trans_date,amount,paidamount,paiddate,descr
            FROM billingstatus
            WHERE username=? 
            AND trans_date>=? 
            AND trans_date<=? 
            AND result=? 
            AND (descr IS NULL OR descr NOT LIKE ?)
            ORDER BY trans_date
            /) or die "Can't prepare: $DBI::errstr";
    $sth->execute($username,$startdatestr,$enddatestr,'success','Return Fee%') or die "Can't execute: $DBI::errstr";
    my $results = $sth->fetchall_arrayref({});
    my $userdata = {};

    #Go Through each billing entry:
    foreach my $billing (@$results) {
      $commission = 0;
      my $orderid = $billing->{'orderid'};
      my $trans_date = $billing->{'trans_date'};
      my $amount = $billing->{'amount'};
      my $paidamount = $billing->{'paidamount'};
      my $paiddate = $billing->{'paiddate'};
      my $descr = $billing->{'descr'};

      $trans_datestr = sprintf("%02d/%02d/%04d",substr($trans_date,4,2), substr($trans_date,6,2), substr($trans_date,0,4));

      $paiddatestr = sprintf("%02d/%02d/%04d",substr($paiddate,4,2), substr($paiddate,6,2), substr($paiddate,0,4));

      $monthlycommission = $origmonthlycommission;

      if ($origsalescommission =~ /,/) {
        @salesarray = split(/,/,$origsalescommission);
        $years = substr($trans_date,0,4) - substr($cstartdate,0,4);
        $salescommission = $salesarray[$years];
      } else {
        $salescommission = $origsalescommission;
      }

      if (($reseller =~ /^(dmongell|wdunkak|smortens)$/) && ($cstartdate ne "")) {
        if ($cstartdate <= $threeyearsago) {
          # skip this customer totally
          $salescommission = .20;
          $monthlycommission = 0;
          $extracommission = 0;
        } elsif ($cstartdate <= $twoyearsago) {
          # lower comission to 15%
          $salescommission = .15;
          $monthlycommission = .15;
          $extracommission = .15;
        }
      }

      # actual calculation of commission
      if (($descr =~ /Monthly Billing/) && ($amount > 0)) {
        # if the amount paid is less than or equal to the monthly min
        # we calculate based on the monthly min commission
        if ((($amount <= $monthly_min) && ($monthly_min ne "")) || ($transcommission != 1)) {
          # if it's greater than 1 then it is a flat rate
          if ($monthlycommission >= 1) {
            $commission = $monthlycommission;
          } else {
          # if it's less than 1 then it's a percentage of the amount
            $commission = ($monthly_min - $extrafees) * $monthlycommission;
          }
        } else {
          # commission based on tran commission
          # flat commission for over monthly min uses per trans commission
          if ($transcommission >= 1) {
           $commission = $monthlycommission;
          } else {
          # otherwise it's a percentage
            $commission = ($amount - $extrafees) * $transcommission;
          }
        }

        if ($commission < $monthlycommission) {
          if ($monthlycommission >= 1) {
            $commission = $monthlycommission;
          } else {
            $commission = $monthly_min * $monthlycommission;
          }
        }

        # check to see if extra fee commission should be added
        if ($extrafees > 0) {
          # flat rate
          if ($extracommission >= 1) {
            $commission += $extracommission;
          } else {
            # percentage of extrafee
            $commission += $extrafees * $extracommission;
          }
        }
      } elsif (($descr =~ /Return Monthly Billing/) && ($amount < 0)) {
        if (($reseller =~ /^(dmongell|wdunkak|smortens)$/) && ($cstartdate <= $threeyearsago)) {
          # if Will or Donna, and older than 3 years, no return.
        } elsif ($monthlycommission >= 1) {
          #Fixed Fee Commission
          $commission -= $monthlycommission;
        } else {
          if ($transcommission == 0) {
            #Percentage Commission
            $commission -= ($monthly_min - $extrafees) * $monthlycommission;
          } else {
            # USe Trans Comm
            if ((-1*$amount) <= $monthly_min) {
              $commission = -1*(($monthly_min + $extrafees) * $monthlycommission);
            } else {
              $commission = ($amount + $extrafees) * $transcommission;
            }
          }
        }

        #Calculate Extra Fees
        if ($extrafees > 0) {
          if (($reseller =~ /^(dmongell|wdunkak|smortens)$/) && ($cstartdate <= $threeyearsago)) {
            # do nothing here in this case

          } elsif ($extracommission >= 1) {
            $commission -= $extracommission;

          } else {
            # percentage of extrafee
            $commission -= $extrafees * $extracommission;
          }
        }

      } elsif ($salescommission >= 1) {
        $commission = $salescommission;
        if ($amount < 0) {
          $commission = -$commission;
        }
      } elsif ($salescommission < 1) {
        $commission = $amount * $salescommission;
      } else {
        $commission = "";
      }

      $commission = sprintf("%.2f", $commission);

        if ($resellerAcct =~ /^($internalReseller)$/) {
          if ($reseller ne $resellerold) {
            $resellertotal = 0;
            $resellercommission = 0;
          }
          if ($paiddate eq "") {
            $resellertotal = $resellertotal + $amount;
            $resellercommission = $resellercommission + $commission;
          }

        }

        if (($resellerAcct =~ /^($internalReseller)$/) && ($paiddate eq "")) {
          if ($paidamount ne "") {
            $commtotal = $commtotal + $paidamount;
          } else {
            $commtotal = $commtotal + $commission;
          }
        } else {
          $time->fromFormat($paiddate,'yyyymmdd');
          $paiddatestr = $time->inFormat('unix');
          $paidtotal = $paidtotal + $paidamount;
        }
        $resellerold = $reseller;
        $usernameold = $username;

      #Properly format transdate
      my $newTransDate = substr($trans_date,4,2) . '/' . substr($trans_date,0,4);
      $paiddatestr = sprintf("%02d/%02d/%04d",substr($paiddate,4,2), substr($paiddate,6,2), substr($paiddate,0,4));

      #No payout date? Let's fix how that's displayed.
      if ($paiddatestr eq '00/00/0000') {
        $paiddatestr = 'N/A';
      }

      #Check payout amount, and cover all cases
      unless ($paidamount) {
        $paidamount = $commission;
        unless($paidamount) {
          $paidamount = 0;
        }
      }
  
      #format payout amount
      $paidamount = sprintf("%.2f",$paidamount);

      my $returnArr = { 'username' => $username, 'transdate' => $trans_datestr, 'amount' => $amount, 'descr' => $descr, 'commission' => $paidamount, 'paydate' => $paiddatestr, 'orderid' => $orderid};

      $userdata->{$orderid} = $returnArr;
      #Add this commission
    }
    
    #Add this user
    $output->{$username} = $userdata;
  }

  #send data
  my $superHash = { 'data' => $output, 'commtotal' => $commtotal, 'paidtotal' => $paidtotal };
  return $superHash;

}

#end of month getter
sub getDays {
  my $self = shift;
  my $month = shift;
  my $time = new PlugNPay::Sys::Time();
  
  return $time->getLastOfMonth($month);

}

1;
