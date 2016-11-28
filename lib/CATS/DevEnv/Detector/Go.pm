package CATS::DevEnv::Detector::Go;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Go' }
sub code { '90' }

sub _detect {
    my ($self) = @_;
    env_path($self, "$ENV{'GOROOT'}/bin/go");
}

sub hello_world {
    my ($self, $go) = @_;
    my $hello_world =<<'END'
package main

import "fmt"

func main() {
    fmt.Print(`Hello World`)
}
END
;
    my $source = write_temp_file('hello_world.go', $hello_world);
    my ($ok, $err, $buf) = run command => [ $go, 'run', $source ];
    $ok && $buf->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, 'version' ];
    $ok && $buf->[0] =~ /go version go(\d{1,2}\.\d{1,2}\.\d{1,2})/ ? $1 : 0;
}

1;
