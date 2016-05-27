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

use Test::More tests => 15;

use File::Spec;
use constant FS => 'File::Spec';
my $path;
BEGIN { $path = FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1]); }

use lib FS->catdir($path, '..', 'lib');

use CATS::FileUtil;

my $tmpdir;
BEGIN {
    $tmpdir = FS->catdir($path, 'tmp');
     -d $tmpdir or mkdir $tmpdir;
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

1;
