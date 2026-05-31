package App::DataFactory::Metadata;

use strict;
use warnings;
use utf8;

our $VERSION = "0.1.0";

# Returns a structural snapshot representation of the current application release lifecycle state
sub get_release_info {
    return {
        version      => $VERSION,
        release_date => '2026-05-31',
        status       => 'beta', # stable, alpha, beta, development
        codename     => 'MemFactory',
        license      => 'Artistic-2.0',
        author       => 'Vladislav Kantor',
        repository   => 'https://github.com/borg-1of9/App-DataFactory',
    };
}

1;
