package PlugNPay::API::REST::Responder::Helpdesk;

use PlugNPay::Reseller::Helpdesk;

use base "PlugNPay::API::REST::Responder";

sub _getOutputData {
  my $self = shift;
  my $data = {};
  my $action = $self->getAction();

  if ($action eq 'read') {
    $data = $self->_read();
  } elsif ($action eq 'create') {
    $data = $self->_create();
  }

  return $data;
}

sub _read {
  my $self = shift;

  my $username = $self->getGatewayAccount();
  my $helpdesk = new PlugNPay::Reseller::Helpdesk($username);

  my @cols = ({'name'=>'Ticket','type'=>'number','id' => 'ticket'},
            {'name'=>'Email','type'=>'string','id' => 'email'},
            {'name'=>'Subject','type'=>'string', 'id' => 'subject'},
            {'name'=>'Status','type'=>'string', 'id' => 'status'},
            {'name'=>'Replies','type'=>'number', 'id' => 'replies'},
            {'name'=>'View Ticket','type'=>'string','id' => 'link'});

  my $data = $helpdesk->getTickets({'username' => $username});
  $self->setResponseCode('200');

  return  {'rows' => $helpdesk->prepareForGoogleTable($data), 'columns' => \@cols, 'data' => $data};
}

sub _create {
  my $self = shift;
  my $options = $self->getInputData();

  my $username = $self->getGatewayAccount();
  my $helpdesk = new PlugNPay::Reseller::Helpdesk($username);

  my $email = $options->{'email'};
  my $topicID = $options->{'topicId'};
  my $name = $options->{'name'};
  my $subject = $options->{'subject'};
  my $description = $options->{'message'};
  my $priority = $options->{'pri'};
  my $phone = $options->{'phone'};

  # ## Build data hash
  my $data = {
    pnp_user => $username,
    email => $email,
    phone => $phone,
    name => $name,
    source => 'reseller',
    topicId => $topicID, # 2 is accounting
    priorityId => $priority, # 2 is "normal",
    subject => $subject,
    message => $description
  };
  my $response = $helpdesk->newTicket($data);

  ## check API response
  my $output = {};
  if ($response->{'status'} eq 'false') {
    $output = {'status' => 'Ticketing Error'};
    $self->setResponseCode('520');
  } else {
    $output = {'status' => $response->{'status'},
               'ticket' => $response->{'ticketNumber'},
               'email' => $data->{'email'}};
    $self->setResponseCode('201');
  }

  return $output;
}

1;
