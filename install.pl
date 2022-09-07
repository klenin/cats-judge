use v5.10;
use strict;
use warnings;

use IO::Uncompress::Unzip qw(unzip $UnzipError);
use File::Copy qw(copy);
use File::Fetch;
use File::Path qw(make_path);
use File::Spec;
use FindBin;
use Getopt::Long;
use IPC::Cmd;
use List::Util qw(max);

use lib File::Spec->catdir($FindBin::Bin, 'lib');
use lib File::Spec->catdir($FindBin::Bin, 'lib', 'cats-problem');

use CATS::ConsoleColor qw(colored);
use CATS::DevEnv::Detector::Utils qw(globq run);
use CATS::FileUtil;
use CATS::Judge::ConfigFile qw(cfg_file);
use CATS::Loggers;
use CATS::MaybeDie qw(maybe_die);
use CATS::Spawner::Platform;

$| = 1;

sub usage
{
    my (undef, undef, $cmd) = File::Spec->splitpath($0);
    print <<"USAGE";
Usage:
    $cmd
    $cmd --step <num> ...
        [--bin <download[:version[:remote-repository]]|build>]
        [--devenv <devenv-filter>] [--method <devenv-detection-method>]
        [--modules <modules-filter>]
        [--verbose] [--force]
    $cmd --help|-?
USAGE
    exit;
}

GetOptions(
     \my %opts,
    'step=i@',
    'bin=s',
    'devenv=s',
    'method=s@',
    'modules=s',
    'verbose',
    'force',
    'help|?',
) or usage;
usage if defined $opts{help};

CATS::DevEnv::Detector::Utils::set_debug(1, *STDERR) if $opts{verbose};

printf "Installing cats-judge%s\n", ($opts{verbose} ? ' verbosely' : '');

my %filter_steps;
if ($opts{step}) {
    my @steps = @{$opts{step}};
    undef @filter_steps{@steps};
    printf "Will only run steps: %s\n", join ' ', sort { $a <=> $b } @steps;
}

CATS::MaybeDie::init(%opts);

my $fu = CATS::FileUtil->new({ logger => CATS::Logger::Die->new });
my $fr = CATS::FileUtil->new({
    run_debug_log => $opts{verbose},
    logger => CATS::Logger::FH->new(*STDERR),
});

my $step_count = 0;

sub step($&) {
    my ($msg, $action) = @_;
    print colored(sprintf('%2d', ++$step_count), 'bold white'), ". $msg ...";
    if (!%filter_steps || exists $filter_steps{$step_count}) {
        $action->();
        say colored(' ok', 'green');
    }
    else {
        say colored(' skipped', 'cyan');
    }
}

sub my_copy {
    my ($from, $to) = @_;
    print "\nCopying: $from -> $to" if $opts{verbose};
    -e $to and maybe_die "Destination already exists: $to";
    copy($from, $to) or maybe_die $!;
}

sub load_cfg {
    require CATS::Judge::Config;
    CATS::Judge::Config->import;
    CATS::Judge::Config->new(root => $FindBin::Bin)->load(file => $CATS::Judge::ConfigFile::main);
}

step 'Verify install', sub {
    -f 'judge.pl' && -d 'lib' or die 'Must run from cats-judge directory';
    eval { load_cfg; } and maybe_die 'Seems to be already installed';
    say $@ if $opts{verbose};
};

step 'Verify git', sub {
    my $x = `git --version` or die 'Git not found';
    $x =~ /^git version/ or die "Git not found: $x";
};

step 'Verify required modules', sub {
    my $lines = $fu->read_lines_chomp('cpanfile');
    my @missing = grep !eval "require $_; 1;", map /^requires '(.+)';$/ && $1, @$lines;
    maybe_die join "\n", 'Some required modules not found:', @missing, '' if @missing;
};

step 'Verify optional modules', sub {
    my @bad = grep !eval "require $_; 1;", qw(
        FormalInput
        DBI
        HTTP::Request::Common
        IPC::Run
        LWP::Protocol::https
        LWP::UserAgent
        SQL::Abstract
        Term::ReadKey
        WWW::Mechanize
    );
    warn join "\n", 'Some optional modules not found:', @bad, '' if @bad;
};

step 'Clone submodules', sub {
    system('git submodule update --init');
    $? and maybe_die "Failed: $?, $!";
};

step 'Disable Windows Error Reporting UI', sub {
    CATS::DevEnv::Detector::Utils::disable_windows_error_reporting_ui();
};

