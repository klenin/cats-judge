use strict;
use warnings;

package CATS::Logger::Count;

sub new { bless { msgs => [] }, $_[0]; }

sub msg {
    my ($self, @rest) = @_;
    push @{$self->{msgs}}, join '', @rest;
    undef;
}

sub count { scalar @{$_[0]->{msgs}} }

package CATS::Logger::Die;

sub new { bless {}, $_[0] }

sub msg { die join '', @_[1..$#_] }

package CATS::Logger::FH;

sub new { bless { fh => $_[1] || die }, $_[0] }

sub msg {
    my ($self, @rest) = @_;
    $self->{fh}->print(@rest);
    undef;
}

1;
