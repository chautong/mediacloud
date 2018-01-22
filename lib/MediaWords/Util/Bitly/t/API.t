use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::More;

use MediaWords::Test::Bitly;
use MediaWords::Test::DB;

sub test_bitly_info()
{
    my $test_hashes = [ '2DfNQPk', 'xrn7zH' ];

    my $bitly = MediaWords::Util::Bitly::API->new();
    my $info  = $bitly->bitly_info( $test_hashes );

    ok( $info->{ 'info' } );
    is( scalar( @{ $info->{ 'info' } } ),     2 );
    is( $info->{ 'info' }->[ 0 ]->{ 'hash' }, $test_hashes->[ 0 ] );
    is( $info->{ 'info' }->[ 1 ]->{ 'hash' }, $test_hashes->[ 1 ] );
}

sub test_bitly_hashref()
{
    my $test_hashes = [ '2DfNQPk', 'xrn7zH' ];

    my $bitly = MediaWords::Util::Bitly::API->new();
    my $info  = $bitly->bitly_info_hashref( $test_hashes );

    ok( $info->{ $test_hashes->[ 0 ] } );
    is( $info->{ $test_hashes->[ 0 ] }->{ 'hash' }, $test_hashes->[ 0 ] );
    ok( $info->{ $test_hashes->[ 1 ] } );
    is( $info->{ $test_hashes->[ 1 ] }->{ 'hash' }, $test_hashes->[ 1 ] );
}

sub test_bitly_link_lookup()
{
    my $test_urls = [ 'https://civic.mit.edu/', 'https://cyber.harvard.edu/' ];

    my $bitly       = MediaWords::Util::Bitly::API->new();
    my $link_lookup = $bitly->bitly_link_lookup( $test_urls );

    ok( $link_lookup->{ 'link_lookup' } );
    is( scalar( @{ $link_lookup->{ 'link_lookup' } } ),    2 );
    is( $link_lookup->{ 'link_lookup' }->[ 0 ]->{ 'url' }, $test_urls->[ 0 ] );
    like( $link_lookup->{ 'link_lookup' }->[ 0 ]->{ 'aggregate_link' }, qr|^https?://bit\.ly/[a-zA-Z0-9]+?$| );
    is( $link_lookup->{ 'link_lookup' }->[ 1 ]->{ 'url' }, $test_urls->[ 1 ] );
    like( $link_lookup->{ 'link_lookup' }->[ 1 ]->{ 'aggregate_link' }, qr|^https?://bit\.ly/[a-zA-Z0-9]+?$| );
}

sub test_bitly_link_lookup_hashref()
{
    my $test_urls = [ 'https://civic.mit.edu/', 'https://cyber.harvard.edu/' ];

    my $bitly       = MediaWords::Util::Bitly::API->new();
    my $link_lookup = $bitly->bitly_link_lookup_hashref( $test_urls );

    like( $link_lookup->{ $test_urls->[ 0 ] }, qr/^[a-zA-Z0-9]+?$/ );
    like( $link_lookup->{ $test_urls->[ 1 ] }, qr/^[a-zA-Z0-9]+?$/ );
}

sub test_bitly_link_clicks()
{
    my $test_bitly_id        = '2DfNQPk';
    my $test_start_timestamp = 1515456000;
    my $test_end_timestamp   = 1516233600;

    my $bitly = MediaWords::Util::Bitly::API->new();
    my $link_clicks = $bitly->bitly_link_clicks( $test_bitly_id, $test_start_timestamp, $test_end_timestamp );

    ok( $link_clicks->{ 'link_clicks' } );
    my $expected_units = ( $test_end_timestamp - $test_start_timestamp ) / ( 60 * 60 * 24 );
    is( $link_clicks->{ 'units' },             $expected_units );
    is( $link_clicks->{ 'tz_offset' },         0 );
    is( $link_clicks->{ 'unit' },              'day' );
    is( $link_clicks->{ 'unit_reference_ts' }, $test_end_timestamp );

    is( scalar( @{ $link_clicks->{ 'link_clicks' } } ), $expected_units );
    ok( defined $link_clicks->{ 'link_clicks' }->[ 0 ]->{ 'dt' } );
    ok( defined $link_clicks->{ 'link_clicks' }->[ 0 ]->{ 'clicks' } );

}

sub test_fetch_stats_for_url($)
{
    my $db = shift;

    use Time::Local;

    my $test_url             = 'http://feeds.foxnews.com/~r/foxnews/national/~3/bmilmNKlhLw/';
    my $test_start_timestamp = timelocal( 0, 0, 0, 1, 6, 2013 );
    my $test_end_timestamp   = timelocal( 0, 0, 0, 1, 11, 2013 );

    my $bitly = MediaWords::Util::Bitly::API->new();
    my $link_stats = $bitly->fetch_stats_for_url( $db, $test_url, $test_start_timestamp, $test_end_timestamp );

    ok( keys( %{ $link_stats } ) > 0 );
    ok( $link_stats->{ collection_timestamp } );
    ok( $link_stats->{ data } );
    my $data = $link_stats->{ data };

    my $first_entry = $data->{ ( sort keys %{ $data } )[ 0 ] };
    is( ref( $first_entry ), ref( {} ) );
    ok( length( $first_entry->{ url } ) );
    ok( $first_entry->{ info } );
    ok( defined $first_entry->{ info }->{ hash } );
    ok( defined $first_entry->{ info }->{ global_hash } );
    ok( defined $first_entry->{ info }->{ user_hash } );
    ok( defined $first_entry->{ info }->{ created_at } );
    ok( $first_entry->{ clicks } );

    my $first_clicks_entry = $first_entry->{ clicks }->[ 0 ];
    is( $first_clicks_entry->{ unit_reference_ts }, $test_end_timestamp );
    is( $first_clicks_entry->{ unit },              'day' );
    is( $first_clicks_entry->{ units },     int( ( $test_end_timestamp - $test_start_timestamp ) / ( 60 * 60 * 24 ) ) );
    is( $first_clicks_entry->{ tz_offset }, 0 );
    ok( $first_clicks_entry->{ link_clicks } );

    my $first_link_clicks_entry = $first_clicks_entry->{ link_clicks }->[ 0 ];
    ok( defined $first_link_clicks_entry->{ clicks } );
    ok( defined $first_link_clicks_entry->{ dt } );
}

sub main()
{
    if ( MediaWords::Test::Bitly::live_backend_test_is_enabled() )
    {
        plan tests => 85;
    }
    else
    {
        plan tests => 43;
    }

    MediaWords::Test::Bitly::test_on_all_backends( \&test_bitly_info );
    MediaWords::Test::Bitly::test_on_all_backends( \&test_bitly_hashref );
    MediaWords::Test::Bitly::test_on_all_backends( \&test_bitly_link_lookup );
    MediaWords::Test::Bitly::test_on_all_backends( \&test_bitly_link_lookup_hashref );
    MediaWords::Test::Bitly::test_on_all_backends( \&test_bitly_link_clicks );

    MediaWords::Test::Bitly::test_on_all_backends(
        sub {

            # Initialize a fresh database for every Bit.ly backend
            MediaWords::Test::DB::test_on_test_database(
                sub {
                    my ( $db ) = @_;

                    test_fetch_stats_for_url( $db );
                }
            );
        }
    );
}

main();
