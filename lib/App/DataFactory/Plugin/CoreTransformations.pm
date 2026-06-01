package App::DataFactory::Plugin::CoreTransformations;

use strict;
use warnings;
use utf8;

our $VERSION = "0.1.0";

# Returns a hash mapping of uppercase native SQL function names to Perl anonymous codeblocks
sub register_functions {
    return {
        # 1. Implementation for pipeline to_lower converter
        'PERL_TO_LOWER' => sub {
            my ($value) = @_;
            return undef unless defined $value;
            return lc($value);
        },

        # 2. Implementation for pipeline to_upper converter
        'PERL_TO_UPPER' => sub {
            my ($value) = @_;
            return undef unless defined $value;
            return uc($value);
        },

        # 3. Implementation for pipeline whitespace trim/strip cleaner
        'PERL_TRIM' => sub {
            my ($value) = @_;
            return undef unless defined $value;
            $value =~ s/^\s+//;
            $value =~ s/\s+$//;
            return $value;
        }
    };
}

1;
