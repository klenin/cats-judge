use strict;
use warnings;

use Test::More tests => 62;
use Test::Exception;

use File::Spec;
use IPC::Cmd;

use constant FS => 'File::Spec';
my $path;
BEGIN { $path = FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1]); }

use lib FS->catdir($path, '..', 'lib');

use CATS::FileUtil;
use CATS::Loggers;

my $tmpdir;
BEGIN {
    $tmpdir = FS->catdir($path, 'tmp');
     -d $tmpdir or mkdir $tmpdir or die 'Unable to create temporary directory';
}
END { -d $tmpdir and rmdir $tmpdir }

sub make_fu { CATS::FileUtil->new({ logger => CATS::Logger::Count->new, @_ }) }
sub make_fu_dies { CATS::FileUtil->new({ logger => CATS::Logger::Die->new, @_ }) }

isa_ok make_fu, 'CATS::FileUtil', 'fu';

{
    my $fu = make_fu;
    ok !$fu->write_to_file($tmpdir, 'abc'), 'write_to_file dir';
    is $fu->{logger}->count, 1, 'write_to_file dir log';
}

{
    my $fu = make_fu_dies;
    throws_ok { $fu->read_lines([ $tmpdir, 'notxt' ]) } qr/notxt/, 'read_lines nonexistent die';
}

{
    my $fu = make_fu;
    ok !$fu->read_lines([ $tmpdir, 'notxt' ]), 'read_lines nonexistent';
    is $fu->{logger}->count, 1, 'read_lines nonexistent log';
}

{
    my $fu = make_fu;
    my $p = [ $tmpdir, 'f.txt' ];
    my $data = "abc\n";
    ok $fu->write_to_file($p, $data), 'write_to_file';
    my $fn = FS->catfile(@$p);
    ok -f $fn, 'write_to_file exists';
    is -s $fn, length $data, 'write_to_file size';
    is_deeply $fu->read_lines($fn), [ "abc\n" ], 'write_to_file read_lines';
    is_deeply $fu->read_lines_chomp($fn), [ 'abc' ], 'write_to_file read_lines_chomp';
    unlink $fn;
}

{
    my $fu = make_fu;
    ok !$fu->remove_file([ $tmpdir, 'f.txt' ]), 'remove_file no file';
    is $fu->{logger}->count, 1, 'remove_file no file log';
}

{
    my $fu = make_fu;

    my $fn = FS->catfile($tmpdir, 'f1.txt');
    ok $fu->write_to_file($fn, 'abc') && -f $fn, 'remove_file prepare';

    ok $fu->remove_file($fn), 'remove_file';
    ok ! -f $fn, 'remove_file ok';
    is $fu->{logger}->count, 0, 'remove_file no log';
}

{
    my $fu = make_fu;

    my $fn = FS->catfile($tmpdir, 'f2.exe');
    $fu->write_to_file($fn, 'MZabc') && -f $fn;
    subtest 'remove_file locked ', sub {
        plan $^O eq 'MSWin32' ? (tests => 3) : (skip_all => 'Windows only');
        open my $f, '<', $fn or die "$fn: $!";
        ok !$fu->remove_file($fn), 'remove_file locked';
        ok -f $fn, 'remove_file locked ok';
        ok $fu->{logger}->count > 0, 'remove_file locked log';
    };
    ok $fu->remove_file($fn), 'remove_file unlocked';
    ok ! -f $fn, 'remove_file unlocked ok';
}

{
    my $fu = make_fu;
    my $dn = FS->catfile($tmpdir, 'td');
    ok !-d $dn, 'ensure_dir before';
    $fu->ensure_dir($dn);
    ok -d $dn, 'ensure_dir after';
    $fu->ensure_dir($dn);
    rmdir $dn;
    throws_ok { $fu->ensure_dir([ $tmpdir, 'a/b' ], 'xxx') } qr/xxx/, 'ensure_dir fail';
}

{
    my $fu = make_fu;
    $fu->ensure_dir([ $tmpdir, 'a' ]);
    $fu->ensure_dir([ $tmpdir, 'a', 'b' ]);
    $fu->ensure_dir([ $tmpdir, 'a', 'c' ]);
    $fu->write_to_file([ $tmpdir, 'a', 'b', 'f.txt' ], 'f');
    $fu->write_to_file([ $tmpdir, "z$_" ], "z$_") for 1..2;

    ok 2 == grep(-f FS->catfile($tmpdir, "z$_"), 1..2), 'remove glob before';
    ok $fu->remove([ $tmpdir, 'z*' ]), 'remove glob';
    ok 0 == grep(-f FS->catfile($tmpdir, "z$_"), 1..2), 'remove glob after';

    ok -f FS->catfile($tmpdir, 'a', 'b', 'f.txt'), 'remove before';
    ok $fu->remove([ $tmpdir, 'a' ]), 'remove';
    ok !-e FS->catfile($tmpdir, 'a'), 'remove after';
    is $fu->{logger}->count, 0, 'remove no log';

    ok $fu->remove([ $tmpdir, 'qqq', 'ppp' ]), 'remove nonexistent';
}

