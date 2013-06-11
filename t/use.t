use strict;
use warnings;
use Test::More;
use IO::Socket::INET;
use Net::EmptyPort 'empty_port';
use Time::HiRes 'time';

BEGIN { use_ok 'Protocol::OSC' }
my $p = Protocol::OSC->new;
my $port = empty_port(undef, 'udp');
my @spec = (time,[qw(/echo isf 3 aaba 3.1)],[qw(/echo ii 3 1)]);

my $in = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $port, qw(Proto udp Type), SOCK_DGRAM ) || die $!;
$in->blocking(0);
my $client = IO::Socket::INET->new( qw(PeerAddr localhost PeerPort), $port, qw(Proto udp Type), SOCK_DGRAM ) || die $!;
$client->send($p->bundle(@spec));
$in->recv(my $packet, $in->sockopt(SO_RCVBUF));

ok $p->parse($packet)->[0] eq $spec[0], 'bundle in-out - udp';

$port = empty_port(undef, 'tcp');
$in = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $port, qw(Proto tcp Type), SOCK_STREAM, qw(Listen 1 Reuse 1) ) || die $!;
$in->blocking(0);
$client = IO::Socket::INET->new( qw(PeerAddr localhost PeerPort), $port, Proto => 'tcp', Type => SOCK_STREAM ) || die $!;
$client->send($p->to_stream($p->bundle(@spec)));
$in->accept->recv($packet = undef, $in->sockopt(SO_RCVBUF));

ok $p->parse(($p->from_stream($packet))[0])->[0] eq $spec[0], 'bundle in-out - tcp';

$p->set_cb('/echo', sub { 
    ok !defined($_[0]), 'process 1';
    ok $_[2]->type eq 'isf', 'process 2';
});
$p->process($p->message(@{$spec[1]}));

done_testing;
