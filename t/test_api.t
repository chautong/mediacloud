#!/usr/bin/env perl

# general test of api end popints

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";

}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use HTTP::HashServer;
use Readonly;
use Test::More;
use Test::Deep;

use MediaWords::DBI::Media::Health;
use MediaWords::DBI::Stats;
use MediaWords::Test::API;
use MediaWords::Test::DB;
use MediaWords::Test::Solr;
use MediaWords::Test::Supervisor;
use MediaWords::Util::Tags;
use MediaWords::Util::Web;

Readonly my $NUM_MEDIA            => 5;
Readonly my $NUM_FEEDS_PER_MEDIUM => 2;
Readonly my $NUM_STORIES_PER_FEED => 10;

# return tag in either { tags_id => $tags_id }or { tag => $tag, tag_set => $tag_set } form depending on $input_form
sub get_put_tag_input_tag($$$)
{
    my ( $tag, $tag_set, $input_form ) = @_;

    if ( $input_form eq 'id' )
    {
        return { tags_id => $tag->{ tags_id } };
    }
    elsif ( $input_form eq 'name' )
    {
        return { tag => $tag->{ tag }, tag_set => $tag_set->{ name } };
    }
    else
    {
        die( "unknown input_form '$input_form'" );
    }
}

# given a set of tags, return a list of hashes in the proper form for a put_tags call
sub get_put_tag_input_records($$$$$$)
{
    my ( $db, $table, $rows, $tag_sets, $input_form, $action ) = @_;

    my $id_field = $table . "_id";

    my $input = [];
    for my $add_tag_set ( @{ $tag_sets } )
    {
        for my $add_tag ( @{ $add_tag_set->{ add_tags } } )
        {
            for my $row ( @{ $rows } )
            {
                my $put_tag = get_put_tag_input_tag( $add_tag, $add_tag_set, $input_form );
                $put_tag->{ $id_field } = $row->{ $id_field };
                $put_tag->{ action } = $action;

                push( @{ $input }, $put_tag );
            }
        }
    }

    return $input;
}

# get the url for the put_tag end point for the given table
sub get_put_tag_url($;$)
{
    my ( $table, $clear ) = @_;

    my $url = ( $table eq 'story_sentences' ) ? '/api/v2/sentences/put_tags' : "/api/v2/$table/put_tags";

    $url .= '?clear_tag_sets=1' if ( $clear );

    return $url;
}

# test using put_tags to add the given tags to the given rows in the given table.
sub test_add_tags
{
    my ( $db, $table, $rows, $tag_sets, $input_form, $clear ) = @_;

    my $num_add_tag_sets = int( scalar( @{ $tag_sets } ) / 2 );
    my $num_add_tags     = int( scalar( @{ $tag_sets->[ 0 ]->{ tags } } ) / 2 );

    my $add_tag_sets = [ @{ $tag_sets }[ 0 .. $num_add_tag_sets - 1 ] ];
    map { $_->{ add_tags } = [ @{ $_->{ tags } }[ 0 .. $num_add_tags - 1 ] ] } @{ $add_tag_sets };

    my $put_tags = get_put_tag_input_records( $db, $table, $rows, $add_tag_sets, $input_form, 'add' );

    my $r = test_put( get_put_tag_url( $table, $clear ), $put_tags );

    my $map_table    = $table . "_tags_map";
    my $id_field     = $table . "_id";
    my $row_ids      = [ map { $_->{ $id_field } } @{ $rows } ];
    my $row_ids_list = join( ',', @{ $row_ids } );

    my $add_tags = [];
    map { push( @{ $add_tags }, @{ $_->{ add_tags } } ) } @{ $add_tag_sets };

    my $clear_label = $clear ? 'clear' : 'no clear';
    my $label =
      "test add tags $table with $clear_label input $input_form [" .
      scalar( @{ $rows } ) . " rows / " .
      scalar( @{ $add_tags } ) . " add tags]";

    my $tags_ids_list = join( ',', map { $_->{ tags_id } } @{ $add_tags } );

    my ( $map_count ) = $db->query( <<SQL )->flat;
select count(*) from $map_table where $id_field in ( $row_ids_list ) and tags_id in ( $tags_ids_list )
SQL

    my $expected_map_count = scalar( @{ $rows } ) * scalar( @{ $add_tags } );
    is( $map_count, $expected_map_count, "$label map count" );

    my $maps = $db->query( <<SQL )->hashes;
select * from $map_table where $id_field in ( $row_ids_list ) and tags_id in ( $tags_ids_list )
SQL
    for my $map ( @{ $maps } )
    {
        my $row_expected = grep { $map->{ $id_field } == $_->{ $id_field } } @{ $rows };
        ok( $row_expected, "$label expected row $map->{ $id_field }" );

        my $tag_expected = grep { $map->{ $id_field } == $_->{ $id_field } } @{ $rows };
        ok( $tag_expected, "$label expected tag $map->{ tags_id }" );
    }

    # clean up so the next test has a clean slate
    $db->query( "delete from $map_table where $id_field in ( $row_ids_list ) and tags_id in ( $tags_ids_list )" );
}

