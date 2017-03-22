use strict;
use warnings;

use Test::More tests => 4;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use CATS::Spawner::Const ':all';

my $is_win = ($^O eq 'MSWin32');
my $exe = $is_win ? '.exe' : '';

my ($gcc, @gcc_opts) = split ' ', $cfg->defines->{'#gnu_cpp'};
ok -x $sp, 'sp exists' or exit;
ok -x $gcc, 'gcc exists' or exit;

my $builtin_runner = CATS::Spawner::Builtin->new({
    logger => CATS::Logger::Die->new,
    run_temp_dir => $tmpdir,
    run_method => 'system'
});

my $spr = CATS::Spawner::Default->new({
    logger => CATS::Logger::Die->new,
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

sub items_ok {
    my ($r, $msg) = @_;
    for my $ri (@{$r->items}) {
        is_deeply $ri->{errors}, [], "$msg no errors";
        is $ri->{terminate_reason}, $TR_OK, "$msg TR_OK";
    }
    $r->items;
}

sub program { CATS::Spawner::Program->new(@_) }

sub compile {
    my ($src, $out, $skip) = @_;
    my $fullsrc = FS->catdir($Bin, 'cpp', $src);
    $out = FS->catdir($tmpdir, $out);
    my $app = program($gcc, [ '-o', $out, $fullsrc ]);
    my $r = $builtin_runner->run(undef, $app);
    items_ok($r, "$src compile");
    my $compile_success = 1;
    is $r->items->[0]->{exit_status}, 0, 'compile exit code' or $compile_success = 0;
    ok -x $out, 'compile success' or $compile_success = 0;
    ($skip and skip "$src compilation failed", $skip - 4) unless $compile_success;
    $out;
}

sub run_sp {
    my ($globals, $application, $args, $opts) = @_;
    my $app = program($application, $args, $opts);
    my $r = $spr->run($globals, $app);
    items_ok($r, (FS->splitpath($application))[2]);
}

sub run_sp_multiple {
    my ($globals, @apps, $msg) = @_;
    my $r = $spr->run($globals, @apps);
    items_ok($r, join ', ', map { (FS->splitpath($_->application))[2] } @apps );
}

sub tmp_name {
    my @chars = ('A'..'Z', 'a'..'z', '0'..'9');
    FS->catdir($tmpdir, join '', (map @chars[rand @chars], 1..20), '.tmp');
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

sub run_subtest {
    my ($name, $plan, $sub) = @_;
    subtest $name => sub {
        SKIP: {
            plan tests => $plan;
            $sub->($plan);
        }
    };
}

run_subtest 'HelloWorld', 7, sub {
    my $hw = compile('helloworld.cpp', 'helloworld' . $exe, $_[0]);
    run_sp(undef, $hw);
    is_deeply $spr->stdout_lines, [ 'Hello world!' ], 'helloworld stdout';
    clear_tmpdir;
};

run_subtest 'Pipe', 12, sub {
    my $pipe = compile('pipe.cpp', 'pipe' . $exe, $_[0]);

    run_subtest 'Pipe input', 6, sub {
        my $in = make_test_file('test', 1);
        run_sp({ stdin => $in }, $pipe);
        is_deeply $spr->stdout_lines_chomp, [ 'test' ], 'pipe one input global';
        clear_tmpdir('*.txt');
        run_sp(undef, $pipe, [], { stdin => $in });
        is_deeply $spr->stdout_lines_chomp, [ 'test' ], 'pipe one input local';
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe big input', 3, sub {
        my $n = 26214;
        my $data;
        $data .= '123456789' for 1..$n;
        my $in = make_test_file($data, 1);
        run_sp(undef, $pipe, [], { stdin => $in });
        is_deeply $spr->stdout_lines_chomp, [ $data ];
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe output', 6, sub {
        my $out = tmp_name;
        run_sp({ stdout => $out }, $pipe, [ '"out string"' ]);
        is_deeply $fu->read_lines_chomp($out), [ 'out string' ], 'pipe one output global';
        clear_tmpdir('*.txt', '*.tmp');
        run_sp({ stdout => '' }, $pipe, [ '"out string"' ], { stdout => $out });
        is_deeply $fu->read_lines_chomp($out), [ 'out string' ], 'pipe one output local';
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe input -> output', 3, sub {
        my $in = make_test_file('test string', 1);
        my $out = tmp_name;
        run_sp({ stdin => $in, stdout => $out }, $pipe);
        is_deeply $spr->stdout_lines_chomp, [ 'test string' ];
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe input from two files', 3, sub {
        my $in1 = make_test_file('one', 1);
        my $in2 = make_test_file('two', 1);
        run_sp({ stdin => $in1 }, $pipe, [], { stdin => $in2 });
        like $spr->stdout_lines_chomp->[0], qr/(one|two){2}/;
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe output in same files', 3, sub {
        my $out1 = tmp_name;
        my $out2 = tmp_name;
        run_sp({ stdout => $out1 }, $pipe, [ '"out string"' ], { stdout => $out2 });
        is_deeply [ @{$fu->read_lines_chomp($out1)}, @{$fu->read_lines_chomp($out2)} ], [ 'out string', 'out string' ];
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe output + error to one file', 3, sub {
        my $out = tmp_name;
        run_sp({ stdout => $out, stderr => $out }, $pipe, [ 'out', 'err' ]);
        is_deeply $spr->stdout_lines_chomp, [ 'errout' ];
        clear_tmpdir('*.txt', '*.tmp');
    };

    run_subtest 'Pipe stdin close without redirect', 3, sub {
        my $out = tmp_name;
        run_sp({ stdout => $out, stderr => $out }, $pipe);
        is_deeply $spr->stdout_lines_chomp, [ ];
        clear_tmpdir('*.txt', '*.tmp');
    };

    clear_tmpdir;
};
