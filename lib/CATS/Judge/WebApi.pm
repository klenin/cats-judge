package CATS::Judge::WebApi;

use strict;
use warnings;

use Encode;
use File::Spec;
use File::Temp;
use HTTP::Request::Common;
use JSON::XS;
use LWP::UserAgent;

use CATS::DevEnv;
use CATS::JudgeDB;

use base qw(CATS::Judge::Base);

sub new_from_cfg {
    my ($class, $cfg) = @_;
    $class->SUPER::new(
        name => $cfg->name, password => $cfg->cats_password,
        cats_url => $cfg->cats_url, no_sertificate => $cfg->no_certificate_check,
    );
}

# Based on http://www.perlmonks.org/?node_id=1078704 .
sub suppress_certificate_check {
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
    $ENV{HTTPS_DEBUG} = 1;
    IO::Socket::SSL::set_ctx_defaults(
         SSL_verifycn_scheme => 'www',
         SSL_verify_mode => 0,
    );
}

sub init {
    my ($self) = @_;

    $self->{agent} = LWP::UserAgent->new(requests_redirectable => [ qw(GET POST) ]);
    if ($self->{no_certificate_check}) {
        require IO::Socket::SSL;
        $self->{agent}->ssl_opts(verify_hostname => 0, SSL_verify_mode => 0x00);
    }
}

sub get_json {
    my ($self, $params, $headers) = @_;
    suppress_certificate_check if $self->{no_certificate_check};

    push @$params, json => 1;
    my $request = $self->{agent}->request(
        POST "$self->{cats_url}/", %{$headers // {}}, Content => $params);
    if ($request->{_rc} == 502) {
        # May be intermittent crash or proxy error. Retry once.
        warn "Error: $request->{_rc} '$request->{_msg}', retrying";
        $request = $self->{agent}->request(
            POST "$self->{cats_url}/", %{$headers // {}}, Content => $params);
    }
    die "Error: $request->{_rc} '$request->{_msg}'" unless $request->{_rc} == 200;
    decode_json($request->content);
}

sub auth {
    my ($self) = @_;

    my $response = $self->get_json([
        f => 'login',
        login => $self->{name},
        passwd => $self->{password},
    ]);
    die "Incorrect login and password" if $response->{status} eq 'error';
    $self->{sid} = $response->{sid};

    $response = $self->get_json([
        f => 'get_judge_id',
        sid => $self->{sid},
    ]);
    die "get_judge_id: $response->{error}" if $response->{error};
    $self->{id} = $response->{id};
}

sub update_dev_env {
    my ($self) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_des',
        sid => $self->{sid},
    ]);

    die "update_dev_env: $response->{error}" if $response->{error};

    $self->{dev_env} = CATS::DevEnv->new($response);
}

sub get_problem {
    my ($self, $pid) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_problem',
        pid => $pid,
        sid => $self->{sid},
    ]);

    die "get_problem: $response->{error}" if $response->{error};

    $response->{problem};
}

sub get_problem_sources {
    my ($self, $pid) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_problem_sources',
        pid => $pid,
        sid => $self->{sid},
    ]);

    die "get_problem_sources: $response->{error}" if $response->{error};

    $response->{sources};
}

sub get_problem_tests {
    my ($self, $pid) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_problem_tests',
        pid => $pid,
        sid => $self->{sid},
    ]);

    die "get_problem_tests: $response->{error}" if $response->{error};

    $response->{tests};
}

sub is_problem_uptodate {
    my ($self, $pid, $date) = @_;

    my $response = $self->get_json([
        f => 'api_judge_is_problem_uptodate',
        pid => $pid,
        date => $date,
        sid => $self->{sid},
    ]);

    die "is_problem_uptodate: $response->{error}" if $response->{error};

    $response->{uptodate};
}

sub save_log_dump {
    my ($self, $req, $dump) = @_;

    # IO::Socket::SSL fails when writing long data blocks.
    # LWP does not provide chunking directly, but
    # DYNAMIC_FILE_UPLOAD reads and transmits file by blocks of 2048 bytes.
    # No way to pass a file handle to HTTP::Request::Common, so create a real file.
    my $fh = File::Temp->new(TEMPLATE => 'logXXXXXXXX', DIR => File::Spec->tmpdir);
    print $fh Encode::encode_utf8($dump);
    $fh->flush;

    local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
    my $response = $self->get_json([
        f => 'api_judge_save_log_dump',
        req_id => $req->{id},
        dump => [ $fh->filename, 'log' ],
        sid => $self->{sid},
    ], { Content_Type => 'form-data' } );

    die "save_log_dump: $response->{error}" if $response->{error};
}

sub set_request_state {
    my ($self, $req, $state, %p) = @_;

    my $response = $self->get_json([
        f => 'api_judge_set_request_state',
        req_id => $req->{id},
        state => $state,
        problem_id => $p{problem_id},
        contest_id => $p{contest_id},
        failed_test => $p{failed_test} // '',
        sid => $self->{sid},
    ]);

    die "set_request_state: $response->{error}" if $response->{error};
}

sub select_request {
    my ($self) = @_;

    my $response = $self->get_json([
        f => 'api_judge_select_request',
        sid => $self->{sid},
        de_version => $self->{dev_env}->version,
        map "$_", CATS::JudgeDB::get_de_bitfields_hash(@{$self->{de_bitmap}}),
    ]);

    if ($response->{error}) {
        if ($response->{error} eq $cats::es_old_de_version) {
            warn 'updating des list';
            $self->update_dev_env();
            $self->update_de_bitmap();
            return;
        } else {
            die "select_request: $response->{error}"
        }
    }

    $self->{lock_counter} = $response->{lock_counter};
    $self->{was_pinged} = $response->{was_pinged};
    $response->{request};
}

sub delete_req_details {
    my ($self, $req_id) = @_;

    my $response = $self->get_json([
        f => 'api_judge_delete_req_details',
        req_id => $req_id,
        sid => $self->{sid},
    ]);

    die "delete_req_details: $response->{error}" if $response->{error};
}

sub insert_req_details {
    my ($self, $p) = @_;

    my $response = $self->get_json([
        f => 'api_judge_insert_req_details',
        params => encode_json($p),
        sid => $self->{sid},
    ]);

    die "insert_req_details: $response->{error}" if $response->{error};
}

sub save_input_test_data {
    my ($self, $problem_id, $test_rank, $input, $input_size) = @_;

    my $response = $self->get_json([
        f => 'api_judge_save_input_test_data',
        problem_id => $problem_id,
        test_rank => $test_rank,
        input => $input,
        input_size => $input_size,
        sid => $self->{sid},
    ]);

    die "save_input_test_data: $response->{error}" if $response->{error};
}

sub save_answer_test_data {
    my ($self, $problem_id, $test_rank, $answer, $answer_size) = @_;

    my $response = $self->get_json([
        f => 'api_judge_save_answer_test_data',
        problem_id => $problem_id,
        test_rank => $test_rank,
        answer => $answer,
        answer_size => $answer_size,
        sid => $self->{sid},
    ]);

    die "save_answer_test_data: $response->{error}" if $response->{error};
}

sub get_testset {
    my ($self, $req_id, $update) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_testset',
        req_id => $req_id,
        update => $update,
        sid => $self->{sid},
    ]);

    die "get_testset: $response->{error}" if $response->{error};

    %{$response->{testset}};
}

1;
