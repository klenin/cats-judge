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

use Test::More tests => 6;

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

1;
