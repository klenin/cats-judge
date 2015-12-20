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
    my $source = write_temp_file('hello_world.c', $hello_world);
    my $exe = temp_file('hello_world.exe');
    my $compile = qq~"$gcc" -o "$exe" "$source"~;
    system $compile;
    $? >> 8 == 0 && `"$exe"` eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my $v = `"$path" --version`;
    if ($v =~ /(?:gcc|GCC).+\s((?:\d+\.)+\d+)/) {
        return $1;
    }
    return 0;
}

1;
