package CATS::Judge::Dummy;

use strict;
use warnings;

use CATS::Constants;

use base qw(CATS::Judge::Base);

my $dummy_counter = 0;
my $source = 'print "Hello world!\n"; open(H, ">output.txt") or die; print H q~bb~;';
my $file_name = 'test.pl';
my $de = 501; #perl
my $test_output = 'bb';
my $test_input = 'aa';

sub auth {
    my ($self) = @_;
    return;
}

sub is_locked {
    $dummy_counter = $dummy_counter + 1;
    $dummy_counter - 1;
}

sub set_request_state {
    my ($self, $req, $state, %p) = @_;
}

sub select_request {
    my ($self) = @_;
    {
        id => 0,
        problem_id => 0,
        contest_id => 0,
        state => 1,
        is_jury => 0,
        run_all_tests => 1,
        status => $cats::problem_st_ready,
        fname => $file_name,
        src => $source,
        de_id => $de,
    };
}

sub save_log_dump {
    my ($self, $req, $dump) = @_;
}

sub set_DEs {
    my ($self, $cfg_de) = @_;
    while (my ($key, $value) = each %$cfg_de) {
        $value->{code} = $value->{id} = $key;
    }
    $self->{supported_DEs} = join ',', sort { $a <=> $b } keys %$cfg_de;
}

sub get_problem_sources {
    my ($self, $pid) = @_;
    my $problem_sources = [{
        id => 0,
        stype => 0,
        problem_id => 0,
        de_id => $de,
        code => $de,
        src => $source,
        fname => $file_name,
        input_file => 'input.txt',
        output_file => 'output.txt',
        guid => 'guid',
        time_limit => 10,
        memory_limit => 10
    }];
    [ @$problem_sources ];
}

sub delete_req_details {
    my ($self, $req_id) = @_;
}

sub insert_req_details {
    my ($self, $p) = @_;
}

sub get_problem_tests {
    my ($self, $pid) = @_;
    [{
        generator_id => 1,
        rank => 0,
        param => 0,
        std_solution_id => 0,
        in_file => $test_input,
        out_file => $test_output,
        gen_group => 0
    }];
}

sub get_problem {
    my ($self, $pid) = @_;
    {
        id => 1,
        title => 'Dummy test',
        upload_date => 0,
        time_limit => 10,
        memory_limit => 10,
        input_file => 'input.txt',
        output_file => 'output.txt',
        std_checker => 'text',
        contest_id => 0
    };
}

sub is_problem_uptodate { 1 }

sub get_testset { (0) }

1;
