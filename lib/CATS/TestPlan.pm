use strict;
use warnings;

package CATS::TestPlan;

use CATS::Testset;
use CATS::Constants;

sub new {
    my ($class, %p) = @_;
    my $self = {
        all_testsets => $p{testsets},
        tests => $p{tests},
        state => {},
        plan => [],
        current => undef,
        first_failed => undef,
    };
    bless $self, $class;
}

sub set_test_result {
    my ($self, $result) = @_;
    my $c = $self->current or die 'Setting result without current test';
    !exists $self->{state}->{$c} or die "Test $c is planned twice";
    $self->{state}->{$c} = $result;
    $self->{first_failed} = $c if !$result && ($self->first_failed // 1e10) > $c;
}

sub get_state {
    my ($self, $results) = @_;
    return $cats::st_ignore_submit if !@$results;
    for (@$results) {
        if ($_->{result} != $cats::st_accepted) {
            $self->{first_failed} = $_->{test_rank};
            return $_->{result};
        }
    }
    $cats::st_accepted;
}

sub _get_next {
    my ($self) = @_;
    my $p = $self->{plan};
    $self->{current} = @$p ? shift @$p : undef;
}

sub start {}
sub current { $_[0]->{current} }
sub state { $_[0]->{state} }
sub first_failed { $_[0]->{first_failed} }

package CATS::TestPlan::All;

use base qw(CATS::TestPlan);

sub start {
    my ($self) = @_;
    $self->{state} = {};
    $self->{plan} = [ sort { $a <=> $b } keys %{$self->{tests}} ];
    $self->_get_next;
}

sub set_test_result {
    my ($self, $result) = @_;
    $self->SUPER::set_test_result($result);
    $self->_get_next;
}

# Run tests in random order until fail, then run sequentially to find first failed test.
package CATS::TestPlan::ACM;

use base qw(CATS::TestPlan);

sub start {
    my ($self) = @_;
    $self->{state} = {};
    my $p = $self->{plan} = [ keys %{$self->{tests}} ]; # Randomized by language.
    for (my $i = 0; $i < $#$p; ++$i) {
        my $j = $i + int(rand(@$p - $i));
        ($p->[$i], $p->[$j]) = ($p->[$j], $p->[$i]);
    }
    $self->{phase} = 1;
    $self->_get_next;
}

sub set_test_result {
    my ($self, $result) = @_;
    $self->SUPER::set_test_result($result);
    if (!$result) {
        return $self->{current} = undef if $self->{phase} == 2;
        $self->{phase} = 2;
        $self->{plan} = [
            sort { $a <=> $b }
            grep $_ < $self->current && !exists $self->{state}->{$_},
            keys %{$self->{tests}}
        ];
    }
    $self->_get_next;
}

# Run tests sequentially, after first fail on each scoring group ignore the rest of it.
package CATS::TestPlan::ScoringGroups;

use base qw(CATS::TestPlan);

sub start {
    my ($self) = @_;
    $self->{state} = {};
    $self->{plan} = [ sort { $a <=> $b } keys %{$self->{tests}} ];
    $self->_get_next;
}

sub set_test_result {
    my ($self, $result) = @_;
    $self->SUPER::set_test_result($result);
    my $failed = $self->{tests}->{$self->current};
    if (!$result && $failed && $failed->{points}) {
        $self->{plan} = [
            grep {
                my $t = $self->{tests}->{$_};
                !$t || $t->{name} ne $failed->{name};
            } @{$self->{plan}}
        ];
    }
    $self->_get_next;
}

1;
