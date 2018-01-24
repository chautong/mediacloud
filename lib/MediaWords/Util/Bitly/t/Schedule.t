use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::More tests => 18;

use MediaWords::Test::Bitly;
use MediaWords::Test::DB;

use DateTime;

sub test_story_timestamp_lower_bound()
{
    is(
        MediaWords::Util::Bitly::Schedule::_story_timestamp_lower_bound(),
        DateTime->new( year => 2008, month => 01, day => 01 )->epoch
    );
}

sub test_story_timestamp_upper_bound()
{
    is( MediaWords::Util::Bitly::Schedule::_story_timestamp_upper_bound(), DateTime->now()->epoch );
}

sub test_story_start_timestamp()
{
    my $day = 15;

    is(
        MediaWords::Util::Bitly::Schedule::_story_start_timestamp(
            DateTime->new(
                year  => 2012,
                month => 10,
                day   => $day,
                hour  => 8
            )->epoch
        ),
        DateTime->new(
            year  => 2012,
            month => 10,
            day   => $day - 2,
            hour  => 8
        )->epoch
    );
}

sub test_story_end_timestamp()
{
    is(
        MediaWords::Util::Bitly::Schedule::_story_end_timestamp(
            DateTime->new(
                year  => 2012,
                month => 10,
                day   => 15,
                hour  => 8
            )->epoch
        ),
        DateTime->new(
            year  => 2012,
            month => 11,
            day   => 14,
            hour  => 8
        )->epoch
    );

    # Too far off in the future
    my $now = time();
    is( MediaWords::Util::Bitly::Schedule::_story_end_timestamp( $now + 2000 ), $now );
}

