package CATS::DevEnv::Detector::Utils;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils::Common;
use if $^O eq 'MSWin32', 'CATS::DevEnv::Detector::Utils::Windows';
use if $^O ne 'MSWin32', 'CATS::DevEnv::Detector::Utils::WindowsStub';

use parent qw(Exporter);
our @EXPORT = qw(
    allow_methods
    clear
    debug_log
    drives
    env_path
    folder
    globq
    lang_dirs
    normalize_path
    pbox
    program_files
    registry
    registry_assoc
    registry_glob
    run
    set_debug
    temp_file
    TEMP_SUBDIR
    version_cmp
    which
    write_temp_file
);

sub set_debug {
    my ($debug, $stderr) = @_;
    $CATS::DevEnv::Detector::Utils::Common::debug = $debug;
    $CATS::DevEnv::Detector::Utils::Common::log = $stderr;
}

1;
