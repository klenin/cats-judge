package CATS::DevEnv::Detector::Python2;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub _detect {
    my ($self) = @_;
    env_path($self, 'python');
    which($self, 'python');
    drives($self, 'python', 'python');
    folder($self, '/usr/bin/', 'python');
    registry_loop($self,
        'Python/PythonCore',
        'InstallPath',
        '',
        'python'
    );
}

sub hello_world {
    my ($self, $python) = @_;
    return `"$python" -c "print 'Hello world'"` eq "Hello world\n";
}

sub get_version {
    my ($self, $path) = @_;
    if (`"$path" --version` =~ /Python (\d{1,2}\.\d{1,2}\.\d{1,2})/) {
        return $1;
    }
    return 0;
}

1;
