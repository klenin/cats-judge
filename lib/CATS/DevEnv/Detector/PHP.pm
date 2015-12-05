package CATS::DevEnv::Detector::PHP;

use parent qw(CATS::DevEnv::Detector::Base);

sub detect {
    my ($self) = @_;
    $self->{result} = {};
    CATS::DevEnv::Detector::Utils::env_path($self, 'php');
    CATS::DevEnv::Detector::Utils::which($self, 'php');
    CATS::DevEnv::Detector::Utils::drives($self, 'php', 'php');
    CATS::DevEnv::Detector::Utils::folder($self, '/usr/bin/', 'php');
    return $self->{result};
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
