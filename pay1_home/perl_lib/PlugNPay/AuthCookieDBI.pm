#===============================================================================
#
# $Id: AuthCookieDBI.pm,v 1.60 2011/03/12 20:14:41 matisse Exp $
#
# PlugNPay::AuthCookieDBI
#
# An AuthCookie module backed by a DBI database.
#
# See end of this file for Copyright notices.
#
# Author:  Jacob Davies <jacob@well.com>
# Maintainer: Matisse Enzer <matisse@cpan.org> (as of version 2.0)
#
# This library is a big POS and should be replaced with something
# better.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# This module has been heavily modified to work with PlugNPay Modules
# where possible.
#
#===============================================================================

package PlugNPay::AuthCookieDBI;

use strict;
use warnings;
#use 5.010_000;
our $VERSION = '2.17';

use PlugNPay::AuthCookie;
use base qw( PlugNPay::AuthCookie );

use Apache2::RequestRec;
use DBI;
use Apache2::Log;
use Apache2::Const -compile => qw( OK HTTP_FORBIDDEN SERVER_ERROR :log );
use Apache2::ServerUtil;
use Carp qw();
use Digest::MD5 qw( md5_hex );
use Date::Calc qw( Today_and_Now Add_Delta_DHMS );

use PlugNPay::Username;
use PlugNPay::DBConnection;
use PlugNPay::Util::Encryption::Random;
use PlugNPay::Util::Encryption::AES;
use PlugNPay::Authentication;
use PlugNPay::Metrics;
use PlugNPay::Reseller::Chain;
use PlugNPay::GatewayAccount;

# Also uses Crypt::CBC if you're using encrypted cookies.
# Also uses Apache2::Session if you're using sessions.
use English qw(-no_match_vars);

#===============================================================================
# FILE (LEXICAL)  G L O B A L S
#===============================================================================

my %CIPHERS = ();

# Stores Cipher::CBC objects in $CIPHERS{ idea:AuthName },
# $CIPHERS{ des:AuthName } etc.

use constant COLON_REGEX => qr/ : /mx;
use constant DATE_TIME_STRING_REGEX =>
    qr/ \A \d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2} \z /mx;
use constant EMPTY_STRING                 => q{};
use constant HEX_STRING_REGEX             => qr/ \A [0-9a-fA-F]+ \z /mx;
use constant HYPHEN_REGEX                 => qr/ - /mx;
use constant PERCENT_ENCODED_STRING_REGEX => qr/ \A [a-zA-Z0-9_\%]+ \z /mx;
use constant THIRTY_TWO_CHARACTER_HEX_STRING_REGEX =>
    qr/  \A [0-9a-fA-F]{32} \z /mx;
use constant TRUE             => 1;
use constant WHITESPACE_REGEX => qr/ \s+ /mx;
use constant LOG_TYPE_AUTH    => 'authentication';
use constant LOG_TYPE_SYSTEM  => 'system';
use constant LOG_TYPE_TIMEOUT => 'timeout';

#===============================================================================
# P E R L D O C
#===============================================================================

=head1 NAME

PlugNPay::AuthCookieDBI - An AuthCookie module backed by a DBI database,
modified for use by Plug'n Pay.

=head1 VERSION

    This is version 2.14

=head1 COMPATIBILITY

Starting with version 2.03 the module is in the Apache2::* namespace,
L<PlugNPay::AuthCookieDBI>.  For F<mod_perl1> versions
there is: L<Apache::AuthCookieDBI>

=head1 SYNOPSIS

    # In httpd.conf or .htaccess

    PerlModule PlugNPay:AuthCookieDBI
    PerlSetVar WhatEverPath /
    PerlSetVar WhatEverLoginScript /login.pl

    # Optional, to share tickets between servers.
    PerlSetVar WhatEverDomain .domain.com

    PerlSetVar WhatEverDBI_SessionLifetime 00-24-00-00

    # Protected by AuthCookieDBI.
    <Directory /www/domain.com/authcookiedbi>
        AuthType PlugNPay::AuthCookieDBI
        AuthName WhatEver
        PerlAuthenHandler PlugNPay::AuthCookieDBI->authenticate
        require valid-user
        require group system
    </Directory>

    # Login location.
    <Files LOGIN>
        AuthType PlugNPay::AuthCookieDBI
        AuthName WhatEver
        SetHandler perl-script
        PerlHandler PlugNPay::AuthCookieDBI->login

        # If the directopry you are protecting is the DocumentRoot directory
        # then uncomment the following directive:
        #Satisfy any
    </Files>

