use strict;
use warnings;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use Test::More tests => 12;
use CATS::Spawner::Const ':all';

run_subtest 'Terminate reasons', 5 * compile_plan + 10, sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $while = compile('while.cpp', "while$exe", $_[0] - compile_plan);
    my $write = compile('write.cpp', "write$exe", $_[0] - compile_plan * 2);
    my $memory = compile('memory.cpp', "memory$exe", $_[0] - compile_plan * 3);
    my $empty = compile('empty.cpp', "empty$exe", $_[0] - compile_plan * 4);

    my $tr_variants = {
        $TR_OK => { # parameters: exit_code
            program => sub {
                program($empty, [ "$_[0]->{exit_code}" ])
            },
            check_plan => 1,
            check => sub {
                my ($r, $i, $params) = @_;
                is $r->{exit_status}, $params->{exit_code}, "empty $i exit status";
            }
        },
        $TR_TIME_LIMIT => { # parameters: tl, tl_min, tl_max
            program => sub {
                program($while, undef, { time_limit => $_[0]->{tl} })->set_expected_tr($TR_TIME_LIMIT)
            },
            check_plan => 2,
            check => sub {
                my ($r, $i, $params) = @_;
                cmp_ok $r->{consumed}->{user_time}, '>=', $params->{tl_min} - 0.01, "while $i min user time";
                cmp_ok $r->{consumed}->{user_time}, '<=', $params->{tl_max}, "while $i max user time";
            }
        },
        $TR_WRITE_LIMIT => {
            program => sub {
                program($write, undef, { stdout => '*f:' . FS->catfile($tmpdir, 'stdout.txt'), write_limit => $_[0]->{wl} })->set_expected_tr($TR_WRITE_LIMIT)
            },
            check_plan => 2,
            check => sub {
                my ($r, $i, $params) = @_;
                cmp_ok $r->{consumed}->{write}, '>=', $params->{wl_min}, "write $i min bytes written";
                cmp_ok $r->{consumed}->{write}, '<=', $params->{wl_max}, "write $i max bytes written";
            }
        },
        $TR_MEMORY_LIMIT => {
            program => sub {
                program($memory, undef, { memory_limit => $_[0]->{ml} })->set_expected_tr($TR_MEMORY_LIMIT)
            },
            check_plan => 2,
            check => sub {
                my ($r, $i, $params) = @_;
                cmp_ok $r->{consumed}->{memory}, '>=', $params->{ml_min}, "memory $i min";
                cmp_ok $r->{consumed}->{memory}, '<=', $params->{ml_max}, "memory $i max";
            }
        }
    };

    # Running set of terminate reasons [ { tr => TR_CODE, params => { ... } }, ... ]
    my $run_tr_test = sub {
        my ($name, $variants) = @_;
        my $plan = 0;
        $plan += $tr_variants->{$_->{tr}}->{check_plan} // 0 for @$variants;
        run_subtest $name, $plan + items_ok_plan(scalar @$variants), sub {
            my $r = run_sp_multiple(undef, [ map { $tr_variants->{$_->{tr}}->{program}->($_->{params} // {}) } @$variants ]);
            for my $i (0 .. @$r - 1) {
                my $v = $variants->[$i];
                my $vr = $tr_variants->{$v->{tr}};
                $vr->{check}->($r->[$i], $i, $v->{params}) if $vr->{check};
            }
        };
        clear_tmpdir('*.txt', '*.tmp');
    };



    $run_tr_test->('Run 2 with different exit codes (TR_OK)', [
        { tr => $TR_OK, params => { exit_code => 10 }},
        { tr => $TR_OK, params => { exit_code => 20 }},
    ]);

    $run_tr_test->('Run 3 with different exit codes (TR_OK)', [
        { tr => $TR_OK, params => { exit_code => 1 }},
        { tr => $TR_OK, params => { exit_code => 2 }},
        { tr => $TR_OK, params => { exit_code => 3 }},
    ]);

    $run_tr_test->('Run 2 with different time limits (TR_TIME_LIMIT)', [
        { tr => $TR_TIME_LIMIT, params => { tl => 0.3, tl_min => 0.3, tl_max => 0.5 }},
        { tr => $TR_TIME_LIMIT, params => { tl => 0.4, tl_min => 0.4, tl_max => 0.6 }},
    ]);

    $run_tr_test->('Run 3 with different time limits (TR_TIME_LIMIT)', [
        { tr => $TR_TIME_LIMIT, params => { tl => 0.3, tl_min => 0.3, tl_max => 0.5 }},
        { tr => $TR_TIME_LIMIT, params => { tl => 0.4, tl_min => 0.4, tl_max => 0.6 }},
        { tr => $TR_TIME_LIMIT, params => { tl => 0.5, tl_min => 0.5, tl_max => 0.7 }},
    ]);

    $run_tr_test->('TR_OK, TR_TIME_LIMIT', [
        { tr => $TR_OK, params => { exit_code => 1 }},
        { tr => $TR_TIME_LIMIT, params => { tl => 0.3, tl_min => 0.3, tl_max => 0.5 }},
    ]);

    $run_tr_test->('TR_OK, TR_WRITE_LIMIT', [
        { tr => $TR_OK, params => { exit_code => 1 }},
        { tr => $TR_WRITE_LIMIT, params => { wl => '100B', wl_min => 100, wl_max => MB }},
    ]);

    $run_tr_test->('TR_OK, TR_MEMORY_LIMIT', [
        { tr => $TR_OK, params => { exit_code => 1 }},
        { tr => $TR_MEMORY_LIMIT, params => { ml => 100, ml_min => 90 * MB, ml_max => 200 * MB }},
    ]);

    $run_tr_test->('TR_WRITE_LIMIT, TR_TIME_LIMIT', [
        { tr => $TR_WRITE_LIMIT, params => { wl => '100B', wl_min => 100, wl_max => MB }},
        { tr => $TR_TIME_LIMIT, params => { tl => 0.3, tl_min => 0.3, tl_max => 0.5 }},
    ]);

    $run_tr_test->('TR_MEMORY_LIMIT, TR_WRITE_LIMIT', [
        { tr => $TR_MEMORY_LIMIT, params => { ml => 100, ml_min => 90 * MB, ml_max => 200 * MB }},
        { tr => $TR_WRITE_LIMIT, params => { wl => '100B', wl_min => 100, wl_max => MB }},
    ]);

    $run_tr_test->('TR_TIME_LIMIT, TR_MEMORY_LIMIT', [
        { tr => $TR_TIME_LIMIT, params => { tl => 0.3, tl_min => 0.3, tl_max => 0.5 }},
        { tr => $TR_MEMORY_LIMIT, params => { ml => 100, ml_min => 90 * MB, ml_max => 200 * MB }},
    ]);

    clear_tmpdir;
};

run_subtest 'Interact speed', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $inter = compile('interact.cpp', "interact$exe", $_[0]);
    my $cinpipe = compile('cinpipe.cpp', "cinpipe$exe", $_[0] - compile_plan);

    my $r = run_sp_multiple({ deadline => 2 }, [
        program($inter),
        program($cinpipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' }),
    ]);
    is_deeply $spr->stdout_lines_chomp, [ ('111111111') x 10000 ], 'interact + cinpipe stdout';

    clear_tmpdir;
};

run_subtest 'Run 3 with one stdout file', compile_plan + items_ok_plan(3) + 2, sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $out = tmp_name;
    my $r = run_sp_multiple(undef, [
        program($pipe, [ '1' ], { stdout => $out }),
        program($pipe, [ '2' ], { stdout => $out }),
        program($pipe, [ '3' ], { stdout => $out }),
    ]);
    my $res = $fu->read_lines_chomp($out);
    is scalar @$res, 1, 'out lines count';
    like $res->[0], qr/^(123|132|213|231|312|321)$/, 'out lines content';

    clear_tmpdir;
};

run_subtest 'Run 3 with one stdin file', compile_plan + items_ok_plan(3) + 2, sub {
    my $input = make_test_file('test', 1);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $r = run_sp_multiple(undef, [
        program($pipe, undef, { stdin => $input }),
        program($pipe, undef, { stdin => $input }),
        program($pipe, undef, { stdin => $input }),
    ]);
    my $res = $spr->stdout_lines_chomp;
    is scalar @$res, 1, 'out lines count';
    like $res->[0], qr/^testtesttest$/, 'out lines content';

    clear_tmpdir;
};

run_subtest 'Run 2 with wl to pipe', compile_plan + items_ok_plan(2) + 4, sub {
    my $n = 30000;
    my $data;
    $data .= '0123456789' for 1..$n;
    my $input = make_test_file($data, 1);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $r = run_sp_multiple({ stdout => '', write_limit => '260000B' }, [
        program($pipe, undef, { stdin => $input })->set_expected_tr($TR_WRITE_LIMIT),
        program($pipe, undef, { stdin => $input })->set_expected_tr($TR_WRITE_LIMIT),
    ]);
    cmp_ok $r->[0]->{consumed}->{write}, '>=', 200000, 'bytes written min';
    cmp_ok $r->[0]->{consumed}->{write}, '<=', 350000, 'bytes written max';
    cmp_ok $r->[0]->{consumed}->{write}, '>=', 200000, 'bytes written min';
    cmp_ok $r->[0]->{consumed}->{write}, '<=', 350000, 'bytes written max';

    clear_tmpdir;
};

run_subtest 'Run 2 with TIME_LIMIT and IDLE_TIME_LIMIT', compile_plan * 2 + items_ok_plan(3), sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $while = compile('while.cpp', "while$exe", $_[0] - compile_plan);
    my $r = run_sp_multiple(undef, [
        program($pipe, undef, { idle_time_limit => 1, stdin => '*1.stdout' })->set_expected_tr($TR_IDLENESS_LIMIT),
        program($pipe, undef, { stdin => '*0.stdout' })->set_expected_tr($TR_OK),
        program($while, undef, { time_limit => 2 })->set_expected_tr($TR_TIME_LIMIT),
    ]);

    clear_tmpdir;
};

run_subtest 'Run 2 with deadlock', compile_plan + items_ok_plan(2), sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $r = run_sp_multiple(undef, [
        program($pipe, undef, { idle_time_limit => 1, stdin => '*1.stdout' })->set_expected_tr($TR_IDLENESS_LIMIT),
        program($pipe, undef, { idle_time_limit => 2, stdin => '*0.stdout' })->set_expected_tr($TR_OK),
    ]);

    clear_tmpdir;
};

