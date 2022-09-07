package CATS::DevEnv::Detector::R;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'R' }
sub code { '511' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'R');
    which($self, 'R');
    registry_glob($self, 'R-core/R/*/InstallPath', 'bin', 'R');
    drives($self, 'R/bin', 'R');
    lang_dirs($self, 'R', 'bin', 'R');
    folder($self, '/usr/bin/', 'R');
}

sub hello_world {
    my ($self, $R) = @_;
    return `"$R" --slave --vanilla -e "cat('Hello world')"` eq 'Hello world';
}

sub get_version {
    my ($self, $path) = @_;

    my ($ok, $err, $buf) = run command => [ $path, '--version', '-q' ];
    $ok or return 0;
    $buf->[0] =~ /R version ([\d.?]+)/ ? $1 : 0;
}

1;
