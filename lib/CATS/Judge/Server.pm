package CATS::Judge::Server;

use strict;
use warnings;

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

1;
