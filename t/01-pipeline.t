use strict;
use warnings;
use utf8;

use Test::More tests => 5;
use lib 'lib';
use Capture::Tiny qw(capture);
use JSON::XS;
use File::Spec;

# Ensure the module can be loaded correctly
use_ok('App::DataFactory');

# Build explicit relative paths to our mock test artifacts
my $config_path = File::Spec->catfile('t', 'data', 'config.yaml');
my $csv_path    = File::Spec->catfile('t', 'data', 'test_data.csv');
my $json_path   = File::Spec->catfile('t', 'data', 'test_data.json');
my $xml_path    = File::Spec->catfile('t', 'data', 'test_data.xml');

# -------------------------------------------------------------------------
# TEST CASE 1: Verify the complete ETL execution flow using explicit mapping
# -------------------------------------------------------------------------
subtest 'Successful ETL pipeline run with explicit schema' => sub {
    plan tests => 5;

    # Capture STDOUT, STDERR and the exit code of our main orchestrator
    my ($stdout, $stderr, $exit_code) = capture {
        App::DataFactory->run('-c', $config_path);
    };

    is($exit_code, 0, 'Application exited successfully with status 0');
    is($stderr, '', 'No errors or unexpected warnings printed to STDERR');

    # Parse the unified response matrix
    my $response;
    my $parsed_ok = 0;
    eval {
        $response = decode_json($stdout);
        $parsed_ok = 1;
    };

    ok($parsed_ok, 'STDOUT output contains a valid serialized JSON string');
    is($response->{success}, 1, 'Unified JSON metadata state indicates success => 1');
    diag("DEBUG PIPELINE ERROR MESSAGE: " . $response->{error}{message}) if !$response->{success};
    # Verify the structure and content of our joined database rows
    my $data = $response->{data};
    is(scalar(@$data), 3, 'Output array contains exactly 3 aggregated records');
};

# -------------------------------------------------------------------------
# TEST CASE 2: Schema auto-discovery fallback warning verification
# -------------------------------------------------------------------------
subtest 'Fallback to schema-less autodiscovery configuration' => sub {
    plan tests => 3;

    # Create a temporary modified config file missing the mapping field block
        my $temp_config_path = File::Spec->catfile('t', 'data', 'temp_schemaless_config.yaml');

        open my $in_fh, '<:encoding(utf8)', $config_path or die $!;
        open my $out_fh, '>:encoding(utf8)', $temp_config_path or die $!;
        while (<$in_fh>) {
            # 1. Dynamically strip the mapping definition lines for the csv source block
            next if /^\s+mapping:/ .. /^\s+source_type:/; # Strip up to the last mapping key cleanly

            # 2. FIXED: Rewrite the SQL query on the fly to use correct auto-generated column positions
            s/c\.source_type/c.col3/g; # Index 3 becomes col3 (DEVICE)
            s/c\.code/c.col0/g;        # Index 0 becomes col0 (id1435)

            print $out_fh $_;
        }
        close $in_fh;
        close $out_fh;


    my ($stdout, $stderr, $exit_code) = capture {
        App::DataFactory->run('-c', $temp_config_path);
    };

    # Clean up the temporary testing asset file from disk immediately
    unlink $temp_config_path;

    # Check that our Extractor module successfully triggered the STDERR alerts
    like($stderr, qr/Warning \[Extractor\]: No column mapping schema found/, 'Correct schema warning emitted to STDERR');
    like($stderr, qr/ingested as TEXT.*'col0' to 'colN'/, 'User notified about col0-colN names rules allocation');

    my $response = decode_json($stdout);
    is($response->{success}, 1, 'Pipeline completed successfully even without initial mapping declaration');
    diag("DEBUG SCHEMA-LESS ERROR: " . $response->{error}{message}) if !$response->{success};
};

# -------------------------------------------------------------------------
# TEST CASE 3: Secure error handling encapsulation and unified response
# -------------------------------------------------------------------------
subtest 'Graceful exception management with structured JSON response' => sub {
    plan tests => 4;

    # Create a broken config targeting a non-existent CSV data source file
    my $broken_config_path = File::Spec->catfile('t', 'data', 'temp_broken_config.yaml');
    open my $out_fh, '>:encoding(utf8)', $broken_config_path or die $!;
    print $out_fh <<'EOF';
---
extract:
  - id: "ghost_source"
    type: "file"
    name: "t/data/does_not_exist.csv"
load:
  - source_id: "ghost_source"
    type: "stdout"
    format: "json"
EOF
    close $out_fh;

    my ($stdout, $stderr, $exit_code) = capture {
        App::DataFactory->run('-c', $broken_config_path);
    };
    unlink $broken_config_path;

    is($exit_code, 1, 'Application returned error state code 1');

    my $response = decode_json($stdout);
    is($response->{success}, 0, 'Unified response status set to false => 0');
    is($response->{error}{component}, 'PipelineEngine', 'Error correctly localized to the execution core engine');
    like($response->{error}{message}, qr/Unable to open physical source data stream/, 'User receives clean explanation message instead of crash logs');
};

# -------------------------------------------------------------------------
# TEST CASE 4: Verification of Core Plugin transformations execution
# -------------------------------------------------------------------------
subtest 'Core plugin text manipulation operations execution' => sub {
    plan tests => 3;

    require App::DataFactory::Plugin::CoreTransformations;
    my $funcs = App::DataFactory::Plugin::CoreTransformations->register_functions();

    is($funcs->{PERL_TO_LOWER}->('ROUTER'), 'router', 'Plugin conversion to lowercase works natively');
    is($funcs->{PERL_TO_UPPER}->('switch'), 'SWITCH', 'Plugin conversion to uppercase works natively');
    is($funcs->{PERL_TRIM}->('  spaced  '), 'spaced', 'Plugin whitespace edge trimming routines clean data accurately');
};

1;