my @detected_DEs;
step 'Detect development environments', sub {
    IPC::Cmd->can_capture_buffer or print ' IPC::Cmd is inadequate, will use emulation';
    print "\n";
    CATS::DevEnv::Detector::Utils::disable_error_dialogs();
    CATS::DevEnv::Detector::Utils::allow_methods($opts{method}) if $opts{method};
    my %de_cache;
    for (globq(File::Spec->catfile($FindBin::Bin, qw[lib CATS DevEnv Detector *.pm]))) {
        my ($name) = /(\w+)\.pm$/;
        next if $name =~ /^(Utils|Base)$/ || $opts{devenv} && $name !~ qr/$opts{devenv}/i;
        require $_;
        my $d = "CATS::DevEnv::Detector::$name"->new(cache => \%de_cache);
        printf "    Detecting %s:\n", $d->name;
        for (values %{$d->detect}){
            printf "      %s %-12s %s\n",
                ($_->{preferred} ? '*' : $_->{valid} ? ' ' : '?'), $_->{version}, $_->{path};
            my $ep = $_->{extra_paths};
            for (sort keys %{$ep}) {
                printf "        %12s %s\n", $_, $ep->{$_};
            }
            $_->{preferred} or next;
            $de_cache{$name} = { path => $_->{path}, code => $d->code, extra_paths => $ep };
            push @detected_DEs, $de_cache{$name};
        }
    }
};

my $proxy;
step 'Detect proxy', sub {
    $proxy = CATS::DevEnv::Detector::Utils::detect_proxy() or return;
    $proxy =~ /^http/ or $proxy = "http://$proxy";
    print " $proxy ";
    if ($ENV{HTTP_PROXY} // '' eq $proxy) {
        $proxy = '#env:HTTP_PROXY';
        print " -> $proxy ";
    }
};

my $platform;
step 'Detect platform', sub {
    $platform = CATS::Spawner::Platform::get or maybe_die "Unsupported platform: $^O";
    print " $platform" if $platform;
};

step 'Prepare spawner binary', sub {
    $platform or maybe_die "\nDetect platform first";
    my $dir = File::Spec->catdir('spawner-bin', $platform);
    -e $dir ?
        (-d $dir or maybe_die "\n$dir is not a directory") :
        make_path $dir or maybe_die "\nCan't create directory $dir";

    my $make_type = $opts{bin} // 'download';
    $make_type =~ qr~^download(:(v(\d+\.)+\d+)(:(\w+)\/(\w+))?)?$~
        or maybe_die 'Unknown --bin value';
    my $version = '';
    my $repo_owner = 'klenin';
    my $remote_repo = 'Spawner2';
    if ($1) {
        $version = $2;
        $repo_owner = $5 if $4;
        $remote_repo = $6 if $4;
    }
    elsif (-d $remote_repo) {
        # Git wants forward slash even on Windows.
        my $tag = `git --git-dir=$remote_repo/.git describe --tag --match "v[0-9]*"`;
        $tag =~ s/[\n\r]//g;
        $tag =~ /^v(\d+\.)+\d+$/ or maybe_die "Spawner submodule has invalid version tag: $tag";
        $version = $tag;
    }
    else {
        my $uri1 = "http://api.github.com/repos/$repo_owner/$remote_repo/releases/latest";
        my $ff1 = File::Fetch->new(uri => $uri1);
        $File::Fetch::BLACKLIST = ['iosock'];
        my $response;
        $ff1->fetch(to => \$response) or maybe_die;
        $response =~ /"name":"([^"]+)"/; # JSON::XS installed may be not installed yet.
        $response or maybe_die();
        $version = $1;
    }
    print $opts{verbose} ? "\n    Download spawner binary $version...\n" : " $version";
    my $file = "$platform.zip";
    # Use non-empty file if already present.
    unlink $file unless -s $file;
    # File::Fetch does not understand https protocol name but redirect works.
    my $uri = "http://github.com/$repo_owner/$remote_repo/releases/download/$version/$file";
    print "    Link: $uri\n" if $opts{verbose};
    if ($proxy) {
        $ENV{http_proxy} = $ENV{https_proxy} = $proxy;
    }
    my $ff = File::Fetch->new(uri => $uri);
    my $zip_file = -e $file ? $file : $ff->fetch or maybe_die "Can't download bin files from $uri";
    my $sp = $^O eq 'MSWin32' ? 'sp.exe' : 'sp';
    my $sp_path = File::Spec->catfile($dir, $sp);
    printf "    Downloaded: %d bytes\n", -s $zip_file if $opts{verbose};
    unzip($zip_file => $sp_path, Name => $sp, BinModeOut => 1)
        or maybe_die "Can't unzip $zip_file: $UnzipError";
    chmod 0744, $sp_path if $^O ne 'MSWin32';
    unlink $zip_file;
};

step 'Copy Config.pm', sub {
    my @p = qw(lib cats-problem CATS);
    my_copy(File::Spec->catfile(@p, 'Config.pm.template'), File::Spec->catfile(@p, 'Config.pm'));
};

