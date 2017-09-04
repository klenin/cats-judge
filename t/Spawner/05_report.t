use strict;
use warnings;

use FindBin qw($Bin);
use File::Spec;
use Test::Exception;
use Test::More tests => 26;

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use CATS::Spawner;

BEGIN {
    no strict 'refs';
    *ci = *CATS::Spawner::Report::check_item;
    *$_ = *{"CATS::Spawner::Report::$_"} for qw(ANY INT STR FLOAT OPT);
}

throws_ok { ci('', OPT * 2, '') } qr/Bad schema/, 'bad schema';

ok ci('zzz', ANY, ''), 'ANY';

ok ci(123, INT, ''), 'INT';
throws_ok { ci('abc', INT, 'int1') } qr/int1/, 'bad INT 1';
throws_ok { ci('1.2', INT, 'int2') } qr/int2/, 'bad INT 2';

ok ci('55', FLOAT, ''), 'FLOAT 1';
ok ci('5.5', FLOAT, ''), 'FLOAT 2';
ok ci('5e9', FLOAT, ''), 'FLOAT exp 1';
ok ci('2.2e-005', FLOAT, ''), 'FLOAT exp 2';
throws_ok { ci('5.x', FLOAT, 'float1') } qr/float1/, 'bad FLOAT 1';
throws_ok { ci('5e', FLOAT, 'float2') } qr/float2/, 'bad FLOAT 2';

ok ci('abc', STR, ''), 'STR';

ok ci(undef, STR | OPT, ''), 'OPT';
throws_ok { ci(undef, STR, 'undef1') } qr/undef1/, 'not OPT';

ok ci([ 1, 2, 3], [ INT ], ''), 'array of INT';
throws_ok { ci(123, [ INT ], 'array1') } qr/array1/, 'bad array of INT 1';
throws_ok { ci([ 1, 'a' ], [ INT ], 'array2') } qr/array2#1/, 'bad array of INT 2';
throws_ok { ci({}, [ INT ], 'array3') } qr/HASH.+ARRAY.+array3/, 'bad array of INT 3';

{
my $h = { x => INT, y => FLOAT };
ok ci({ x => 5, y => 6.7 }, $h, ''), 'hash';
throws_ok { ci([], $h, 'hash1') } qr/hash1/, 'bad hash 1';
throws_ok { ci({ x => 5 }, $h, 'hash1') } qr~hash1/y~, 'bad hash 2';
throws_ok { ci({ x => 5, z => '' }, $h, 'hash3') } qr~hash3/z~, 'bad hash 3';
throws_ok { ci({ x => 'abc', y => 5 }, $h, 'hash4') } qr~hash4/x~, 'bad hash 4';
throws_ok { ci([], $h, 'hash5') } qr~ARRAY.+HASH.+hash5~, 'bad hash 5';
}

{
my $s = { x => [ { y => INT} ] };
ok ci({ x => [ { y => 1 }, { y => 2 } ] }, $s, ''), 'nested';
throws_ok { ci({ x => [ { y => 1 }, { y => {} } ] }, $s, 'nested1') } qr~nested1/x#1/y~, 'bad nested 1';
}
