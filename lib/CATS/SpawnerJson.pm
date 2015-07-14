package CATS::SpawnerJson;
use strict;
use warnings;

use JSON::XS;
use base qw(CATS::Spawner);

my @required_fields = qw(
    Application
    CreateProcessMethod
    UserName
    TerminateReason
    ExitStatus
);

sub parse_report
{
    my ($self, $file) = @_;
    my $log = $self->{log};
    my $json = decode_json(join '', <$file>);
    my $sp_report = { report => $json };

    my $report_item = $json->[0];

    for my $item (@required_fields) {
        defined($sp_report->{$item} = $report_item->{$item})
            or return $log->msg("Required report field $item not found\n");
    }

    $sp_report->{SpawnerError} = join(' ', @{$report_item->{SpawnerError}}) || '<none>';
    $sp_report->{UserTime} = $report_item->{Result}->{Time};
    $sp_report->{PeakMemoryUsed} = $report_item->{Result}->{Memory};
    $sp_report->{Written} = $report_item->{Result}->{BytesWritten};
    $sp_report;
}

sub check_report
{
    my ($self, $sp_report) = @_;
    my $log = $self->{log};

    foreach my $report_item (@{$sp_report->{report}}) {
        $log->msg("-> Process: $report_item->{Application}\n");
        if (@{$report_item->{SpawnerError}})
        {
            $log->msg("\tspawner error: " . join(' ', $report_item->{SpawnerError}) . "\n");
            return undef;
        }

        if ($report_item->{TerminateReason} eq $cats::tm_exit_process && $sp_report->{ExitStatus} ne '0')
        {
            $log->msg("process exit code: $sp_report->{ExitStatus}\n");
        }
        elsif ($report_item->{TerminateReason} eq $cats::tm_time_limit_exceeded)
        {
            $log->msg("time limit exceeded\n");
        }
        elsif ($report_item->{TerminateReason} eq $cats::tm_idleness_limit_exceeded)
        {
            $log->msg("idleness limit exceeded\n");
        }
        elsif ($report_item->{TerminateReason} eq $cats::tm_write_limit_exceeded)
        {
            $log->msg("write limit exceeded\n");
        }
        elsif ($report_item->{TerminateReason} eq $cats::tm_memory_limit_exceeded)
        {
            $log->msg("memory limit exceeded\n");
        }
        elsif ($report_item->{TerminateReason} eq $cats::tm_abnormal_exit_process)
        {
            $log->msg("abnormal process termination. Process exit status: $report_item->{ExitStatus}\n");
        }
        $log->msg(
            "-> UserTime: $report_item->{Result}->{Time} s | MemoryUsed: $report_item->{Result}->{Memory} bytes | Written: $report_item->{Result}->{BytesWritten} bytes\n");
    }
    1;
}

1;
