package CATS::DevEnv::Detector::Base;
use strict;
use warnings;
use File::Spec;

sub new {
    my $class = shift;
    bless {@_}, $class;
}

sub detect {
    die "abstract method called CATS::DevEnv::DetectorBase::detect";
}

sub validate {
    my ($self, $file) = @_;
    return -e $file;
}

sub get_init {
    return "";
}

sub get_version {
    return "";
}

sub add {
    my ($self, $path) = @_;
    $self->{result}->{$path} = {
        path => $path,
        version => $self->get_version($path),
        init => $self->get_init($path),
    };
}

sub validate_and_add {
    my ($self, $path) = @_;
    my $p = File::Spec->canonpath($path);
    my $res = $self->validate($p);
    $res && $self->add($p);
    return $res;
}

1;
