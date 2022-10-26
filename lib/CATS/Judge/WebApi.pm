package CATS::Judge::WebApi;

use strict;
use warnings;

use Encode;
use File::Spec;
use File::Temp;
use HTTP::Request::Common;
use JSON::XS;
use LWP::UserAgent;
use MIME::Base64 ();

use CATS::DeBitmaps;
use CATS::DevEnv;

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
        lang => 'en',
    ]);
    die sprintf "Auth failed: '%s'", $response->{message} // '' if $response->{status} eq 'error';
    $self->{sid} = $response->{sid};

    $response = $self->get_json([
        f => 'get_judge_id',
        sid => $self->{sid},
        version => $self->version,
    ]);
    die "get_judge_id: $response->{error}" if $response->{error};
    $self->{id} = $response->{id};
}

sub can_split {
    1; # TODO:     my $response = $self->get_json([ f => 'api_judge_can_split', sid => $self->{sid},]);
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

sub get_problem_snippets {
    my ($self, $pid) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_problem_snippets',
        pid => $pid,
        sid => $self->{sid},
    ]);

    die "get_problem_snippets: $response->{error}" if $response->{error};

    $response->{snippets};
}

sub get_problem_tags {
    my ($self, $pid, $cid, $aid) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_problem_tags',
        pid => $pid,
        cid => $cid,
        aid => $aid,
        sid => $self->{sid},
    ]);

    die "get_problem_tags: $response->{error}" if $response->{error};

    $response->{tags};
}

sub get_snippet_text {
    my ($self, $problem_id, $contest_id, $account_id, $names) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_snippet_text',
        pid => $problem_id,
        cid => $contest_id,
        uid => $account_id,
        (map { +name => $_ } @$names),
        sid => $self->{sid},
    ]);

    die "get_snippet_text: $response->{error}" if $response->{error};

    $response->{texts};
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

sub save_logs {
    my ($self, $job_id, $dump) = @_;

    # IO::Socket::SSL fails when writing long data blocks.
    # LWP does not provide chunking directly, but
    # DYNAMIC_FILE_UPLOAD reads and transmits file by blocks of 2048 bytes.
    # No way to pass a file handle to HTTP::Request::Common, so create a real file.
    my $fh = File::Temp->new(TEMPLATE => 'logXXXXXXXX', DIR => File::Spec->tmpdir);
    print $fh Encode::encode_utf8($dump);
    $fh->flush;

    local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
    my $response = $self->get_json([
        f => 'api_judge_save_logs',
        job_id => $job_id,
        dump => [ $fh->filename, 'log' ],
        sid => $self->{sid},
    ], { Content_Type => 'form-data' } );

    die "save_logs: $response->{error}" if $response->{error};
}

sub set_request_state {
    my ($self, $req, $state, $job_id, %p) = @_;

    my $response = $self->get_json([
        f => 'api_judge_set_request_state',
        req_id => $req->{id},
        state => $state,
        job_id => $job_id,
        account_id  => $p{account_id},
        problem_id => $p{problem_id},
        contest_id => $p{contest_id},
        failed_test => $p{failed_test} // '',
        sid => $self->{sid},
    ]);

    die "set_request_state: $response->{error}" if $response->{error};

    $response->{result};
}

sub is_set_req_state_allowed {
    my ($self, $job_id, $force) = @_;
    my $response = $self->get_json([
        f => 'api_judge_is_set_req_state_allowed',
        job_id => $job_id,
        force => $force,
        sid => $self->{sid},
    ]);

    die "is_set_req_state_allowed: $response->{error}" if $response->{error};

    ($response->{parent_id}, $response->{allow_set_req_state});
}

sub create_splitted_jobs {
    my ($self, $job_type, $testsets, $p) = @_;
    warn join(' ', @$testsets);
    my $response = $self->get_json([
        f => 'api_judge_create_splitted_jobs',
        job_type => $job_type,
        problem_id => $p->{problem_id},
        contest_id => $p->{contest_id},
        req_id => $p->{req_id},
        state => $p->{state},
        parent_id => $p->{parent_id},
        sid => $self->{sid},
        (map +(testsets => $_), @$testsets),
    ]);

    die "create_splitted_jobs: $response->{error}" if $response->{error};
}

