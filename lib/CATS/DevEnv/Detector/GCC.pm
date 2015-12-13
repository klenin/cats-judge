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

sub hello_world {
    my ($self, $gcc) = @_;
    my $hello_world =<<"END"
#include <stdio.h>
int main() {
    printf("Hello World");
}
END
;
    my $source = write_file('hello_world.c', $hello_world);
    my $exe = File::Spec->rel2abs("tmp/hello_world.exe");
    my $compile = "\"$gcc\" -o $exe $source";
    system $compile;
    return $? >> 8 || `$exe` ne "Hello World";
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" --version` =~ /.*?\) (\d{1,2}\.\d{1,2}\.\d{1,2})/) {
        return $1;
    }
    return 0;
}



1;
