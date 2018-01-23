use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use utf8;
use Test::More;
use Test::Differences;
use Test::Deep;

use Data::Dumper;
use Readonly;

use MediaWords::Util::Bitly;
use MediaWords::Test::DB;
use MediaWords::Test::Bitly;
use MediaWords::TM::Mine;

sub test_bitly_processing_is_enabled()
{
    my $config     = MediaWords::Util::Config::get_config();
    my $new_config = python_deep_copy( $config );
    $new_config->{ bitly } = {};
    my $old_bitly_enabled = $config->{ bitly }->{ enabled };

    $new_config->{ bitly }->{ enabled } = 1;
    MediaWords::Util::Config::set_config( $new_config );
    ok( MediaWords::Util::Bitly::bitly_processing_is_enabled() );

    $new_config->{ bitly }->{ enabled } = 0;
    MediaWords::Util::Config::set_config( $new_config );
    ok( !MediaWords::Util::Bitly::bitly_processing_is_enabled() );

    $new_config->{ bitly }->{ enabled } = undef;
    MediaWords::Util::Config::set_config( $new_config );
    ok( !MediaWords::Util::Bitly::bitly_processing_is_enabled() );

    # Reset configuration
    $new_config->{ bitly }->{ enabled } = $old_bitly_enabled;
    MediaWords::Util::Config::set_config( $new_config );
}

sub test_merge_story_stats()
{
    # New stats had an error, old stats didn't
    {
        my $old_stats = { data => { bitly_id => { foo => 'bar ' }, }, };
        my $new_stats = { error => 'An error occurred while fetching new stats', };
        my $expected_stats = $old_stats;

        cmp_deeply( MediaWords::Util::Bitly::_merge_story_stats( $old_stats, $new_stats ), $expected_stats );
    }

    # Old stats had an error, new stats didn't
    {
        my $old_stats = { error => 'An error occurred while fetching old stats', };
        my $new_stats = { data => { bitly_id => { foo => 'bar ' }, }, };
        my $expected_stats = $new_stats;

        cmp_deeply( MediaWords::Util::Bitly::_merge_story_stats( $old_stats, $new_stats ), $expected_stats );
    }

    # Both old and new stats had an error
    {
        my $old_stats = { error => 'An error occurred while fetching old stats', };
        my $new_stats = { error => 'An error occurred while fetching new stats', };
        my $expected_stats = $new_stats;

        cmp_deeply( MediaWords::Util::Bitly::_merge_story_stats( $old_stats, $new_stats ), $expected_stats );
    }

    # Merge stats for different days, make sure timestamp gets copied too
    {
        my $old_stats_clicks = {
            link_clicks => [
                { dt => 1, clicks => 1 },    #
                { dt => 2, clicks => 2 },    #
                { dt => 3, clicks => 3 },    #
            ]
        };
        my $new_stats_clicks = {
            link_clicks => [
                { dt => 4, clicks => 4 },    #
                { dt => 5, clicks => 5 },    #
                { dt => 6, clicks => 6 },    #
            ]
        };
        my $old_stats = {
            data => { bitly_id => { clicks => [ $old_stats_clicks ] } },    #
            collection_timestamp => 1,                                      #
        };
        my $new_stats = {
            data => { bitly_id => { clicks => [ $new_stats_clicks ] } },    #
            collection_timestamp => 2,                                      #
        };
        my $expected_stats = {
            data => { bitly_id => { clicks => [ $old_stats_clicks, $new_stats_clicks ] } },    #
            collection_timestamp => 2,                                                         #
        };

        cmp_deeply( MediaWords::Util::Bitly::_merge_story_stats( $old_stats, $new_stats ), $expected_stats );
    }
}

sub test_aggregate_story_stats()
{
    # Raw data has been fetched twice, had overlapping stats
    {
        my $stories_id = 123;

        my $old_stats_clicks = {
            link_clicks => [
                { dt => 1, clicks => 1 },      #
                { dt => 2, clicks => 10 },     #
                { dt => 3, clicks => 100 },    #
            ]
        };
        my $new_stats_clicks = {
            link_clicks => [
                { dt => 2, clicks => 1000 },      #
                { dt => 3, clicks => 10000 },     #
                { dt => 4, clicks => 100000 },    #
            ]
        };

        my $stats = {
            data => {
                bitly_id_1 => { clicks => [ $old_stats_clicks, $new_stats_clicks ] },
                bitly_id_2 => { clicks => [ $old_stats_clicks, $new_stats_clicks ] },
            }
        };

        my $expected_dates_and_clicks = {

            # Old stats:
            #     1 click from bitly_id_1 + 1 click from bitly_id_2
            MediaWords::Util::SQL::get_sql_date_from_epoch( 1 ) => 1 * 2,

            # New stats:
            #     1000 clicks from bitly_id_1 + 1000 clicks from bitly_id_2
            MediaWords::Util::SQL::get_sql_date_from_epoch( 2 ) => 1000 * 2,

            # New stats:
            #     10,000 clicks from bitly_id_1 + 10,000 clicks from bitly_id_2
            MediaWords::Util::SQL::get_sql_date_from_epoch( 3 ) => 10000 * 2,

            # New stats:
            #     100,000 clicks from bitly_id_1 + 100,000 clicks from bitly_id_2
            MediaWords::Util::SQL::get_sql_date_from_epoch( 4 ) => 100000 * 2,

        };

        my $aggregated_stats = MediaWords::Util::Bitly::aggregate_story_stats( $stories_id, undef, $stats );
        cmp_deeply( $aggregated_stats->{ dates_and_clicks }, $expected_dates_and_clicks );
    }
}

