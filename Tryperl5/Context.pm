package Tryperl5::Context;

use Safe 2.27;
use Modern::Perl;
use Data::Dumper;
use Exporter qw(import);
use IO::CaptureOutput qw(capture);
use PadWalker qw(closed_over peek_sub);

our @EXPORT = qw(add_context get_context remove_context safe_eval);

my %contexts;
sub add_context {
    my $id = shift;

    my $safe = Safe->new;
    $safe->permit_only(qw(
        :base_core
        :base_mem
        :base_loop
        :base_math
        :base_orig
        print
        time
        sort
    ));

    $contexts{$id} = {
        persist => {},
        safe    => $safe,
    };
}

sub get_context {
    my $id = shift;

    $contexts{$id};
}

sub remove_context {
    my $id = shift;

    delete $contexts{$id};
}

sub safe_eval {
    my($code, $id) = @_;

    my $compiled = compile(prepare($code, $id), $id);
    if(not ref $compiled or ref $compiled ne 'CODE') {
        return prepare_output('', $compiled, '');
    }

    restore($compiled, $id);

    local $SIG{ALRM} = sub { die };
    alarm(3);
    my($out, $err, $ret) = execute($compiled);
    alarm(0);

    save($compiled, $id);

    prepare_output($out, $err, $ret);
}

sub compile {
    my($code, $id) = @_;

    my $compiled = get_context($id)->{safe}->reval($code, 1);

    return defined $compiled ? $compiled : $@;
}

sub prepare {
    my($code, $id) = @_;

    my $vars = join ';', map "my $_", keys %{ get_context($id)->{persist} };

    qq/$vars; sub { $code }/
}

sub execute {
    my $compiled = shift;

    my(@ret, $stdout, $stderr);
    capture { @ret = eval { $compiled->() } } \$stdout, \$stderr;

    ($stdout, $stderr, \@ret);
}

sub save {
    my($compiled, $id) = @_;

    my $persist  = get_context($id)->{persist};
    my $lexicals = get_lexicals($compiled);

    while(my($varname, $valref) = each %$lexicals) {
        $persist->{$varname} = $$valref;
    }
}

sub restore {
    my($compiled, $id) = @_;

    my $persist = get_context($id)->{persist};
    return unless %$persist;
    my $lexicals = get_lexicals($compiled);

    for my $varname (keys %$lexicals) {
        next unless exists $persist->{$varname};
        ${ $lexicals->{$varname} } = $persist->{$varname};
    }
}

sub prepare_output {
    my($out, $err, $ret) = @_;

    local $Data::Dumper::Indent = 0;
    $ret = Data::Dumper->new([$ret], ['RETURN_VALUE'])->Dump;

    for($err) {
        s{[.,]$}{};
        s{at .+? line \d+}{}g;
        s{<DATA> line \d+}{}g;
        s{trapped by operation mask}{call is not allowed}g;
    }

    ($out, $err, $ret);
}

sub get_lexicals {
    my $compiled = shift;

    my $closed_over = closed_over $compiled;
    peek_sub ${ $closed_over->{'$sub'} };
}

1;
