#!/bin/env perl

# Purpose: Allows merchants to securely upload files to PnP server, for further PnP review.

# Last Updated: 07/25/07

require 5.001;
$| = 1;

use lib $ENV{'PNP_PERL_LIB'};
use CGI qw/:standard/;
use sysutils;
use strict;

if (($ENV{'HTTP_X_FORWARDED_SERVER'} ne "") && ($ENV{'HTTP_X_FORWARDED_FOR'} ne "")) {
  $ENV{'HTTP_HOST'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_HOST'}))[0];
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

if ($ENV{'SEC_LEVEL'} > 11) {
  print "Content-Type: text/html\n\n";
  print "Your current security level is not cleared for this operation. <p>Please contact Technical Support if you believe this to be in error. ";
  exit;
}

my $query = new CGI;

my %query;
my @array = $query->param;
foreach my $var (@array) {
  $query{$var} = &CGI::escapeHTML($query->param($var));
  $query{$var} =~ s/(\;|\`|\|)//g; # remove non-allowed characters from input fields
}

if ($ENV{'HTTP_X_FORWARDED_SERVER'} ne "") {
  # changed for breach 4/9/2009
  #$ENV{'SERVER_NAME'} = $ENV{'HTTP_X_FORWARDED_SERVER'};
  $ENV{'SERVER_NAME'} = (split(/\,/,$ENV{'HTTP_X_FORWARDED_SERVER'}))[0];
}

# initialize params here:
my $script = "https://" . $ENV{'SERVER_NAME'} . $ENV{'SCRIPT_NAME'}; # self-location of this script -> should never need to be changed...
my $upload_dir = "/home/p/pay1/secure_uploads/"; # absolute path to folder where uplaoded files will reside

my $allowed_ascii_types  = "XML|TXT|CSV|HTM|HTML|IIF"; # allowed ASCII files types (pipe delimited)
my $allowed_binary_types = "ZIP|XLS|DOC|PDF|JPG|JPEG|GIF|BMP|PNG|QBW"; # allowed Binary files types (pipe delimited)
my $non_allowed_types    = "ADE|ADP|ASX|BAS|BAT|CHM|CMD|COM|CPL|CRT|DLL|EXE|HLP|HTA|INF|INS|ISP|JS|JSE|LNK|MDB|MDE|MDT|MDW|MDZ|MSC|MSI|MSP|MST|PCD|PIF|PL|PM|REG|SCF|SCR|SCT|SHB|SHS|URL|VB|VBE|VBS|WS|WSC|WSF|WSH"; # do not allow these file types because they can be harmful to the PC/server (pipe delimited)

my $max_files = 3; # set maximum number of uploaded files allowed on server at any given time
my $max_size = 20; # set maximum size of uploaded file in Megabytes (i.e. using '8' = 8 Meg maximum file size)

# If you want to restrict the upload file size (in bytes), uncomment the next line and change the number
$CGI::POST_MAX = 1048576 * $max_size; # set to 20 Megs max file size
# Converion Notes: 1K = 1024 bytes, 1Meg = 1048576 bytes.
$CGI::DISABLE_UPLOADS = 0;  # allow uploads

my $merchant = $ENV{'REMOTE_USER'};  # grab merchant's username
my $ipaddress = $ENV{'REMOTE_ADDR'}; # grab merchant's IP address

if ($query{'mode'} eq "upload") {
  &validate();
  &upload_file();
}
else {
  &upload_form();
}

exit;

sub html_head {
  print "Content-Type: text/html\n\n";

  print "<html>\n";
  print "<head>\n";
  print "<title>Secure File Upload Administration</title>\n";
  print "<link rel=\"shortcut icon\" href=\"favicon.ico\">\n";
  print "<link href=\"/css/style.css\" type=\"text/css\" rel=\"stylesheet\">\n";
  print "</head>\n";
  print "<body bgcolor=\"#ffffff\" onLoad=\"self.focus()\">\n";

  print "<div align=\"center\">\n";
  print "<table cellspacing=\"0\" cellpadding=\"4\" border=\"0\" width=\"500\">\n";
  print "  <tr>\n";
  print "    <td align=\"center\"><img src=\"/adminlogos/pnp_admin_logo.gif\" alt=\"Corp. Logo\"></td>\n";
  print "  </tr>\n";
  print "  <tr>\n";
  print "    <th align=\"center\"><font size=\"4\" face=\"Arial,Helvetica,Univers,Zurich BT\">Secure File Upload Administration</font></th>\n";
  print "  </tr>\n";
  print "</table>\n";
  print "<br></div>\n";

  return;
}

sub html_tail {
  print "</body>\n";
  print "</html>\n";

  exit;
}

sub upload_form {
  my ($error) = @_;

  &html_head();

  if ($error ne "") {
    print "<p><font color=\"#ff0000\"><b>ERROR:</b></font> $error</p>\n";
  }

  print "<FORM ACTION=\"$script\" METHOD=\"post\" ENCTYPE=\"multipart/form-data\">\n";
  print "<input type=\"hidden\" name=\"mode\" value=\"upload\">\n";

  print "<table border=\"0\" cellspacing=\"0\" cellpadding=\"3\">\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\"><p><b>Please select the file you wish to securely upload to our server:</b></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=\"right\" valign=\"top\"><p>File To Upload:</p></td>\n";
  print "    <td><p><input type=\"file\" name=\"upload_file\"></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\"><p><b>Enter the email address of the staff member you wish to notify about this upload:</b></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=\"right\" valign=\"top\"><p>Notify Staff:</p></td>\n";
  print "    <td><p><input type=\"text\" name=\"admin_email\" value=\"$query{'admin_email'}\">\n";
  print "<br>(i.e. support\@plugnpay.com)</p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\" align=\"center\"><hr width=\"80%\"</td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\"><p><b>Optionally, enter your direct contact information:</b></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=\"right\" valign=\"top\"><p>Name:</p></td>\n";
  print "    <td><p><input type=\"text\" name=\"name\" value=\"$query{'name'}\"></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=\"right\" valign=\"top\"><p>Email:</p></td>\n";
  print "    <td><p><input type=\"text\" name=\"email\" value=\"$query{'email'}\">\n";
  print "<br>(i.e. you\@yourdomain.com)</p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=\"right\" valign=\"top\"><p>Phone:</p></td>\n";
  print "    <td><p><input type=\"text\" name=\"phone\" value=\"$query{'phone'}\">\n";
  print "<br>(i.e. 1-555-555-5555 x123)</p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\"><p><b>Optionally, include any special instructions/comments, as necessary:</b></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td align=\"right\" valign=\"top\"><p>Comments:</p></td>\n";
  print "    <td><p><textarea cols=\"50\" rows=\"8\">$query{'comments'}</textarea></p></td>\n";
  print "  </tr>\n";

  print "  <tr>\n";
  print "    <td colspan=\"2\"><p><input type=\"submit\" name=\"Submit\" value=\"Upload Data\"></p></td>\n";
  print "  </tr>\n";

  print "</table>\n";
  print "</form>\n";

  &html_tail();
  return;
}

sub upload_file {

  # get filename
  my $filename = &CGI::escapeHTML($query->param("upload_file"));
  $filename =~ s/.*[\/\\](.*)/$1/;
  $filename =~ s/[^a-zA-Z0-9\_\-\.]//g;
  $filename = lc("$filename");

  $filename = $merchant . "_" . $filename;

  # get filename's extension
  my @temp = split(/\./, $filename);
  my $filename_ext = $temp[$#temp];
  $filename_ext = lc("$filename_ext");

  # make list of all allowed file_extensions
  my @allowed_types;
  $allowed_ascii_types = lc("$allowed_ascii_types");
  $allowed_binary_types = lc("$allowed_binary_types");

  my @temp_ascii = split(/\|/, $allowed_ascii_types);
  for (my $i = 0; $i <= $#temp_ascii; $i++) {
    push (@allowed_types, $temp_ascii[$i]);
  }
  my @temp_binary = split(/\|/, $allowed_binary_types);
  for (my $i = 0; $i <= $#temp_binary; $i++) {
    push (@allowed_types, $temp_binary[$i]);
  }

  my $match_ext = 0; # assume no match
  foreach (my $i = 0; $i <= $#allowed_types; $i++) {
    if ($filename_ext =~ /$allowed_types[$i]/i) {
      $match_ext = 1;
      last;
    }
  }

  if ($match_ext == 0) {
    my $error = "\'$filename_ext\' Invalid File Type... You may only upload files with the following extensions: @allowed_types";
    &upload_form("$error");
  }

  # grab the file uploaded
  my $upload_filehandle = $query->upload("upload_file");

  # look for uploads that exceed $CGI::POST_MAX
  if (!$upload_filehandle && $query->cgi_error()) {
    my $error = "The file you are attempting to upload exceeds the maximum allowable file size.\n";
    &upload_form("$error");
  }

  # open target file on harddisk
  $upload_dir =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
  $filename =~ s/[^a-zA-Z0-9\_\-\.]//g;
  $filename =~ s/\.\.//g;
  my $path_file = "$upload_dir\/$filename";
  &sysutils::filelog("write",">$path_file");
  open(UPLOADFILE, ">$path_file") or die "Cannot open $path_file for writing. $!";

  # set target file format
  if ($filename_ext =~ /$allowed_ascii_types/i) {
    # use ASCII format - do nothing...
  }
  else {
    # use/assume binary format
    binmode UPLOADFILE;
  }

  # write the uploaded file to the target file
  while(<$upload_filehandle>) {
    print UPLOADFILE;
  }

  # close targe file handle
  close(UPLOADFILE);

  # double check file size, in case CGI::POST_MAX is not enforced for some reason.
  if ((-s "$upload_dir/$filename") >= $CGI::POST_MAX) {
    if ($filename ne "") {
      unlink("$upload_dir/$filename");
    }
    my $error = "The file you are attempting to upload exceeds the maximum allowable file size.\n";
    &upload_form("$error");
  }

  # force 664 file permissions - to ensure files cannot be executed
  chmod(0664, "$upload_dir/$filename");

  # sent file upload notification
  &send_email($filename);

  # display thank you response to the end user
  &html_head();
  print "<div align=\"center\">You file has been securely uploaded to our server.";
  print "<br>A notification has been sent to \'$query{'admin_email'}\'.\n";
  print "<form><input type=\"button\" value=\"Close Window\" onClick=\"javascript:window.close();\"></form></div>\n";
  &html_tail();

  return;
}

sub send_email {
  my ($filename) = @_;

  # open email handler
  open(MAIL,"| /usr/lib/sendmail -t") or die "Cannot open sendmail handle. $!";

  # print email message to email handler
  if ($query{'admin_email'} ne "") {
    print MAIL "To: $query{'admin_email'}\n";
  }
  else {
    print MAIL "To: support\@plugnpay.com\n";
  }

  if ($query{'email'} ne "") {
    print MAIL "From: $query{'email'}\n";
  }
  else {
    print MAIL "From: support\@plugnpay.com\n";
  }
  print MAIL "Subject: New Secure File Uploaded - $merchant\n\n";

  print MAIL "A new file has been uploaded to the site for your review.\n\n";

  print MAIL "Username: $merchant\n";
  print MAIL "File Name: $filename\n\n";
  print MAIL "IP: $ipaddress\n";

  print MAIL "Merchant Contact Info: \n";
  print MAIL "Name:  $query{'name'}\n";
  print MAIL "Email: $query{'email'}\n";
  print MAIL "Phone: $query{'phone'}\n";

  print MAIL "Comments:\n";
  print MAIL "$query{'comments'}\n";

  print MAIL "\n\n";

  # close email handler
  close(MAIL);

  return;
}


sub validate {

  # limit number of files uploaded by merchant
  my $file_count = 0;
  my @existing_files = ();

  $upload_dir =~ s/[^a-zA-Z0-9\_\-\.\/]//g;
  opendir(UPLOADS, "$upload_dir") or die "Cannot open directory $upload_dir for reading. $!";
  my @all_files = readdir(UPLOADS);
  closedir(UPLOADS);

  for (my $i = 0; $i <= $#all_files; $i++) {
    if ($all_files[$i] =~ /^($merchant\_)/) {
      $file_count = $file_count + 1;
      my $filename = $all_files[$i];
      $filename =~ s/^($merchant\_)//g;
      push (@existing_files, $filename);
    }
  }

  if ($file_count >= $max_files) {
    my $error = "You have exceeded the maximum number of secure upload files you can upload to our servers at any given time.\n";
    $error .= "<br><b>Please contact tech support for additional assistance, before attempting to upload any new files.</b>\n";
    $error .= "<br>&nbsp;\n";
    $error .= "<br>Currently Uploaded Files:\n";
    for (my $i = 0; $i <= $#existing_files; $i++) {
      $error .= "<br>\&bull; $existing_files[$i]\n";
    }
    &upload_form("$error");
  }

  # now validate information provided by the customer
  if ($query{'admin_email'} ne "") {
    $query{'admin_email'} =~ s/[^a-zA-Z_0-9\_\-\.\@]//g;
    if ($query{'admin_email'} !~ /^(\w¦\-¦\_¦\.)+\@((\w¦\-¦\_)+\.)+[a-zA-Z]{2,}$/) {
      #print "Email address is valid\n";
    }
    else {
      my $error = "You must supply a valid formatted admin email address. (i.e. name\@ourdomain\.com)\n";
      &upload_form("$error");
    }

    if ($query{'admin_email'} !~ /(\@plugnpay\.com)$/) {
      my $error = "You must specify a valid email address, of a staff member within our company, which you want to be notify about this upload.\n";
      &upload_form("$error");
    }
  }

  if ($query{'email'} ne "") {
    $query{'email'} =~ s/[^a-zA-Z_0-9\_\-\.\@]//g;
    if ($query{'email'} !~ /^(\w¦\-¦\_¦\.)+\@((\w¦\-¦\_)+\.)+[a-zA-Z]{2,}$/) {
      #print "Email address is valid\n";
    }
    else {
      my $error = "You must supply a valid formatted contact email address. (i.e. name\@yourdomain\.com)\n";
      &upload_form("$error");
    }
  }

  return;
}

