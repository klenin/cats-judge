use strict;
use warnings;

use Test::More tests => 51;

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
my $verbose = 0;

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
    my @p = ($judge, grep defined $_, @_);
    print join ' ', map { ref $_ ? join('/', @$_) : $_ } @p if $verbose;
    my $r = $fu->run([ $perl, @p ]);
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

maybe_subtest 'config print', 12, sub {
    like run_judge(qw(config --print sleep_time))->stdout->[0],
        qr/sleep_time = \d+/, 'config print';
    like run_judge(qw(config --bare --print sleep_time))->stdout->[0],
        qr/^\d+$/, 'config print bare';
    is run_judge(qw(config --bare --print DEs/^2$/extension))->stdout->[0],
        "zip\n", 'config print nested';
};

maybe_subtest 'config set', 4, sub {
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

maybe_subtest 'UH on bad compiler', 8, sub {
    like run_judge(qw(install -p), $p_minimal)->stdout->[-1],
        qr/problem.*(cached|installed)/, 'minimal';
    like run_judge_sol($p_minimal, 'ok.cpp', 'config-set' => 'DEs.102.compile=zzz')->stdout->[-1],
        qr/unhandled error/, 'unhandled';
};

SKIP: {
    skip 'ML under linux is unstable', 1 if $^O ne 'MSWin32';
    maybe_subtest 'compiler limits', 8, sub {
        like run_judge(qw(install -p), $p_minimal)->stdout->[-1],
            qr/problem.*(cached|installed)/, 'minimal';
        like run_judge_sol(
            $p_minimal, 'ok.cpp', 'config-set' => 'compile.memory_limit=4')->stdout->[-1],
            qr/compilation error/, 'CE on memory limit';
    };
}

maybe_subtest 'compile_error_flag', 4, sub {
    like run_judge_sol($p_minimal, 'warn.pl',
        de => 501, 'config-set' => "DEs.501.compile_error_flag=FLAG")->stdout->[-1],
        qr/compilation error/, 'compilation error';
};

maybe_subtest 'compile_precompile', 4, sub {
    like run_judge_sol(FS->catfile($path, 'p_precompile'), 'sol',
        de => 3, 'config-set' => qq~"DEs.3.compile_precompile=#perl inc.pl %full_name"~)->stdout->[-1],
        qr/accepted/, 'accepted';
};

SKIP: {
    my ($java, $javac) =
        sort @{$fu->run([ $perl, $judge, 'config --print defines/#javac?$ --bare' ])->stdout};
    chomp for $java, $javac;
    -e $java && -e $javac or skip 'No Java', 1;
    maybe_subtest 'Java rename', 4, sub {
        like run_judge_sol($p_minimal, 'bad_name.java', de => 401)->stdout->[-1], qr/accepted/, 'accepted';
    };
}

maybe_subtest 'reinitialize', 15, sub {
    my $cache_dir = run_judge(qw(config --print cachedir --bare))->stdout->[0];
    chomp $cache_dir;
    ok $cache_dir, 'cache dir';
    my $install_stdout = run_judge(qw(install -p), $p_minimal)->stdout;
    my ($cache_name) = $install_stdout->[-1] =~ /problem '(\w+)' (?:cached|installed)/;
    ok $cache_name,'cache name';
    my $p = CATS::FileUtil::fn([ $cache_dir, $cache_name, 'temp', '0ok.cpp' ]);
    ok -d $p, "to remove: $p";
    $fu->remove($p);
    ok !-e $p, "removed: $p";
    my $stdout = run_judge_sol($p_minimal, 'ok.cpp')->stdout;
    like $stdout->[-1], qr/accepted/, 'accepted';
    is scalar(grep /reinitialize/, @$stdout), 1, 'reinitialize';
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

my $p_unsupported = FS->catfile($path, 'p_unsupported');

maybe_subtest 'unsupported DEs', 4, sub {
    like run_judge(qw(install -p), $p_unsupported)->stdout->[-1],
        qr/unsupported.*999/, 'unsupported';
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
    skip 'ML under linux is unstable', 2 if $^O ne 'MSWin32';
    maybe_subtest 'verdicts ML', 4, sub {
        like run_judge_sol($p_verdicts, 'allocate.cpp')->stdout->[-1],
            qr/memory limit exceeded/, 'ML';
    };
    maybe_subtest 'verdicts ML handicap', 4, sub {
        like run_judge_sol($p_verdicts, 'allocate.cpp',
            'config-set' => 'DEs.102.memory_handicap=600')->stdout->[-1],
            qr/accept/, 'no ML handicap';
    };
}

maybe_subtest 'verdicts WL', 4, sub {
    like run_judge_sol($p_verdicts, 'write_10mb.cpp')->stdout->[-1], qr/write limit exceeded/, 'WL';
};

my $p_partial = FS->catfile($path, 'p_partial');

maybe_subtest 'partial OK', 5, sub {
    my $out = run_judge_sol($p_partial, '1', de => 3, c => 'columns=P', result => 'text')->stdout;
    like $out->[-2], qr/5/, 'partial points';
    like $out->[-8], qr/accepted/, 'partial ok';
};

maybe_subtest 'partial UH', 5, sub {
    my $out = run_judge_sol($p_partial, '2', de => 3)->stdout;
    like $out->[-1], qr/unhandled/, 'partial unhandled';
    like $out->[-2], qr/partial/i, 'partial unhandled message';
};

my $p_generator = FS->catfile($path, 'p_generator');

maybe_subtest 'generator install', 4, sub {
    like run_judge(qw(install --force-install -p), $p_generator)->stdout->[-1],
        qr/problem.*installed/, 'installed';
};

maybe_subtest 'generator', 4, sub {
    like run_judge_sol($p_generator, 'subdir/sol_copy.cpp')->stdout->[-1], qr/accepted/, 'generator';
};

maybe_subtest 'answer text', 4, sub {
    like run_judge_sol($p_generator, '2.out', de => 3, t => 2)->stdout->[-1],
        qr/accepted/, 'answer text';
};

maybe_subtest 'answer text WA', 4, sub {
    like run_judge_sol($p_generator, '2.out', de => 3, t => '2-3')->stdout->[-1],
        qr/wrong answer on test 3/, 'WA';
};

maybe_subtest 'answer STDOUT', 4, sub {
    like run_judge_sol($p_verdicts, 'zero', de => 3)->stdout->[-1], qr/accepted/, 'answer STDOUT';
};

my $p_hash = FS->catfile($path, 'p_hash');

maybe_subtest 'hash', 4, sub {
    like run_judge(qw(i -p), $p_hash)->stdout->[-3],
        qr/Invalid hash for test 3.*old=ea4.*new=da4/, 'hash';
};

my $p_module = FS->catfile($path, 'p_module');

maybe_subtest 'module export', 4, sub {
    like run_judge_sol($p_module, 'test.cpp')->stdout->[-1], qr/accepted/, 'module export'
};

my $p_module_import = FS->catfile($path, 'p_module_import');

maybe_subtest 'module import', 4, sub {
    like run_judge_sol($p_module_import, 'ok.cpp', 'force-install' => undef)->stdout->[-1],
        qr/accepted/, 'module import'
};

maybe_subtest 'module orphan', 6, sub {
    my $r = run_judge(qw(clear-cache -p), $p_module)->stdout;
    like $r->[-3], qr/Orphaned.*test\.module\.1/, 'warning';
    like $r->[-2], qr/Orphaned.*test\.module\.2/, 'warning';
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

my $q_nogen = FS->catfile($path, 'q_nogen');

maybe_subtest 'failed generator', 4, sub {
    like run_judge(qw(install -p), $q_nogen)->stdout->[-1],
        qr/problem.*failed to install/, 'failed';
};

my $q_validator = FS->catfile($path, 'q_validator');

maybe_subtest 'failed validator', 5, sub {
    my $r = run_judge(qw(install -p), $q_validator)->stdout;
    like $r->[-2], qr/input validation failed: #2/, 'validation';
    like $r->[-1], qr/problem.*failed to install/, 'failed';
};

my $q_validator_stdin = FS->catfile($path, 'q_validator_stdin');

maybe_subtest 'stdin validator', 5, sub {
    my $r = run_judge(qw(install -p), $q_validator_stdin)->stdout;
    like $r->[-2], qr/input validation failed: #3/, 'validation';
    like $r->[-1], qr/problem.*failed to install/, 'failed';
};

my $p_main = FS->catfile($path, 'p_main');

maybe_subtest 'main', 4, sub {
    like run_judge_sol($p_main, 'test1.h', de => 102)->stdout->[-1], qr/accepted/, 'main result'
};

my $p_linter = FS->catfile($path, 'p_linter');

maybe_subtest 'linter', 12, sub {
    like run_judge_sol($p_linter, 'ok.cpp')->stdout->[-1], qr/accepted/, 'ok';
    like run_judge_sol($p_linter, 'sol_a.cpp')->stdout->[-1], qr/lint error/, 'before';
    like run_judge_sol($p_linter, 'sol_b.cpp')->stdout->[-1], qr/lint error/, 'after';
};

my $p_quiz_de = FS->catfile($path, 'p_quiz_de');

maybe_subtest 'quiz', 15, sub {
    my $r = run_judge(qw(install -p), $p_quiz_de)->stdout;
    like run_judge_sol($p_quiz_de, 'ok.txt', de => 6)->stdout->[-1], qr/accepted/, 'ok';
    like run_judge_sol($p_quiz_de, 'wrong1.txt', de => 6)->stdout->[-1], qr/wrong answer on test 1/, 'WA';
    like run_judge_sol($p_quiz_de, 'wrong2.txt', de => 6)->stdout->[-1], qr/wrong answer on test 2/, 'WA';
};

1;
