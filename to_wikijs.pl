#!/usr/bin/perl

use strict;
use warnings "all";
use Cwd;
use Getopt::Std;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Encode;

BEGIN { unshift @INC, '.'; }
use MacroProcess;
use TreeWalk;

use YAML::XS;
use File::Slurp;
use MIME::Types;
use IPC::Run3 qw( run3 );
use Sys::Binmode;

use utf8;
use Carp qw(confess cluck);
BEGIN {
    *CORE::GLOBAL::warn = \&cluck;
    *CORE::GLOBAL::die = \&confess;
}

$| = 1;
my $DEBUG="false";

=comment

switches:

a - inline attachments at the end of the html file
m - html is converted to markdown before being written to file
d - enable debug output

=cut
our ( $opt_d, $opt_m , $opt_a);
$opt_d=0;

getopts('dm');

$DEBUG="true" if ( $opt_d eq 1 );

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

# my $spaces;
# {
#     local $/=undef;
#     $spaces = Load(<STDIN>);
# }

my $spaces = YAML::XS::LoadFile("export.yml");

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

    my @title_mappings;
    
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
		my $dir_name = lc( sanitize_name( $node->{ "title" } ));
		debug("creating and entering directory $dir_name.");
		mkdir $dir_name
		    || die "cannot create directory: $!";
		chdir $dir_name
		    || die "could not change into directory: $!";
		debug("current cwd is " . cwd() . ".");
	    }

	    debug("Processing page with title ".$node->{"title"}.".");
	    MacroProcess::macros_convert( \%{$node}, \%{ $spaces->{"users"} } );
	    append_attachments( \%{$node} )
		if (defined $opt_a && $opt_a eq 1);
	    my $filename;
	    my $content;
	    utf8::encode $node->{ "body" };
	    if ( defined $opt_m && $opt_m eq 1 ){
		my @pandoc_command = qw ( pandoc --from html --to markdown );
	        run3( \@pandoc_command,
		      \$node->{ "body" },
		      \$content,
		      \undef, 
		      { binmode_stdin => ":utf8",
		    binmode_stdout => ":utf8"} )
		    || die "could not convert using pandoc program: $?";
	        $filename = lc( sanitize_name( $node->{ "title" } )) . ".md";
	    } else {
	        $filename = lc( sanitize_name( $node->{ "title" } )) . ".html";
		$content = $node->{ "body" };
	    }
	    utf8::encode($filename);
	    push @title_mappings, "\'" .$node->{ "title" } ."\'|\'" . $filename . "\'";
	    debug("creating file with filename $filename.");
	    # write_file( $filename,
	    # 		{binmode => ':utf8'},
	    # 		$content )
	    # 	|| die "cannot write to file $filename: $!";
	    open my $file, '>:encoding(UTF-8)', $filename
		       || die "cannot open to file $filename: $!";
	    #binmode $file, ":encoding(UTF-8)";
	    print {$file} $content;
	    close $file;
	    $signal = "";
	}
    }
    open my $mappings_file, '>:raw', "title_mappings.txt"
	|| die "cannot open to file title_mappings.txt: $!";
    foreach ( @title_mappings ) {
	utf8::encode( $_ );
	print $mappings_file "$_\n";
    }
    close $mappings_file;
}

sub sanitize_name {
    my $string=shift @_;
=comment

removing or replacing reserved and unsafe characters
that could or can cause problems inside URLs
and pathnames.

=cut
    $string =~ s/[\$#@~!&*()\[\]<>;,:?^'"`\\\/]//g;
    $string =~ s/\s-\s/-/g;
    $string =~ s/(?:\s)+/-/g;
    $string =~ s/\./-/g;
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
