package CATS::Spawner::Default;

use strict;
use warnings;

use Encode qw();
use JSON::XS qw(decode_json);

use CATS::ConsoleColor qw(colored);
use CATS::FileUtil;
use CATS::Spawner::Const ':all';

use FindBin qw($Bin);

use base 'CATS::Spawner';

sub _init {
    my ($self) = @_;
    my $fu = $self->{fu} = CATS::FileUtil->new({ logger => $self->opts->{logger} });
    $self->{sp} = $fu->quote_braced($self->opts->{path} || die 'path required');
    for (qw(stdout stderr report)) {
        my $s = $self->opts->{"save_$_"} //= "$_.txt";
        $self->opts->{$_} = $fu->quote_braced($s);
    }
    $self->opts->{hide_report} //= 1;
}

sub opts { $_[0]->{opts} }

sub stdout_lines {
    my ($self) = @_;
    die if @{$self->{stdouts}} != 1;
    $self->{fu}->read_lines($self->{stdouts}->[0]);
}

sub stderr_lines {
    my ($self) = @_;
    die if @{$self->{stderrs}} != 1;
    $self->{fu}->read_lines($self->{stderrs}->[0]);
}

sub stdout_lines_chomp {
    my ($self) = @_;
    die if @{$self->{stdouts}} != 1;
    $self->{fu}->read_lines_chomp($self->{stdouts}->[0]);
}

sub stderr_lines_chomp {
    my ($self) = @_;
    die if @{$self->{stderrs}} != 1;
    $self->{fu}->read_lines_chomp($self->{stderrs}->[0]);
}

