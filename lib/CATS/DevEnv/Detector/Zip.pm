package CATS::DevEnv::Detector::Zip;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Zip' }
sub code { '2' }

# Just 7-Zip for now.
sub _detect {
    my ($self) = @_;
    env_path($self, '7z');
    which($self, '7z');
    registry_glob($self, '7-Zip/Path64', '', '7z');
    registry_glob($self, '7-Zip/Path', '', '7z');
    drives($self, '7-Zip', '7z');
    program_files($self, '7-Zip', '7z');
    pbox($self, '7zip', '', '7z');
}

sub hello_world {
    my ($self, $zip) = @_;
    my $source = write_temp_file('hello_world.txt', 'Hello World');
    my $archive = temp_file('hello_world.7z');
    run command => [ $zip, 'a', $archive, $source ] or return;
    my ($ok, undef, undef, $out) = run command => [ $zip, 'x', '-so', $archive ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, undef, undef, $out) = run command => [ $path ];
    $ok && $out->[0] =~ /7-Zip.+\s((?:\d+\.)+\d+)/ ? $1 : 0;
}

1;
