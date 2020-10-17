package CATS::DevEnv::Detector::PyPy;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'PyPy 3' }
sub code { '510' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'pypy');
    which($self, 'pypy');
    drives($self, 'pypy', 'pypy');
    folder($self, '/usr/bin/', 'pypy');
    pbox($self, 'pypy3', '', 'pypy');
}

sub hello_world {
    my ($self, $pypy) = @_;
    return `"$pypy" -c "print ('Hello world')"` eq "Hello world\n";
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '--version' ];
    $ok && $buf->[0] =~/Python (?:3(?:\.\d+)+).+\[PyPy (\d+(?:\.\d+)+)/s ? $1 : 0;
}

1;
