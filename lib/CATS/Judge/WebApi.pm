package CATS::Judge::WebApi;

use strict;
use warnings;

use LWP::UserAgent;
use JSON::XS;
use HTTP::Request::Common;
#TODO: remove after full convesion
use CATS::DB;

use base qw(CATS::Judge::DirectDatabase);

sub new_from_cfg {
    my ($class, $cfg) = @_;
    $class->SUPER::new(name => $cfg->name, password => $cfg->cats_password, cats_url => $cfg->cats_url);
}

sub init {
    my ($self) = @_;

    $self->{agent} = LWP::UserAgent->new(requests_redirectable => [ qw(GET POST) ]);
}

sub get_json {
    my ($self, $params) = @_;

    push @$params, 'json', 1;
    my $request = $self->{agent}->request(POST "$self->{cats_url}/", $params);
    die "Error: $request->{_rc} '$request->{_msg}'" unless $request->{_rc} == 200;
    decode_json($request->{_content});
}

sub auth {
    my ($self) = @_;

    my $response = $self->get_json([
        f => 'login',
        login => $self->{name},
        passwd => $self->{password},
    ]);
    die "Incorrect login and password" if $response->{status} eq 'error';
    $self->{sid} = $response->{sid};

    $response = $self->get_json([
        f => 'get_judge_id',
        sid => $self->{sid},
    ]);
    die "get_judge_id: $response->{error}" if $response->{error};
    $self->{id} = $response->{id};
}

sub update_state {
    my ($self) = @_;

    my $response = $self->get_json([
        f => 'api_judge_update_state',
        sid => $self->{sid},
    ]);

    die "update_state: $response->{error}" if $response->{error};

    $self->{lock_counter} = $response->{lock_counter};

    #TODO: remove after full conversion
    $dbh->commit;

    !$response->{is_alive};
}

sub is_locked { $_[0]->{lock_counter} }

1;
