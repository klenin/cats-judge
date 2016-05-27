package CATS::FileUtil;

use strict;
use warnings;

use File::Spec;

sub new {
    my ($class, $opts) = @_;
    my $self = { logger => $opts->{logger} };
    bless $self, $class;
}

sub log {
    my ($self, @rest) = @_;
    $self->{logger}->msg(@rest);
}

sub fn {
    my ($file) = @_;
    ref $file eq 'ARRAY' ? File::Spec->catfile(@$file) : $file;
}

sub write_to_file {
    my ($self, $file_name, $src) = @_;
    my $fn = fn($file_name);
    open my $file, '>', $fn or return $self->log("open failed: '$fn' ($!)\n");
    binmode $file;
    print $file $src;
    1;
}

1;
