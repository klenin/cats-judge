use v5.10;
use strict;
use warnings;

use File::Copy qw(copy);
use File::Spec;
use Getopt::Long;
use IPC::Cmd;
use List::Util qw(max);

use lib 'lib';
use CATS::DevEnv::Detector::Utils qw(globq run);
use CATS::ConsoleColor qw(colored);

$| = 1;

sub usage
{
    my (undef, undef, $cmd) = File::Spec->splitpath($0);
    print <<"USAGE";
Usage:
    $cmd
    $cmd --step <num> ...
        [--devenv <devenv-filter>] [--modules <modules-filter>]
        [--verbose] [--force]
    $cmd --help|-?
USAGE
    exit;
}

GetOptions(
    \my %opts,
    'step=i@',
    'devenv=s',
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

sub maybe_die {
    $opts{force} or die @_;
    print @_;
    print ' overridden by --force';
}

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

sub step_copy {
    my ($from, $to) = @_;
    step "Copy $from -> $to", sub {
        -e $to and maybe_die "Destination already exists: $to";
        copy($from, $to) or maybe_die $!;
    };
}

step 'Verify install', sub {
    -f 'judge.pl' && -d 'lib' or die 'Must run from cats-judge directory';
    -f 'config.xml' and maybe_die 'Seems to be already installed';
};

step 'Verify git', sub {
    my $x = `git --version` or die 'Git not found';
    $x =~ /^git version/ or die "Git not found: $x";
};

step 'Verify required modules', sub {
    my @bad = grep !eval "require $_; 1;", qw(Archive::Zip DBI JSON::XS XML::Parser::Expat File::Copy::Recursive);
    maybe_die join "\n", 'Some required modules not found:', @bad, '' if @bad;
};

step 'Verify optional modules', sub {
    my @bad = grep !eval "require $_; 1;", qw(FormalInput IPC::Run);
    warn join "\n", 'Some optional modules not found:', @bad, '' if @bad;
};

step 'Clone sumbodules', sub {
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
    for (globq(File::Spec->catfile(qw[lib CATS DevEnv Detector *.pm]))) {
        my ($name) = /(\w+)\.pm$/;
        next if $name =~ /^(Utils|Base)$/ || $opts{devenv} && $name !~ qr/$opts{devenv}/i;
        require $_;
        my $d = "CATS::DevEnv::Detector::$name"->new;
        printf "    Detecting %s:\n", $d->name;
        for (values %{$d->detect}){
            printf "      %s %-12s %s\n",
                ($_->{preferred} ? '*' : $_->{valid} ? ' ' : '?'), $_->{version}, $_->{path};
            push @detected_DEs, { path => $_->{path}, code => $d->code } if ($_->{preferred});
        }
    }
};

my $proxy;
step 'Detect proxy', sub {
    $proxy = CATS::DevEnv::Detector::Utils::detect_proxy() or return;
    print " $proxy ";
    $proxy = "http://$proxy";
};

my $platform;
step 'Detect platform', sub {
    if ($^O eq 'MSWin32') {
        $platform = 'win32';
    }
    elsif ($^O eq 'linux') {
        $platform = `uname -i` eq 'x86_64' ? 'linux-amd64' : 'linux-i386';
    }
    else {
        maybe_die "Unsupported platform: $^O";
    }
    print " $platform" if $platform;
};

my @p = qw(lib cats-problem CATS);
step_copy(File::Spec->catfile(@p, 'Config.pm.template'), File::Spec->catfile(@p, 'Config.pm'));

step_copy('config.xml.template', 'config.xml');

step 'Save configuration', sub {
    @detected_DEs || defined $proxy || defined $platform or return;
    open my $conf_in, '<', 'config.xml' or die "Can't open config.xml";
    open my $conf_out, '>', 'config.xml.tmp' or die "Can't open config.xml.tmp";
    my %path_idx;
    $path_idx{$_->{code}} = $_ for @detected_DEs;
    my $flag = 0;
    while (<$conf_in>) {
        s~(\s+proxy=")"~$1$proxy"~ if defined $proxy;
        my $sp = 'value="%workdir/spawner-bin/';
        s~(\s$sp)\w+~ $sp$platform~ if defined $platform;
        $flag = $flag ? $_ !~ m/<!-- END -->/ : $_ =~ m/<!-- This code is touched by install.pl -->/;
        my ($code) = /de_code_autodetect="(\d+)"/;
        s/value="[^"]*"/value="$path_idx{$code}->{path}"/ if $flag && $code && $path_idx{$code};
        print $conf_out $_;
    }
    close $conf_in;
    close $conf_out;
    rename 'config.xml.tmp', 'config.xml' or die "rename: $!";
};

sub parse_xml_file {
    my ($file, %handlers) = @_;
    my $xml_parser = XML::Parser::Expat->new;
    $xml_parser->setHandlers(%handlers);
    $xml_parser->parsefile($file);
}

sub get_dirs {
    -e 'config.xml' or die 'Missing config.xml';
    my ($modulesdir, $cachedir);
    parse_xml_file('config.xml', Start => sub {
        my ($p, $el, %atts) = @_;
        $el eq 'judge' or return;
        $modulesdir = $atts{modulesdir};
        $cachedir = $atts{cachedir};
        $p->finish;
    });
    ($modulesdir, $cachedir);
}

sub slurp_lines {
    my ($filename) = @_;
    open my $f, '<', $filename or return ();
    map { chomp; $_ } <$f>;
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
    -e $module_cache or return;
    ((slurp_lines("$module_cache.des"))[2] // '') eq 'state:ready';
}

step 'Install cats-modules', sub {
    require XML::Parser::Expat;
    # todo use CATS::Judge::Config
    my ($modulesdir, $cachedir) = get_dirs();
    my $cats_modules_dir = File::Spec->catfile(qw[lib cats-modules]);
    my @modules = map +{
        name => $_,
        xml => globq(File::Spec->catfile($cats_modules_dir, $_, '*.xml')),
        dir => File::Spec->catfile($cats_modules_dir, $_),
        success => 0
    }, grep !$opts{modules} || /$opts{modules}/,
        slurp_lines(File::Spec->catfile($cats_modules_dir, 'modules.txt'));
    my $jcmd = File::Spec->catfile('cmd', 'j.'. ($^O eq 'MSWin32' ? 'cmd' : 'sh'));
    print "\n";
    for my $m (@modules) {
        my ($ok, $err, $buf) = run command => [ $jcmd, 'install', '--problem', $m->{dir} ];
        $ok or print $err, next;
        print @$buf if $opts{verbose};
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
