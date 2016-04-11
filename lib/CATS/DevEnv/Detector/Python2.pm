package CATS::DevEnv::Detector::Python2;

use strict;
use warnings;
no warnings 'redefine';

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Python 2' }
sub code { '502' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'python');
    which($self, 'python');
    drives($self, 'python', 'python');
    folder($self, '/usr/bin/', 'python');
    registry_glob($self,
        'Python/PythonCore/*/InstallPath/', '', 'python');
}

sub hello_world {
    my ($self, $python) = @_;
    return `"$python" -c "print 'Hello world'"` eq "Hello world\n";
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '--version' ];
    $ok && $buf->[0] =~/Python (2(?:\.\d+)+)/ ? $1 : 0;
}

1;
