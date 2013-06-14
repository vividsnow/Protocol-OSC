use strict;
use warnings;
use Test::More;
use IO::Socket::INET;
use Test::TCP 'test_tcp';
use Time::HiRes qw(time usleep);
use Net::EmptyPort 'empty_port';

BEGIN { use_ok 'Protocol::OSC' }
my $p = Protocol::OSC->new;
my @spec = (time,[qw(/echo isf 3 aaba 3.1)],[qw(/echo ii 3 1)]);

if (my $port = empty_port(undef, 'udp')) {
    my $in = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $port, qw(Proto udp Type), SOCK_DGRAM );
    my $client = IO::Socket::INET->new( qw(PeerAddr localhost PeerPort), $port, qw(Proto udp Type), SOCK_DGRAM );
    $client->send($p->bundle(@spec));
    usleep 0.2e6;
    $in->recv(my $packet, $in->sockopt(SO_RCVBUF));
    ok($p->parse($packet)->[0] eq $spec[0], 'bundle in-out - udp') if $packet;
}

test_tcp(
    client => sub {
        my ($port, $server_pid) = @_;
        my $client = IO::Socket::INET->new( qw(PeerAddr localhost PeerPort), $port, qw(Proto tcp Type), SOCK_STREAM );
        $client->send($p->to_stream($p->bundle(@spec)));
        usleep 0.2e6;
    },
    server => sub {
        my $port = shift;
        my $in = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $port, qw(Proto tcp Type), SOCK_STREAM, qw(Listen 1),
            $^O eq 'MSWin32' ? () : (ReuseAddr => 1) );
        while (my $sock = $in->accept) {
            $sock->recv(my $packet, $in->sockopt(SO_RCVBUF));
            ok($p->parse(($p->from_stream($packet))[0])->[0] eq $spec[0], 'bundle in-out - tcp') if $packet;
        }
    }
);

$p->set_cb('/echo', sub { 
    ok !defined($_[0]), 'process 1';
    ok $_[2]->type eq 'isf', 'process 2';
});
$p->process($p->message(@{$spec[1]}));

done_testing;
