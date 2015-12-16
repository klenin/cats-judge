package CATS::DevEnv::Detector::FPC;

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
    my $hello_world =<<"END"
program Hello;
begin
  writeln ('Hello World')
end.
END
;
    my $source = File::Spec->rel2abs(write_file('hello_world.pp', $hello_world));
    my $exe = File::Spec->rel2abs("tmp/hello_world.exe");
    my $compile = "\"$fpc\" \"$source\" -o\"$exe\"";
    system $compile;
    $? >> 8 == 0 && `"$exe"` eq "Hello World\n";
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" -h` =~ /Free Pascal Compiler version (\d{1,2}\.\d{1,2}\.\d{1,2}) .*/) {
        return $1;
    }
    return 0;
}



1;
