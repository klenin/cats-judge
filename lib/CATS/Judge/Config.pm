package CATS::Judge::Config;

use strict;
use warnings;

use XML::Parser::Expat;

sub required_fields() { qw(name rundir workdir modulesdir report_file stdout_file formal_input_fname) }
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

    $self->{$_} or die "config: undefined $_" for required_fields;
}

1;
