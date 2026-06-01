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

=begin markdown

# App::DataFactory

App::DataFactory is a highly-extensible, secure, and blazing-fast data engineering command-line utility and library written in Perl. It safely ingests diverse, multi-format raw datasets (CSV, JSON, XML, MessagePack) or live streams into an ephemeral, memory-mapped SQLite database workspace.

Custom data-cleansing pipelines declared in configuration files are dynamically compiled into native SQL functions, enabling complex relational transformations, multi-source `JOIN` operations, and schema filtering on a single execution pass.

The utility operates natively in two modes:
1. **Hybrid Mode**: Merges persistent static configuration definitions on disk with shifting data streams from local paths or `STDIN`.
2. **Monolithic Microservice Mode**: Ingests both execution blueprint rules and row record payloads packed inside a single compound JSON buffer through standard input, running entirely in-memory with zero host storage attachments.

---

## Architecture Overview

App::DataFactory unifies the raw structural relational power of SQL with the agile text-manipulation capability of Perl. By abstracting operations into standard ETL sequences, it avoids heavy in-memory Perl nested hash operations.

```mermaid
graph TD
    A[Extract: CSV / JSON / XML / STDIN] -->|Secure Placeholders Ingest| B[(SQLite In-Memory DB)]
    C[Pipelines Configuration] -->|Dynamic Compilation| D[Perl Functional Layer]
    D -->|sqlite_create_function| B
    B -->|B-Tree Indexes Optimization| B
    B -->|Declarative Relational JOINs / SELECT| E[Unified Output Matrix]
    E -->|Formatters: JSON / MessagePack| F[Load: Files / STDOUT]
    G[App::DataFactory::Plugin::*] -->|Hooks / AI / Advanced Analytics| D
```

### Core Architecture Stages:
1. **Extract**: Parses external file descriptors or memory pipes into memory tables. Employs binding execution placeholders (`?`) across all ingest queries to completely eliminate SQL Injection threats.
2. **Transform**: Registers reusable ordered functional pipeline chains or plugin components into the virtual database environment as standard SQL routines (`PIPE_*`) before running raw relational schema modifications.
3. **Load**: Serializes structured response matrices containing automated execution telemetry, operational status, and records collections out to files or `STDOUT`.

---

## Installation & Requirements

### Prerequisites
- Perl 5.14+ (Perl 5.34+ highly recommended)
- Standard compilation tools (`make`, `gcc`, `libxml2-dev` for XML parsing extensions)

### Installing Required CPAN Extensions
Install missing framework components using `cpanm` (CPAN Minus):
```bash
cpanm Try::Tiny YAML::XS DBI DBD::SQLite Text::CSV_XS JSON::XS XML::LibXML Data::MessagePack Capture::Tiny
```

### Building From Source
```bash
git clone https://github.com/borg-1of9/datafactory
cd App-DataFactory
perl Makefile.PL
make
make test
sudo make install
```

### Uninstallation
To completely scrub the application and binary hooks from your operating system:
```bash
sudo rm -f $(which datafactory)
sudo rm -rf /usr/local/share/perl5/site_perl/App/DataFactory*
```

---

## Global Configuration Schema (`config.yaml`)

The blueprint file structure uses clean ETL organization matrices:

```yaml
---
# 1. Sequential pipeline chains mapping text transformation routines
pipelines:
  normalize_source:
    - to_lower: ""
    - trim: ""

# 2. EXTRACT: Data ingestion and structural mapping rules
extract:
  - id: "csv_source"
    type: "file"
    name: "t/data/test_data.csv"
    sep_char: ";"
    binary: true
    # Directly maps sequential source indexes to database column IDs
    mapping:
      0: "code"
      1: "name"
      3: "source_type"
    # Automatically triggers B-Tree index creation instantly after commit
    indexes:
      - "code"
      - "source_type"

  - id: "json_source"
    type: "file"
    name: "t/data/test_data.json"
    name_id: ["device_type", "status", "firmware"]

  - id: "xml_source"
    type: "file"
    name: "t/data/test_data.xml"
    root_node: "/inventory/item"
    columns: ["hw_code", "location"]

# 3. TRANSFORM: Ephemeral relational schema manipulation queries
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

# 4. LOAD: Unified output serialization definitions
load:
  - source_id: "consolidated_view"
    type: "stdout"
    name: "-"
    format: "json"
    pretty: true
```

---

## Core Feature Showcases

