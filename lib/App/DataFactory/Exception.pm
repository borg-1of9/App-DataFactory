package App::DataFactory::Exception;

use strict;
use warnings;
use utf8;

our $VERSION = "0.2.0";

# Constructor for the exception object
sub new {
    my ($class, %args) = @_;

    my $self = {
        component => $args{component} // 'Core',
        message   => $args{message}   // 'Unknown application error',
        sql_state => $args{sql_state} // undef,
    };

    return bless $self, $class;
}

# Accessor methods
sub component { return $_[0]->{component}; }
sub message   { return $_[0]->{message}; }
sub sql_state { return $_[0]->{sql_state}; }

# Formats the error string nicely for CLI or logger output
sub as_string {
    my ($self) = @_;
    my $str = sprintf("Error [%s]: %s", $self->{component}, $self->{message});
    if (defined $self->{sql_state}) {
        $str .= sprintf(" (SQL State: %s)", $self->{sql_state});
    }
    return $str;
}

1;
