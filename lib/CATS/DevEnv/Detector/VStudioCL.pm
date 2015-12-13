package CATS::DevEnv::Detector::VStudioCL;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);
use File::Spec;

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
    my $hello_world =<<"END"
#include <iostream>
using namespace std;
int main() {
    cout << "Hello World";
}
END
;
    my $source = File::Spec->rel2abs(write_file('hello_world.cpp', $hello_world));
    my $exe = File::Spec->rel2abs("tmp/hello_world.exe");
    my $vcvarsall = $self->get_init($cl);
    my $compile =<<END
\@echo off
$vcvarsall
"$cl" /Ox /EHsc /nologo "$source" /Fe"$exe"
END
;
    my $compile_bat = write_fie('compile.bat', $compile);
    system $compile_bat;
    $? >> 8 == 0 && `"$exe"` eq "Hello World";
}

sub get_init {
    my ($self, $path) = @_;
    my $vcvarsall_dir = File::Spec->rel2abs("../..", $path);
    my $res = File::Spec->catfile($vcvarsall_dir, "vcvarsall.bat");
    return -e $res && "call \"$res\"" || "";
}

1;
