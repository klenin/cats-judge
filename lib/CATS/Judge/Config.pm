package CATS::Judge::Config;

use strict;
use warnings;

use XML::Parser::Expat;
use CATS::Config;

sub dir_fields() { qw(workdir cachedir logdir rundir modulesdir) }
sub required_fields() { dir_fields, qw(name report_file stdout_file formal_input_fname) }
sub optional_fields() { qw(show_child_stdout save_child_stdout) }
sub special_fields() { qw(defines DEs checkers def_DEs) }
sub de_fields() { qw(compile run interactor_name run_interactive generate check runfile validate extension) }
sub param_fields() { required_fields, optional_fields, special_fields }

sub import {
    for (required_fields, optional_fields, special_fields) {
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

sub read_file {
    my ($self, $file, $overrides) = @_;

    my $defines = {};
    my $apply_defines = sub {
        my ($value) = @_;
        my $expr = shift // '';
        $expr =~ s/$_/$defines->{$_}/g for sort { length $b <=> length $a } keys %$defines;
        $expr;
    };

    my $parser = XML::Parser::Expat->new;
    $parser->setHandlers(Start => sub {
        my ($p, $el, %atts) = @_;
        my $h = {
            judge => sub {
                $self->{$_} = $atts{$_} for required_fields, optional_fields;
            },
            de => sub {
                my $dd = $self->def_DEs;
                for (split / /, $atts{'extension'} // '') {
                    die "Duplicate default extension $_ for DEs $dd->{$_} and $atts{code}" if $dd->{$_};
                    $dd->{$_} = $atts{code};
                }
                $self->DEs->{$atts{'code'}} =
                    { map { $_ => $apply_defines->($atts{$_}) } de_fields };
            },
            define => sub {
                $defines->{$atts{'name'}} = $apply_defines->($atts{'value'});
            },
            checker => sub {
                $self->checkers->{$atts{'name'}} = $apply_defines->($atts{'exec'});
            },
        }->{$el} or die "Unknown tag $el";
        $h->();
    });
    $parser->parse($file);

    $self->{defines} = $defines;

    $self->{$_} = $overrides->{$_} for keys %$overrides;
    defined $self->{$_} or die "config: undefined $_" for required_fields;
    $_ = File::Spec->rel2abs($_, cats_dir) for @{$self}{dir_fields()};
}

sub print_helper {
    my ($val, $keys, $depth) = @_;
    for my $k (sort @$keys) {
        print "$depth$k =";
        my $v = $val->{$k};
        if (ref $v) {
            print "\n";
            print_helper($v, [ keys %$v ], "$depth    ");
        }
        else {
            print " $v\n";
        }
    }
}

sub print_params {
    my ($self, $regexp) = @_;
    my $r = qr/$regexp/;
    print_helper($self, [ grep /$r/, keys %$self ], '');
}

1;
