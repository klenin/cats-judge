package CATS::FileUtil;

use strict;
use warnings;

use Carp;
use File::Spec;
use File::Copy::Recursive qw(rcopy);

sub new {
    my ($class, $opts) = @_;
    my $self = { logger => $opts->{logger} };
    bless $self, $class;
}

sub log {
    my ($self, @rest) = @_;
    $self->{logger} or confess;
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
    my $q = $^O eq 'Win32' ? '"' : "'";
    $fn =~ s/$q/\\$q/g;
    "$q$fn$q";
}

1;
