use strict;
use warnings;

use Test::More tests => 31;

use File::Spec;

use constant FS => 'File::Spec';
my $path;
BEGIN { $path = FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1]); }

use lib FS->catdir($path, '..', 'lib');

use CATS::FileUtil;
use CATS::Loggers;

my $perl = "{$^X}";
my $judge = FS->catfile($path, '..', 'judge.pl');
my $fu = CATS::FileUtil->new({ logger => CATS::Logger::Count->new, run_temp_dir => '.' });


sub maybe_subtest {
    my ($name, $plan, $subtest) = @_;
    SKIP: {
        skip "Skipping, '$name' does not match '$ARGV[0]' ", 1 if $ARGV[0] && $name !~ $ARGV[0];
        subtest $name, sub {
            plan tests => $plan;
            $subtest->();
        }
    }
}

sub run_judge {
    my $r = $fu->run([ $perl, $judge, @_ ]);
    is $r->ok, 1, 'ok';
    is $r->err, '', 'no err';
    is $r->exit_code, 0, 'exit_code';
    $r;
}

sub run_judge_sol {
    my ($problem, $sol, %opt) = @_;
    $opt{de} //= 102;
    $opt{result} //= 'none';
    my @sols = ref $sol eq 'ARRAY' ? @$sol : ($sol);
    my @runs = map { -run => [ $problem, $_ ] } @sols;
    run_judge(qw(run -p), $problem, @runs, map { +"--$_" => $opt{$_} } sort keys %opt);
}

maybe_subtest 'usage', 4, sub {
    like join('', @{run_judge()->stdout}), qr/Usage/, 'usage';
};

maybe_subtest 'config print', 4, sub {
    like run_judge('config print', qw(config --print sleep_time))->stdout->[0],
        qr/sleep_time = \d+/, 'config print';
};

maybe_subtest 'usage', 4, sub {
    like run_judge(qw(config --print sleep_time --config-set sleep_time=99))->stdout->[0],
        qr/sleep_time = 99/, 'config set';
};

my $p_minimal = FS->catfile($path, 'p_minimal');

maybe_subtest 'columns R', 5, sub {
    my $s = run_judge_sol($p_minimal, 'ok.cpp',
        c => 'columns=R', t => 1, result => 'text')->stdout;
    like $s->[-1], qr/^\-+$/, 'last row';
    like $s->[-4], qr/^\s*Rank\s*$/, 'Rank';
};

maybe_subtest 'columns OCRVVTMOW', 5, sub {
    my $s = run_judge_sol($p_minimal, 'ok.cpp',
        c => 'columns=OCRVVTMOW', t => 1, result => 'text')->stdout;
    like $s->[-1], qr/^(\-+\+)+\-+$/, 'last row';
    my @cols = qw(Output Comment Rank Verdict Verdict Time Memory Output Written);
    is_deeply [ split /\W+/, $s->[-4] ], [ '', @cols ], 'columns OCRVVTMOW';
};

maybe_subtest 'minimal', 4, sub {
    like run_judge(qw(install --force-install -p), $p_minimal)->stdout->[-1],
        qr/problem.*installed/, 'installed';
};

maybe_subtest 'cached minimal', 4, sub {
    like run_judge(qw(install -p), $p_minimal)->stdout->[-1],
        qr/problem.*cached/, 'cached minimal';
};

maybe_subtest 'run minimal', 4, sub {
    like run_judge_sol($p_minimal, 'ok.cpp')->stdout->[-1], qr/accepted/, 'accepted';
};

maybe_subtest 'minimal html', 5, sub {
    my $tmpdir = [ $path, 'tmp' ];
    $fu->ensure_dir($tmpdir);
    like run_judge_sol(
        $p_minimal, 'ok.cpp', result => 'html',
        'config-set' => 'resultsdir=' . FS->rel2abs(CATS::FileUtil::fn($tmpdir))
    )->stdout->[-1],
        qr/accepted/, 'accepted';
    is scalar @{[ glob(FS->catfile(@$tmpdir, '*')) ]}, 1, 'html exists';
    $fu->remove($tmpdir);
};

maybe_subtest 'no tests', 4, sub {
    like run_judge_sol($p_minimal, 'ok.cpp', t => 99)->stdout->[-1], qr/ignore submit/, 'ignored';
};

my $p_verdicts = FS->catfile($path, 'p_verdicts');

maybe_subtest 'verdicts', 4, sub {
    like run_judge(qw(install --force-install -p), $p_verdicts)->stdout->[-1],
        qr/problem.*installed/, 'installed';
};