# test removing tag associations
sub test_remove_tags
{
    my ( $db, $table, $rows, $tag_sets, $input_form ) = @_;

    my $map_table         = $table . "_tags_map";
    my $id_field          = $table . "_id";
    my $row_ids           = [ map { $_->{ $id_field } } @{ $rows } ];
    my $row_ids_list      = join( ',', @{ $row_ids } );
    my $tag_sets_ids_list = join( ',', map { $_->{ tag_sets_id } } @{ $tag_sets } );

    my $label = "test remove tags $table input $input_form";

    for my $row ( @{ $rows } )
    {
        $db->query( <<SQL, $row->{ $id_field } );
insert into $map_table ( $id_field, tags_id )
        select \$1, tags_id from tags where tag_sets_id in ( $tag_sets_ids_list )
SQL
    }

    map { $_->{ add_tags } = [ $_->{ tags }->[ 0 ] ] } @{ $tag_sets };

    my $put_tags = get_put_tag_input_records( $db, $table, $rows, $tag_sets, $input_form, 'remove' );
    my $r = test_put( get_put_tag_url( $table ), $put_tags );

    my $expected_map_count =
      scalar( @{ $tag_sets } ) * ( scalar( @{ $tag_sets->[ 0 ]->{ tags } } ) - 1 ) * scalar( @{ $rows } );

    my ( $map_count ) = $db->query( <<SQL )->flat;
select count(*)
    from $map_table join tags using ( tags_id )
    where $id_field in ( $row_ids_list ) and tag_sets_id in ( $tag_sets_ids_list )
SQL
    is( $map_count, $expected_map_count, "$label map count" );

    # clean up so the next test has a clean slate
    $db->query( <<SQL );
delete from $map_table
    using tags
    where $map_table.tags_id = tags.tags_id and
        $id_field in ( $row_ids_list ) and
        tag_sets_id in ( $tag_sets_ids_list )
SQL
}

# add all tags to the map, use the clear_tags= param, then make sure only added tags are associated
sub test_clear_tags($$$$$)
{
    my ( $db, $table, $rows, $tag_sets, $input_form ) = @_;

    my $map_table = $table . "_tags_map";
    my $id_field  = $table . "_id";

    my $tag_sets_ids_list = join( ',', map { $_->{ tag_sets_id } } @{ $tag_sets } );

    for my $row ( @{ $rows } )
    {
        $db->query( <<SQL, $row->{ $id_field } );
insert into $map_table ( $id_field, tags_id )
        select \$1, tags_id from tags where tag_sets_id in ( $tag_sets_ids_list )
SQL
    }

    test_add_tags( $db, $table, $rows, $tag_sets, $input_form, 1 );
}

# test /apiv/2/$table/put_tags call.  assumes that there are at least three rows in $table, which there should be
# from the create_test_story_stack() call
sub test_put_tags($$)
{
    my ( $db, $table ) = @_;

    my $url      = get_put_tag_url( $table );
    my $id_field = $table . "_id";

    my $num_tag_sets = 5;
    my $num_tags     = 10;

    my $tag_sets = [];
    for my $i ( 1 .. $num_tag_sets )
    {
        my $tag_set = $db->find_or_create( 'tag_sets', { name => "put tags $i" } );
        for my $i ( 1 .. $num_tags )
        {
            my $tag = $db->find_or_create( 'tags', { tag => "tag $i", tag_sets_id => $tag_set->{ tag_sets_id } } );
            push( @{ $tag_set->{ tags } }, $tag );
        }
        push( @{ $tag_sets }, $tag_set );
    }

    my $first_tags_id = $tag_sets->[ 0 ]->{ tags }->[ 0 ];

    my $num_rows = 3;
    my $rows     = $db->query( "select * from $table limit $num_rows" )->hashes;

    my $first_row_id = $rows->[ 0 ]->{ "${ table }_id" };

    # test that api recognizes various errors
    test_put( $url, {}, 1 );    # require list
    test_put( $url, [ [] ], 1 );    # require list of records
    test_put( $url, [ { tags_id   => $first_tags_id } ], 1 );    # require id
    test_put( $url, [ { $id_field => $first_row_id } ],  1 );    # require tag

    test_add_tags( $db, $table, $rows, $tag_sets, 'id' );
    test_add_tags( $db, $table, $rows, $tag_sets, 'name' );
    test_remove_tags( $db, $table, $rows, $tag_sets, 'id' );

    test_clear_tags( $db, $table, $rows, $tag_sets, 'id' );
}

