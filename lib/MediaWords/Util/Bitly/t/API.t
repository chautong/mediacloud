use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::More;

use MediaWords::Test::DB;
use MediaWords::Test::HTTP::HashServer;
use MediaWords::Util::Network;
use MediaWords::Util::Text;

use Readonly;

# Environment variable which might contain Bit.ly access token to be used for testing live API
Readonly my $ENV_BITLY_TEST_ACCESS_TOKEN => 'MC_BITLY_TEST_ACCESS_TOKEN';

sub _bitly_info_test_callback($)
{
    my ( $request ) = @_;

    my $params = $request->query_params();

    unless ( $params->{ hash } )
    {
        my $response = '';
        $response .= "HTTP/1.0 200 OK\r\n";
        $response .= "Content-Type: application/json; charset=utf-8\r\n";
        $response .= "\r\n";
        $response .= MediaWords::Util::JSON::encode_json(
            {
                "status_code" => 500,
                "data"        => undef,
                "status_txt"  => "MISSING_ARG_SHORTURL_OR_HASH",
            }
        );
        return $response;
    }

    my $hashes;
    if ( ref $params->{ hash } eq ref [] )
    {
        $hashes = $params->{ hash };
    }
    else
    {
        $hashes = [ $params->{ hash } ];
    }

    my $hash_info = [];
    foreach my $hash ( @{ $hashes } )
    {
        push(
            @{ $hash_info },
            {
                "hash"        => $hash,
                "title"       => "Title for link with hash $hash",
                "created_at"  => 1515903065,
                "host"        => undef,
                "global_hash" => $hash,
                "user_hash"   => $hash,
            }
        );
    }

    my $response = '';
    $response .= "HTTP/1.0 200 OK\r\n";
    $response .= "Content-Type: application/json; charset=utf-8\r\n";
    $response .= "\r\n";
    $response .= MediaWords::Util::JSON::encode_json(
        {
            "data"        => { "info" => $hash_info, },
            "status_code" => 200,
            "status_txt"  => "OK",
        }
    );
    return $response;
}

sub _bitly_link_lookup_test_callback($)
{
    my ( $request ) = @_;

    my $params = $request->query_params();

    unless ( $params->{ url } )
    {
        my $response = '';
        $response .= "HTTP/1.0 200 OK\r\n";
        $response .= "Content-Type: application/json; charset=utf-8\r\n";
        $response .= "\r\n";
        $response .= MediaWords::Util::JSON::encode_json(
            {
                "status_code" => 500,
                "data"        => undef,
                "status_txt"  => "MISSING_ARG_URL",
            }
        );
        return $response;
    }

    my $urls;
    if ( ref $params->{ url } eq ref [] )
    {
        $urls = $params->{ url };
    }
    else
    {
        $urls = [ $params->{ url } ];
    }

    my $link_lookup = [];
    foreach my $url ( @{ $urls } )
    {
        push(
            @{ $link_lookup },
            {
                "url"            => $url,
                "aggregate_link" => "http://bit.ly/" . MediaWords::Util::Text::random_string( 6 ),
            }
        );
    }

    my $response = '';
    $response .= "HTTP/1.0 200 OK\r\n";
    $response .= "Content-Type: application/json; charset=utf-8\r\n";
    $response .= "\r\n";
    $response .= MediaWords::Util::JSON::encode_json(
        {
            "data"        => { "link_lookup" => $link_lookup, },
            "status_code" => 200,
            "status_txt"  => "OK",
        }
    );
    return $response;
}

