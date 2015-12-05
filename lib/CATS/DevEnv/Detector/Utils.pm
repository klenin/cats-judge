package CATS::DevEnv::Detector::Utils;
use strict;
use warnings;
use if $^O eq 'MSWin32', "Win32::TieRegistry";
use if $^O eq 'MSWin32', "Win32API::File" => qw(getLogicalDrives);

use File::Spec;
use constant FS => 'File::Spec';
use constant DIRS_IN_PATH => FS->path();

sub clear {
    my ($ret) = @_;
    unlink "tmp/*";
    return $ret;
}

sub write_file {
    my ($name, $text) = @_;
    open(my $fh, '>', $name);
    print $fh $text;
    close $fh;
}

sub hello_world {
    my ($compile) = @_;
    system $compile;
    $? >> 8 && return clear(0);
    my $out = `hello_world.exe`;
    $out ne "Hello World" && return clear(0);
    return clear(1);
}

sub which {
    my ($detector, $file) = @_;
    if ($^O eq "MSWin32") {
        return 0;
    }
    my $output =`which $file`;
    my $res = 0;
    for my $line (split /\n/, $output) {
        $res += $detector->validate_and_add($line);
    }
    return $res;
}

sub env_path {
    my ($detector, $file) = @_;
    my $res = 0;
    for my $dir (DIRS_IN_PATH) {
        $res = folder($detector, $dir, $file);
    }
    return $res;
}

sub extension {
    my ($detector, $path) = @_;
    my @exts = ('', '.exe', '.bat', '.com');
    my $res = 0;
    for my $e (@exts) {
        $res += $detector->validate_and_add($path . $e);
    }
    return $res;
}

sub folder {
    my ($detector, $folder, $file) = @_;
    my $path = FS->catfile($folder, $file);
    return extension($detector, $path);
}

sub registry {
    my ($detector, $reg, $key, $local_path, $file) = @_;
    $local_path ||= "";
    my $registry = get_registry_obj($detector, $reg) or return 0;
    my $folder = $registry->GetValue($key) or return 0;
    return folder($detector, FS->catdir($folder,$local_path) , $file);
}

sub get_registry_obj {
    my ($detector, $reg) = @_;
    return Win32::TieRegistry->new($reg, {
        Access => Win32::TieRegistry::KEY_READ(),
        Delimiter => '/'
    });
}

sub registry_loop {
    my ($detector, $reg, $key, $local_path, $file) = @_;
    $local_path ||= "";
    my $registry = get_registry_obj($detector, $reg) or return 0;
    my $res = 0;
    foreach my $subkey ($registry->SubKeyNames()) {
        my $subreg = $registry->Open($subkey, {
            Access => Win32::TieRegistry::KEY_READ(),
            Delimiter => '/'
        });
        my $folder = $subreg->GetValue($key) or next;
        $res += folder($detector, FS->catdir($folder, $local_path), $file);
    }
    return $res;
}

sub program_files {
    my ($detector, $local_path, $file) = @_;
    my @paths = (
        'HKEY_LOCAL_MACHINE/SOFTWARE/Microsoft/Windows/CurrentVersion',
        'HKEY_LOCAL_MACHINE/SOFTWARE/Wow6432Node/Microsoft/Windows/CurrentVersion'
    );
    my @keys = (
        'ProgramFilesDir',
        'ProgramFilesDir (x86)'
    );
    my $res = 0;
    foreach my $path (@paths) {
        foreach my $key (@keys) {
            $res += registry($detector, $path, $key, $file, $local_path);
        }
    }
    return $res;
}


sub drives {
    my ($detector, $folder, $file) = @_;
    $folder ||= "";
    my @drives = getLogicalDrives();
    my $res = 0;
    foreach my $drive (@drives) {
        $res += folder($detector, FS->catdir($drive, $folder), $file);
    }
    return $res;
}

sub versioncmp {
    my ($a, $b) = @_;
    my @A = ($a =~ /([-.]|\d+|[^-.\d]+)/g);
    my @B = ($b =~ /([-.]|\d+|[^-.\d]+)/g);

    my ($A, $B);
    while (@A and @B) {
	$A = shift @A;
	$B = shift @B;
	if ($A eq '-' and $B eq '-') {
	    next;
	} elsif ( $A eq '-' ) {
	    return -1;
	} elsif ( $B eq '-') {
	    return 1;
	} elsif ($A eq '.' and $B eq '.') {
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
