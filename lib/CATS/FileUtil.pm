package CATS::FileUtil;

use strict;
use warnings;

use Carp;
use Encode;
use File::Spec;
use File::Copy::Recursive qw(rcopy);
use IPC::Cmd;

use constant OPTIONS => [qw(
    logger
    run_debug_log
    run_temp_dir
    run_method
)];

sub new {
    my ($class, $opts) = @_;
    my $self = { map { $_ => $opts->{$_} } @{OPTIONS()} };
    $self->{run_method} //= IPC::Cmd->can_capture_buffer ? 'ipc' : 'system';
    bless $self, $class;
}

sub log {
    my ($self, @rest) = @_;
    $self->{logger} or confess 'No logger';
    $self->{logger}->msg(@rest);
}

sub _fn_basic {
    my ($file) = @_;
    ref $file eq 'ARRAY' ? File::Spec->catfile(@$file) : $file;
}

sub _fn_win {
    my $fn = _fn_basic(@_);
    Encode::from_to($fn, 'UTF-8', 'WINDOWS-1251');
    $fn;
}

BEGIN { *fn = $^O eq 'MSWin32' ? \&_fn_win : \&_fn_basic }

sub write_to_file {
    my ($self, $file_name, $src) = @_;
    my $fn = fn($file_name);
    open my $file, '>', $fn or return $self->log("open failed: '$fn' ($!)\n");
    binmode $file;
    print $file $src;
    1;
}

