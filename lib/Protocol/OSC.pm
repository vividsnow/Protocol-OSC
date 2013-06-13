# ABSTRACT: Open Sound Control v1.1 protocol implementation
use strict;
use warnings;
package Protocol::OSC;
use Scalar::Util 'looks_like_number';
use constant { NTP_EPOCH_DIFF => 2208988800, MAX_INT => 1 << 32 };
my %converter = qw(i N f f> d d> s Z*x!4 b N/C*x!4 h h t N2);
sub new { bless {
    scheduler => sub { $_[0]->(splice @_, 1) },
    actions => {},
    splice(@_, 1),
}, shift }
sub parse {
    my ($self, $data) = @_;
    if ((my $f = substr $data, 0, 1) eq '#') { # bundle
        my (undef, $time, $fraction, @msgs) = unpack 'Z8N2(N/A*)*', $data;
        Protocol::OSC::Bundle->new($self->tag2time($time, $fraction), map $self->parse($_), @msgs);
    } elsif ($f eq '/') { # message
        my ($path, $type, $args) = unpack '(Z*x!4)2A*', $data;
        substr $type, 0, 1, '';
        Protocol::OSC::Message->new( $path, $type,
            unpack join('', map $converter{$_} || (), split '', $type), pack 'Z*x!4', $args );
    } else { warn 'broken osc packet' }
}
sub bundle {
    my ($self, $time, @msgs) = @_;
    pack 'Z8N2(N/A*)*', '#bundle', $self->time2tag($time), map {
        $self->${\( defined $_->[0] && !looks_like_number $_->[0] ? 'message' : 'bundle' )}(@{$_})
    } @msgs;
}
*msg = \&message;
sub message {
    my ($self, $path, $type, @args) = @_;
    pack '(Z*x!4)2A*', $path, ','.$type,
        join '', map pack($converter{$_}, shift@args),
        grep exists$converter{$_}, split //, $type;
}
sub process {
    my ($self, $packet, $scheduler_cb, $at_time, @bundle) = @_;
    if ((my $r = ref$packet) eq 'Protocol::OSC::Bundle') {
        map $self->process($_, $scheduler_cb, $packet->[0], $packet, @bundle), splice @$packet, 1;
    } elsif ($r eq 'Protocol::OSC::Message') {
        map {
            ( $scheduler_cb || $self->{scheduler} )->($_->[1], $at_time, $_->[0], $packet, @bundle)
        } $self->match($packet->[0]);
    } else { $self->process($self->parse($packet), $scheduler_cb, $at_time, @bundle) }
}
sub actions { $_[0]->{actions} }
sub set_cb { $_[0]->{actions}->{$_[1]} = $_[2] }
sub del_cb { delete $_[0]->{actions}->{$_[1]} }
sub match {
    my ($self, $pattern) = @_;
    $pattern =~ s!(\*|//)!.+!g;
    $pattern =~ y/?{},!/.()^|/;
    map [$_, $self->{actions}->{$_}], grep /^$pattern$/, keys%{$self->{actions}};
}
sub tag2time {
    my ($self, $secs, $frac) = @_;
    return undef if !$secs && $frac == 1;
    $secs - NTP_EPOCH_DIFF + $frac / MAX_INT;
}
sub time2tag {
    my ($self, $t) = @_;
    return (0, 1) unless $t;
    my $secs = int($t);
    ( $secs + NTP_EPOCH_DIFF, int MAX_INT * ($t - $secs) );
}
sub to_stream { pack 'N/A*' => $_[1] }
sub from_stream {
    my ($self, $buf) = @_;
    return $buf if length $buf < 4;
    my $n = unpack 'N', substr $buf, 0, 4;
    return $buf if length $buf < $n + 4;
    (unpack('N/A*', substr $buf, 0, 4+$n, ''), $buf);
}

package Protocol::OSC::Message;
sub new { bless [splice(@_,1)], shift }
sub path { $_[0]->[0] }
sub type { $_[0]->[1] }
sub args { my $self = shift; @$self[2..$#$self] }

package Protocol::OSC::Bundle;
sub new { bless [splice(@_,1)], shift }
sub time { $_[0]->[0] }
sub packets { my $self = shift; @$self[1..$#$self] }

1;
