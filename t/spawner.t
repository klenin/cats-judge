use strict;
use warnings;

use Test::More tests => 3;

use File::Spec;
use constant FS => 'File::Spec';
my $path;
BEGIN { $path = FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1]); }

use lib FS->catdir($path, '..', 'lib');
use lib FS->catdir($path, '..', 'lib', 'cats-problem');

use CATS::Spawner;
use CATS::SpawnerJson;
use CATS::Spawner::Platform;
use CATS::FileUtil;

my $fu = CATS::FileUtil->new;
my $perl = $fu->quote_fn($^X);
my $sp = FS->catdir($path, '..', CATS::Spawner::Platform::get_path);

ok -x $sp, 'exists';
ok `$sp` && $? == 0, 'runs';
ok `$sp $perl -v` && $? == 0, 'runs perl';

1;

