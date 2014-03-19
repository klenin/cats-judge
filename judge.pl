#!perl -w
use v5.10;
use strict;
use XML::Parser::Expat;

use POSIX qw(strftime);
use File::Spec;
use constant FS => 'File::Spec';
use File::NCopy qw(copy);

use lib 'lib';
use CATS::Constants;
use CATS::Utils qw(split_fname);
use CATS::DB qw(new_id $dbh);
use CATS::Testset;
use CATS::Judge::Server;

use open IN => ':crlf', OUT => ':raw';

my $tm_exit_process           = 'ExitProcess';
my $tm_time_limit_exceeded    = 'TimeLimitExceeded';
my $tm_memory_limit_exceeded  = 'MemoryLimitExceeded';
my $tm_write_limit_exceeded   = 'WriteLimitExceeded';
my $tm_abnormal_exit_process  = 'AbnormalExitProcess';

my $terminate_reason;
my $exit_status;
my $user_time;
my $memory_used;
my $written;

my $judge;
my $workdir;
my $rundir;
my $report_file;
my $stdout_file;
my $formal_input_fname;
my $show_child_stdout;
my $save_child_stdout;
my $judge_cfg = 'config.xml';

my %defines;
my %judge_de;
my %checkers;

my $jsid;
my $jid;
my $dump;

my $problem_sources;

my ($log_month, $log_year);
my $last_log_line = '';

sub log_msg
{
    my $fmt = shift;
    my $s = sprintf $fmt, @_;
    syswrite STDOUT, $s;
    if ($last_log_line ne $s)
    {
        syswrite FDLOG, strftime('%d.%m %H:%M:%S', localtime) . " $s";
        $last_log_line = $s;
    }
    $dump .= $s;
    undef;
}


sub trim
{
    my $s = shift;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    $s;
}


sub get_cmd
{
    my ($action, $de_id) = @_;

    my $code = $dbh->selectrow_array(qq~SELECT code FROM default_de WHERE id=?~, {}, $de_id);

    if (!defined $judge_de{ $code }) {
        log_msg("unknown de code: $code\n");
        return undef;
    }

    return $judge_de{$code}->{$action};
}


