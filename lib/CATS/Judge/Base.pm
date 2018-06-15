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

sub can_split { 0 }

sub set_request_state { abstract @_ }

sub was_pinged { $_[0]->{was_pinged} }

sub select_request { abstract @_ }

sub create_splitted_jobs {}

sub create_job { 0 }

sub get_tests_req_details { [] }

sub is_set_req_state_allowed { (0, 1) }

sub finish_job { 1 }

sub save_logs {}

sub quick_check_de {
    my ($de) = @_;
    exists $de->{code} or return 0;
    # Special and legacy DEs are not checked.
    my $c = $de->{compile} or return 1;
    $c =~ /^"([^"]+)"|^(\S+)\s/ or return 0;
    my $fn = $1 // $2;
    my $ok = -e $fn or print STDERR "Warning: DE $de->{code} not found at: $fn\n";
    $ok;
}

sub set_DEs {
    my ($self, $cfg_de) = @_;

    $self->update_dev_env;

    for my $de (@{$self->{dev_env}->des}) {
        my $c = $de->{code};
        $cfg_de->{$c} &&= { %{$cfg_de->{$c}}, %$de };
    }

    delete @$cfg_de{grep !quick_check_de($cfg_de->{$_}), sort keys %$cfg_de};
    $self->{supported_DEs} = [ sort { $a <=> $b } keys %$cfg_de ];
    $self->update_de_bitmap;
}

sub update_dev_env {}

sub update_de_bitmap {
    my ($self) = @_;
    $self->{de_bitmap} = [ $self->{dev_env}->bitmap_by_codes(@{$self->{supported_DEs}}) ];
}

sub save_problem_snippet {}

sub get_problem_sources { [] }

sub delete_req_details { 1 }

sub insert_req_details { 1 }

sub save_input_test_data {}

sub save_answer_test_data {}

sub get_problem_tests { [] }

sub get_problem_snippets { [] }

sub get_snippet_text { '' }

sub get_problem { {} }

sub is_problem_uptodate { 0 }

sub get_testset { (0) }

sub finalize {}

1;