# test tags/list
sub test_tags_list($)
{
    my ( $db ) = @_;

    my $num_tags = 10;
    my $label    = "tags list";

    my $tag_set     = $db->create( 'tag_sets', { name => 'tag list test' } );
    my $tag_sets_id = $tag_set->{ tag_sets_id };
    my $input_tags  = [ map { { tag => "tag $_", label => "tag $_", tag_sets_id => $tag_sets_id } } ( 1 .. $num_tags ) ];
    map { test_post( '/api/v2/tags/create', $_ ) } @{ $input_tags };

    # query by tag_sets_id
    my $got_tags = test_get( '/api/v2/tags/list', { tag_sets_id => $tag_sets_id } );
    is( scalar( @{ $got_tags } ), $num_tags, "$label number of tags" );

    for my $got_tag ( @{ $got_tags } )
    {
        my ( $input_tag ) = grep { $got_tag->{ tag } eq $_->{ tag } } @{ $input_tags };
        ok( $input_tag, "$label found input tag" );
        map { is( $got_tag->{ $_ }, $input_tag->{ $_ }, "$label field $_" ) } keys( %{ $input_tag } );
    }

    my ( $t0, $t1, $t2, $t3 ) = @{ $got_tags };

    # test public= query
    test_put( '/api/v2/tags/update', { tags_id => $t0->{ tags_id }, show_on_media   => 1 } );
    test_put( '/api/v2/tags/update', { tags_id => $t1->{ tags_id }, show_on_stories => 1 } );
    my $got_public_tags = test_get( '/api/v2/tags/list', { public => 1, tag_sets_id => $tag_sets_id } );
    is( scalar( @{ $got_public_tags } ), 2, "$label show_on_media count" );
    ok( ( grep { $_->{ tags_id } == $t0->{ tags_id } } @{ $got_public_tags } ), "$label public show_on_media" );
    ok( ( grep { $_->{ tags_id } == $t1->{ tags_id } } @{ $got_public_tags } ), "$label public show_on_stories" );

    # test similar_tags_id
    my $medium = $db->query( "select * from media limit 1" )->hash;
    map { $db->create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $_->{ tags_id } } ) }
      ( $t0, $t1, $t2 );
    my $got_similar_tags = test_get( '/api/v2/tags/list', { similar_tags_id => $t0->{ tags_id } } );
    is( scalar( @{ $got_similar_tags } ), 2, "$label similar count" );
    ok( ( grep { $_->{ tags_id } == $t1->{ tags_id } } @{ $got_similar_tags } ), "$label similar tags_id t1" );
    ok( ( grep { $_->{ tags_id } == $t2->{ tags_id } } @{ $got_similar_tags } ), "$label simlar tags_id t2" );
}

# test tags/single
sub test_tags_single($)
{
    my ( $db ) = @_;

    my $label = "tags/single";

    my $expected_tag = $db->query( "select * from tags order by tags_id limit 1" )->hash;

    my $got_tags = test_get( '/api/v2/tags/single/' . $expected_tag->{ tags_id } );

    my $got_tag = $got_tags->[ 0 ];

    ok( $got_tag, "$label found tag" );

    my $fields = [ qw/tags_id tag_sets_id tag label description show_on_media show_on_stories is_static/ ];
    map { is( $got_tag->{ $_ }, $expected_tag->{ $_ }, "$label field $_" ) } @{ $fields };
}

# test tags create, update, list, and association
sub test_tags($)
{
    my ( $db ) = @_;

    # test for required fields errors
    test_post( '/api/v2/tags/create', { tag   => 'foo' }, 1 );    # should require label
    test_post( '/api/v2/tags/create', { label => 'foo' }, 1 );    # should require tag
    test_put( '/api/v2/tags/update', { tag => 'foo' }, 1 );       # should require tags_id

    my $tag_set = $db->create( 'tag_sets', { name => 'foo tag set' } );

    # simple tag creation
    my $create_input = {
        tag_sets_id     => $tag_set->{ tag_sets_id },
        tag             => 'foo tag',
        label           => 'foo label',
        description     => 'foo description',
        show_on_media   => 1,
        show_on_stories => 1,
        is_static       => 1
    };

    my $r = test_post( '/api/v2/tags/create', $create_input );
    validate_db_row( $db, 'tags', $r->{ tag }, $create_input, 'create tag' );

    # error on update non-existent tag
    test_put( '/api/v2/tags/update', { tags_id => -1 }, 1 );

    # simple update
    my $update_input = {
        tags_id         => $r->{ tag }->{ tags_id },
        tag             => 'bar tag',
        label           => 'bar label',
        description     => 'bar description',
        show_on_media   => 0,
        show_on_stories => 0,
        is_static       => 0
    };

    $r = test_put( '/api/v2/tags/update', $update_input );
    validate_db_row( $db, 'tags', $r->{ tag }, $update_input, 'update tag' );

    # simple tags/list test
    test_tags_list( $db );
    test_tags_single( $db );

    # test put_tags calls on all tables
    test_put_tags( $db, 'stories' );
    test_put_tags( $db, 'story_sentences' );
    test_put_tags( $db, 'media' );

}