sub test_story_processing_is_enabled()
{
    my $config     = MediaWords::Util::Config::get_config();
    my $new_config = python_deep_copy( $config );
    $new_config->{ bitly } = {};
    my $old_bitly_enabled = $config->{ bitly }->{ enabled };

    $new_config->{ bitly }->{ enabled } = 1;
    $new_config->{ bitly }->{ story_processing }->{ enabled } = 1;
    MediaWords::Util::Config::set_config( $new_config );
    ok( MediaWords::Util::Bitly::Schedule::story_processing_is_enabled() );

    $new_config->{ bitly }->{ story_processing }->{ enabled } = 0;
    MediaWords::Util::Config::set_config( $new_config );
    ok( !MediaWords::Util::Bitly::Schedule::story_processing_is_enabled() );

    $new_config->{ bitly }->{ enabled } = 0;
    $new_config->{ bitly }->{ story_processing }->{ enabled } = 1;
    MediaWords::Util::Config::set_config( $new_config );
    ok( !MediaWords::Util::Bitly::Schedule::story_processing_is_enabled() );

    # Reset configuration
    $new_config->{ bitly }->{ enabled } = $old_bitly_enabled;
    MediaWords::Util::Config::set_config( $new_config );
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

sub test_story_timestamp($)
{
    my $db = shift;

    my $timezone = DateTime::TimeZone->new( name => 'local' );

    my $medium = MediaWords::Test::DB::create_test_medium( $db, 'test' );
    my $feed = MediaWords::Test::DB::create_test_feed( $db, 'feed', $medium );
    my $story = MediaWords::Test::DB::create_test_story( $db, 'story', $feed );
    my $stories_id = $story->{ stories_id };

    $story = $db->update_by_id( 'stories', $stories_id, { 'publish_date' => '2012-10-15 08:00:00' } );
    is( MediaWords::Util::Bitly::Schedule::_story_timestamp( $story ),
        DateTime->new( year => 2012, month => 10, day => 15, hour => 8, time_zone => $timezone )->epoch );

    # Less than _story_timestamp_lower_bound()
    $story = $db->update_by_id(
        'stories',
        $stories_id,
        {
            'publish_date' => '2001-10-15 08:00:00',
            'collect_date' => '2010-10-15 08:00:00',
        }
    );
    is( MediaWords::Util::Bitly::Schedule::_story_timestamp( $story ),
        DateTime->new( year => 2010, month => 10, day => 15, hour => 8, time_zone => $timezone )->epoch );

    # More than _story_timestamp_upper_bound
    $story = $db->update_by_id(
        'stories',
        $stories_id,
        {
            'publish_date' => '2060-10-15 08:00:00',
            'collect_date' => '2011-10-15 08:00:00',
        }
    );
    is( MediaWords::Util::Bitly::Schedule::_story_timestamp( $story ),
        DateTime->new( year => 2011, month => 10, day => 15, hour => 8, time_zone => $timezone )->epoch );
}

sub test_add_to_processing_schedule($)
{
    my $db = shift;

    my $timezone = DateTime::TimeZone->new( name => 'local' );

    # By how many seconds to delay the story processing with Bit.ly
    my $processing_delay_1 = 60 * 60 * 24 * 2;
    my $processing_delay_2 = 60 * 60 * 24 * 20;

    my $config                              = MediaWords::Util::Config::get_config();
    my $new_config                          = python_deep_copy( $config );
    my $old_bitly_story_processing_schedule = $config->{ bitly }->{ story_processing }->{ schedule };
    $new_config->{ bitly }->{ story_processing }->{ schedule } = [ $processing_delay_1, $processing_delay_2, ];
    MediaWords::Util::Config::set_config( $new_config );

    my $medium = MediaWords::Test::DB::create_test_medium( $db, 'test' );
    my $feed = MediaWords::Test::DB::create_test_feed( $db, 'feed', $medium );
    my $story = MediaWords::Test::DB::create_test_story( $db, 'story', $feed );

    my $stories_id = $story->{ stories_id };

    $story = $db->update_by_id( 'stories', $stories_id, { 'publish_date' => '2012-10-15 08:00:00' } );

    {
        my $scheduled_stories = $db->query(
            <<SQL,
            SELECT stories_id,
                   EXTRACT(EPOCH FROM fetch_at)::int AS fetch_at_timestamp
            FROM bitly_processing_schedule
            WHERE stories_id = ?
            ORDER BY fetch_at
SQL
            $stories_id
        )->hashes;
        is( scalar( @{ $scheduled_stories } ), 0 );
    }

    MediaWords::Util::Bitly::Schedule::add_to_processing_schedule( $db, $stories_id );

    {
        my $scheduled_stories = $db->query(
            <<SQL,
            SELECT stories_id,
                   EXTRACT(EPOCH FROM fetch_at)::int AS fetch_at_timestamp
            FROM bitly_processing_schedule
            WHERE stories_id = ?
            ORDER BY fetch_at
SQL
            $stories_id
        )->hashes;
        is( scalar( @{ $scheduled_stories } ), 2 );
        is(
            $scheduled_stories->[ 0 ]->{ fetch_at_timestamp },
            DateTime->new(
                year  => 2012,    #
                month => 10,      #
                day   => 15,      #

                # FIXME not quite sure why we have to add 8 hours; probably
                # has something to do with the fact that publish_date is stored
                # in America/New_York timezone, but not necessarily
                hour => 8 + 8,    #

                time_zone => $timezone    #
            )->epoch + $processing_delay_1
        );
        is(
            $scheduled_stories->[ 1 ]->{ fetch_at_timestamp },
            DateTime->new(
                year  => 2012,            #
                month => 10,              #
                day   => 15,              #

                # FIXME not quite sure why we have to add 8 hours; probably
                # has something to do with the fact that publish_date is stored
                # in America/New_York timezone, but not necessarily
                hour => 8 + 8,    #

                time_zone => $timezone    #
            )->epoch + $processing_delay_2
        );
    }

    # Reset configuration
    $new_config->{ bitly }->{ story_processing }->{ schedule } = $old_bitly_story_processing_schedule;
    MediaWords::Util::Config::set_config( $new_config );
}

sub main()
{
    test_story_timestamp_lower_bound();
    test_story_timestamp_upper_bound();
    test_story_start_timestamp();
    test_story_end_timestamp();
    test_story_processing_is_enabled();

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_skip_processing_for_story_feed( $db );
        }
    );

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_story_timestamp( $db );
        }
    );

    MediaWords::Test::Bitly::test_with_story_processing_enabled(
        sub {

            MediaWords::Test::DB::test_on_test_database(
                sub {
                    my ( $db ) = @_;

                    test_add_to_processing_schedule( $db );
                }
            );
        }
    );

}

main();
