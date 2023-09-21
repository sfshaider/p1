package PlugNPay::Reseller;

use strict;
use PlugNPay::Contact;
use PlugNPay::DBConnection;
use PlugNPay::GatewayAccount;
use PlugNPay::Logging::DataLog;
use JSON::XS;

use overload '""' => 'getResellerAccount';

sub new {
  my $self = {};
  my $class = shift;
  bless $self,$class;

  my $resellerAccount = shift;

  if($resellerAccount){
    $self->load($resellerAccount);
    $self->loadEmailData($resellerAccount);
  }

  return $self;
}

sub setResellerAccount {
  my $self = shift;
  my $accountName = lc shift;
  $accountName =~ s/[^a-z0-9]//g;
  $self->_setAccountData('username',$accountName);
}

sub getResellerAccount {
  my $self = shift;
  return $self->_getAccountData('username');
}

sub load {
  my $self = shift;
  my $accountName = shift;

  $self->setResellerAccount($accountName);

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
                  SELECT sellcore,sellcoremini,sellcoretran,sellmem,sellmemmini,sellmemtran,
                  buymem,username,name,addr1,addr2,city,state,zip,country,tel,fax,email,taxid,
                  status,password,salesagent,salescomm,monthlycomm,commlevel,comments,company,
                  trans_date,buycore,buycoremini,buycoretran,buymemmini,buymemtran,b_csetup,b_cmin,
                  b_ctran,b_rsetup,b_rmin,b_rtran,b_msetup,b_mmin,b_mtran,b_dsetup,b_dmin,b_dtran,b_fsetup,
                  b_fmin,b_ftran,s_csetup,s_cmin,s_ctran,s_rsetup,s_rmin,s_rtran,s_msetup,s_mmin,s_mtran,
                  s_dsetup,s_dmin,s_dtran,s_fsetup,s_fmin,s_ftran,overview,sendpwd,sendbillauth,retailflag,
                  b_asetup,b_amin,b_atran,s_amin,s_atran,b_cosetup,b_comin,b_cotran,s_cotran,premiumflag,
                  b_ctranmax,b_ctranex,exnumflag,s_ctranmax,s_ctranex,payallflag,b_lsetup,b_lmin,b_ltran,
                  s_lsetup,s_lmin,s_ltran,b_hrsetup,b_hrmin,b_hrtran,b_bpsetup,b_bpmin,b_bptran,s_bpmin,
                  s_bptran,referral,startdate,commissions,features
                  FROM salesforce
                  WHERE username = ?
  /);
  $sth->execute($self->getResellerAccount);
  my $row = $sth->fetchrow_hashref;
  $sth->finish();

  $self->{'rawAccountData'} = $row;
  my $features = $row->{'features'};
  $self->setRawFeatures($features);
}

sub save {
  my $self = shift;

  my $tableInfo = new PlugNPay::DBConnection()->getColumnsForTable({ database => 'pnpmisc', table => 'salesforce' });
  my @fields = keys %{$tableInfo};
  my @fieldValues = map { $self->_getAccountData($_) || '' } @fields; # No nulls, default to empty string
  my $fieldNamesString = join(',',map { $_ } @fields);
  my $insertPlaceholdersString = join(',',map { '?' } @fields);
  my $updateString = join(',',map { $_ . ' = ?' } @fields);

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $insert = 'INSERT INTO salesforce (' . $fieldNamesString . ') VALUES (' . $insertPlaceholdersString . ')';
  my $update = 'UPDATE salesforce SET ' . $updateString . ' WHERE username = ?';

  my $sth;
  if ($self->exists) {
    $sth = $dbh->prepare($update) or die($DBI::errstr);
    $sth->execute(@fieldValues, $self->getResellerAccount()) or die($DBI::errstr);
  } else {
    $sth = $dbh->prepare($insert) or die($DBI::errstr);
    $sth->execute(@fieldValues) or die($DBI::errstr);
  }
}

sub delete {
  # this MUST be called statically.
  my $username = shift;

  my $dbs = new PlugNPay::DBConnection();
  $dbs->executeOrDie('pnpmisc',q/
    DELETE FROM salesforce WHERE username = ?
  /,[$username]);

  PlugNPay::GatewayAccount::delete($username);
}

