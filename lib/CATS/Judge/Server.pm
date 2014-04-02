package CATS::Judge::Server;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB qw(new_id $dbh);

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
            R.id, R.problem_id, R.contest_id, R.state, CA.is_jury, CP.status, S.fname, S.src, S.de_id
        FROM reqs R
        INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
        INNER JOIN sources S ON S.req_id = R.id
        INNER JOIN default_de D ON D.id = S.de_id
        LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
        WHERE R.state = ? AND
            (CP.status IS NULL OR CP.status = ? OR CA.is_jury = 1) AND D.code IN ($supported_DEs)
        ROWS 1~); # AND judge_id IS NULL~
    $dbh->selectrow_hashref($sth, { Slice => {} }, $cats::st_not_processed, $cats::problem_st_ready);
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

1;