step 'Copy configuration from templates', sub {
    for (qw(autodetect local local_devenv)) {
        my $fn = cfg_file("$_.xml");
        my_copy("$fn.template", $fn);
    }
};

sub transform_file {
    my ($name, $transform_line) = @_;
    open my $fin, '<', $name or die "Can't open $name: $!";
    open my $fout, '>', "$name.tmp" or die "Can't open $name.tmp: $!";
    while (<$fin>) {
        my $orig = $_;
        my $result = $transform_line->($_);
        print $fout $result;
        print "\n    $orig -> $result" if $opts{verbose} && $result ne $orig;
    }
    close $fin;
    close $fout;
    copy $name, "$name.bak" or die "backup: $!";
    rename "$name.tmp", $name or die "rename: $!";
}

step 'Update configuration', sub {
    @detected_DEs || defined $proxy || defined $platform or return;

    transform_file(cfg_file('local.xml'), sub {
        defined $proxy and s~(\s+proxy=")"~$1$proxy"~ for $_[0];
        $_[0];
    });
    my %path_idx;
    $path_idx{$_->{code}} = $_ for @detected_DEs;
    transform_file(cfg_file('autodetect.xml'), sub {
        for ($_[0]) {
            if (/^<!--.* install.pl -->$/) {
                s/used/generated/;
            }
            elsif (my ($code, $extra) = /de_code_autodetect="(\d+)(?:\.([a-zA-Z]+))?"/) {
                if (my $de = $path_idx{$code}) {
                    my $path = $extra ? $de->{extra_paths}->{$extra} : $de->{path};
                    s/value="[^"]*"/value="$path"/;
                }
            }
            elsif (my ($code_enable) = /<de code="(\d+)" enabled="(?:\d+)"/) {
                if (my $de = $path_idx{$code_enable}) {
                    s/enabled="\d+"/enabled="1"/;
                }
            }
        }
        $_[0];
    });
};

sub parse_xml_file {
    my ($file, %handlers) = @_;
    my $xml_parser = XML::Parser::Expat->new;
    $xml_parser->setHandlers(%handlers);
    $xml_parser->parsefile($file);
}

sub get_dirs {
    my $cfg = load_cfg;
    ($cfg->modulesdir, $cfg->cachedir);
}

sub check_module {
    my ($module_name, $cachedir) = @_;
    -e $module_name or return;
    my $path = '';
    parse_xml_file($module_name,
        Start => sub {
            my ($p, $el) = @_;
            $p->setHandlers(Char => sub { $path .= $_[1] }) if $el eq 'path';
        },
        End => sub {
            my ($p, $el) = @_;
            $p->finish if $el eq 'path';
        }
    );
    $path or return;
    my ($module_cache) = $path =~ /^(.*\Q$cachedir\E.*)[\\\/]temp/ or return;
    -d $module_cache && -f "$module_cache.des" or return;
    ($fu->read_lines_chomp("$module_cache.des")->[2] // '') eq 'state:ready';
}

step 'Install cats-modules', sub {
    require XML::Parser::Expat;
    # todo use CATS::Judge::Config
    my ($modulesdir, $cachedir) = get_dirs();
    my $cats_modules_dir = File::Spec->catfile(qw[lib cats-modules]);
    my @modules = map +{
        name => $_,
        xml => globq(File::Spec->catfile($cats_modules_dir, $_, '*.xml')),
        dir => [ $cats_modules_dir, $_ ],
        success => 0
    }, grep !$opts{modules} || /$opts{modules}/,
        @{$fu->read_lines_chomp([ $cats_modules_dir, 'modules.txt'])};
    my $jcmd = [ 'cmd', 'j.'. ($^O eq 'MSWin32' ? 'cmd' : 'sh') ];
    print "\n";
    for my $m (@modules) {
        my $run = $fr->run([ $jcmd, 'install', '--problem', $m->{dir} ]);
        $run->ok or print $run->err, next;
        print @{$run->full} if $opts{verbose};
        parse_xml_file($m->{xml}, Start => sub {
            my ($p, $el, %atts) = @_;
            exists $atts{export} or return;
            $m->{total}++;
            my $module_xml = File::Spec->catfile($modulesdir, "$atts{export}.xml");
            $m->{success}++ if check_module($module_xml, $cachedir);
        });
    }
    my $w = max(map length $_->{name}, @modules);
    for my $m (@modules) {
        printf " %*s : %s\n", $w, $m->{name},
            !$m->{success} ? colored('FAILED', 'red'):
            $m->{success} < $m->{total} ? colored("PARTIAL $m->{success}/$m->{total}", 'yellow') :
            colored('ok', 'green');
    }
};

step 'Add j to path', sub {
    print CATS::DevEnv::Detector::Utils::add_to_path(File::Spec->rel2abs('cmd'));
};
