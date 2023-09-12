package MacroProcess;

use strict;
use warnings;

use feature "switch";
use Encode qw(decode encode);

use HTML::Entities;
use XML::LibXML;

binmode STDERR, ':utf8';

my $DEBUG="true";

my $debug = sub {
    my $message = shift @_;
    print STDERR $message . "\n" if $DEBUG eq "true";
};

my $macro_images = sub {
    my $tree    = shift @_;
    my $subtree = shift @_;

    foreach my $image_node ( $tree->findnodes('//ac:image') ){
	$debug->("Found image node ".$image_node->toString.".");
	my $image_tag = XML::LibXML::Element->new("img");
	
	###
	#
	# collecting all attributes for the image tag
	#
	my %image_attributes;
	if ( $image_node->hasAttributes() ){
	    foreach my $attribute ( $image_node->attributes() ){
		$image_tag->setAttribute( $attribute->localName(),
					  $attribute->value );
	    }
	}

	###
	#
	# looking up the filename
	# then getting the extension via a regex
	#
	if ( $image_node->exists('./ri:attachment/@ri:filename') ){
	    my $file_name = $image_node->findvalue('./ri:attachment/@ri:filename');
	    my ($file_format) = $file_name =~ /\.([^.]+)$/;
	    my $src_string = "data:image/"
		. $file_format
		. ";base64,"
		. $subtree->{ "attachments" }->{ $file_name };
	    $image_tag->setAttribute( "src",
				      $src_string );

	} elsif ( $image_node->exists('./ri:url/@ri:value')) {
	    $image_tag->setAttribute( "src",
				      $image_node->findvalue('./ri:url/@ri:value')
		);

	} else {
	    $debug->("No image source or date was found!");
	}
	
	$image_node->replaceNode( $image_tag );
	#my ( $image_node_body ) = $image_node->findnodes('/body');
	#$subtree->{ "body" } = decode_entities( $image_node_body->toString );
    }
};

my $macro_symbols = sub {
    my $tree    = shift @_;
    my $subtree = shift @_;

    foreach my $symbol_node ( $tree->findnodes('//ac:emoticon') ){
	$debug->("Found emoticon node ".$symbol_node->toString.".");
	my $symbol_node_parent = $symbol_node->parentNode;
	my $symbol_name = $symbol_node->findvalue('./@ac:name');
	my $symbol_unicode;
	for ($symbol_name) {
	    when (/^tick$/)     { $symbol_unicode = "\N{CHECK MARK}" }
	    when (/^cross$/)    { $symbol_unicode = "\N{BALLOT X}" }
	    when (/^question$/) { $symbol_unicode = "?" }
	    when (/^warning$/)  { $symbol_unicode = "!" }
	    when (/^smile$/)    { $symbol_unicode = "\N{SLIGHTLY SMILING FACE}" }
	    default       {
		$symbol_unicode = " ";
		$debug->("Unknown symbol name: $symbol_name");
		    }
	}
	my $symbol_new = XML::LibXML::Text->new( $symbol_unicode );
	$symbol_node_parent->insertBefore( $symbol_new, $symbol_node );
	$symbol_node->unbindNode;
	print "";
    }
};

my $macro_tasklist = sub {
    my $tree    = shift @_;
    my $subtree = shift @_;

=comment
	
it seems that the returned list containes the nodes in
order of the depth.
assuming that this is always the case the list is being
processed in reverse order.

=cut
    my $task_node_list = $tree->findnodes('//ac:task-list');
    if ( $task_node_list->size ) {
	my $task_node_list_size = $task_node_list->size;
	while ( $task_node_list->size ){
	    my $tasklist_node = $task_node_list->pop;
	    $debug->("Found tasklist.");
	    my $list_tag = XML::LibXML::Element->new("ul");

	    foreach my $tasklist_element ( $tasklist_node->findnodes('.//ac:task') ){
		# $debug->("Processing task element ".$tasklist_element->toString.".");
		my $list_element = XML::LibXML::Element->new("li");
		my $list_element_body = ( $tasklist_element->findnodes('./ac:task-body') )[0]->toString;
=comment

because the html tags inside the body are treaded as nodes by the xml library
the whole node is taken as a string ans the outer ac:task:body tag is stripped.
a more xml-ly method is unknown.
=cut
		$list_element_body=~ s/<\/ac:task-body>//;
		$list_element_body=~ s/<ac:task-body>//;
		$list_element->appendTextNode( $list_element_body );
		$list_tag->appendChild( $list_element );
	    }
	    $tasklist_node->replaceNode( $list_tag );
	}
    }
};

