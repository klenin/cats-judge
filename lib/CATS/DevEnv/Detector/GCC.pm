package CATS::DevEnv::Detector::GCC;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub _detect {
    my ($self) = @_;
    env_path($self, 'gcc');
    which($self, 'gcc');
    drives($self, 'MinGW/bin/', 'gcc');
    drives($self, 'cygwin/bin/', 'gcc');
    program_files($self, 'MinGW/bin/', 'gcc');
    program_files($self, 'cygwin/bin/', 'gcc');
}

sub validate {
    my ($self, $gcc) = @_;
    $self->SUPER::validate($gcc)
        && $self->get_version($gcc)
        or return 0;
    ;
    my $hello_world =<<"END"
#include <stdio.h>
int main() {
    printf("Hello World");
}
END
;
    write_file('hello_world.c', $hello_world);
    my $compile = "\"$gcc\" -o hello_world.exe hello_world.c";
    hello_world($compile);
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" --version` =~ /.*?\) (\d{1,2}\.\d{1,2}\.\d{1,2})/) {
        return $1;
    }
    return "";
}



1;
