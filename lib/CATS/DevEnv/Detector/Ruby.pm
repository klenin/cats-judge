package CATS::DevEnv::Detector::Ruby;

use strict;
use warnings;

use IPC::Cmd qw(run);

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Ruby' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'ruby');
    which($self, 'ruby');
    drives($self, 'ruby', 'ruby');
    lang_dirs($self, 'ruby', 'bin', 'ruby');
    folder($self, '/usr/bin/', 'ruby');
    registry_glob($self,
        'RubyInstaller/MRI/*/InstallLocation/', 'bin', 'ruby');
}

sub hello_world {
    my ($self, $ruby) = @_;
    return `"$ruby" -e "puts 'Hello world'"` eq "Hello world\n";
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '--version' ];
    $ok && $buf->[0] =~/ruby (\d(?:\.\d+)+(?:p\d+))/ ? $1 : 0;
}

1;