sub test_num_topic_stories_without_bitly_statistics($)
{
    my $db = shift;

    Readonly my $test_story_count => 42;
    Readonly my $label            => 'num_topic_stories_without_bitly_statistics';

    my $topic = MediaWords::Test::DB::create_test_topic( $db, $label );

    my $medium = MediaWords::Test::DB::create_test_medium( $db, $label );
    my $feed = MediaWords::Test::DB::create_test_feed( $db, $label, $medium );

    my $first_story = undef;
    for my $i ( 1 .. $test_story_count )
    {
        my $story = MediaWords::Test::DB::create_test_story( $db, "$label $i", $feed );
        MediaWords::TM::Mine::add_to_topic_stories( $db, $topic, $story, 1, 'f', 1 );

        unless ( defined $first_story )
        {
            $first_story = $story;
        }
    }

    {
        my $story_count = MediaWords::Util::Bitly::num_topic_stories_without_bitly_statistics( $db, $topic->{ topics_id } );
        is( $story_count, $test_story_count );
    }

    $db->query(
        <<SQL,
        INSERT INTO bitly_clicks_total (stories_id, click_count)
        VALUES (?, ?)
SQL
        $first_story->{ stories_id }, 123
    );

    {
        my $story_count = MediaWords::Util::Bitly::num_topic_stories_without_bitly_statistics( $db, $topic->{ topics_id } );
        is( $story_count, $test_story_count - 1 );
    }
}

# Test read_story_stats(), store_story_stats(), story_stats_are_stored()
sub test_read_store_are_stored_story_stats($)
{
    my $db = shift;

    my $story_stats = {
        'collection_timestamp' => 1516665734,
        'data'                 => {
            'fGgISg' => {
                'url' =>
                  'http://www.foxnews.com/us/2013/07/04/crowds-across-america-protest-nsa-in-restore-fourth-movement.html',
                'clicks' => [
                    {
                        'unit'              => 'day',
                        'unit_reference_ts' => 1385874000,
                        'link_clicks'       => [
                            {
                                'clicks' => 42,
                                'dt'     => 1385874000
                            },
                            {
                                'dt'     => 1385960400,
                                'clicks' => 43
                            },
                            {
                                'dt'     => 1386046800,
                                'clicks' => 44
                            }
                        ],
                        'units'     => 153,
                        'tz_offset' => 0
                    }
                ],
                'info' => {
                    'host'        => undef,
                    'title'       => 'Title for link with hash fGgISg',
                    'global_hash' => 'fGgISg',
                    'user_hash'   => 'fGgISg',
                    'created_at'  => 1515903065,
                    'hash'        => 'fGgISg'
                }
            },
            'ZjWs1r' => {
                'clicks' => [
                    {
                        'link_clicks' => [
                            {
                                'clicks' => 42,
                                'dt'     => 1385874000
                            },
                            {
                                'clicks' => 43,
                                'dt'     => 1385960400
                            },
                            {
                                'clicks' => 44,
                                'dt'     => 1386046800
                            }
                        ],
                        'units'             => 153,
                        'tz_offset'         => 0,
                        'unit'              => 'day',
                        'unit_reference_ts' => 1385874000
                    }
                ],
                'url'  => 'http://feeds.foxnews.com/~r/foxnews/national/~3/bmilmNKlhLw/',
                'info' => {
                    'title'       => 'Title for link with hash ZjWs1r',
                    'user_hash'   => 'ZjWs1r',
                    'global_hash' => 'ZjWs1r',
                    'hash'        => 'ZjWs1r',
                    'created_at'  => 1515903065,
                    'host'        => undef
                }
            },
            '390N0b' => {
                'clicks' => [
                    {
                        'units'       => 153,
                        'link_clicks' => [
                            {
                                'dt'     => 1385874000,
                                'clicks' => 42
                            },
                            {
                                'dt'     => 1385960400,
                                'clicks' => 43
                            },
                            {
                                'clicks' => 44,
                                'dt'     => 1386046800
                            }
                        ],
                        'tz_offset'         => 0,
                        'unit_reference_ts' => 1385874000,
                        'unit'              => 'day'
                    }
                ],
                'url' =>
'http://www.foxnews.com/us/2013/07/04/crowds-across-america-protest-nsa-in-restore-fourth-movement.html?utm_source=feedburner&utm_medium=feed&utm_campaign=Feed%253A+foxnews%252Fnational+%2528Internal+-+US+Latest+-+Text%2529',
                'info' => {
                    'global_hash' => '390N0b',
                    'created_at'  => 1515903065,
                    'user_hash'   => '390N0b',
                    'hash'        => '390N0b',
                    'title'       => 'Title for link with hash 390N0b',
                    'host'        => undef
                }
            }
        }
    };

    Readonly my $label => 'read_store_are_stored_story_stats';

    my $medium = MediaWords::Test::DB::create_test_medium( $db, $label );
    my $feed = MediaWords::Test::DB::create_test_feed( $db, 'feed', $medium );
    my $story = MediaWords::Test::DB::create_test_story( $db, 'story', $feed );

    my $stories_id = $story->{ stories_id };

    ok( !MediaWords::Util::Bitly::story_stats_are_stored( $db, $stories_id ) );

    MediaWords::Util::Bitly::store_story_stats( $db, $stories_id, $story_stats );
    ok( MediaWords::Util::Bitly::story_stats_are_stored( $db, $stories_id ) );

    {
        my $read_story_stats = MediaWords::Util::Bitly::read_story_stats( $db, $stories_id );
        my $clicks = $read_story_stats->{ data }->{ fGgISg }->{ clicks };
        is( scalar( @{ $clicks } ), 1 );
        my $first_entry_clicks = $clicks->[ 0 ]->{ link_clicks }->[ 0 ]->{ clicks };
        ok( defined $first_entry_clicks );
    }

    # Store updated stats, see if clicks get merged
    my $new_click_count = 128;
    $story_stats->{ data }->{ fGgISg }->{ clicks }->[ 0 ]->{ link_clicks }->[ 0 ]->{ clicks } = $new_click_count;
    MediaWords::Util::Bitly::store_story_stats( $db, $stories_id, $story_stats );
    ok( MediaWords::Util::Bitly::story_stats_are_stored( $db, $stories_id ) );

    {
        my $read_story_stats = MediaWords::Util::Bitly::read_story_stats( $db, $stories_id );
        my $clicks = $read_story_stats->{ data }->{ fGgISg }->{ clicks };
        is( scalar( @{ $clicks } ), 2 );
        my $second_entry_clicks = $clicks->[ 1 ]->{ link_clicks }->[ 0 ]->{ clicks };
        ok( defined $second_entry_clicks );
        is( $second_entry_clicks, $new_click_count );
    }
}