my $macro_usermention = sub {
    my $tree    = shift @_;
    my $subtree = shift @_;
    my $users   = shift @_;

    foreach my $usermention_node ( $tree->findnodes('//ac:link/ri:user/..') ){
	$debug->("Found user mention macro.");
	my $userkey = $usermention_node->findvalue('./ri:user/@ri:userkey');
	my $username = "@" . $users->{ $userkey }->{ "name" };
	my $user_tag = XML::LibXML::Element->new("strong");
	$user_tag->appendTextNode( $username );
	$usermention_node->replaceNode( $user_tag );
    }
};

my $macro_code = sub {
     my $tree    = shift @_;
     my $subtree = shift @_;

     foreach my $code_node (
	 $tree->findnodes('//ac:structured-macro[@ac:name="code"]')
	 ){
	 $debug->("Found code macro.");
	 my $paragraph_tag = XML::LibXML::Element->new("p");
	 my $pre_tag       = XML::LibXML::Element->new("pre");
	 my $code_tag      = XML::LibXML::Element->new("code");
	 $pre_tag->appendChild( $code_tag );
	 $paragraph_tag->appendChild( $pre_tag );
	 my $code_body = $code_node->findvalue('./ac:plain-text-body');
=comment

because the code might contain HTML it is encoded using url coding
to prevent being decoded or encoded by the ampersand coding.

=cut
	 #$code_body = url_encode_utf8( $code_body );
	 $code_tag->appendTextNode( $code_body );
	 $code_tag->setAttribute( "class",
				  $code_node->findvalue('./ac:parameter[@ac:name="language"]')
	     );
	 $code_node->replaceNode( $paragraph_tag );
     }
};

sub macros_convert {
    my $subtree = shift @_;
    my $users   = shift @_;

=comment
	
adding body tags and namespace information
otherwise the xml library is going to have trouble processing the
page content.

=cut
    $debug->("Adding outer body tag with namespace information.");
    my $body_tag_string = '<body xmlns:ac="http://atlassian.confluence" xmlns:ri="http://atlassian.ressource" >';
    my $body = $body_tag_string . $subtree->{ "body" } . "</body>";
    
=comment

the ampersand (&) encoded string are entities inside the xml document
yet disabling their expansion still causes errors inside libxml.
therefor the Entities library is used to convert these to unicode.
all ampersand symbols are then encoded. the libxml library is then not
going to complain about these.
then the document is converted to UTF8 because otherwise the libxml
throws an error.

this process is finicky and not completely understood.

=cut
    #$body = encode( "utf8" ,decode_entities( $body ));
    $body = encode( "utf8" ,$body );
    $body =~ s/&/&#038;/g;
    $body =~ s/\]\]\ >/\]\]>/g;
    my $tree=XML::LibXML->load_xml(
	string => $body,
	expand_entities =>0,
	recover => 1
	) || die "Could not load xml document from string!" ;
    $debug->("Processing possible image macros.");
    $macro_images->($tree, $subtree);
    
    $debug->("Processing possible emoticon macros.");
    $macro_symbols->($tree, $subtree);
    
    $debug->("Processing possible tasklist macros.");
    $macro_tasklist->($tree, $subtree);
    
    $debug->("Processing possible user mention macros.");
    $macro_usermention->($tree, $subtree, $users);

    $debug->("Processing possible code macros.");
    $macro_code->($tree, $subtree);

    $subtree->{ "body" } = $tree->toString;

=comment

for some unknown reasons not all ampersand encoded entities
are being decodes during the function call.
it is necessary to call this function multiple.

=cut

    while ( $subtree->{ "body" } =~ /&lt;|&gt;|&amp;/ ){
	$debug->("Found encoded entities, decoding these.");
	decode_entities $subtree->{ "body" };
    }

    #$subtree->{ "body" } = url_decode_utf8( $subtree->{ "body" } );
    
    ###
    #
    # removing the body tags and the namespace information 
    #
    $debug->("Removing outer body tags with namespaces.");
    $subtree->{ "body" } =~ s#$body_tag_string##;
    $subtree->{ "body" } =~ s#</body>##;
}

1;
