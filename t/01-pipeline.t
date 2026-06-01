use strict;
use warnings;
use utf8;

use Test::More tests => 5;
use lib 'lib';
use Capture::Tiny qw(capture);
use JSON::XS;
use File::Spec;
use FindBin;
use YAML::XS qw(DumpFile);

# Ensure the module can be loaded correctly
use_ok('App::DataFactory');

# Resolve absolute path to the directory containing our data artifacts
my $base_dir = File::Spec->catdir($FindBin::Bin, 'data');

# -------------------------------------------------------------------------
# HELPER: Generates a perfectly mapped runtime config structure with absolute paths
# -------------------------------------------------------------------------
sub get_absolute_test_config {
    my $cfg = {
        pipelines => {
            normalize_source => [
                { to_lower => "" },
                { trim     => "" }
            ]
        },
        extract => [
            {
                id       => "csv_source",
                type     => "file",
                name     => File::Spec->catfile($base_dir, 'test_data.csv'),
                sep_char => ";",
                binary   => 1,
                mapping  => {
                    0 => "code",
                    1 => "name",
                    3 => "source_type"
                }
            },
            {
                id      => "json_source",
                type    => "file",
                name    => File::Spec->catfile($base_dir, 'test_data.json'),
                name_id => ["device_type", "status", "firmware"]
            },
            {
                id        => "xml_source",
                type      => "file",
                name      => File::Spec->catfile($base_dir, 'test_data.xml'),
                root_node => "/inventory/item",
                columns   => ["hw_code", "location"]
            }
        ],
        transform => [
            {
                id    => "consolidated_view",
                query => "SELECT c.code AS device_code, c.name AS device_name, j.status AS current_status, j.firmware AS firmware_version, x.location AS warehouse_location FROM csv_source c LEFT JOIN json_source j ON PIPE_normalize_source(c.source_type) = j.device_type LEFT JOIN xml_source x ON c.code = x.hw_code"
            }
        ],
        load => [
            {
                source_id => "consolidated_view",
                type      => "stdout",
                name      => "-",
                format    => "json",
                pretty    => 1
            }
        ]
    };
    return $cfg;
}

# -------------------------------------------------------------------------
# TEST CASE 1: Verify the complete ETL execution flow using explicit mapping
# -------------------------------------------------------------------------
subtest 'Successful ETL pipeline run with explicit schema' => sub {
    plan tests => 5;

    my $runtime_config = get_absolute_test_config();
    my $temp_config_path = File::Spec->catfile($base_dir, 'temp_explicit_run.yaml');
    DumpFile($temp_config_path, $runtime_config);

    my ($stdout, $stderr, $exit_code) = capture {
        App::DataFactory->run('-c', $temp_config_path);
    };
    unlink $temp_config_path;

    is($exit_code, 0, 'Application exited successfully with status 0');
    is($stderr, '', 'No errors or unexpected warnings printed to STDERR');

    my $response;
    my $parsed_ok = 0;
    eval {
        $response = decode_json($stdout);
        $parsed_ok = 1;
    };

    ok($parsed_ok, 'STDOUT output contains a valid serialized JSON string');
    if ($parsed_ok) {
        is($response->{success}, 1, 'Unified JSON metadata state indicates success => 1');
        my $data = $response->{data};
        is(scalar(@$data), 3, 'Output array contains exactly 3 aggregated records');
    } else {
        fail('Unified JSON metadata state indicates success => 1');
        fail('Output array contains exactly 3 aggregated records');
    }
};

# -------------------------------------------------------------------------
# TEST CASE 2: Schema auto-discovery fallback warning verification
# -------------------------------------------------------------------------
subtest 'Fallback to schema-less autodiscovery configuration' => sub {
    plan tests => 3;

    my $runtime_config = get_absolute_test_config();

    # FIXED: Access extract array index [0] to strip mapping safely
    delete $runtime_config->{extract}[0]{mapping};

    # FIXED: Access transform array index [0] to adjust the SQL query target fields
    $runtime_config->{transform}[0]{query} = "SELECT c.col0 AS device_code, c.col1 AS device_name, j.status AS current_status, j.firmware AS firmware_version, x.location AS warehouse_location FROM csv_source c LEFT JOIN json_source j ON PIPE_normalize_source(c.col3) = j.device_type LEFT JOIN xml_source x ON c.col0 = x.hw_code";

    my $temp_config_path = File::Spec->catfile($base_dir, 'temp_schemaless_run.yaml');
    DumpFile($temp_config_path, $runtime_config);

    my ($stdout, $stderr, $exit_code) = capture {
        App::DataFactory->run('-c', $temp_config_path);
    };
    unlink $temp_config_path;

    like($stderr, qr/Warning \[Extractor\]: No column mapping schema found/, 'Correct schema warning emitted to STDERR');
    like($stderr, qr/ingested as TEXT.*'col0' to 'colN'/, 'User notified about col0-colN names rules allocation');

    my $response = decode_json($stdout);
    is($response->{success}, 1, 'Pipeline completed successfully even without initial mapping declaration');
};

# -------------------------------------------------------------------------
# TEST CASE 3: Secure error handling encapsulation and unified response
# -------------------------------------------------------------------------
subtest 'Graceful exception management with structured JSON response' => sub {
    plan tests => 4;

    my $ghost_file_path = File::Spec->catfile($base_dir, 'does_not_exist.csv');
    my $runtime_config = {
        extract => [
            {
                id   => "ghost_source",
                type => "file",
                name => $ghost_file_path
            }
        ],
        load => [
            {
                source_id => "ghost_source",
                type      => "stdout",
                format    => "json"
            }
        ]
    };

    my $temp_config_path = File::Spec->catfile($base_dir, 'temp_broken_run.yaml');
    DumpFile($temp_config_path, $runtime_config);

    my ($stdout, $stderr, $exit_code) = capture {
        App::DataFactory->run('-c', $temp_config_path);
    };
    unlink $temp_config_path;

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
