package TreeWalk;

use strict;
use warnings;

use feature "state";

binmode STDERR, ':utf8';

my $DEBUG="false";

my $debug = sub {
    my $message = shift @_;
    print STDERR $message . "\n" if $DEBUG eq "true";
};

=comment

description:

the function walks the directory structure and returns a list of subtrees. it also returns a signal/hint in which direction the position inside the tree
changed.

implementation:

if the root has not been already set it is by taking the passed node.

signals:

CURRENT - the function is returning the current node without moving
          up or down inside the tree
UP	- the function is returning a child of a previous parent
DOWN	- the function is returning a parent of a previous child

=cut

our @node_list;

sub walk {
    my $node = shift @_;
    my $signal;

    if ( defined $node->{ "child" }
	 and scalar keys %{ $node->{ "child" } } ){

	$signal = "UP";
	push @node_list, $signal;
	$debug->("Signal $signal.");
	$debug->("Processing children, going down inside the tree.");	
    }

    push @node_list, $node;
    $debug->("Pushed ".$node->{"title"}." to list.");
    
    my @child_list = keys %{ $node->{ "child" } };
    while ( @child_list ){
	my $child_id = shift @child_list;
	$debug->("processing child $child_id.");
	
	walk( \%{ $node->{ "child" }->{ $child_id } } );

	if ( @child_list ){
	    $signal = "CURRENT";
	    push @node_list, $signal;
	    $debug->("Signal $signal.");
	    $debug->("Processing next child.");
	}
    }

    if ( defined $node->{ "child" }
	 and scalar keys %{ $node->{ "child" } } ){

	$signal = "DOWN";
	push @node_list, $signal;
	$debug->("Signal $signal.");
	$debug->("Children processed, going up inside the tree.");
    } 
}

1; 
