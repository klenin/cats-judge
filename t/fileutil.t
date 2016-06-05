package Logger;

sub new { bless { msgs => [] }, $_[0]; }

sub msg {
    my ($self, @rest) = @_;
    push @{$self->{msgs}}, join '', @rest;
    0;
}

sub count { scalar @{$_[0]->{msgs}} }

package main;

use strict;
use warnings;

use Test::More tests => 46;
use Test::Exception;

use File::Spec;
use constant FS => 'File::Spec';
my $path;
BEGIN { $path = FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1]); }

use lib FS->catdir($path, '..', 'lib');

use CATS::FileUtil;

my $tmpdir;
BEGIN {
    $tmpdir = FS->catdir($path, 'tmp');
     -d $tmpdir or mkdir $tmpdir or die 'Unable to create temporary directory';
}
END { -d $tmpdir and rmdir $tmpdir }

sub make_fu { CATS::FileUtil->new({ logger => Logger->new }) }

isa_ok make_fu, 'CATS::FileUtil', 'fu';

{
    my $fu = make_fu;
    ok !$fu->write_to_file($tmpdir, 'abc'), 'write_to_file dir';
    is $fu->{logger}->count, 1, 'write_to_file dir log';
}

{
    my $fu = make_fu;
    my $p = [ $tmpdir, 'f.txt' ];
    ok $fu->write_to_file($p, 'abc' . chr(10) . chr(13)), 'write_to_file';
    my $fn = FS->catfile(@$p);
    ok -f $fn, 'write_to_file exists';
    is -s $fn, 5, 'write_to_file size';
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
    my $q = $^O eq 'Win32' ? '"' : "'";
    is $fu->quote_fn(' a bc'), "$q a bc$q", 'quote';
    is $fu->quote_fn(q~a "'bc~),
        ($^O eq 'Win32' ? q~"a \"'bc"~ : q~'a "\'bc'~), 'escape quote';

    is $fu->quote_braced('abc'), 'abc', 'no braced';
    is $fu->quote_braced('abc{}'), 'abc', 'empty braced';
    is $fu->quote_braced('{-a -b} {-c} -d'), "$q-a -b$q -c -d", 'braced';
}

1;
