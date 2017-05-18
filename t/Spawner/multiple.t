use strict;
use warnings;

use Test::More tests => 20;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use CATS::Spawner::Const ':all';
use constant MB => 1024 * 1024;

my $is_win = ($^O eq 'MSWin32');
my $exe = $is_win ? '.exe' : '';

my ($gcc, @gcc_opts) = split ' ', $cfg->defines->{'#gnu_cpp'};
ok -x $sp, 'sp exists' or exit;
ok -x $gcc, 'gcc exists' or exit;

my $builtin_runner = CATS::Spawner::Builtin->new({
    logger => CATS::Logger::Die->new,
    run_temp_dir => $tmpdir,
    run_method => 'system'
});

my $spr = CATS::Spawner::Default->new({
    logger => CATS::Logger::Count->new,
    path => $sp,
    save_stdout => [ $tmpdir, 'stdout.txt' ],
    save_stderr => [ $tmpdir, 'stderr.txt' ],
    save_report => [ $tmpdir, 'report.txt' ],
    #debug => 1,
    json => 1,
});

sub clear_tmpdir {
    push @_, '*' if @_ < 1;
    $fu->remove([ $tmpdir, $_ ]) for (@_);
}

sub items_ok_plan { 1 + $_[0] * 3 }

sub items_ok {
    my ($r, $apps, $msg) = @_;
    is scalar @{$r->items}, scalar @$apps, 'report count == programs count';
    for my $i (0 .. scalar @{$r->items} - 1) {
        my $ri = $r->items->[$i];
        is $r->exit_code, 0, "$msg spawner exit code";
        is_deeply $ri->{errors}, [], "$msg no errors";
        is $ri->{terminate_reason}, $apps->[$i]->{tr} // $TR_OK, "$msg TR_CODE";
    }
    $r->items;
}

sub program { CATS::Spawner::Program->new(@_) }

my $compile_plan = items_ok_plan(1) + 2;