### Schema Auto-Discovery (Schema-less Ingestion)
If the `mapping` or `columns` fields are completely omitted inside an `extract` configuration profile block, the engine automatically interrogates the structural layout boundaries from the very first row record:
1. Diagnostic warning alerts are safely route-dispatched to `STDERR` to keep `STDOUT` clean.
2. All discovered fields are securely allocated under `TEXT` storage affinities.
3. Fields are automatically assigned zero-based sequential system markers: **`col0`, `col1`, ... `colN`**.

#### Querying Auto-Generated Columns:
```yaml
transform:
  - id: "dynamic_view"
    query: >
      SELECT
        col0 AS record_id,
        CAST(col2 AS INTEGER) * 1.21 AS vat_price
      FROM raw_logs
      WHERE col3 = 'active'
```

### Native SQL Functions Interoperability
Because queries are passed straight to SQLite, you can use all standard SQL built-in tools side-by-side with your perlobject pipelines (`PIPE_*`):
- **Date Utilities**: `date(col3, '+1 day')`, `strftime('%Y', col3)`
- **Strings**: `LENGTH(col1)`, `SUBSTR(col2, 1, 4)`, `COALESCE(col4, 'N/A')`
- **Math**: `ROUND(col5, 2)`, `ABS(col6)`, `AVG(CAST(col7 AS REAL))`

---

## Command Line Interface (CLI) Manual

### Basic Usage Patterns
```bash
# Launch a persistent file-based automation blueprint profile
datafactory --config pipeline.yaml

# Shortcut argument options string syntax
datafactory -c pipeline.yaml

# Show comprehensive application help information and manuals
datafactory --help
```

### Microservice Streaming Execution (Pure STDIN)
Feed the runtime configuration schema alongside dataset payloads together into a compound stream packet. No volume mounting or file path configuration on disk is required:
```bash
cat monolithic_payload.json | datafactory
```

---

## Unified Response Matrix Format
App::DataFactory communicates using a strict **Unified Response Pattern** across both JSON and MessagePack targets. Even during catastrophic core execution script processing failures, a valid serialized block is returned to `STDOUT` so remote orchestrators (e.g., a WebSocket server) can gracefully catch the exception schema metadata:

### Success Output Object Structure
```json
{
  "success": 1,
  "error": null,
  "data": [
    {
      "device_code": "id1435",
      "device_name": "Main Router Base",
      "current_status": "operational"
    }
  ]
}
```

### Failure Output Object Structure
```json
{
  "success": 0,
  "error": {
    "component": "Extractor",
    "message": "Unable to open physical source data stream 't/data/wrong.csv': No such file"
  },
  "data": null
}
```

---

## Modular Plugin Development

Extend data parsing, apply mathematical analysis, or trigger external localized AI models (e.g., via local Ollama endpoint API calls) by dropping a custom package file under the `App/DataFactory/Plugin/` folder namespace path.

### Custom Plugin Implementation Template
```perl
package App::DataFactory::Plugin::Anonymizer;

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

# The framework manager automatically registers hooks compiled inside this subroutine
sub register_functions {
    return {
        'AI_HASH_MASK' => sub {
            my ($input_string, $salt) = @_;
            return undef unless defined $input_string;
            $salt //= "factory_secure_salt";
            return substr(sha256_hex($input_string . $salt), 0, 16);
        }
    };
}

1;
```
Once deployed, the customized expression `AI_HASH_MASK(column_id)` becomes instantly executable directly inside any query string within the `transform` definitions block.

---

## Containerization & Docker Blueprints

### Dockerfile
```dockerfile
FROM perl:5.38-slim

RUN apt-get update && apt-get install -y \
    build-essential \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

RUN cpanm --notest Try::Tiny YAML::XS DBI DBD::SQLite Text::CSV_XS JSON::XS XML::LibXML Data::MessagePack Capture::Tiny

WORKDIR /usr/src/app
COPY . .

RUN perl Makefile.PL && make && make install

ENTRYPOINT ["datafactory"]
CMD ["--help"]
```

### Building and Running the Image
```bash
# Build image locally
docker build -t borg-1of9/datafactory:latest .

# Run container in Hybrid Mode (Mounting local testing data volumes paths)
docker run --rm -v $(pwd)/t/data:/data borg-1of9/datafactory:latest --config /data/config.yaml

# Run container in Streaming Microservice Mode (Pure decoupled STDIN/STDOUT)
cat t/data/monolithic_payload.json | docker run -i --rm borg-1of9/datafactory:latest
```

=end markdown

=head1 LICENSE

Copyright (C) Vladislav Kantor.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Vladislav Kantor E<lt>kantor.vladislav@gmail.comE<gt>

=cut
