#!perl -w
use v5.10;
use strict;

use File::Spec;
use constant FS => 'File::Spec';
use File::NCopy qw(copy);

use lib 'lib';
use CATS::Constants;
use CATS::Utils qw(split_fname);
use CATS::Judge::Config;
use CATS::Judge::Log;
use CATS::Judge::Server;

use CATS::Spawner;

use open IN => ':crlf', OUT => ':raw';


my $cfg = CATS::Judge::Config->new;
my $log = CATS::Judge::Log->new;
my $judge;
my $spawner;
my %judge_de_idx;

my $problem_sources;

sub log_msg { $log->msg(@_); }

sub get_run_key {
    return {
        $cats::rm_default => 'run',
        $cats::rm_interactive => 'run_interactive',
    }->{$_[0] // $cats::rm_default};
}

sub get_cmd {
    my ($action, $de_id) = @_;
    exists $judge_de_idx{$de_id} or die "undefined de_id: $de_id";
    $judge_de_idx{$de_id}->{$action};
}

sub get_cfg_define {
    my $name = shift;
    my $value = $cfg->defines->{$name};
    if (!$value) {
        log_msg("unknown define name: $name\n");
    }
    $value;
}

sub get_std_checker_cmd
{
    my $std_checker_name = shift;

    if (!defined $cfg->checkers->{$std_checker_name}) {
        log_msg("unknown std checker: $std_checker_name\n");
        return undef;
    }

     $cfg->checkers->{$std_checker_name};
}


sub write_to_file
{
    my ($file_name, $src) = @_;

    unless (open(F, ">$file_name")) {
        log_msg("open failed: '$file_name' ($!)\n");
        return undef;
    }

    print F $src;
    close F;
    1;
}

sub recurse_dir
{
    my $dir = shift;

    chmod 0777, $dir;
    unless(opendir DIR, $dir)
    {
        log_msg("opendir $dir: $!\n");
        return 0;
    }

    my @files = grep {! /^\.\.?$/} readdir DIR;
    closedir DIR;

    my $res = 1;
    for (@files) {
        my $f = "$dir/$_";
        if (-f $f || -l $f) {
            unless (unlink $f) {
                log_msg("rm $f: $!\n");
                $res = 0;
            }
        }

        elsif (-d $f && ! -l $f) {
            recurse_dir($f)
                or $res = 0;

            unless (rmdir $f) {
                log_msg("rm $f: $!\n");
                $res = 0;
            }
        }
    }
    $res;
}


sub expand
{
    my @args;

    for (@_) {
        push @args, glob;
    }
    @args;
}


sub my_remove
{
    my @files = expand @_;
    my $res = 1;
    for (@files)
    {
        if (-f $_ || -l $_) {
            for my $retry (0..9) {
                -f $_ || -l $_ or last;
                $retry and log_msg("rm: retry $retry: $_\n");
                unless (unlink $_) {
                    log_msg("rm $_: $!\n");
                    $res = 0;
                }
                $retry and sleep 1;
            }
        }
        elsif (-d $_)
        {
            recurse_dir($_)
                or $res = 0;

            unless (rmdir $_) {
                log_msg("rm $_: $!\n");
                $res = 0;
            }
        }
    }
    $res;
}


sub my_chdir
{
    my $path = shift;

    unless (chdir($path))
    {
        log_msg("couldn't set directory '$path': $!\n");
        return undef;
    }
    1;
}


sub my_mkdir
{
    my $path = shift;

    my_remove($path)
        or return undef;

    unless (mkdir($path, 0755))
    {
        log_msg("couldn't create directory '$path': $!\n");
        return undef;
    }
    1;
}


sub my_copy
{
    my ($src, $dest) = @_;
    #return 1
    $src = File::Spec->canonpath($src);
    $dest = File::Spec->canonpath($dest);
    if (copy \1, $src, $dest) { return 1; }
    use Carp;
    log_msg "copy failed: 'cp $src $dest' '$!' " . Carp::longmess('') . "\n";
    return undef;
}


sub my_safe_copy
{
    my ($src, $dest, $pid) = @_;
    $src = File::Spec->canonpath($src);
    $dest = File::Spec->canonpath($dest);
    return 1 if copy \1, $src, $dest;
    log_msg "copy failed: 'cp $src $dest' $!, trying to reinitialize\n";
    # Возможно, что кеш задачи был повреждён, либо изменился импротированный модуль
    # Попробуем переинициализировать задачу. Если и это не поможет -- вылетаем.
    initialize_problem($pid);
    my_copy($src, $dest);
    die 'REINIT';
}

sub clear_rundir
{
    my_remove $cfg->rundir . '/*'
}


sub apply_params
{
    my ($str, $params) = @_;
    $str =~ s/%$_/$params->{$_}/g
        for sort { length $b <=> length $a } keys %$params;
    $str;
}

sub save_problem_description
{
    my ($pid, $title, $date, $state) = @_;

    my $fn = "tests/$pid.des";
    open my $desc, '>', $fn
        or return log_msg("open failed: '$fn' ($!)\n");

    print $desc join "\n", "title:$title", "date:$date", "state:$state";
    close $desc;
    1;
}


sub get_special_limits
{
    my ($ps) = @_;
    my %limits = (
        tl => $ps->{time_limit}, d => $ps->{time_limit},
        ml => $ps->{memory_limit},
    );
    join ' ', map "-$_:$limits{$_}", grep $limits{$_}, keys %limits,
}


sub generate_test
{
    my ($pid, $test, $input_fname) = @_;
    die 'generated' if $test->{generated};

    my ($ps) = grep $_->{id} == $test->{generator_id}, @$problem_sources or die;

    clear_rundir or return undef;

    my_copy("tests/$pid/temp/$test->{generator_id}/*", $cfg->rundir)
        or return undef;

    my $generate_cmd = get_cmd('generate', $ps->{de_id})
        or do { print "No generate cmd for: $ps->{de_id}\n"; return undef; };
    my ($vol, $dir, $fname, $name, $ext) = split_fname($ps->{fname});

    my $redir = '';
    my $out = $ps->{output_file} // $input_fname;
    if ($out =~ /^\*STD(IN|OUT)$/)
    {
        $test->{gen_group} and return undef;
        $out = 'stdout1.txt';
        $redir = " -so:$out -ho:1";
    }
    my $sp_report = $spawner->execute(
        $generate_cmd, {
        full_name => $fname, name => $name,
        limits => get_special_limits($ps),
        args => $test->{param} // '', redir => $redir }
    ) or return undef;

    if ($sp_report->{TerminateReason} ne $cats::tm_exit_process || $sp_report->{ExitStatus} ne '0')
    {
        return undef;
    }
    $out;
}


sub generate_test_group
{
    my ($pid, $test, $tests) = @_;
    $test->{gen_group} or die 'gen_group';
    return 1 if $test->{generated};
    my $out = generate_test($pid, $test, 'in');
    unless ($out)
    {
        log_msg("failed to generate test group $test->{gen_group}\n");
        return undef;
    }
    $out =~ s/%n/%d/g;
    $out =~ s/%0n/%02d/g;
    #$out =~ s/%(0*)n/length($1) ? '%0' . length($1) . 'd' : '%d'/eg;
    for (@$tests)
    {
        next unless ($_->{gen_group} || 0) == $test->{gen_group};
        $_->{generated} = 1;
        my_copy($cfg->rundir . sprintf("/$out", $_->{rank}), "tests/$pid/$_->{rank}.tst")
            or return undef;
    }
    1;
}


sub input_or { $_[0] eq '*STDIN' ? 'input.txt' : $_[1] }
sub output_or { $_[0] eq '*STDOUT' ? 'output.txt' : $_[1] }

sub input_or_default { FS->catfile($cfg->rundir, input_or($_[0], $_[0])) }
sub output_or_default { FS->catfile($cfg->rundir, output_or($_[0], $_[0])) }

sub input_output_redir {
    input_redir => input_or($_[0], ''), output_redir => output_or($_[1], ''),
}

sub interactor_name_or_default {
    interactor_name => get_cmd("interactor_name", $_[0]) ||
        get_cfg_define("#default_interactor_name"),
}

sub validate_test
{
    my ($pid, $test, $path_to_test) = @_;
    my $in_v_id = $test->{input_validator_id};
    if ($in_v_id) {
        clear_rundir or return undef;
        
        my ($validator) = grep $_->{id} == $in_v_id, @$problem_sources or die;
        my_copy($path_to_test, $cfg->rundir) and
        my_copy("tests/$pid/temp/$in_v_id/*", $cfg->rundir)
            or return undef;
            
        my $validate_cmd = get_cmd('validate', $validator->{de_id})
            or do { print "No validate cmd for: $validator->{de_id}\n"; return undef; };
        my ($vol, $dir, $fname, $name, $ext) = split_fname($validator->{fname});
        my ($t_vol, $t_dir, $t_fname, $t_name, $t_ext) = split_fname($path_to_test);
    
        my $sp_report = $spawner->execute(
            $validate_cmd, {
            full_name => $fname, name => $name,
            limits => get_special_limits($validator),
            test_input => $t_fname
            }
        ) or return undef;
    
        if ($sp_report->{TerminateReason} ne $cats::tm_exit_process || $sp_report->{ExitStatus} ne '0')
        {
            return undef;
        }
    }
        
    1;
}

sub prepare_tests
{
    my ($pid, $input_fname, $output_fname, $tlimit, $mlimit, $run_method) = @_;
    my $tests = $judge->get_problem_tests($pid);

    if (!@$tests) {
        log_msg("no tests defined\n");
        return undef;
    }

    for my $t (@$tests)
    {
        # создаем входной файл теста
        if (defined $t->{in_file})
        {
            write_to_file("tests/$pid/$t->{rank}.tst", $t->{in_file})
                or return undef;
        }
        elsif (defined $t->{generator_id})
        {
            if ($t->{gen_group})
            {
                generate_test_group($pid, $t, $tests)
                    or return undef;
            }
            else
            {
                my $out = generate_test($pid, $t, $input_fname)
                    or return undef;
                my_copy($cfg->rundir . "/$out", "tests/$pid/$t->{rank}.tst")
                    or return undef;
            }
        }
        else
        {
            log_msg("no input file defined for test #$t->{rank}\n");
            return undef;
        }

        validate_test($pid, $t, "tests/$pid/$t->{rank}.tst") or
            return log_msg("input validation failed: #$t->{rank}\n");
        # создаем выходной файл теста
        if (defined $t->{out_file})
        {
            write_to_file("tests/$pid/$t->{rank}.ans", $t->{out_file})
                or return undef;
        }
        elsif (defined $t->{std_solution_id})
        {
            my ($ps) = grep $_->{id} == $t->{std_solution_id}, @$problem_sources;

            clear_rundir or return undef;

            my_copy("tests/$pid/temp/$t->{std_solution_id}/*", $cfg->rundir)
                or return undef;

            my_copy("tests/$pid/$t->{rank}.tst", input_or_default($input_fname))
                or return undef;

            my $run_key = get_run_key($run_method);
            my $run_cmd = get_cmd($run_key, $ps->{de_id})
                or return log_msg("No '$run_key' action for DE: $ps->{code}\n");

            my ($vol, $dir, $fname, $name, $ext) = split_fname($ps->{fname});

            my $sp_report = $spawner->execute($run_cmd, {
                full_name => $fname,
                name => $name,
                time_limit => $ps->{time_limit} || $tlimit,
                memory_limit => $ps->{memory_limit} || $mlimit,
                deadline => ($ps->{time_limit} ? "-d:$ps->{time_limit}" : ''),
                interactor_name_or_default($ps->{de_id}),
                input_output_redir($input_fname, $output_fname),
            }) or return undef;

            if ($sp_report->{TerminateReason} ne $cats::tm_exit_process || $sp_report->{ExitStatus} ne '0')
            {
                return undef;
            }

            my_copy(output_or_default($output_fname), "tests/$pid/$t->{rank}.ans")
                or return undef;
        }
        else
        {
            log_msg("no output file defined for test #$t->{rank}\n");
            return undef;
        }
    }

    1;
}


sub prepare_modules
{
    my ($stype) = @_;
    # выбрать модули *в порядке заливки*
    for my $m (grep $_->{stype} == $stype, @$problem_sources)
    {
        my (undef, undef, $fname, $name, undef) = split_fname($m->{fname});
        log_msg("module: $fname\n");
        write_to_file($cfg->rundir . "/$fname", $m->{src})
            or return undef;

        # в данном случае ничего страшного, если compile_cmd нету,
        # это значит, что модуль компилировать не надо (de_code=1)
        my $compile_cmd = get_cmd('compile', $m->{de_id})
            or next;
        $spawner->execute($compile_cmd, { full_name => $fname, name => $name })
            or return undef;
    }
    1;
}

sub initialize_problem
{
    my $pid = shift;

    my $p = $judge->get_problem($pid);

    save_problem_description($pid, $p->{title}, $p->{upload_date}, 'not ready')
        or return undef;

    # компилируем вспомогательные программы (эталонные решения, генераторы тестов, программы проверки)
    my_mkdir("tests/$pid")
        or return undef;

    my_mkdir("tests/$pid/temp")
        or return undef;

    my %main_source_types;
    $main_source_types{$_} = 1 for keys %cats::source_modules;

    for my $ps (grep $main_source_types{$_->{stype}}, @$problem_sources)
    {
        clear_rundir or return undef;

        prepare_modules($cats::source_modules{$ps->{stype}} || 0)
            or return undef;

        my ($vol, $dir, $fname, $name, $ext) = split_fname($ps->{fname});
        write_to_file($cfg->rundir . "/$fname", $ps->{src})
            or return undef;

        if (my $compile_cmd = get_cmd('compile', $ps->{de_id}))
        {
            my $sp_report = $spawner->execute($compile_cmd, { full_name => $fname, name => $name })
                or return undef;
            if ($sp_report->{TerminateReason} ne $cats::tm_exit_process || $sp_report->{ExitStatus} ne '0')
            {
                log_msg("*** compilation error ***\n");
                return undef;
            }
        }

        if ($ps->{stype} == $cats::generator && $p->{formal_input}) {
           write_to_file($cfg->rundir . '/' . $cfg->formal_input_fname, $p->{formal_input})
              or return undef;
        }

        my_mkdir("tests/$pid/temp/$ps->{id}")
            or return undef;

        my_copy($cfg->rundir . '/*', "tests/$pid/temp/$ps->{id}")
            or return undef;
    }
    prepare_tests($pid, $p->{input_file}, $p->{output_file}, $p->{time_limit},
        $p->{memory_limit}, $p->{run_method})
        or return undef;

    save_problem_description($pid, $p->{title}, $p->{upload_date}, 'ready')
        or return undef;

    1;
}


my %inserted_details;
my %test_run_details;

sub insert_test_run_details
{
    my %p = (%test_run_details, @_);
    for ($inserted_details{ $p{test_rank} })
    {
        return if $_;
        $_ = $p{result};
    }
    $judge->insert_req_details(\%p);
}


sub run_checker
{
    my %p = @_;

    my $problem = $p{problem};

    my $i = input_or_default($problem->{input_file});
    my $o = output_or_default($problem->{output_file});
    my $a = "$p{rank}.ans";

    my $checker_params = {
        test_input => $i,
        test_output => $o,
        test_answer => $a,
        checker_args => qq~"$a" "$o" "$i"~,
    };

    my $checker_cmd;
    if (defined $problem->{std_checker})
    {
        $checker_cmd = get_std_checker_cmd($problem->{std_checker})
            or return undef;
    }
    else
    {
        my ($ps) = grep $_->{id} == $problem->{checker_id}, @$problem_sources;

        my_safe_copy("tests/$problem->{id}/temp/$problem->{checker_id}/*", $cfg->rundir, $problem->{id})
            or return undef;

        (undef, undef, undef, $checker_params->{name}, undef) =
            split_fname($checker_params->{full_name} = $ps->{fname});
        $cats::source_modules{$ps->{stype}} || 0 == $cats::checker_module
            or die "Bad checker type $ps->{stype}";
        $checker_params->{checker_args} =
            $ps->{stype} == $cats::checker ? qq~"$a" "$o" "$i"~ : qq~"$i" "$o" "$a"~;

        $checker_params->{limits} = get_special_limits($ps);

        $checker_cmd = get_cmd('check', $ps->{de_id})
            or return log_msg("No 'check' action for DE: $ps->{code}\n");
    }

    my $sp_report;
    for my $c (\$test_run_details{checker_comment})
    {
        $$c = undef;
        $sp_report = $spawner->execute($checker_cmd, $checker_params, duplicate_output => $c)
            or return undef;
        #Encode::from_to($$c, 'cp866', 'utf8');
        # обрезать для надёжности, чтобы влезло в поле БД
        $$c = substr($$c, 0, 199) if defined $$c;
    }

    # checked only once?
    $sp_report->{TerminateReason} eq $cats::tm_exit_process or return undef;

    $sp_report;
}


sub filter_hash
{
    my $hash = shift;
    map { $_ => $hash->{$_} } @_;
}


sub run_single_test
{
    my %p = @_;
    my $problem = $p{problem};

    log_msg("[test $p{rank}]\n");
    $test_run_details{test_rank} = $p{rank};
    $test_run_details{checker_comment} = '';

    clear_rundir or return undef;

    my $pid = $problem->{id};

    my_safe_copy("solutions/$p{sid}/*", $cfg->rundir, $pid)
        or return undef;
    my_safe_copy(
        "tests/$problem->{id}/$p{rank}.tst",
        input_or_default($problem->{input_file}), $pid)
        or return undef;

    my $run_key = get_run_key($problem->{run_method});
    my $run_cmd = get_cmd($run_key, $p{de_id})
        or return log_msg("No '$run_key' action for DE: $judge_de_idx{$p{de_id}}->{code}\n");

    my $exec_params = {
        filter_hash($problem, qw/name full_name time_limit memory_limit output_file/),
        input_output_redir(@$problem{qw(input_file output_file)}),
        interactor_name_or_default($p{de_id}),
        test_rank => sprintf('%02d', $p{rank}),
    };
    $exec_params->{memory_limit} += $p{memory_handicap} || 0;
    {
        my $sp_report = $spawner->execute($run_cmd, $exec_params) or return undef;

        $test_run_details{time_used} = $sp_report->{UserTime};
        $test_run_details{memory_used} = int($sp_report->{PeakMemoryUsed} * 1024 * 1024);
        $test_run_details{disk_used} = int($sp_report->{Written} * 1024 * 1024);

        for ($sp_report->{TerminateReason})
        {
            if ($_ eq $cats::tm_exit_process)
            {
                if ($sp_report->{ExitStatus} ne '0')
                {
                    $test_run_details{checker_comment} = $sp_report->{ExitStatus};
                    return $cats::st_runtime_error;
                }
            }
            else
            {
                return $cats::st_runtime_error         if $_ eq $cats::tm_abnormal_exit_process;
                return $cats::st_time_limit_exceeded   if $_ eq $cats::tm_time_limit_exceeded;
                return $cats::st_idleness_limit_exceeded if $_ eq $cats::tm_idleness_limit_exceeded;
                return $cats::st_memory_limit_exceeded if $_ eq $cats::tm_memory_limit_exceeded;
                return $cats::st_security_violation    if $_ eq $cats::tm_write_limit_exceeded;

                log_msg("unknown terminate reason: $_\n");
                return undef;
            }
        }
    }
    my_safe_copy(
        "tests/$problem->{id}/$p{rank}.tst",
        input_or_default($problem->{input_file}), $problem->{id})
        or return undef;
    my_safe_copy("tests/$problem->{id}/$p{rank}.ans", $cfg->rundir . "/$p{rank}.ans", $problem->{id})
        or return undef;
    {
        my $sp_report = run_checker(problem => $problem, rank => $p{rank})
            or return undef;

        my $result = {
            0 => $cats::st_accepted,
            1 => $cats::st_wrong_answer,
            2 => $cats::st_presentation_error
        }->{$sp_report->{ExitStatus}}
            // return log_msg("checker error (exit code '$sp_report->{ExitStatus}')\n");
        log_msg("OK\n") if $result == $cats::st_accepted;
        $result;
    }
}


sub test_solution {
    my ($r) = @_;
    my ($sid, $de_id) = ($r->{id}, $r->{de_id});

    log_msg("Testing solution: $sid for problem: $r->{problem_id}\n");
    my $problem = $judge->get_problem($r->{problem_id});

    my $memory_handicap = $judge_de_idx{$de_id}->{memory_handicap};

    ($problem->{checker_id}) = map $_->{id}, grep
        { ($cats::source_modules{$_->{stype}} || -1) == $cats::checker_module }
        @$problem_sources;

    if (!defined $problem->{checker_id} && !defined $problem->{std_checker})
    {
        log_msg("no checker defined!\n");
        return undef;
    }

    $judge->delete_req_details($sid);
    %test_run_details = (req_id => $sid, test_rank => 1);
    %inserted_details = ();

    (undef, undef, $problem->{full_name}, $problem->{name}, undef) = split_fname($r->{fname});

    my $res = undef;
    my $failed_test = undef;

    for (0..1)
    {
    my $r = eval
    {
    clear_rundir or return undef;

    prepare_modules($cats::solution_module) or return undef;
    write_to_file($cfg->rundir . "/$problem->{full_name}", $r->{src})
        or return undef;

    my $compile_cmd = get_cmd('compile', $de_id);
    defined $compile_cmd or return undef;

    if ($compile_cmd ne '')
    {
        my $sp_report = $spawner->execute($compile_cmd, { filter_hash($problem, qw/full_name name/) })
            or return undef;
        my $ok = $sp_report->{TerminateReason} eq $cats::tm_exit_process && $sp_report->{ExitStatus} eq '0';
        if ($ok)
        {
            my $runfile = get_cmd('runfile', $de_id);
            $runfile = apply_params($runfile, $problem) if $runfile;
            if ($runfile && !(-f $cfg->rundir . "/$runfile"))
            {
                $ok = 0;
                log_msg("Runfile '$runfile' not created\n");
            }
        }
        if (!$ok)
        {
            insert_test_run_details(result => $cats::st_compilation_error);
            log_msg("compilation error\n");
            return $cats::st_compilation_error;
        }
    }

    my_mkdir("solutions/$sid")
        or return undef;

    my_copy($cfg->rundir . '/*', "solutions/$sid")
        or return undef;

    # сначале тестируем в случайном порядке,
    # если найдена ошибка -- подряд до первого ошибочного теста
    for my $pass (1..2)
    {
        my @tests = $judge->get_testset($sid, 1);

        if (!@tests)
        {
            log_msg("no tests defined\n");
            return $cats::st_unhandled_error;
        }

        # получаем случайный порядок тестов
        if ($pass == 1 && !$r->{run_all_tests}) {
            for (@tests) {
                my $r = \$tests[rand @tests];
                ($_, $$r) = ($$r, $_);
            }
        }

        for my $rank (@tests)
        {
            if (!$inserted_details{$rank})
            {
                $res = run_single_test(
                    problem => $problem, sid => $sid, rank => $rank,
                    de_id => $de_id, memory_handicap => $memory_handicap
                ) or return undef;
                insert_test_run_details(result => $res);
            }
            else
            {
                $res = $inserted_details{$rank};
            }
            if ($res != $cats::st_accepted)
            {
                if (!$failed_test || $rank < $failed_test)
                {
                    $failed_test = $rank;
                }
                $r->{run_all_tests} or last;
            }
        }
        last if $res == $cats::st_accepted || $r->{run_all_tests};
    }
    'FALL';
    };
    my $e = $@;
    if ($e)
    {
        die $e unless $e =~ /^REINIT/;
    }
    else
    {
        return $r unless ($r || '') eq 'FALL';
        last;
    }
    } # for
    if ($r->{run_all_tests} && $failed_test) {
        $res = $inserted_details{$failed_test};
    }
    $r->{failed_test} = $failed_test;
    return $res;
}


sub problem_ready
{
    my ($pid) = @_;

    open my $pdesc, '<', "tests/$pid.des" or return 0;

    my $title = <$pdesc>;
    my $date = <$pdesc>;
    my $state = <$pdesc>;
    close $pdesc;

    $state eq 'state:ready' or return 0;

    # Emulate old CATS_TO_EXACT_DATE format.
    $date =~ m/^date:(\d+)-(\d+)-(\d+)\s(.+)$/ or return 0;
    $date = "$3-$2-$1 $4";
    $judge->is_problem_uptodate($pid, $date);
}

sub process_request
{
    my ($r) = @_;
    $r or return;

    $judge->lock_request($r);
    $log->clear_dump;

    if (!defined $r->{status}) {
        log_msg("security: problem $r->{problem_id} is not included in contest $r->{contest_id}\n");
        $judge->set_request_state($r, $cats::st_unhandled_error);
        return;
    }

    $problem_sources = $judge->get_problem_sources($r->{problem_id});
    # Ignore unsupported DEs for requests, but demand every problem to be installable on every judge.
    my %unsupported_DEs =
        map { $_->{code} => 1 } grep !exists $judge_de_idx{$_->{de_id}}, @$problem_sources;
    if (%unsupported_DEs) {
        log_msg("unsupported DEs for problem %s: %s\n",
            $r->{problem_id}, join ', ', sort keys %unsupported_DEs);
        $judge->set_request_state($r, $cats::st_unhandled_error, %$r);
        return;
    }

    my $state = $cats::st_testing;
    if (!problem_ready($r->{problem_id})) {
        log_msg("install problem $r->{problem_id} log:\n");
        eval {
            initialize_problem($r->{problem_id});
        } or do {
            $state = $cats::st_unhandled_error;
            log_msg("error: $@\n");
        }
    }
    else {
        log_msg("problem $r->{problem_id} cached\n");
    }
    $judge->save_log_dump($r, $log->{dump});
    $judge->set_request_state($r, $state, %$r);
    return if $state == $cats::st_unhandled_error;

    log_msg("test log:\n");
    if ($r->{fname} =~ /[^_a-zA-Z0-9\.\\\:\$]/) {
        log_msg("renamed from '$r->{fname}'\n");
        $r->{fname} =~ tr/_a-zA-Z0-9\.\\:$/x/c;
    }

    eval {
        $state = test_solution($r); 1;
    } or do {
        $state = undef;
        log_msg("error: $@\n");
    };

    defined $state
        or insert_test_run_details(result => ($state = $cats::st_unhandled_error));

    $judge->save_log_dump($r, $log->{dump});
    $judge->set_request_state($r, $state, %$r);
}

sub main_loop
{
    log_msg("judge: %s\n", $judge->name);
    log_msg("supported DEs: %s\n", join ',', sort { $a <=> $b } keys %{$cfg->DEs});

    my_chdir($cfg->workdir) or return;
    for (my $i = 0; ; $i++) {
        sleep 2;
        log_msg("pong\n") if $judge->update_state;
        log_msg("...\n") if $i % 5 == 0;
        next if $judge->is_locked;
        process_request($judge->select_request);
    }
}

$log->init;
{
    my $judge_cfg = 'config.xml';
    open my $cfg_file, '<', $judge_cfg or die "Couldn't open $judge_cfg";
    $cfg->read_file($cfg_file);
}
CATS::DB::sql_connect;
$judge = CATS::Judge::Server->new(name => $cfg->name);
$judge->auth;
$judge->set_DEs($cfg->DEs);
$judge_de_idx{$_->{id}} = $_ for values %{$cfg->DEs};
$spawner = CATS::Spawner->new(cfg => $cfg, log => $log);
main_loop;
CATS::DB::sql_disconnect;

1;
