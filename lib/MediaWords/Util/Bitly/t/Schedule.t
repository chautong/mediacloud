use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::NoWarnings;
use Test::More tests => 3;

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

sub main()
{
    test_story_timestamp_lower_bound();
    test_story_timestamp_upper_bound();
}

main();