run_subtest 'Run 2 with different way to IDLE_TIME_LIMIT', compile_plan * 2 + items_ok_plan(3), sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $sleep = compile('close_stdout.cpp', "sleep$exe", $_[0] - compile_plan);
    my $r = run_sp_multiple(undef, [
        program($pipe, undef, { idle_time_limit => 1, stdin => '*1.stdout' })->set_expected_tr($TR_IDLENESS_LIMIT),
        program($pipe, undef, { stdin => '*0.stdout' })->set_expected_tr($TR_OK),
        program($sleep, [ '2' ], { idle_time_limit => 1 })->set_expected_tr($TR_IDLENESS_LIMIT),
    ]);

    clear_tmpdir;
};

run_subtest 'Close pipes on exit', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $empty = compile('empty.cpp', "empty$exe", $_[0] - compile_plan);
    my $r = run_sp_multiple({ deadline => 5 }, [
        program($pipe, undef, { stdin => "*1.stdout" }),
        program($empty, [ '1' ])
    ]);
    is $r->[1]->{exit_status}, 1, 'empty exit status';

    clear_tmpdir;
};

run_subtest 'Force close stdout pipe', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $close_stdout = compile('close_stdout.cpp', "close_stdout$exe", $_[0] - compile_plan);
    my $r = run_sp_multiple({ deadline => 1 }, [
        program($pipe, undef, { stdin => "*1.stdout" }),
        program($close_stdout, [ '0.6' ])
    ]);
    cmp_ok $r->[1]->{consumed}->{wall_clock_time}, '>', 0.5, 'close_stdout time';

    clear_tmpdir;
};

run_subtest 'Force close stdout pipe 10x', compile_plan * 2 + (items_ok_plan(2) + 1) * 10, sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $close_stdout = compile('close_stdout.cpp', "close_stdout$exe", $_[0] - compile_plan);
    # Test for bad spawner exit code
    for (1..10) {
        my $r = run_sp_multiple({ deadline => 1 }, [
            program($pipe, undef, { stdin => "*1.stdout" }),
            program($close_stdout, [ '0.6' ])
        ]);
        cmp_ok $r->[1]->{consumed}->{wall_clock_time}, '>', 0.5, 'close_stdout time';
    }

    clear_tmpdir;
};

run_subtest 'Stdout to file and another program stdin', compile_plan + items_ok_plan(2) + 1, sub {
    my $out = tmp_name;
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $r = run_sp_multiple({ stdout => $out }, [
        program($pipe, [ 'stdout' ], { stdout => "*1.stdin" }),
        program($pipe)
    ]);
    is_deeply $fu->read_lines_chomp($out), [ 'stdoutstdout' ], 'stdout';

    clear_tmpdir;
};
