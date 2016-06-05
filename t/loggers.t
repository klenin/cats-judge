use strict;
use warnings;

use Test::More tests => 4;
use Test::Exception;

use File::Spec;
use constant FS => 'File::Spec';
my $path;
BEGIN { $path = FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1]); }

use lib FS->catdir($path, '..', 'lib');

use CATS::Loggers;

{
    my $d = CATS::Logger::Die->new;
    throws_ok { $d->msg(1, 2) } qr/12/, 'Logger::Die';
}

{
    my $c = CATS::Logger::Count->new;
    is $c->count, 0, 'count 0';
    ok !defined $c->msg('asfsdf'), 'msg returns undef';
    is $c->count, 1, 'count 1';
}
