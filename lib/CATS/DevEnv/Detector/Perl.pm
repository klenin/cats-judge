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

sub hello_world {
    my ($self, $perl) = @_;
    return `"$perl" -e "print 'Hello world'"` eq "Hello world";
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" -v` =~ /This is perl \d+, version \d+, subversion 3 \(v([\d.?]+)\)/) {
        return $1;
    }
    return "";
}

1;
