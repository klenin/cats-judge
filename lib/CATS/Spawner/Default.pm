package CATS::Spawner::Default;

use strict;
use warnings;

use JSON::XS qw(decode_json);

use CATS::FileUtil;
use CATS::Spawner::Const ':all';

use base 'CATS::Spawner1';

sub _init {
    my ($self) = @_;
    my $fu = $self->{fu} = CATS::FileUtil->new({ logger => $self->opts->{logger} });
    $self->{sp} = $fu->quote_braced($self->opts->{path} || die 'path required');
    for (qw(stdout stderr report)) {
        my $s = $self->opts->{"save_$_"} //= "$_.txt";
        $self->opts->{$_ . '_file'}= $fu->quote_braced($s);
    }
    $self->opts->{hide_report} //= 1;
}

sub opts { $_[0]->{opts} }

sub stdout_lines {
    my ($self) = @_;
    $self->{fu}->read_lines($self->{opts}->{stdout_file});
}

sub stderr_lines {
    my ($self) = @_;
    $self->{fu}->read_lines($self->{opts}->{stderr_file});
}

sub make_sp_params {
    my ($self, $p) = @_;
    my @r = (
        so => $self->opts->{stdout_file},
        se => $self->opts->{stderr_file},
        sr => $self->opts->{report_file},
        hr => $self->opts->{hide_report},
        tl => $p->{time_limit},
        ml => $p->{memory_limit},
        wl => $p->{write_limit},
    );
    ($self->opts->{json} ? '--json' : ()),
    map {
        my ($name, $value) = splice @r, 0, 2;
        defined $value ? "-$name=$value" : ();
    } 1 .. @r / 2;
}

sub _run {
    my ($self, $p) = @_;
    my $sp = $self->{sp};
    my @quoted = map $self->{fu}->quote_braced($_),
        $self->make_sp_params($p), $p->application, @{$p->arguments};
    my $report = CATS::Spawner::Report->new;
    my $exit_code = system(join ' ', $self->{sp}, @quoted);
    $exit_code == 0
        or return $report->error("failed to run spawner: $! ($exit_code)");
    open my $file, '<', $self->opts->{report_file}
        or return $report->error("unable to open report '$self->opts->{report_file}': $!");
    $self->opts->{json} ?
        $self->parse_json_report($report, $file) :
        $self->parse_legacy_report($report, $file);
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
    #ExitStatus:            0
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
        exit_status => $raw_report->{ExitStatus},
        consumed => {
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
    ExitStatus
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
        my $e = $ji->{SpawnerError};
        my $tr =  $terminate_reasons->{$ji->{TerminateReason}}
            or return $report->error("Unknown terminate reason: $ji->{TerminateReason}");
        my $lim = $ji->{Limit};
        my $res = $ji->{Result};
        $report->add({
            application => $ji->{Application},
            arguments => $ji->{Arguments},
            method => $ji->{CreateProcessMethod},
            security => {
                user_name => $ji->{UserName},
            },
            errors => (@$e == 0 || $e->[0] eq '<none>' ? [] : $e),
            limits => {
                wall_clock_time => $lim->{DeadLine},
                user_time => $lim->{Time},
                idle_time => $lim->{IdleTimeLimit},
                memory => $lim->{Memory},
                write => $lim->{IOBytes},
                load_ratio => $lim->{IdlenessProcessorLoad},
            },
            terminate_reason => $tr,
            exit_status => $ji->{ExitStatus} // die('ExitStatus not found'),
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
