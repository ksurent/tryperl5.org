#!/usr/bin/env perl

use lib '../';

use Modern::Perl;
use Tryperl5::Context;
use Test::More qw(no_plan);

BEGIN {
    use_ok 'Tryperl5::Context';
}

my $cid = int rand time;

my $added_context = add_context($cid);
ok defined $added_context;

my $got_context = get_context($cid);
ok defined $got_context;
is_deeply $got_context, $added_context;

remove_context($cid);
$got_context = get_context($cid);
ok not defined $got_context;


ok not defined get_context(int rand time);

my @tests = (
    {code => q/my $var = 'hello';/, ret => qr/hello/, out => qr/^$/,      err => qr/^$/},
    {code => q/print $var/,         ret => qr/1/,     out => qr/^hello$/, err => qr/^$/},
    {code => q/$var = "world"/,     ret => qr/world/, out => qr/^$/,      err => qr/^$/},
    {code => q/print $var;/,        ret => qr/1/,     out => qr/^world$/, err => qr/^$/},
);

add_context($cid);
for(@tests) {
    my($out, $err, $ret) = safe_eval($_->{code}, $cid);

    like $ret, $_->{ret};
    like $out, $_->{out};
    like $err, $_->{err};
}
