package App::DataFactory::PluginManager;

use strict;
use warnings;
use utf8;
use Module::Load; # Standard clean module dynamic loader
use App::DataFactory::Exception;

our $VERSION = "0.2.0";

sub new {
    my ($class) = @_;
    return bless { plugins => [] }, $class;
}

# Discovers and registers custom functions from Perl plugins into the SQLite instance
sub register_all_plugins {
    my ($self, $dbh) = @_;

    # In a fully automated setup, we would scan @INC directories for sub-modules.
    # For initial reliable runtime stability, we define explicit core/available plugins.
    my @available_plugins = ('App::DataFactory::Plugin::CoreTransformations');

    foreach my $plugin_class (@available_plugins) {
        # Use eval {} safely to trap load failures without string execution
        my $loaded = 0;
        eval {
            load $plugin_class;
            $loaded = 1;
        };

        if (!$loaded || $@) {
            return App::DataFactory::Exception->new(
                component => 'PluginManager',
                message   => "Failed to dynamically load plugin package '$plugin_class': $@"
            );
        }

        # Verify the mandatory interface hook method exists
        if (!$plugin_class->can('register_functions')) {
            return App::DataFactory::Exception->new(
                component => 'PluginManager',
                message   => "Plugin '$plugin_class' breaks interface rule: missing register_functions()"
            );
        }

        # Fetch the subroutines from the plugin
        my $functions_ref = $plugin_class->register_functions();

        # Inject each plugin method straight into the SQLite engine workspace environment
        while (my ($sql_func_name, $perl_sub_ref) = each %$functions_ref) {
            eval {
                $dbh->sqlite_create_function($sql_func_name, -1, $perl_sub_ref);
            };
            if ($@) {
                return App::DataFactory::Exception->new(
                    component => 'PluginManager',
                    message   => "Failed to register custom SQL function '$sql_func_name' via $plugin_class: $@"
                );
            }
        }

        push @{$self->{plugins}}, $plugin_class;
    }

    return 1; # Success status indicator
}

1;
