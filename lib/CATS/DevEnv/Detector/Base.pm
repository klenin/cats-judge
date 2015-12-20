package CATS::DevEnv::Detector::Base;
use strict;
use warnings;

use File::Spec;
use CATS::DevEnv::Detector::Utils;

sub new {
    my $class = shift;
    bless { @_ }, $class;
}

sub detect {
    my ($self) = @_;
    $self->{result} = {};
    $self->_detect;
    return $self->{result};
}

sub _detect {
    die 'abstract method called ', (caller(0))[3], "\n";
}

sub validate {
    my ($self, $file) = @_;
    $self->get_version($file) && $self->hello_world($file);
}

sub get_init { '' }

sub get_version { '' }

sub hello_world { 0 }

sub add {
    my ($self, $path) = @_;
    $self->{result}->{normalize_path($path)} ||= {
        path => $path,
        version => $self->get_version($path),
        init => $self->get_init($path),
    };
}

sub validate_and_add {
    my ($self, $path) = @_;
    my $p = File::Spec->canonpath($path);
    -f $path && !exists $self->{result}->{normalize_path($p)} or return;
    clear($self->validate($p)) && $self->add($p);
}

1;
