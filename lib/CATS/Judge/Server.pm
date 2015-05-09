package CATS::Judge::Server;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB qw(new_id $dbh);
use CATS::Testset;

use base qw(CATS::Judge::Base);

sub auth {
    my ($self) = @_;

    $self->{id} = $dbh->selectrow_array(q~
        SELECT id FROM judges WHERE nick = ?~, {}, $self->name);
    $self->{id} or die sprintf "unknown judge name: '%s'", $self->name;

    for (1..20) {
        $self->{sid} = $self->make_sid;
        if ($dbh->do(q~
            UPDATE judges SET jsid = ? WHERE id = ?~, {}, $self->{sid}, $self->{id})
        ) {
            $dbh->commit;
            return;
        }
        sleep 1;
    }
    die "login failed\n";
}

sub update_state {
    my ($self) = @_;

    (my $is_alive, $self->{lock_counter}, my $current_sid) = $dbh->selectrow_array(q~
        SELECT is_alive, lock_counter, jsid FROM judges WHERE id = ?~, {}, $self->{id});

    $current_sid eq $self->{sid}
        or die "killed: $current_sid != $self->{sid}";

    $dbh->do(q~
        UPDATE judges SET is_alive = 1, alive_date = CURRENT_DATE
        WHERE id = ? AND is_alive = 0~, {}, $self->{id}) if !$is_alive;
    $dbh->commit;
    !$is_alive;
}

sub is_locked { $_[0]->{lock_counter} }

sub set_request_state {
    my ($self, $req, $state, %p) = @_;
    $dbh->do(qq~
        UPDATE reqs SET state = ?, failed_test = ?, result_time = CURRENT_TIMESTAMP
        WHERE id = ? AND judge_id = ?~, {},
        $state, $p{failed_test}, $req->{id}, $self->{id});
    if ($state == $cats::st_unhandled_error && defined $p{problem_id} && defined $p{contest_id}) {
        $dbh->do(qq~
            UPDATE contest_problems SET status = ?
            WHERE problem_id = ? AND contest_id = ?~, {},
            $cats::problem_st_suspended, $p{problem_id}, $p{contest_id});
    }
    $dbh->commit;
}

sub select_request {
    my ($self, $supported_DEs) = @_;
    my $sth = $dbh->prepare_cached(qq~
        SELECT
            R.id, R.problem_id, R.contest_id, R.state, CA.is_jury, C.run_all_tests,
            CP.status, S.fname, S.src, S.de_id
        FROM reqs R
        INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
        INNER JOIN contests C ON C.id = R.contest_id
        INNER JOIN sources S ON S.req_id = R.id
        INNER JOIN default_de D ON D.id = S.de_id
        LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
        WHERE R.state = ? AND
            (CP.status IS NULL OR CP.status = ? OR CA.is_jury = 1) AND
            D.code IN ($self->{supported_DEs}) AND (judge_id IS NULL OR judge_id = ?)
        ROWS 1~);
    $dbh->selectrow_hashref(
        $sth, { Slice => {} }, $cats::st_not_processed, $cats::problem_st_ready, $self->{id});
}

sub lock_request {
    my ($self, $req) = @_;
    $dbh->do(q~
        UPDATE reqs SET state = ?, judge_id = ? WHERE id = ?~, {},
        $cats::st_install_processing, $self->{id}, $req->{id});
    $dbh->commit;
}

sub save_log_dump {
    my ($self, $req, $dump) = @_;

    my $id = $dbh->selectrow_array(q~
        SELECT id FROM log_dumps WHERE req_id = ?~, undef, $req->{id});
    if (defined $id) {
        my $c = $dbh->prepare(q~UPDATE log_dumps SET dump = ? WHERE id = ?~);
        $c->bind_param(1, $dump, { ora_type => 113 });
        $c->bind_param(2, $id);
        $c->execute;
    }
    else {
        my $c = $dbh->prepare(q~INSERT INTO log_dumps (id, dump, req_id) VALUES (?, ?, ?)~);
        $c->bind_param(1, new_id);
        $c->bind_param(2, $dump, { ora_type => 113 });
        $c->bind_param(3, $req->{id});
        $c->execute;
    }
}

sub set_DEs {
    my ($self, $cfg_de) = @_;
    my $db_de = $dbh->selectall_arrayref(q~
        SELECT id, code, description, memory_handicap FROM default_de~, { Slice => {} });
    for my $de (@$db_de) {
        my $c = $de->{code};
        exists $cfg_de->{$c} or next;
        $cfg_de->{$c} = { %{$cfg_de->{$c}}, %$de };
    }
    delete @$cfg_de{grep !exists $cfg_de->{$_}->{code}, keys %$cfg_de};
    $self->{supported_DEs} = join ',', sort { $a <=> $b } keys %$cfg_de;
}

sub get_problem_sources {
    my ($self, $pid) = @_;
    my $problem_sources = $dbh->selectall_arrayref(q~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
        WHERE ps.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $pid);
    my $imported = $dbh->selectall_arrayref(q~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
            INNER JOIN problem_sources_import psi ON ps.guid = psi.guid
        WHERE psi.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $pid);
    [ @$problem_sources, @$imported ];
}

sub delete_req_details {
    my ($self, $req_id) = @_;
    $dbh->do(q~DELETE FROM req_details WHERE req_id = ?~, undef, $req_id);
    $dbh->commit;
}

sub insert_req_details {
    my ($self, $p) = @_;
    $dbh->do(
        sprintf(
            q~INSERT INTO req_details (%s) VALUES (%s)~,
            join(', ', keys %$p), join(', ', ('?') x keys %$p)
        ),
        undef, values %$p
    );
    $dbh->commit;
}

sub get_problem_tests {
    my ($self, $pid) = @_;
    $dbh->selectall_arrayref(q~
        SELECT generator_id, input_validator_id, rank, param, std_solution_id, in_file, out_file, gen_group
        FROM tests WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
        $pid);
}

sub get_problem {
    my ($self, $pid) = @_;
    $dbh->selectrow_hashref(q~
        SELECT
            id, title, upload_date, time_limit, memory_limit,
            input_file, output_file, std_checker, contest_id, formal_input,
            run_method
        FROM problems WHERE id = ?~, { Slice => {} }, $pid);
}

sub is_problem_uptodate {
    my ($self, $pid, $date) = @_;
    scalar $dbh->selectrow_array(q~
        SELECT 1 FROM problems
        WHERE id = ? AND upload_date - 1.0000000000 / 24 / 60 / 60 <= ?~, undef,
        $pid, $date);
}

sub get_testset {
    my ($self, $rid, $update) = @_;
    CATS::Testset::get_testset($rid, $update);
}

1;
