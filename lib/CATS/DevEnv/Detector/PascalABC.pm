package CATS::DevEnv::Detector::PascalABC;

use strict;
use warnings;

use IPC::Cmd qw(run);

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'PascalABC.NET' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'pabcnetcclear');
    which($self, 'pabcnetcclear');
    registry_assoc($self, 'PascalABCNET.PascalABCNETProject', '', 'pabcnetcclear');
    drives($self, 'PascalABC.NET', 'pabcnetcclear');
    program_files($self, 'PascalABC.NET', 'pabcnetcclear');
}

sub hello_world {
    my ($self, $fpc) = @_;
    my $hello_world =<<'END'
begin
  write('Hello World')
end.
END
;
    my $source = write_temp_file('hello_world.pas', $hello_world);
    my $exe = temp_file('hello_world.exe');
    my ($ok, $err, $buf) = run command => [ $fpc, $source ];
    $ok or die $err;
    ($ok, $err, $buf) = run command => [ $exe ];
    $ok && $buf->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path ];
    # PascalABC does not provide version info AND returns non-zero.
    $buf->[0] =~ /Command line is absent/ ? '1.0' : 0;
}

1;
