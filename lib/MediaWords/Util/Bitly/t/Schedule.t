use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::More tests => 5;

use MediaWords::Test::Bitly;
use MediaWords::Test::DB;

use Time::Local;

sub test_story_timestamp_lower_bound()
{
    is( MediaWords::Util::Bitly::Schedule::_story_timestamp_lower_bound(), 1199145600 );
}

sub test_story_timestamp_upper_bound()
{
    is( MediaWords::Util::Bitly::Schedule::_story_timestamp_upper_bound(), time() );
}

sub test_skip_processing_for_story_feed($)
{
    my $db = shift;

    my $medium = MediaWords::Test::DB::create_test_medium( $db, 'test' );
    my $feed = MediaWords::Test::DB::create_test_feed( $db, 'feed', $medium );
    my $story = MediaWords::Test::DB::create_test_story( $db, 'story', $feed );
    my $stories_id = $story->{ stories_id };

    ok( !MediaWords::Util::Bitly::Schedule::_skip_processing_for_story_feed( $db, $stories_id ) );

    $db->update_by_id( 'feeds', $feed->{ feeds_id }, { 'skip_bitly_processing' => 't' } );

    ok( MediaWords::Util::Bitly::Schedule::_skip_processing_for_story_feed( $db, $stories_id ) );
}

sub main()
{
    test_story_timestamp_lower_bound();
    test_story_timestamp_upper_bound();

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_skip_processing_for_story_feed( $db );
        }
    );
}

main();
