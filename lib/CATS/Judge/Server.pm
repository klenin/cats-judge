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

1;
