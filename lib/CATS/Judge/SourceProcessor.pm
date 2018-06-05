package CATS::Judge::SourceProcessor;

use strict;
use warnings;

sub new {
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
    $self->cfg && $self->fu && $self->log or die;
    $self;
}

sub cfg { $_[0]->{cfg} }
sub fu { $_[0]->{fu} }
sub log { $_[0]->{log} }

sub init_DEs {
    my ($self) = @_;
    $self->{de_idx} = {};
    $self->{de_idx}->{$_->{id}} = $_ for values %{$self->cfg->DEs};
}

sub property {
    my ($self, $name, $de_id) = @_;
    exists $self->{de_idx}->{$de_id} or die "undefined de_id: $de_id";
    $self->{de_idx}->{$de_id}->{$name};
}

sub memory_handicap {
    my ($self, $de_id) = @_;
    $self->{de_idx}->{$de_id}->{memory_handicap} // 0;
}

sub encoding {
    my ($self, $de_id) = @_;
    $self->{de_idx}->{$de_id}->{encoding};
}

# sources: [ { de_id, code } ]
sub unsupported_DEs {
    my ($self, $sources) = @_;
    map { $_->{code} => 1 } grep !exists $self->{de_idx}->{$_->{de_id}}, @$sources;
}

1;
