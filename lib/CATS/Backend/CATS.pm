package CATS::Backend::CATS;

use strict;
use warnings;

use Archive::Zip;
use File::Glob 'bsd_glob';
use File::Temp;
use JSON::XS;
use LWP::UserAgent;

my $has_Http_Request_Common;
BEGIN { $has_Http_Request_Common = eval { require HTTP::Request::Common; import HTTP::Request::Common; 1; } }

sub new {
    my ($class, $problem, $log, $problem_path, $url, $problem_exist, $root, $proxy, $verbose) = @_;
    my ($sid) = $url =~ m/sid=([a-zA-Z0-9]+)/;
    my ($cid) = $url =~ m/cid=([0-9]+)/ or $log->error("bad contest url $url");
    my ($pid) = $url =~ m/download=([0-9]+)/;
    my $self = {
        root => $root,
        problem => $problem,
        log => $log,
        name => $problem_exist ? $problem->{description}{title} : $problem_path,
        path => $problem_exist ? $problem_path : "$problem_path.zip",
        agent => LWP::UserAgent->new(requests_redirectable => [ qw(GET POST) ]),
        sid => $sid,
        cid => $cid,
        pid => $pid,
        verbose => $verbose,
    };
    $self->{agent}->proxy('http', $proxy) if $proxy;
    $self->{agent}->timeout(10);
    return bless $self => $class;
}

sub needs_login { !defined $_[0]->{sid} }

sub post {
    my ($self, $params) = @_;
    $self->{log}->note("POST $self->{root}/main.pl " . join(' ', @$params)) if $self->{verbose};
    my $r = $self->{agent}->request(POST "$self->{root}/main.pl", $params);
    $r->is_success or die $r->status_line;
    decode_json($r->content);
}

sub login {
    my ($self, $login, $password) = @_;
    my $log = $self->{log};
    my $response = $self->post([
        f => 'login',
        json => 1,
        login => $login,
        passwd => $password,
    ]);
    $response->{status} eq 'error' and $log->error($response->{message});
    $self->{sid} = $response->{sid};
    $log->note("sid=%s\n", $self->{sid}) if $self->{verbose};
}

sub start {
    my $self = shift;
    my $response = $self->post([
        f => 'problems',
        json => 1,
        cid => $self->{cid},
        sid => $self->{sid},
    ]);
    if ($response->{error}) {
        $self->{log}->error($response->{error});
    }
}

sub upload_problem {
    my $self = shift;
    $has_Http_Request_Common or $self->{log}->error('HTTP::Request::Common is required to upload problems');
    my $agent = $self->{agent};
    my $fname;
    if (-d $self->{path}) {
        my $zip = Archive::Zip->new;
        my $fh = File::Temp->new(SUFFIX => '.zip');
        $zip->addTree({ root => $self->{path} });
        $zip->writeToFileNamed($fh->filename);
        $fname = $fh->filename;
    } else {
        $fname = $self->{path};
    }

    my $response = $agent->request(POST "$self->{root}/main.pl",
        Content_Type => 'form-data',
        Content => [
            f => 'problems',
            json => 1,
            cid => $self->{cid},
            sid => $self->{sid},
            zip => [ $fname ],
            add_new => 1,
    ]);
}

sub download_without_using_url {
    my $self = shift;
    my $log = $self->{log};
    my $response = $self->post([
        f => 'problems',
        json => 1,
        cid => $self->{cid},
        sid => $self->{sid},
    ]);
    my @problems = grep $_->{name} eq $self->{name} || ($_->{code} // '') eq $self->{name},
        @{$response->{problems}};
    @problems != 1 and $log->error(@problems . " problems have name '$self->{name}'");
    $self->{agent}->request(GET "$self->{root}/$problems[0]->{package_url}");
}

sub download_using_url {
    my $self = shift;
    my $agent = $self->{agent};
    my $response = $agent->request(POST "$self->{root}/main.pl",
      Content => [
        sid => $self->{sid},
        cid => $self->{cid},
        f => 'problems',
        download => $self->{pid},
    ]);
    if ($response->{error}) {
        $self->{log}->warning($response->{error});
        $response = $self->download_without_using_url;
    }
    $response;
}

sub download_problem {
    my $self = shift;
    my $agent = $self->{agent};
    my $log = $self->{log};
    my $response = $self->{pid} ? $self->download_using_url : $self->download_without_using_url;
    my ($fname, $fh);
    -d $self->{path}
        ? $fname = ($fh = File::Temp->new(SUFFIX => '.zip'))->filename
        : open $fh, '>', $fname = $self->{path} or $log->error("Can't update $fname");
    binmode $fh;
    print $fh $response->{_content};
    close $fh;

    if (-d $self->{path}) {
        my $zip = Archive::Zip->new($fname) or die "Can't read $fname";
        for my $member ($zip->members) {
            $member->isDirectory and next;
            $member->fileName =~ m/[\\\/]?(.*)/;
            unlink my $fn = File::Spec->catfile($self->{path}, $1);
            $member->extractToFileNamed($fn);
        }
    }
}

1;
