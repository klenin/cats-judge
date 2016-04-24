use v5.10;
use strict;
use warnings;

use File::Copy qw(copy);
use File::Spec;
use Getopt::Long;
use IPC::Cmd;

use lib 'lib';
use CATS::DevEnv::Detector::Utils qw(globq run);

$| = 1;

sub usage
{
    my (undef, undef, $cmd) = File::Spec->splitpath($0);
    print <<"USAGE";
Usage:
    $cmd
    $cmd --step <num> ... [--devenv <devenv-filter>] [--verbose]
    $cmd --help|-?
USAGE
    exit;
}

GetOptions(
    \my %opts,
    'step=i@',
    'devenv=s',
    'verbose',
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

my $step_count = 0;

sub step($&) {
    my ($msg, $action) = @_;
    print ++$step_count, ". $msg ...";
    if (!%filter_steps || exists $filter_steps{$step_count}) {
        $action->();
        print " ok\n";
    }
    else {
        print " skipped\n";
    }
}

sub step_copy {
    my ($from, $to) = @_;
    step "Copying $from -> $to", sub {
        -e $to and die "Destination already exists: $to";
        copy($from, $to) or die $!;
    };
}

step 'Verifying', sub {
    -f 'judge.pl' && -d 'lib' or die 'Must run from cats-judge directory';
    -f 'config.xml' and die 'Seems to be already installed';
};

step 'Verifying git', sub {
    my $x = `git --version` or die 'Git not found';
    $x =~ /^git version/ or die "Git not found: $x";
};

step 'Verifying required modules', sub {
    my @bad = grep !eval "require $_; 1;", qw(DBI JSON::XS XML::Parser::Expat File::Copy::Recursive);
    die join "\n", 'Some required modules not found:', @bad, '' if @bad;
};

step 'Verifying optional modules', sub {
    my @bad = grep !eval "require $_; 1;", qw(FormalInput IPC::Run);
    warn join "\n", 'Some optional modules not found:', @bad, '' if @bad;
};

step 'Cloning sumbodules', sub {
    system('git submodule update --init');
    $? and die "Failed: $?, $!";
};

step 'Disabling Windows Error Reporting UI', sub {
    CATS::DevEnv::Detector::Utils::disable_windows_error_reporting_ui();
};

my @detected_DEs;
step 'Detecting development environments', sub {
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

my @p = qw(lib cats-problem CATS);
step_copy(File::Spec->catfile(@p, 'Config.pm.template'), File::Spec->catfile(@p, 'Config.pm'));

step_copy('config.xml.template', 'config.xml');

step 'Adding development environment paths to config', sub {
    @detected_DEs or return;
    open my $conf_in, '<', 'config.xml' or die "Can't open config.xml";
    open my $conf_out, '>', 'config.xml.tmp' or die "Can't open config.xml";
    my %path_idx;
    $path_idx{$_->{code}} = $_ for @detected_DEs;
    my $flag = 0;
    while (<$conf_in>) {
        $flag = $flag ? $_ !~ m/<!-- END -->/ : $_ =~ m/<!-- This code is touched by install.pl -->/;
        my ($code) = /de_code_autodetect="(\d+)"/;
        s/value="[^"]*"/value="$path_idx{$code}->{path}"/ if $flag && $code && $path_idx{$code};
        print $conf_out $_;
    }
    close $conf_in;
    close $conf_out;
    rename 'config.xml.tmp', 'config.xml';
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
    my $module_cache;
    parse_xml_file($module_name, Char => sub {
        my ($p, $string) = @_;
        $string =~ m/$cachedir.(.*).temp/ or return;
        $module_cache = $1;
    });
    $module_cache = File::Spec->catfile($cachedir, $module_cache);
    -e $module_cache or return;
    ((slurp_lines("$module_cache.des"))[2] // '') eq 'state:ready';
}

step 'Installing cats-modules', sub {
    require XML::Parser::Expat;
    # todo use CATS::Judge::Config
    my ($modulesdir, $cachedir) = get_dirs();
    my $cats_modules_dir = File::Spec->catfile(qw[lib cats-modules]);
    my @modules = map +{
        xml => globq(File::Spec->catfile($cats_modules_dir, $_, '*.xml')),
        dir => File::Spec->catfile($cats_modules_dir, $_),
        success => 0
    }, slurp_lines(File::Spec->catfile($cats_modules_dir, 'modules.txt'));
    my $jcmd = File::Spec->catfile('cmd', 'j.cmd');
    print "\n";
    for (@modules) {
        my ($ok, $err, $buf) = run command => [ $jcmd, '--problem', $_->{dir} ];
        $ok or print $err, next;
        print @$buf if $opts{verbose};
        my $module_name;
        parse_xml_file($_->{xml}, Start => sub {
            my ($p, $el, %atts) = @_;
            exists $atts{export} or return;
            my $name = File::Spec->catfile($modulesdir, "$atts{export}.xml");
            -e $name and $module_name = $name;
        });
        $module_name and check_module($module_name, $cachedir) or next;
        $_->{success} = 1;
        print "    $_->{dir} installed\n";
    }
    $_->{success} or print "    Failed to install: $_->{dir}\n" for @modules;
};
