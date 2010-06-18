package Tryperl5::Context;

use Safe;
use Modern::Perl;
use Data::Dumper;
use Exporter qw(import);
use Lexical::Persistence;
use IO::CaptureOutput qw(capture);

our @EXPORT = qw(add_context get_context safe_eval);

{
    no warnings 'redefine';
    *Safe::reval = sub {
        my($obj, $expr, $strict) = @_;
        my $root = $obj->{Root};

        my $evalsub = Safe::lexless_anon_sub($root, $strict, $expr);
        return Opcode::_safe_call_sv($root, $obj->{Mask}, $evalsub);
    };
}


my %contexts;
sub add_context {
    my $id = shift;

    $contexts{$id} = {
        persist => Lexical::Persistence->new,
        safe    => Safe->new,
    };
    $contexts{$id}->{safe}->permit_only(qw(
        :base_core
        :base_mem
        :base_loop
        :base_math
        :base_orig
        say
        print
        require
        caller
        binmode
    ));
}

sub get_context {
    my $id = shift;

    $contexts{$id};
}

sub safe_eval {
    my($code, $id) = @_;

    my $compiled = compile($code, $id);
    if(not ref $compiled or ref $compiled ne 'CODE') {
        return prepare_output('', $compiled, '');
    }

    local $SIG{ALRM} = sub { die };
    alarm(3);
    my($out, $err, $ret) = execute($compiled, $id);
    alarm(0);

    prepare_output($out, $err, $ret);
}

sub compile {
    my($code, $id) = @_;

    my $context = get_context($id);
    my $compiled = $context->{safe}->reval(prepare_code($code, $id), 1);
    return $compiled ? $compiled : $@;
}

sub execute {
    my($compiled, $id) = @_;

    my(@ret, $stdout, $stderr);
    my $context = get_context($id);
    my $persisted = $context->{persist}->wrap($compiled);
    capture { @ret = eval { $persisted->() } } \$stdout, \$stderr;

    ($stdout, $stderr, \@ret);
}

sub prepare_code {
    my($code, $id) = @_;

    my $context = get_context($id);
    my $saved;# = 'use utf8;binmode STDOUT,":utf8";use feature qw(say switch state);';
    $saved .= join '', map { "my $_;" } keys %{ $context->{persist}->get_context('_') };
    $saved .= $code;

    qq!sub { $saved }!;
}

sub prepare_output {
    my($out, $err, $ret) = @_;

    local $Data::Dumper::Indent = 0;
    $ret = Data::Dumper->new([$ret], ['RETURN_VALUE'])->Dump;

    for($err) {
        s{at .+? line \d+,?}{}g;
        s{<DATA> line \d+\.?}{}g;
        s{trapped by operation mask}{call is not allowed}g;
    }

    ($out, $err, $ret);
}

1;