sub test_fetch_stats_for_story($)
{
    my $db = shift;

    use Time::Local;

    # Input URL and timestamps
    my $test_url             = 'http://feeds.foxnews.com/~r/foxnews/national/~3/bmilmNKlhLw/';
    my $test_start_timestamp = timelocal( 0, 0, 0, 1, 6, 2013 );
    my $test_end_timestamp   = timelocal( 0, 0, 0, 1, 11, 2013 );

    # URL that is to be resolved by all_url_variants()
    my $expected_resolved_url =
      'http://www.foxnews.com/us/2013/07/04/crowds-across-america-protest-nsa-in-restore-fourth-movement.html';

    Readonly my $label => 'fetch_stats_for_story';

    my $medium = MediaWords::Test::DB::create_test_medium( $db, $label );
    my $feed = MediaWords::Test::DB::create_test_feed( $db, 'feed', $medium );
    my $story = MediaWords::Test::DB::create_test_story( $db, 'story', $feed );
    $db->update_by_id( 'stories', $story->{ stories_id }, { 'url' => $test_url } );

    my $story_stats = MediaWords::Util::Bitly::fetch_stats_for_story( $db, $story->{ stories_id },
        $test_start_timestamp, $test_end_timestamp );

    ok( $story_stats->{ data } );
    my $data = $story_stats->{ data };

    my $found_resolved_url = 0;
    for my $bitly_id ( keys %{ $data } )
    {
        my $entry = $data->{ $bitly_id };
        my $url   = $entry->{ url };
        if ( $url eq $expected_resolved_url )
        {
            $found_resolved_url = 1;
            last;
        }
    }

    ok( $found_resolved_url, "Found resolved URL in data: " . Dumper( $story_stats ) );
}

sub main()
{
    if ( MediaWords::Test::Bitly::live_backend_test_is_enabled() )
    {
        plan tests => 30;
    }
    else
    {
        plan tests => 20;
    }

    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_bitly_processing_is_enabled();
    test_merge_story_stats();
    test_aggregate_story_stats();

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_num_topic_stories_without_bitly_statistics( $db );
        }
    );

    # No point in having multiple Bit.ly backends for this test as it doesn't
    # make any API calls, we just want the Bit.ly client enabled
    MediaWords::Test::Bitly::test_on_all_backends(
        sub {

            # Initialize a fresh database for every Bit.ly backend
            MediaWords::Test::DB::test_on_test_database(
                sub {
                    my ( $db ) = @_;

                    test_read_store_are_stored_story_stats( $db );
                }
            );
        }
    );

    MediaWords::Test::Bitly::test_on_all_backends(
        sub {

            # Initialize a fresh database for every Bit.ly backend
            MediaWords::Test::DB::test_on_test_database(
                sub {
                    my ( $db ) = @_;

                    test_fetch_stats_for_story( $db );
                }
            );
        }
    );
}

main();
