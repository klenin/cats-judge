package CATS::DevEnv::Detector::GPP;

use IPC::Cmd qw(run);

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
    my $hello_world = <<'END'
#include <iostream>
int main() {
    std::cout<<"Hello World";
}
END
;
    my $source = write_temp_file('hello_world.cpp', $hello_world);
    my $exe = temp_file('hello_world.exe');
    run command => [ $gcc, '-o', $exe, $source ] or return;
    my ($ok, undef, undef, my $out) = run command => [ $exe ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my $v = `"$path" --version`;
    $v =~ /[gG]\+\+.+\s((?:\d+\.)+\d+)/ ? $1 : 0;
}

1;
