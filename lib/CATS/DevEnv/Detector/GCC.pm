package CATS::DevEnv::Detector::GCC;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'GNU C' }
sub code { '105' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'gcc');
    which($self, 'gcc');
    drives($self, 'MinGW/bin/', 'gcc');
    drives($self, 'cygwin/bin/', 'gcc');
    program_files($self, 'MinGW/bin/', 'gcc');
    program_files($self, 'cygwin/bin/', 'gcc');
    pbox($self, 'mingw-w64', 'bin', 'gcc');
}

sub hello_world {
    my ($self, $gcc) = @_;
    my $hello_world = <<'END'
#include <stdio.h>
int main() {
    printf("Hello World");
    return 0;
}
END
;
    my $source = write_temp_file('hello_world.c', $hello_world);
    my $exe = temp_file('hello_world.exe');
    run command => [ $gcc, '-o', $exe, $source ] or return;
    my ($ok, undef, undef, $out) = run command => [ $exe ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, undef, undef, $out) = run command => [ $path, '--version' ];
    $ok && $out->[0] =~ /(?:gcc|GCC).+\s((?:\d+\.)+\d+)/ ? $1 : 0;
}

1;
