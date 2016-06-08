use strict;
use warnings;

use Test::More tests => 16;

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
ok `$sp` && $? == 0, 'runs';
ok `$sp $perl -v` && $? == 0, 'runs perl';

is $TR_OK, 1, 'const';

my $b = CATS::Spawner::Builtin->new({
    logger => CATS::Logger::Die->new, run_temp_dir => $tmpdir });

{
    my $r = $b->run(application => $perl, arguments => [ '-e', '{print(1)}' ]);
    is scalar @{$r->items}, 1, 'spawner builtin single item';
    is $r->items->[0]->{terminate_reason}, $TR_OK, 'spawner builtin basic';
}

my $d = CATS::Spawner::Default->new({
    logger => CATS::Logger::Die->new,
    path => $sp,
    save_stdout => [ $tmpdir, 'stdout.txt' ],
    save_stderr => [ $tmpdir, 'stderr.txt' ],
    save_report => [ $tmpdir, 'report.txt' ],
});

sub dq { $fu->quote_fn($fu->quote_fn($_[0])) }

{
    my $r = $d->run(application => $perl, arguments => [ '-e', dq('print 1') ]);
    is scalar @{$r->items}, 1, 'spawner def single item';
    my $ri = $r->items->[0];
    is_deeply $ri->{errors}, [], 'spawner def no errors';
    is $ri->{terminate_reason}, $TR_OK, 'spawner def';
    is $ri->{limits}->{memory}, undef, 'spawner def limit';
    is_deeply $fu->read_lines($d->{opts}->{save_stdout}), [ '1' ], 'spawner def stdout';
}

{
    my $r = $d->run(
        application => $perl, arguments => [ '-e', dq('1 while 1;') ],
        time_limit => 0.3);
    is scalar @{$r->items}, 1, 'spawner TL single item';
    my $ri = $r->items->[0];
    is_deeply $ri->{errors}, [], 'spawner TL no errors';
    is 1*$ri->{limits}->{user_time}, 0.3, 'spawner TL limit';
    is $ri->{terminate_reason}, $TR_TIME_LIMIT, 'spawner TL';
    ok abs($ri->{consumed}->{user_time} - 0.3) < 0.1, 'spawner TL consumed';
}

$fu->remove([ $tmpdir, '*.txt' ]);

1;