sub exists {
  my $self = shift;
  my $account = shift;

  if (!defined $account) {
    if (ref($self)) {
      $account = $self->getResellerAccount();
    } else {
      $account = $self;
    }
  }

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
    SELECT count(username) as `exists`
    FROM salesforce
    WHERE username = ?
  /);

  $sth->execute($account);

  my $results = $sth->fetchall_arrayref({});
  if ($results && $results->[0]) {
    return ($results->[0]{'exists'} == 1);
  }
  return 0;
}

sub list {
  my $self = shift;

  my $dbs = new PlugNPay::DBConnection();
  my $result = $dbs->fetchallOrDie('pnpmisc', q/
    SELECT username
    FROM salesforce
  /, [], {});

  my $rows = $result->{'result'};
  my @resellers = map { $_->{'username'} } @{$rows};
  return \@resellers;
}

sub getStartDate{
  my $self = shift;
  return $self->_getAccountData('startdate');
}

sub setStartDate {
  my $self = shift;
  $self->_setAccountData('startdate');
}

sub getMonthly {
  my $self = shift;
  my $payallflag = $self->_getAccountData('payallflag');

  if ($payallflag eq "1"){
    return $self->_getAccountData('b_cmin');
  }
  else {
    return $self->_getAccountData('s_cmin');
  }
}

sub getPerTran {
  my $self = shift;
  my $payallflag = $self->_getAccountData('payallflag');

  if ($payallflag eq "1"){
    return $self->_getAccountData('b_ctran');
  }
  else {
    return $self->_getAccountData('s_ctran');
  }

}

sub getPercent{
  my $self = shift;
  my $payallflag = $self->_getAccountData('payallflag');

  if ($payallflag eq "1"){
    return $self->_getAccountData('b_ctran');
  }
  else {
    return $self->_getAccountData('s_ctran');
  }
}

sub setSalesAgent{
  my $self = shift;
  $self->_getAccountData('salesagent',shift);
}

sub getSalesAgent{
  my $self = shift;
  return $self->_getAccountData('salesagent');
}

sub setPremiumFlag {
  my $self = shift;
  $self->_setAccountData('premiumflag',shift);
}

sub getPremiumFlag {
  my $self = shift;
  return $self->_getAccountData('premiumflag');
}

sub setExNumFlag {
  my $self = shift;
  $self->_setAccountData('exnumflag',shift);
}

sub getExNumFlag {
  my $self = shift;
  return $self->_getAccountData('exnumflag');
}

sub setRetailFlag {
  my $self = shift;
  $self->_setAccountData('retailflag',shift);
}

sub getRetailFlag {
  my $self = shift;
  return $self->_getAccountData('retailflag');
}

sub getTaxID {
  my $self = shift;
  return $self->_getAccountData('taxid');
}

sub setTaxID{
  my $self = shift;
  $self->_setAccountData('taxid',shift);
}

sub getPayAllFlag {
  my $self = shift;
  return $self->_getAccountData('payallflag');
}

sub setPayAllFlag {
  my $self = shift;
  $self->_setAccountData('payallflag',shift);
}

sub getCommissionsFlag {
  my $self = shift;
  return $self->_getAccountData('commissions');
}

sub setCommissionsFlag {
  my $self = shift;
  $self->_setAccountData('commissions',shift);
}

sub setSendBillAuth {
  my $self = shift;
  $self->_setAccountData('sendbillauth', shift);
}

sub getSendBillAuth {
  my $self = shift;
  return $self->_getAccountData('sendbillauth');
}

sub isReferral {
 my $self = shift;
 my $referralStatus = lc( $self->_getAccountData('referral'));
 if ( $referralStatus eq 'yes'){
   return 1;
 }
 else {
   return 0;
 }
}

sub getBuyRate {
  my $self = shift;

  return $self->_getAccountData('b_csetup');
}

sub infoList {
  my $self = shift;
  my $resellerListRef = shift || $self;

  my %info;

  if (@{$resellerListRef}) {
    my $placeholders = join(',',map { '?' } @{$resellerListRef});

    my $dbs = new PlugNPay::DBConnection();
    my $sth = $dbs->prepare('pnpmisc',q/
      SELECT username,company as name,status
        FROM customers
       WHERE username in (/ . $placeholders . q/)
    /);

    $sth->execute(@{$resellerListRef});

    my $result = $sth->fetchall_arrayref({});

    if ($result) {
      %info = map { $_->{'username'} => {name => $_->{'name'}, status => $_->{'status'}} } @{$result};
    }
  }

  return \%info;
}

