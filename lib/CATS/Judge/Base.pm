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

sub is_locked { 0 }

sub set_request_state { abstract @_ }

sub was_pinged { $_[0]->{was_pinged} }

sub select_request { abstract @_ }

sub save_log_dump {}

sub set_DEs { $_[1]->{$_}->{code} = $_[1]->{$_}->{id} = $_ for keys %{$_[1]} }

sub get_problem_sources { [] }

sub delete_req_details {}

sub insert_req_details {}

sub get_problem_tests { [] }

sub get_problem { {} }

sub is_problem_uptodate { 0 }

sub get_testset { (0) }

sub finalize {}

1;
