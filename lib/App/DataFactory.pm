package App::DataFactory;

use strict;
use warnings;
use utf8;

use Getopt::Long qw(GetOptionsFromArray :config no_ignore_case bundling);
use Pod::Usage qw(pod2usage);
use YAML::XS qw(LoadFile);
use Try::Tiny;
use DBI;
use JSON::XS;

# Load our modular infrastructure sub-components
use App::DataFactory::Exception;
use App::DataFactory::PluginManager;
use App::DataFactory::PipelineCompiler;
use App::DataFactory::Extractor;
use App::DataFactory::Metadata;

our $VERSION = "0.1.0";

# Main application orchestrator entry point
sub run {
    my ($class, @args) = @_;

    # Ensure CLI interface terminals handle standard Unicode streams
    binmode(STDOUT, ":utf8");
    binmode(STDERR, ":utf8");

    # 1. Parsing Command Line Option Configurations
    my %opts = (
        config => undef,
        help   => 0,
    );

    GetOptionsFromArray(
        \@args,
        'c|config=s' => \$opts{config},
        'v|version' => \$opts{version},
        'h|help'     => \$opts{help},
    ) or do {
        pod2usage(-exitval => 2, -verbose => 0, -input => __FILE__);
    };

    if ($opts{version}) {
        my $meta = App::DataFactory::Metadata->get_release_info();
        printf("App::DataFactory version %s (%s, build status: %s)\n",
            $meta->{version}, $meta->{release_date}, $meta->{status});
        return 0;
    }

    if ($opts{help}) {
        pod2usage(-exitval => 0, -verbose => 1, -input => __FILE__);
    }

    # Declare runtime contextual placeholders
    my $config;
    my $is_pure_stdin_mode = 0;
    my $exit_status = 0;

    # Initialize a unified metadata payload container for structured M2M communication
    my $response_payload = {
        success => 1,
        error   => undef,
        data    => undef,
    };

    # Default fallback target routing parameters
    my $target_format = 'json';
    my $target_type   = 'stdout';
    my $target_name   = '-';
    my $pretty_print  = 0;

    # 2. Determine configuration delivery stream mechanics
    if (!defined $opts{config}) {
        # -t STDIN checks if the standard input is interactive (connected to a terminal/keyboard)
        if (-t STDIN) {
            # User launched the binary without arguments and without piping any data.
            # Show the usage manual help screen immediately and exit cleanly.
            pod2usage(-exitval => 0, -verbose => 1, -input => __FILE__);
            return 0;
        }

        # If STDIN is NOT interactive, it means data is being piped in (e.g., cat data | datafactory)
        if (!-t STDIN) {
            $is_pure_stdin_mode = 1;
        } else {
            $exit_status = 1;
            $response_payload->{success} = 0;
            $response_payload->{error} = {
                component => 'Core',
                message   => "Missing configuration file parameter (--config) and no data found on STDIN."
            };
        }
    }

    # 4. Initialize virtual database workspace and execute processing pipelines
    if ($exit_status == 0) {
        my $dbh;
        try {
            # Spin up the volatile relational scratchpad environment
            $dbh = DBI->connect(
                "dbi:SQLite:dbname=:memory:", "", "",
                {
                    RaiseError     => 1, # Throws exceptions handled natively via Try::Tiny
                    PrintError     => 0, # Quiet down core logging channels to prevent interface noise
                    AutoCommit     => 1,
                    sqlite_unicode => 1, # Force native multi-byte encoding configurations
                }
            );

            # 5. Connect and initialize extension plugins workspace functions
            my $plugin_mgr = App::DataFactory::PluginManager->new();
            my $plugin_res = $plugin_mgr->register_all_plugins($dbh);
            if (ref($plugin_res) eq 'App::DataFactory::Exception') {
                die $plugin_res->as_string;
            }

            # 6. Chain custom transformation structures into memory-mapped pipeline routes
            if (defined $config->{pipelines}) {
                my $compiler = App::DataFactory::PipelineCompiler->new();
                my $compile_res = $compiler->compile_and_register_pipelines($dbh, $config->{pipelines});
                if (ref($compile_res) eq 'App::DataFactory::Exception') {
                    die $compile_res->as_string;
                }
            }

            # 7. EXTRACT PHASE: Populate database structures using secure parameters bindings
            if (defined $config->{extract}) {
                my $extractor = App::DataFactory::Extractor->new();
                foreach my $source_node (@{$config->{extract}}) {

                    # If monolithic stream contains internal records payload array, override processing context
                    if ($is_pure_stdin_mode && exists $config->{_inline_data_payload}{$source_node->{id}}) {
                        # Temporarily dump inline data to structure for extractor compatibility
                        # (Will be fully integrated with direct stream feeds later)
                        next;
                    }

                    my $extract_res = $extractor->load_source($dbh, $source_node);
                    if (ref($extract_res) eq 'App::DataFactory::Exception') {
                        die $extract_res->as_string;
                    }
                }
            }

            # 8. TRANSFORM PHASE: Run declarative relational workspace mapping transformations
            if (defined $config->{transform}) {
                foreach my $transform_node (@{$config->{transform}}) {
                    my $table_id  = $transform_node->{id};
                    my $sql_query = $transform_node->{query};

                    # Safely compile a destination view table out of custom processing definitions
                    my $composed_sql = sprintf(
                        "CREATE TABLE %s AS %s",
                        $dbh->quote_identifier($table_id),
                        $sql_query
                    );
                    $dbh->do($composed_sql);
                }
            }

            # 9. LOAD PHASE: Parse configuration profiles for serialization stage
            if (defined $config->{load} && ref($config->{load}) eq 'ARRAY' && @{$config->{load}}) {
                my $load_node = $config->{load}[0]; # Fix: Target the first configuration profile element explicitly
                $target_format = lc($load_node->{format} // 'json');
                $target_type   = lc($load_node->{type}   // 'stdout');
                $target_name   = $load_node->{name}      // '-';
                $pretty_print  = $load_node->{pretty}    // 0;

                my $source_id = $load_node->{source_id};
                my $fetch_sql = sprintf("SELECT * FROM %s", $dbh->quote_identifier($source_id));
                $response_payload->{data} = $dbh->selectall_arrayref($fetch_sql, { Slice => {} });
            }

        } catch {
            # Catch global execution runtime anomalies and format them into the payload error response
            $exit_status = 1;
            $response_payload->{success} = 0;
            $response_payload->{error}   = {
                component => 'PipelineEngine',
                message   => "$_"
            };
        };

        # 10. Memory cleanups and structural connection disengagements
        if (defined $dbh) {
            $dbh->disconnect();
        }
    }

    # 11. UNIFIED SERIALIZATION PHASE: Output either structured payload OR packed error matrix
    my $encoded_stream;

    if ($target_format eq 'msgpack') {
        require Data::MessagePack;
        my $mp_engine = Data::MessagePack->new();
        $encoded_stream = $mp_engine->pack($response_payload);
    } else {
        # Fallback to standard clean JSON serialization formats
        my $json_engine = JSON::XS->new->utf8;
        $json_engine->pretty(1) if $pretty_print;
        $encoded_stream = $json_engine->encode($response_payload);
    }

    # Stream the encoded block out to the designated destination target channels
    if ($target_type eq 'stdout' || $target_name eq '-') {
        if ($target_format eq 'msgpack') {
            binmode(STDOUT, ':raw'); # Guard binary stream alignment for messagepack payloads
        } else {
            binmode(STDOUT, ':utf8');
        }
        print STDOUT $encoded_stream;
    } else {
        open my $out_fh, ">", $target_name or do {
            print STDERR "Error [Core]: Cannot write output file target channel '$target_name': $!\n";
            return 1;
        };
        if ($target_format eq 'msgpack') {
            binmode($out_fh, ':raw');
        } else {
            binmode($out_fh, ':encoding(utf8)');
        }
        print $out_fh $encoded_stream;
        close $out_fh;
    }

    return $exit_status;
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

App::DataFactory - Extensible Pipeline Data Ingestion and Relational Transformation Engine

=head1 SYNOPSIS

    use App::DataFactory;
    my $exit_code = App::DataFactory->run(@ARGV);

=head1 DESCRIPTION

App::DataFactory securely extracts raw structured streams (CSV, JSON, XML),
compiles functional Perl validation pipelines as native SQL routines,
and executes declarative memory-mapped schema joins inside an ephemeral database.

=head1 OPTIONS

=over 4

=item B<-c, --config>

Path to the target YAML configuration pipeline blueprint profile on disk.

=item B<-h, --help>

Display this comprehensive application usage manuals and command interface definitions.

=back

=head1 LICENSE

Copyright (C) Vladislav Kantor.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Vladislav Kantor E<lt>kantor.vladislav@gmail.comE<gt>

=cut