{
    my $fu = make_fu;
    ok $fu->mkdir_clean([ $tmpdir, 'm' ]), 'mkdir';
    ok -d FS->catfile($tmpdir, 'm'), 'mkdir after';
    ok $fu->mkdir_clean([ $tmpdir, 'm', 'n' ]), 'mkdir subdir';
    ok $fu->mkdir_clean([ $tmpdir, 'm' ]), 'mkdir twice';
    ok -d FS->catfile($tmpdir, 'm') && !-e FS->catfile($tmpdir, 'm', 'n'), 'mkdir cleans';

    ok !$fu->mkdir_clean([ $tmpdir, 'm', '1', '2' ]), 'mkdir fail';
    is $fu->{logger}->count, 1, 'mkdir fail log';
    rmdir FS->catfile($tmpdir, 'm') or die;
}

{
    my $fu = make_fu;
    $fu->ensure_dir([ $tmpdir, 'a1' ]);
    $fu->ensure_dir([ $tmpdir, 'a1', 'b' ]);
    $fu->ensure_dir([ $tmpdir, 'a1', 'c' ]);
    $fu->write_to_file([ $tmpdir, 'a1', 'b', 'f.txt' ], 'f');
    ok -f FS->catfile($tmpdir, 'a1', 'b', 'f.txt'), 'copy before';
    ok $fu->copy([ $tmpdir, 'a1' ], [ $tmpdir, 'a2' ]), 'copy';
    ok -f FS->catfile($tmpdir, 'a2', 'b', 'f.txt'), 'copy after';
    is $fu->{logger}->count, 0, 'copy no log';
    ok $fu->remove([ $tmpdir, 'a?' ]), 'remove after copy';
    local $SIG{__WARN__} = sub {};
    ok !$fu->copy([ $tmpdir, 'x' ], $tmpdir), 'copy to self';
    is $fu->{logger}->count, 1, 'copy to self log';
}

{
    my $fu = make_fu;
    is $fu->quote_fn('abc'), 'abc', 'no quote';
    my $q = $^O eq 'MSWin32' ? '"' : "'";
    is $fu->quote_fn(' a bc'), "$q a bc$q", 'quote';
    is $fu->quote_fn(q~a "'bc~),
        ($^O eq 'MSWin32' ? q~"a \"'bc"~ : q~'a "\'bc'~), 'escape quote';

    is $fu->quote_braced('abc'), 'abc', 'no braced';
    is $fu->quote_braced('abc{}'), 'abc', 'empty braced';
    is $fu->quote_braced('{-a -b} {-c} -d'), "$q-a -b$q -c -d", 'braced';
    is $fu->quote_braced('{print 123}'), $q . "print 123$q", 'only braced';
    is $fu->quote_braced([ 'a b', 'c' ]), $q . FS->catfile('a b', 'c') . $q, 'braced fn';
}

{
    *sb = \&CATS::FileUtil::_split_braced;
    is_deeply [ sb('abc') ], [ 'abc' ], 'split_braced no braces';
    is_deeply [ sb('{abc}') ], [ 'abc' ], 'split_braced 1';
    is_deeply [ sb('{a  bc} d  ef') ], [ 'a  bc', 'd', 'ef' ], 'split_braced 2';
    is_deeply [ sb('a{ abc }  ') ], [ 'a', ' abc ' ], 'split_braced 3';
    is_deeply [ sb('{}{}') ], [ '', '' ], 'split_braced empty';
    throws_ok { sb('{{') } qr/nested/i, 'split_braced nested';
    throws_ok { sb('}') } qr/unmatched/i, 'split_braced unmatched';
}

sub test_run {
    plan tests => 14;
    my $fu = make_fu(@_);
    my $perl = "{$^X}";

    is $fu->run([ $tmpdir, 'nofile' ])->ok, 0, 'run nonexistent';
    is $fu->run([ $perl, '-v' ])->ok, 1, 'run 0';

    {
        my $r = $fu->run([ $perl, '-e', '{print 123}' ]);
        is $r->ok, 1, 'run 1';
        is $r->err, '', 'run 1 no err';
        is_deeply $r->stdout, [ '123' ], 'run 1 stdout';
        is_deeply $r->stderr, [], 'run 1 stderr';
        is_deeply $r->full, [ '123' ], 'run 1 full';
    }

    {
        my $r = $fu->run([ $perl, '-e', '{print STDERR 567}' ]);
        is $r->ok, 1, 'run 2';
        is $r->err, '', 'run 2 no err';
        is_deeply $r->stdout, [], 'run 2 stdout';
        is_deeply $r->stderr, [ '567' ], 'run 2 stderr';
        is_deeply $r->full, [ '567' ], 'run 2 full';
    }

    is $fu->run([ $perl, '-e', '{exit 77}' ])->ok, 0, 'run exit 77';

    ok $fu->remove([ $tmpdir, '*.txt' ]), 'run cleanup';
}

subtest 'run no IPC', sub { test_run(run_use_ipc => 0, run_temp_dir => $tmpdir); };
subtest 'run IPC',
    IPC::Cmd->can_capture_buffer ?
    sub { test_run(run_use_ipc => 1); } : sub { plan skip_all => 'Bad IPC' };

1;
