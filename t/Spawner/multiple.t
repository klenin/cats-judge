use strict;
use warnings;

use Test::More tests => 7;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use CATS::Spawner::Const ':all';

my $is_win = ($^O eq 'MSWin32');

my $exe = $is_win ? '.exe' : '';
my $gcc = $cfg->defines->{'#gnu_cpp'};
ok -x $sp, 'sp exists';
ok -x $gcc, 'gcc exists';

my $builtin_runner = CATS::Spawner::Builtin->new({
    logger => CATS::Logger::Die->new,
    run_temp_dir => $tmpdir,
    run_method => 'system'
});

my $spr = CATS::Spawner::Default->new({
    logger => CATS::Logger::Die->new,
    path => $sp,
    save_stdout => [ $tmpdir, 'stdout.txt' ],
    save_stderr => [ $tmpdir, 'stderr.txt' ],
    save_report => [ $tmpdir, 'report.txt' ],
    json => 1,
});

sub items_ok {
    my ($r, $msg) = @_;
    for my $ri (@{$r->items}) {
        is_deeply $ri->{errors}, [], "$msg no errors";
        is $ri->{terminate_reason}, $TR_OK, "$msg TR_OK";
    }
    $r->items;
}

sub compile {
    my ($src, $out) = @_;
    my $fullsrc = FS->catdir($Bin, 'cpp', $src);
    $out = FS->catdir($tmpdir, $out);
    my $r = $builtin_runner->run(application => $gcc, arguments => [
        '-o',
        $out,
        $fullsrc
    ]);
    items_ok($r, $src . ' compile');
    $out;
}

sub run_sp {
    my ($app, $args) = @_;
    my $r = $spr->run(application => $app, arguments => $args // []);
    items_ok($r, (FS->splitpath($app))[2]);
}

my $hw = compile('helloworld.cpp', 'helloworld' . $exe);
run_sp($hw);
is_deeply $spr->stdout_lines, [ 'Hello world!' ], 'helloworld stdout';
$fu->remove($hw);
$fu->remove([ $tmpdir, '*.txt']);
