package Pod::ROBODoc;

use strict;
use warnings;

our $VERSION = '0.3';

use Carp;
use IO::File;
use IO::String;
use Scalar::Util qw( blessed );
use Params::Validate qw( :all );

my $EMPTY = q{};
my $RD_BEGIN_MARK = qr{
    ^ [*]{4}  # starts with 4 asterisks
    i?        # optional "internal" flag
    ([a-z*])  # header type
    [*]       # ends with an asterisk
    [ ]*      # optional trailing whitespace
    (.*)      # optional item name
}ox;
my $RD_END_MARK = qr{ \A [*]{4} \s* \z }ox;
my %RD_HEADERS  = (
    c    => 'Class',
    d    => 'Constant',
    f    => 'Function',
    h    => 'Module',
    m    => 'Method',
    s    => 'Structure',
    t    => 'Type',
    u    => 'Unit Test',
    v    => 'Variable',
    q{*} => $EMPTY,
);

my @RD_TAGS = (
    'NAME',          'COPYRIGHT',      'SYNOPSIS',    'USAGE',
    'FUNCTION',      'DESCRIPTION',    'PURPOSE',     'AUTHOR',
    'CREATION DATE', 'MODIFICATION HISTORY',          'INPUTS',
    'ARGUMENTS',     'OPTIONS',        'PARAMETERS',  'SWITCHES',
    'OUTPUT',        'SIDE EFFECTS',   'RESULT',      'RETURN VALUE',
    'EXAMPLE',       'NOTES',          'DIAGNOSTICS', 'WARNINGS',
    'ERRORS',        'BUGS',           'TODO',        'IDEAS',
    'PORTABILITY',   'SEE ALSO',       'METHODS',     'NEW METHODS',
    'ATTRIBUTES',    'NEW ATTRIBUTES', 'TAGS',        'COMMANDS',
    'DERIVED FROM',  'DERIVED BY',     'USES',        'CHILDREN',
    'USED BY',       'PARENTS',        'SOURCE',      'LICENSE',
);
my $RD_TAG_STRING;
my $RD_TAG_REGEX;

sub new
{
    my $class  = shift;
    my %params = validate( @_, {
        keepsource => { default => 0  },
        skipblanks => { default => 0  },
        customtags => { default => [], type => ARRAYREF },
    });

    my $self = bless { %params }, $class;

    $self->_load_custom_tags();

    return $self;
}

sub filter
{
    my $self   = shift;
    my %params = validate( @_, {
        input  => { default => undef, type => UNDEF | SCALAR | HANDLE },
        output => { default => undef, type => UNDEF | SCALAR | HANDLE },
    });

    ## Setup input file handle
    my $in_fh;

    if ( ! $params{input} ) {
        $in_fh = \*STDIN;
    }
    elsif (( blessed $params{input} and $params{input}->isa( 'GLOB' ))
        or ( ref $params{input}  eq 'GLOB' )
        or ( ref \$params{input} eq 'GLOB' )) {
        $in_fh = $params{input};
    }
    elsif ( ref \$params{input} eq 'SCALAR' ) {
        $in_fh = IO::File->new( $params{input}, '<' )
            or croak "Can't open input file '$params{input}': $!";
    }
    else {
        croak "Unknown type of 'input' parameter";
    }

    ## Setup output file handle
    my $out_fh;

    if ( ! $params{output} ) {
        $out_fh = \*STDOUT;
    }
    elsif (( blessed $params{output} and $params{output}->isa( 'GLOB' ))
        or ( ref $params{output}  eq 'GLOB' )
        or ( ref \$params{output} eq 'GLOB' )) {
        $out_fh = $params{output};
    }
    elsif ( ref \$params{output} eq 'SCALAR' ) {
        $out_fh = IO::File->new( $params{output}, '>' )
            or croak "Can't open output file '$params{output}': $!";
    }
    else {
        croak "Unknown type of 'output' parameter";
    }

    $self->_parse_robodoc( $in_fh  );
    $self->_write_pod    ( $out_fh ) if @{ $self->{_parsed} };

    $in_fh ->close or carp "Can't close input file: $!";
    $out_fh->close or carp "Can't close output file: $!";

    return;
}

sub convert
{
    my $self   = shift;
    my ( $rd ) = validate_pos( @_, { type => SCALAR } );

    my $in_fh  = IO::String->new( $rd );
    my $out_fh = IO::String->new();

    $self->_parse_robodoc( $in_fh  );
    $self->_write_pod    ( $out_fh ) if @{ $self->{_parsed} };

    return ${ $out_fh->string_ref() };
}

sub _load_custom_tags
{
    my ( $self ) = @_;

    push @RD_TAGS, grep { / [A-Z0-9\s_-]+ /x } @{ $self->{customtags} };

    $RD_TAG_STRING = join q{|}, @RD_TAGS;
    $RD_TAG_REGEX  = qr{\A[ ]*($RD_TAG_STRING)[ ]*\z}o;

    return;
}

