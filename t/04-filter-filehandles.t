use strict;
use warnings;

use Test::More tests => 2;
use File::Temp;
use Pod::ROBODoc;

#-------------------------------------------------------------------------------
# Setup variables
#-------------------------------------------------------------------------------
my $in_fh  = IO::File->new( 't/robodoc/example-full', '<' );
my $out_fh = File::Temp->new();

my $pr = Pod::ROBODoc->new();

#-------------------------------------------------------------------------------
# Test filter() with filehandle arguments
#-------------------------------------------------------------------------------
eval {
    $pr->filter( 
        input  => $in_fh,
        output => $out_fh,
    );
};

is( $@, q{}, 'filter with filehandles succeeds' );
ok( -s $out_fh->filename(), 'filter with filehandles writes outfile' );
