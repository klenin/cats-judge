package CATS::DevEnv::Detector::VStudioCL;
use File::Basename;

use parent qw(CATS::DevEnv::Detector::Base);
use File::Spec;
sub detect {
    my ($self) = @_;
    $self->{result} = {};
    CATS::DevEnv::Detector::Utils::env_path($self, 'cl');
    CATS::DevEnv::Detector::Utils::which($self, 'cl');
    CATS::DevEnv::Detector::Utils::registry_loop($self,
        'HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/VisualStudio',
        'ShellFolder',
        'VC/bin/',
        'cl'
    );
    return $self->{result};
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
    CATS::DevEnv::Detector::Utils::write_file('hello_world.cpp', $hello_world);
    my $vcvarsall = $self->get_init($cl);
    my $call_vcvarsall = $vcvarsall && "call \"$vcvarsall\"" || "";
    my $compile =<<END
\@echo off
$call_vcvarsall
"$cl" /Ox /EHsc /nologo hello_world.cpp /Fe"hello_world.exe"
END
;
    CATS::DevEnv::Detector::Utils::write_file('compile.bat', $compile);
    CATS::DevEnv::Detector::Utils::hello_world('compile.bat');
}

sub get_init {
    my ($self, $path) = @_;
    my $vcvarsall_dir = File::Spec->rel2abs("../..", $path);
    my $res = File::Spec->catfile($vcvarsall_dir, "vcvarsall.bat");
    return -e $res && $res || "";
}

1;