sub merchantList {
  my $self = shift;
  my $options = shift || {};
  my $reseller = $self->getResellerAccount();

  my $pageLength = $options->{'pageLength'};
  my $pageNumber = $options->{'page'} || 0;
  my $offset = $pageNumber * $pageLength;

  # search handling
  my @whereValues;
  my $where = '';

  push @whereValues,$reseller;

  my $searchFieldColumnMap = {
    username => 'username',
    name => 'company',
    status => 'status',
    startDate => 'startdate'
  };

  foreach my $searchField (keys %{$searchFieldColumnMap}) {
    if (defined ($options->{'searchFields'}{$searchField})) {
      my $likeString = $options->{'searchFields'}{$searchField}{'text'};
      my $modifier = $options->{'searchFields'}{$searchField}{'modifier'};
      if ($modifier eq 'starts') {
        $likeString = $likeString . '%';
      } elsif ($modifier eq 'ends') {
        $likeString = '%' . $likeString;
      } elsif ($modifier eq 'contains') {
        $likeString = '%' . $likeString . '%';
      }
      push @whereValues,$likeString;
      $where .= ' AND ' . $searchFieldColumnMap->{$searchField} . ' LIKE ? ';
    }
  }

  my $limit = '';
  my @limitValues;
  if (defined $pageLength) {
    $limit = 'LIMIT ?,?';
    push @limitValues,$offset,$pageLength;
  }

  my %data;
  $data{'list'} = $self->_merchantList($where,$limit,\@whereValues,\@limitValues);
  $data{'pageLength'} = $pageLength;
  $data{'pageNumber'} = $pageNumber;
  $data{'count'} = $self->_merchantCount($where,\@whereValues);
  return \%data;
}

sub _merchantList {
  my $self = shift;
  my $where = shift;
  my $limit = shift;
  my $whereValues = shift;
  my $limitValues = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
	SELECT username, company as name, status, startdate as startDate
	FROM customers
	WHERE reseller = ?
	/ . $where . q/
	ORDER BY username ASC
        / . $limit . q/
  /) or die($DBI::errstr);

  $sth->execute(@{$whereValues},@{$limitValues}) or die($DBI::errstr);

  my $result = $sth->fetchall_arrayref({});

  my %list;
  if ($result) {
    foreach my $row (@{$result}) {
      my $startDate;
      if ($row->{'startDate'} =~ /^\d{8}$/) {
        $row->{'startDate'} =~ /(\d{4})(\d{2})(\d{2})/;
        $startDate = $1 . '-' . $2 . '-' . $3;
      } else {
        $startDate = '';
      }
      $list{$row->{'username'}} = {name => $row->{'name'}, status => $row->{'status'}, startDate => $startDate}
    }
  }
  return \%list;
}

sub _merchantCount {
  my $self = shift;
  my $where = shift;
  my $whereValues = shift;

  my $dbh = PlugNPay::DBConnection::connections()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
	SELECT COUNT(username) AS count
        FROM customers
        WHERE reseller = ?
        / . $where . q/
  /);

  $sth->execute(@{$whereValues});

  my $result = $sth->fetchall_arrayref({});
  if ($result) {
    return $result->[0]{'count'};
  }
  return 0;
}


sub setContactInfo {
  my $self = shift;
  my $contact = shift;

  $self->{'contact'} = $contact;
  $self->_setAccountData('name',$contact->getFullName());
  $self->_setAccountData('company',$contact->getCompany());
  $self->_setAccountData('addr1',$contact->getAddress1());
  $self->_setAccountData('addr2',$contact->getAddress2());
  $self->_setAccountData('city',$contact->getCity());
  $self->_setAccountData('state',$contact->getState());
  $self->_setAccountData('zip',$contact->getPostalCode());
  $self->_setAccountData('country',$contact->getCountry());
  $self->_setAccountData('tel',$contact->getPhone());
  $self->_setAccountData('fax',$contact->getFax());
  $self->_setAccountData('email',$contact->getEmailAddress());
}

