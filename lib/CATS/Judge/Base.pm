package CATS::Judge::Base;

use strict;
use warnings;

our $timestamp_format = '%d-%m-%Y %H:%M:%S';

sub new {
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
    $self->init();
    $self;
}

sub init {}

sub abstract { die sprintf "%s::%s is abstract", ref $_[0], (caller 1)[3] =~ /([^:]+)$/; }

sub name { $_[0]->{name} }

my @sid_alph = ('0'..'9', 'A'..'Z', 'a'..'z');
sub make_sid { join '', map $sid_alph[rand @sid_alph], 1..30 }

sub auth { $_[0]->{sid} = $_[0]->make_sid; 1; }

sub set_request_state { abstract @_ }

sub was_pinged { $_[0]->{was_pinged} }

sub select_request { abstract @_ }

sub save_log_dump {}

sub set_DEs {
    my ($self, $cfg_de) = @_;

    $self->update_dev_env();

    for my $de (@{$self->{dev_env}->des}) {
        my $c = $de->{code};
        $cfg_de->{$c} &&= { %{$cfg_de->{$c}}, %$de };
    }

    delete @$cfg_de{grep !exists $cfg_de->{$_}->{code}, keys %$cfg_de};
    $self->{supported_DEs} = [ sort { $a <=> $b } keys %$cfg_de ];
    $self->update_de_bitmap();
}

sub update_de_bitmap {
    my ($self) = @_;
    $self->{de_bitmap} = [ $self->{dev_env}->bitmap_by_codes(@{$self->{supported_DEs}}) ];
}

sub get_problem_sources { [] }

sub delete_req_details {}

sub insert_req_details {}

sub save_input_test_data {}

sub save_answer_test_data {}

sub get_problem_tests { [] }

sub get_problem { {} }

sub is_problem_uptodate { 0 }

sub get_testset { (0) }

sub finalize {}

1;
