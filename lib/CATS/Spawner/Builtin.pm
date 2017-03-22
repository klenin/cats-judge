package CATS::Spawner::Builtin;

use strict;
use warnings;

use CATS::FileUtil;

use base 'CATS::Spawner1';

use CATS::Spawner::Const ':all';

sub _init {
    my ($self) = @_;
    $self->{fu} = CATS::FileUtil->new({
        map { $_ => $self->{opts}->{$_} } qw(logger run_temp_dir run_method) });
}

sub _run {
    my ($self, $globals, @programs) = @_;
    die 'Programs count not equal 1' if @programs != 1;

    my $program = $programs[0];
    my $run = $self->{fu}->run([ $program->application, @{$program->arguments} ]);
    $self->{stdout} = $run->stdout;
    $self->{stderr} = $run->stderr;
    my $report = CATS::Spawner::Report->new;
    $report->add({
        params => $globals,
        terminate_reason => ($run->ok || $run->exit_code ? $TR_OK : $TR_ABORT),
        errors => [],
        exit_status => $run->exit_code,
        consumed => {
            user_time => 0,
            memory => 1,
            write => 1,
        },
    });
}

sub stdout_lines { $_[0]->{stdout} }
sub stderr_lines { $_[0]->{stderr} }

1;
