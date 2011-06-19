#!/usr/bin/env perl

use strict;
use warnings;

use Dancer;
use Dancer::Handler;
use Dancer::Config;
use Crypt::SaltedHash;
use Away;
use Away::DB;

use Plack::Builder;

Dancer::Config->load;

my $dsn = setting('plugins')->{DBIC}{away}{dsn};
my $ops =  setting('plugins')->{DBIC}{away}{options};

my $app = sub {
    my $env     = shift;
    Dancer::Handler->init_request_headers($env);
    my $request = Dancer::Request->new(env => $env);
    Dancer->dance($request);
};

builder {
    enable "Auth::Basic", authenticator => sub {
        my ( $username, $password ) = @_;
        my $db = Away::DB->connect($dsn, undef, undef, $ops); 
        my $employee = $db->resultset('Employee')->find({crsid => $username});
        return false unless $employee;
        my $salted = $employee->password_hash;
        return Crypt::SaltedHash->validate($salted, $password);
    };
    enable "ConditionalGET";
    enable "ETag";
    return $app;
};
