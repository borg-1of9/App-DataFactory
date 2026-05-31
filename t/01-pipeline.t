use strict;
use warnings;
use utf8;

use Test::More tests => 5;
use lib 'lib'; # Tells Perl to look for App::DataFactory inside the local lib/ directory
use Capture::Tiny qw(capture);
use JSON::XS;
use File::Spec;
use File::Basename;

# Ensure the module can be loaded correctly
use_ok('App::DataFactory');

# Establish an isolated testing directory context path
my $test_dir = File::Spec->catdir('t', 'data');
unless (-d $test_dir) {
    mkdir $test_dir or die "Cannot create test artifacts directory structure: $!";
}

my $config_path = File::Spec->catfile($test_dir, 'config.yaml');
my $csv_path    = File::Spec->catfile($test_dir, 'test_data.csv');
my $json_path   = File::Spec->catfile($test_dir, 'test_data.json');
my $xml_path    = File::Spec->catfile($test_dir, 'test_data.xml');

# Dynamically generate mock validation data structures inside the isolated path
open my $csv_fh, '>:encoding(utf8)', $csv_path or die $!;
print $csv_fh "id1435;Main Router Base;Internal Node;DEVICE;10G-SFP;Rack A\n";
print $csv_fh "id1455;Edge Firewall SW;Perimeter Security;Firewall;1G-RJ45;Rack B\n";
print $csv_fh "id1665;Access Switch 48P;Floor Distribution;device;POE-SFP;Rack C\n";
close $csv_fh;

open my $json_fh, '>:encoding(utf8)', $json_path or die $!;
print $json_fh encode_json([
  { device_type => "device",   status => "operational", firmware => "v14.2.1" },
  { device_type => "firewall", status => "maintenance", firmware => "v3.8.9" }
]);
close $json_fh;

open my $xml_fh, '>:encoding(utf8)', $xml_path or die $!;
print $xml_fh <<'EOF';
<?xml version="1.0" encoding="UTF-8"?>
<inventory>
  <item><hw_code>id1435</hw_code><location>Prague-DataCenter-Room1</location></item>
  <item><hw_code>id1455</hw_code><location>Prague-DataCenter-Room2</location></item>
  <item><hw_code>id1665</hw_code><location>Ostrava-Office-ServerRoom</location></item>
</inventory>
EOF
close $xml_fh;

open my $cfg_fh, '>:encoding(utf8)', $config_path or die $!;
print $cfg_fh <<EOF;
---
pipelines:
  normalize_source:
    - to_lower: ""
    - trim: ""

extract:
  - id: "csv_source"
    type: "file"
    name: "$csv_path"
    sep_char: ";"
    binary: true
    mapping:
      0: "code"
      1: "name"
      3: "source_type"

  - id: "json_source"
    type: "file"
    name: "$json_path"
    name_id: ["device_type", "status", "firmware"]

  - id: "xml_source"
    type: "file"
    name: "$xml_path"
    root_node: "/inventory/item"
    columns: ["hw_code", "location"]

transform:
  - id: "consolidated_view"
    query: >
      SELECT
        c.code AS device_code,
        c.name AS device_name,
        j.status AS current_status,
        j.firmware AS firmware_version,
        x.location AS warehouse_location
      FROM csv_source c
      LEFT JOIN json_source j ON PIPE_normalize_source(c.source_type) = j.device_type
      LEFT JOIN xml_source x ON c.code = x.hw_code

load:
  - source_id: "consolidated_view"
    type: "stdout"
    name: "-"
    format: "json"
    pretty: true
EOF
close $cfg_fh;

# -------------------------------------------------------------------------
# TEST CASE 1: Verify the complete ETL execution flow using explicit mapping
# -------------------------------------------------------------------------
subtest 'Successful ETL pipeline run with explicit schema' => sub {
    plan tests => 5;

    my ($stdout, $stderr, $exit_code) = capture {
        App::DataFactory->run('-c', $config_path);
    };

    is($exit_code, 0, 'Application exited successfully with status 0');
    is($stderr, '', 'No errors or unexpected warnings printed to STDERR');

    my $response;
    my $parsed_ok = 0;
    eval {
        $response = decode_json($stdout);
        $parsed_ok = 1;
    };

    ok($parsed_ok, 'STDOUT output contains a valid serialized JSON string');
    is($response->{success}, 1, 'Unified JSON metadata state indicates success => 1');

    my $data = $response->{data};
    is(scalar(@$data), 3, 'Output array contains exactly 3 aggregated records');
};

# -------------------------------------------------------------------------
# TEST CASE 2: Schema auto-discovery fallback warning verification
# -------------------------------------------------------------------------
subtest 'Fallback to schema-less autodiscovery configuration' => sub {
    plan tests => 3;

    my $temp_config_path = File::Spec->catfile($test_dir, 'temp_schemaless_config.yaml');

    open my $in_fh, '<:encoding(utf8)', $config_path or die $!;
    open my $out_fh, '>:encoding(utf8)', $temp_config_path or die $!;
    while (<$in_fh>) {
        next if /^\s+mapping:/ .. /^\s+source_type:/;
        s/c\.source_type/c.col3/g;
        s/c\.code/c.col0/g;
        print $out_fh $_;
    }
    close $in_fh;
    close $out_fh;

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

    my $broken_config_path = File::Spec->catfile($test_dir, 'temp_broken_config.yaml');
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

# Clean up all volatile generated testing assets before test loop exits
unlink $config_path, $csv_path, $json_path, $xml_path;
rmdir $test_dir;

1;