sub getContactInfo {
  my $self = shift;
  my $contact = $self->{'contact'};

  if (!$contact) {
    $contact = new PlugNPay::Contact();
  }

  $contact->setFullName($self->_getAccountData('name'));
  $contact->setCompany($self->_getAccountData('company'));
  $contact->setAddress1($self->_getAccountData('addr1'));
  $contact->setAddress2($self->_getAccountData('addr2'));
  $contact->setCity($self->_getAccountData('city'));
  $contact->setCountry($self->_getAccountData('country'));
  $contact->setState($self->_getAccountData('state'));
  $contact->setPostalCode($self->_getAccountData('zip'));
  $contact->setPhone($self->_getAccountData('tel'));
  $contact->setFax($self->_getAccountData('fax'));
  $contact->setEmailAddress($self->_getAccountData('email'));

  return $contact;
}

sub loadEmailData {
  my $self = shift;
  my $resellerAccount = shift;

  $self->loadPrivateLabelData($resellerAccount);
}

# many of you feel bad for loadEmailData, that is because you crazy
# it has no feelings, and the new one is much better.
sub loadPrivateLabelData {
  my $self = shift;
  my $username = shift;
  if (!defined $username) {
    $username = $self->getResellerAccount();
  }

  $username = $self->usernameExists($username) ? $username : 'plugnpay';
  my $dbh = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbh->prepare(q/
                           SELECT username, commonname, email, emaildomain, admindomain, support_email, noreply_email, registration_email, subject_prefix_email, company
                           FROM privatelabel
                           WHERE username = ?
                           OR username = 'plugnpay'/);
  $sth->execute($username) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});

  my $usernameEmails = {};
  foreach my $row (@{$rows}) {
    $usernameEmails->{$row->{'username'}} = {
      'email_domain'         => $row->{'emaildomain'},
      'admin_domain'         => $row->{'admindomain'},
      'noreply_email'        => $row->{'noreply_email'},
      'support_email'        => $row->{'support_email'},
      'registration_email'   => $row->{'registration_email'},
      'subject_prefix_email' => $row->{'subject_prefix_email'},
      'email'                => $row->{'email'},
      'commonname'           => $row->{'commonname'},
      'company'              => $row->{'company'},
    };
  }

  $self->setCommonName($usernameEmails->{$username}{'commonname'} ? $usernameEmails->{$username}{'commonname'} : $usernameEmails->{'plugnpay'}{'commonname'});
  $self->setEmailDomain($usernameEmails->{$username}{'email_domain'} ? $usernameEmails->{$username}{'email_domain'} : $usernameEmails->{'plugnpay'}{'email_domain'});
  $self->setAdminDomain($usernameEmails->{$username}{'admin_domain'} ? $usernameEmails->{$username}{'admin_domain'} : $usernameEmails->{'plugnpay'}{'admin_domain'});
  $self->setRegistrationEmail($usernameEmails->{$username}{'registration_email'} ? $usernameEmails->{$username}{'registration_email'} : $usernameEmails->{'plugnpay'}{'registration_email'});
  $self->setNoReplyEmail($usernameEmails->{$username}{'noreply_email'} ? $usernameEmails->{$username}{'noreply_email'} : $usernameEmails->{'plugnpay'}{'noreply_email'});
  $self->setSupportEmail($usernameEmails->{$username}{'support_email'} ? $usernameEmails->{$username}{'support_email'} : $usernameEmails->{'plugnpay'}{'support_email'});
  $self->setPrivateLabelEmail($usernameEmails->{$username}{'email'} ? $usernameEmails->{$username}{'email'} : $usernameEmails->{'plugnpay'}{'email'});
  $self->setSubjectPrefixEmail($usernameEmails->{$username}{'subject_prefix_email'} ? $usernameEmails->{$username}{'subject_prefix_email'} : $usernameEmails->{'plugnpay'}{'subject_prefix_email'});
  $self->setPrivateLabelCompany($usernameEmails->{$username}{'company'} ? $usernameEmails->{$username}{'company'} : $usernameEmails->{'plugnpay'}{'company'});
}

sub setPrivateLabelCompany {
  my $self = shift;
  my $privateLabelCompany = shift;
  $self->{'privateLabelCompany'} = $privateLabelCompany;
}

sub getPrivateLabelCompany {
  my $self = shift;
  return $self->{'privateLabelCompany'};
}

sub getAdminDomainList {
  my $self = shift;
  my $dbs = new PlugNPay::DBConnection();
  my $data = [];
  eval {
     $data = $dbs->fetchallOrDie('pnpmisc',q/
      SELECT DISTINCT admindomain FROM privatelabel
    /, [], {});
  };

  if ($@) {
    my $logger = new PlugNPay::Logging::DataLog({collection => 'reseller'});
    $logger->log({message => $@});
  }

  my @domains = map { $_->{'admindomain'} } @{$data->{'result'}};

  return \@domains;
}

