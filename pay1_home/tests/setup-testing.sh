#!/bin/sh

yum install -y perl-Test-Harness.noarch perl-Test-Output.noarch
(echo yes; echo sudo; echo no; echo no; echo http://mirrors.rit.edu/CPAN/;)| cpan
cpan install Test::More
cpan install Test::Exception
cpan install Perl::Metrics::Simple
cpan install Module::Build
cpan install Test::Exception
cpan install Test::MockObject
cpan install Test::MockModule
cpan install Digest::Bcrypt
