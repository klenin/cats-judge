use strict;
use warnings;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use Test::More tests => 13;
use CATS::Spawner::Const ':all';

run_subtest 'Empty controller', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $empty = compile('empty.cpp', "empty$exe", $_[0]);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0] - compile_plan);

    my $r = run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($empty, [ 1 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' }),
    ]);
    is $r->[0]->{exit_status}, 1, 'controller exit status';

    clear_tmpdir;
};
run_subtest 'Empty agent', compile_plan * 2 + items_ok_plan(2) + 2, sub {
    my $pc = compile('pipe_controller.cpp', "pc$exe", $_[0]);
    my $empty = compile('empty.cpp', "empty$exe", $_[0] - compile_plan);

    my $r = run_sp_multiple({ time_limit => 1 }, [
        program($pc, [ 1 ], { controller => 1, idle_time_limit => 2 }),
        program($empty, [ 2 ], { stdin => '*0.stdout', stdout => '*0.stdin', idle_time_limit => 1 }),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '1TERMINATED' ], 'controller result';
    is $r->[1]->{exit_status}, 2, 'agent exit status';

    clear_tmpdir;
};

run_subtest 'Controller time limit', compile_plan * 2 + items_ok_plan(2), sub {
    my $while = compile('while.cpp', "while$exe", $_[0]);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0] - compile_plan);

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1}, [
        program($while, undef, { controller => 1 })->set_expected_tr($TR_TIME_LIMIT),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin', idle_time_limit => 2 }),
    ]);

    clear_tmpdir;
};

run_subtest 'Agent time limit', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $pc = compile('pipe_controller.cpp', "pc$exe", $_[0]);
    my $while = compile('while.cpp', "while$exe", $_[0] - compile_plan);

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($pc, [ 1 ], { controller => 1, idle_time_limit => 2 }),
        program($while, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_TIME_LIMIT),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '1TERMINATED' ], 'controller result';
    clear_tmpdir;
};

run_subtest 'Pipe controller', compile_plan * 2 + items_ok_plan(2) + items_ok_plan(3) + items_ok_plan(4) + 3, sub {
    my $pc = compile('pipe_controller.cpp', "pc$exe", $_[0]);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0] - compile_plan);

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($pc, [ 1 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '1OK' ], 'controller 1 result';

    clear_tmpdir('*.txt', '*.tmp');

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($pc, [ 2, 1 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '2OK', '1OK' ], 'controller 2 result';

    clear_tmpdir('*.txt', '*.tmp');

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($pc, [ 1, 3, 2 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '1OK', '3OK', '2OK' ], 'controller 3 result';

    clear_tmpdir;
};

run_subtest 'Agent index out of range', compile_plan * 2 + 2, sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0] - compile_plan);

    my $r = $spr->run({ time_limit => 1, deadline => 1 },
        program($sc, [ 6 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })
    );

    my $errors = $r->{items}->[0]->{errors};
    is scalar @$errors, 1, 'spawner errors count';
    like $errors->[0], qr/Agent index out of range: 999#msg/, 'spawner PANIC';

    clear_tmpdir;
};

run_subtest 'Controller wait terminated agent', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0] - compile_plan);

    run_sp_multiple({ time_limit => 1, deadline => 1 }, [
        program($sc, [ 1, 3, 5, 7, 0, 3, 5 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);

    is_deeply $spr->stderr_lines_chomp, [ '1T#', '1T#' ], 'controller result';

    clear_tmpdir;
};

run_subtest 'Controller wait, sleep, wait with empty agent', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $empty = compile('empty.cpp', "empty$exe", $_[0] - compile_plan);

    run_sp_multiple({ time_limit => 1, deadline => 1 }, [
        program($sc, [ 0, 7, 3, 5, 0, 3, 5 ], { controller => 1 }),
        program($empty, undef, { stdin => '*0.stdout', stdout => '*0.stdin' }),
    ]);

    is_deeply $spr->stderr_lines_chomp, [ '1T#', '1T#' ], 'controller result';

    clear_tmpdir;
};

run_subtest 'Controller wait and return, SLEEP agent TR_IL', compile_plan * 2 + items_ok_plan(2), sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $sleep = compile('close_stdout.cpp', "close_stdout$exe", $_[0] - compile_plan);

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($sc, [ 0 ], { controller => 1 }),
        program($sleep, [ 5 ], { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_IDLENESS_LIMIT),
    ]);

    clear_tmpdir;
};

run_subtest 'Controller stop and return, SLEEP agent TR_CONTROLLER', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $sleep = compile('close_stdout.cpp', "close_stdout$exe", $_[0] - compile_plan);

    my $r = run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($sc, [ 1 ], { controller => 1 }),
        program($sleep, [ 5 ], { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);
    cmp_ok $r->[1]->{consumed}->{user_time}, '==', 0, 'agent user time';

    clear_tmpdir;
};

run_subtest 'Controller stop and return, WHILE agent TR_CONTROLLER', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $while = compile('while.cpp', "while$exe", $_[0] - compile_plan);

    my $r = run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($sc, [ 1 ], { controller => 1 }),
        program($while, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);
    cmp_ok $r->[1]->{consumed}->{user_time}, '==', 0, 'agent user time';

    clear_tmpdir;
};

run_subtest 'Controller wait and stop, WHILE agent TR_CONTROLLER', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $while = compile('while.cpp', "while$exe", $_[0] - compile_plan);

    my $r = run_sp_multiple({ time_limit => 1, idle_time_limit => 2 }, [
        program($sc, [ 0, 7, 7, 7, 1 ], { controller => 1 }),
        program($while, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);
    cmp_ok $r->[1]->{consumed}->{user_time}, '>', 0.2, 'agent user time';

    clear_tmpdir;
};

run_subtest 'Controller IL', compile_plan * 2 + items_ok_plan(2), sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $empty = compile('empty.cpp', "empty$exe", $_[0] - compile_plan);

    my $r = run_sp_multiple({ time_limit => 1 }, [
        program($sc, [ 3 ], { controller => 1, idle_time_limit => 0.7 })->set_expected_tr($TR_IDLENESS_LIMIT),
        program($empty, undef, { stdin => '*0.stdout', stdout => '*0.stdin', idle_time_limit => 0.3 }),
    ]);

    clear_tmpdir;
};
