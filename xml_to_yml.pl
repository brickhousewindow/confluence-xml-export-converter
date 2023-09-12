#!/usr/bin/perl

use strict;
use warnings;

use XML::LibXML;
use YAML::XS;
use File::Slurp;
use MIME::Base64;

my $DEBUG="false";

my $filename = 'entities.xml';
my $dom = XML::LibXML->load_xml(location => $filename) or die "Could not read file!";

=comment

%spaces {
        %space_id {
                  $title
                  $body
                  %attachments { $name }
                  %child {
                         %page_id {
                                  $title
                                  $body
                                  %attachments { $name }
                                  %child { ...
                         %page_id { ...
%users {
       %id {
           $name
           $email
=cut               

my $spaces={};

sub debug;

###
#
# extracting information about the spaces itself
#
my @space_ids;

foreach my $space ($dom->findnodes('//object[@class="Space"]')) {
    my $space_id = $space->findvalue('./id[@name="id"]');
    debug "found space with id $space_id.";
    $spaces->{ $space_id }->{"name"}  = $space->findvalue('./property[@name="name"]');
    debug "found name of space $space_id," .$spaces->{ $space_id }->{"name"}. ".";
    my $space_homepage_id=$space->findvalue('./property[@name="homePage"]/id');
    push(@space_ids,$space_id.":".$space_homepage_id);
    my $homepage=$dom->findnodes('//object[@class="Page"]/id[text()='.$space_homepage_id.']/..');
    #using only the first element assuming that there is only one homepage
    $spaces->{ $space_id }->{"title"} = $homepage->[0]->findvalue('./property[@name="title"]');
    my $homepage_bodycontent_id=$homepage->[0]->findvalue('./collection[@name="bodyContents"]/element[@class="BodyContent"]/id');
    $spaces->{ $space_id }->{"body"}  = $dom->findvalue('//object[@class="BodyContent"]/id[text()="'.$homepage_bodycontent_id.'"]/../property[@name="body"]'); 
}

=comment

recursively following the page hierarchie.
because a page can contain content and other pages
like a node can be a file and directory at the same time
the page content is put into a page called index.

first we loop over the pages inside the space root

=cut
sub process_children;

foreach my $id_tuple (@space_ids){
    (my $space_id, my $homepage_id)=split(":", $id_tuple);
    
    foreach my $child_subtree ($dom->findnodes('//object[@class="Page"]/property[@name="parent"]/id[text()='
					       .$homepage_id
					       .']/../..') ){
	next if ( $child_subtree->findvalue('./property[@name="contentStatus"]') ne "current" );
	my $page_id = $child_subtree->findvalue('./id');
	debug "found page with id $page_id.";
        $spaces->{ $space_id }->{ "child" }->{ $page_id }={};
	debug "processing the child pages.";
	process_children($child_subtree, \%{ $spaces->{ $space_id }->{ "child" }->{ $page_id }  });
    }
}

sub process_children {
    # $child is a xml subtree object
    my $child = shift(@_);
    my $subtree = shift(@_);
    my $page_id  =$child->findvalue('./id');
    my $space_id =$child->findvalue('./property[@name="space"]/id');
    
    # getting the title
    $subtree->{ "title" } = $child->findvalue('./property[@name="title"]');
    debug "set title to " .$subtree->{ "title" }. ".";
    
    #getting the body content from another object
    my $body_id = $child->findvalue('./collection[@name="bodyContents"]/element[@class="BodyContent"]/id');
    if ( $body_id ){
	my $body_subtree = $dom->findnodes('//object[@class="BodyContent"]/id[text()="'
					   .$body_id
					   .'"]/..');
	$subtree->{ "body" } = $body_subtree->[0]->findvalue('./property[@name="body"]');
    }

    # getting the attachments and appending them as base64 string
    if ( length $child->findnodes('./collection[@name="attachments"]') ) {
	my $attachment_id_string = $child->findvalue('./collection[@name="attachments"]');
	my @attachment_id_list = split('\n\n',$attachment_id_string);
	foreach my $attachment_id ( @attachment_id_list ) {
	    my ( $attachment_subtree ) = $dom->findnodes('//object[@class="Attachment"]/id[text()="'
						       .$attachment_id
						       .'"]/..');
	    my $attachment_name = $attachment_subtree->findvalue('./property[@name="title"]');
	    my $attachment_version = $attachment_subtree->findvalue('./property[@name="version"]');
	    # archaic methed because it is being written for perl version 5.30.3
	    eval {
		my $attachment_body = encode_base64(
		    read_file( "attachments/"
			       . $page_id . "/"
			       . $attachment_id . "/"
			       . $attachment_version,
			       { binmode=> ":raw" }	  
		    ));
		$subtree->{ "attachments" }->{ $attachment_name } = $attachment_body;
		1;
	    } or do {
		my $e = $@;
		debug("could not get attachment data for attachment $attachment_id version $attachment_version on page $page_id: $e");
	    }
	}
    }
    
    # getting list of children
    my $children_subtree = $dom->findnodes('//object[@class="Page"]/id[text()="'
					   . $page_id
					   .'"]/..');
    # the string contains all values inside one string
    # assuming that only one element is required
    my $children_list_string=$children_subtree->[0]->findvalue('./collection[@name="children"]');
    my @children_id_list=split('\n\n',$children_list_string);
    foreach my $child_id (@children_id_list){
	( my $child_page_subtree )=$dom->findnodes('//object[@class="Page"]/id[text()="'
					       . $child_id
					       . '"]/..');
	next if ( $child_page_subtree->findvalue('./property[@name="contentStatus"]') ne "current" );
	$subtree->{ "child" }={} unless ( defined $subtree->{ "child" } );
	process_children($child_page_subtree, \%{ $subtree->{ "child" }->{ $child_id } });
    }
}

=comment

searching for user information. it is appended to the root of the tree
as its own node.

=cut

$spaces->{ "users" }={};

foreach my $user_node ( $dom->findnodes('//object[@class="ConfluenceUserImpl"]') ){
    my $user_id = $user_node->findvalue('./id[@name="key"]');
    $spaces->{ "users" }->{ $user_id }={}
      unless ( defined $spaces->{ "users" }->{ $user_id } );
    $spaces->{ "users" }->{ $user_id }->{ "name" }  = $user_node->findvalue('./property[@name="name"]');
    $spaces->{ "users" }->{ $user_id }->{ "email" } = $user_node->findvalue('./property[@name="email"]');
}

print Dump( $spaces );

sub debug {
    my $message = shift @_;
    print STDERR $message."\n" if ( $DEBUG eq "true");
}
