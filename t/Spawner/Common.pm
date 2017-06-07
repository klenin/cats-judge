package Common;

use strict;
use warnings;

use Exporter qw(import);
use File::Spec;
use FindBin qw($Bin);
use Test::More;

use constant FS => 'File::Spec';
use constant MB => 1024 * 1024;

my $root;
BEGIN { $root = FS->catdir($Bin, '..', '..'); };

use lib FS->catdir($root, 'lib');
use lib FS->catdir($root, 'lib', 'cats-problem');

use CATS::FileUtil;
use CATS::Judge::Config;
use CATS::Loggers;
use CATS::Spawner::Builtin;
use CATS::Spawner::Const ':all';
use CATS::Spawner::Default;
use CATS::Spawner::Platform;
use CATS::Spawner::Program;

our @EXPORT = qw(
    $cfg
    $exe
    $fu
    $gcc
    $is_win
    $perl
    $sp
    $spr
    $tmpdir
    @gcc_opts
    MB
    clear_tmpdir
    compile
    compile_plan
    items_ok
    items_ok_plan
    make_test_file
    program
    run_sp
    run_sp_multiple
    run_subtest
    tmp_name
);

our $tmpdir;
BEGIN {
    $tmpdir = FS->catdir($Bin, '..', 'tmp');
     -d $tmpdir or mkdir $tmpdir or die 'Unable to create temporary directory';
}
END { -d $tmpdir and rmdir $tmpdir }

our $is_win = ($^O eq 'MSWin32');
our $exe = $is_win ? '.exe' : '';

our $cfg = CATS::Judge::Config->new;
our $fu = CATS::FileUtil->new({ logger => CATS::Logger::Die->new });
our $perl = $fu->quote_fn($^X);
our $sp = FS->catdir($root, CATS::Spawner::Platform::get_path);

my $judge_cfg = FS->catdir($root, 'config.xml');
open my $cfg_file, '<', $judge_cfg or die "Couldn't open $judge_cfg";
$cfg->read_file($cfg_file, {});

our ($gcc, @gcc_opts) = split ' ', $cfg->defines->{'#gnu_cpp'};

our $builtin_runner = CATS::Spawner::Builtin->new({
    logger => CATS::Logger::Die->new,
    run_temp_dir => $tmpdir,
    run_method => 'system'
});

our $spr = CATS::Spawner::Default->new({
    logger => CATS::Logger::Count->new,
    path => $sp,
    save_stdout => [ $tmpdir, 'stdout.txt' ],
    save_stderr => [ $tmpdir, 'stderr.txt' ],
    save_report => [ $tmpdir, 'report.txt' ],
    #debug => 1,
    json => 1,
});

sub clear_tmpdir {
    push @_, '*' if @_ < 1;
    $fu->remove([ $tmpdir, $_ ]) for (@_);
}

sub items_ok_plan { 1 + $_[0] * 3 }

sub items_ok {
    my ($r, $apps, $msg) = @_;
    is scalar @{$r->items}, scalar @$apps, 'report count == programs count';
    for my $i (0 .. scalar @{$r->items} - 1) {
        my $ri = $r->items->[$i];
        is $r->exit_code, 0, "$msg spawner exit code";
        is_deeply $ri->{errors}, [], "$msg no errors";
        is $ri->{terminate_reason}, $apps->[$i]->{tr} // $TR_OK, "$msg TR_CODE";
    }
    $r->items;
}

sub program { CATS::Spawner::Program->new(@_) }

sub compile_plan() { items_ok_plan(1) + 2 }

sub compile {
    my ($src, $out, $skip, $flags) = @_;
    my $fullsrc = FS->catdir($Bin, 'cpp', $src);
    $out = FS->catdir($tmpdir, $out);
    my $app = program($gcc, [ @{$flags // []}, @gcc_opts, '-O0', '-o', $out, $fullsrc ]);
    my $r = $builtin_runner->run(undef, $app);
    items_ok($r, [ $app ], "$src compile");
    my $compile_success = 1;
    is $r->items->[0]->{exit_status}, 0, 'compile exit code' or $compile_success = 0;
    ok -x $out, 'compile success' or $compile_success = 0;
    ($skip and skip "$src compilation failed", $skip - compile_plan) unless $compile_success;
    $out;
}

sub run_sp {
    my ($globals, $application, $args, $opts, $tr) = @_;
    my $app = program($application, $args, $opts)->set_expected_tr($tr // $TR_OK);
    my $r = $spr->run($globals, $app);
    items_ok($r, [ $app ], (FS->splitpath($application))[2]);
}

sub run_sp_multiple {
    my ($globals, $apps, $msg) = @_;
    my $r = $spr->run($globals, @$apps);
    items_ok($r, $apps, join ', ', map { (FS->splitpath($_->application))[2] } @$apps );
}

sub tmp_name {
    my @chars = ('A'..'Z', 'a'..'z', '0'..'9');
    FS->catdir($tmpdir, join '', (map @chars[rand @chars], 1..10), '.tmp');
}

sub make_test_file {
    my ($line, $count, $endl) = @_;
    $endl //= "\n";

    my $filename = tmp_name;
    open my $fh, '>', $filename;
    print $fh "$line$endl" for 1..$count - 1;
    print $fh $line;
    $filename;
}

my $subtest_depth = 0;

sub run_subtest {
    my ($name, $plan, $sub) = @_;
    ++$subtest_depth;
    if ($subtest_depth == 1 && $ARGV[0] && ($name !~ $ARGV[0])) {
        SKIP: { skip "Skipping, '$name' does not match '$ARGV[0]'", 1; }
        --$subtest_depth;
        return;
    }
    subtest $name => sub {
        SKIP: {
            plan tests => $plan;
            $sub->($plan);
        }
    };
    --$subtest_depth;
}

1;