=head1 DESCRIPTION

This module is an authentication handler that uses the basic mechanism provided
by PlugNPay::AuthCookie with a DBI database for ticket-based protection.  It
is based on two tokens being provided, a username and password, which can
be any strings (there are no illegal characters for either).  The username is
used to set the remote user as if Basic Authentication was used.

=cut

our $session_encryption_keys;

#-------------------------------------------------------------------------------
# _log_not_set -- Log that a particular authentication variable was not set.

sub _log_not_set {
    my ( $class, $r, $variable ) = @_;
    my $auth_name = $r->auth_name;
    my $message   = "${class}\t$variable not set for auth realm $auth_name";
    $class->logger( $r, Apache2::Const::LOG_ERR, $message, undef,
        LOG_TYPE_SYSTEM, $r->uri );
    return;
}

#-------------------------------------------------------------------------------
# _dir_config_var -- Get a particular authentication variable.

sub _dir_config_var {
    my ( $class, $r, $variable ) = @_;
    my $auth_name = $r->auth_name;
    return $r->dir_config("$auth_name$variable");
}

my %CONFIG_DEFAULT = (
    DBI_SessionLifetime => '00-24-00-00',
);

sub _dbi_config_vars {
    my ( $class, $r ) = @_;

    my %c;    # config variables hash
    foreach my $variable ( keys %CONFIG_DEFAULT ) {
        my $value_from_config = $class->_dir_config_var( $r, $variable );
        $c{$variable}
            = defined $value_from_config
            ? $value_from_config
            : $CONFIG_DEFAULT{$variable};
        if ( !defined $c{$variable} ) {
            $class->_log_not_set( $r, $variable );
        }
    }

    return %c;
}

=head1 APACHE CONFIGURATION DIRECTIVES

All configuration directives for this module are passed in PerlSetVars.  These
PerlSetVars must begin with the AuthName that you are describing, so if your
AuthName is PrivateBankingSystem they will look like:

    PerlSetVar PrivateBankingSystemDBI_DSN "DBI:mysql:database=banking"

See also L<Apache2::Authcookie> for the directives required for any kind
of PlugNPay::AuthCookie-based authentication system.

In the following descriptions, replace "WhatEver" with your particular
AuthName.  The available configuration directives are as follows:

=over 4

=item C<WhatEverDBI_SessionLifetime>

How long tickets are good for after being issued.  Note that presently
PlugNPay::AuthCookie does not set a client-side expire time, which means that
most clients will only keep the cookie until the user quits the browser.
However, if you wish to force people to log in again sooner than that, set
this value.  This can be 'forever' or a life time specified as:

    DD-hh-mm-ss -- Days, hours, minute and seconds to live.

This is not required and defaults to '00-24-00-00' or 24 hours.

=back

=cut

#-------------------------------------------------------------------------------
# _now_year_month_day_hour_minute_second -- Return a string with the time in
# this order separated by dashes.

sub _now_year_month_day_hour_minute_second {
    return sprintf '%04d-%02d-%02d-%02d-%02d-%02d', Today_and_Now;
}


# Takes a list and returns a list of the same size.
# Any element in the inputs that is defined is returned unchanged. Elements that
# were undef are returned as empty strings.
sub _defined_or_empty {
    my @args        = @_;
    my @all_defined = ();
    foreach my $arg (@args) {
        if ( defined $arg ) {
            push @all_defined, $arg;
        }
        else {
            push @all_defined, EMPTY_STRING;
        }
    }
    return @all_defined;
}

sub _is_empty {
    my $string = shift;
    return TRUE if not defined $string;
    return TRUE if $string eq EMPTY_STRING;
    return;
}

#===============================================================================
# P U B L I C   F U N C T I O N S
#===============================================================================

sub extra_session_info {
    my ( $class, $r, $user, $password, @extra_data ) = @_;

    return EMPTY_STRING;
}