# test tag set create, update, and list
sub test_tag_sets($)
{
    my ( $db ) = @_;

}

# test feeds/list and single
sub test_feeds_list($)
{
    my ( $db ) = @_;

    my $label = "feeds/list";

    my $medium = MediaWords::Test::DB::create_test_medium( $db, $label );

    map { MediaWords::Test::DB::create_test_feed( $db, "$label $_", $medium ) } ( 1 .. 10 );

    my $expected_feeds = $db->query( "select * from feeds where media_id = ?", $medium->{ media_id } )->hashes;

    my $got_feeds = test_get( '/api/v2/feeds/list', { media_id => $medium->{ media_id } } );

    my $fields = [ qw/name url feed_type media_id/ ];
    rows_match( $label, $got_feeds, $expected_feeds, "feeds_id", $fields );

    $label = "feeds/single";

    my $expected_single = $expected_feeds->[ 0 ];

    my $got_feed = test_get( '/api/v2/feeds/single/' . $expected_single->{ feeds_id }, {} );
    rows_match( $label, $got_feed, [ $expected_single ], 'feeds_id', $fields );
}

# test feeds/* end points
sub test_feeds($)
{
    my ( $db ) = @_;

    # test for required fields errors
    test_post( '/api/v2/feeds/create', {}, 1 );
    test_put( '/api/v2/feeds/update', { name => 'foo' }, 1 );

    my $medium = $db->query( "select * from media limit 1" )->hash;

    # simple tag creation
    my $create_input = {
        media_id    => $medium->{ media_id },
        name        => 'feed name',
        url         => 'http://feed.create',
        feed_type   => 'syndicated',
        feed_status => 'active'
    };

    my $r = test_post( '/api/v2/feeds/create', $create_input );
    validate_db_row( $db, 'feeds', $r->{ feed }, $create_input, 'create feed' );

    # error on update non-existent tag
    test_put( '/api/v2/feeds/update', { feeds_id => -1 }, 1 );

    # simple update
    my $update_input = {
        feeds_id    => $r->{ feed }->{ feeds_id },
        name        => 'feed name update',
        url         => 'http://feed.create/update',
        feed_type   => 'web_page',
        feed_status => 'inactive'
    };

    $r = test_put( '/api/v2/feeds/update', $update_input );
    validate_db_row( $db, 'feeds', $r->{ feed }, $update_input, 'update feed' );

    $r = test_post( '/api/v2/feeds/scrape', { media_id => $medium->{ media_id } } );
    ok( $r->{ job_state }, "feeds/scrape job state returned" );
    is( $r->{ job_state }->{ media_id }, $medium->{ media_id }, "feeds/scrape media_id" );
    ok( $r->{ job_state }->{ state } ne 'error', "feeds/scrape job state is not an error" );

    $r = test_get( '/api/v2/feeds/scrape_status', { media_id => $medium->{ media_id } } );
    is( $r->{ job_states }->[ 0 ]->{ media_id }, $medium->{ media_id }, "feeds/scrape_status media_id" );

    $r = test_get( '/api/v2/feeds/scrape_status', {} );
    is( $r->{ job_states }->[ 0 ]->{ media_id }, $medium->{ media_id }, "feeds/scrape_status all media_id" );

    test_feeds_list( $db );
}

