package CATS::Spawner::Program;

use strict;
use warnings;

sub new {
    my ($class, $app, $args, $opts) = @_;
    my $self = bless { app => $app, args => $args // [], opts => $opts // {} }, $class;
    $self;
}

sub make_params {
    my ($self) = @_;
    my @r = (
        i  => $self->opts->{stdin},
        se => $self->opts->{stderr},
        so => $self->opts->{stdout},
        tl => $self->opts->{time_limit},
        y  => $self->opts->{idle_time_limit},
        d  => $self->opts->{deadline},
        ml => $self->opts->{memory_limit},
        wl => $self->opts->{write_limit},
    );
    ($self->opts->{controller} ? '--controller' : ()),
    map {
        my ($name, $value) = splice @r, 0, 2;
        defined $value ? "-$name=$value" : ();
    } 1 .. @r / 2;
}

sub application { $_[0]->{app} }

sub arguments { $_[0]->{args} }

sub opts { $_[0]->{opts} }

sub set_expected_tr { $_[0]->{tr} = $_[1]; $_[0]; }

1;
