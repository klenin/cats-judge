use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::Exception;
use Test::More tests => 18;

use lib File::Spec->catdir($FindBin::Bin, '..', 'lib');
use lib File::Spec->catdir($FindBin::Bin, '..', 'lib', 'cats-problem');

use CATS::Judge::Config;

sub make_cfg { CATS::Judge::Config->new(root => File::Spec->catdir($FindBin::Bin, '..')) }

{
    my $c = make_cfg;
    is $c->apply_defines('abc'), 'abc', 'apply no defs';
    $c->{defines} = { x => 1, xy => 2, z => 'x' };
    is $c->apply_defines('abcxd'), 'abc1d', 'apply 1';
    is $c->apply_defines('xyxyzx'), '22x1', 'apply greedy';
}

my $default = q~<?xml version="1.0"?>
<judge
    name="test"
    sleep_time="1"
    report_file="r"
    stdout_file="o"
    stderr_file="e"
    formal_input_fname="f"
    cats_url="c"
    polygon_url="p"
    api="a"
    cachedir="d"
    logdir="d"
    modulesdir="d"
    solutionsdir="d"
    resultsdir="d"
    rundir="d"
    workdir="d"
>
~;
my $end = q~</judge>~;

{
    my $c = make_cfg;
    $c->load(src => "$default$end", override => { cats_url => 'rrr' });
    is $c->name, 'test', 'read';
    is $c->cats_url, 'rrr', 'override';
}

{
    my $c = make_cfg;
    $c->load(src => qq~$default<judge name="test1"/>$end~);
    is $c->name, 'test1', 'read override';
}

{
    my $c = make_cfg;
    throws_ok { $c->load(src => "$default<zzz/>$end") } qr/zzz/, 'unknown tag';
    throws_ok { $c->load(src => qq~$default<checker name="qqq"/>$end~) }
        qr/qqq.*exec/, 'checker no exec';
    throws_ok { $c->load(src => qq~$default<define/>$end~) }
        qr/define.*name/, 'define no name';
    throws_ok { $c->load(src => qq~$default<define name="ttt"/>$end~) }
        qr/ttt.*value/, 'define no value';
    throws_ok { $c->load(src => qq~$default<de/>$end~) }
        qr/de.*code/, 'de no code';
    throws_ok { $c->load(src => qq~$default
        <de code="111" extension="xx"/>
        <de code="222" extension="xx"/>
        $end
    ~) }
        qr/duplicate.*xx.*111.*222/, 'duplicate extension';
}

{
    my $c = make_cfg;
    (my $no_name = $default) =~ s/name=/name1=/;
    throws_ok { $c->load(src => "$no_name$end") } qr/name/, 'no required';
}

{
    my $c = make_cfg;
    $c->load(src => qq~$default<define name="#xx" value="2"/><judge name="test#xx"/>$end~);
    is $c->name, 'test2', 'define';
}

{
    my $c = make_cfg;
    throws_ok { $c->load(src => qq~$default<include />$end~) } qr/file/, 'include no file';
    throws_ok { $c->load(src => qq~$default<include file="qqq"/>$end~) } qr/qqq/, 'include bad file';
    $c->load(src => qq~$default
      <judge name="zzz"/>
      <de code="111" compile="zzz" run="qqq" />
      <include file="t/cfg_include.xml" />
      <de code="111" check="zzz#inc 1" />
      $end~);
    is $c->name, 'included', 'include name';
    is_deeply $c->DEs->{111}, {
        compile => 'bbb', run => 'qqq', check => 'zzzabc 1' }, 'include de';
}
