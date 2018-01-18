package MediaWords::Util::Network;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

MediaWords::Util::Python::import_python_module( __PACKAGE__, 'mediawords.util.network' );

1;
