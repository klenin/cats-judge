use strict;
use warnings;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use Test::More tests => compile_plan + 11;
use CATS::Spawner::Const ':all';

run_subtest 'HelloWorld', compile_plan + items_ok_plan(1) + 1, sub {
    my $hw = compile('helloworld.cpp', 'helloworld' . $exe, $_[0]);
    run_sp(undef, $hw);
    is_deeply $spr->stdout_lines, [ 'Hello world!' ], 'helloworld stdout';
    clear_tmpdir;
};

{
    print "\nCompile pipe:\n";
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
}

run_subtest 'Open stdin file inside program', compile_plan + items_ok_plan(1) + 1, sub {
    my $input = make_test_file('abc', 1);
    my $fopen = compile('fopen.cpp', "fopen$exe", $_[0]);
    run_sp({ stdin => $input }, $fopen, [ $input ]);
    is_deeply $spr->stdout_lines_chomp, [ 'aabbcc' ], 'merged stdout';
    clear_tmpdir;
};

run_subtest 'Many lines to stdout', compile_plan + items_ok_plan(1), sub {
    my $many_lines = compile('many_lines.cpp', "many_lines$exe", $_[0]);
    run_sp({ deadline => 2 }, $many_lines);
    clear_tmpdir;
};
