package CATS::DevEnv::Detector::PHP;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'PHP' }
sub code { '505' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'php');
    which($self, 'php');
    drives($self, 'php*', 'php');
    lang_dirs($self, 'php*', '', 'php');
    folder($self, '/usr/bin/', 'php');
    pbox($self, 'php', '', 'php');
}

sub hello_world {
    my ($self, $php) = @_;
    my ($ok, $err, $buf, $out) = run command => [ $php, '-r', q~print "Hello world";~ ];
    $ok && $out->[0] eq 'Hello world';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path,  '-v' ];
    $ok && $buf->[0] =~ /PHP (\d{1,2}\.\d{1,2}\.\d{1,2}).*/ ? $1 : 0;
}

1;
