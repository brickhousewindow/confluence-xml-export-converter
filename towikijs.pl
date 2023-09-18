#!/usr/bin/perl

use strict;
use warnings;
use Cwd;

BEGIN { unshift @INC, '.'; }
use MacroProcess;
use TreeWalk;

use YAML::XS;
use File::Slurp;
use MIME::Types;

use Carp qw(confess cluck);
BEGIN {
    *CORE::GLOBAL::warn = \&cluck;
    *CORE::GLOBAL::die = \&confess;
}

binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';
$| = 1;
my $DEBUG="true";

=comment

%spaces {
        %space_id {
                  $title
                  $body
                  %child {
                         %page_id {
                                  $title
                                  $body
                                  %child { ...
                         %page_id { ...
%users {
       %id {
           $name
           $email
=cut                  

my $spaces;
{
    local $/=undef;
    $spaces = Load(<STDIN>);
}

sub process_child;
sub sanitize_filename;
sub debug;
sub append_attachments;

foreach my $id (keys %$spaces){
    next if ( $id eq "users" );
    debug("processing space id $id.");
    process_space( \%{ $spaces->{ $id } } );
}

sub process_space {
    my $space = shift @_;
    TreeWalk::walk( $space );
    my @node_list = @TreeWalk::node_list;
    my $signal = "UP";

    foreach my $node ( @node_list ){

	if ( $node eq "UP" ) {
	    $signal = $node;
	    debug("Signal switched to $signal.");
	}
	elsif ( $node eq "DOWN" ) {
	    $signal = $node;
	    debug("Signal switched to $signal.");
	    debug("going one directory up.");
	    chdir ".." || die "could not change into directory: $!";
	    debug("current cwd is " . cwd() . ".");
	    
	} 
	elsif ( $node eq "CURRENT" ) {
	    $signal = $node;
	    debug("Signal switched to $signal.");
	}
	else {
	
=comment
	
creating a file to place the content inside.
because a directory cannot have a content the body is put
into a file named after the directory.
pages inside Confluence all have unique names
inside a space therefor conflicts are not expected.

=cut
	    if ( $signal eq "UP" ) {
		my $dir_name = sanitize_name( $node->{ "title" } );
		debug("creating and entering directory $dir_name.");
		mkdir $dir_name
		    || die "cannot create directory: $!";
		chdir $dir_name
		    || die "could not change into directory: $!";
		debug("current cwd is " . cwd() . ".");
	    }

	    debug("Processing page with title ".$node->{"title"}.".");
	    MacroProcess::macros_convert( \%{$node}, \%{ $spaces->{"users"} } );
	    append_attachments( \%{$node} );
	    
	    my $filename = sanitize_name( $node->{ "title" } ) . ".html";
	    debug("creating file with filename $filename.");
	    write_file( $filename,
			{binmode => ':utf8'},
			$node->{ "body" }
		) || die "cannot write to file $filename: $!";
	    $signal = "";
	}
    }
}

sub sanitize_name {
    my $string=shift @_;
=comment

removing or replacing reserved and unsafe characters
that could or can cause problems inside URLs
and pathnames.

=cut
    $string =~ tr/\\|^%$?@#//;
    $string =~ s/&/_and_/g;
    $string =~ s/\+/_plus_/g;
    $string =~ s/=/_equal_/g;
    $string =~ s/[,\/;:]/-/g;
    $string =~ s/(?:\s)+/_/g;
    $string =~ tr/[]{}<>/()()()/;
    return $string
}

sub debug {
    my $message = shift @_;
    print STDERR $message . "\n" if $DEBUG eq "true";
}

sub append_attachments {
    my $subtree = shift @_;

    foreach my $attachment ( keys %{ $subtree->{ "attachments" } } ){
	debug("Appending attachment $attachment.");
	my $mime_type = MIME::Types->new();
	my $type = $mime_type->mimeTypeOf( $attachment );
	debug("MIME type of attachment is $type.");
	$subtree->{ "body" } = $subtree->{ "body" } .
	    "<p><a href=\"data:" .
	    $type .
	    ";base64," .
	    $subtree->{ "attachments" }->{ $attachment } .
	    "\"/>".
	    $attachment .
	    "</a></p>" ;
    }

}