maybe_subtest 'verdicts OK', 4, sub {
    like run_judge_sol($p_verdicts, 'print0.cpp')->stdout->[-1], qr/accepted/, 'OK';
};

maybe_subtest 'verdicts WA', 4, sub {
    like run_judge_sol($p_verdicts, 'print1.cpp')->stdout->[-1], qr/wrong answer/, 'WA';
};

maybe_subtest 'verdicts WA before PE All', 4, sub {
    like run_judge_sol($p_verdicts, 'copy.cpp')->stdout->[-1], qr/wrong answer on test 1/, 'WA';
};

maybe_subtest 'verdicts WA before PE ACM', 4, sub {
    like run_judge_sol($p_verdicts, 'copy.cpp', 'use-plan' => 'acm' )->stdout->[-1],
        qr/wrong answer on test 1/, 'WA';
};

maybe_subtest 'verdicts PE', 4, sub {
    like run_judge_sol($p_verdicts, 'print2.cpp')->stdout->[-1], qr/presentation error/, 'PE';
};

maybe_subtest 'verdicts UH', 4, sub {
    like run_judge_sol($p_verdicts, 'print3.cpp')->stdout->[-1], qr/unhandled error/, 'UH';
};

maybe_subtest 'verdicts CE', 4, sub {
    like run_judge_sol($p_verdicts, '1.in')->stdout->[-1], qr/compilation error/, 'CE';
};

maybe_subtest 'verdicts RE', 4, sub {
    like run_judge_sol($p_verdicts, 'return99.cpp')->stdout->[-1], qr/runtime error/, 'RE';
};

maybe_subtest 'verdicts TL', 4, sub {
    like run_judge_sol($p_verdicts, 'hang.cpp')->stdout->[-1], qr/time limit exceeded/, 'TL';
};

maybe_subtest 'verdicts multiple', 5, sub {
    my $s = run_judge_sol($p_verdicts, ['print1.cpp', 'print0.cpp', 'hang.cpp'],
        c => 'columns=V', t => 2, result => 'text')->stdout;
    like $s->[-1], qr/^[\-+]+$/, 'last row';
    # Runs are sorted alphabetically.
    like $s->[-2], qr/^\s+TL\s+\|\s+OK\s+\|\s+WA\s+$/, 'verdicts';
};

SKIP: {
    skip 'ML under linux is unstable', 1 if $^O ne 'MSWin32';
    maybe_subtest 'verdicts ML', 4, sub {
        like run_judge_sol($p_verdicts, 'allocate.cpp')->stdout->[-1],
            qr/memory limit exceeded/, 'ML';
    };
}

maybe_subtest 'verdicts WL', 4, sub {
    like run_judge_sol($p_verdicts, 'write_10mb.cpp')->stdout->[-1], qr/write limit exceeded/, 'WL';
};

my $p_generator = FS->catfile($path, 'p_generator');

maybe_subtest 'generator', 4, sub {
    like run_judge_sol($p_generator, 'sol_copy.cpp')->stdout->[-1], qr/accepted/, 'generator';
};

maybe_subtest 'answer text', 4, sub {
    like run_judge_sol($p_generator, '2.out', de => 3, t => 2)->stdout->[-1],
        qr/accepted/, 'answer text';
};

maybe_subtest 'answer text WA', 4, sub {
    like run_judge_sol($p_generator, '2.out', de => 3, t => '2-3')->stdout->[-1],
        qr/wrong answer on test 3/, 'WA';
};

my $p_module = FS->catfile($path, 'p_module');

maybe_subtest 'module import', 4, sub {
    like run_judge_sol($p_module, 'test.cpp')->stdout->[-1], qr/accepted/, 'module import result'
};

maybe_subtest 'module orphan', 5, sub {
    my $r = run_judge(qw(clear-cache -p), $p_module)->stdout;
    like $r->[-2], qr/Orphaned.*test\.module\.1/, 'warning';
    like $r->[-1], qr/cache\s+removed/, 'cache removed';
};

my $p_interactive = FS->catfile($path, 'p_interactive');

maybe_subtest 'interactive OK', 4, sub {
    like run_judge_sol($p_interactive, 'sol_echo.cpp')->stdout->[-1], qr/accepted/, 'OK';
};

maybe_subtest 'interactive empty', 4, sub {
    like run_judge_sol($p_interactive, 'empty.cpp')->stdout->[-1],
        qr/wrong answer/, 'interactive empty';
};

maybe_subtest 'interactive IL', 4, sub {
    like run_judge_sol($p_interactive, 'read.cpp')->stdout->[-1], qr/idleness limit exceeded/, 'IL';
};

1;
