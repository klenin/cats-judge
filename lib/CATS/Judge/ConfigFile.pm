package CATS::Judge::ConfigFile;

use strict;
use warnings;

use File::Spec;

use parent qw(Exporter);
our @EXPORT_OK = qw(cfg_file);

sub cfg_file { File::Spec->catfile('config', $_[0]) }

our $main = cfg_file('main.xml');

1;
