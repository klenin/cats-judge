use strict;
use warnings;

use Test::More tests => 16;

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

my $p_minimal = FS->catfile($path, 'p_minimal');

{
    my $r = run_judge('usage');
    like join('', @{$r->stdout}), qr/Usage/, 'usage';
}

{
    my $r = run_judge('minimal', qw(install --force-install -p), $p_minimal);
    like $r->stdout->[-1], qr/problem.*installed/, 'minimal installed';
}

{
    my $r = run_judge('cached minimal', qw(install -p), $p_minimal);
    like $r->stdout->[-1], qr/problem.*cached/, 'cached minimal';
}

{
    my $r = run_judge('run minimal',
        qw(run -p), $p_minimal, '--run', [ $p_minimal, 'ok.cpp' ], qw(--de 102 --result none));
    like $r->stdout->[-1], qr/accepted/, 'run minimal accepted';
}

1;