sub authen_cred {
    my ( $class, $r, $user, $password, @extra_data ) = @_;
    my $realm = $r->auth_name;
    my $overrideVersion = 2;

    # filter user
    my $originalUser = $user;
    $user =~ s/[^a-zA-Z0-9 ]//g;
    my $filtered = ($user eq $originalUser)
                 ? '(filtered)'
                 : '';

    # log attempt
    $class->logger( $r, Apache2::Const::LOG_NOTICE, 'attempting auth for user: [' . $user . ']' . $filtered, $user, LOG_TYPE_AUTH, $r->uri );

    my $method = $ENV{'REQUEST_METHOD'};
    if (uc($method) ne 'POST') {
      my $message =  "${class}\tbad login method for auth realm $realm: $method";
      $class->logger( $r, Apache2::Const::LOG_NOTICE, $message, $user, LOG_TYPE_AUTH, $r->uri);
      return;
    }

    my ($username,$override) = split(/\s+/,$user);

    my $authenticator = new PlugNPay::Authentication($username);

    if (!$authenticator->validateLogin({ login => $username,
      password                                 => $password,
      realm                                    => $realm,
      override                                 => $override,
      version                                  => $overrideVersion
    })) {
      new PlugNPay::Metrics()->increment({ metric => 'authentication.failure' });
      $class->logger( $r, Apache2::Const::LOG_NOTICE, 'auth failed for user: [' . $user . ']' . $filtered, $user, LOG_TYPE_AUTH, $r->uri );
      return;
    } else {
        my $overrideType = $authenticator->getOverrideType();
        # make sure reseller has access to the merchant they are attempting to log in as
        if ($overrideType eq "reseller") {
            my $ga = new PlugNPay::GatewayAccount($override);
            my $chain = new PlugNPay::Reseller::Chain($username);
            if ($username ne $ga->getReseller() && !$chain->hasDescendant($ga->getReseller())) {
                new PlugNPay::Metrics()->increment({ metric => 'authentication.failure' });
                my $message = 'Reseller, ' . $username . ', does not have access to ' . $override;
                $class->logger($r, Apache2::Const::LOG_NOTICE, $message, $username, LOG_TYPE_AUTH, $r->uri);
                return;
            }
        }
        # make sure overrideType is 'all' if attempting to override into private
        if ($override ne '' && $r->uri =~ /priv/gi) {
            if ($overrideType ne 'all') {
                new PlugNPay::Metrics()->increment({ metric => 'authentication.failure' });
                $class->logger($r, Apache2::Const::LOG_NOTICE, 'user does not have access to private: [' . $user . ']' . $filtered, $user, LOG_TYPE_AUTH, $r->uri);
                return;
            }
        }
      # successful authentication
      new PlugNPay::Metrics()->increment({ metric => 'authentication.success' });
      $class->logger( $r, Apache2::Const::LOG_NOTICE, 'auth succeeded for user: [' . $user . ']' . $filtered, $user, LOG_TYPE_AUTH, $r->uri );
    }


    # check if username can override if override is being attempted, if attempted and username can not override, fail.
    if ($override && !$authenticator->canOverride()) {
      $class->logger( $r, Apache2::Const::LOG_NOTICE, 'override failed for user: [' . $user . ']' . $filtered, $user, LOG_TYPE_AUTH, $r->uri );
      return;
    }

    return $authenticator->getCookie();
}

#-------------------------------------------------------------------------------
# Take a session key and check that it is still valid; if so, return the user.

sub authen_ses_key {
    my ( $class, $r, $cookie ) = @_;
    my $realm = $r->auth_name;

    my $authenticator = new PlugNPay::Authentication();

    if (!$authenticator->validateCookie({'cookie' => $cookie, 'realm' => $realm})) {
      my $reason = $authenticator->getReason();
      my $login = $authenticator->getLogin();
      my $message = 'Cookie validation failed: ' . $reason;
      $class->logger( $r, Apache2::Const::LOG_INFO, $message, $login, LOG_TYPE_TIMEOUT, $r->uri);
      $r->auth_type->logout($r);
      return;
    }

    my $login = $authenticator->getLogin();
    my $override = $authenticator->getOverrideLogin();
    my $overrideType = $authenticator->getOverrideType();

    # make sure reseller has access to the merchant they are logged in as
    if ($overrideType eq "reseller") {
        my $ga = new PlugNPay::GatewayAccount($override);
        my $chain = new PlugNPay::Reseller::Chain($login);
        if ($login ne $ga->getReseller() && !$chain->hasDescendant($ga->getReseller())) {
            my $message = 'Cookie validation failed: Reseller, ' . $login . ', does not have access to ' . $override;
            $class->logger( $r, Apache2::Const::LOG_INFO, $message, $login, LOG_TYPE_TIMEOUT, $r->uri);
            $r->auth_type->logout($r);
            return;
        }
    }

    my $account = $authenticator->getAccount();
    my $subaccount = $authenticator->getSubAccount();
    my $securityLevel = $authenticator->getSecurityLevel();
    my $mustChangePassword = $authenticator->getMustChangePassword();
    
    ## Set environmental variables.
    $r->user($account);
    $r->subprocess_env(LOGIN => $override || $login);
    $r->subprocess_env(SEC_LEVEL => $securityLevel);
    if ($mustChangePassword) {
      $r->subprocess_env(TEMPFLAG => 1);
    }
    $r->subprocess_env(SECLEVEL => $securityLevel); # both used?  SEC_LEVEL and SECLEVEL?

    if ($override) {
      $r->subprocess_env(TECH => $login);
    }

    # return the account.
    return $account;
}

