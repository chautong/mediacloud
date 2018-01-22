package MediaWords::Test::Bitly;

# Bit.ly testing helpers

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::Test::HTTP::HashServer;
use MediaWords::Util::Config;
use MediaWords::Util::Network;
use MediaWords::Util::JSON;
use MediaWords::Util::Text;

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

sub live_backend_test_is_enabled()
{
    if ( $ENV{ $ENV_BITLY_TEST_ACCESS_TOKEN . '' } )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub test_subroutines_on_all_backends($)
{
    my $test_subroutines = shift;

    my $config     = MediaWords::Util::Config::get_config();
    my $new_config = python_deep_copy( $config );

    # Enable Bit.ly for this test only
    $new_config->{ bitly } = {};
    my $old_bitly_enabled      = $config->{ bitly }->{ enabled };
    my $old_bitly_api_endpoint = $config->{ bitly }->{ api_endpoint };
    my $old_bitly_access_token = $config->{ bitly }->{ access_token };
    $new_config->{ bitly }->{ enabled } = 1;

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

    if ( live_backend_test_is_enabled() )
    {
        # Live API endpoint
        push(
            @{ $test_backends },
            {
                'api_endpoint' => $config->{ bitly }->{ api_endpoint },        # Will be set to live API's endpoint
                'access_token' => $ENV{ $ENV_BITLY_TEST_ACCESS_TOKEN . '' },
            }
        );

    }

    for my $backend ( @{ $test_backends } )
    {
        $new_config->{ bitly }->{ api_endpoint } = $backend->{ 'api_endpoint' };
        $new_config->{ bitly }->{ access_token } = $backend->{ 'access_token' };
        MediaWords::Util::Config::set_config( $new_config );

        for my $subroutine ( @{ $test_subroutines } )
        {
            $subroutine->();
        }
    }

    # Reset configuration
    $new_config->{ bitly }->{ enabled }      = $old_bitly_enabled;
    $new_config->{ bitly }->{ api_endpoint } = $old_bitly_api_endpoint;
    $new_config->{ bitly }->{ access_token } = $old_bitly_access_token;
    MediaWords::Util::Config::set_config( $new_config );
}

1;