# test the media/submit_suggestion call
sub test_media_suggestions_submit($)
{
    my ( $db ) = @_;

    # make sure url is required
    test_post( '/api/v2/media/submit_suggestion', {}, 1 );

    # test with simple url
    my $simple_url = 'http://foo.com';
    test_post( '/api/v2/media/submit_suggestion', { url => $simple_url } );

    my $simple_ms = $db->query( "select * from media_suggestions where url = \$1", $simple_url )->hash;
    ok( $simple_ms, "media/submit_suggestion simple url found" );

    # test with all fields in input
    my $tag_1 = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'media_suggestions:tag_1' );
    my $tag_2 = MediaWords::Util::Tags::lookup_or_create_tag( $db, 'media_suggestions:tag_2' );

    my $full_ms_input = {
        url      => 'http://bar.com',
        name     => 'foo',
        feed_url => 'http://feed.url',
        reason   => 'bar',
        tags_ids => [ map { $_->{ tags_id } } ( $tag_1, $tag_2 ) ]
    };

    test_post( '/api/v2/media/submit_suggestion', $full_ms_input );

    my $full_ms_db = $db->query( "select * from media_suggestions where url = \$1", $full_ms_input->{ url } )->hash;
    ok( $full_ms_db, "media/submit_suggestion full input found" );

    for my $field ( qw/name feed_url reason/ )
    {
        is( $full_ms_db->{ $field }, $full_ms_input->{ $field }, "media/submit_suggestion full input $field" );
    }

    ok( $full_ms_db->{ date_submitted }, "media/submit_suggestion full date_submitted set" );

    for my $tag ( $tag_1, $tag_2 )
    {
        my $tag_exists = $db->query( <<SQL, $tag->{ tags_id }, $full_ms_db->{ media_suggestions_id } )->hash;
select * from media_suggestions_tags_map where tags_id = \$1 and media_suggestions_id = \$2
SQL
        ok( $tag_exists, "media/submit_suggestion full tag $tag->{ tags_id } exists" );
    }
}

# test that the media/list_suggestions call with the given $call_params returned the given results
sub test_suggestions_list_results($$$)
{
    my ( $label, $call_params, $expected_results ) = @_;

    $label = "media/list_suggestions $label";

    my $expected_num = scalar( @{ $expected_results } );

    my $r = test_get( '/api/v2/media/list_suggestions', $call_params );
    my $got_mss = $r->{ media_suggestions };
    ok( $got_mss, "$label media_suggestions set" );

    is( scalar( @{ $got_mss } ), $expected_num, "$label number returned" );

    my $prev_id = 0;
    for my $got_ms ( @{ $got_mss } )
    {
        my ( $expected_ms ) =
          grep { $_->{ media_suggestions_id } == $got_ms->{ media_suggestions_id } } @{ $expected_results };
        ok( $expected_ms, "$label returned ms $got_ms->{ media_suggestions_id } matches db row" );
        for my $field ( qw/status url name feed_url reason media_id mark_reason user/ )
        {
            is( $got_ms->{ $field }, $expected_ms->{ $field }, "$label field $field" );
        }
        ok( $got_ms->{ media_suggestions_id } > $prev_id, "$label media_ids in order" );
        $prev_id = $got_ms->{ media_suggestions_id };
    }

}

# test media/list_suggestions
sub test_media_suggestions_list($)
{
    my ( $db ) = @_;

    my $num_status_ms = 10;

    my ( $auth_users_id, $email ) = $db->query( "select auth_users_id from auth_users limit 1" )->flat;

    my $ms_db     = [];
    my $media_ids = $db->query( "select media_id from media" )->flat;

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "media_suggestions:test_tag" );

    for my $status ( qw/pending approved rejected/ )
    {
        for my $i ( 1 .. $num_status_ms )
        {
            my $ms = {
                url           => "http://m.s/$i",
                name          => "ms $i",
                feed_url      => "http://feed.m.s/$i",
                auth_users_id => $auth_users_id,
                reason        => "reason $i",
                status        => $status,
            };

            if ( $status ne 'pending' )
            {
                $ms->{ mark_reason } = "mark reason $i";
                $ms->{ date_marked } = MediaWords::Util::SQL::sql_now;
            }

            if ( $status eq 'approved' )
            {
                $ms->{ media_id } = shift( @{ $media_ids } );
                push( @{ $media_ids }, $ms->{ media_id } );
            }

            $ms = $db->create( 'media_suggestions', $ms );

            $ms->{ email } = $email;

            if ( $i % 2 )
            {
                $ms->{ tags_id } = [ $tag->{ tags_id } ];
                $db->query( <<SQL, $ms->{ media_suggestions_id }, $tag->{ tags_id } );
insert into media_suggestions_tags_map ( media_suggestions_id, tags_id ) values ( \$1, \$2 )
SQL
            }

            push( @{ $ms_db }, $ms );
        }
    }

    test_suggestions_list_results( 'pending', {}, [ grep { $_->{ status } eq 'pending' } @{ $ms_db } ] );
    test_suggestions_list_results( 'all', { all => 1 }, $ms_db );

    my $pending_tags_ms = [ grep { $_->{ status } eq 'pending' && $_->{ tags_id } } @{ $ms_db } ];
    test_suggestions_list_results( 'pending + tags_id', { tags_id => $tag->{ tags_id } }, $pending_tags_ms );

}

