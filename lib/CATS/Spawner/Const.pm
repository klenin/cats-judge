package CATS::Spawner::Const;

use base qw(Exporter);

my $c = [qw(
    $TR_OK
    $TR_TIME_LIMIT
    $TR_MEMORY_LIMIT
    $TR_WRITE_LIMIT
    $TR_IDLENESS_LIMIT
    $TR_ABORT
    $TR_CONTROLLER
    $TR_SECURITY
)];

eval 'our (' . join(',', @$c) . ') = 1..' . @$c;

our @EXPORT_OK = @$c;
our %EXPORT_TAGS = (all => $c);

1;
