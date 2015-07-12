package CATS::Judge::Config;

use strict;
use warnings;

use XML::Parser::Expat;
use CATS::Config;

sub dir_fields() { qw(rundir workdir logdir modulesdir) }
sub required_fields() { dir_fields(), qw(name report_file stdout_file formal_input_fname) }
sub optional_fields() { qw(show_child_stdout save_child_stdout) }
sub special_fields() { qw(defines DEs checkers) }
sub de_fields() { qw(compile run interactor_name run_interactive generate check runfile validate) }

sub import {
    for (required_fields, optional_fields, special_fields) {
        no strict 'refs';
        my $x = $_;
        *{"$_[0]::$_"} = sub { $_[0]->{$x} };
    }
}

sub new {
    my ($class) = shift;
    my $self = { defines => {}, DEs => {}, checkers => {} };
    bless $self, $class;
    $self;
}

sub read_file {
    my ($self, $file) = @_;

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

    defined $self->{$_} or die "config: undefined $_" for required_fields;
    $_ = File::Spec->rel2abs($_, cats_dir) for @{$self}{dir_fields()};
}

sub print_params {
    my ($self, $regexp) = @_;
    my $r = qr/$regexp/;
    for my $k (sort grep /$r/, keys %$self) {
        print "$k =";
        my $v = $self->{$k};
        ref $v or print(" $v\n"), next;
        print "\n";
        print "    $_ = $v->{$_}\n" for sort keys %$v;
    }
}

1;
