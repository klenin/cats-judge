package CATS::DevEnv::Detector::VBasic;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Visual Basic' }
sub code { '303' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'vbc');
    which($self, 'vbc');
    program_files($self, 'MSBuild/*/Bin', 'vbc');
    registry($self,
        'Microsoft/NET Framework Setup/NDP/v4/Full', 'InstallPath', '', 'vbc');
    registry_glob($self,
        'Microsoft/NET Framework Setup/NDP/*/InstallPath', '', 'vbc');
}

sub hello_world {
    my ($self, $csc) = @_;
    my $hello_world =<<'END'
Module Hello
Sub Main
    Console.Write("Hello World")
End Sub
End Module
END
;
    my $source = write_temp_file('hello_world.bas', $hello_world);
    my $exe = temp_file('hello_world.exe');
    run command => [ $csc, "/out:$exe", $source ] or return;
    my ($ok, undef, undef, $out, $err) = run command => [ $exe ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path,  '/help' ];
    $ok or return 0;
    $buf->[0] =~ /Visual Basic.+\s((?:\d+\.)+\d+)/ ? $1 : 0;
}

1;
