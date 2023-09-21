package PlugNPay::ResponseLink::LocalProxy::Request;

use strict;
use warnings FATAL => 'all';

use JSON::XS;
use MIME::Base64;

=pod

=head1 B<PlugNPay::ResponseLink::LocalProxy::Request>

Request Object for sending an http(s) request through the responselink proxy

=cut

sub new {
    my $class = shift;
    my $self = {};
    bless $self,$class;
    return $self;
}

=pod

=head2 I<setMethod>

=head4 Inputs:

=over 4

=item * method: string, HTTP method (gets lowercased)

=back

=cut

sub setMethod {
    my $self = shift;
    my $method = shift;
    $self->{'method'} = lc $method;
}

=pod

=head2 I<getMethod>

=head4 Outputs:

=over 4

=item * method: string, HTTP method (gets lowercased)

=back

=cut

sub getMethod {
    my $self = shift;
    return $self->{'method'};
}

=pod

=head2 I<setUrl>

=head4 Inputs:

=over 4

=item * url: string, HTTP url

=back

=cut

sub setUrl {
    my $self = shift;
    my $url = shift;
    $self->{'url'} = $url;
}

=pod

=head2 I<getUrl>

=head4 Outputs:

=over 4

=item * url: string, HTTP url

=back

=cut

sub getUrl {
    my $self = shift;
    return $self->{'url'};
}

=pod

=head2 I<addHeader>

=head4 Inputs:

=over 4

=item * headerName: string, header to add

=item * headerValue: string, value for header

=back

=cut

sub addHeader {
    my $self = shift;
    my $headerName = shift;
    my $headerValue = shift;

    if (!defined $headerName || $headerName eq '') {
        die('invalid header name');
    }

    if (!defined $headerValue || $headerValue eq '') {
        die('invalid header value');
    }

    if (!defined $self->{'headers'}) {
        $self->{'headers'} = {};
    }

    if (!defined $self->{'headers'}{$headerName}) {
        $self->{'headers'}{$headerName} = [];
    }

    push @{$self->{'headers'}{$headerName}}, $headerValue;
}

=pod

=head2 I<removeHeader>

=head4 Inputs:

=over 4

=item * headerName: string, header to remove

=item * headerValue: string, optional, to remove a specific value for a header if it has multiple values

=back

=cut

sub removeHeader {
    my $self = shift;
    my $headerName = shift;
    my $headerValue = shift || '';

    if (!defined $headerName || $headerName eq '') {
        die('invalid header name');
    }

    my @updatedValues;

    if (!defined $self->{'headers'}) {
        return
    }

    if (!defined $self->{'headers'}{$headerName}) {
        return
    }

    foreach my $value (@{$self->{'headers'}{$headerName}}) {
       if ($headerValue eq '' || $headerValue eq $value) {
         next;
       }
       push @updatedValues, $value;
    }

    if (@updatedValues > 0) {
      $self->{'headers'}{$headerName} = \@updatedValues;
    } else {
        delete $self->{'headers'}{$headerName};
    }
}

=pod

=head2 I<getHeaders>

=head4 Outputs:

=over 4

=item * headers: map[string][]string, 

=back

=cut

sub getHeaders {
    my $self = shift;

    my %headers;

    foreach my $headerName (keys %{$self->{'headers'}}) {
        my @headerValues = @{$self->{'headers'}{$headerName}};
        $headers{$headerName} = \@headerValues;
    }

    return \%headers;
}

=pod

=head2 I<setContent>

=head4 Inputs:

=over 4

=item * content: string, HTTP body content


=back

=cut

sub setContent {
    my $self = shift;
    my $content = shift;
    $self->{'content'} = $content;
}

=pod

=head2 I<getContent>

=head4 Outputs:

=over 4

=item * content: string, HTTP body content

=back

=cut

sub getContent {
    my $self = shift;
    return $self->{'content'};
}

=pod

=head2 I<setContentType>

=head4 Inputs:

=over 4

=item * content: string, HTTP body content type


=back

=cut

sub setContentType {
    my $self = shift;
    my $contentType = shift;
    $self->{'contentType'} = $contentType;
}

=pod

=head2 I<getContentType>

=head4 Outputs:

=over 4

=item * contentType: string, HTTP body content type

=back

=cut

sub getContentType {
    my $self = shift;
    return $self->{'contentType'};
}

=pod

=head2 I<setInsecure>

=head4 Turns off TLS certificate and host validation

=cut

sub setInsecure {
    my $self = shift;
    $self->{'insecure'} = 1;
}

=pod

=head2 I<setInsecure>

=head4 Turns on TLS certificate and host validation


=cut

sub setSecure {
    my $self = shift;
    $self->{'insecure'} = 0;
}

=pod

=head2 I<getInsecure>

=head4 Outputs:

=over 4

=item * insecure: 1 if TLS certificate validation is turned off, 0 if turned on

=back

=cut

sub getInsecure {
    my $self = shift;
    return $self->{'insecure'} ? 1 : 0;
}

=pod

=head2 I<setTimeoutSeconds>

=head4 Inputs:

=over 4

=item * seconds: float, number of seconds to timeout.

=back

=cut

sub setTimeoutSeconds {
    my $self = shift;
    my $seconds = shift;

    if ($seconds !~ /^[0-9]*(\.[0-9]*)?$/) {
        die("invalid floating point value $seconds");
    }

    if ($seconds < 0) {
        die("seconds can not be negative");
    }

    $self->{'seconds'} = $seconds;
}

=pod

=head2 I<getTimeoutSeconds>

=head4 Outputs:

=over 4

=item * seconds: number of seconds for request to timeout after

=back

=cut

sub getTimeoutSeconds {
    my $self = shift;
    return ($self->{'seconds'} || 0) + 0;
}

=pod

=head2 I<getJson>

=head4 Outputs:

=over 4

=item * json: string, JSON text representation of request

=back

=cut

sub toJson {
    my $self = shift;

    my $coder = JSON::XS->new->ascii();

    my $bools = $coder->decode('[false,true]');
    my ($false,$true) = @{$bools};

    my $base64Content = encode_base64($self->getContent() || '');

    my $data = {
        method => $self->getMethod(),
        url => $self->getUrl(),
        headers => $self->getHeaders(),
        contentType => $self->getContentType(),
        content => $base64Content,
        insecure => $self->getInsecure() ? $true : $false,
        timeoutSeconds => $self->getTimeoutSeconds()
    };

    my $jsonData = $coder->encode($data);

    return $jsonData;
}

1;