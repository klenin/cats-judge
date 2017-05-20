use strict;
use warnings;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use Test::More tests => 4;
use CATS::Spawner::Const ':all';

ok -x $sp, 'sp exists' or BAIL_OUT('sp does not exist');
ok `$sp` && $? == 0, 'runs'or BAIL_OUT('sp does not run');
ok `$sp $perl -v` && $? == 0, 'runs perl' or BAIL_OUT('sp does not run perl');
ok -x $gcc, 'gcc exists' or BAIL_OUT('gcc does not exist');
