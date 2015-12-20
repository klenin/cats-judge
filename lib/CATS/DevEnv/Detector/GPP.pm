package CATS::DevEnv::Detector::GPP;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub _detect {
    my ($self) = @_;
    env_path($self, 'g++');
    which($self, 'g++');
    drives($self, 'MinGW/bin/', 'g++');
    drives($self, 'cygwin/bin/', 'g++');
    program_files($self, 'MinGW/bin/', 'g++');
    program_files($self, 'cygwin/bin/', 'g++');
}

sub hello_world {
    my ($self, $gcc) = @_;
    my $hello_world =<<"END"
#include <iostream>
int main() {
    std::cout<<"Hello World";
}
END
;
    my $source = File::Spec->rel2abs(write_file('hello_world.cpp', $hello_world));
    my $exe = File::Spec->rel2abs('tmp/hello_world.exe');
    my $compile = qq~"$gcc" -o "$exe" "$source"~;
    system $compile;
    $? >> 8 == 0 && `"$exe"` eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my $v = `"$path" --version`;
    if ($v =~ /[gG]\+\+.+\s((?:\d+\.)+\d+)/) {
        return $1;
    }
    return 0;
}

1;
