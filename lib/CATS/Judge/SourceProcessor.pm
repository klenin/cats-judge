package CATS::Judge::SourceProcessor;

use strict;
use warnings;

use File::Spec;

use CATS::Constants;
use CATS::Judge::Config ();
use CATS::Spawner::Const ':all';

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

# ps: { de_id, code }
sub require_property {
    my ($self, $name, $ps, $opts) = @_;
    my $value = $self->property($name, $ps->{de_id})
        or return $self->log->msg("No '%s' action for DE: %s\n",
            $name, $ps->{code} // 'id=' . $ps->{de_id});
    $ps->{name_parts} or return $self->log->msg("No name parts\n");
    apply_params($value, { %{$ps->{name_parts}}, %$opts });
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

    my $compile_limits = $self->cfg->compile;
    my %limits = map { $compile_limits->{$_} ? ($_ => $compile_limits->{$_}) : () }
        @cats::limits_fields;
    $limits{deadline} = $limits{time_limit} if $limits{time_limit};

    my $sp_report = $self->sp->run_single({
        ($opt->{section} ? (section => $cats::log_section_compile) : ()),
        encoding => $de->{encoding},
        %limits, %env },
        apply_params($de->{compile}, $name_parts)
    ) or return;

    return if @{$sp_report->errors} ||
        0 == grep $sp_report->{terminate_reason} == $_,
            $TR_OK, $TR_TIME_LIMIT, $TR_MEMORY_LIMIT, $TR_WRITE_LIMIT;

    my $ok = $sp_report->ok;

    if ($ok && $de->{compile_error_flag}) {
        my $re = qr/\Q$cats::log_section_start_prefix$cats::log_section_compile\E\n\Q$de->{compile_error_flag}\E/m;
        $ok = 0 if $self->log->get_dump =~ $re;
    }

    if ($ok && $de->{runfile}) {
        my $fn = apply_params($de->{runfile}, $name_parts);
        -f File::Spec->catfile($self->cfg->rundir, $fn) or do {
            $self->log->msg("Runfile '$fn' not created\n");
            $ok = 0;
        };
    }

    return $cats::st_testing if $ok;

    if ($de->{compile_rename_regexp} && !$opt->{renamed}) {
        my $re = qr/\Q$cats::log_section_start_prefix$cats::log_section_compile\E.*$de->{compile_rename_regexp}/ms;
        if (my ($new_name) = $self->log->get_dump =~ $re) {
            $self->log->msg("Compiler requires rename to '$new_name'\n");
            $self->fu->copy(map [ $self-> cfg->rundir, $_ ], $name_parts->{full_name}, $new_name) or return;
            ($name_parts->{name}) = ($new_name =~ /^(\w+)(?:\.\w+)?$/);
            $name_parts->{full_name} = $new_name;
            return $self->compile($source, { %$opt, renamed => 1 });
        }
    }
    $self->log->msg("compilation error\n");
    $cats::st_compilation_error;
}

sub get_limits {
    my ($self, $ps, $problem) = @_;
    $problem //= {};
    my %res = map { $_ => $ps->{"req_$_"} || $ps->{"cp_$_"} || $ps->{$_} || $problem->{$_} }
        @cats::limits_fields;
    $res{deadline} = $res{time_limit}
        if $res{time_limit} && (!defined $ENV{SP_DEADLINE} || $res{time_limit} > $ENV{SP_DEADLINE});
    if ($res{memory_limit} && $ps->{de_id}) {
        my $mh = $self->property(memory_handicap => $ps->{de_id}) // 0;
	if ($mh >= 0) {
            $res{memory_limit} += $mh;
	}
	else {
            delete $res{memory_limit}
	}
    }
    $res{write_limit} = $res{write_limit} . 'B' if $res{write_limit};
    %res;
}

1;
