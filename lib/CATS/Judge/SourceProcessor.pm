package CATS::Judge::SourceProcessor;

use strict;
use warnings;

use File::Spec;

use CATS::Constants;
use CATS::Judge::Config ();

*apply_params = *CATS::Judge::Config::apply_params;

sub new {
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
    $self->cfg && $self->fu && $self->log && $self->sp or die;

    $self->{de_idx} = {};
    $self->{de_idx}->{$_->{id}} = $_ for values %{$self->cfg->DEs};

    $self;
}

sub cfg { $_[0]->{cfg} }
sub fu { $_[0]->{fu} }
sub log { $_[0]->{log} }
sub sp { $_[0]->{sp} }

sub property {
    my ($self, $name, $de_id) = @_;
    exists $self->{de_idx}->{$de_id} or die "undefined de_id: $de_id";
    $self->{de_idx}->{$de_id}->{$name};
}

sub memory_handicap {
    my ($self, $de_id) = @_;
    $self->{de_idx}->{$de_id}->{memory_handicap} // 0;
}

# sources: [ { de_id, code } ]
sub unsupported_DEs {
    my ($self, $sources) = @_;
    map { $_->{code} => 1 } grep !exists $self->{de_idx}->{$_->{de_id}}, @$sources;
}

# source: { de_id, name_parts }
# => undef | $cats::st_testing | $cats::st_compilation_error
sub compile {
    my ($self, $source, $opt) = @_;
    my $de_id = $source->{de_id} or die;
    my $name_parts = $source->{name_parts} or die;
    my $de = $self->{de_idx}->{$de_id} or die "undefined de_id: $de_id";

    defined $de->{compile} or return;
    # Empty string -> no compilation needed.
    $de->{compile} or return $cats::st_testing;

    my %env;
    if (my $add_path = $self->property(compile_add_path => $de_id)) {
        my $path = apply_params($add_path, { %$name_parts, PATH => $ENV{PATH} });
        %env = (env => { PATH => $path });
    }
    my $sp_report = $self->sp->run_single({
        ($opt->{section} ? (section => $cats::log_section_compile) : ()),
        encoding => $de->{encoding},
        %env },
        apply_params($de->{compile}, $name_parts)
    ) or return;
    $sp_report->tr_ok or return;

    my $ok = $sp_report->{exit_code} == 0;

    if ($ok && $de->{compile_error_flag}) {
        my $re = qr/\Q$cats::log_section_compile\E\n\Q$de->{compile_error_flag}\E/m;
        $ok = 0 if $self->log->get_dump =~ $re;
    }

    if ($ok && $de->{runfile}) {
        my $fn = apply_params($de->{runfile}, $name_parts);
        -f File::Spec->catfile($self->cfg->rundir, $fn) or do {
            $self->log->msg("Runfile '$fn' not created\n");
            $ok = 0;
        };
    }

    $ok or $self->log->msg("compilation error\n");
    $ok ? $cats::st_testing : $cats::st_compilation_error;
}

1;
