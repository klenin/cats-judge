package CATS::Spawner::Builtin;

use strict;
use warnings;

use CATS::FileUtil;

use base 'CATS::Spawner1';

use CATS::Spawner::Const ':all';

sub _init {
    my ($self) = @_;
    $self->{fu} = CATS::FileUtil->new({
        map { $_ => $self->{opts}->{$_} } qw(logger run_temp_dir) });
}

sub _run {
    my ($self, $p) = @_;
    my $run = $self->{fu}->run([ $p->application, @{$p->arguments} ]);
    my $report = CATS::Spawner::Report->new;
    $report->add({
        params => $p,
        terminate_reason => ($run->ok ? $TR_OK : $TR_ABORT),
        errors => [],
        exit_status => $run->err // '',
        consumed => {
            user_time => 0,
            memory => 1,
            write => 1,
        },
    });
}

1;
