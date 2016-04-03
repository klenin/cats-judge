package CATS::DevEnv::Detector::Utils;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils::Common;
use if $^O eq 'MSWin32', 'CATS::DevEnv::Detector::Utils::Windows';
use if $^O ne 'MSWin32', 'CATS::DevEnv::Detector::Utils::WindowsStub';

use parent qw(Exporter);
our @EXPORT = qw(
    TEMP_SUBDIR temp_file write_temp_file version_cmp clear normalize_path globq
    which env_path folder debug_log
    registry registry_assoc registry_glob program_files drives lang_dirs
);

1;