sub get_std_checker_cmd
{
    my $std_checker_name = shift;

    if (!defined $checkers{$std_checker_name}) {
        log_msg("unknown std checker: $std_checker_name\n");
        return undef;
    }

    $checkers{$std_checker_name};
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


sub clear_log_dump 
{
    $dump = '';
}


sub dump_child_stdout
{    
    my %p = @_;
    my $duplicate_to = $p{duplicate_to};

    unless (open(FSTDOUT, "<$stdout_file"))
    {
        log_msg("open failed: '$stdout_file' ($!)\n");
        return undef;
    }

    my $eol = 0;
    while (<FSTDOUT>)
    {
        if ($show_child_stdout) {
            print STDERR $_;
        }
                        
        if ($save_child_stdout) {
            syswrite FDLOG, $_;
            $dump .= $_ if length $dump < 50000;
        }

        if ($duplicate_to) {
            $$duplicate_to .= $_;
            syswrite FDLOG, '!!';
        }
        
        $eol = (substr($_, -2, 2) eq '\n');
    }

    if ($eol)
    {
        if ($show_child_stdout) {
            print STDERR "\n";
        }

        if ($save_child_stdout) {
            syswrite FDLOG, "\n";
            $dump .= '\n';
        }

        if ($duplicate_to) {
            $$duplicate_to .= $_;
        }
    }

    close FSTDOUT;

    1;
}


sub save_log_dump
{
    my $rid = shift;

    my $did = $dbh->selectrow_array(qq~SELECT id FROM log_dumps WHERE req_id=?~, {}, $rid);
    if (defined $did)
    {
        my $c = $dbh->prepare(qq~UPDATE log_dumps SET dump=? WHERE id=?~);
        $c->bind_param(1, $dump, { ora_type => 113 });
        $c->bind_param(2, $did);
        $c->execute;
    }
    else
    {
        my $c = $dbh->prepare(qq~INSERT INTO log_dumps (id, dump, req_id) VALUES(?,?,?)~);
        $c->bind_param(1, new_id);
        $c->bind_param(2, $dump, { ora_type => 113 });
        $c->bind_param(3, $rid);
        $c->execute;
    }
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
            unless (unlink $_) {
                log_msg("rm $_: $!\n");
                $res = 0;
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
    if (copy \1, $src, $dest) { return 1; }
    use Carp;
    log_msg "copy failed: 'cp $src $dest' '$!' " . Carp::longmess('') . "\n";
    return undef;
}


sub my_safe_copy
{
    my ($src, $dest, $pid) = @_;
    return 1 if copy \1, $src, $dest;
    log_msg "copy failed: 'cp $src $dest' $!, trying to reinitialize\n";
    # Возможно, что кеш задачи был повреждён, либо изменился импротированный модуль
    # Попробуем переинициализировать задачу. Если и это не поможет -- вылетаем.
    initialize_problem($pid);
    my_copy($src, $dest);
    die 'REINIT';
}


sub apply_params
{
    my ($str, $params) = @_;
    $str =~ s/%$_/$params->{$_}/g
        for sort { length $b <=> length $a } keys %$params;
    $str;
}

sub execute
{
    my ($exec_str, $params, %rest) = @_;

    $terminate_reason = undef;
    $exit_status = undef;

    #my %subst = %$params;
   
    #for (keys %subst)
    #{
    #    $exec_str =~ s/%$_/$subst{$_}/g;
    #}
    $exec_str = apply_params($exec_str, $params);
    $exec_str =~ s/%report_file/$report_file/g;
    $exec_str =~ s/%stdout_file/$stdout_file/g;
    $exec_str =~ s/%deadline//g;
        
    my_chdir($rundir)
        or return undef;


    # очистим stdout_file
    open(FSTDOUT, ">$stdout_file") or
        do { my_chdir($workdir); return undef; };

    close(FSTDOUT);

    log_msg("> %s\n", $exec_str);
    my $rc = system($exec_str) >> 8;

    dump_child_stdout(duplicate_to => $rest{duplicate_output});

    if ($rc)
    {
        log_msg("exit code: $rc\n $!\n");
        my_chdir($workdir);
        return undef;
    }

    unless (open(FREPORT, "<$report_file"))
    {
        log_msg("open failed: '$report_file' ($!)\n");
        my_chdir($workdir);
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
        log_msg("malformed spawner report: $signature\n");
        my_chdir($workdir);
        return undef;
    }

    for (1..10) {
        my $skip = <FREPORT>;
    }
    $user_time          = <FREPORT>;
    $memory_used        = <FREPORT>;
    $written            = <FREPORT>;
    $terminate_reason   = <FREPORT>;
    $exit_status        = <FREPORT>;
    $skip               = <FREPORT>;
    my $spawner_error   = <FREPORT>;
    
    close FREPORT;

    $spawner_error =~ m/^SpawnerError:(.*)/; 

    $_ = trim($1);
    if ($_ ne '<none>')
    {
        log_msg("\tspawner error: $_\n");
        my_chdir($workdir);
        return undef;
    }

    $terminate_reason =~ m/^TerminateReason:(.*)/; 
    $terminate_reason = trim($1);

    $exit_status =~ m/^ExitStatus:(.*)/;
    $exit_status = trim($1);
    
    $user_time =~ m/^UserTime:(.*) \(sec\)/;
    $user_time = trim($1);
    
    $memory_used =~ m/^PeakMemoryUsed:(.*)\(Mb\)/;
    $memory_used = trim($1);

    $written =~ m/^Written:(.*)\(Mb\)/;
    $written = trim($1);

    if ($terminate_reason eq $tm_exit_process && $exit_status ne '0')
    {
        log_msg("process exit code: $exit_status\n");
    }
    elsif ($terminate_reason eq $tm_time_limit_exceeded)
    {
        log_msg("time limit exceeded\n");
    }
    elsif ($terminate_reason eq $tm_write_limit_exceeded)
    {
        log_msg("write limit exceeded\n");
    }
    elsif ($terminate_reason eq $tm_memory_limit_exceeded)
    {
        log_msg("memory limit exceeded\n");
    }
    elsif ($terminate_reason eq $tm_abnormal_exit_process)
    {
        log_msg("abnormal process termination. Process exit status: $exit_status\n");
    }
    log_msg(
        "-> UserTime: $user_time s | MemoryUsed: $memory_used Mb | Written: $written Mb\n");
    
    my_chdir($workdir) 
        or return undef;

    return 1;
}


sub get_problem_sources($)
{
    return $problem_sources if $problem_sources;
    $problem_sources = $dbh->selectall_arrayref(qq~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
        WHERE ps.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $_[0]);
    my $imported = $dbh->selectall_arrayref(qq~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
            INNER JOIN problem_sources_import psi ON ps.guid = psi.guid
        WHERE psi.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $_[0]);
    push @$problem_sources, @$imported;
    return $problem_sources;
}


sub unsupported_DEs
{
	my %seen;
	sort grep !$seen{$_}++, map $_->{code},
		grep !defined($judge_de{$_->{code}}), @{get_problem_sources($_[0])};
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

    my_remove "$rundir/*"
        or return undef;

    my_copy("tests/$pid/temp/$test->{generator_id}/*", "$rundir")
        or return undef;

    my $generate_cmd = get_cmd('generate', $ps->{de_id})
        or do { print "No generate cmd for: $ps->{de_id}\n"; return undef; };
    my ($vol, $dir, $fname, $name, $ext) = split_fname($ps->{fname});

    my $redir = '';
    my $out = $ps->{output_file};
    if (!defined $out)
    {
        $out = $input_fname;
    }
    if ($out =~ /^\*STD(IN|OUT)$/)
    {
        $test->{gen_group} and return undef;
        $out = 'stdout1.txt';
        $redir = " -so:$out -ho:1";
    }
    execute(
        $generate_cmd, {
        full_name => $fname, name => $name,
        limits => get_special_limits($ps),
        args => $test->{param} // '', redir => $redir }
    ) or return undef;

    if ($terminate_reason ne $tm_exit_process || $exit_status ne '0')
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
        my_copy(sprintf("$rundir/$out", $_->{rank}), "tests/$pid/$_->{rank}.tst")
            or return undef;
    }
    1;
}


sub input_or { $_[0] eq '*STDIN' ? 'input.txt' : $_[1] }
sub output_or { $_[0] eq '*STDOUT' ? 'output.txt' : $_[1] }

sub input_or_default { FS->catfile($rundir, input_or($_[0], $_[0])) }
sub output_or_default { FS->catfile($rundir, output_or($_[0], $_[0])) }

sub input_output_redir {
    input_redir => input_or($_[0], ''), output_redir => output_or($_[1], ''),
}


sub prepare_tests
{
    my ($pid, $input_fname, $output_fname, $tlimit, $mlimit) = @_;
    # создаем тесты
    my $tests = $dbh->selectall_arrayref(qq~
        SELECT generator_id, rank, param, std_solution_id, in_file, out_file, gen_group
            FROM tests WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
        $pid);

    if (!@$tests)   
    {
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
                my_copy("$rundir/$out", "tests/$pid/$t->{rank}.tst")
                    or return undef;
            }
        }
        else 
        {
            log_msg("no input file defined for test #$t->{rank}\n");
            return undef;
        }

        # создаем выходной файл теста
        if (defined $t->{out_file})
        {
            write_to_file("tests/$pid/$t->{rank}.ans", $t->{out_file})
                or return undef;
        }
        elsif (defined $t->{std_solution_id})
        {
            my ($ps) = grep $_->{id} == $t->{std_solution_id}, @$problem_sources;

            my_remove "$rundir/*"
                or return undef;
 
            my_copy("tests/$pid/temp/$t->{std_solution_id}/*", "$rundir")
                or return undef;

            my_copy("tests/$pid/$t->{rank}.tst", input_or_default($input_fname))
                or return undef;

            my $run_cmd = get_cmd('run', $ps->{de_id})
                or return undef;

            my ($vol, $dir, $fname, $name, $ext) = split_fname($ps->{fname});

            execute($run_cmd, {
                full_name => $fname, 
                name => $name, 
                time_limit => $ps->{time_limit} || $tlimit,
                memory_limit => $ps->{memory_limit} || $mlimit,
                deadline => ($ps->{time_limit} ? "-d:$ps->{time_limit}" : ''),
                input_output_redir($input_fname, $output_fname),
            }) or return undef;

            if ($terminate_reason ne $tm_exit_process || $exit_status ne '0')
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
        write_to_file("$rundir/$fname", $m->{src})
            or return undef;

        # в данном случае ничего страшного, если compile_cmd нету, 
        # это значит, что модуль компилировать не надо (de_code=1)
        my $compile_cmd = get_cmd('compile', $m->{de_id})
            or next;
        execute($compile_cmd, { full_name => $fname, name => $name })
            or return undef;
    }
    1;
}

sub initialize_problem
{
    my $pid = shift;

    my (
        $title, $upload_date, $input_fname, $output_fname,
        $tlimit, $mlimit, $cid, $formal_input
    ) =
        $dbh->selectrow_array(qq~
            SELECT
                title, upload_date, input_file, output_file,
                time_limit, memory_limit, contest_id, formal_input
            FROM problems WHERE id=?~, {}, $pid);

    save_problem_description($pid, $title, $upload_date, 'not ready')
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
        my_remove "$rundir/*"
            or return undef;
        
        prepare_modules($cats::source_modules{$ps->{stype}} || 0)
            or return undef;

        my ($vol, $dir, $fname, $name, $ext) = split_fname($ps->{fname});
        write_to_file("$rundir/$fname", $ps->{src}) 
            or return undef;

        if (my $compile_cmd = get_cmd('compile', $ps->{de_id}))
        {
            execute($compile_cmd, { full_name => $fname, name => $name })
                or return undef;
            if ($terminate_reason ne $tm_exit_process || $exit_status ne '0')
            {
                log_msg("*** compilation error ***\n");
                return undef;
            }    
        }

        # после компиляции генератора положить ему formal_input_fname
        if ($ps->{stype} == $cats::generator && $formal_input) {
           write_to_file("$rundir/$formal_input_fname", $formal_input)
              or return undef;
        }

        my_mkdir("tests/$pid/temp/$ps->{id}")
            or return undef;

        my_copy("$rundir/*", "tests/$pid/temp/$ps->{id}")
            or return undef;
    }
    prepare_tests($pid, $input_fname, $output_fname, $tlimit, $mlimit)
        or return undef;

    # проверяем, что эталонное решение проходит на всех тестах
    for my $ps (grep $_->{stype} == $cats::adv_solution, @$problem_sources)
    {
        log_msg("==== testing ====\n");
        my ($state, $failed_test) =
            test_solution($pid, $ps->{id}, $ps->{fname}, $ps->{src}, $ps->{de_id}, $cid);

        if (!defined($state) || $state != $cats::st_accepted) 
        {
            log_msg("==== test failed ====\n");
            return undef;
        }

        log_msg("=== test completed ===\n");
    }

    save_problem_description($pid, $title, $upload_date, 'ready')
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
    $dbh->do(
        sprintf(
            q~INSERT INTO req_details (%s) VALUES (%s)~,
            join(', ', keys %p), join(', ', ('?') x keys(%p))
        ),
        undef, values %p
    ) or log_msg("Details failed\n");
    $dbh->commit;
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

        my_safe_copy("tests/$problem->{id}/temp/$problem->{checker_id}/*", "$rundir", $problem->{id})
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

    for my $c (\$test_run_details{checker_comment})
    {
        $$c = undef;
        execute($checker_cmd, $checker_params, duplicate_output => $c)
            or return undef;
        #Encode::from_to($$c, 'cp866', 'utf8');
        # обрезать для надёжности, чтобы влезло в поле БД
        $$c = substr($$c, 0, 199) if defined $$c;
    }

    $terminate_reason eq $tm_exit_process or return undef;

    1;
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

    my_remove "$rundir/*" or return undef;
    my_safe_copy("solutions/$p{sid}/*", $rundir, $problem->{id})
        or return undef;
    my_safe_copy(
        "tests/$problem->{id}/$p{rank}.tst",
        input_or_default($problem->{input_file}), $problem->{id})
        or return undef;
    my $run_cmd = get_cmd('run', $p{de_id})
        or return undef;

    my $exec_params = {
        filter_hash($problem, qw/name full_name time_limit memory_limit output_file/),
        input_output_redir(@$problem{qw(input_file output_file)}),
        test_rank => sprintf('%02d', $p{rank}),
    };
    $exec_params->{memory_limit} += $p{memory_handicap} || 0;
    execute($run_cmd, $exec_params) or return undef;

    $test_run_details{time_used} = $user_time;
    $test_run_details{memory_used} = int($memory_used * 1024 * 1024);
    $test_run_details{disk_used} = int($written * 1024 * 1024);

    for ($terminate_reason)
    {
        if ($_ eq $tm_exit_process)
        {
            if ($exit_status ne '0')
            {
                $test_run_details{checker_comment} = $exit_status;
                return $cats::st_runtime_error;
            }
        }
        else
        {
            return $cats::st_runtime_error         if $_ eq $tm_abnormal_exit_process;
            return $cats::st_time_limit_exceeded   if $_ eq $tm_time_limit_exceeded;
            return $cats::st_memory_limit_exceeded if $_ eq $tm_memory_limit_exceeded;
            return $cats::st_security_violation    if $_ eq $tm_write_limit_exceeded;
            
            log_msg("unknown terminate reason: $_\n");
            return undef;
        }
    }

    my_safe_copy(
        "tests/$problem->{id}/$p{rank}.tst",
        input_or_default($problem->{input_file}), $problem->{id})
        or return undef;
    my_safe_copy("tests/$problem->{id}/$p{rank}.ans", "$rundir/$p{rank}.ans", $problem->{id})
        or return undef;

    run_checker(problem => $problem, rank => $p{rank})
        or return undef;

    if ($exit_status eq '0')
    {
        log_msg("OK\n");
        return $cats::st_accepted;
    }
    elsif ($exit_status eq '1')
    {
        return $cats::st_wrong_answer;
    }
    elsif ($exit_status eq '2')
    {
        return $cats::st_presentation_error;
    }
    else
    {
        log_msg("checker error (exit code '$exit_status')\n");
        return undef;
    }
}


