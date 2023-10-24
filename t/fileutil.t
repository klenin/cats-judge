use strict;
use warnings;

use Test::More tests => 97;
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

like CATS::FileUtil::fn([ 'a', 'b' ]), qr/a.b/, 'fn';

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
    is_deeply [ $fu->load_file($fn, 2) ], [ 'ab', 4 ], 'load_file';
    is_deeply $fu->read_lines($fn), [ "abc\n" ], 'write_to_file read_lines';
    is_deeply $fu->read_lines_chomp($fn), [ 'abc' ], 'write_to_file read_lines_chomp';
    unlink $fn;
}

{
    my $fu = make_fu;
    my $p = [ $tmpdir, 'f.txt' ];
    my $data = "\x01\x00\x1A\x0D\x0D\x0A\x0A\xFF";
    ok $fu->write_to_file($p, $data), 'write_to_file bin';
    is_deeply [ $fu->load_file($p, 200) ], [ $data, length($data) ], 'load_file bin';
    unlink FS->catfile(@$p);
}

{
    my $fu = make_fu;
    my $p = [ $tmpdir, 'f.txt' ];
    my $data = "abc\x0D\x0A\x0Adef\x0Aqqq";
    ok $fu->write_to_file($p, $data), 'write_to_file bin crlf';
    is_deeply $fu->read_lines($p, io => ':crlf'),
        [ "abc\n", "\n", "def\n", 'qqq' ], 'read_file crlf';
    unlink FS->catfile(@$p);
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
    my $fn = [ $tmpdir, '.dot' ];
    my $ffn = CATS::FileUtil::fn($fn);
    ok $fu->write_to_file($fn, 'abc') && -f $ffn, 'remove .dot prepare';

    ok $fu->remove([ $tmpdir, '*' ]), 'remove .dot by glob';
    ok -f $ffn, 'remove .dot by glob does not work';

    ok $fu->remove_all($tmpdir), 'remove .dot by dir_files';
    ok !-e $ffn, 'remove .dot by dir_files';
}

{
    my $fu = make_fu;

    my $fn = FS->catfile($tmpdir, 'f2.exe');
    ok $fu->write_to_file($fn, 'MZabc') && -f $fn, 'remove_file locked prepare';
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

    my @r = ([], [ $tmpdir, 'aa' ], [ $tmpdir, 'bb' ]);
    my @f = ('', 'a$a.txt', 'b$b.txt');
    ok $fu->ensure_dir($r[1]) && -d CATS::FileUtil::fn($r[1]), 'remove_rec 1 ensure_dir';
    ok $fu->write_to_file([ @{$r[1]}, $f[1] ], 'qqq') && -f CATS::FileUtil::fn([ @{$r[1]}, $f[1] ]),
        'remove_rec 1 prepare';
    ok $fu->remove_all($tmpdir), 'remove_rec 1 ok';
    ok ! @{$fu->dir_files($tmpdir)}, 'remove_rec 1 works';

    for (1..2) {
        ok $fu->ensure_dir($r[$_]) && -d CATS::FileUtil::fn($r[$_]), "remove_rec 2 ensure_dir $_";
        my $ff = [ @{$r[$_]}, $f[$_] ];
        ok $fu->write_to_file($ff, 'qqq') && -f CATS::FileUtil::fn($ff), "remove_rec 2 prepare $_";
    }
    ok $fu->remove_all($tmpdir), 'remove_rec 2 ok';
    ok ! @{$fu->dir_files($tmpdir)}, 'remove_rec 2 works';
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
    map $fu->ensure_dir($_), (
        my ($a1, $a1_b, $a1_c) =
        ([ $tmpdir, 'a1' ], [ $tmpdir, 'a1', 'b' ], [ $tmpdir, 'a1', 'c' ]));
    is_deeply
        [ sort @{$fu->dir_files($a1)} ],
        [ map CATS::FileUtil::fn($_), $a1_b, $a1_c ], 'dir_files';
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
    my $fu = make_fu_dies;
    $fu->ensure_dir([ $tmpdir, 'a1' ]);
    $fu->ensure_dir([ $tmpdir, 'a2' ]);
    $fu->write_to_file([ $tmpdir, 'a1', '01' ], '111');
    $fu->write_to_file([ $tmpdir, 'a2', '02' ], '222');
    my $fn1 = [ $tmpdir, '01.txt' ];
    ok $fu->copy_glob([ $tmpdir, 'a?', '01' ], $fn1), 'copy_glob';
    ok -f FS->catfile(@$fn1), 'copy_glob after';
    is_deeply $fu->read_lines($fn1), [ '111' ], 'copy_glob read_lines';
    ok $fu->remove([ $tmpdir, '01.txt' ]), 'remove after copy_glob 1';

    throws_ok { $fu->copy_glob([ $tmpdir, 'a?', '*' ], 'zzz') }
        qr/duplicate/, 'copy_glob duplicate';
    ok !-f FS->catfile($tmpdir, 'zzz'), 'copy_glob duplicate no copy';

    ok $fu->remove([ $tmpdir, 'a?' ]), 'remove after copy_glob 2';
}

