#!/bin/sh

# Set up Packages

yum update -y

# amazonlinux:2 doesn't include groupadd by default
yum install -y shadow-utils gzip tar

# epel is installed diferently on amazonlinux:2
amazon-linux-extras install epel -y

cat packages.txt | xargs yum install -y
if [ ! "$!" = "0" ]; then
  echo "Failed to install packages.  Exiting."
  exit
fi

yum install -y gcc

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

yum remove -y gcc


# Set up Directories

mkdir -p /home/pay1/etc
mkdir -p /home/p

mkdir -p /home/pay1/logs
chmod a+rwx /home/pay1/logs

mkdir -p /home/pay1/log/datalog
chmod a+rwx /home/pay1/log/datalog
mkdir -p /home/pay1/log/local
mkdir -p /home/pay1/log/loggy
touch /home/pay1/log/local/datalog_skip_proxy
mkdir -p /home/pay1/etc/datalog
touch /home/pay1/etc/is_container

ln -s /home/pay1 /home/p/pay1

# Set up pay1 user

groupadd -g 10000 pay1
useradd -g pay1 -u 10000 -d /home/pay1 -s /bin/bash pay1

chown -R pay1:pay1 /home/pay1
mkdir -p /home/pay1/log/batchfiles

