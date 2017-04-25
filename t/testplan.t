use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 26;
use Test::Exception;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');

use CATS::TestPlan;

{
    my $p = CATS::TestPlan::All->new(tests => {});
    $p->start;
    is $p->current, undef, 'empty';
    is $p->first_failed, undef, 'empty first failed';
    throws_ok { $p->set_test_result } qr/without current/, 'empty set_test_result';
}

sub make_tests { +{ map { $_ => undef } 1 .. $_[0] } }

{
    my $p = CATS::TestPlan::All->new(tests => make_tests(3));
    my $i = 0;
    for ($p->start; $p->current; ++$i) {
        $p->set_test_result($i);
    }
    is $i, 3, 'all count';
    is_deeply $p->state, { 1 => 0, 2 => 1, 3 => 2 }, 'all state';
    is $p->first_failed, 1, 'all first failed';
    throws_ok { $p->set_test_result } qr/without current/, 'after all set_test_result';
}

{
    my $n = 5;
    my $p = CATS::TestPlan::ACM->new(tests => make_tests($n));

    my $i = 2;
    for ($p->start; $p->current; ++$i) {
        $p->set_test_result($i);
    }
    is $i, $n + 2, 'acm count';
    is_deeply [ sort { $a <=> $b } keys %{$p->state} ], [ 1 .. $n ], 'acm state keys';
    is_deeply [ sort { $a <=> $b } values %{$p->state} ], [ 2 .. $n + 1 ], 'acm state values';
    is $p->first_failed, undef, "acm no first failed";
}

for my $try (1..3) {
    my $n = 20;
    my $f = 10;
    my $p = CATS::TestPlan::ACM->new(tests => make_tests($n));
    my $i = 1;
    for ($p->start; $p->current; ++$i) {
        $p->set_test_result($p->current < $f ? 1 : 0);
    }
    cmp_ok $i, '>=', $f + 1, "acm $try min";
    cmp_ok $i, '<=', $f + 2, "acm $try max";
    is_deeply
        [ sort { $a <=> $b } grep $p->state->{$_}, keys %{$p->state} ],
        [ 1 .. $f - 1 ], "acm $try passed";
    is $p->state->{$f}, 0, "acm $try failed";
    is $p->first_failed, $f, "acm $try first failed";
}

1;