# test media/mark_suggestion end point
sub test_media_suggestions_mark($)
{
    my ( $db ) = @_;

    my ( $auth_users_id ) = $db->query( "select auth_users_id from auth_users limit 1" )->flat;

    my $ms = {
        url           => "http://m.s/mark",
        name          => "ms mark",
        feed_url      => "http://feed.m.s/mark",
        auth_users_id => $auth_users_id,
        reason        => "reason mark"
    };
    $ms = $db->create( 'media_suggestions', $ms );
    my $ms_id = $ms->{ media_suggestions_id };

    # test for required status and media_suggestions_id
    test_put( '/api/v2/media/mark_suggestion', {}, 1 );
    test_put( '/api/v2/media/mark_suggestion', { media_suggestions_id => $ms_id }, 1 );
    test_put( '/api/v2/media/mark_suggestion', { status => 'approved' }, 1 );

    # test for error on invalid input
    test_put( '/api/v2/media/mark_suggestion', { media_suggestions_id => 0,      status => 'approved' },       1 );
    test_put( '/api/v2/media/mark_suggestion', { media_suggestions_id => $ms_id, status => 'invalid_status' }, 1 );

    # test reject
    test_put( '/api/v2/media/mark_suggestion',
        { media_suggestions_id => $ms_id, status => 'rejected', mark_reason => 'rejected' } );
    $ms = $db->require_by_id( 'media_suggestions', $ms_id );

    is( $ms->{ status },      'rejected', "media/mark_suggestion reject status" );
    is( $ms->{ mark_reason }, 'rejected', "media/mark_suggestion reject mark_reason" );

    my ( $media_id ) = $db->query( "select media_id from media limit 1" )->flat;

    # test approve
    my $approve_input = {
        media_suggestions_id => $ms_id,
        status               => 'approved',
        mark_reason          => 'approved'
    };

    # verify that approval with media_id causes error
    test_put( '/api/v2/media/mark_suggestion', $approve_input, 1 );

    # now try valid submission
    $approve_input->{ media_id } = $media_id;
    test_put( '/api/v2/media/mark_suggestion', $approve_input );
    $ms = $db->require_by_id( 'media_suggestions', $ms_id );

    is( $ms->{ status },      'approved', "media/mark_suggestion approve status" );
    is( $ms->{ mark_reason }, 'approved', "media/mark_suggestion approve mark_reason" );
    is( $ms->{ media_id },    $media_id,  'media/mark_suggestion approve media_id' );

    # now try setting back to pending
    test_put( '/api/v2/media/mark_suggestion',
        { media_suggestions_id => $ms_id, status => 'pending', mark_reason => 'pending' } );
    $ms = $db->require_by_id( 'media_suggestions', $ms_id );

    is( $ms->{ status },      'pending', "media/mark_suggestion pending status" );
    is( $ms->{ mark_reason }, 'pending', "media/mark_suggestion pending mark_reason" );
}

# test media suggestions list, submit, and mark calls
sub test_media_suggestions($)
{
    my ( $db ) = @_;

    test_media_suggestions_list( $db );
    test_media_suggestions_submit( $db );
    test_media_suggestions_mark( $db );
}

# test topics/ create and update
sub test_topics_crud($)
{
    my ( $db ) = @_;
}

# test wc/list end point
sub test_wc_list($)
{
    my ( $db ) = @_;

    my $label = "wc/list";

    my $story = $db->query( "select * from stories order by stories_id limit 1" )->hash;

    my $sentences = $db->query( <<SQL, $story->{ stories_id } )->flat;
select sentence from story_sentences where stories_id = ?
SQL

    my $en = MediaWords::Languages::Language::language_for_code( 'en' );

    my $expected_word_counts = {};
    for my $sentence ( @{ $sentences } )
    {
        my $words = [ grep { length( $_ ) > 2 } split( /\W+/, lc( $sentence ) ) ];
        my $stems = $en->stem( @{ $words } );
        map { $expected_word_counts->{ $_ }++ } @{ $stems };
    }

    my $got_word_counts = test_get(
        '/api/v2/wc/list',
        {
            q                 => "stories_id:$story->{ stories_id }",
            languages         => 'en',                                 # set to english so that we can know how to stem above
            num_words         => 10000,
            include_stopwords => 1                                     # don't try to test stopwording
        }
    );

    is( scalar( @{ $got_word_counts } ), scalar( keys( %{ $expected_word_counts } ) ), "$label number of words" );

    for my $got_word_count ( @{ $got_word_counts } )
    {
        my $stem = $got_word_count->{ stem };
        ok( $expected_word_counts->{ $stem }, "$label word count for '$stem' is found but not expected" );
        is( $got_word_count->{ count }, $expected_word_counts->{ $stem }, "$label expected word count for '$stem'" );
    }
}

