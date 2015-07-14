package CATS::Spawner;
use strict;
use warnings;

use CATS::Constants;
use CATS::Judge::Log;

$cats::tm_exit_process            = 'ExitProcess';
$cats::tm_time_limit_exceeded     = 'TimeLimitExceeded';
$cats::tm_memory_limit_exceeded   = 'MemoryLimitExceeded';
$cats::tm_write_limit_exceeded    = 'WriteLimitExceeded';
$cats::tm_abnormal_exit_process   = 'AbnormalExitProcess';
$cats::tm_idleness_limit_exceeded = 'IdleTimeLimitExceeded';

my @required_fields = qw(
    Application
    Parameters
    SecurityLevel
    CreateProcessMethod
    UserName
    UserTimeLimit
    DeadLine
    MemoryLimit
    WriteLimit
    UserTime
    PeakMemoryUsed
    Written
    TerminateReason
    ExitStatus
    SpawnerError
);

sub new {
    my ($class) = shift;
    my $self = { @_ }; #cfg => $params{cfg}, log => $params{log} };
    bless $self, $class;
    $self;
}

sub apply_params
{
    my ($str, $params) = @_;
    $str =~ s/%$_/$params->{$_}/g
        for sort { length $b <=> length $a } keys %$params;
    $str;
}

#move this to FileUtils.pm or Utils.pm
sub my_chdir
{
    my $self = shift;
    my $path = shift;
    my $log = $self->{log};
    unless (chdir($path))
    {
        $log->msg("couldn't set directory '$path': $!\n");
        return undef;
    }
    1;
}

sub dump_child_stdout
{
    my ($self, $duplicate_to) = @_;
    my $log = $self->{log};
    unless (open(FSTDOUT, '<', $self->{cfg}->{stdout_file}))
    {
        $log->msg("open failed: '%s' ($!)\n", $self->{cfg}->{stdout_file});
        return undef;
    }

    my $eol = 0;
    while (<FSTDOUT>)
    {
        if ($self->{cfg}->show_child_stdout) {
            print STDERR $_;
        }
        if ($self->{cfg}->save_child_stdout) {
            $log->dump_write($_);
        }
        if ($duplicate_to) {
            $$duplicate_to .= $_;
        }
        $eol = (substr($_, -2, 2) eq '\n');
    }
    if ($eol)
    {
        if ($self->{cfg}->show_child_stdout) {
            print STDERR "\n";
        }
        if ($self->{cfg}->save_child_stdout) {
            $log->dump_write("\n");
        }
        if ($duplicate_to) {
            $$duplicate_to .= $_;
        }
    }
    close FSTDOUT;
    1;
}

sub execute
{
    my ($self, $exec_str, $params, %rest) = @_;
    $self->my_chdir($self->{cfg}->rundir)
        or return undef;
    my $result = $self->execute_inplace($exec_str, $params, %rest);
    $self->my_chdir($self->{cfg}->workdir)
        or return undef;
    $result;
}

sub execute_inplace
{
    my ($self, $exec_str, $params, %rest) = @_;
    my $log = $self->{log};

    $exec_str = apply_params($exec_str, $params);
    $exec_str =~ s/[%]$_/$self->{cfg}->{$_}/eg for $self->{cfg}->param_fields();
    $exec_str =~ s/%deadline//g;

    # очистим stdout_file
    open(FSTDOUT, '>', $self->{cfg}->stdout_file) or return undef;
    close(FSTDOUT);

    $log->msg("> %s\n", $exec_str);
    my $rc = system($exec_str) >> 8;

    $self->dump_child_stdout($rest{duplicate_output});

    if ($rc)
    {
        $log->msg("exit code: $rc\n $!\n");
        return undef;
    }

    unless (open(FREPORT, '<', $self->{cfg}->report_file))
    {
        $log->msg("open failed: '%s' ($!)\n", $self->{cfg}->report_file);
        return undef;
    }

    # Пример файла отчета:
    #
    #--------------- Spawner report ---------------
    #Application:           test.exe
    #Parameters:            <none>
    #SecurityLevel:         0
    #CreateProcessMethod:   CreateProcessAsUser
    #UserName:              acm3
    #UserTimeLimit:         0.001000 (sec)
    #DeadLine:              Infinity
    #MemoryLimit:           20.000000 (Mb)
    #WriteLimit:            Infinity
    #----------------------------------------------
    #UserTime:              0.010014 (sec)
    #PeakMemoryUsed:        20.140625 (Mb)
    #Written:               0.000000 (Mb)
    #TerminateReason:       TimeLimitExceeded
    #ExitStatus:            0
    #----------------------------------------------
    #SpawnerError:          <none>

    my $skip = <FREPORT>;
    my $signature = <FREPORT>;
    if ($signature ne "--------------- Spawner report ---------------\n")
    {
        $log->msg("malformed spawner report: $signature\n");
        return undef;
    }

    my $checking = 0;
    my $sp_report = {};
    while (my $line = <FREPORT>) {
        if ($line =~ /^([a-zA-Z]+):\s+(.+)$/) {
            my $p = $1;
            my $v = $2;
            if ($v =~ /^(\d+\.?\d*)\s*\((.+)\)/) {
                $v = $1;
                #check $2
            }
            if ($p ne $required_fields[$checking]) {
                $log->msg("Expected $required_fields[$checking], got $p at pos $checking\n");
                return undef;
            }
            $checking++;
            $sp_report->{$p} = $v;
        }
    }
    close FREPORT;

    if ($sp_report->{SpawnerError} ne '<none>')
    {
        $log->msg("\tspawner error: $sp_report->{SpawnerError}\n");
        return undef;
    }

    if ($sp_report->{TerminateReason} eq $cats::tm_exit_process && $sp_report->{ExitStatus} ne '0')
    {
        $log->msg("process exit code: $sp_report->{ExitStatus}\n");
    }
    elsif ($sp_report->{TerminateReason} eq $cats::tm_time_limit_exceeded)
    {
        $log->msg("time limit exceeded\n");
    }
    elsif ($sp_report->{TerminateReason} eq $cats::tm_idleness_limit_exceeded)
    {
        $log->msg("idleness limit exceeded\n");
    }
    elsif ($sp_report->{TerminateReason} eq $cats::tm_write_limit_exceeded)
    {
        $log->msg("write limit exceeded\n");
    }
    elsif ($sp_report->{TerminateReason} eq $cats::tm_memory_limit_exceeded)
    {
        $log->msg("memory limit exceeded\n");
    }
    elsif ($sp_report->{TerminateReason} eq $cats::tm_abnormal_exit_process)
    {
        $log->msg("abnormal process termination. Process exit status: $sp_report->{ExitStatus}\n");
    }
    $log->msg(
        "-> UserTime: $sp_report->{UserTime} s | MemoryUsed: $sp_report->{PeakMemoryUsed} Mb | Written: $sp_report->{Written} Mb\n");

    $sp_report;
}

1;
