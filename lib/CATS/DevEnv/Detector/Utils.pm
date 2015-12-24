package CATS::DevEnv::Detector::Utils;

use strict;
use warnings;

use if $^O eq 'MSWin32', 'Win32::TieRegistry';
use if $^O eq 'MSWin32', 'Win32API::File' => qw(getLogicalDrives SetErrorMode);

use File::Glob 'bsd_glob';
use File::Spec;
use File::Path qw(remove_tree);
use constant FS => 'File::Spec';

use constant TEMP_SUBDIR => 'tmp';

use parent qw(Exporter);
our @EXPORT = qw(
    TEMP_SUBDIR temp_file write_temp_file version_cmp clear normalize_path globq
    which env_path folder registry registry_assoc registry_glob program_files drives pattern
);

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
    return 0 if $^O eq 'MSWin32';
    my $output =`which $file`;
    for my $line (split /\n/, $output) {
        $detector->validate_and_add($line);
    }
}

sub env_path {
    my ($detector, $file) = @_;
    for my $dir (FS->path) {
        folder($detector, $dir, $file);
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
    my ($detector, $folder, $file) = @_;
    for (globq $folder) {
        extension($detector, FS->catfile($_, $file));
    }
}

use constant REGISTRY_PREFIX => qw(
    HKEY_LOCAL_MACHINE/SOFTWARE/
    HKEY_LOCAL_MACHINE/SOFTWARE/Wow6432Node/
);

sub registry {
    my ($detector, $reg, $key, $local_path, $file) = @_;
    $local_path ||= '';
    for my $reg_prefix (REGISTRY_PREFIX) {
        my $registry = get_registry_obj("$reg_prefix$reg") or next;
        my $folder = $registry->GetValue($key) or next;
        folder($detector, FS->catdir($folder, $local_path), $file);
    }
}

use constant REG_READONLY => {
    Delimiter => '/',
    Access =>
        Win32::TieRegistry::KEY_READ
};

use constant REG_READ_WRITE => {
    Delimiter => '/',
    Access =>
        Win32::TieRegistry::KEY_READ |
        Win32::TieRegistry::KEY_WRITE
};

sub get_registry_obj {
    my ($reg) = @_;
    Win32::TieRegistry->new($reg, REG_READONLY);
}

sub registry_assoc {
    my ($detector, $assoc, $local_path, $file) = @_;
    my $cmd_key = get_registry_obj("HKEY_CLASSES_ROOT/$assoc/Shell/Open/Command") or return;
    my $cmd_line = $cmd_key->GetValue('') or return;
    my ($folder) = ($cmd_line =~ /^\"([^"]+)\\[^\\]+\"/) or return;
    folder($detector, FS->catdir($folder, $local_path), $file);
}

sub _registry_rec {
    my ($detector, $parent, $local_path, $file, $key, @rest) = @_;
    if (!@rest) {
        my $folder = $parent->GetValue($key) or return;
        folder($detector, FS->catdir($folder, $local_path), $file);
        return;
    }
    my @names = $key eq '*' ? $parent->SubKeyNames : $key;
    for my $subkey (@names) {
        my $subreg = $parent->Open($subkey, REG_READONLY) or next;
        _registry_rec($detector, $subreg, $local_path, $file, @rest)
    }
}

sub registry_glob {
    my ($detector, $reg_path, $local_path, $file) = @_;
    $local_path ||= '';
    my @r = split '/', $reg_path, -1;
    for (REGISTRY_PREFIX) {
        my $reg = get_registry_obj($_) or return;
        _registry_rec($detector, $reg, $local_path, $file, @r);
    }
}

sub program_files {
    my ($detector, $local_path, $file) = @_;
    my @keys = (
        'ProgramFilesDir',
        'ProgramFilesDir (x86)'
    );
    foreach my $key (@keys) {
        registry($detector, 'Microsoft/Windows/CurrentVersion', $key, $local_path, $file);
    }
}

sub pattern {
    my ($detector, $pattern) = @_;
    my @drives = ('');
    if ($^O eq 'MSWin32') {
        for my $d (getLogicalDrives()) {
            $d =~ s/\\/\//;
            push @drives, $d;
        }
    }
    for my $drive (@drives) {
        for (globq $drive . $pattern) {
            $detector->validate_and_add($_);
        }
    }
}

sub drives {
    my ($detector, $folder, $file) = @_;
    $folder ||= "";
    my @drives = getLogicalDrives();
    foreach my $drive (@drives) {
        folder($detector, FS->catdir($drive, $folder), $file);
    }
}

sub normalize_path { FS->case_tolerant ? uc $_[0] : $_[0] }

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

sub disable_error_dialogs {
    $^O eq 'MSWin32' or return;
    # https://msdn.microsoft.com/en-us/library/windows/desktop/ms680621%28v=vs.85%29.aspx
    # SEM_FAILCRITICALERRORS
    SetErrorMode(1 | SetErrorMode(0));
}

use constant POLICY_KEYS => qw(
    HKEY_LOCAL_MACHINE/Software/Policies
    HKEY_LOCAL_MACHINE/Software/Microsoft/Windows/CurrentVersion/Policies
    HKEY_CURRENT_USER/Software/Policies
    HKEY_CURRENT_USER/Software/Microsoft/Windows/CurrentVersion/Policies
);

sub disable_windows_error_reporting_ui {
    $^O eq 'MSWin32' or return;
    my $wre = 'Microsoft/Windows/Windows Error Reporting';
    for my $key (POLICY_KEYS) {
        my $obj = get_registry_obj("$key/$wre") or next;
        my $old_value = $obj->GetValue('DontShowUI') // next;
        if (hex($old_value) > 0) {
            print ' (already disabled) ';
        }
        else {
            print ' (was enabled) ';
            $obj = Win32::TieRegistry->new("$key/$wre", REG_READ_WRITE) or die $^E;
            $obj->SetValue('DontShowUI', 1);
        }
        return;
    }
    print ' (was undefined) ';
    for my $key (POLICY_KEYS) {
        my $parent = Win32::TieRegistry->new($key, REG_READ_WRITE) or next;
        my $obj = $parent->CreateKey($wre, REG_READ_WRITE) or warn($^E), next;
        $obj->SetValue('DontShowUI', 1);
        return;
    }
}

1;
