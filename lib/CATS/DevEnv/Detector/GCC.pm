package CATS::DevEnv::Detector::GCC;

use parent qw(CATS::DevEnv::Detector::Base);

sub detect {
    my ($self) = @_;
    $self->{result} = {};
    CATS::DevEnv::Detector::Utils::env_path($self, 'gcc');
    CATS::DevEnv::Detector::Utils::which($self, 'gcc');
    CATS::DevEnv::Detector::Utils::drives($self, 'MinGW/bin/', 'gcc');
    CATS::DevEnv::Detector::Utils::drives($self, 'cygwin/bin/', 'gcc');
    CATS::DevEnv::Detector::Utils::program_files($self, 'MinGW/bin/', 'gcc');
    CATS::DevEnv::Detector::Utils::program_files($self, 'cygwin/bin/', 'gcc');
    return $self->{result};
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
    CATS::DevEnv::Detector::Utils::write_file('hello_world.c', $hello_world);
    my $compile = "\"$gcc\" -o hello_world.exe hello_world.c";
    CATS::DevEnv::Detector::Utils::hello_world($compile);
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" --version` =~ /.*?\) (\d{1,2}\.\d{1,2}\.\d{1,2})/) {
        return $1;
    }
    return "";
}



1;
