#!/usr/bin/perl

use strict;
use warnings;
use Cwd;

BEGIN { unshift @INC, '.'; }
use MacroProcess;

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
    debug("processing space id $id.");
    process_child( \%{ $spaces->{ $id } } );
}

sub process_child {
    my $subtree = shift @_;
    debug("Processing page with title ".$subtree->{"title"}.".");

    if ( defined $subtree->{ "child" }
	 and scalar keys %{ $subtree->{ "child" } } ){
	my $dir_name = sanitize_name( $subtree->{ "title" } );
	debug("creating and entering directory $dir_name.");
	mkdir $dir_name
	    || die "cannot create directory: $!";
	chdir $dir_name
	    || die "could not change into directory: $!";
	debug(qq#current cwd is # . cwd() . qq#.#);
    }

=comment
	
creating a file to place the content inside.
because a directory cannot have content the body is put
into a file named after the directory.
pages inside Confluence all have unique names
inside a space therefor conflicts are not expected.

=cut
    if ( defined $subtree->{ "body" }
	 and length $subtree->{ "body" } ){

        MacroProcess::macros_convert( \%{$subtree}, \%{ $spaces->{"users"} } );

	append_attachments( \%{$subtree} );
	
	my $filename = sanitize_name( $subtree->{ "title" } ) . ".html";
	debug("creating file with filename $filename.");
	write_file( $filename,
		    {binmode => ':utf8'},
		    $subtree->{ "body" }
	    ) || die "cannot write to file $filename: $!";
    }

    foreach my $child_id ( keys %{ $subtree->{ "child" } } ){
	debug("processing child $child_id.");
	process_child( \%{ $subtree->{ "child" }->{ $child_id } } );
    }
    debug("all children were processed.");

    if ( defined $subtree->{ "child" }
	 and scalar keys %{ $subtree->{ "child" } } ){
	debug("going one directory up.");
	chdir "..";
	debug(qq#current cwd is # . cwd() . qq#.#);
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
