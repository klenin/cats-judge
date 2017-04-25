use strict;
use warnings;

use Test::More tests => 88;

use File::Spec;

use constant FS => 'File::Spec';
my $path;
BEGIN { $path = FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1]); }

use lib FS->catdir($path, '..', 'lib');

use CATS::FileUtil;
use CATS::Loggers;

my $perl = "{$^X}";
my $judge = FS->catfile($path, '..', 'judge.pl');
my $fu = CATS::FileUtil->new({ logger => CATS::Logger::Count->new });

sub run_judge {
    my ($name, @args) = @_;
    my $r = $fu->run([ $perl, $judge, @args ]);
    is $r->ok, 1, "$name ok";
    is $r->err, '', "$name no err";
    is $r->exit_code, 0, "$name exit_code";
    $r;
}

sub run_judge_sol {
    my ($name, $problem, $sol, %opt) = @_;
    $opt{de} //= 102;
    $opt{result} //= 'none';
    run_judge($name, qw(run -p), $problem, '-run', [ $problem, $sol ],
        map { +"--$_" => $opt{$_} } sort keys %opt);
}

like join('', @{run_judge('usage')->stdout}), qr/Usage/, 'usage';

like run_judge('config print', qw(config --print sleep_time))->stdout->[0],
    qr/sleep_time = \d+/, 'config print';

like run_judge('config set', qw(config --print sleep_time --config-set sleep_time=99))->stdout->[0],
    qr/sleep_time = 99/, 'config set';

my $p_minimal = FS->catfile($path, 'p_minimal');

like run_judge('minimal', qw(install --force-install -p), $p_minimal)->stdout->[-1],
    qr/problem.*installed/, 'minimal installed';

like run_judge('cached minimal', qw(install -p), $p_minimal)->stdout->[-1],
    qr/problem.*cached/, 'cached minimal';

like run_judge_sol('run minimal', $p_minimal, 'ok.cpp')->stdout->[-1],
    qr/accepted/, 'run minimal accepted';

my $p_verdicts = FS->catfile($path, 'p_verdicts');

like run_judge('verdicts', qw(install --force-install -p), $p_verdicts)->stdout->[-1],
    qr/problem.*installed/, 'verdicts installed';

like run_judge_sol('verdicts OK', $p_verdicts, 'print0.cpp')->stdout->[-1],
    qr/accepted/, 'verdicts OK';

like run_judge_sol('verdicts WA', $p_verdicts, 'print1.cpp')->stdout->[-1],
    qr/wrong answer/, 'verdicts WA';

like run_judge_sol('verdicts PE', $p_verdicts, 'print2.cpp')->stdout->[-1],
    qr/presentation error/, 'verdicts PE';

like run_judge_sol('verdicts UH', $p_verdicts, 'print3.cpp')->stdout->[-1],
    qr/unhandled error/, 'verdicts UH';

like run_judge_sol('verdicts CE', $p_verdicts, '1.in')->stdout->[-1],
    qr/compilation error/, 'verdicts CE';

like run_judge_sol('verdicts RE', $p_verdicts, 'return99.cpp')->stdout->[-1],
    qr/runtime error/, 'verdicts RE';

like run_judge_sol('verdicts TL', $p_verdicts, 'hang.cpp')->stdout->[-1],
    qr/time limit exceeded/, 'verdicts TL';

SKIP: {
    skip 'ML under linux is unstable', 4 if $^O ne 'MSWin32';
    like run_judge_sol('verdicts ML', $p_verdicts, 'allocate.cpp')->stdout->[-1],
        qr/memory limit exceeded/, 'verdicts ML';
}

like run_judge_sol('verdicts WL', $p_verdicts, 'write_10mb.cpp')->stdout->[-1],
    qr/write limit exceeded/, 'verdicts WL';

my $p_generator = FS->catfile($path, 'p_generator');

like run_judge_sol('generator', $p_generator, 'sol_copy.cpp')->stdout->[-1],
    qr/accepted/, 'generator';

like run_judge_sol('answer text', $p_generator, '2.out', de => 3, t => 2)->stdout->[-1],
    qr/accepted/, 'answer text';

like run_judge_sol('answer text WA', $p_generator, '2.out', de => 3, t => '2-3')->stdout->[-1],
    qr/wrong answer on test 3/, 'answer text WA';

my $p_interactive = FS->catfile($path, 'p_interactive');

like run_judge_sol('interactive OK', $p_interactive, 'sol_echo.cpp')->stdout->[-1],
    qr/accepted/, 'interactive OK';

like run_judge_sol('interactive empty', $p_interactive, 'empty.cpp')->stdout->[-1],
    qr/wrong answer/, 'interactive empty';

like run_judge_sol('interactive IL', $p_interactive, 'read.cpp')->stdout->[-1],
    qr/idleness limit exceeded/, 'interactive IL';

1;
