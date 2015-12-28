package CATS::DevEnv::Detector::FPC;

use strict;
use warnings;

use IPC::Cmd qw(run);

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Free Pascal' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'fpc');
    which($self, 'fpc');
    registry_assoc($self, assoc => 'Lazarus.AssocFile.lpr', local_path => '/fpc/*/bin/i386-win32', file => 'fpc');
    drives($self, 'lazarus/fpc/*/bin/i386-win32', 'fpc');
    pattern($self, 'FPC/*/bin/*/{fpc,fpc.*,ppc*}');
}

sub hello_world {
    my ($self, $fpc) = @_;
    my $hello_world =<<'END'
begin
  write('Hello World')
end.
END
;
    my $source = write_temp_file('hello_world.pp', $hello_world);
    my $exe = temp_file('hello_world.exe');
    my ($ok, $err, $buf) = run command => [ $fpc, $source ];
    $ok or die $err;
    ($ok, $err, $buf) = run command => [ $exe ];
    $ok && $buf->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '-i' ];
    $ok or die $err;
    if ($buf->[0] =~ /Free Pascal Compiler version (\d{1,2}\.\d{1,2}\.\d{1,2})/) {
        return $1;
    }
    return 0;
}

1;
