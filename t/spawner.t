use strict;
use warnings;

use Test::More tests => 58;

use File::Spec;
use constant FS => 'File::Spec';
my $path;
BEGIN { $path = FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1]); }

use lib FS->catdir($path, '..', 'lib');
use lib FS->catdir($path, '..', 'lib', 'cats-problem');

use CATS::Spawner::Const ':all';
use CATS::Spawner::Builtin;
use CATS::Spawner::Default;
use CATS::Spawner::Platform;
use CATS::FileUtil;
use CATS::Loggers;

my $tmpdir;
BEGIN {
    $tmpdir = FS->catdir($path, 'tmp');
     -d $tmpdir or mkdir $tmpdir or die 'Unable to create temporary directory';
}
END { -d $tmpdir and rmdir $tmpdir }

my $fu = CATS::FileUtil->new;
my $perl = $fu->quote_fn($^X);
my $sp = FS->catdir($path, '..', CATS::Spawner::Platform::get_path);

ok -x $sp, 'exists';

my $spq = $fu->quote_fn($sp);

ok `$spq` && $? == 0, 'runs';
ok `$spq $perl -v` && $? == 0, 'runs perl';

is $TR_OK, 1, 'const';

my $b = CATS::Spawner::Builtin->new({
    logger => CATS::Logger::Die->new, run_temp_dir => $tmpdir });

{
    my $r = $b->run(application => $perl, arguments => [ '-e', '{print(1)}' ]);
    is scalar @{$r->items}, 1, 'spawner builtin single item';
    is $r->items->[0]->{terminate_reason}, $TR_OK, 'spawner builtin basic';
}

sub single_item_ok {
    my ($r, $msg, $tr) = @_;
    is scalar @{$r->items}, 1, "$msg single item";
    my $ri = $r->items->[0];
    is_deeply $ri->{errors}, [], "$msg no errors";
    is $ri->{terminate_reason}, $tr // $TR_OK, "$msg TR";
    $ri;
}

sub simple {
    my ($s, $msg) = @_;
    $msg .= ' simple';
    my $r = $s->run(application => $perl, arguments => [ '-e', '{print 1}' ]);
    my $ri = single_item_ok($r, $msg);
    is $ri->{limits}->{memory}, undef, "$msg limit";
    is_deeply $fu->read_lines($s->{opts}->{save_stdout}), [ '1' ], "$msg stdout";
}

sub out_err {
    my ($s, $msg) = @_;
    $msg .= ' out+err';
    my $fn = [ $tmpdir, 't.pl' ];
    $fu->write_to_file($fn, "print STDOUT 'OUT';\ndie 'ERR';\n") or die;
    my $r = $s->run(application => $perl, arguments => [ $fn ]);
    my $ri = single_item_ok($r, $msg);
    like $ri->{exit_status}, qr/255/, "$msg out+err status";
    is_deeply $fu->read_lines($s->{opts}->{save_stdout}), [ 'OUT' ], "$msg stdout";
    like $fu->read_lines($s->{opts}->{save_stderr})->[0], qr/ERR/, "$msg stderr";
    $fu->remove($fn) or die;
}

sub time_limit {
    my ($s, $msg) = @_;
    $msg .= ' TL';
    my $tl = $^O eq 'MSWin32' ? 0.3 : 1.0;
    my $r = $s->run(
        application => $perl, arguments => [ '-e', '{1 while 1;}' ],
        time_limit => $tl);
    my $ri = single_item_ok($r, $msg, $TR_TIME_LIMIT);
    is 1*$ri->{limits}->{user_time}, $tl, "$msg limit";
    ok abs($ri->{consumed}->{user_time} - $tl) < 0.1, "$msg consumed";
}

sub memory_limit {
    my ($s, $msg) = @_;
    $msg .= ' ML';
    my $ml = 10;
    my $r = $s->run(
        application => $perl, arguments => [ '-e', '{ $x .= 2 x 10_000 while 1; }' ],
        memory_limit => $ml);
    $ml *= 1024 * 1024;
    my $ri = single_item_ok($r, $msg, $TR_MEMORY_LIMIT);
    is 1*$ri->{limits}->{memory}, $ml, "$msg limit";
    ok abs($ri->{consumed}->{memory} - $ml) / $ml < 0.2, "$msg consumed";
}

sub write_limit {
    my ($s, $msg) = @_;
    $msg .= ' WL';
    my $wl = 2;
    my $r = $s->run(
        application => $perl, arguments => [ '-e', '{ print 2 x 10_000 while 1; }' ],
        write_limit => $wl);
    $wl *= 1024 * 1024;
    my $ri = single_item_ok($r, $msg, $TR_WRITE_LIMIT);
    is 1*$ri->{limits}->{write}, $wl, "$msg limit";
    ok abs($ri->{consumed}->{write} - $wl) / $wl < 0.1, "$msg consumed";
}

my %p = (
    logger => CATS::Logger::Die->new,
    path => $sp,
    save_stdout => [ $tmpdir, 'stdout.txt' ],
    save_stderr => [ $tmpdir, 'stderr.txt' ],
    save_report => [ $tmpdir, 'report.txt' ],
);
my $dt = CATS::Spawner::Default->new({ %p });
my $dj = CATS::Spawner::Default->new({ %p, json => 1 }); 

simple($dt, 'dt');
out_err($dt, 'dt');
time_limit($dt, 'dt');
memory_limit($dt, 'dt');
write_limit($dt, 'dt');

simple($dj, 'dj');
out_err($dj, 'dj');
time_limit($dj, 'dj');
memory_limit($dj, 'dj');
write_limit($dj, 'dj');

$fu->remove([ $tmpdir, '*.txt' ]);