sub test_solution
{
    my ($pid, $sid, $fname_with_path, $src, $de_id, $cid) = @_;
    log_msg("Testing solution: $sid for problem: $pid\n");
    my $problem = $dbh->selectrow_hashref(qq~
        SELECT id, time_limit, memory_limit, input_file, output_file, std_checker        
        FROM problems WHERE id = ?~, { Slice => {} }, $pid);

    my ($run_all_tests) = $dbh->selectrow_array(qq~
        SELECT run_all_tests FROM contests WHERE id = ?~, undef, $cid);

    my ($memory_handicap) = $dbh->selectrow_array(qq~
        SELECT memory_handicap FROM default_de WHERE id = ?~, undef, $de_id);
    
    ($problem->{checker_id}) = map $_->{id}, grep
        { ($cats::source_modules{$_->{stype}} || -1) == $cats::checker_module }
        @$problem_sources;

    if (!defined $problem->{checker_id} && !defined $problem->{std_checker})
    {
        log_msg("no checker defined!\n");
        return undef;
    }

    $dbh->do('DELETE FROM req_details WHERE req_id = ?', undef, $sid);
    $dbh->commit;
    %test_run_details = (req_id => $sid, test_rank => 1);
    %inserted_details = ();

    (undef, undef, $problem->{full_name}, $problem->{name}, undef) =
        split_fname($fname_with_path);
        
    my $res = undef;
    my $failed_test = undef;

    for (0..1)
    {
    my $r = eval
    {
    my_remove "$rundir/*"
        or return undef;
      
    prepare_modules($cats::solution_module) or return undef;
    write_to_file("$rundir/$problem->{full_name}", $src)
        or return undef;

    my $compile_cmd = get_cmd('compile', $de_id);
    defined $compile_cmd or return undef;

    if ($compile_cmd ne '')
    {
        execute($compile_cmd, { filter_hash($problem, qw/full_name name/) })
            or return undef;
        my $ok = $terminate_reason eq $tm_exit_process && $exit_status eq '0';
        if ($ok)
        {
            my $runfile = get_cmd('runfile', $de_id);
            $runfile = apply_params($runfile, $problem) if $runfile;
            if ($runfile && !(-f "$rundir/$runfile"))
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

    my_copy("$rundir/*", "solutions/$sid")
        or return undef;

    # сначале тестируем в случайном порядке,
    # если найдена ошибка -- подряд до первого ошибочного теста
    for my $pass (1..2)
    {
        my @tests = CATS::Testset::get_testset($sid, 1);

        if (!@tests)
        {
            log_msg("no tests defined\n");
            return $cats::st_unhandled_error;
        }
    
        # получаем случайный порядок тестов
        if ($pass == 1 && !$run_all_tests) 
        {
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
                $run_all_tests or last;
            }
        }
        last if $res == $cats::st_accepted || $run_all_tests;
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
    if ($run_all_tests && $failed_test)
    {
        $res = $inserted_details{$failed_test};
    }
    return ($res, $failed_test);
}


sub auth_judge 
{

    $jid = $dbh->selectrow_array(qq~
        SELECT id FROM judges WHERE nick = ?~, {}, $judge->name);
    unless (defined $jid)
    {
        log_msg("unknown judge name: '%s'\n", $judge->name);
        return 0;
    }

    my @ch = ('A'..'Z','a'..'z','0'..'9');
    for (1..20)
    {
        $jsid = '';
        for (1..30)
        {
            $jsid .= @ch[rand @ch];
        }
    
        if ($dbh->do(qq~UPDATE judges SET jsid=? WHERE id=?~, {}, $jsid, $jid) )
        { 
            $dbh->commit;
            return 1;
        }
    }
    
    log_msg("login failed\n"); 
    0;
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

    # Эмулируем старый формат CATS_TO_EXACT_DATE
    $date =~ m/^date:(\d+)-(\d+)-(\d+)\s(.+)$/ or return 0;
    $date = "$3-$2-$1 $4";
    my ($is_uptodate) = $dbh->selectrow_array(qq~
        SELECT 1 FROM problems
        WHERE id = ? AND upload_date - 1.0000000000 / 24 / 60 / 60 <= ?~, undef,
        $pid, $date);
    $is_uptodate;
}


sub set_request_state
{
    my ($rid, $state, %p) = @_;
    $dbh->do(qq~
        UPDATE reqs SET state = ?, failed_test = ?, result_time = CURRENT_TIMESTAMP
        WHERE id = ? AND judge_id = ?~, {},
        $state, $p{failed_test}, $rid, $jid);
    if ($state == $cats::st_unhandled_error && defined $p{problem_id} && defined $p{contest_id})
    {
        $dbh->do(qq~
            UPDATE contest_problems SET status = ?
                WHERE problem_id = ? AND contest_id = ?~, {},
            $cats::problem_st_suspended, $p{problem_id}, $p{contest_id});
    }
    $dbh->commit;
}


sub process_requests
{
    my $c = $dbh->prepare(qq~
        SELECT
            R.id, R.problem_id, R.contest_id, R.state, CA.is_jury,
            (SELECT CP.status FROM contest_problems CP
                WHERE CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id) AS status
        FROM reqs R
        INNER JOIN contest_accounts CA
            ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
        WHERE R.state = ?~
    ); # AND judge_id IS NULL~);
    $c->execute($cats::st_not_processed);

    while (my $r = $c->fetchrow_hashref)
    {
        if (!defined $r->{status})
        {
            log_msg("security: problem $r->{problem_id} is not included in contest $r->{contest_id}\n");
            $dbh->do(q~
                UPDATE reqs SET state=? WHERE id=?~, undef,
                $cats::st_unhandled_error, $r->{id});
            $dbh->commit;
            next;
        }
        $r->{status} == $cats::problem_st_ready || $r->{is_jury}
            or next;
        my ($src, $fname, $de_id, $de_code) =
        $dbh->selectrow_array(qq~
            SELECT S.src, S.fname, D.id, D.code 
            FROM sources S, default_de D
            WHERE S.req_id = ? AND D.id = S.de_id~, {}, $r->{id});
        # данная среда разработки не поддерживается
        if (!defined $judge_de{$de_code})
        {  
            log_msg("unsupported DE $de_code in request $r->{id}\n");
            $dbh->do(q~UPDATE reqs SET state=? WHERE id=?~, undef, $cats::st_unhandled_error, $r->{id});
            $dbh->commit;
            log_msg("set to unhandled_error\n");
            last;
        }

        undef $problem_sources;

        if (my @u = unsupported_DEs($r->{problem_id}))
        {
            my $m = join ', ', @u;
            log_msg("unsupported DEs for problem $r->{problem_id}: $m\n");
            next;
        }

        # блокируем запись
        $dbh->do(qq~UPDATE reqs SET judge_id = ? WHERE id = ?~, {}, $jid, $r->{id});
        set_request_state($r->{id}, $cats::st_install_processing);

        clear_log_dump;
                
        my $state = $cats::st_testing;
        if (!problem_ready($r->{problem_id}))
        {
            log_msg("install problem $r->{problem_id} log:\n");

            # устанавливаем пакет с задачей            
            eval {
                initialize_problem($r->{problem_id});
            } or do {
                $state = $cats::st_unhandled_error;
                log_msg("error: $@\n");
            }
        }
        else
        {
            log_msg("problem $r->{problem_id} cached\n");
        }
          
        save_log_dump($r->{id});

        set_request_state($r->{id}, $state, %$r);
        if ($state != $cats::st_unhandled_error)
        { 
            # тестируем решение
            log_msg("test log:\n");

            my $failed_test;
            if ($fname =~ /[^_a-zA-Z0-9\.\\\:\$]/)
            {
                log_msg("renamed from '$fname'\n");
                $fname =~ tr/_a-zA-Z0-9\.\\:$/x/c;
            }
            ($state, $failed_test) = test_solution(
                $r->{problem_id}, $r->{id}, $fname, $src, $de_id, $r->{contest_id});

            if (!defined $state)
            {
                insert_test_run_details(result => ($state = $cats::st_unhandled_error));
            }

            save_log_dump($r->{id});

            set_request_state($r->{id}, $state, failed_test => $failed_test, %$r);
            
            $dbh->commit;
        }
        last;
    }

    1;
}


sub main_loop
{
    log_msg("judge: %s\n", $judge->name);

    my_chdir($workdir) 
        or return undef;
    
    for (my $i = 0; ; $i++)
    {
        sleep 2;

        my ($is_alive, $lock_counter, $current_sid) = $dbh->selectrow_array(qq~
            SELECT is_alive, lock_counter, jsid FROM judges WHERE id = ?~, {}, $jid);
        
        if (!$is_alive)
        {
            log_msg("pong\n");
            $dbh->do(qq~
                UPDATE judges SET is_alive = 1, alive_date = CURRENT_DATE
                    WHERE id = ? AND is_alive = 0~, {},
                $jid);
        }
        $dbh->commit;
        
        log_msg("...\n") if $i % 5 == 0;

        next if $lock_counter; # judge locked
        if ($current_sid ne $jsid)
        {
            log_msg "killed: $current_sid != $jsid\n";
            last;
        }
        
        last unless process_requests;
    }
}


sub char_handler
{

    my ($p, $text) = @_;
}


sub apply_defines
{
    my $expr = shift;
    $expr or return $expr;

    for (sort { length $b <=> length $a } keys %defines)
    {
        $expr =~ s/$_/$defines{$_}/g;
    }
    
    $expr;
}


sub start_handler
{

    my ($p, $el, %atts) = @_;

    my %de;

    if ($el eq 'judge') 
    {
        $workdir = $atts{'workdir'};
        $rundir = $atts{'rundir'};
        my $judge_name = $atts{'name'};
        $report_file = $atts{'report_file'};
        $stdout_file = $atts{'stdout_file'};
        $formal_input_fname = $atts{'formal_input_fname'};
        $show_child_stdout = $atts{'show_child_stdout'};
        $save_child_stdout = $atts{'save_child_stdout'};
        $judge = CATS::Judge::Server->new(name => $judge_name);
    }
    
    if ($el eq 'de') 
    {
        $de{$_} = apply_defines($atts{$_})
            for qw(compile run generate check runfile);
        $judge_de{$atts{'code'}} = \%de;        
    }
                            
    if ($el eq 'define')
    {        
        $defines{$atts{'name'}} = apply_defines($atts{'value'});
    }

    if ($el eq 'checker')
    {        
        $checkers{$atts{'name'}} = apply_defines($atts{'exec'});
    }
}


sub end_handler
{

    my ($p, $el) = @_;
} 


sub read_cfg
{ 
    my $parser = new XML::Parser::Expat;

    $parser->setHandlers('Start' => \&start_handler, 'End' => \&end_handler, 'Char'  => \&char_handler);

    open(CFG, $judge_cfg) 
        or die "Couldn't open $judge_cfg\n";

    $parser->parse(*CFG);
    
    close CFG;

    $judge->name    || die "$judge_cfg: undefined judge name";
    $workdir        || die "$judge_cfg: undefined judge working directory";
    $rundir         || die "$judge_cfg: undefined judge running directory";
    $report_file    || die "$judge_cfg: undefined spawner report file";
    $stdout_file    || die "$judge_cfg: undefined spawner stdout file";
    $formal_input_fname || die "$judge_cfg: undefined file name for formal input";
}


#$fatal_error_html_style = 0;

(undef, undef, undef, undef, $log_month, $log_year) = localtime;
open FDLOG, sprintf '>>judge-%04d-%02d.log', $log_year + 1900, $log_month + 1;
CATS::DB::sql_connect;
read_cfg;
main_loop if auth_judge;
CATS::DB::sql_disconnect;

close FDLOG;

1;
