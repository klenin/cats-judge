package CATS::DevEnv::Detector::VStudioCL;

use strict;
use warnings;

use File::Spec;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Visual C++' }
sub code { '113' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'cl');
    which($self, 'cl');
    registry_glob($self,
        'Microsoft/VisualStudio/*/ShellFolder', 'VC/bin', 'cl');
    registry_glob($self,
        'Microsoft/VisualStudio/*/Setup/VC/ProductDir', 'bin', 'cl');
}

sub hello_world {
    my ($self, $cl) = @_;
    my $hello_world =<<'END'
#include <iostream>
int main() {
    std::cout << "Hello World";
    return 0;
}
END
;
    my $source = write_temp_file('hello_world.cpp', $hello_world);
    my $exe = temp_file('hello_world.exe');
    my $vcvarsall = $self->get_init($cl);
    my $tmp = TEMP_SUBDIR;
    my $compile =<<END
\@echo off
$vcvarsall
cd $tmp
"$cl" /Ox /EHsc /nologo "$source" /Fe"$exe" 1>nul
cd ..
END
;
    my $compile_bat = write_temp_file('compile.bat', $compile);
    run(command => $compile_bat) && `"$exe"` eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path ];
    $ok or return;
    $buf->[0] =~ m/C\/C\+\+.+\s((?:\d+\.)+\d+)\s.+86/ ? $1 : 0;
}

sub get_init {
    my ($self, $path) = @_;
    my $vcvarsall_dir = File::Spec->rel2abs('../..', $path);
    my $res = File::Spec->catfile($vcvarsall_dir, 'vcvarsall.bat');
    return -e $res ? qq~call "$res"~ : '';
}

1;
