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
}

sub get_init { '' }

sub get_version { '' }

sub hello_world { 0 }

sub validate_and_add {
    my ($self, $path) = @_;
    my $p = File::Spec->canonpath($path);
    my $np = normalize_path($p);
    -f $path && !exists $self->{result}->{$np} or return;

    my $version = $self->get_version($p) or return;
    my $r = $self->{result}->{$np} = { path => $p, version => $version };
    $self->hello_world($p) or return;
    $r->{init} = $self->get_init($p);
    $r->{valid} = 1;
    clear;
}

1;
