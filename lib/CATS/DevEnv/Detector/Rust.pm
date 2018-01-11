package CATS::DevEnv::Detector::Rust;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Rust' }
sub code { '120' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'rustc');
    which($self, 'rustc');
    lang_dirs($self, 'rust', 'bin', 'rustc');
    registry_glob($self, 'The Rust Project Developers/*/*/InstallDir', 'bin', 'rustc');
    pbox($self, 'rust', 'bin', 'rustc');
}

sub hello_world {
    my ($self, $rustc) = @_;
    my $hello_world = <<'END'
fn main() {
    print!("Hello World");
}
END
;
    my $source = write_temp_file('hello_world.rs', $hello_world);
    my $exe = temp_file('hello_world.exe');
    run command => [ $rustc, '-o', $exe, $source ] or return;
    my ($ok, undef, undef, $out) = run command => [ $exe ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, undef, undef, $out) = run command => [ $path, '--version' ];
    $ok && $out->[0] =~ /^rustc\s((?:\d+\.)+\d+)/ ? $1 : 0;
}

1;
