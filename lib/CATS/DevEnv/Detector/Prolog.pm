package CATS::DevEnv::Detector::Prolog;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Prolog' }
sub code { '509' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'swipl');
    which($self, 'swipl');
    drives($self, 'swipl', 'bin', 'swipl');
    lang_dirs($self, 'swipl', 'bin', 'swipl');
    folder($self, '/usr/bin/', 'swipl');
    registry_glob($self, 'SWI/Prolog/home', 'bin', 'swipl');
}

sub hello_world {
    my ($self, $swipl) = @_;

    my $hello_world = <<'END'
main :- write("Hello World"), halt.
END
;
    my $source = write_temp_file('hello_world.pro', $hello_world);
    `"$swipl" -g main -l "$source"` eq "Hello World";
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '--version' ];
    $ok && $buf->[0] =~/SWI-Prolog\sversion\s(\d+(?:\.\d+)+)/ ? $1 : 0;
}

1;