sub _bitly_link_clicks_test_callback($)
{
    my ( $request ) = @_;

    my $params = $request->query_params();

    unless ( $params->{ link } )
    {
        my $response = '';
        $response .= "HTTP/1.0 200 OK\r\n";
        $response .= "Content-Type: application/json; charset=utf-8\r\n";
        $response .= "\r\n";
        $response .= MediaWords::Util::JSON::encode_json(
            {
                "status_code" => 400,
                "data"        => undef,
                "status_txt"  => "INVALID_ARG_MISSING_BITLINK",
            }
        );
        return $response;
    }

    unless ( $params->{ rollup } eq 'false' )
    {
        my $response = '';
        $response .= "HTTP/1.0 200 OK\r\n";
        $response .= "Content-Type: application/json; charset=utf-8\r\n";
        $response .= "\r\n";
        $response .= MediaWords::Util::JSON::encode_json(
            {
                "status_code" => 400,
                "data"        => undef,
                "status_txt"  => "Unit test does not support non-rollup requests",
            }
        );
        return $response;
    }

    my $units             = int( $params->{ units } );
    my $unit_reference_ts = int( $params->{ unit_reference_ts } );

    my $link_clicks = [];
    for ( my $x = 0 ; $x < $units ; ++$x )
    {
        push(
            @{ $link_clicks },
            {
                "dt" => $unit_reference_ts + ( $x * ( 60 * 60 * 24 ) ),
                "clicks" => $x,
            }
        );
    }

    my $response = '';
    $response .= "HTTP/1.0 200 OK\r\n";
    $response .= "Content-Type: application/json; charset=utf-8\r\n";
    $response .= "\r\n";
    $response .= MediaWords::Util::JSON::encode_json(
        {
            "status_code" => 200,
            "data"        => {
                "units"             => $units,
                "unit_reference_ts" => $unit_reference_ts,
                "tz_offset"         => 0,
                "unit"              => "day",
                "link_clicks"       => $link_clicks,
            },
            "status_txt" => "OK",
        }
    );
    return $response;
}

sub _mock_api_endpoint_pages()
{
    my $pages = {
        '/v3/info' => { callback => \&_bitly_info_test_callback, },

        '/v3/link/lookup' => { callback => \&_bitly_link_lookup_test_callback, },

        '/v3/link/clicks' => { callback => \&_bitly_link_clicks_test_callback, },
    };

    return $pages;
}

sub test_bitly_info($)
{
    my $api_endpoint = shift;

    my $test_hashes = [ '2DfNQPk', 'xrn7zH' ];

    my $bitly = MediaWords::Util::Bitly::API->new( $api_endpoint );
    my $info  = $bitly->bitly_info( $test_hashes );

    ok( $info->{ 'info' } );
    is( scalar( @{ $info->{ 'info' } } ),     2 );
    is( $info->{ 'info' }->[ 0 ]->{ 'hash' }, $test_hashes->[ 0 ] );
    is( $info->{ 'info' }->[ 1 ]->{ 'hash' }, $test_hashes->[ 1 ] );
}

sub test_bitly_hashref($)
{
    my $api_endpoint = shift;

    my $test_hashes = [ '2DfNQPk', 'xrn7zH' ];

    my $bitly = MediaWords::Util::Bitly::API->new( $api_endpoint );
    my $info  = $bitly->bitly_info_hashref( $test_hashes );

    ok( $info->{ $test_hashes->[ 0 ] } );
    is( $info->{ $test_hashes->[ 0 ] }->{ 'hash' }, $test_hashes->[ 0 ] );
    ok( $info->{ $test_hashes->[ 1 ] } );
    is( $info->{ $test_hashes->[ 1 ] }->{ 'hash' }, $test_hashes->[ 1 ] );
}

