use strict;
use warnings;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use Test::More tests => 3;
use CATS::Spawner::Const ':all';

SKIP: {
    skip('not a Win32 system', 3) unless $is_win;

    my $test_src = FS->catdir($Bin, 'cpp', 'helloworld.cpp');
    my $test_out = FS->catdir($tmpdir, "mingw_m32_test$exe");
    my $gcc_prog = program($gcc, [ '-m32', @gcc_opts, '-O0', '-o', $test_out, $test_src ]);
    my $gcc_test = $Common::builtin_runner->run(undef, $gcc_prog);
    skip('bad -m32 option support', 3) if $gcc_test->exit_code != 0;

    run_subtest 'Win32 compliant stack segment', compile_plan + 2, sub {
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

    run_subtest 'Win32 excessive stack segment', compile_plan + 2, sub {
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

    run_subtest 'Win32 excessive data segment', compile_plan + 2, sub {
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
