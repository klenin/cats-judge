use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::Exception;
use Test::More tests => 3;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');
use lib File::Spec->catdir($FindBin::Bin, '..', 'lib', 'cats-problem');

use CATS::Judge::Config;

{
    my $c = CATS::Judge::Config->new;
    is $c->apply_defines('abc'), 'abc', 'apply no defs';
    $c->{defines} = { x => 1, xy => 2, z => 'x' };
    is $c->apply_defines('abcxd'), 'abc1d', 'apply 1';
    is $c->apply_defines('xyxyzx'), '22x1', 'apply greedy';
}
