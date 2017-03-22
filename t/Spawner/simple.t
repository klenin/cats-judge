use strict;
use warnings;

use Test::More tests => 90;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use CATS::Spawner::Const ':all';

ok -x $sp, 'exists';

my $spq = $fu->quote_fn($sp);

ok `$spq` && $? == 0, 'runs';
ok `$spq $perl -v` && $? == 0, 'runs perl';

is $TR_OK, 1, 'const';

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
    my $app = CATS::Spawner::Program->new($perl, [ '-e', '{print 1}' ]);
    my $r = $s->run(undef, $app);
    my $ri = single_item_ok($r, $msg);
    is $ri->{limits}->{memory}, undef, "$msg limit";
    is_deeply $s->stdout_lines, [ '1' ], "$msg stdout";
}

sub out_err {
    my ($s, $msg) = @_;
    $msg .= ' out+err';
    my $fn = [ $tmpdir, 't.pl' ];
    $fu->write_to_file($fn, "print STDOUT 'OUT';\ndie 'ERR';\n") or die;
    my $app = CATS::Spawner::Program->new($perl, [ $fn ]);
    my $r = $s->run(undef, $app);
    my $ri = single_item_ok($r, $msg);
    like $ri->{exit_status}, qr/255/, "$msg out+err status";
    is_deeply $s->stdout_lines, [ 'OUT' ], "$msg stdout";
    like $s->stderr_lines->[0], qr/ERR/, "$msg stderr";
    $fu->remove($fn) or die;
}

sub time_limit {
    my ($s, $msg) = @_;
    $msg .= ' TL';
    my $tl = $^O eq 'MSWin32' ? 0.3 : 1.0;
    my $app = CATS::Spawner::Program->new($perl, [ '-e', '{1 while 1;}' ]);
    my $r = $s->run({ time_limit => $tl }, $app);
    my $ri = single_item_ok($r, $msg, $TR_TIME_LIMIT);
    is 1*$ri->{limits}->{user_time}, $tl, "$msg limit";
    cmp_ok abs($ri->{consumed}->{user_time} - $tl), '<', 0.1, "$msg consumed";
}

sub deadline {
    my ($s, $msg) = @_;
    $msg .= ' deadline';
    my $dl = $^O eq 'MSWin32' ? 0.3 : 1.0;
    my $app = CATS::Spawner::Program->new($perl, [ '-e', '{sleep 1; 1 while 1;}' ]);
    my $r = $s->run({ deadline => $dl }, $app);
    my $ri = single_item_ok($r, $msg, $TR_TIME_LIMIT);
    is 1*$ri->{limits}->{wall_clock_time}, $dl, "$msg limit";
    cmp_ok $ri->{consumed}->{user_time}, '<', 0.5 * $dl, "$msg consumed user";
    cmp_ok abs($ri->{consumed}->{wall_clock_time} - $dl), '<', 0.1, "$msg consumed wall";
}

sub idle_time_limit {
    my ($s, $msg) = @_;
    $msg .= ' IL';
    my $il = $^O eq 'MSWin32' ? 0.3 : 1.0;
    my $app = CATS::Spawner::Program->new($perl, [ '-e', '{sleep 1000;}' ]);
    my $r = $s->run({ idle_time_limit => $il }, $app);
    my $ri = single_item_ok($r, $msg, $TR_IDLENESS_LIMIT);
    is 1*$ri->{limits}->{idle_time}, $il, "$msg limit";
    cmp_ok $ri->{consumed}->{user_time}, '<', 0.1, "$msg consumed user";
    cmp_ok abs($ri->{consumed}->{wall_clock_time} - $il), '<', 0.2, "$msg consumed wall";
}

sub memory_limit {
    my ($s, $msg) = @_;
    $msg .= ' ML';
    my $ml = $^O eq 'MSWin32' ? 10 : 50;
    my $app = CATS::Spawner::Program->new($perl, [ '-e', '{$x .= 2 x 10_000 while 1;}' ]);
    my $r = $s->run({ memory_limit => $ml }, $app);
    $ml *= 1024 * 1024;
    my $ri = single_item_ok($r, $msg, $TR_MEMORY_LIMIT);
    is 1*$ri->{limits}->{memory}, $ml, "$msg limit";
    cmp_ok abs($ri->{consumed}->{memory} - $ml) / $ml, '<', 0.2, "$msg consumed";
}

sub write_limit {
    my ($s, $msg) = @_;
    $msg .= ' WL';
    my $wl = $^O eq 'MSWin32' ? 2 : 20;
    my $app = CATS::Spawner::Program->new($perl, [ '-e', '{print 2 x 10_000 while 1;}' ]);
    my $r = $s->run({ write_limit => $wl }, $app);
    $wl *= 1024 * 1024;
    my $ri = single_item_ok($r, $msg, $TR_WRITE_LIMIT);
    is 1*$ri->{limits}->{write}, $wl, "$msg limit";
    cmp_ok abs($ri->{consumed}->{write} - $wl) / $wl, '<', 0.15, "$msg consumed";
}

my $bi = CATS::Spawner::Builtin->new({
    logger => CATS::Logger::Die->new, run_temp_dir => $tmpdir, run_method => 'ipc' });
my $bs = CATS::Spawner::Builtin->new({
    logger => CATS::Logger::Die->new, run_temp_dir => $tmpdir, run_method => 'system' });
my %p = (
    logger => CATS::Logger::Die->new,
    path => $sp,
    save_stdout => [ $tmpdir, 'stdout.txt' ],
    save_stderr => [ $tmpdir, 'stderr.txt' ],
    save_report => [ $tmpdir, 'report.txt' ],
);
my $dt = CATS::Spawner::Default->new({ %p });
my $dj = CATS::Spawner::Default->new({ %p, json => 1 });

simple($bi, 'bi');
out_err($bi, 'bi');

simple($bs, 'bs');
out_err($bs, 'bs');

simple($dt, 'dt');
out_err($dt, 'dt');
time_limit($dt, 'dt');
memory_limit($dt, 'dt');
write_limit($dt, 'dt');

simple($dj, 'dj');
out_err($dj, 'dj');
time_limit($dj, 'dj');
deadline($dj, 'dj');
idle_time_limit($dj, 'dj');
memory_limit($dj, 'dj');
write_limit($dj, 'dj');

$fu->remove([ $tmpdir, '*.txt' ]);
