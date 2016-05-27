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

sub remove_file {
    my ($self, $file_name) = @_;
    my $fn = fn($file_name);
    -f $fn || -l $fn or return $self->log("remove_file: '$fn' is not a file\n");

    # Some AV software blocks access to new executables while running checks.
    for my $retry (0..9) {
        unlink $fn or return $self->log("remove_file: unlink '$fn' failed ($!)\n");
        -f $fn || -l $fn or return 1;
        $retry or next;
        sleep 1;
        $self->log("remove_file: '$fn' retry $retry\n");
    }
}

1;