sub read_lines {
    my ($self, $file_name, %opts) = @_;
    my $fn = fn($file_name);
    open my $f, '<' . ($opts{io} // ''), $fn
        or return $self->log("read_lines failed: '$fn' ($!)\n");
    [ <$f> ];
}

sub load_file {
    my ($self, $file_name, $limit) = @_;
    my $fn = fn($file_name);
    open my $f, '<', $fn or return $self->log("load_file failed: '$fn' ($!)\n");
    binmode $f;
    read($f, my $res, $limit);
    $res, -s $f;
}

sub read_lines_chomp {
    my ($self, $file_name, %opts) = @_;
    my $fn = fn($file_name);
    open my $f, '<' . ($opts{io} // ''), $fn
        or return $self->log("read_lines_chomp failed: '$fn' ($!)\n");
    [ map { chomp; $_ } <$f> ];
}

sub ensure_dir {
    my ($self, $dir_name, $name) = @_;
    my $dn = fn $dir_name;
    $name ||= '';
    -d $dn or mkdir $dn or die "Can not create $name '$dn': $!";
}

sub dir_files {
    my ($self, $dir) = @_;

    my $dir_name = fn $dir;
    opendir my $dir_handle, $dir_name
        or return $self->log("opendir: '$dir_name' ($!)\n");
    [ map File::Spec->catfile($dir_name, $_), grep !/^\.\.?$/, readdir $dir_handle ];
}

sub remove_file {
    my ($self, $file_name) = @_;
    my $fn = _fn_basic($file_name);
    -f $fn || -l $fn or return $self->log("remove_file: '$fn' is not a file\n");

    # Some AV software blocks access to new executables while running checks.
    for my $retry (0..3) {
        unlink $fn or $self->log("remove_file: unlink '$fn' failed ($!)\n");
        -f $fn || -l $fn or return 1;
        sleep 1; # Might be delayed stat update.
        -f $fn || -l $fn or return 1;
        $self->log("remove_file: '$fn' retry $retry\n") if $retry;
    }
}

sub _remove_files {
    my ($self, @files) = @_;
    # Do not recurse into directory symlinks.
    @files == grep {
        (-f || -l) ? $self->remove_file($_) :
        (-d) ? $self->_remove_dir_rec($_) : 1 } @files;
}

sub _remove_dir_rec {
    my ($self, $dir_name) = @_;

    my $files = $self->dir_files($dir_name) or return;
    $self->_remove_files(@$files) or return;
    rmdir $dir_name or return $self->log("remove_dir $dir_name: $!\n");
    1;
}

sub remove {
    @_ == 2 or die;
    my ($self, $path) = @_;
    $self->_remove_files(glob fn $path);
}

sub remove_all {
    @_ == 2 or die;
    my ($self, $path) = @_;
    $self->_remove_files(@{$self->dir_files($path)}) && 1;
}

sub mkdir_clean {
    my ($self, $dir_name) = @_;

    my $dn = fn $dir_name;
    $self->remove($dn) or return;
    mkdir $dn, 0755 or return $self->log("mkdir '$dn' failed: $!\n");
    1;
}

sub copy {
    my ($self, $src, $dest) = @_;
    my ($sn, $dn) = map File::Spec->canonpath(fn $_), $src, $dest;
    return 1 if rcopy $sn, $dn;
    $self->log("copy failed: 'cp $sn $dn' '$!' " . Carp::longmess('') . "\n");
}

sub copy_glob {
    my ($self, $src, $dest) = @_;
    my ($sn, $dn) = map File::Spec->canonpath(fn $_), $src, $dest;
    my (@files) = glob $sn;
    @files == 1 or return $self->log(
        sprintf "duplicate copy sources, '%s' for 'cp %s %s'\n", join (', ', @files), $sn, $dn);
    return 1 if rcopy $files[0], $dn;
    $self->log("copy failed: 'cp $sn $dn' '$!' " . Carp::longmess('') . "\n");
}

sub quote_fn {
    my ($self, $fn) = @_;
    $fn =~ /\s/ or return $fn;
    if ($^O eq 'MSWin32') {
        $fn =~ s/"/\\"/g;
        qq~"$fn"~;
    }
    else {
        $fn =~ s/'/'\\''/g;
        "'$fn'";
    }
}

sub quote_braced {
    my ($self, $cmd) = @_;
    return $self->quote_fn(fn($cmd)) if ref $cmd eq 'ARRAY';
    $cmd =~ s/\{([^\}]*)\}/$self->quote_fn($1)/eg;
    $cmd;
}

sub _split_braced {
    my ($cmd) = @_;
    my @parts;
    my $state = 'spaces';
    for my $c (split '', $cmd) {
        if ($c eq '{') {
            die 'Nested braces' if $state eq 'braced';
            push @parts, '';
            $state = 'braced';
        }
        elsif ($c eq '}') {
            die 'Unmatched closing brace' if $state ne 'braced';
            $state = 'spaces';
        }
        elsif ($c =~ /\s/) {
            if ($state eq 'braced') {
                $parts[-1] .= $c;
            }
            else {
                $state = 'spaces';
            }
        }
        else {
            if ($state eq 'spaces') {
                push @parts, $c;
                $state = 'word';
            }
            else {
                $parts[-1] .= $c;
            }
        }
    }
    die 'Unmatched opening brace' if $state eq 'braced';
    @parts;
}

sub _split_lines { open my $f, '<:crlf', \$_[0]; <$f>; }

sub _run_ipc {
    my ($self, $cmd) = @_;
    my @parts = map _split_braced(fn($_)), @$cmd;
    $self->log(join(' ', 'run_ipc:', @parts), "\n") if $self->{run_debug_log};
    my ($ok, $err, @outputs) = IPC::Cmd::run command => \@parts;
    my $exit_code =
        # Optimistically, check the existence after the failed run.
        !$ok && IPC::Cmd::can_run($parts[0]) && $err =~ /value\s(\d+)$/ ? $1 : 0;
    # Unlike IPC::Cmd, we guarantee that outputs are split per-line.
    my ($full, $stdout, $stderr) = map [ map _split_lines($_), @$_ ], @outputs;
    CATS::RunResult->new(
        ok => $ok, err => $err, exit_code => $exit_code,
        full => $full, stdout => $stdout, stderr => $stderr);
}

sub _run_system {
    my ($self, $cmd) = @_;
    my $tmp = $self->{run_temp_dir}
        or confess "run: run_temp_dir is required for 'system' method";
    my @quoted = map $self->quote_braced($_), @$cmd;
    # On Windows system('non-existing file') gets $? == 256 instead of $? == -1.
    # Since we are forced to check existence anyway, do it early.
    -x $quoted[0] or return
        CATS::RunResult->new(full => [], stdout => [], stderr => []);
    $self->log(join(' ', 'run_system:', @quoted), "\n") if $self->{run_debug_log};
    -d $tmp or mkdir $tmp or return $self->log("run: mkdir: $!");
    my @redirects = map File::Spec->catfile($tmp, $_), qw(stdout.txt stderr.txt);
    my $command = join ' ', @quoted,
        map { ($_ + 1) . '>' . $self->quote_fn($redirects[$_]) } 0..1;
    my $ok = system($command) == 0 ? 1 : 0;
    my $err = $ok ? '' : $? == -1 ? $! : $? & 127 ? 'SIGNAL' : $? >> 8;
    my @redirected_data = map $self->read_lines($_) // [], @redirects;
    CATS::RunResult->new(
        ok => $ok, err => $err,
        exit_code => ($err =~ /^\d+$/ ? $err : 0),
        full => [ map @$_, @redirected_data ],
        stdout => $redirected_data[0],
        stderr => $redirected_data[1],
    );
}

sub run { goto $_[0]->{run_method} eq 'ipc' ? \&_run_ipc : \&_run_system; }

package CATS::RunResult;

sub new {
    my ($class, %p) = @_;
    my $self = { map { $_ => $p{$_} } qw(ok err exit_code full stdout stderr) };
    $self->{ok} //= 0;
    $self->{err} //= '';
    $self->{exit_code} //= 0;
    ref $self->{$_} eq 'ARRAY' or die for qw(full stdout stderr);
    bless $self, $class;
}

sub ok { $_[0]->{ok} }
sub err { $_[0]->{err} }
sub exit_code { $_[0]->{exit_code} }
sub full { $_[0]->{full} }
sub stdout { $_[0]->{stdout} }
sub stderr { $_[0]->{stderr} }

sub check_err { !$_[0]->ok && $_[0]->err =~ $_[1] }
sub check_stdout { $_[0]->ok && $_[0]->stdout_buf =~ $_[1] }

1;
