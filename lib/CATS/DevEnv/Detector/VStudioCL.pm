package CATS::DevEnv::Detector::VStudioCL;

use File::Spec;
use IPC::Run;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub _detect {
    my ($self) = @_;
    env_path($self, 'cl');
    which($self, 'cl');
    registry_loop($self,
        'Microsoft/VisualStudio',
        'ShellFolder',
        'VC/bin/',
        'cl'
    );
}

sub hello_world {
    my ($self, $cl) = @_;
    my $hello_world =<<'END'
#include <iostream>
int main() {
    std::cout << "Hello World";
}
END
;
    my $source = File::Spec->rel2abs(write_file('hello_world.cpp', $hello_world));
    my $exe = File::Spec->rel2abs('tmp/hello_world.exe');
    my $vcvarsall = $self->get_init($cl);
    my $compile =<<END
\@echo off
$vcvarsall
cd tmp
"$cl" /Ox /EHsc /nologo "$source" /Fe"$exe" 1>nul
cd ..
END
;
    my $compile_bat = write_file('compile.bat', $compile);
    system $compile_bat;
    $? >> 8 == 0 && `"$exe"` eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($in, $out, $err);
    IPC::Run::run [ $path ], \$in, \$out, \$err;
    if ($err =~ /Optimizing Compiler Version (\d+\.\d+\.\d+) for x86/) {
        return $1;
    }
    return 0;
}

sub get_init {
    my ($self, $path) = @_;
    my $vcvarsall_dir = File::Spec->rel2abs('../..', $path);
    my $res = File::Spec->catfile($vcvarsall_dir, 'vcvarsall.bat');
    return -e $res ? qq~call "$res"~ : '';
}

1;
