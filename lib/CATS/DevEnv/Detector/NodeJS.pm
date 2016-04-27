package CATS::DevEnv::Detector::NodeJS;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'NodeJS' }
sub code { '507' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'node');
    which($self, 'node');
    program_files($self, 'nodejs', 'node');
    drives($self, 'Node', 'node');
    drives($self, 'NodeJS', 'node');
    lang_dirs($self, 'node', '', 'perl');
}

sub hello_world {
    my ($self, $nodejs) = @_;
    # Should be process.stdout.write('Hello World').
    # However, nodejs crashes while trying to create pipe wrapper for redirected stdout.
    my $out_name = temp_file('output.txt');
    (my $out_name_quoted = $out_name) =~ s'\\'\\\\'g;
    my $source = write_temp_file('test.js',
        "require('fs').writeFile('$out_name_quoted', 'Hello World', function() {})");
    run command => [ $nodejs, $source ] or return;
    open my $outf, '<', $out_name or return;
    <$outf> eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path,  '-v' ];
    $ok && $buf->[0] =~ /v((?:[0-9_]+\.)+[0-9_]+)/ ? $1 : 0;
}

1;
