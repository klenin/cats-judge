package CATS::DevEnv::Detector::Perl;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Perl' }
sub code { '501' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'perl');
    which($self, 'perl');
    registry_assoc($self, assoc => 'Perl_program_file', command => 'Execute Perl Program', file => 'perl');
    drives($self, 'perl/bin', 'perl');
    drives($self, 'perl/perl/bin', 'perl');
    drives($self, 'strawberry/perl/bin', 'perl');
    lang_dirs($self, 'perl', 'perl/bin', 'perl');
    folder($self, '/usr/bin/', 'perl');
}

sub hello_world {
    my ($self, $perl) = @_;
    return `"$perl" -e "print 'Hello world'"` eq 'Hello world';
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" -v` =~ /This is perl \d+, version \d+, subversion \d+ \(v([\d.?]+)\)/) {
        return $1;
    }
    return 0;
}

1;
