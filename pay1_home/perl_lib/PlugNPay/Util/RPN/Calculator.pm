package PlugNPay::Util::RPN::Calculator;

use strict;
use PlugNPay::Die;

our $_operators; # defined later for readability

sub new {
  my $class = shift;
  my $self = {};
  bless $self,$class;
  return $self;
}

sub _stackPush {
  my $self = shift;
  my $element = shift;
  if (!defined $self->{'stack'}) {
    $self->{'stack'} = [];
  }

  unshift @{$self->{'stack'}},$element;
}

sub _stackPop {
  my $self = shift;
  return shift @{$self->{'stack'}};
}

sub _stackSize {
  my $self = shift;
  return @{$self->{'stack'}};
}

sub calculate {
  my $self = shift;
  my $input = shift;
  my @originalInput = @{$input};

  while (@{$input} >= 1) {
    my $element = shift @{$input};
    if (!defined $element) {
      die('Undefined element! ' . join(',',@originalInput));
    }
    if ($self->isOperator($element)) {
      my $requiredArgumentCount = $_operators->{$element}{'args'};
      my @values;

      if ($requiredArgumentCount eq '*') {
        $requiredArgumentCount = $self->_stackSize();;
      }

      while ($requiredArgumentCount > 0) {
        push @values,$self->_stackPop();
        $requiredArgumentCount--;
      }
      my $operationResult = $self->operate(\@values,$element);
      $self->_stackPush($operationResult);
    } else {
      $self->_stackPush($element);
    }
  }

  return $self->_stackPop();
}

sub calculateBoolean {
  my $self = shift;
  my $input = shift;
  return ($self->calculate($input) == 1 ? 1 : 0);
}

sub operate {
  my $self = shift;
  my $argsRef = shift;
  my $operator = shift;

  if ($self->isOperator($operator)) {
    my $argCount = $_operators->{$operator}{'args'};
    if ($argCount eq @{$argsRef} || $argCount eq '*') {
      my $operation = $_operators->{$operator}{'operation'};
      my $result = &$operation(reverse @{$argsRef});
      return $result;
    }
  }
}

sub isOperator {
  my $self = shift;
  my $questionableOperator = shift;
  return defined $_operators->{$questionableOperator};
}

$_operators = {
## Math ##
  '+' =>  { args => 2, operation => sub {(shift) + (shift)}},
  '-' =>  { args => 2, operation => sub {(shift) - (shift)}},
  '*' =>  { args => 2, operation => sub {(shift) * (shift)}},
  '/' =>  { args => 2, operation => sub {(shift) / (shift)}},
  '%' =>  { args => 2, operation => sub {(shift) % (shift)}},
  '>' =>  { args => 2, operation => sub {((shift) gt (shift) ? 1 : 0)}},
  '<' =>  { args => 2, operation => sub {((shift) lt (shift) ? 1 : 0)}},
  '==' => { args => 2, operation => sub {((shift) == (shift) ? 1 : 0)}},
  '!=' => { args => 2, operation => sub {((shift) != (shift) ? 1 : 0)}},
  'sum' => { args => '*', operation => sub { my $sum = 0; foreach my $value (@_) { $sum += $value; } return $sum; } },
  'min' => { args => 2, operation => sub { my ($op1, $op2) = @_; return ($op1 > $op2 ? $op2 : $op1); }},
## Logic ##
  # if then else
  '->' => { args => 3, operation => sub { my ($op1,$op2,$op3) = @_; if ($op1 == 1) { return $op2; } else { return $op3; }}}
};

1;
