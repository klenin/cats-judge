package CATS::Judge::Local;

use strict;
use warnings;

use CATS::Constants;

use base qw(CATS::Judge::Base);

sub auth {
    my ($self) = @_;
    return;
}

sub update_state {
    my ($self) = @_;
    0;
}

sub set_request_state {
    my ($self, $req, $state, %p) = @_;
}

sub select_request {
    my ($self, $supported_DEs) = @_;
    die 'Not implement yet';
}

sub save_log_dump {
    my ($self, $req, $dump) = @_;
}

sub set_DEs {
    my ($self, $cfg_de) = @_;
    die 'Not implement yet';
}

sub get_problem_sources {
    my ($self, $pid) = @_;
    die 'Not implement yet';
}

sub delete_req_details {
    my ($self, $req_id) = @_;
}

sub insert_req_details {
    my ($self, $p) = @_;
}

sub get_problem_tests {
    my ($self, $pid) = @_;
    die 'Not implement yet';
}

sub get_problem {
    my ($self, $pid) = @_;
    die 'Not implement yet';
}

sub is_problem_uptodate { 1 }

sub get_testset { (0) }

1;
