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
    my $v = $self->get_version($file) or return;
    $self->hello_world($file) ? $v : undef;
}

sub get_init { '' }

sub get_version { '' }

sub hello_world { 0 }

sub add {
    my ($self, $path, $version) = @_;
    $self->{result}->{normalize_path($path)} ||= {
        path => $path,
        version => $version,
        init => $self->get_init($path),
    };
}

sub validate_and_add {
    my ($self, $path) = @_;
    my $p = File::Spec->canonpath($path);
    -f $path && !exists $self->{result}->{normalize_path($p)} or return;
    my $version = $self->validate($p) or return;
    clear;
    $self->add($p, $version);
}

1;
