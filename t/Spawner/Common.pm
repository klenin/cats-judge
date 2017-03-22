package Common;

use strict;
use warnings;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

my $root;
BEGIN { $root = FS->catdir($Bin, '..', '..'); };

use lib FS->catdir($root, 'lib');
use lib FS->catdir($root, 'lib', 'cats-problem');

use CATS::Spawner::Builtin;
use CATS::Spawner::Default;
use CATS::Spawner::Platform;
use CATS::Spawner::Program;
use CATS::FileUtil;
use CATS::Loggers;
use CATS::Judge::Config;

use Exporter qw(import);
our @EXPORT = qw($tmpdir $fu $perl $sp $cfg);

our $tmpdir;
BEGIN {
    $tmpdir = FS->catdir($Bin, '..', 'tmp');
     -d $tmpdir or mkdir $tmpdir or die 'Unable to create temporary directory';
}
END { -d $tmpdir and rmdir $tmpdir }

our $cfg = CATS::Judge::Config->new;
our $fu = CATS::FileUtil->new;
our $perl = $fu->quote_fn($^X);
our $sp = FS->catdir($root, CATS::Spawner::Platform::get_path);

my $judge_cfg = FS->catdir($root, 'config.xml');
open my $cfg_file, '<', $judge_cfg or die "Couldn't open $judge_cfg";
$cfg->read_file($cfg_file, {});

1;