sub group {
    my ( $class, $r, $groups ) = @_;
    my @groups = split( WHITESPACE_REGEX, $groups );
    my $realm = $r->auth_name;

    # Get the configuration information.
    my %c = $class->_dbi_config_vars($r);

    my $rUser = $r->user || '';
    my $login = $r->subprocess_env('LOGIN') || $rUser;
    my ($override,$user) = split(/\s+/,$login);
    $user ||= $override;

    # filter user
    $user = '' if !defined $user;
    my $originalUser = $user;
    $user =~ s/[^a-zA-Z0-9_ ]//g;
    my $filtered = ($user ne $originalUser)
                 ? '(filtered)'
                 : '';

    if (!$user) {
      return Apache2::Const::AUTHZ_DENIED_NO_USER;
    }

    my $authenticator = new PlugNPay::Authentication();
    for my $group (@groups) {
      if ($authenticator->canAccess({'login' => $user, 'group' => $group, 'realm' => $realm})) {
        my $message = '[' . $user . ']' . $filtered . ' can access [' . $group . ']! ';
        $class->logger( $r, Apache2::Const::LOG_INFO, $message, $user, LOG_TYPE_AUTH, $r->uri );
        $r->subprocess_env( 'AUTH_COOKIE_DBI_GROUP' => $group );
        return Apache2::Const::AUTHZ_GRANTED
      }
    }

    my $message = ${class} . "\tuser [" . $user . ']' . $filtered . ' was not a member of any of the required groups ' . @groups . ' for auth realm ' . $realm;
    $class->logger( $r, Apache2::Const::LOG_INFO, $message, $user, LOG_TYPE_AUTH, $r->uri );

    return Apache2::Const::AUTHZ_DENIED;
}

#-------------------------------------------------------------------------------


sub logger {
    my ( $class, $r, $log_level, $message, $user, $log_type, @extra_args ) = @_;

    # $log_level should be an Apache constant, e.g. Apache2::Const::LOG_NOTICE

    # Sub-classes should override this method if they want to implent their
    # own logging strategy.
    #
    my @log_args = ( $message, @extra_args );

    my %apache_log_method_for_level = (
        Apache2::Const::LOG_DEBUG   => 'debug',
        Apache2::Const::LOG_INFO    => 'info',
        Apache2::Const::LOG_NOTICE  => 'notice',
        Apache2::Const::LOG_WARNING => 'warn',
        Apache2::Const::LOG_ERR     => 'error',
        Apache2::Const::LOG_CRIT    => 'crit',
        Apache2::Const::LOG_ALERT   => 'alert',
        Apache2::Const::LOG_EMERG   => 'emerg',
    );
    my $log_method = $apache_log_method_for_level{$log_level};
    if ( !$log_method ) {
        my ( $pkg, $file, $line, $sub ) = caller(1);
        $r->log_error(
            "Unknown log_level '$log_level' passed to logger() from $sub at line $line in $file "
        );
        $log_method = 'log_error';
    }
    $r->log->$log_method(@log_args);
}

1;

__END__

=head1 SUBCLASSING

You can subclass this module to override public functions and change
their behaviour.

=head1 CLASS METHODS

=head2 authen_cred($r, $user, $password, @extra_data)

Take the credentials for a user and check that they match; if so, return
a new session key for this user that can be stored in the cookie.
If there is a problem, return a bogus session key.

=head2 authen_ses_key($r, $encrypted_session_key)

