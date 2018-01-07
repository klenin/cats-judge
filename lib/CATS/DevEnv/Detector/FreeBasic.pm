package CATS::DevEnv::Detector::FreeBasic;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'FreeBasic' }
sub code { '302' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'fbc');
    which($self, 'fbc');
    drives($self, 'FreeBasic', 'fbc');
    lang_dirs($self, 'FreeBasic', '', 'fbc');
}

sub hello_world {
    my ($self, $fbc) = @_;
    my $hello_world =<<'END'
Print "Hello World";
END
;
    my $source = write_temp_file('hello_world.bas', $hello_world);
    my $exe = temp_file('hello_world.exe');
    run command => [ $fbc, $source ] or return;
    my ($ok, undef, undef, $out, $err) = run command => [ $exe ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path,  '-version' ];
    $ok or return 0;
    $buf->[0] =~ /FreeBASIC Compiler - Version ((?:\d+\.)+\d+)/ ? $1 : 0;
}

1;
