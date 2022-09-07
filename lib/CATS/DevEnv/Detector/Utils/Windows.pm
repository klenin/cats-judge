package CATS::DevEnv::Detector::Utils::Windows;

use strict;
use warnings;

BEGIN { $^O eq 'MSWin32' or die 'Windows only'; }

use constant FS => 'File::Spec';

use Win32::TieRegistry;
use Win32::API;
use Win32API::File qw(getLogicalDrives SetErrorMode);

use CATS::DevEnv::Detector::Utils::Common;

use parent qw(Exporter);
our @EXPORT = qw(
    add_to_path
    detect_proxy
    disable_error_dialogs
    disable_windows_error_reporting_ui
    drives
    lang_dirs
    pbox
    program_files
    registry
    registry_assoc
    registry_glob
);

use constant REGISTRY_PREFIX => qw(
    HKEY_CURRENT_USER/Software/
    HKEY_CURRENT_USER/Software/Wow6432Node/
    HKEY_LOCAL_MACHINE/SOFTWARE/
    HKEY_LOCAL_MACHINE/SOFTWARE/Wow6432Node/
);

sub registry {
    my ($detector, $reg, $key, $local_path, $file) = @_;
    $allowed{registry} or return;
    $local_path ||= '';
    for my $reg_prefix (REGISTRY_PREFIX) {
        my $registry = get_registry_obj("$reg_prefix$reg") or next;
        my $folder = $registry->GetValue($key) or next;
        folder($detector, FS->catdir($folder, $local_path), $file, { force => 1 });
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
    debug_log("get_registry_obj: $reg");
    Win32::TieRegistry->new($reg, REG_READONLY);
}

sub registry_assoc {
    my ($detector, %p) = @_;
    $allowed{registry} or return;
    my $assoc = $p{assoc} or die;
    my $local_path = $p{local_path} // '';
    my $file = $p{file} or die;
    my $command = $p{command} // 'Open';
    my $cmd_key = get_registry_obj("HKEY_CLASSES_ROOT/$assoc/Shell/$command/Command") or return;
    my $cmd_line = $cmd_key->GetValue('') or return;
    my ($folder) = ($cmd_line =~ /^\"([^"]+)\\[^\\]+\"/) or return;
    folder($detector, FS->catdir($folder, $local_path), $file, { force => 1 });
}

sub SubKeyNames_fixup {
    my ($reg) = @_;
    $reg = tied(%$reg) if tied(%$reg);
    # Workaround for https://rt.cpan.org/Public/Bug/Display.html?id=97127, fixed in Win32::TieRegistry 0.27
    use version ();
    return $reg->SubKeyNames if version->parse($Win32::TieRegistry::VERSION) >= version->parse('0.27');
    my @subkeys;
    my ($nameSize, $classSize) = $reg->Information(qw(MaxSubKeyLen MaxSubClassLen));
    while ($reg->RegEnumKeyEx(
        scalar @subkeys, my $subkey, (my $ns = $nameSize + 1), [], my $class, (my $cl = $classSize + 1), my $time)
    ) {
        push @subkeys, $subkey;
    }
    @subkeys;
}

sub _registry_rec {
    my ($detector, $parent, $local_path, $file, $key, @rest) = @_;
    if (!@rest) {
        my $folder = $parent->GetValue($key) or return;
        folder($detector, FS->catdir($folder, $local_path), $file, { force => 1 });
        return;
    }

    my $prefix = '';
    my @names;
    if ($key =~ /^(.*)\*$/) {
        $prefix = $1;
        @names = SubKeyNames_fixup($parent);
    }
    else {
        @names = $key;
    }
    for my $subkey (@names) {
        $subkey =~ /^\Q$prefix\E/ or next;
        my $subreg = $parent->Open($subkey, REG_READONLY) or next;
        debug_log('_registry_rec: ', $parent->Path(), $subkey);
        _registry_rec($detector, $subreg, $local_path, $file, @rest)
    }
}

sub registry_glob {
    my ($detector, $reg_path, $local_path, $file) = @_;
    $allowed{registry} or return;
    $local_path ||= '';
    my @r = split '/', $reg_path, -1;
    for (REGISTRY_PREFIX) {
        my $reg = get_registry_obj($_) or return;
        _registry_rec($detector, $reg, $local_path, $file, @r);
    }
}

sub program_files {
    my ($detector, $local_path, $file) = @_;
    $allowed{folder} or return;
    my @keys = (
        'ProgramFilesDir',
        'ProgramFilesDir (x86)'
    );
    foreach my $key (@keys) {
        registry($detector, 'Microsoft/Windows/CurrentVersion', $key, $local_path, $file);
    }
}

sub drives {
    my ($detector, $folder, $file) = @_;
    $allowed{folder} or return;
    $folder or die;
    my @drives = getLogicalDrives();
    foreach my $drive (@drives) {
        folder($detector, FS->catdir($drive, $folder), $file);
    }
}

sub lang_dirs {
    my ($detector, $folder, $subfolder, $file) = @_;
    $allowed{folder} or return;
    drives($detector, FS->catfile(@$_), $file) for
        [ 'lang', $folder, $subfolder ],
        [ 'langs', $folder, $subfolder ],
        [ 'lang', $folder, '*', $subfolder ],
        [ 'langs', $folder, '*', $subfolder ];
}

sub disable_error_dialogs {
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

sub windows_encode_console_message {
    my ($msg) = @_;
    my $acp = Win32::API::More->new('kernel32', 'int GetACP()')->Call;
    my $cocp = Win32::API::More->new('kernel32', 'int GetConsoleOutputCP()')->Call;
    Encode::from_to($msg, "CP$acp", "CP$cocp") if $acp != $cocp;
    $msg;
}

sub disable_windows_error_reporting_ui {
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
        my $obj = $parent->CreateKey($wre, REG_READ_WRITE) or next;
        $obj->SetValue('DontShowUI', 1) or next;
        return;
    }
    print 'failed to set: ', windows_encode_console_message($^E);
}

sub detect_proxy {
    my $key = get_registry_obj(
        'HKEY_CURRENT_USER/Software/Microsoft/Windows/CurrentVersion/Internet Settings') or return '';
    $key->GetValue('ProxyEnable') or return '';
    $key->GetValue('ProxyServer') // '';
}

sub add_to_path {
    my ($dir) = @_;
    my $key = Win32::TieRegistry->new('HKEY_CURRENT_USER/Environment', REG_READ_WRITE) or return;
    my ($path, $type) = $key->GetValue('PATH');
    $path = $path ? "$path;" : '';
    my $dir_re = qr/\Q$dir\E\\?$/;
    return ' (already in user path)' if grep /$dir_re/, split /;/, $path;
    return ' (already in some other path)' if grep /$dir_re/, FS->path;
    $key->SetValue('PATH', $path . $dir, $type // Win32::TieRegistry::REG_SZ);
    return 'added';
}

sub pbox {
    my ($detector, $name, $folder, $file) = @_;
    $allowed{pbox} or return;
    $name or die;
    my $pbox = $ENV{PBOX_HOME} or return;
    my $fname = FS->catfile($pbox, 'registry', $name, ".$name.pbox");
    open my $reg, '<', $fname or return;
    debug_log("pbox: $fname");
    while (<$reg>) {
        /^homedir=(.+)$/ or next;
        folder($detector, FS->catdir($1, $folder), $file);
    }
}

1;
