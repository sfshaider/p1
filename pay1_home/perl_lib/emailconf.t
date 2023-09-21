#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 50;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

require_ok('emailconf');

# set up mocking for tests
my $mock = Test::MockObject->new();

# Mock PlugNPay::DBConnection
my $noQueries = sub {
  print STDERR new PlugNPay::Util::StackTrace()->string("\n") . "\n";
  die('unexpected query executed')
 };
my $dbsMock = Test::MockModule->new('PlugNPay::DBConnection');
$dbsMock->redefine(
'executeOrDie' => $noQueries,
'fetchallOrDie' => $noQueries
);

my $emailconfMock = Test::MockModule->new('emailconf');

# updateRuleDb()
eval {
  my %updatedFields;
  my %whereFields;
  # redefined executeOrDie to test updateRuleDb()
  $dbsMock->redefine(
  'executeOrDie' => sub {
    my (undef,$database,$query,$values) = @_;
    $query =~ s/\n/ /g;

    # get fields being updated
    $query =~ /set\s+(.*)\s+where/i;
    my @fields = map { $_ =~ s/\s*=.*//g; $_ } split(',',$1);
    %updatedFields = map { $_ => shift @{$values} } @fields;

    # get where values
    # this isn't perfect but it works for the test
    $query =~ /where (.*)/i;
    my $wheres = $1;
    $wheres =~ s/\s*(AND|OR)\s*//ig;
    my @wheres = split(/\s*=\s*\?\s*/,$wheres);
    %whereFields = map { $_ => shift @{$values} } @wheres;
  }
  );

  my $inputValues = {
    emailType => 'emailType value',
    delay => 'delay value',
    include => 'include value',
    exclude => 'exclude value',
    description => 'description value',
    contentType => 'contentType value',
    content => 'content value',
    emailId => 'emailId value',
    gatewayAccount => 'gatewayAccount value'
  };

  emailconf::updateEmailDb($inputValues);

  is($updatedFields{'type'},$inputValues->{'emailType'},'updateRuleDb(): correct value is inserted for emailType => type');
  is($updatedFields{'delay'},$inputValues->{'delay'},'updateRuleDb(): correct value is inserted for delay => delay');
  is($updatedFields{'include'},$inputValues->{'include'},'updateRuleDb(): correct value is inserted for include => include');
  is($updatedFields{'exclude'},$inputValues->{'exclude'},'updateRuleDb(): correct value is inserted for exclude => exclude');
  is($updatedFields{'description'},$inputValues->{'description'},'updateRuleDb(): correct value is inserted for description => description');
  is($updatedFields{'emailtype'},$inputValues->{'contentType'},'updateRuleDb(): correct value is inserted for contentType => emailtype');
  is($updatedFields{'data'},$inputValues->{'content'},'updateRuleDb(): correct value is inserted for content => data');
  is($whereFields{'body'},$inputValues->{'emailId'},'updateRuleDb(): correct value is inserted for emailId => body');
  is($whereFields{'username'},$inputValues->{'gatewayAccount'},'updateRuleDb(): correct value is inserted for gatewayAccount => username');

  # delete the gatewayAccount input to check that an error is thrown when gatewayAccount is not sent
  my %inputValuesNoGatewayAccount = %{$inputValues};
  delete $inputValuesNoGatewayAccount{'gatewayAccount'};
  throws_ok( sub {
    emailconf::updateEmailDb(\%inputValuesNoGatewayAccount);
  }, qr/gatewayAccount is required/, 'updateRuleDb(): error is thrown when gatewayAccount not sent');

  # delete the emailType input to check that an error is thrown when gatewayAccount is not sent
  my %inputValuesNoEmailType = %{$inputValues};
  delete $inputValuesNoEmailType{'emailType'};
  throws_ok( sub {
    emailconf::updateEmailDb(\%inputValuesNoEmailType);
  }, qr/emailType is required/, 'updateRuleDb(): error is thrown when emailType not sent');

  # delete the emailId input to check that an error is thrown when gatewayAccount is not sent
  my %inputValuesNoEmailId = %{$inputValues};
  delete $inputValuesNoEmailId{'emailId'};
  throws_ok( sub {
    emailconf::updateEmailDb(\%inputValuesNoEmailId);
  }, qr/emailId is required/, 'updateRuleDb(): error is thrown when emailId not sent');

  # delete the content input to check that an error is thrown when gatewayAccount is not sent
  my %inputValuesNoContent = %{$inputValues};
  delete $inputValuesNoContent{'content'};
  throws_ok( sub {
    emailconf::updateEmailDb(\%inputValuesNoContent);
  }, qr/content is required/, 'updateRuleDb(): error is thrown when content not sent');
};
print $@ if $@;

# revert executeOrDie to $noQueries
$dbsMock->redefine(
'executeOrDie' => $noQueries
);


# calculateEmailData()
eval {
  my $input = {
    templateType => 'marketing',
    timeUnit => 'day',
    timeUnitQuantity => 0,
    subject => 'witty subject here',
    otherFields => {
      srchlowamt => 'how do you pronounce this',
      filelink => 'is this required?',
      weightamt => '1000',
      weightzip => 12345
    },
    tests => {
      what => '5',
      name => 'cost',
      type => 'gt'
    },
    all => 'no'
  };
  my $res = emailconf::calculateEmailData($input);
  like($res->{'emailInclude'},qr/"subject=$input->{'subject'}"/,'subject gets set in emailinclude for marketing email');
  like($res->{'emailInclude'},qr/"srchlowamt=how do you pronounce this"/,'a srch field gets set in emailinclude for marketing'); # what is a srch field?
  is($res->{'emailWeight'},'"weightamt=1000","weightzip=12345"','emailWeight is correct for marketing email');
  like($res->{'emailDelay'},qr/,$input->{'timeUnit'}/,'emailDelay time unit is set for marketing email');
  like($res->{'emailDelay'},qr/$input->{'timeUnitQuantity'}/,,'emailDelay time unit quantity is set for marketing email');
  is($res->{'emailType'},'mark','emailType is set to mark for marketing email');
  is($res->{'emailExclude'},'none','emailExclude is none for marketing email');

  $input = {
    templateType => 'confirmation',
    timeUnit => 'day',
    timeUnitQuantity => 0,
    subject => 'witty subject here',
    otherFields => {
      srchlowamt => 'how do you pronounce this',
      filelink => 'is this required?'
    },
    tests => {
      what => '5',
      name => 'cost',
      type => 'gt'
    }
  };
  $res = emailconf::calculateEmailData($input);

  is($res->{'emailInclude'},'5:gt:cost:witty subject here','emailInclude is correct for confirmation email');
  is($res->{'emailExclude'},'none','emailExclude is none for confirmation email');
  is($res->{'emailWeight'},'','emailWeight is empty string for confirmation email');
  like($res->{'emailDelay'},qr/,none/,'emailDelay time unit is none for confirmation email');
  like($res->{'emailDelay'},qr/$input->{'timeUnitQuantity'}/,,'emailDelay time unit quantity is 0 for confirmation email');
  is($res->{'emailType'},'conf','emailType is set to mark for confirmation email');

  $input = {
    templateType => 'merchant'
  };
  $res = emailconf::calculateEmailData($input);
  is($res->{'emailType'},'merch','emailType is set to merch for merchant email');


};
print $@ if $@;

# updateEmail()
eval {
  $emailconfMock->redefine(
  'updateEmailDb' => sub {
    return;
  }
  );


};
print $@ if $@;

$emailconfMock->unmock('updateEmailDb');


# loadEmailDb()
# my $emailId = $input->{'emailId'};
# my $gatewayAccount = $input->{'gatewayAccount'};
eval {
  my %whereFields;
  my $input = {
    emailId => 'emailId',
    gatewayAccount => 'gatewayAccount'
  };

  $dbsMock->redefine(
  'fetchallOrDie' => sub {
    my (undef,$database,$query,$values) = @_;
    $query =~ s/\n/ /g;

    # get fields being loaded
    $query =~ /select\s+(.*?)\s+from/i;
    my @fields = split(',',$1);
    my %loadedFields;
    foreach my $field (@fields) {
      $field =~ s/^\s*(.*?)\s*$/$1/; # strip off leading and trailing spaces
      $field =~ /\w+\s+AS\s+(\w+)/i; # check if column is aliased for output
      $field = $1 || $field;
      $loadedFields{$field} = ($field) . 'Value'; # set field value as field with 'Value' concatenated
    }

    # get where values
    # this isn't perfect but it works for the test
    $query =~ /where (.*)/i;
    my $wheres = $1;
    $wheres =~ s/\s*(AND|OR)\s*//ig;
    my @wheres = split(/\s*=\s*\?\s*/,$wheres);
    %whereFields = map { $_ => shift @{$values} } @wheres;

    return {
      rows => [\%loadedFields]
    };
  }
  );

  my $res = emailconf::loadEmailDb($input);
  is($res->{'content'},'contentValue','content value is correct value');
  is($res->{'delay'},'delayValue','delay value is correct value');
  is($res->{'include'},'includeValue','include value is correct value');
  is($res->{'description'},'descriptionValue','description value is correct value');
  is($res->{'excludeUrl'},'excludeUrlValue','excludeUrl value is correct value');
  is($res->{'contentType'},'contentTypeValue','contentType value is correct value');
  is($res->{'emailType'},'emailTypeValue','emailType value is correct value');
  is($res->{'weight'},'weightValue','weight value is correct value');
  is($whereFields{'body'},'emailId','body in query matches input emailId');
  is($whereFields{'username'},'gatewayAccount','username in query matches input gatewayAccount');
};
print $@ if $@;

$dbsMock->redefine(
'fetchallOrDie' => $noQueries
);


# loadEmail()
eval {
  my $input = {
    emailId => 'emailId',
    gatewayAccount => 'gatewayAccount'
  };

  $emailconfMock->redefine(
  'loadEmailDb' => sub {
    return {
      content => 'contentValue',
      delay => '0,none',
      include => '"subject=janky subject","filelink=somethin.txt"',
      description => 'email description',
      excludeUrl => 'i do not see this being used',
      contentType => 'text',
      emailType => 'conf',
      weight => '"weightamt=1000"'
    };
  }
  );

  my $res = emailconf::loadEmail($input);

  is($res->{'content'},'contentValue','content is correct value');
  is($res->{'delay'},'0,none','delay is correct value');
  is($res->{'include'},'"subject=janky subject","filelink=somethin.txt"','include is correct value');
  is($res->{'description'},'email description','description is correct value');
  is($res->{'excludeUrl'},'i do not see this being used','excludeUrl is correct value');
  is($res->{'contentType'},'text','contentType is correct value');
  is($res->{'emailType'},'conf','emailType is correct value');
  is($res->{'weight'},'"weightamt=1000"','weight is correct value');
  is($res->{'queryData'}{'testwhat'},'"subject=janky subject","filelink=somethin.txt"','querydata->testwhat is the correct value');
  is($res->{'queryData'}{'template_type'},'confirmation','querydata->template_type is the correct value');
};
print $@ if $@;

$emailconfMock->unmock('loadEmailDb');

# deleteEmailDb()
eval {
  my %whereFields;
  my $input = {
    emailId => 'emailId',
    gatewayAccount => 'gatewayAccount'
  };

  $dbsMock->redefine(
  'executeOrDie' => sub {
    my (undef,$database,$query,$values) = @_;
    $query =~ s/\n/ /g;

    # get where values
    # this isn't perfect but it works for the test
    $query =~ /where (.*)/i;
    my $wheres = $1;
    $wheres =~ s/\s*(AND|OR)\s*//ig;
    my @wheres = split(/\s*=\s*\?\s*/,$wheres);
    %whereFields = map { $_ => shift @{$values} } @wheres;
  }
  );

  emailconf::deleteEmailDb($input);
  is($whereFields{'body'},'emailId','body in query matches input emailId');
  is($whereFields{'username'},'gatewayAccount','username in query matches input gatewayAccount');
};
print $@ if $@;

$dbsMock->redefine(
'executeOrDie' => $noQueries
);