# test controversies/list and single
sub test_controversies($)
{
    my ( $db ) = @_;

    my $label = "controversies/list";

    map { MediaWords::Test::DB::create_test_topic( $db, "$label $_" ) } ( 1 .. 10 );

    my $expected_topics = $db->query( "select *, topics_id controversies_id from topics" )->hashes;

    my $got_controversies = test_get( '/api/v2/controversies/list', {} );

    my $fields = [ qw/controversies_id name pattern solr_seed_query description max_iterations/ ];
    rows_match( $label, $got_controversies, $expected_topics, "controversies_id", $fields );

    $label = "controversies/single";

    my $expected_single = $expected_topics->[ 0 ];

    my $got_controversy = test_get( '/api/v2/controversies/single/' . $expected_single->{ topics_id }, {} );
    rows_match( $label, $got_controversy, [ $expected_single ], 'controversies_id', $fields );
}

# test controversy_dumps/list and single
sub test_controversy_dumps($)
{
    my ( $db ) = @_;

    my $label = "controversy_dumps/list";

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );

    for my $i ( 1 .. 10 )
    {
        $db->create(
            'snapshots',
            {
                topics_id     => $topic->{ topics_id },
                snapshot_date => '2017-01-01',
                start_date    => '2016-01-01',
                end_date      => '2017-01-01',
                note          => "snapshot $i"
            }
        );
    }

    my $expected_snapshots = $db->query( <<SQL, $topic->{ topics_id } )->hashes;
select *, topics_id controversies_id, snapshots_id controversy_dumps_id
    from snapshots
    where topics_id = ?
SQL

    my $got_cds = test_get( '/api/v2/controversy_dumps/list', { controversies_id => $topic->{ topics_id } } );

    my $fields = [ qw/controversies_id controversy_dumps_id start_date end_date note/ ];
    rows_match( $label, $got_cds, $expected_snapshots, 'controversy_dumps_id', $fields );

    $label = 'controversy_dumps/single';

    my $expected_snapshot = $expected_snapshots->[ 0 ];

    my $got_cd = test_get( '/api/v2/controversy_dumps/single/' . $expected_snapshot->{ snapshots_id }, {} );
    rows_match( $label, $got_cd, [ $expected_snapshot ], 'controversy_dumps_id', $fields );
}

# test controversy_dump_time_slices/list and single
sub test_controversy_dump_time_slices($)
{
    my ( $db ) = @_;

    my $label = "controversy_dump_time_slices/list";

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );
    my $snapshot = $db->create(
        'snapshots',
        {
            topics_id     => $topic->{ topics_id },
            snapshot_date => '2017-01-01',
            start_date    => '2016-01-01',
            end_date      => '2017-01-01',
        }
    );

    my $metrics = [
        qw/story_count story_link_count medium_count medium_link_count tweet_count /,
        qw/model_num_media model_r2_mean model_r2_stddev/
    ];
    for my $i ( 1 .. 9 )
    {
        my $timespan = {
            snapshots_id => $snapshot->{ snapshots_id },
            start_date   => '2016-01-0' . $i,
            end_date     => '2017-01-0' . $i,
            period       => 'custom'
        };

        map { $timespan->{ $_ } = $i * length( $_ ) } @{ $metrics };
        $db->create( 'timespans', $timespan );
    }

    my $expected_timespans = $db->query( <<SQL, $snapshot->{ snapshots_id } )->hashes;
select *, snapshots_id controversy_dumps_id, timespans_id controversy_dump_time_slices_id
    from timespans
    where snapshots_id = ?
SQL

    my $got_cdtss =
      test_get( '/api/v2/controversy_dump_time_slices/list', { controversy_dumps_id => $snapshot->{ snapshots_id } } );

    my $fields = [ qw/controversy_dumps_id start_date end_date period/, @{ $metrics } ];
    rows_match( $label, $got_cdtss, $expected_timespans, 'controversy_dump_time_slices_id', $fields );

    $label = 'controversy_dump_time_slices/single';

    my $expected_timespan = $expected_timespans->[ 0 ];

    my $got_cdts = test_get( '/api/v2/controversy_dump_time_slices/single/' . $expected_timespan->{ timespans_id }, {} );
    rows_match( $label, $got_cdts, [ $expected_timespan ], 'controversy_dump_time_slices_id', $fields );
}

