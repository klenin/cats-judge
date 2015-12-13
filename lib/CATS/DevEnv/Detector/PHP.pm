package CATS::DevEnv::Detector::PHP;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub _detect {
    my ($self) = @_;
    env_path($self, 'php');
    which($self, 'php');
    drives($self, 'php', 'php');
    folder($self, '/usr/bin/', 'php');
}

sub validate {
    my ($self, $php) = @_;
    $self->SUPER::validate($php)
        && $self->get_version($php)
        && `"$php" -r "print 'Hello world';"` eq "Hello world"
        or return 0;
    ;
    return 1;
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" -v` =~ /PHP (\d{1,2}\.\d{1,2}\.\d{1,2}).*/) {
        return $1;
    }
    return "";
}

1;
