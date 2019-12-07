package CATS::DevEnv::Detector::Blender;

use strict;
use warnings;
no warnings 'redefine';

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Blender' }
sub code { '604' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'blender');
    which($self, 'blender');
    program_files($self, 'Blender Foundation/Blender*', 'blender');
    folder($self, '/usr/bin/', 'blender');
}

sub hello_world {
    my ($self, $blender) = @_;

    my $hello_world = <<'END'
print('Hello World')
END
;
    my $source = write_temp_file('hello_world.py', $hello_world);
    `"$blender" -P "$source" -b` =~ 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '--version' ];
    $ok && join ('', @$buf) =~/Blender\s+(\d+(?:\.\d+)+)/ ? $1 : 0;
}

1;
