package CATS::DevEnv::Detector::Utils::WindowsStub;

use strict;
use warnings;

use parent qw(Exporter);

{
    no strict 'refs';
    my $symbols = \%{__PACKAGE__ . '::'};
    our @EXPORT = grep *{$symbols->{$_}}{CODE}, keys %$symbols;
}

sub add_to_path {}
sub detect_proxy { '' }
sub disable_error_dialogs {}
sub disable_windows_error_reporting_ui {}
sub drives {}
sub lang_dirs {}
sub pbox {}
sub program_files {}
sub registry {}
sub registry_assoc {}
sub registry_glob {}

1;
