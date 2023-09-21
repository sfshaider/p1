package PlugNPay::Util::RPN;

use strict;

use PlugNPay::Util::RPN::Calculator;

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub addVariables {
  my $self = shift;
  my $hashref = shift;
  foreach my $name (keys %{$hashref}) {
    $self->addVariable($name,$hashref->{$name});
  }
}

sub addVariable {
  my $self = shift;
  my $name = shift;
  my $value = shift;

  if (!defined $self->{'variables'}) {
    $self->_initVariables();
  }

  $self->{'variables'}{$name} = $value;
}

sub getVariable {
  my $self = shift;
  my $name = shift;
  if (!defined $self->{'variables'}) {
    $self->_initVariables();
  }
  return $self->{'variables'}{$name};
}

sub setFormula {
  my $self = shift;
  my $formula = shift;
  $self->{'formula'} = $formula;
}

sub getFormula {
  my $self = shift;
  return $self->{'formula'};
}

sub _prepareInput {
  my $self = shift;

  my $formula = $self->getFormula();

  my @input = split(/\s+/,$formula);

  for (my $i = 0; $i < @input; $i++) {
    if (substr($input[$i],0,1) eq '$') {
      $input[$i] = $self->getVariable(substr($input[$i],1));
    }
  }

  return \@input;
}

sub calculate {
  my $self = shift;
  my $input = $self->_prepareInput();
  my $calculator = new PlugNPay::Util::RPN::Calculator();
  return $calculator->calculate($input);
}

sub calculateBoolean {
  my $self = shift;
  my $input = $self->_prepareInput();
  my $calculator = new PlugNPay::Util::RPN::Calculator();
  return $calculator->calculateBoolean($input);
}



sub _initVariables {
  my $self = shift;
  $self->{'variables'} = {};
}

1;
