package App::DataFactory::PipelineCompiler;

use strict;
use warnings;
use utf8;
use App::DataFactory::Exception;

our $VERSION = "0.1.0";

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

# Compiles declared pipeline arrays from config into chain-linked single SQL executable functions
sub compile_and_register_pipelines {
    my ($self, $dbh, $pipelines_config) = @_;

    return 1 unless defined $pipelines_config;

    # Fetch available base functions registered from our Core/Transform plugins
    my $transform_plugin = 'App::DataFactory::Plugin::CoreTransformations';
    my $base_funcs = $transform_plugin->register_functions();

    while (my ($pipeline_name, $steps_array_ref) = each %$pipelines_config) {

        # We build a localized wrapper sub that iteratively calls the ordered config steps
        my $compiled_sub = sub {
            my ($input_data) = @_;
            return undef unless defined $input_data;

            my $current_value = $input_data;

            # Loop sequentially through the pipeline tasks in the exact configuration array order
            foreach my $step (@$steps_array_ref) {
                my ($func_key) = keys %$step;

                # Standardize matching to look up base plugin functions (e.g., to_lower -> PERL_TO_LOWER)
                my $internal_lookup = 'PERL_' . uc($func_key);

                if (exists $base_funcs->{$internal_lookup}) {
                    $current_value = $base_funcs->{$internal_lookup}->($current_value);
                } else {
                    # Soft fallback fallback or ignore if the specified transform key is unknown
                    warn "Warning: Pipeline step execution skipped. Unknown transform wrapper '$func_key'\n";
                }
            }
            return $current_value;
        };

        # Expose the compiled sequential handler chain pipeline straight into the SQL runtime environment
        my $sql_pipeline_identifier = 'PIPE_' . $pipeline_name;

        my $registered = 0;
        eval {
            $dbh->sqlite_create_function($sql_pipeline_identifier, 1, $compiled_sub);
            $registered = 1;
        };

        if (!$registered || $@) {
            return App::DataFactory::Exception->new(
                component => 'PipelineCompiler',
                message   => "Failed to compile custom query pipeline chain '$sql_pipeline_identifier': $@"
            );
        }
    }

    return 1; # Pipelines configured successfully
}

1;
