#!/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;

require_ok('PlugNPay::Legacy::Genfiles');
my $genfiles = new PlugNPay::Legacy::Genfiles();

testBatchGroups();

sub testBatchGroups {
  ok($genfiles->batchGroupMatch('1','1'), 'group and batch group are the same');
  ok($genfiles->batchGroupMatch('10','10'), 'group and batch group are the same');
  ok($genfiles->batchGroupMatch('100','100'), 'group and batch group are the same');
  ok($genfiles->batchGroupMatch('0',''), 'empty batch group is treated as zero');
  ok($genfiles->batchGroupMatch('','0'), 'empty group is treated as zero');
  ok(!$genfiles->batchGroupMatch('1','2'), 'group and batch group are different');
  ok(!$genfiles->batchGroupMatch('9','10'), 'group and batch group are different');
  ok(!$genfiles->batchGroupMatch('99','100'), 'group and batch group are different');
  ok(!$genfiles->batchGroupMatch('abc','1'), 'group is invalid');
  ok(!$genfiles->batchGroupMatch('1','abc'), 'batch group is invalid');
}