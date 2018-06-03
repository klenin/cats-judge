package CATS::Judge::DirectDatabase;

use strict;
use warnings;

use CATS::Config;
use CATS::Constants;
use CATS::DB qw($dbh);
use CATS::DevEnv;
use CATS::JudgeDB;
use CATS::Testset;
use CATS::Job;

use base qw(CATS::Judge::Base);

sub new_from_cfg {
    my ($class, $cfg) = @_;
    $class->SUPER::new(name => $cfg->name);
}

sub auth {
    my ($self) = @_;

    ($self->{id}, $self->{uid}, my $nick) = $dbh->selectrow_array(q~
        SELECT J.id, A.id, J.nick FROM judges J INNER JOIN accounts A ON J.account_id = A.id
        WHERE A.login = ?~, undef,
        $self->name);
    $self->{id} or die sprintf "unknown judge name: '%s'", $self->name;

    $nick eq $self->{name}
        or die "bad judge nick: $nick != $self->{name}";

    for (1..20) {
        $self->{sid} = $self->make_sid;
        if ($dbh->do(q~
            UPDATE accounts SET sid = ?, last_login = CURRENT_TIMESTAMP,
                last_ip = (
                    SELECT mon$remote_address
                    FROM mon$attachments M
                    WHERE M.mon$attachment_id = CURRENT_CONNECTION)
            WHERE id = ?~, undef,
            $self->{sid}, $self->{uid})
        ) {
            $dbh->commit;
            return;
        }
        sleep 1;
    }
    die "login failed\n";
}

sub is_locked { $_[0]->{lock_counter} }

sub set_request_state {
    my ($self, $req, $state, %p) = @_;

    CATS::JudgeDB::set_request_state({
        jid         => $self->{id},
        req_id      => $req->{id},
        state       => $state,
        contest_id  => $p{contest_id},
        problem_id  => $p{problem_id},
        failed_test => $p{failed_test},
    });
}

sub create_job {
    my ($self, $job_type, $p) = @_;
    $p->{judge_id} = $self->{id};
    my $job_id = CATS::Job::create($job_type, $p);
    $dbh->commit;
    $job_id;
}

sub finish_job {
    my ($self, $job_id, $job_state) = @_;
    CATS::JudgeDB::finish_job($job_id, $job_state);
}

sub select_request {
    my ($self) = @_;

    ($self->{was_pinged}, $self->{pin_mode}, my $current_sid, my $time_since_alive) = $dbh->selectrow_array(q~
        SELECT 1 - J.is_alive, J.pin_mode, A.sid, CURRENT_TIMESTAMP - J.alive_date
        FROM judges J INNER JOIN accounts A ON J.account_id = A.id WHERE J.id = ?~, undef,
        $self->{id});

    $current_sid eq $self->{sid}
        or die "killed: $current_sid != $self->{sid}";

    my $request = CATS::JudgeDB::select_request({
        jid              => $self->{id},
        was_pinged       => $self->{was_pinged},
        pin_mode         => $self->{pin_mode},
        time_since_alive => $time_since_alive,
        de_version       => $self->{dev_env}->version,
        CATS::JudgeDB::get_de_bitfields_hash(@{$self->{de_bitmap}}),
    });

    if ($request && $request->{error}) {
        if ($request->{error} eq $cats::es_old_de_version) {
            warn 'updating des list';
            $self->update_dev_env();
            $self->update_de_bitmap();
            return;
        } else {
            die "select_request error: $request->{error}";
        }
    }

    $request;
}

sub save_logs {
    my ($self, $job_id, $dump) = @_;
    CATS::JudgeDB::save_logs($job_id, $dump);
}

sub update_dev_env {
    my ($self) = @_;

    $self->{dev_env} = CATS::DevEnv->new(CATS::JudgeDB::get_DEs());
}

sub get_problem_sources {
    my ($self, $pid) = @_;
    CATS::JudgeDB::get_problem_sources($pid);
}

sub delete_req_details {
    my ($self, $req_id) = @_;
    CATS::JudgeDB::delete_req_details($req_id, $self->{id}) or die 'stolen';
}

sub insert_req_details {
    my ($self, $p) = @_;
    CATS::JudgeDB::insert_req_details(%$p, judge_id => $self->{id}) or die 'stolen';
}

sub save_problem_snippet {
    my ($self, @rest) = @_;
    CATS::JudgeDB::save_problem_snippet(@rest);
}

sub save_input_test_data {
    my ($self, @rest) = @_;
    CATS::JudgeDB::save_input_test_data(@rest);
}

sub save_answer_test_data {
    my ($self, @rest) = @_;
    CATS::JudgeDB::save_answer_test_data(@rest);
}

sub get_problem_tests {
    my ($self, $pid) = @_;
    CATS::JudgeDB::get_problem_tests($pid);
}

sub get_snippet_text {
    my ($self, @rest) = @_;
    CATS::JudgeDB::get_snippet_text(@rest);
}

sub get_problem_snippets {
    my ($self, $pid) = @_;
    CATS::JudgeDB::get_problem_snippets($pid);
}

sub get_problem_tags {
    my ($self, @rest) = @_;
    CATS::JudgeDB::get_problem_tags(@rest);
}

sub get_problem {
    my ($self, $pid) = @_;
    CATS::JudgeDB::get_problem($pid);
}

sub is_problem_uptodate {
    my ($self, $pid, $date) = @_;
    CATS::JudgeDB::is_problem_uptodate($pid, $date);
}

sub get_testset {
    my ($self, $rid, $update) = @_;
    CATS::Testset::get_testset($dbh, $rid, $update);
}

sub finalize {
    CATS::DB::sql_disconnect;
}

1;
