package CATS::DevEnv::Detector::Haskell;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Haskell' }
sub code { '503' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'ghc');
    which($self, 'ghc');
    program_files($self, 'Haskell Platform/*/bin', 'ghc');
    registry_glob($self, 'Haskell/Haskell Platform/*/InstallDir', 'bin', 'ghc');
}

sub hello_world {
    my ($self, $ghc) = @_;
    my $hello_world = <<'END'
main = putStr "Hello World"
END
;
    my $source = write_temp_file('hello_world.hs', $hello_world);
    my $exe = temp_file('hello_world.exe');
    run command => [ $ghc, '-o', $exe, $source ] or return;
    my ($ok, undef, undef, $out) = run command => [ $exe ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my $v = `"$path" --version`;
    $v =~ /^The Glorious Glasgow Haskell Compilation System, version ((?:\d+\.)+\d+)/ ? $1 : 0;
}

1;