Take a session key and check that it is still valid; if so, return the user.

=head2 decrypt_session_key($r, $encryptiontype, $encrypted_session_key, $secret_key)

Returns the decrypted session key or false on failure.

=head2 extra_session_info($r, $user, $password, @extra_data)

A stub method that you may want to override in a subclass.

This method returns extra fields to add to the session key.
It should return a string consisting of ":field1:field2:field3"
(where each field is preceded by a colon).

The default implementation returns an empty string.

=head2 group($r, $groups_string)

Take a string containing a whitespace-delimited list of groups and make sur
that the current remote user is a member of one of them.

Returns either I<Apache2::Const::HTTP_FORBIDDEN>
or I<Apache2::Const::OK>.

=head2 logger($r, $log_level, $message, $user, $log_type, @extra_args)

Calls one of the I<Apache::Log> methods with:

  ( $message, @extra_args )

for example, if the I<log_level> is I<Apache2::Const::LOG_DEBUG> then
this method will call:

  $r->log->debug( $message, @extra_args )

Sub-classes may wish to override this method to perform their own
logging, for example to log to a database.

I<$log_level> is one of the constants:

 Apache2::Const::LOG_DEBUG
 Apache2::Const::LOG_INFO
 Apache2::Const::LOG_NOTICE
 Apache2::Const::LOG_WARNING
 Apache2::Const::LOG_ERR
 Apache2::Const::LOG_CRIT
 Apache2::Const::LOG_ALERT
 Apache2::Const::LOG_EMERG

I<$message> is a text string.

I<$user> should be the username, could be undef in some cases.

I<$log_type> is always undef when called in this module, but
sub-classes may wish to use it when they override this method.

I<@extra_args> are appended to the call to the appropriate
I<Apache::Log> method. Usually this is simply the value of I<$r-E<gt>uri>.

=head2 user_is_active($r, $user)

If the C<DBI_UserActiveField> is not set then this method
returns true without checking the database (this is
the default behavior).

If C<DBI_UserActiveField> is set then this method checks the
database and returns the value in that field for this user.

=head1 DATABASE SCHEMAS

For this module to work, the database tables must be laid out at least somewhat
according to the following rules:  the user field must be a UNIQUE KEY
so there is only one row per user; the password field must be NOT NULL.  If
you're using MD5 passwords the password field must be 32 characters long to
allow enough space for the output of md5_hex().  If you're using crypt()
passwords you need to allow 13 characters. If you're using sha256_hex()
then you need to allow for 64 characters, for sha384_hex() allow 96 characters,
and for sha512_hex() allow 128.

An minimal CREATE TABLE statement might look like:

    CREATE TABLE users (
        user VARCHAR(16) PRIMARY KEY,
        password VARCHAR(32) NOT NULL
    )

For the groups table, the access table is actually going to be a join table
between the users table and a table in which there is one row per group
if you have more per-group data to store; if all you care about is group
membership though, you only need this one table.  The only constraints on
this table are that the user and group fields be NOT NULL.

A minimal CREATE TABLE statement might look like:

    CREATE TABLE groups (
        grp VARCHAR(16) NOT NULL,
        user VARCHAR(16) NOT NULL
    )

=head1 COPYRIGHT

 Copyright (C) 2002 SF Interactive.
 Copyright (C) 2003-2004 Jacob Davies
 Copyright (C) 2004-2010 Matisse Enzer

=head1 LICENSE

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=head1 CREDITS

  Original Author: Jacob Davies
  Incomplete list of additional contributors (alphabetical by first name):
    Carl Gustafsson
    Chad Columbus
    Jay Strauss
    Joe Ingersoll
    Keith Lawson
    Lance P Cleveland
    Matisse Enzer
    Nick Phillips
    William McKee

=head1 MAINTAINER

Matisse Enzer

        <matisse@cpan.org>

=head1 SEE ALSO

 Latest version: http://search.cpan.org/dist/Apache2-AuthCookieDBI

 PlugNPay::AuthCookie - http://search.cpan.org/dist/Apache2-AuthCookie
 Apache2::Session    - http://search.cpan.org/dist/Apache2-Session
 Apache::AuthDBI     - http://search.cpan.org/dist/Apache-DBI

=head1 TODO

=over 2

=item Improve test coverage.

=item Refactor authen_cred() and authen_ses_key() into several smaller private methods.

=item Refactor documentation.

=back

=cut
