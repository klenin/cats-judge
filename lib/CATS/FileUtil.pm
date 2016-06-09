package CATS::FileUtil;

use strict;
use warnings;

use Carp;
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

sub fn {
    my ($file) = @_;
    ref $file eq 'ARRAY' ? File::Spec->catfile(@$file) : $file;
}

sub write_to_file {
    my ($self, $file_name, $src) = @_;
    my $fn = fn($file_name);
    open my $file, '>', $fn or return $self->log("open failed: '$fn' ($!)\n");
    binmode $file;
    print $file $src;
    1;
}

sub read_lines {
    my ($self, $file_name) = @_;
    my $fn = fn($file_name);
    open my $f, '<', $fn or return $self->log("read_lines failed: '$fn' ($!)\n");
    [ map $_, <$f> ];
}

sub read_lines_chomp {
    my ($self, $file_name) = @_;
    my $fn = fn($file_name);
    open my $f, '<', $fn  or return $self->log("read_lines_chomp failed: '$fn' ($!)\n");
    [ map { chomp; $_ } <$f> ];
}

sub ensure_dir {
    my ($self, $dir_name, $name) = @_;
    my $dn = fn $dir_name;
    $name ||= '';
    -d $dn or mkdir $dn or die "Can not create $name '$dn': $!";
}

sub remove_file {
    my ($self, $file_name) = @_;
    my $fn = fn($file_name);
    -f $fn || -l $fn or return $self->log("remove_file: '$fn' is not a file\n");

    # Some AV software blocks access to new executables while running checks.
    for my $retry (0..9) {
        unlink $fn or return $self->log("remove_file: unlink '$fn' failed ($!)\n");
        -f $fn || -l $fn or return 1;
        $retry or next;
        sleep 1;
        $self->log("remove_file: '$fn' retry $retry\n");
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

    opendir my $dir, $dir_name or return $self->log("opendir: '$dir_name' ($!)\n");
    my @files = map File::Spec->catfile($dir_name, $_), grep !/^\.\.?$/, readdir $dir;
    closedir $dir;

    $self->_remove_files(@files) or return;
    rmdir $dir_name or return $self->log("remove_dir $dir_name: $!\n");
    1;
}

sub remove {
    @_ == 2 or die;
    my ($self, $path) = @_;
    $self->_remove_files(glob fn $path);
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

sub quote_fn {
    my ($self, $fn) = @_;
    $fn =~ /\s/ or return $fn;
    my $q = $^O eq 'MSWin32' ? '"' : "'";
    $fn =~ s/$q/\\$q/g;
    "$q$fn$q";
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
    @parts;
}

sub _run_ipc {
    my ($self, $cmd) = @_;
    my @parts = map _split_braced(fn($_)), @$cmd;
    $self->log(join(' ', 'run_ipc:', @parts), "\n") if $self->{run_debug_log};
    IPC::Cmd::run command => \@parts;
}

sub _run_system {
    my ($self, $cmd) = @_;
    my $tmp = $self->{run_temp_dir}
        or confess "run: run_temp_dir is required for 'system' method";
    my @quoted = map $self->quote_braced($_), @$cmd;
    $self->log(join(' ', 'run_system:', @quoted), "\n") if $self->{run_debug_log};
    -d $tmp or mkdir $tmp or return $self->log("run: mkdir: $!");
    my @redirects = map File::Spec->catfile($tmp, $_), qw(stdout.txt stderr.txt);
    my $command = join ' ', @quoted,
        map { ($_ + 1) . '>' . $self->quote_fn($redirects[$_]) } 0..1;
    system($command) == 0 or return (0, $!, [], [], []);
    my $redirected_data = [ map $self->read_lines($_) // [], @redirects ];
    (1, '', [ map @$_, @$redirected_data ], @$redirected_data);
}

sub _run_array {
    goto $_[0]->{run_method} = 'ipc' ? \&_run_ipc : \&_run_system;
}

sub run { CATS::RunResult->new(_run_array @_) }

package CATS::RunResult;

sub new {
    my ($class, @p) = @_;
    # $ok, $err, $full_buf, $stdout_buff, $stderr_buff
    $p[0] //= 0;
    $p[1] //= '';
    ref $p[$_] eq 'ARRAY' or die for 2..4;
    bless [ @p ], $class;
}

sub ok { $_[0]->[0] // 0 }
sub err { $_[0]->[1] }
sub full { $_[0]->[2] }
sub stdout { $_[0]->[3] }
sub stderr { $_[0]->[4] }

sub check_err { !$_[0]->ok && $_[0]->err =~ $_[1] }
sub check_stdout { $_[0]->ok && $_[0]->stdout_buf =~ $_[1] }

1;
