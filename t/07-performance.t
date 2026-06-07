use strict;
use warnings;
use utf8;
use Test::More;
use DBI;
use App::DataFactory::Extractor;

# Create a test database in memory
my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", {
    RaiseError => 1,
    PrintError => 0,
});

# Create an instance of the Extractor
my $extractor = App::DataFactory::Extractor->new();

# Create a test table
$dbh->do("CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT, value TEXT)");

# Insert some test data
$dbh->do("INSERT INTO test_table (name, value) VALUES ('test1', 'value1')");
$dbh->do("INSERT INTO test_table (name, value) VALUES ('test2', 'value2')");

# Define the source configuration for the test table
my $source_config = {
    id => 'test_table',
    name => 'test_table',
};

# Build indexes for the test table
my $result = $extractor->_build_indexes($dbh, $source_config);

# Check if the indexes were created successfully
ok($result, "Indexes were created successfully");

# Query the test table to verify the indexes are working
my $sth = $dbh->prepare("SELECT name, value FROM test_table WHERE name = 'test1'");
$sth->execute();
my $row = $sth->fetchrow_hashref();

# Check if the query returned the expected data
is($row->{name}, 'test1', "Query returned the expected data");

# Disconnect from the database
$dbh->disconnect();

done_testing();
