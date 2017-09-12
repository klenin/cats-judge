package CATS::Judge::Config;

use strict;
use warnings;

use XML::Parser::Expat;
use CATS::Config;

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
) }
sub special_fields() { qw(checkers def_DEs defines DEs) }
sub security_fields() { qw(cats_password) }
sub de_fields() { qw(
    check compile encoding extension generate interactor_name run run_interactive runfile validate) }
sub param_fields() { required_fields, optional_fields, special_fields }

sub import {
    for (required_fields, optional_fields, special_fields, security_fields) {
        no strict 'refs';
        my $x = $_;
        *{"$_[0]::$_"} = sub { $_[0]->{$x} };
    }
}

sub new {
    my ($class) = shift;
    my $self = { defines => {}, DEs => {}, checkers => {}, def_DEs => {} };
    bless $self, $class;
    $self;
}

sub apply_defines {
    my ($self, $value) = @_;
    $value //= '';
    my $defines = $self->{defines};
    $value =~ s/$_/$defines->{$_}/g
        for sort { length $b <=> length $a || $a cmp $b } keys %$defines;
    $value;
}

sub _read_attributes {
    my ($self, $dest, $atts, @fields) = @_;
    for (@fields) {
        $dest->{$_} = $self->apply_defines($atts->{$_}) if exists $atts->{$_};
    }
}

sub read_part {
    my ($self, $source) = @_;

    my $handlers = {
        judge => sub {
            $self->_read_attributes($self, $_[0], required_fields, optional_fields);
        },
        security => sub {
            $self->_read_attributes($self, $_[0], security_fields);
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
    };

    my $parser = XML::Parser::Expat->new;
    $parser->setHandlers(Start => sub {
        my ($p, $el, %attrs) = @_;
        my $h = $handlers->{$el} or die "Unknown tag $el";
        $h->(\%attrs);
    });
    $parser->parse($source);
}

sub read_file {
    my ($self, $file, $overrides) = @_;
    $self->read_part($file);
    if ($overrides) {
        $self->{$_} = $overrides->{$_} for keys %$overrides;
    }
    defined $self->{$_} or die "config: undefined $_" for required_fields;
    $_ = File::Spec->rel2abs($_, cats_dir) for @{$self}{dir_fields()};
}

sub print_helper {
    my ($val, $keys, $depth, $bare) = @_;
    for my $k (sort @$keys) {
        print "$depth$k =" unless $bare;
        my $v = $val->{$k};
        if (ref $v) {
            print "\n";
            print_helper($v, [ keys %$v ], "$depth    ");
        }
        else {
            print $bare ? "$v\n" : " $v\n";
        }
    }
}

sub print_params {
    my ($self, $regexp, $bare) = @_;
    my $r = qr/$regexp/;
    print_helper($self, [ grep /$r/, keys %$self ], '', $bare);
}

1;