sub compile {
    my ($src, $out, $skip, $flags) = @_;
    my $fullsrc = FS->catdir($Bin, 'cpp', $src);
    $out = FS->catdir($tmpdir, $out);
    my $app = program($gcc, [ @{$flags // []}, @gcc_opts, '-O0', '-o', $out, $fullsrc ]);
    my $r = $builtin_runner->run(undef, $app);
    items_ok($r, [ $app ], "$src compile");
    my $compile_success = 1;
    is $r->items->[0]->{exit_status}, 0, 'compile exit code' or $compile_success = 0;
    ok -x $out, 'compile success' or $compile_success = 0;
    ($skip and skip "$src compilation failed", $skip - $compile_plan) unless $compile_success;
    $out;
}

sub run_sp {
    my ($globals, $application, $args, $opts, $tr) = @_;
    my $app = program($application, $args, $opts)->set_expected_tr($tr // $TR_OK);
    my $r = $spr->run($globals, $app);
    items_ok($r, [ $app ], (FS->splitpath($application))[2]);
}

sub run_sp_multiple {
    my ($globals, $apps, $msg) = @_;
    my $r = $spr->run($globals, @$apps);
    items_ok($r, $apps, join ', ', map { (FS->splitpath($_->application))[2] } @$apps );
}

sub tmp_name {
    my @chars = ('A'..'Z', 'a'..'z', '0'..'9');
    FS->catdir($tmpdir, join '', (map @chars[rand @chars], 1..10), '.tmp');
}

sub make_test_file {
    my ($line, $count, $endl) = @_;
    $endl //= "\n";

    my $filename = tmp_name;
    open my $fh, '>', $filename;
    print $fh "$line$endl" for 1..$count - 1;
    print $fh $line;
    $filename;
}

sub run_subtest {
    my ($name, $plan, $sub) = @_;
    subtest $name => sub {
        SKIP: {
            plan tests => $plan;
            $sub->($plan);
        }
    };
}

run_subtest 'HelloWorld', $compile_plan + items_ok_plan(1) + 1, sub {
    my $hw = compile('helloworld.cpp', 'helloworld' . $exe, $_[0]);
    run_sp(undef, $hw);
    is_deeply $spr->stdout_lines, [ 'Hello world!' ], 'helloworld stdout';
    clear_tmpdir;
};

run_subtest 'Pipe', $compile_plan + 8, sub {
    my $pipe = compile('pipe.cpp', 'pipe' . $exe, $_[0]);

    run_subtest 'Pipe input', (items_ok_plan(1) + 1) * 2, sub {
        my $in = make_test_file('test', 1);
        run_sp({ stdin => $in }, $pipe);
        is_deeply $spr->stdout_lines_chomp, [ 'test' ], 'pipe one input global';
        clear_tmpdir('*.txt');
        run_sp(undef, $pipe, [], { stdin => $in });
        is_deeply $spr->stdout_lines_chomp, [ 'test' ], 'pipe one input local';
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe big input', items_ok_plan(1) + 1, sub {
        my $n = 26214;
        my $data;
        $data .= '123456789' for 1..$n;
        my $in = make_test_file($data, 1);
        run_sp(undef, $pipe, [], { stdin => $in });
        is_deeply $spr->stdout_lines_chomp, [ $data ];
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe output', (items_ok_plan(1) + 1) * 2, sub {
        my $out = tmp_name;
        run_sp({ stdout => $out }, $pipe, [ '"out string"' ]);
        is_deeply $fu->read_lines_chomp($out), [ 'out string' ], 'pipe one output global';
        clear_tmpdir('*.txt', '*.tmp');
        run_sp({ stdout => '' }, $pipe, [ '"out string"' ], { stdout => $out });
        is_deeply $fu->read_lines_chomp($out), [ 'out string' ], 'pipe one output local';
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe input -> output', items_ok_plan(1) + 1, sub {
        my $in = make_test_file('test string', 1);
        my $out = tmp_name;
        run_sp({ stdin => $in, stdout => $out }, $pipe);
        is_deeply $spr->stdout_lines_chomp, [ 'test string' ];
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe input from two files', items_ok_plan(1) + 2, sub {
        my $in1 = make_test_file('one', 1);
        my $in2 = make_test_file('two', 1);
        run_sp({ stdin => $in1 }, $pipe, [], { stdin => $in2 });
        my $res = $spr->stdout_lines_chomp;
        is scalar @$res, 1;
        like $res->[0], qr/^(onetwo|twoone)$/;
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe output in same files', items_ok_plan(1) + 1, sub {
        my $out1 = tmp_name;
        my $out2 = tmp_name;
        run_sp({ stdout => $out1 }, $pipe, [ '"out string"' ], { stdout => $out2 });
        is_deeply [ @{$fu->read_lines_chomp($out1)}, @{$fu->read_lines_chomp($out2)} ], [ 'out string', 'out string' ];
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe output + error to one file', items_ok_plan(1) + 2, sub {
        my $out = tmp_name;
        run_sp({ stdout => $out, stderr => $out }, $pipe, [ 'out', 'err' ]);
        my $res = $spr->stdout_lines_chomp;
        is scalar @$res, 1;
        like $res->[0], qr/^(outerr|errout)$/;
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe stdin close without redirect', items_ok_plan(1) + 1, sub {
        my $out = tmp_name;
        run_sp({ stdout => $out, stderr => $out }, $pipe);
        is_deeply $spr->stdout_lines_chomp, [ ];
        clear_tmpdir('*.txt', '*.tmp');
    };

    clear_tmpdir;
};

run_subtest 'Open stdin file inside program', $compile_plan + items_ok_plan(1) + 1, sub {
    my $input = make_test_file('abc', 1);
    my $fopen = compile('fopen.cpp', "fopen$exe", $_[0]);
    run_sp({ stdin => $input }, $fopen, [ $input ]);
    is_deeply $spr->stdout_lines_chomp, [ 'aabbcc' ], 'merged stdout';
    clear_tmpdir;
};

run_subtest 'Many lines to stdout', $compile_plan + items_ok_plan(1), sub {
    my $many_lines = compile('many_lines.cpp', "many_lines$exe", $_[0]);
    run_sp({ deadline => 2 }, $many_lines);
    clear_tmpdir;
};

run_subtest 'Terminate reasons', 5 * $compile_plan + 10, sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $while = compile('while.cpp', "while$exe", $_[0] - $compile_plan);
    my $write = compile('write.cpp', "write$exe", $_[0] - $compile_plan * 2);
    my $memory = compile('memory.cpp', "memory$exe", $_[0] - $compile_plan * 3);
    my $empty = compile('empty.cpp', "empty$exe", $_[0] - $compile_plan * 4);

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

run_subtest 'Run 3 with one stdout file', $compile_plan + items_ok_plan(3) + 2, sub {
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

run_subtest 'Run 3 with one stdin file', $compile_plan + items_ok_plan(3) + 2, sub {
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

run_subtest 'Run 2 with wl to pipe', $compile_plan + items_ok_plan(2) + 4, sub {
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

run_subtest 'Run 2 with TIME_LIMIT and IDLE_TIME_LIMIT', $compile_plan * 2 + items_ok_plan(3), sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $while = compile('while.cpp', "while$exe", $_[0] - $compile_plan);
    my $r = run_sp_multiple(undef, [
        program($pipe, undef, { idle_time_limit => 1, stdin => '*1.stdout' })->set_expected_tr($TR_IDLENESS_LIMIT),
        program($pipe, undef, { stdin => '*0.stdout' })->set_expected_tr($TR_OK),
        program($while, undef, { time_limit => 2 })->set_expected_tr($TR_TIME_LIMIT),
    ]);

    clear_tmpdir;
};

run_subtest 'Run 2 with deadlock', $compile_plan + items_ok_plan(2), sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $r = run_sp_multiple(undef, [
        program($pipe, undef, { idle_time_limit => 1, stdin => '*1.stdout' })->set_expected_tr($TR_IDLENESS_LIMIT),
        program($pipe, undef, { idle_time_limit => 2, stdin => '*0.stdout' })->set_expected_tr($TR_OK),
    ]);

    clear_tmpdir;
};

run_subtest 'Run 2 with different way to IDLE_TIME_LIMIT', $compile_plan * 2 + items_ok_plan(3), sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $sleep = compile('close_stdout.cpp', "sleep$exe", $_[0] - $compile_plan);
    my $r = run_sp_multiple(undef, [
        program($pipe, undef, { idle_time_limit => 1, stdin => '*1.stdout' })->set_expected_tr($TR_IDLENESS_LIMIT),
        program($pipe, undef, { stdin => '*0.stdout' })->set_expected_tr($TR_OK),
        program($sleep, [ '2' ], { idle_time_limit => 1 })->set_expected_tr($TR_IDLENESS_LIMIT),
    ]);

    clear_tmpdir;
};

run_subtest 'Close pipes on exit', $compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $empty = compile('empty.cpp', "empty$exe", $_[0] - $compile_plan);
    my $r = run_sp_multiple({ deadline => 5 }, [
        program($pipe, undef, { stdin => "*1.stdout" }),
        program($empty, [ '1' ])
    ]);
    is $r->[1]->{exit_status}, 1, 'empty exit status';

    clear_tmpdir;
};

run_subtest 'Force close stdout pipe', $compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $close_stdout = compile('close_stdout.cpp', "close_stdout$exe", $_[0] - $compile_plan);
    my $r = run_sp_multiple({ deadline => 1 }, [
        program($pipe, undef, { stdin => "*1.stdout" }),
        program($close_stdout, [ '0.6' ])
    ]);
    cmp_ok $r->[1]->{consumed}->{wall_clock_time}, '>', 0.5, 'close_stdout time';

    clear_tmpdir;
};

run_subtest 'Force close stdout pipe 10x', $compile_plan * 2 + (items_ok_plan(2) + 1) * 10, sub {
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $close_stdout = compile('close_stdout.cpp', "close_stdout$exe", $_[0] - $compile_plan);
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

run_subtest 'Stdout to file and another program stdin', $compile_plan + items_ok_plan(2) + 1, sub {
    my $out = tmp_name;
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0]);
    my $r = run_sp_multiple({ stdout => $out }, [
        program($pipe, [ 'stdout' ], { stdout => "*1.stdin" }),
        program($pipe)
    ]);
    is_deeply $fu->read_lines_chomp($out), [ 'stdoutstdout' ], 'stdout';

    clear_tmpdir;
};

SKIP: {
    skip('not a Win32 system', 3) unless $is_win;

    my $test_src = FS->catdir($Bin, 'cpp', 'helloworld.cpp');
    my $test_out = FS->catdir($tmpdir, "mingw_m32_test$exe");
    my $gcc_prog = program($gcc, [ '-m32', @gcc_opts, '-O0', '-o', $test_out, $test_src ]);
    my $gcc_test = $builtin_runner->run(undef, $gcc_prog);
    skip('bad -m32 option support', 3) if $gcc_test->exit_code != 0;

    run_subtest 'Win32 compliant stack segment', $compile_plan + 2, sub {
        my $app = compile('helloworld.cpp', "stackseg_good$exe", $_[0], [ '-Wl,--stack=0x40000000', '-m32' ]);
        run_subtest 'lesser than ML', items_ok_plan(1) + 1, sub {
            run_sp(undef, $app);
            is_deeply $spr->stdout_lines, [ 'Hello world!' ], 'stackseg: helloworld stdout';
        };
        run_subtest 'greater than ML', items_ok_plan(1) + 1, sub {
            my $rep = run_sp({ memory_limit => 256 }, $app);
            is_deeply $spr->stdout_lines, [ 'Hello world!' ], 'stackseg: helloworld stdout';
        };
        clear_tmpdir;
    };

    run_subtest 'Win32 excessive stack segment', $compile_plan + 2, sub {
        my $app = compile('helloworld.cpp', "stackseg_bad$exe", $_[0], [ '-Wl,--stack=0x7FFFFFFF', '-m32' ]);
        run_subtest 'lesser than ML', 1, sub {
            my $run = $spr->run(undef, program($app));
            ok @{$run->items->[0]->{errors}}, 'win32 error expected'
        };
        run_subtest 'greater than ML', items_ok_plan(1), sub {
            my $rep = run_sp({ memory_limit => 1024 }, $app, undef, undef, $TR_MEMORY_LIMIT);
        };
        clear_tmpdir;
    };

    run_subtest 'Win32 excessive data segment', $compile_plan + 2, sub {
        my $app = compile('w32_dataseg.cpp', "w32_dataseg$exe", $_[0], [ '-m32' ]);
        run_subtest 'lesser than ML', 1, sub {
            my $run = $spr->run(undef, program($app));
            ok @{$run->items->[0]->{errors}}, 'win32 error expected'
        };
        run_subtest 'greater than ML', items_ok_plan(1), sub {
            my $rep = run_sp({ memory_limit => 256 }, $app, undef, undef, $TR_MEMORY_LIMIT);
        };
        clear_tmpdir;
    };
}
