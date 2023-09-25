#!/usr/bin/perl

use strict;
use warnings;
use utf8;

BEGIN { unshift @INC, '.'; }
use MacroProcess;
use TreeWalk;

use YAML::XS;
use File::Slurp;
use MIME::Types;
use LWP::UserAgent;
use Mozilla::CA;
use JSON;
use MIME::Base64;
use Text::Unidecode;

use Carp qw(confess cluck);
BEGIN {
    *CORE::GLOBAL::warn = \&cluck;
    *CORE::GLOBAL::die = \&confess;
}

binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';
$| = 1;
my $DEBUG="true";
my $DOMAIN="";
my $TOKEN_ID="";
my $TOKEN_SECRET="";

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

sub sanitize_filename;
sub debug;
sub append_attachments;
sub join_path;
sub api_call;
sub api_create_book;
sub api_create_chapter;
sub api_create_page;
sub api_append_attachments;

foreach my $id (keys %$spaces){
    next if ( $id eq "users" );
    debug("processing space id $id.");
    my $book_id = api_create_book( $spaces->{ $id }->{ "title" } );
    process_space( \%{ $spaces->{ $id } },
	$book_id );
}

sub process_space {
    my $space = shift @_;
    my $book_id = shift @_;
    TreeWalk::walk( $space );
    my @node_list = @TreeWalk::node_list;
    my @path_directory_list;
    my %chapters;
    my $chapter_id;
    my $signal = "CURRENT";
    shift @node_list;

    foreach my $node ( @node_list ){
	if ( $node eq "UP" ) {
	    $signal = $node;
	    debug("Signal switched to $signal.");
	}
	elsif ( $node eq "DOWN" ) {
	    $signal = $node;
	    debug("Signal switched to $signal.");
	    debug("removing one directory from path.");
	    pop @path_directory_list; 
	    unless ( scalar @path_directory_list ){
		undef $chapter_id ;
	    }
	    else {
		debug("new path is ".join_path( \@path_directory_list ).".");
		$chapter_id = $chapters{ join_path( \@path_directory_list ) };
	    }
	} 
	elsif ( $node eq "CURRENT" ) {
	    $signal = $node;
	    debug("Signal switched to $signal.");
	}
	else {
	    if ( $signal eq "UP" ) {
		debug("adding directory to path.");
		push @path_directory_list, $node->{ "title" };
		debug("new path is " .join_path( \@path_directory_list ). ".");
	        $chapter_id = api_create_chapter( join_path( \@path_directory_list ),
						  $book_id );
		$chapters{ join_path( \@path_directory_list ) } = $chapter_id;
	    }
 
	    debug("Processing page with title ".$node->{"title"}.".");
	    MacroProcess::macros_convert( \%{$node}, \%{ $spaces->{"users"} } );
	    my $page_id = api_create_page( \%{$node},
					   $chapter_id,
					   $book_id );
	    
	    append_attachments( \%{$node},
				$page_id );
	    
	    $signal = "";
	}
    }
}

sub debug {
    my $message = shift @_;
    print STDERR $message . "\n" if $DEBUG eq "true";
}

sub api_call {
    my $api_path = shift @_;
    my $body     = shift @_;
    
    my $api_request = LWP::UserAgent->new();
    debug("sending api call to ". $DOMAIN .$api_path ." .");
    my $response = $api_request->post( $DOMAIN.$api_path,
				       $body,
				       "Authorization" => "Token $TOKEN_ID:$TOKEN_SECRET");
    if ($response->is_success) {
	return $response->decoded_content();
    }
    else {
	die $response->status_line;
    }
}

sub api_create_book {
    my $name = shift @_;

    my %body;
    $body{ "name" } = $name;
    debug("creating book with name $name.");

    my $json_answer = decode_json( api_call("/api/books",
					    \%body ));
    debug("book with name $name and id ".$json_answer->{ "id" }."created.");
    return $json_answer->{ "id" };
    
}

sub api_create_chapter {
    my $name = shift @_;
    my $book_id = shift @_;

    my %body;
    $body{ "name" } = $name;
    $body{ "book_id" } = $book_id;
    debug("creating chapter with name $name.");

    my $json_answer = decode_json( api_call("/api/chapters",
					    \%body ));
    debug("chapter with name $name created.");
    return $json_answer->{ "id" };
}

sub api_create_page {
    my $node = shift @_;
    my $chapter_id = shift @_;
    my $book_id = shift @_;

    my %body;
    if ( defined $chapter_id ){
	$body{ "chapter_id" } = $chapter_id;
    }
    else {
	$body{ "book_id" } = $book_id;
    }
    $body{ "name" } = $node->{ "title" };
    $body{ "html" } = $node->{ "body" };

    my $json_answer = decode_json( api_call("/api/pages",
					    \%body ));
    debug("page with name ". $node->{ "title" } ." created.");
    return $json_answer->{ "id" };
}

sub append_attachments {
    my $subtree = shift @_;
    my $page_id = shift @_;

    foreach my $attachment ( keys %{ $subtree->{ "attachments" } } ){
	debug("Appending attachment $attachment.");
        my $api_request = LWP::UserAgent->new();
	# $api_request->default_header('Content_Type' => 'form-data;boundary=xYzZYX');
	
	#my $file = decode_base64 $subtree->{ "attachments" }->{ $attachment };
	my $mime_type = MIME::Types->new();
	my $type = $mime_type->mimeTypeOf( $attachment );
	
	# my $url = $DOMAIN."/api/attachements";
	# my $header = ['Content-Type' => 'multipart/form-data'];
	# my $request = HTTP::Request->new("POST",
	# 				 $url,
	# 				 $header,
	# 				 $file);
	# $request->header( "Authorization" => "Token $TOKEN_ID:$TOKEN_SECRET" );
	my $response;
	# TODO: not all attachments can be uploaded due to UTF8 decoding problems
	eval { $response = $api_request->post( $DOMAIN . "/api/attachments",
					   [ "uploaded_to" => $page_id,
					     "name" => $attachment,
					     "file" => [
						 undef,
						 $attachment,
						 "Content-Type" => "$type",
						 "Content" =>
						 decode_base64(
							 $subtree->{ "attachments" }->{ $attachment }
						     )
					     ],
					   ],
					   "Content-Type"  => "form-data",
						 "Authorization" => "Token $TOKEN_ID:$TOKEN_SECRET" );};
	$DB::single = 1 if $@;
	#my $response = $api_request->request($request);
	
	unless ( $response->is_success ) {
	    die $response->as_string unless ( $response->code == 422 );
	}	   
    }
}

sub join_path {
    my $list = shift @_;
    return join "/", @{ $list };
}
