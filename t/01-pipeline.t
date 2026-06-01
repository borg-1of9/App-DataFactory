use strict;
use warnings;
use utf8;

use Test::More;
use lib 'lib';
use JSON::XS;
use File::Spec;
use FindBin;
use DBI;

# Ensure all application modules load correctly inside the test harness
use_ok('App::DataFactory');
use_ok('App::DataFactory::Extractor');
use_ok('App::DataFactory::PluginManager');
use_ok('App::DataFactory::PipelineCompiler');

my $base_dir = File::Spec->catdir($FindBin::Bin, 'data');
my $csv_file = File::Spec->catfile($base_dir, 'test_data.csv');
my $json_file = File::Spec->catfile($base_dir, 'test_data.json');
my $xml_file = File::Spec->catfile($base_dir, 'test_data.xml');

# -------------------------------------------------------------------------
# TEST CASE 1: Full In-Memory Integration Sweep with Explicit Mapping
# -------------------------------------------------------------------------
subtest 'Explicit schema ETL pipeline execution mapping' => sub {
    plan tests => 3;

    my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", { RaiseError => 1, sqlite_unicode => 1 });

    # 1. Plugin registration verification
    my $pm = App::DataFactory::PluginManager->new();
    ok($pm->register_all_plugins($dbh), 'All core transformations plugins registered to SQLite handle');

    # 2. Pipeline registration verification
    my $pc = App::DataFactory::PipelineCompiler->new();
    my $pipelines = { normalize_source => [ { to_lower => "" }, { trim => "" } ] };
    ok($pc->compile_and_register_pipelines($dbh, $pipelines), 'Ordered execution pipelines compiled into native SQL');

    # 3. Extract data layers
    my $ext = App::DataFactory::Extractor->new();
    $ext->load_source($dbh, { id => "csv_source", type => "file", name => $csv_file, sep_char => ";", binary => 1, mapping => { 0 => "code", 1 => "name", 3 => "source_type" } });
    $ext->load_source($dbh, { id => "json_source", type => "file", name => $json_file, name_id => ["device_type", "status", "firmware"] });
    $ext->load_source($dbh, { id => "xml_source", type => "file", name => $xml_file, root_node => "/inventory/item", columns => ["hw_code", "location"] });

    # 4. Transform query validation via joined datasets extraction
    my $query = "SELECT c.code AS device_code, c.name AS device_name, j.status AS current_status FROM csv_source c LEFT JOIN json_source j ON PIPE_normalize_source(c.source_type) = j.device_type";
    my $res = $dbh->selectall_arrayref($query, { Slice => {} });

    is(scalar(@$res), 3, 'In-memory relational engine joined datasets into exactly 3 records');
    $dbh->disconnect();
};

# -------------------------------------------------------------------------
# TEST CASE 2: Schema Auto-Discovery Fallback Integration Testing
# -------------------------------------------------------------------------
subtest 'Schema-less autodiscovery processing routine parameters rules' => sub {
    plan tests => 2;

    my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", { RaiseError => 1, sqlite_unicode => 1 });

    # Bootstrap transformers to ensure environment parity
    App::DataFactory::PluginManager->new()->register_all_plugins($dbh);
    App::DataFactory::PipelineCompiler->new()->compile_and_register_pipelines($dbh, { normalize_source => [ { to_lower => "" } ] });

    my $ext = App::DataFactory::Extractor->new();

    # Trigger an ingestion without a mapping attribute profile explicitly
    my $res = $ext->load_source($dbh, { id => "csv_source", type => "file", name => $csv_file, sep_char => ";", binary => 1 });
    is($res, 1, 'Extractor completed schema-less csv load status flag successfully');

    # Attempt execution utilizing fallback zero-based column system names
    my $query = "SELECT col0, col1, col3 FROM csv_source WHERE col3 = 'DEVICE' OR col3 = 'device'";
    my $rows = $dbh->selectall_arrayref($query, { Slice => {} });
    is(scalar(@$rows), 2, 'Relational engine filtered data accurately matching col3 generated headers boundaries');

    $dbh->disconnect();
};

# -------------------------------------------------------------------------
# TEST CASE 3: Secure Error Handling Encapsulation Verification
# -------------------------------------------------------------------------
subtest 'Graceful exception mapping validations inside Extractor hooks' => sub {
    plan tests => 2;

    my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", { RaiseError => 1, sqlite_unicode => 1 });
    my $ext = App::DataFactory::Extractor->new();

    # Inject a non-existent file stream reference target purposefully
    my $err_obj = $ext->load_source($dbh, { id => "ghost", type => "file", name => "invalid_dataset_path.csv" });

    is(ref($err_obj), 'App::DataFactory::Exception', 'Framework successfully encapsulated failure into a structured Exception object');
    like($err_obj->message, qr/Unable to open physical source data stream/, 'Exception reports clean description details');

    $dbh->disconnect();
};

done_testing();

1;
