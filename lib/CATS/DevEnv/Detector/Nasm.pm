package CATS::DevEnv::Detector::Nasm;

use strict;
use warnings;


use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'Nasm' }
sub code { '130' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'nasm');
    which($self, 'nasm');
    drives($self, 'nasm', 'nasm');
    lang_dirs($self, 'nasm', '', 'nasm');
}

sub hello_world {
    my ($self, $nasm) = @_;

    # We need gcc for linker. Run gcc detector first since it will trash temporary dir.
    my $gcc = $self->{cache}->{GCC};
    if (!$gcc) {
        debug_log('Detecting GCC form Nasm...');
        require CATS::DevEnv::Detector::GCC;
        my $gcc_detector = CATS::DevEnv::Detector::GCC->new;
        ($gcc) = grep $_->{valid} && $_->{preferred}, values %{$gcc_detector->detect}
            or return;
    }

    my $hello_world =<<'END'
global  _main
    extern  _printf
    section .text
_main:
    push message
    call _printf
    add  esp, 4
    mov  eax, 0
    ret
message:
    db  'Hello World', 0
END
;
    my $source = write_temp_file('hello_world.asm', $hello_world);
    my $exe = temp_file('hello_world.exe');
    my $format = $^O eq 'MSWin32' ? 'win32' : 'elf32';
    {
        my ($ok, $err, $buf) = run command => [ $nasm, '-f', $format, $source ];
        $ok or return;
    }
    my $obj_file = temp_file('hello_world.' . ($^O eq 'MSWin32' ? 'obj' : 'o'));
    -f $obj_file or return;
    {
        my ($ok, $err, $buf) = run command => [ $gcc->{path}, $obj_file, '-o', $exe];
        $ok or return;
    }
    {
        my ($ok, $err, $buf) = run command => [ $exe ];
        $ok && $buf->[0] eq 'Hello World';
    }
}

sub get_version {
    my ($self, $path) = @_;
    my ($ok, $err, $buf) = run command => [ $path, '-v' ];
    $ok && $buf->[0] =~ /NASM version (\d{1,2}\.\d{1,2}\.\d{1,2})/ ? $1 : 0;
}

1;