sub usernameExists {
  my $self = shift;
  my $username = shift;
  my $dbs = new PlugNPay::DBConnection()->getHandleFor('pnpmisc');
  my $sth = $dbs->prepare(q/
                          SELECT COUNT(username) AS usernameCount
                          FROM privatelabel
                          WHERE username = ?
  /);
  $sth->execute($username) or die $DBI::errstr;
  my $rows = $sth->fetchall_arrayref({});
  my $row = $rows->[0];
  if($row->{'usernameCount'}) {
    return 1;
  }
  return 0;
}

sub setSubjectPrefixEmail {
  my $self = shift;
  my $emailSubjectPrefix = shift;
  $self->{'subjectPrefixEmail'} = $emailSubjectPrefix;
}

sub getSubjectPrefixEmail {
  my $self = shift;
  return $self->{'subjectPrefixEmail'};
}

sub setEmailDomain {
  my $self = shift;
  my $emailDomain = shift;
  $self->{'emaildomain'} = $emailDomain;
}

sub getEmailDomain {
  my $self = shift;
  return $self->{'emaildomain'};
}

sub setAdminDomain {
  my $self = shift;
  my $admindomain = shift;
  $self->{'admindomain'} = $admindomain;
}

sub getAdminDomain {
  my $self = shift;
  return $self->{'admindomain'};
}

sub setPrivateLabelEmail {
  my $self = shift;
  my $privateLabelEmail = shift;
  $self->{'privateLabelEmail'} = $privateLabelEmail;
}

sub getPrivateLabelEmail {
  my $self = shift;
  return $self->{'privateLabelEmail'};
}

sub setRegistrationEmail {
  my $self = shift;
  my $registrationEmail = shift;
  $self->{'registrationEmail'} = $registrationEmail;
}

sub getRegistrationEmail {
  my $self = shift;
  return $self->{'registrationEmail'};
}

sub setNoReplyEmail {
  my $self = shift;
  my $noreplyEmail = shift;
  $self->{'noreplyEmail'} = $noreplyEmail;
}

sub getNoReplyEmail {
  my $self = shift;
  return $self->{'noreplyEmail'};
}

sub setSupportEmail {
  my $self = shift;
  my $supportEmail = shift;
  $self->{'supportEmail'} = $supportEmail;
}

sub getSupportEmail {
  my $self = shift;
  return $self->{'supportEmail'};
}

sub setCommonName {
  my $self = shift;
  my $commonName = shift;
  $self->{'commonName'} = $commonName;
}

sub getCommonName {
  my $self = shift;
  return $self->{'commonName'};
}

##############################
# Different buy rate getters #
##############################
sub getBuyRate_Direct{
  my $self = shift;
  return $self->_getAccountData('b_csetup');
}

sub getMonthly_Direct {
  my $self = shift;
  return $self->_getAccountData('b_cmin');
}

sub getPerTran_Direct {
  my $self = shift;
  return $self->_getAccountData('b_ctran');
}

sub getPerTranMax {
  my $self = shift;
  return $self->_getAccountData('b_ctranmax');
}

sub getPerTranExtra {
  my $self = shift;
  return $self->_getAccountData('b_ctranex');
}

sub getBuyRate_Level {
  my $self = shift;
  return $self->_getAccountData('b_lsetup');
}

sub getMonthly_Level {
  my $self = shift;
  return $self->_getAccountData('b_lmin');
}

sub getPerTran_Level{
  my $self = shift;
  return $self->_getAccountData('b_ltran');
}

sub getBuyRate_HighRisk {
  my $self = shift;
  return $self->_getAccountData('b_hrsetup');
}

sub getMonthly_HighRisk {
  my $self = shift;
  return $self->_getAccountData('b_hrmin');
}

sub getPerTran_HighRisk {
  my $self = shift;
  return $self->_getAccountData('b_hrtran');
}

sub getBuyRate_Recurring {
  my $self = shift;
  return $self->_getAccountData('b_rsetup');
}

sub getMonthly_Recurring {
  my $self = shift;
  return $self->_getAccountData('b_rmin');
}

sub getPerTran_Recurring {
  my $self = shift;
  return $self->_getAccountData('b_rtran');
}

