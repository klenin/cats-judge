package CATS::DevEnv::Detector::Delphi;

use strict;
use warnings;

use File::Spec;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Delphi' }
sub code { '203' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'dcc32');
    which($self, 'dcc32');
    registry_assoc($self, assoc => 'BDS.DprFile', file => 'dcc32');
    program_files($self, 'Embarcadero/RAD Studio/*/bin', 'dcc32');
    pbox($self, 'delphi7-compiler', 'bin', 'dcc32');
}

sub hello_world {
    my ($self, $dcc, $r) = @_;
    my $hello_world =<<'END'
begin
  write('Hello World')
end.
END
;
    my $source = write_temp_file('hello_world.pas', $hello_world);
    my $exe = temp_file('hello_world.exe');
    my $dcc_path = File::Spec->catdir((File::Spec->splitpath($dcc))[0, 1]);
    $r->{extra_paths}->{units} = $dcc_path;
    my ($ok, $err, $buf) = run command => [ $dcc, "-U$dcc_path", $source ];
    $ok or die $err;
    ($ok, $err, $buf) = run command => [ $exe ];
    $ok && $buf->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '--version' ];
    $ok or die $err;
    $buf->[0] =~ /Delphi.*\s([0-9\.]+)/ ? $1 : 0;
}

1;