# test downloads/list and single
sub test_downloads($)
{
    my ( $db ) = @_;

    my $label = "downloads/list";

    my $medium = MediaWords::Test::DB::create_test_medium( $db, $label );
    my $feed = MediaWords::Test::DB::create_test_feed( $db, $label, $medium );
    for my $i ( 1 .. 10 )
    {
        my $download = $db->create(
            'downloads',
            {
                feeds_id => $feed->{ feeds_id },
                url      => 'http://test.download/' . $i,
                host     => 'test.download',
                type     => 'feed',
                state    => 'success',
                path     => $i + $i,
                priority => $i,
                sequence => $i * $i
            }
        );

        my $content = "content $download->{ downloads_id }";
        MediaWords::DBI::Downloads::store_content( $db, $download, \$content );
    }

    my $expected_downloads = $db->query( "select * from downloads where feeds_id = ?", $feed->{ feeds_id } )->hashes;
    map { $_->{ raw_content } = "content $_->{ downloads_id }" } @{ $expected_downloads };

    my $got_downloads = test_get( '/api/v2/downloads/list', { feeds_id => $feed->{ feeds_id } } );

    my $fields = [ qw/feeds_id url guid type state priority sequence download_time host/ ];
    rows_match( $label, $got_downloads, $expected_downloads, "downloads_id", $fields );

    $label = "downloads/single";

    my $expected_single = $expected_downloads->[ 0 ];

    my $got_download = test_get( '/api/v2/downloads/single/' . $expected_single->{ downloads_id }, {} );
    rows_match( $label, $got_download, [ $expected_single ], 'downloads_id', $fields );

}

# test mediahealth/list and single
sub test_mediahealth($)
{
    my ( $db ) = @_;

    my $label = "mediahealth/list";

    my $metrics = [
        qw/num_stories num_stories_w num_stories_90 num_stories_y num_sentences num_sentences_w/,
        qw/num_sentences_90 num_sentences_y expected_stories expected_sentences coverage_gaps/
    ];
    for my $i ( 1 .. 10 )
    {
        my $medium = MediaWords::Test::DB::create_test_medium( $db, "$label $i" );
        my $mh = {
            media_id        => $medium->{ media_id },
            is_healthy      => ( $medium->{ media_id } % 2 ) ? 't' : 'f',
            has_active_feed => ( $medium->{ media_id } % 2 ) ? 't' : 'f',
            start_date      => '2011-01-01',
            end_date        => '2017-01-01'
        };

        map { $mh->{ $_ } = $i * length( $_ ) } @{ $metrics };

        $db->create( 'media_health', $mh );
    }

    my $expected_mhs = $db->query( <<SQL, $label )->hashes;
select mh.* from media_health mh join media m using ( media_id ) where m.name like ? || '%'
SQL

    my $media_id_params = join( '&', map { "media_id=$_->{ media_id }" } @{ $expected_mhs } );

    my $got_mhs = test_get( '/api/v2/mediahealth/list?' . $media_id_params, {} );

    my $fields = [ qw/media_id is_health has_active_feed start_date end_date/, @{ $metrics } ];
    rows_match( $label, $got_mhs, $expected_mhs, 'media_id', $fields );
}

sub test_stats_list($)
{
    my ( $db ) = @_;

    my $label = "stats/list";

    MediaWords::DBI::Stats::refresh_stats( $db );

    my $ms = $db->query( "select * from mediacloud_stats" )->hash;

    my $r = test_get( '/api/v2/stats/list', {} );

    my $fields = [
        qw/stats_date daily_downloads daily_stories active_crawled_media active_crawled_feeds/,
        qw/total_stories total_downloads total_sentences/
    ];

    map { is( $r->{ $_ }, $ms->{ $_ }, "$label field '$_'" ) } @{ $fields };
}

# test whether we have at least requested every api end point outside of topics/
sub test_coverage()
{
    my $untested_urls = MediaWords::Test::API::get_untested_api_urls();

    $untested_urls = [ grep { $_ !~ m~/topics/~ } @{ $untested_urls } ];

    ok( scalar( @{ $untested_urls } ) == 0, "end points not requested: " . join( ', ', @{ $untested_urls } ) );
}

# test parts of the ai that only require reading, so we can test these all in one chunk
sub test_api($)
{
    my ( $db ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack_numerated( $db, $NUM_MEDIA, $NUM_FEEDS_PER_MEDIUM,
        $NUM_STORIES_PER_FEED );

    MediaWords::Test::DB::add_content_to_test_story_stack( $db, $media );

    MediaWords::Test::Solr::setup_test_index( $db );

    MediaWords::Test::API::setup_test_api_key( $db );

    test_tag_sets( $db );
    test_feeds( $db );

    test_tags( $db );
    test_media_suggestions( $db );

    test_topics_crud( $db );

    test_controversies( $db );
    test_controversy_dumps( $db );
    test_controversy_dump_time_slices( $db );

    test_downloads( $db );
    test_mediahealth( $db );

    test_wc_list( $db );

    test_stats_list( $db );

    test_coverage();
}

sub main
{
    MediaWords::Test::Supervisor::test_with_supervisor( \&test_api,
        [ 'solr_standalone', 'job_broker:rabbitmq', 'rescrape_media' ] );

    done_testing();
}

main();
