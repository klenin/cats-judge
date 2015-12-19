package CATS::DevEnv::Detector::FPC;

use IPC::Cmd qw(can_run run);

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub _detect {
    my ($self) = @_;
    env_path($self, 'fpc');
    which($self, 'fpc');
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
    my $source = File::Spec->rel2abs(write_file('hello_world.pp', $hello_world));
    my $exe = File::Spec->rel2abs('tmp/hello_world.exe');
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
