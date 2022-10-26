package CATS::Judge::DirectDatabase;

use strict;
use warnings;

use CATS::Config;
use CATS::Constants;
use CATS::DB qw($dbh);
use CATS::DeBitmaps;
use CATS::DevEnv;
use CATS::Job;
use CATS::JudgeDB;
use CATS::Testset;

use base qw(CATS::Judge::Base);

sub new_from_cfg {
    my ($class, $cfg) = @_;
    $class->SUPER::new(name => $cfg->name);
}

sub _set_sid {
    my ($self) = @_;
    for (1..20) {
        $self->{sid} = $self->make_sid;
        return 1 if $dbh->do(qq~
            UPDATE accounts SET sid = ?, last_login = CURRENT_TIMESTAMP,
                last_ip = ($CATS::DB::db->{LAST_IP_QUERY})
            WHERE id = ?~, undef,
            $self->{sid}, $self->{uid});
        sleep 1;
    }

    die "login failed\n";
}

sub auth {
    my ($self) = @_;

    ($self->{id}, $self->{uid}, my $nick, my $old_version) = $dbh->selectrow_array(q~
        SELECT J.id, A.id, J.nick, J.version
        FROM judges J INNER JOIN accounts A ON J.account_id = A.id
        WHERE A.login = ?~, undef,
        $self->name);
    $self->{id} or die sprintf "unknown judge name: '%s'", $self->name;

    $nick eq $self->{name}
        or die "bad judge nick: $nick != $self->{name}";
    $self->_set_sid;
    $dbh->do(q~
        UPDATE judges SET version = ? WHERE id = ?~, undef,
        $self->version, $self->{id}) if ($old_version // '') ne $self->version;
    $dbh->commit;
}

sub is_locked { $_[0]->{lock_counter} }

sub can_split { CATS::JudgeDB::can_split; }

sub set_request_state {
    my ($self, $req, $state, $job_id, %p) = @_;

    CATS::JudgeDB::set_request_state({
        jid         => $self->{id},
        req_id      => $req->{id},
        state       => $state,
        job_id      => $job_id,
        account_id  => $p{account_id},
        contest_id  => $p{contest_id},
        problem_id  => $p{problem_id},
        failed_test => $p{failed_test},
    });
}

sub create_splitted_jobs {
    my ($self, $job_type, $testsets, $p) = @_;
    CATS::Job::create_splitted_jobs($job_type, $testsets, $p);
    $dbh->commit;
}

sub create_job {
    my ($self, $job_type, $p) = @_;
    $p->{judge_id} = $self->{id};
    my $job_id = CATS::Job::create($job_type, $p);
    $dbh->commit;
    $job_id;
}

sub cancel_all {
    my ($self, $req_id) = @_;
    CATS::Job::cancel_all($req_id);
}

sub finish_job {
    my ($self, $job_id, $job_state) = @_;
    CATS::Job::finish($job_id, $job_state);
}

sub get_tests_req_details {
    my ($self, $req_id) = @_;
    CATS::JudgeDB::get_tests_req_details($req_id);
}

sub is_set_req_state_allowed {
    my ($self, $job_id, $force) = @_;
    CATS::JudgeDB::is_set_req_state_allowed($job_id, $force);
}

sub select_request {
    my ($self) = @_;

    ($self->{was_pinged}, $self->{pin_mode}, my $current_sid, my $time_since_alive) = $dbh->selectrow_array(q~
        SELECT 1 - J.is_alive, J.pin_mode, A.sid, CAST(CURRENT_TIMESTAMP - J.alive_date AS DOUBLE PRECISION)
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
        CATS::DeBitmaps::get_de_bitfields_hash(@{$self->{de_bitmap}}),
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
    my ($self, $req_id, $job_id) = @_;
    CATS::JudgeDB::delete_req_details($req_id, $self->{id}, $job_id);
}

sub insert_req_details {
    my ($self, $job_id, $p) = @_;
    CATS::JudgeDB::insert_req_details($job_id, %$p, judge_id => $self->{id});
}

sub save_problem_snippets {
    my ($self, @rest) = @_;
    CATS::JudgeDB::save_problem_snippets(@rest);
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
    my ($self, $table, $id, $update) = @_;
    CATS::Testset::get_testset($dbh, $table, $id, $update);
}

sub finalize {
    CATS::DB::sql_disconnect;
}

1;
