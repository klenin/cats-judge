package CATS::DevEnv::Detector::Python3;

use IPC::Cmd qw(run);

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Python2);

sub _detect {
    my ($self) = @_;
    $self->SUPER::_detect();
    env_path($self, 'python3');
    which($self, 'python3');
    drives($self, 'python3', 'python3');
    folder($self, '/usr/bin/', 'python3');
}

sub hello_world {
    my ($self, $python) = @_;
    return `"$python" -c "print ('Hello world')"` eq "Hello world\n";
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '--version' ];
    $ok && $buf->[0] =~/Python (3(?:\.\d+)+)/ ? $1 : 0;
}

1;