sub _parse_robodoc
{
    my $self   = shift;
    my ( $fh ) = validate_pos( @_, { type => HANDLE } );

    my @parsed;
    my $inrobodoc;
    my $insource;
    my $tag;

    while ( $_ = $fh->getline() )
    {
        chomp;
        my $rawline = $_;

        s/^[ ]*#//;
        next if not $_ and $self->{skipblanks};

        $inrobodoc = 0 if /$RD_END_MARK/;

        if ( $inrobodoc and /$RD_TAG_REGEX/ )
        {
            $tag = $1;
            $insource = $tag eq 'SOURCE';

            next if $insource and not $self->{keepsource};

            push @{ $parsed[ -1 ]{ tags } }, { tag => $tag, text => [] };
            next;
        }

        if ( $inrobodoc and $tag )
        {
            next if $insource and not $self->{keepsource};

            push @{ $parsed[ -1 ]{ tags }->[ -1 ]->{ text } },
                ( $insource ? $rawline : $_ );
        }

        if ( /$RD_BEGIN_MARK/ )
        {
            $inrobodoc = 1;
            $tag = undef;

            push @parsed, { type => $RD_HEADERS{ $1 }, element => $2, tags => [] };
        }
    }

    $self->{_parsed} = \@parsed;
    return;
}

sub _write_pod
{
    my $self   = shift;
    my ( $fh ) = validate_pos( @_, { type => HANDLE } );

    my @pod;

    push @pod, sprintf '# Generated by %s version %s', __PACKAGE__, $VERSION;
    push @pod, '=pod';

    for my $doc ( @{ $self->{_parsed} } )
    {
        push @pod, $EMPTY, "=head1 $doc->{type} $doc->{element}", $EMPTY;

        for my $tag ( @{ $doc->{tags} } )
        {
            if ( $tag->{tag} eq 'SOURCE' ) {
                push @pod, $EMPTY, '=cut', $EMPTY;
            }
            else {
                push @pod, $EMPTY, "=head2 $tag->{tag}", $EMPTY;
            }

            push @pod, $_ for @{ $tag->{text} };
        }
    }

    push @pod, $EMPTY, '=cut', $EMPTY;

    print $fh "$_\n" for @pod;
    return;
}

1;

__END__

=head1 NAME

Pod::ROBODoc - Convert ROBODoc to Pod.

=head1 VERSION

0.3

=head1 SYNOPSIS

    use Pod::ROBODoc;
    my $parser = Pod::ROBODoc->new();

    $parser->convert(
        input  => '/path/to/inputfile',
        output => '/path/to/outputfile,
    );

=head1 DESCRIPTION

Pod::ROBODoc is a simple ROBODoc-to-Pod converter.

=head1 METHODS

=head2 new( [OPTIONS] )

C<new> creates a Pod::ROBODoc object. Options are passed as name-value pairs.

=over 4

=item keepsource

Boolean indicating whether to keep data found within ROBODoc SOURCE tags.
Defaults to false.

=item skipblanks

Boolean indicating whether to strip out whitespace-only lines from ROBODoc.
Defaults to false.

=item customtags

Reference to an array of custom ROBODoc tag names. Defaults to an empty list.

=back

=head2 filter( [INPUT [,OUTPUT]] )

C<filter> takes an input stream containing ROBODoc documentation, converts it to
Pod, and writes it to the output stream.

=over 4

=item input

The input stream containing ROBODoc documentation. Can be a file name or file
handle. Defaults to STDIN.

=item output

The output stream to which the Pod will be written. Can be a file name or file
handle. Defaults to STDOUT.

=back

=head2 convert( INPUT )

C<convert> takes a string containing ROBODoc documentation, converts it to Pod,
and returns the Pod string.

=over 4

=item input

The input string containing ROBODoc documentation.

=back

=head1 CONFIGURATION

TODO

=head1 DEPENDENCIES

L<Carp>, L<IO::File>, L<IO::String>, L<Params::Validate>

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to C<bug-Pod-ROBODoc at rt dot cpan dot org>,
or through the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Pod-Robodoc>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

You may also use this module's github issues tracker at L<http://github.com/mgrimm/Pod-ROBODoc/issues>.

There is currently no support for using filehandles as input and output streams.
This is planned for a future release.

=head1 TODO

=over 4

=item * Write much more extensive tests for generated Pod

=item * Write unit tests for robodoc2pod script

=back

=head1 SEE ALSO

=over 4

=item * Pod

L<< http://perldoc.perl.org/perlpod.html >>

=item * ROBODoc

L<< http://sourceforge.net/projects/robodoc >>

=back

=head1 ACKNOWLEDGEMENTS

This module was inspired by the following post: L<http://www.perlmonks.org/?node_id=536298>

Much of the module design and test suite were adapted from elements of
Pod::WikiDoc.

=head1 AUTHOR

Matt Grimm, C<mgrimm at cpan dot org>

=head1 COPYRIGHT AND LICENSE

Copyright 2010, Matt Grimm, All rights reserved

This software is available under the same terms as perl.