sub getBuyRate_BillPres {
  my $self = shift;
  return $self->_getAccountData('b_bpsetup');
}

sub getMonthly_BillPres {
  my $self = shift;
  return $self->_getAccountData('b_bpmin');
}

sub getPerTran_BillPres {
  my $self = shift;
  return $self->_getAccountData('b_bptran');
}

sub getBuyRate_Membership {
  my $self = shift;
  return $self->_getAccountData('b_msetup');
}

sub getMonthly_Membership {
  my $self = shift;
  return $self->_getAccountData('b_mmin');
}

sub getPerTran_Membership {
  my $self = shift;
  return $self->_getAccountData('b_mtran');
}

sub getBuyRate_Digital {
  my $self = shift;
  return $self->_getAccountData('b_dsetup');
}

sub getMonthly_Digital {
  my $self = shift;
  return $self->_getAccountData('b_dmin');
}

sub getPerTran_Digital {
  my $self = shift;
  return $self->_getAccountData('b_dtran');
}

sub getBuyRate_Affiliate {
  my $self = shift;
  return $self->_getAccountData('b_asetup');
}

sub getMonthly_Affiliate {
  my $self = shift;
  return $self->_getAccountData('b_amin');
}

sub getPerTran_Affiliate {
  my $self = shift;
  return $self->_getAccountData('b_atran');
}

sub getBuyRate_FraudTrak {
  my $self = shift;
  return $self->_getAccountData('b_fsetup');
}

sub getMonthly_FraudTrak {
  my $self = shift;
  return $self->_getAccountData('b_fmin');
}

sub getPerTran_FraudTrak {
  my $self = shift;
  return $self->_getAccountData('b_ftran');
}

sub getBuyRate_Coupon {
  my $self = shift;
  return $self->_getAccountData('b_cosetup');
}

sub getMonthly_Coupon {
  my $self = shift;
  return $self->_getAccountData('b_comin');
}

sub getPerTran_Coupon {
  my $self = shift;
  return $self->_getAccountData('b_cotran');
}

sub setOverview {
  my $self = shift;
  my $overview = shift;

  if ($overview) {
    if (ref($overview) ne 'ARRAY') {
      $overview = [$overview];
      if ($self->getOverview()) {
        push @{$overview},$self->getOverview();
      }
    }

    $self->_setAccountData('overview',join('|',@{$overview}));
  }
}

sub addOverview {
  my $self = shift;
  my $overview = shift;
  my $data = $self->getOverviewArray();
  push @{$data},$overview;

  $self->setOverview($overview);
}


sub getOverview {
  my $self = shift;
  return $self->_getAccountData('overview');
}

sub getOverviewArray {
  my $self = shift;
  my @array = split('|',$self->getOverview());

  return \@array;
}

#####################
# Reseller Features #
#     It's JSON     #
#####################

sub setFeatures {
  my $self = shift;
  my $parsedFeatures = shift;
  my $features = '{}';
  eval {
    $features = encode_json($parsedFeatures);
  };

  $self->_setAccountData('features',$parsedFeatures);
  $self->{'rawFeatures'} = $features;
}

sub getFeatures {
  my $self = shift;
  return $self->_getAccountData('features');
}

sub setRawFeatures {
  my $self = shift;
  my $features = shift;
  my $parsedFeatures = {};
  eval {
    $parsedFeatures = decode_json($features);
  };

  $self->_setAccountData('features',$parsedFeatures);
  $self->{'rawFeatures'} = $features;
}

sub getRawFeatures {
  my $self = shift;
  return $self->{'rawFeatures'};
}

sub addFeature {
  my $self = shift;
  my $featureName = shift;
  my $featureValue = shift;
  my $features = $self->getFeatures();

  $features->{$featureName} = $featureValue;
  $self->setFeatures($features);
}

sub getFeature {
  my $self = shift;
  my $featureName = shift;

  return $self->getFeatures()->{$featureName};
}

###################
# Private methods #
###################
sub _setAccountData {
  my $self = shift;
  return if (ref($self) ne caller());
  my $key = shift;
  my $value = shift;
  $self->{'rawAccountData'}{$key} = $value;
}

sub _getAccountData {
  my $self = shift;
  return if (ref($self) ne caller());
  my $key = shift;
  return $self->{'rawAccountData'}{$key};
}
#######################
# End private methods #
#######################

1;
