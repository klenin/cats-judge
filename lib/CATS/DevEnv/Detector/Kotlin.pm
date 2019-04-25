package CATS::DevEnv::Detector::Kotlin;

use strict;
use warnings;

use File::Spec;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Kotlin' }
sub code { '406' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'kotlinc');
    which($self, 'kotlinc');
    pbox($self, 'kotlin', 'bin', 'kotlinc');
}

sub hello_world {
    my ($self, $kotlinc, $r) = @_;
    my $hello_world =<<'END'
fun main(args: Array<String>) {
    print("Hello World")
}
END
;
    my $source = write_temp_file('HelloWorld.kt', $hello_world);
    my $jar = File::Spec->catfile(TEMP_SUBDIR, 'result.jar');
    run command => [ $kotlinc, $source, '-include-runtime', '-d', $jar ] or return;
    my $kotlin = $kotlinc;
    $kotlin =~ s/kotlinc/kotlin/;
    {
        my ($drive, $path, $file) = File::Spec->splitpath($kotlinc);
        my @parts = File::Spec->splitdir($path);
        $r->{extra_paths}->{path} = File::Spec->catdir($drive, @parts[0 .. $#parts - 2]);
    }
    my ($ok, undef, undef, $out, $err) = run command => [ $kotlin, $jar ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path,  '-version' ];
    $ok && $buf->[0] =~ /kotlinc-\w+\s((?:[0-9_]+\.)+[0-9_]+)/ ? $1 : 0;
}

1;
