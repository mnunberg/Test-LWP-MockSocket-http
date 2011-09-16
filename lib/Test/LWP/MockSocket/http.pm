package Test::LWP::MockSocket::http;
#Hack into LWP's socket methods
use strict;
use warnings;
use base qw(Exporter);
use LWP::Protocol::http;
no warnings 'redefine';

*LWP::Protocol::http::socket_class = sub {
    '_LWP::FakeSocket';
};

our @EXPORT = qw($LWP_Response $LWP_SocketArgs);
our $VERSION = 0.01;
our ($LWP_Response, $LWP_SocketArgs);

package _LWP::FakeSocket;
use IO::String;
use base qw(IO::String);
use strict;
use warnings;
no warnings 'redefine';
Test::LWP::MockSocket::http->import();

my $n_passed = 0;
our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    my ($fn_name) = (split(/::/, $AUTOLOAD))[-1];
    my $meth = Net::HTTP::Methods->can($fn_name);
    if(!$meth) {
        return;
    }
    return $meth->($self, @_);
}

sub new {
    $n_passed = 0;
    my ($cls,%opts) = @_;
    $LWP_SocketArgs = \%opts;
    my $self = IO::String->new();
    bless $self, __PACKAGE__;
    return $self;
}

sub can_read {
    $LWP_Response && $n_passed >= 0;
}

sub configure {
    my $self = $_[0];
    #log_err("Configure Called!");
    return $self;
}

sub syswrite {
    my ($self,$buf,$length) = @_;
    $length ||= length($buf);
    return $length;
}

sub sysread {
    my ($self,$buf,$length) = @_;
    
    my $remaining_length = length($LWP_Response);
    $length = $remaining_length if $length > $remaining_length;
    my $blob = substr($LWP_Response, $n_passed, $length);
    if(!$blob) {
        #No data left. Maybe ConnCache is checking to see if we're still alive.
        #If we set this to -1, can_read will return false, and it will force the
        #creation of a new socket.
        $n_passed = -1;
        return undef;
    } else {
        $_[1] = $blob;
    }    
    $n_passed += $length;
    $self->close();
    return length($blob);
}

0xb00b135;

=head1 NAME

Test::LWP::MockSocket::http - Inject arbitrary data as socket data for LWP::UserAgent

=head1 SYNOPSIS

    use Test::LWP::MockSocket::http;
    use LWP::UserAgent;
    #   $LWP_Response is exported by this module
    $LWP_Response = "HTTP/1.0 200 OK\r\n\r\nSome Response Text";
    my $ua = LWP::UserAgent->new();
    $ua->proxy("http", "http://1.2.3.4:56");
    my $http_response = $ua->get("http://www.foo.com/bar.html");
    
    $http_response->code;       #200
    $http_response->content;    # "Some response text"
    $LWP_SocketArgs->{PeerAddr} # '1.2.3.4'

=head1 DESCRIPTION

This module, when loaded, mangles some functions in L<LWP::Protocol::http>
which will emulate a real socket. LWP is used as normally as much as possible.

Effort has been made to maintain the exact behavior of L<Net::HTTP> and L<LWP::Protocol::http>.

Two variables are exported, C<$LWP_Response> which should contain raw HTTP 'data',
and $LWP_SocketArgs which contains a hashref passed to the socket's C<new> constructor.
This is helpful for debugging complex LWP::UserAgent subclasses (or wrappers) which
modify possible connection settings.

=head1 CAVEATS/BUGS

Probably many. This relies on mainly undocumented behavior and features of LWP
and is likely to break. I wrote this for testing code which used LWP and its
subclasses heavily, but still desired the full functionality of LWP::UserAgent
(if you look closely enough, you will see that the same L<HTTP::Request> object which
is passed to LWP is not the actual one sent on the wire, and the L<HTTP::Response>
object returned by LWP methods is not the same one received on the wire).

=head1 ACKNOWLEDGEMENTS

Thanks to mst for helping me with the difficult task of selecting the module name
=head1 AUTHOR AND COPYRIGHT

Copyright 2011 M. Nunberg

You may use and distribute this software under the terms of the GNU General Public
License Version 2 or higher.