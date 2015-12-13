package CATS::DevEnv::Detector::VStudioCL;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);
use File::Spec;

sub _detect {
    my ($self) = @_;
    env_path($self, 'cl');
    which($self, 'cl');
    registry_loop($self,
        'HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/VisualStudio',
        'ShellFolder',
        'VC/bin/',
        'cl'
    );
}

sub validate {
    my ($self, $cl) = @_;
    $self->SUPER::validate($cl) or return 0;
    my $hello_world =<<"END"
#include <iostream>
using namespace std;
int main() {
    cout << "Hello World";
}
END
;
    write_file('hello_world.cpp', $hello_world);
    my $vcvarsall = $self->get_init($cl);
    my $compile =<<END
\@echo off
$vcvarsall
"$cl" /Ox /EHsc /nologo hello_world.cpp /Fe"hello_world.exe"
END
;
    write_file('compile.bat', $compile);
    hello_world('compile.bat');
}

sub get_init {
    my ($self, $path) = @_;
    my $vcvarsall_dir = File::Spec->rel2abs("../..", $path);
    my $res = File::Spec->catfile($vcvarsall_dir, "vcvarsall.bat");
    return -e $res && "call \"$res\"" || "";
}

1;
