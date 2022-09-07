package CATS::DevEnv::Detector::Utils::Common;

use strict;
use warnings;

use Encode;
use File::Glob 'bsd_glob';
use File::Spec;
use File::Path qw(remove_tree);
use IPC::Cmd;
use constant FS => 'File::Spec';

use constant TEMP_SUBDIR => 'tmp';

use parent qw(Exporter);
our @EXPORT = qw(
    allow_methods
    %allowed
    clear
    debug_log
    env_path
    folder
    globq
    normalize_path
    run
    temp_file
    TEMP_SUBDIR
    version_cmp
    which
    write_temp_file
);

our ($log, $debug);
our %allowed = (folder => 1, path => 1, pbox => 1, registry => 1);

sub allow_methods {
    my ($new_allowed) = @_;
    my @bad = grep !exists $allowed{$_}, @$new_allowed;
    @bad and die sprintf 'Unknown method %s, must be one of: %s',
        join(', ', @bad), join(', ', sort keys %allowed);
    my %n;
    @n{@$new_allowed} = undef;
    $allowed{$_} = exists($n{$_}) // 0 for keys %allowed;
}

sub debug_log { print $log @_, "\n" if $debug; }

sub globq {
    my ($pattern) = @_;
    $pattern =~ s/\\/\\\\/g;
    bsd_glob $pattern;
}

sub clear { remove_tree(TEMP_SUBDIR, { error => \my $err }) }

sub temp_file { FS->rel2abs(FS->catfile(TEMP_SUBDIR, $_[0])) }

sub write_temp_file {
    my ($name, $text) = @_;
    -d TEMP_SUBDIR or mkdir TEMP_SUBDIR;
    my $file = temp_file($name);
    open my $fh, '>', $file;
    print $fh $text;
    close $fh;
    return $file;
}

sub which {
    my ($detector, $file) = @_;
    $allowed{path} or return;
    return if $^O eq 'MSWin32';
    my ($ok, undef, undef, $out) = run(command => [ 'which', $file ]);
    $ok or return;
    for (@$out) {
        chomp;
        $detector->validate_and_add($_);
    }
}

sub env_path {
    my ($detector, $file) = @_;
    $allowed{path} or return;
    for my $dir (FS->path) {
        folder($detector, $dir, $file, { force => 1 });
    }
}

sub extension {
    my ($detector, $path) = @_;
    my @exts = ('', '.exe', '.bat', '.com');
    for my $e (@exts) {
        $detector->validate_and_add($path . $e);
    }
}

sub folder {
    my ($detector, $folder, $file, $opts) = @_;
    $allowed{folder} || $opts->{force} or return;
    debug_log("folder: $folder / $file");
    for (globq $folder) {
        extension($detector, FS->catfile($_, $file));
    }
}

sub normalize_path { FS->case_tolerant ? uc $_[0] : $_[0] }

sub _run_quote {
    my ($arg) = @_;
    $^O eq 'MSWin32' or return $arg;
    my $q = IPC::Cmd::QUOTE;
    $arg =~ s/$q/\\$q/g;
    "$q$arg$q";
}

sub run {
    my (%p) = @_;
    my @quoted = map _run_quote($_), @{$p{command}};
    debug_log(join ' ', 'run:', @quoted);
    return IPC::Cmd::run command => \@quoted if IPC::Cmd->can_capture_buffer;

    -d TEMP_SUBDIR or mkdir TEMP_SUBDIR;
    my ($fstdout, $fstderr) = map FS->catfile(TEMP_SUBDIR, $_), qw(stdout.txt stderr.txt);
    my $command = join ' ', @quoted, '1>' . _run_quote($fstdout), '2>' . _run_quote($fstderr);
    system($command) == 0 or return (0, $!);
    my @stdout = do { open my $f, '<', $fstdout; map $_, <$f>; };
    my @stderr = do { open my $f, '<', $fstderr; map $_, <$f>; };
    (1, '', [ @stdout, @stderr ], \@stdout, \@stderr);
}

sub version_cmp {
    my ($a, $b) = @_;
    my @A = ($a =~ /([-.]|\d+|[^-.\d]+)/g);
    my @B = ($b =~ /([-.]|\d+|[^-.\d]+)/g);

    my ($A, $B);
    while (@A and @B) {
        $A = shift @A;
        $B = shift @B;
        if ($A eq '.' and $B eq '.') {
            next;
        } elsif ( $A eq '.' ) {
            return -1;
        } elsif ( $B eq '.' ) {
            return 1;
        } elsif ($A =~ /^\d+$/ and $B =~ /^\d+$/) {
            if ($A =~ /^0/ || $B =~ /^0/) {
                return $A cmp $B if $A cmp $B;
            } else {
                return $A <=> $B if $A <=> $B;
            }
        } else {
            $A = uc $A;
            $B = uc $B;
            return $A cmp $B if $A cmp $B;
        }
    }
    @A <=> @B;
}

1;
