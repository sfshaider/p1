#!/usr/bin/perl

require 5.001;
$| = 1;

package PixSSH;

use Expect;


# new #
#########################################################
## creates a new instance of the PixSSH object
#########################################################
sub new {
  my $type = shift;

  $PixSSH::ssh_location = "/usr/local/bin/ssh";

  ($PixSSH::host, $PixSSH::hostname, $PixSSH::user, $PixSSH::user_password, $PixSSH::enable_password) = @_;

  $PixSSH::timeout = 10;

  $PixSSH::shell_prompt = $PixSSH::hostname . '> '; 
  $PixSSH::enable_prompt = $PixSSH::hostname . '# '; 
  $PixSSH::config_prompt = $PixSSH::hostname . '(config)# '; 
  $PixSSH::password_prompt = "Password:";
  $PixSSH::user_password_prompt = $PixSSH::user . '@' . $PixSSH::host . "'s password:";
  $PixSSH::lastprompt = $PixSSH::user_password_prompt;

  $PixSSH::pagerlines = "";

  $PixSSH::exp = new Expect;
  $PixSSH::exp->raw_pty(1);
  $PixSSH::exp->log_stdout(0);
  #$PixSSH::exp->debug(3);

  return [], $type;
}

# connect #
#########################################################
## trys to connect to host look for an error if result is empty.
#########################################################
sub connect {
  my $type = shift;
  my $result = "";

  if (($PixSSH::user ne "") && ($PixSSH::host ne "") && ($PixSSH::password_prompt ne "") && ($PixSSH::user_password ne "")) {
    $PixSSH::command = $PixSSH::ssh_location . " " . $PixSSH::user . '@' . $PixSSH::host;


    $PixSSH::exp->spawn($PixSSH::command);
    $result = $PixSSH::exp->expect($PixSSH::timeout, &PixSSH::getPrompt($PixSSH::ssh_location)); 
    $PixSSH::exp->send("$PixSSH::user_password\r");
    $PixSSH::timeout = 2;
    $result = $PixSSH::exp->expect($PixSSH::timeout, &PixSSH::getPrompt("loggedin"));
  }
  else {
    $PixSSH::error = "user host password and prompt must be set.";
  }
  return $result;
}

# disconnect # 
#########################################################
## call me to disconnect from ssh session
#########################################################
sub disconnect {
  my $type = shift;
#  &send_command("","configure terminal",1);
  &send_command("",$PixSSH::pagerlines,1);
#  &send_command("","exit",1);
  &send_command("","logout",1);
  $PixSSH::timeout = 10;
  $PixSSH::exp->soft_close();
}

sub enable {
  my $type = shift;
  #if ($enablePassword eq "" || $enablePrompt eq "") {
  #  $PixSSH::error = "enable password and prompt must be given.";
  #}
  $PixSSH::exp->send("enable\r");
  $PixSSH::exp->expect($PixSSH::timeout, &PixSSH::getPrompt("enable"));
  $PixSSH::exp->send("$PixSSH::enable_password\r");

  $result = $PixSSH::exp->expect($PixSSH::timeout, &PixSSH::getPrompt());
  $PixSSH::pagerlines = &send_command("","show pager",1);
  chomp $PixSSH::pagerlines;
#  &send_command("","configure terminal",1);
  &send_command("","no pager",1);
#  &send_command("","exit",1);
}

# used to send a command
# remember to update shell_prompt before sending a command
# if the shell prompt is going to change
sub send_command {
  my $type = shift;

  my ($command, $getresult) = @_;

  my $result = "";

  $PixSSH::exp->send($command . "\n");
#  if ($getresult) {
    $PixSSH::exp->expect($PixSSH::timeout, &PixSSH::getPrompt($command));
    $result = $PixSSH::exp->before();
#print "gggg $result gggg\n";

#  }

  return $result;
}

# used to set/get shell prompt default is ""
#sub shell_prompt {
#  my $type = shift;
#
#  my ($newprompt) = @_;
#
#  if ($newprompt ne "") {
#    $PixSSH::shell_prompt = $newprompt;
#  }
# 
#  return $PixSSH::shell_prompt; 
#}

sub getPrompt { 
  my ($command) = @_;
  if ($command =~ /^enable/ || ($command =~ /^exit/ && $PixSSH::lastprompt != /config/)) {
    $PixSSH::lastprompt = $PixSSH::enable_prompt;
    return $PixSSH::password_prompt;
  }
  elsif ($command =~ /^conf/) {
    $PixSSH::lastprompt = $PixSSH::configure_prompt;
    return $PixSSH::configure_prompt;
  }
  elsif ($command =~ /^disable/ || $command =~ /^loggedin/) {
    $PixSSH::lastprompt = $PixSSH::shell_prompt;
    return $PixSSH::shell_prompt;
  }
  else {
    return $PixSSH::lastprompt;
  }
}
    

# used to set/get password prompt default is "Password:"
sub password_prompt {
  my $type = shift;

  my ($newprompt) = @_;

  if ($newprompt ne "") {
    $PixSSH::password_prompt = $newprompt;
  }

  return $PixSSH::password_prompt;
}

sub errmsg {
  return $PixSSH::error;
}
