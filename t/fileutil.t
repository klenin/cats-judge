package Logger;

sub new { bless { count => 0 }, $_[0]; }
sub msg { $_[0]->{count}++ }
sub count { $_[0]->{count} }

package main;

use strict;
use warnings;

use Test::More tests => 5;

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
    ok $fu->write_to_file($p, 'abc'), 'write_to_file';
    ok -f FS->catfile(@$p), 'write_to_file exists';
    unlink FS->catfile(@$p);
}

1;
