use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 30;
use Test::Exception;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');
use lib File::Spec->catdir($FindBin::Bin, '..', 'lib', 'cats-problem');

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

    for ($p->start; $p->current;) {
        $p->set_test_result(0);
    }
    is_deeply $p->state, { 1 => 0, 2 => 0, 3 => 0 }, 'all fail state';
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


{
    my $sg1 = { name => 'sg1', points => 10 };
    my $sg2 = { name => 'sg2', points => 20 };
    my $tests = {
        1 => $sg1, 2 => $sg1, 3 => $sg1, 4 => undef, 5 => undef,
        6 => $sg2, 7 => $sg1, 8 => $sg2, 9 => $sg2, 10 => undef,
    };
    my $p = CATS::TestPlan::ScoringGroups->new(tests => $tests);

    for ($p->start; $p->current; ) {
        $p->set_test_result(1);
    }
    is_deeply $p->state, { map { $_ => 1 } keys %$tests }, "sg state all passed";

    my $fails = { 2 => 1, 4 => 1, 8 => 1 };
    for ($p->start; $p->current; ) {
        $p->set_test_result($fails->{$p->current} ? 0 : 1);
    }
    is_deeply $p->state,
        { 1 => 1, 2 => 0, 4 => 0, 5 => 1, 6 => 1, 8 => 0, 10 => 1 }, "sg state with fails";
}

{
    my $sg1 = { name => 'sg1', hide_details => 1 };
    my $sg2 = { name => 'sg1', depends_on => $sg1 };
    my $tests = { 1 => $sg1, 2 => $sg1, 3 => $sg1, 4 => $sg2, 5 => $sg2, 6 => $sg2 };
    my $p = CATS::TestPlan::ScoringGroups->new(tests => $tests);
    for ($p->start; $p->current; ) {
        $p->set_test_result($p->current % 2);
    }
    is_deeply $p->state,
        { 1 => 1, 2 => 0, 3 => 1, 4 => 0, 5 => 1, 6 => 0 }, "no sg without points";
}

1;
