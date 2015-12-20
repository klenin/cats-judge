package CATS::DevEnv::Detector::Java;

use strict;
use warnings;

use IPC::Cmd qw(run);

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Java' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'javac');
    which($self, 'javac');
    registry_glob($self,
        'JavaSoft/Java Development Kit/*/JavaHome', 'bin', 'javac');
    program_files($self, 'Java/jdk*/bin', 'javac');
}

sub hello_world {
    my ($self, $javac) = @_;
    my $hello_world =<<'END'
class HelloWorld {
    public static void main(String[] args) {
        System.out.print("Hello World");
    }
}
END
;
    my $source = write_temp_file('HelloWorld.java', $hello_world);
    run command => [ $javac, $source ] or return;
    my $java = $javac;
    $java =~ s/javac/java/;
    my ($ok, undef, undef, $out, $err) =
        run command => [ $java, '-cp', TEMP_SUBDIR, 'HelloWorld' ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path,  '-version' ];
    $ok or return 0;
    $buf->[0] =~ /javac\s((?:[0-9_]+\.)+[0-9_]+)/ ? $1 : 0;
}

1;
