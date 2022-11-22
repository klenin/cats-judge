package CATS::Judge::Config;

use strict;
use warnings;

use File::Spec;
use XML::Parser::Expat;

use CATS::Config;
use CATS::Constants;
use CATS::Spawner::Platform;

sub dir_fields() { qw(cachedir logdir modulesdir solutionsdir resultsdir rundir workdir) }
sub required_fields() {
    dir_fields, qw(
    api
    name
    cats_url
    sleep_time
    stderr_file
    stdout_file
    formal_input_fname
    polygon_url
    report_file
) }
sub optional_fields() { qw(
    columns
    confess
    log_dump_size
    no_certificate_check
    save_child_stderr
    save_child_stdout
    show_child_stderr
    show_child_stdout
    proxy
    restart_count
    runtime_stderr_size
) }
sub special_fields() { qw(checkers def_DEs defines DEs) }
sub security_fields() { qw(cats_password sp_password sp_user) }
sub compile_fields() { @cats::limits_fields }
sub default_limits_fields() { qw(deadline_add deadline_min idle_time) }
sub color_fields() { qw(
    child_stderr
    child_stdout
    install_fail
    install_ok
    install_start
    problem_cached
    testing_start
) }
sub de_fields() { qw(
    check
    compile
    compile_add_path
    compile_error_flag
    compile_precompile
    compile_rename_regexp
    enabled
    encoding
    extension
    generate
    interactor_name
    memory_handicap
    run
    run_exit_code
    run_interactive
    runfile
    safe
    validate
) }
sub param_fields() { required_fields, optional_fields, special_fields }

sub import {
    for (
        required_fields, optional_fields, special_fields, security_fields,
        qw(compile default_limits color)
    ) {
        no strict 'refs';
        my $x = $_;
        *{"$_[0]::$_"} = sub { $_[0]->{$x} };
    }
}

sub new {
    my ($class, %p) = @_;
    $p{root} or die 'root required';
    my $self = {
        root => $p{root}, defines => {
            '#rootdir' => $p{root},
            '#platform' => CATS::Spawner::Platform::get,
        }, DEs => {}, checkers => {}, def_DEs => {},
        include => { stack => [], overrides => $p{include_overrides} // {} },
    };
    bless $self, $class;
    $self;
}

sub apply_defines {
    my ($self, $value) = @_;
    $value //= '';
    my $defines = $self->{defines};
    $value =~ s/$_/$defines->{$_}/g
        for sort { length $b <=> length $a || $a cmp $b } keys %$defines;
    $value =~ s/#env:([a-zA-Z0-9_]+)/$ENV{$1} || die 'Unknown environment ', $1/eg;
    $value;
}

sub _read_attributes {
    my ($self, $dest, $atts, @fields) = @_;
    for (@fields) {
        $dest->{$_} = $self->apply_defines($atts->{$_}) if exists $atts->{$_};
    }
}

sub _check_color {
    my ($colors, $name) = @_;
    $colors->{$name} or return;
    my $c = $colors->{$name};
    Term::ANSIColor::colorvalid($c) or die "Invalid color for $name: '$c'";
}

sub load_part {
    my ($self, $source) = @_;

    my $handlers = {
        judge => sub {
            $self->_read_attributes($self, $_[0], required_fields, optional_fields);
        },
        security => sub {
            $self->_read_attributes($self, $_[0], security_fields);
        },
        compile => sub {
            $self->_read_attributes($self->{compile} //= {}, $_[0], compile_fields);
        },
        default_limits => sub {
            $self->_read_attributes($self->{default_limits} //= {}, $_[0], default_limits_fields);
        },
        color => sub {
            $self->_read_attributes($self->{color} //= {}, $_[0], color_fields);
            _check_color($self->{color}, $_) for color_fields;
        },
        de => sub {
            my $code = $_[0]->{code} or die 'de: code required';
            my $dd = $self->def_DEs;
            for (split / /, $_[0]->{extension} // '') {
                die "duplicate default extension $_ for DEs $dd->{$_} and $code" if $dd->{$_};
                $dd->{$_} = $code;
            }
            $self->_read_attributes($self->DEs->{$code} //= {}, $_[0], de_fields);
        },
        define => sub {
            $_[0]->{name} or die 'define: name required';
            defined $_[0]->{value} or die "define $_[0]->{name}: value required";
            $self->{defines}->{$_[0]->{name}} = $self->apply_defines($_[0]->{value});
        },
        checker => sub {
            $_[0]->{name} or die 'checker: name required';
            $_[0]->{exec} or die "checker $_[0]->{name}: exec required";
            $self->checkers->{$_[0]->{name}} = $self->apply_defines($_[0]->{exec});
        },
        include => sub {
            $_[0]->{file} or die 'include: file required';
            $self->load_file($self->apply_defines($_[0]->{file}));
        },
    };

    my $parser = XML::Parser::Expat->new;
    $parser->setHandlers(Start => sub {
        my ($p, $el, %attrs) = @_;
        my $h = $handlers->{$el} or die "unknown tag $el";
        $h->(\%attrs);
    });
    $parser->parse($source);
}

sub load_file {
    my ($self, $file) = @_;

    my $stack = $self->{include}->{stack};
    die 'circular include: ', join ' -> ', @$stack, $file if grep $_ eq $file, @$stack;
    push @$stack, $file;

    if (my $ov = $self->{include}->{overrides}->{$file}) {
        $self->load_part($ov);
    }
    else {
       my $full_name = File::Spec->catfile($self->{root}, $file);
       open my $fh, '<', $full_name or die "unable to open $full_name: $!";
       $self->load_part($fh);
    }
    pop @$stack;
}

sub _override {
    my ($self, $override) = @_;
    $override or return;
    for my $k (keys %$override) {
        my $h = \$self;
        $h = \$$h->{$_} for split '\.', $k;
        $$h = $self->apply_defines($override->{$k});
    }
}

sub load {
    my ($self, %p) = @_;
    $p{file} ? $self->load_file($p{file}) :
    $p{src} ? $self->load_part($p{src}) :
    die 'file or src required';
    $self->_override($p{override});
    defined $self->{$_} or die "config: undefined $_" for required_fields;
    $_ = File::Spec->rel2abs($_, cats_dir) for @{$self}{dir_fields()};
    for (keys %{$self->DEs}) {
        $self->DEs->{$_}->{enabled} or delete $self->DEs->{$_};
    }
    for (keys %{$self->def_DEs}) {
        $self->DEs->{$self->def_DEs->{$_}} or delete $self->def_DEs->{$_};
    }
    $self;
}

sub print_helper {
    my ($val, $regexps, $keys, $depth, $bare) = @_;
    my ($regexp, @rest) = @$regexps;
    for my $k (sort $regexp ? grep /$regexp/, @$keys : @$keys) {
        print "$depth$k =" unless $bare;
        my $v = $val->{$k};
        if (ref $v eq 'HASH') {
            print "\n" unless $bare;
            print_helper($v, \@rest, [ keys %$v ], "$depth    ", $bare);
        }
        elsif (!ref $v) {
            print $bare ? "$v\n" : " $v\n";
        }
    }
}

sub print_params {
    my ($self, $regexp, $bare) = @_;
    print_helper($self, [ map qr/$_/, split '/', $regexp ], [ keys %$self ], '', $bare);
}

sub apply_params {
    my ($str, $params) = @_;
    $str =~ s[%$_][$params->{$_} // '']eg
        for sort { length $b <=> length $a } keys %$params;
    $str;
}

1;
