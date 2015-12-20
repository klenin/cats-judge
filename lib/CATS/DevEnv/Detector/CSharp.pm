package CATS::DevEnv::Detector::CSharp;

use strict;
use warnings;

use IPC::Cmd qw(run);

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub _detect {
    my ($self) = @_;
    env_path($self, 'csc');
    which($self, 'csc');
    program_files($self, 'MSBuild/*/Bin', 'csc');
}

sub hello_world {
    my ($self, $csc) = @_;
    my $hello_world =<<'END'
public class HelloWorld {
    public static void Main() {
        System.Console.Write("Hello World");
    }
}
END
;
    my $source = write_temp_file('hello_world.cs', $hello_world);
    my $exe = temp_file('hello_world.exe');
    run command => [ $csc, "/out:$exe", $source ] or return;
    my ($ok, undef, undef, $out, $err) = run command => [ $exe ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path,  '/help' ];
    $ok or return 0;
    $buf->[0] =~ /Visual C# Compiler version\s((?:\d+\.)+\d+)/ ? $1 : 0;
}

1;