sub make_sp_params {
    my ($self, $p) = @_;
    my @r = (
        i  => $p->{stdin} // $self->opts->{stdin},
        so => $p->{stdout} // $self->opts->{stdout},
        se => $p->{stderr} // $self->opts->{stderr},
        sr => $p->{report} // $self->opts->{report},
        hr => $p->{hide_report} // $self->opts->{hide_report},
        tl => $p->{time_limit},
        y  => $p->{idle_time_limit},
        d  => $p->{deadline},
        ml => $p->{memory_limit},
        wl => $p->{write_limit},
        'active-connection-count' => $p->{active_connections},
        'active-process-count' => $p->{active_processes},
        u => $p->{user}->{name},
        p => $p->{user}->{password},
        (map { +D => "{$_=$p->{env}->{$_}}" } sort keys %{$p->{env} // {}}),
    );
    ($p->{json} // $self->opts->{json} ? '--json' : ()),
    map {
        my ($name, $value) = splice @r, 0, 2;
        defined $value ? "-$name=$value" : ();
    } 1 .. @r / 2;
}

sub prepare_redirect {
    my ($files, $redirect) = @_;

    $redirect or return;

    if ($redirect =~ /^\*/) {
        my $flag_rx = '(?:(?:-?(?:f|e))*:)';
        my $pipe_rx = "$flag_rx?(?:\\d+\\.(?:stdin|stdout|stderr)|std|null)";
        my $file_rx = "$flag_rx.*";
        $redirect =~ /^\*(?:$pipe_rx|$file_rx)$/ or die "Bad redirect: $redirect"
    }
    elsif ($files) {
        $files->{$redirect} = 1;
    }
}

my $stderr_encoding = $^O eq 'MSWin32' ? 'WINDOWS-1251' : 'UTF-8';

# file, show, save, color
sub _dump_child {
    my ($self, $globals, %p) = @_;
    my $log = $self->opts->{logger};
    my $show = $self->opts->{$p{show}} || $globals->{show_output};
    my $save = $self->opts->{$p{save}} || $globals->{section} || $globals->{save_output};
    my $duplicate_to = $globals->{duplicate_output};
    my $color = $self->opts->{color}->{$p{color}};

    open(my $fstdout, '<', $self->opts->{$p{file}})
        or return $log->msg("open failed: '%s' ($!)\n", $self->opts->{$p{file}});

    my $eol = 0;
    while (<$fstdout>) {
        $_ = Encode::decode($globals->{encoding}, $_) if $globals->{encoding};
        if ($show) {
            my $e = Encode::encode($stderr_encoding, $_);
            print STDERR $color ? colored($e, $color) : $e;
        }
        $log->dump_write($_) if $save;
        $$duplicate_to .= $_ if $duplicate_to;
        $eol = substr($_, -2, 2) eq '\n';
    }
    if ($eol) {
        print STDERR "\n" if $show;
        $log->dump_write("\n") if $save;
        $$duplicate_to .= "\n" if $duplicate_to;
    }
    1;
}

sub _run {
    my ($self, $globals, @programs) = @_;
    @programs or die;
    my $sp = $self->{sp};

    my $multi = @programs > 1;
    $globals->{json} = 1 if $multi;
    my @quoted = map $self->{fu}->quote_braced($_), $self->make_sp_params($globals),
        $multi ? '--separator=//' : '';

    my $separator = $multi ? '--//' : '';
    my (%stdouts, %stderrs);
    for my $program (@programs) {
        my @program_quoted = map $self->{fu}->quote_braced($_), $separator,
            $program->make_params, $program->application, @{$program->arguments};
        push @quoted, @program_quoted;

        prepare_redirect(undef, $program->opts->{stdin});
        prepare_redirect(\%stdouts, $program->opts->{stdout});
        prepare_redirect(\%stdouts, $program->opts->{stderr});
    }

    my $opts = $self->{opts};
    prepare_redirect(\%stdouts, $globals->{stdout} // $opts->{stdout});
    prepare_redirect(\%stderrs, $globals->{stderr} // $opts->{stderr});

    $self->{stdouts} = [ sort keys %stdouts ];
    $self->{stderrs} = [ sort keys %stderrs ];

    my $report = CATS::Spawner::Report->new;

    my $cur_dir = $Bin;
    my $run_dir = $globals->{run_dir} // $self->opts->{run_dir};
    chdir($run_dir) or return $report->error("failed to change directory to: $run_dir") if $run_dir;

    for (keys %stdouts, keys %stderrs) {
        open my $f, '>', $_ or die "Can't open redirect file: $_ ($!)";
    }

    my $exec_str = join ' ', $self->{sp}, @quoted;
    $opts->{logger}->msg("> %s\n", $exec_str);

    $report->exit_code(system($exec_str));

    open my $file, '<', $opts->{report}
        or return $report->error("unable to open report '$opts->{report}': $!")->
            write_to_log($opts->{logger});

    $opts->{logger}->dump_write("$cats::log_section_start_prefix$globals->{section}\n")
        if $globals->{section};
    $self->_dump_child($globals,
        file => 'stdout_file', show => 'show_child_stdout', save => 'save_child_stdout',
        color => 'child_stdout',
    ) if %stdouts;
    $self->_dump_child($globals,
        file => 'stderr_file', show => 'show_child_stderr', save => 'save_child_stderr',
        color => 'child_stderr',
    ) if %stderrs;
    $opts->{logger}->dump_write("$cats::log_section_end_prefix$globals->{section}\n")
        if $globals->{section};

    my $parsed_report = $opts->{json} ?
        $self->parse_json_report($report, $file) :
        $self->parse_legacy_report($report, $file);

    chdir($cur_dir) or return $report->error("failed to change directory back to: $cur_dir") if $run_dir;

    $parsed_report->write_to_log($opts->{logger})
}

my @legacy_required_fields = qw(
    Application
    Parameters
    SecurityLevel
    CreateProcessMethod
    UserName
    UserTimeLimit
    DeadLine
    MemoryLimit
    WriteLimit
    UserTime
    PeakMemoryUsed
    Written
    TerminateReason
    ExitCode
    ExitStatus
    SpawnerError
);

my $terminate_reasons = {
    ExitProcess => $TR_OK,
    TimeLimitExceeded => $TR_TIME_LIMIT,
    MemoryLimitExceeded => $TR_MEMORY_LIMIT,
    WriteLimitExceeded => $TR_WRITE_LIMIT,
    IdleTimeLimitExceeded => $TR_IDLENESS_LIMIT,
    AbnormalExitProcess => $TR_ABORT,
    TerminatedByController => $TR_CONTROLLER,
    ActiveConnectionCountLimitExceeded => $TR_SECURITY,
    ActiveProcessesCountLimitExceeded => $TR_SECURITY,
};

sub mb_to_bytes { defined $_[0] ? int($_[0]  * 1024 * 1024 + 0.5) : undef }

sub parse_legacy_report {
    my ($self, $report, $file) = @_;

    # Report sample:
    #
    #--------------- Spawner report ---------------
    #Application:           test.exe
    #Parameters:            <none>
    #SecurityLevel:         0
    #CreateProcessMethod:   CreateProcessAsUser
    #UserName:              acm3
    #UserTimeLimit:         0.001000 (sec)
    #DeadLine:              Infinity
    #MemoryLimit:           20.000000 (Mb)
    #WriteLimit:            Infinity
    #----------------------------------------------
    #UserTime:              0.010014 (sec)
    #PeakMemoryUsed:        20.140625 (Mb)
    #Written:               0.000000 (Mb)
    #TerminateReason:       TimeLimitExceeded
    #ExitCode               0
    #ExitStatus:            SIGKILL
    #----------------------------------------------
    #SpawnerError:          <none>

    my $skip = <$file>;
    my $signature = <$file>;
    $signature eq "--------------- Spawner report ---------------\n"
        or return $report->error("malformed spawner report: $signature");

    my $checking = 0;
    my $raw_report = {};
    while (my $line = <$file>) {
        if ($line =~ /^([a-zA-Z]+):\s+(.+)$/) {
            my $p = $1;
            my $v = $2;
            if ($v eq 'Infinity') {
                $v = undef;
            }
            elsif ($v =~ /^(\d+\.?\d*)\s*\((?:.+)\)/) { # Remove units.
                $v = $1;
            }
            my $f = $legacy_required_fields[$checking];
            $p eq $f or return $report->error("Expected $f, got $p at pos $checking");
            $checking++;
            $raw_report->{$p} = $v;
        }
    }
    $checking == @legacy_required_fields or return $report->error("Only $checking required fields");
    my $tr =  $terminate_reasons->{$raw_report->{TerminateReason}}
        or return $report->error("Unknown terminate reason: $raw_report->{TerminateReason}");

    $report->add({
        application => $raw_report->{Application},
        arguments => [ $raw_report->{Parameters} ],
        method => $raw_report->{CreateProcessMethod},
        security => {
            level => $raw_report->{SecurityLevel},
            user_name => $raw_report->{UserName},
        },
        errors => ($raw_report->{SpawnerError} eq '<none>' ? [] : [ $raw_report->{SpawnerError} ]),
        limits => {
            wall_clock_time => $raw_report->{DeadLine},
            user_time => $raw_report->{UserTimeLimit},
            memory => mb_to_bytes($raw_report->{MemoryLimit}),
            write => mb_to_bytes($raw_report->{WriteLimit}),
        },
        terminate_reason => $tr,
        exit_code => $raw_report->{ExitCode},
        exit_status => $raw_report->{ExitStatus},
        consumed => {
            wall_clock_time => $raw_report->{UserTime}, # Approximation.
            user_time => $raw_report->{UserTime},
            memory => mb_to_bytes($raw_report->{PeakMemoryUsed}),
            write => mb_to_bytes($raw_report->{Written}),
        },
    });
}

my @required_fields = qw(
    Application
    CreateProcessMethod
    UserName
    TerminateReason
    ExitCode
);

sub parse_json_report {
    my ($self, $report, $file) = @_;
    my $json = decode_json(join '', <$file>);

=begin
Sample JSON report
[
    {
        "Application": "perl",
        "Arguments": [
            "-e",
            "print 1"
        ],
        "Limit": {
            "IdlenessProcessorLoad": 5.0
        },
        "Options": {
            "SearchInPath": true
        },
        "Result": {
            "Time": 0.0156,
            "WallClockTime": 0.039027,
            "Memory": 1716224,
            "BytesWritten": 1,
            "KernelTime": 0.0,
            "ProcessorLoad": 0.0,
            "WorkingDirectory": "E:\\Work\\cats-judge\\t"
        },
        "StdOut": [],
        "StdErr": [],
        "StdIn": [],
        "CreateProcessMethod": "CreateProcess",
        "UserName": "Ask",
        "TerminateReason": "ExitProcess",
        "ExitCode": 0,
        "ExitStatus": "0",
        "SpawnerError": [
            "<none>"
        ]
    }
]
=cut

    for my $ji (@$json) {
        my $errors = $ji->{SpawnerError};
        $errors = [] if @$errors && $errors->[0] eq '<none>';
        my $tr =  $terminate_reasons->{$ji->{TerminateReason}}
            or die "Unknown terminate reason: $ji->{TerminateReason}";
        my $lim = $ji->{Limit};
        my $res = $ji->{Result};
        $report->add({
            application => $ji->{Application},
            arguments => $ji->{Arguments},
            method => $ji->{CreateProcessMethod},
            security => {
                user_name => $ji->{UserName},
            },
            errors => $errors,
            limits => {
                wall_clock_time => $lim->{WallClockTime},
                user_time => $lim->{Time},
                idle_time => $lim->{IdlenessTime},
                memory => $lim->{Memory},
                write => $lim->{IOBytes},
                load_ratio => $lim->{IdlenessProcessorLoad},
            },
            terminate_reason => $tr,
            original_terminate_reason => $ji->{TerminateReason},
            exit_status => $ji->{ExitStatus},
            exit_code => $ji->{ExitCode} // die('ExitCode not found'),
            consumed => {
                user_time => $res->{Time},
                wall_clock_time => $res->{WallClockTime},
                system_time => $res->{KernelTime},
                memory => $res->{Memory},
                write => $res->{BytesWritten},
            },
        });
    }
    $report;
}

1;
