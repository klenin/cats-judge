package CATS::DevEnv::Detector::Perl;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub _detect {
    my ($self) = @_;
    env_path($self, 'perl');
    which($self, 'perl');
    drives($self, 'perl/bin', 'perl');
    drives($self, 'strawberry/perl/bin', 'perl');
    folder($self, '/usr/bin/', 'perl');
}

sub validate {
    my ($self, $perl) = @_;
    $self->SUPER::validate($perl)
        && $self->get_version($perl)
        && `"$perl" -e "print 'Hello world'"` eq "Hello world"
        or return 0;
    ;
    return 1;
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" -v` =~ /This is perl \d+, version \d+, subversion 3 \(v([\d.?]+)\)/) {
        return $1;
    }
    return "";
}

1;