{
    my $fu = make_fu_dies;
    $fu->ensure_dir([ $tmpdir, 'r' ]);
    $fu->write_to_file([ $tmpdir, 'r', 'пример' ], '111');
    my $fn1 = [ $tmpdir, '01.txt' ];
    ok $fu->copy_glob([ $tmpdir, 'r', '*' ], $fn1), 'copy_glob encoding';
    ok -f FS->catfile(@$fn1), 'copy_glob encoding';
    is_deeply $fu->read_lines($fn1), [ '111' ], 'copy_glob read_lines encoding';
    ok $fu->remove([ $tmpdir, '*' ]), 'remove after copy_glob encoding';
}

{
    my $fu = make_fu;
    is $fu->quote_fn('abc'), 'abc', 'no quote';
    my $q = $^O eq 'MSWin32' ? '"' : "'";
    is $fu->quote_fn(' a bc'), "$q a bc$q", 'quote';
    is $fu->quote_fn(q~a "'bc~),
        ($^O eq 'MSWin32' ? q~"a \"'bc"~ : q~'a "'\''bc'~), 'escape quote';

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
    throws_ok { sb('{') } qr/opening/i, 'split_braced unmatched opening';
    throws_ok { sb('}') } qr/closing/i, 'split_braced unmatched closing';
}

sub test_run {
    plan tests => 33;
    my $fu = make_fu(@_);
    my $perl = "{$^X}";

    {
        my $r = $fu->run([ [ $tmpdir, 'nofile' ] ]);
        is $r->ok, 0, 'run nonexistent';
        is $r->exit_code, 0, 'run nonexistent exit_code';
    }
    is $fu->run([ $perl, '-v' ])->ok, 1, 'run 0';
    {
        my $r = $fu->run([ $perl, '-e', '{print 123}' ]);
        is $r->ok, 1, 'run 1';
        is $r->err, '', 'run 1 no err';
        is $r->exit_code, 0, 'run 1 exit_code';
        is_deeply $r->stdout, [ '123' ], 'run 1 stdout';
        is_deeply $r->stderr, [], 'run 1 stderr';
        is_deeply $r->full, [ '123' ], 'run 1 full';
    }

    {
        my $r = $fu->run([ $perl, '-e', '{print qq~5\n~ x 10}' ]);
        is $r->ok, 1, 'run lines';
        is $r->err, '', 'run lines no err';
        is $r->exit_code, 0, 'run lines exit_code';
        is_deeply $r->stdout, [ ("5\n") x 10 ], 'run lines stdout';
        is_deeply $r->stderr, [], 'run lines stderr';
        is_deeply $r->full, [ ("5\n") x 10 ], 'run 1 full';
    }

    {
        my $r = $fu->run([ $perl, '-e', '{print STDERR 567}' ]);
        is $r->ok, 1, 'run 2';
        is $r->err, '', 'run 2 no err';
        is $r->exit_code, 0, 'run 2 exit_code';
        is_deeply $r->stdout, [], 'run 2 stdout';
        is_deeply $r->stderr, [ '567' ], 'run 2 stderr';
        is_deeply $r->full, [ '567' ], 'run 2 full';
    }

    {
        my $fn = [ $tmpdir, 't.pl' ];
        $fu->write_to_file($fn, 'print 3*3') or die;
        my $r = $fu->run([ $perl, $fn ]);
        is $r->ok, 1, 'run fn';
        is $r->err, '', 'run fn no err';
        is $r->exit_code, 0, 'run fn exit_code';
        is_deeply $r->stdout, [ '9' ], 'run fn stdout';
        $fu->remove($fn) or die;
    }

    {
        my $r = $fu->run([ $perl, '-e', '{print STDOUT 768; die 876;}' ]);
        is $r->ok, 0, 'run out+die';
        like $r->err, qr/255/, 'run out+die exit 255';
        is $r->exit_code, 255, 'run out+die exit_code';
        is_deeply $r->stdout, [ '768' ], 'run out+die stdout';
        like $r->stderr->[0], qr/876/, 'run out+die stderr';
    }

    {
        my $r = $fu->run([ $perl, '-e', '{exit 77}' ]);
        is $r->ok, 0, 'run exit 77 ok';
        is $r->exit_code, 77, 'run exit 77 exit_code';
    }

    ok $fu->remove([ $tmpdir, '*.txt' ]), 'run cleanup';
}

subtest 'run no IPC', sub { test_run(run_method => 'system', run_temp_dir => $tmpdir); };
subtest 'run IPC', sub { IPC::Cmd->can_capture_buffer ?
    test_run(run_method => 'ipc') : plan skip_all => 'Bad IPC' };

