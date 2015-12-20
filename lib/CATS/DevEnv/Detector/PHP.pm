package CATS::DevEnv::Detector::PHP;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub _detect {
    my ($self) = @_;
    env_path($self, 'php');
    which($self, 'php');
    drives($self, 'php', 'php');
    drives($self, 'php5', 'php');
    drives($self, 'lang/php/*', 'php');
    folder($self, '/usr/bin/', 'php');
}

sub hello_world {
    my ($self, $php) = @_;
    return `"$php" -r "print 'Hello world';"` eq 'Hello world';
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" -v` =~ /PHP (\d{1,2}\.\d{1,2}\.\d{1,2}).*/) {
        return $1;
    }
    return 0;
}

1;
