package CATS::DevEnv::Detector::CSharpDotnet;

use strict;
use warnings;

use File::Spec;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Dotnet SDK C#' }
sub code { '407' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'dotnet');
    which($self, 'dotnet');
    program_files($self, 'dotnet/SDK/*', 'dotnet');
    pbox($self, 'dotnet-core-sdk', '', 'dotnet');
    lang_dirs($self, 'dotnet', '', 'dotnet');
}

sub hello_world {
    my ($self, $dotnet, $opts) = @_;

    my $version = $opts->{version};
    $version =~ s/^(\d+\.\d).*/$1/ or die $version;

    my $hello_world = q~System.Console.Write("Hello World");~;
    my $csproj_text = qq~
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net$version</TargetFramework>
  </PropertyGroup>
</Project>~;

    my $project = write_temp_file('hello_world.csproj', $csproj_text);
    my $source = write_temp_file('hello_world.cs', $hello_world);
    my $exe = temp_file(File::Spec->catfile('build', 'hello_world.exe'));
    my $build = temp_file('build');
    run command => [ $dotnet, qw(publish -o), $build, $project ]  or return;
    my ($ok, undef, undef, $out, $err) = run command => [ $exe ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '--info' ];
    $ok or return 0;
    /^\s*Version:\s*((?:\d+\.)+\d+)/m and return $1 for @$buf;
    0;
}

1;