sub cancel_all {
    my ($self, $req_id) = @_;

    my $response = $self->get_json([
        f => 'api_judge_cancel_all',
        req_id => $req_id,
        sid => $self->{sid},
    ]);

    die "cancel_all: $response->{error}" if $response->{error};
}

sub create_job {
    my ($self, $job_type, $p) = @_;

    my $response = $self->get_json([
        f => 'api_judge_create_job',
        job_type => $job_type,
        problem_id => $p->{problem_id},
        state => $p->{state},
        parent_id => $p->{parent_id},
        sid => $self->{sid},
    ]);

    die "create_job: $response->{error}" if $response->{error};
    $response->{job_id};
}

sub finish_job {
    my ($self, $job_id, $job_state) = @_;

    my $response = $self->get_json([
        f => 'api_judge_finish_job',
        job_id => $job_id,
        job_state => $job_state,
        sid => $self->{sid},
    ]);

    die "finish_job: $response->{error}" if $response->{error};
    $response->{result};
}

sub select_request {
    my ($self) = @_;

    my $response = $self->get_json([
        f => 'api_judge_select_request',
        sid => $self->{sid},
        de_version => $self->{dev_env}->version,
        map "$_", CATS::DeBitmaps::get_de_bitfields_hash(@{$self->{de_bitmap}}),
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
    my ($self, $req_id, $job_id) = @_;

    my $response = $self->get_json([
        f => 'api_judge_delete_req_details',
        req_id => $req_id,
        job_id => $job_id,
        sid => $self->{sid},
    ]);

    die "delete_req_details: $response->{error}" if $response->{error};

    $response->{result};
}

sub get_tests_req_details {
    my ($self, $req_id) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_tests_req_details',
        req_id => $req_id,
        sid => $self->{sid},
    ]);

    die "get_tests_req_details: $response->{error}" if $response->{error};

    $response->{req_details};
}

my @req_retails_params = qw(
    output output_size req_id test_rank result time_used memory_used disk_used checker_comment points);

sub insert_req_details {
    my ($self, $job_id, $p) = @_;

    if (exists $p->{output}) {
        $p->{output} = MIME::Base64::encode_base64($p->{output}, '');
    }
    my $response = $self->get_json([
        f => 'api_judge_insert_req_details',
        job_id => $job_id,
        (map { exists $p->{$_} ? ($_ => $p->{$_}) : () } @req_retails_params),
        sid => $self->{sid},
    ]);

    die "insert_req_details: $response->{error}" if $response->{error};

    $response->{result};
}

sub save_input_test_data {
    my ($self, $problem_id, $test_rank, $input, $input_size, $hash) = @_;

    my $response = $self->get_json([
        f => 'api_judge_save_input_test_data',
        problem_id => $problem_id,
        test_rank => $test_rank,
        input => MIME::Base64::encode_base64($input // '', ''),
        input_size => $input_size,
        hash => $hash,
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
        answer => MIME::Base64::encode_base64($answer, ''),
        answer_size => $answer_size,
        sid => $self->{sid},
    ]);

    die "save_answer_test_data: $response->{error}" if $response->{error};
}

# snippets: { name => text }
sub save_problem_snippets {
    my ($self, $problem_id, $contest_id, $account_id, $snippets) = @_;

    my $response = $self->get_json([
        f => 'api_judge_save_problem_snippets',
        problem_id => $problem_id,
        contest_id => $contest_id,
        account_id => $account_id,
        (map { +name => $_ } sort keys %$snippets),
        (map { +text => $snippets->{$_} // '' } sort keys %$snippets),
        sid => $self->{sid},
    ]);

    die "save_problem_snippet: $response->{error}" if $response->{error};
    1;
}

sub get_testset {
    my ($self, $table, $id, $update) = @_;

    my $response = $self->get_json([
        f => 'api_judge_get_testset',
        table => $table,
        id => $id,
        update => $update,
        sid => $self->{sid},
    ]);

    die "get_testset: $response->{error}" if $response->{error};

    %{$response->{testset}};
}

1;