sub test_bitly_link_lookup()
{
    my $api_endpoint = shift;

    my $test_urls = [ 'https://civic.mit.edu/', 'https://cyber.harvard.edu/' ];

    my $bitly       = MediaWords::Util::Bitly::API->new( $api_endpoint );
    my $link_lookup = $bitly->bitly_link_lookup( $test_urls );

    ok( $link_lookup->{ 'link_lookup' } );
    is( scalar( @{ $link_lookup->{ 'link_lookup' } } ),    2 );
    is( $link_lookup->{ 'link_lookup' }->[ 0 ]->{ 'url' }, $test_urls->[ 0 ] );
    like( $link_lookup->{ 'link_lookup' }->[ 0 ]->{ 'aggregate_link' }, qr|^https?://bit\.ly/[a-zA-Z0-9]+?$| );
    is( $link_lookup->{ 'link_lookup' }->[ 1 ]->{ 'url' }, $test_urls->[ 1 ] );
    like( $link_lookup->{ 'link_lookup' }->[ 1 ]->{ 'aggregate_link' }, qr|^https?://bit\.ly/[a-zA-Z0-9]+?$| );
}

sub test_bitly_link_lookup_hashref($)
{
    my $api_endpoint = shift;

    my $test_urls = [ 'https://civic.mit.edu/', 'https://cyber.harvard.edu/' ];

    my $bitly       = MediaWords::Util::Bitly::API->new( $api_endpoint );
    my $link_lookup = $bitly->bitly_link_lookup_hashref( $test_urls );

    like( $link_lookup->{ $test_urls->[ 0 ] }, qr/^[a-zA-Z0-9]+?$/ );
    like( $link_lookup->{ $test_urls->[ 1 ] }, qr/^[a-zA-Z0-9]+?$/ );
}

sub test_bitly_link_clicks($)
{
    my $api_endpoint = shift;

    my $test_bitly_id        = '2DfNQPk';
    my $test_start_timestamp = 1515456000;
    my $test_end_timestamp   = 1516233600;

    my $bitly = MediaWords::Util::Bitly::API->new( $api_endpoint );
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
    my $api_endpoint = shift;

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            use Time::Local;

            my $test_url             = 'http://feeds.foxnews.com/~r/foxnews/national/~3/bmilmNKlhLw/';
            my $test_start_timestamp = timelocal( 0, 0, 0, 1, 6, 2013 );
            my $test_end_timestamp   = timelocal( 0, 0, 0, 1, 11, 2013 );

            my $bitly = MediaWords::Util::Bitly::API->new( $api_endpoint );
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
            is( $first_clicks_entry->{ units }, int( ( $test_end_timestamp - $test_start_timestamp ) / ( 60 * 60 * 24 ) ) );
            is( $first_clicks_entry->{ tz_offset }, 0 );
            ok( $first_clicks_entry->{ link_clicks } );

            my $first_link_clicks_entry = $first_clicks_entry->{ link_clicks }->[ 0 ];
            ok( defined $first_link_clicks_entry->{ clicks } );
            ok( defined $first_link_clicks_entry->{ dt } );
        }
    );
}

sub main()
{
    my $test_subroutines = [
        \&test_bitly_info,                   #
        \&test_bitly_hashref,                #
        \&test_bitly_link_lookup,            #
        \&test_bitly_link_lookup_hashref,    #
        \&test_bitly_link_clicks,            #
        \&test_fetch_stats_for_url,          #
    ];

    my $config     = MediaWords::Util::Config::get_config();
    my $new_config = python_deep_copy( $config );

    my $mock_port         = MediaWords::Util::Network::random_unused_port();
    my $mock_api_endpoint = "http://localhost:$mock_port/";
    my $mock_pages        = _mock_api_endpoint_pages();
    my $mock_hs           = MediaWords::Test::HTTP::HashServer->new( $mock_port, $mock_pages );
    $mock_hs->start();

    my $test_backends = [];

    # Mock API endpoint
    push(
        @{ $test_backends },
        {
            'api_endpoint' => $mock_api_endpoint,
            'access_token' => '01234567890abcdef',
        }
    );

    if ( $ENV{ $ENV_BITLY_TEST_ACCESS_TOKEN . '' } )
    {
        # Live API endpoint
        push(
            @{ $test_backends },
            {
                'api_endpoint' => undef,
                'access_token' => $ENV{ $ENV_BITLY_TEST_ACCESS_TOKEN . '' },
            }
        );

        plan tests => 85;

    }
    else
    {
        plan tests => 43;

    }

    # Enable Bit.ly for this test only
    $new_config->{ bitly } = {};
    my $old_bitly_enabled      = $config->{ bitly }->{ enabled };
    my $old_bitly_access_token = $config->{ bitly }->{ access_token };
    $new_config->{ bitly }->{ enabled } = 1;

    for my $backend ( @{ $test_backends } )
    {

        $new_config->{ bitly }->{ access_token } = $backend->{ 'access_token' };
        MediaWords::Util::Config::set_config( $new_config );

        for my $subroutine ( @{ $test_subroutines } )
        {
            $subroutine->( $backend->{ 'api_endpoint' } );
        }
    }

    # Reset configuration
    $new_config->{ bitly }->{ enabled }      = $old_bitly_enabled;
    $new_config->{ bitly }->{ access_token } = $old_bitly_access_token;
    MediaWords::Util::Config::set_config( $new_config );
}

main();
