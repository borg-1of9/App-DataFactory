package App::DataFactory::Extractor;

use strict;
use warnings;
use utf8;
use Text::CSV_XS;
use JSON::XS;
use XML::LibXML;
use App::DataFactory::Exception;

our $VERSION = "0.1.0";

# Constructor for the extraction component
sub new {
    my ($class) = @_;
    return bless {}, $class;
}

# Master routing method to ingest raw datasets into memory-mapped SQLite tables
sub load_source {
    my ($self, $dbh, $source_config) = @_;

    my $id   = $source_config->{id};
    my $name = $source_config->{name} // '';

    # Robust check: If 'root_node' is present, it is 100% an XML structure
    if (exists $source_config->{root_node} || $name =~ /\.xml$/i) {
        return $self->_import_xml($dbh, $source_config);
    }
    # Process standard CSV datasets
    elsif ($name =~ /\.csv$/i) {
        return $self->_import_csv($dbh, $source_config);
    }
    # Process structured JSON data arrays
    elsif ($name =~ /\.json$/i) {
        return $self->_import_json($dbh, $source_config);
    }

    return App::DataFactory::Exception->new(
        component => 'Extractor',
        message   => "Unsupported extraction dataset layout engine or missing extensions for source ID '$id'"
    );
}

# Internal handler for structured CSV streaming ingestion
sub _import_csv {
    my ($self, $dbh, $source) = @_;
    my $id      = $source->{id};
    my $mapping = $source->{mapping};

    my $csv = Text::CSV_XS->new({
        binary   => ($source->{binary}) ? 1 : 0,
        sep_char => $source->{sep_char} // ';',
    });

    open my $fh, "<:encoding(utf8)", $source->{name} or return App::DataFactory::Exception->new(
        component => 'Extractor',
        message   => "Unable to open physical source data stream '$source->{name}': $!"
    );

    my @sql_columns;
    my @active_indices;
    my @column_names;

    # Check if explicit mapping configuration rules are active
    if (defined $mapping && ref($mapping) eq 'HASH' && %$mapping) {
        foreach my $idx (sort { $a <=> $b } keys %$mapping) {
            my $col_def = $mapping->{$idx};
            my $col_id   = ref($col_def) eq 'HASH' ? $col_def->{id}   : $col_def;
            my $col_type = ref($col_def) eq 'HASH' ? $col_def->{type} : 'TEXT';

            # Sanitize datatypes keyword strings to block invalid injection vectors
            $col_type = 'TEXT' unless $col_type =~ /^(TEXT|INTEGER|REAL|NUMERIC|DATETIME)$/i;

            push @sql_columns, $dbh->quote_identifier($col_id) . " $col_type";
            push @active_indices, $idx;
            push @column_names, $col_id;
        }
    } else {
        # Fallback Strategy Option B: Dynamically sniff schema boundaries from head row record
        my $first_row = $csv->getline($fh);
        unless ($first_row) {
            close $fh;
            return App::DataFactory::Exception->new(
                component => 'Extractor',
                message   => "Failed to auto-discover schema. Source CSV file '$source->{name}' appears empty."
            );
        }

        # Dispatch diagnostic warning notification to standard error channels
        print STDERR "Warning [Extractor]: No column mapping schema found for source ID '$id'.\n";
        print STDERR "                    All fields ingested as TEXT. Use auto-generated IDs 'col0' to 'colN' in your SQL transform queries.\n";

        my $total_cols = scalar(@$first_row);
        @active_indices = (0 .. $total_cols - 1);

        foreach my $idx (@active_indices) {
            my $generated_id = "col" . $idx;
            push @sql_columns, $dbh->quote_identifier($generated_id) . " TEXT";
            push @column_names, $generated_id;
        }

        # Rewind file descriptor to top position to preserve data integrity bounds
        seek($fh, 0, 0);
    }

    # Initialize structural volatile tables schema definitions
    my $create_sql = sprintf("CREATE TABLE %s (%s)", $dbh->quote_identifier($id), join(', ', @sql_columns));
    eval { $dbh->do($create_sql); };
    if ($@) {
        close $fh;
        return App::DataFactory::Exception->new(
            component => 'Extractor',
            message   => "Failed to initialize SQL schema table '$id': $@"
        );
    }

    # Build atomic query binders using secure placement placeholders
    my $placeholders = join(', ', map { '?' } @active_indices);
    my $insert_sql   = sprintf(
        "INSERT INTO %s (%s) VALUES (%s)",
        $dbh->quote_identifier($id),
        join(', ', map { $dbh->quote_identifier($_) } @column_names),
        $placeholders
    );
    my $sth = $dbh->prepare($insert_sql);

    # Execute transactional block insertion routines
    $dbh->begin_work;
    while (my $row = $csv->getline($fh)) {
        my @bind_values;
        foreach my $idx (@active_indices) {
            push @bind_values, $row->[$idx];
        }
        $sth->execute(@bind_values);
    }
    $dbh->commit;
    close $fh;

    return 1;
}

# Internal handler for flat or associative JSON arrays schema parsing
sub _import_json {
    my ($self, $dbh, $source) = @_;
    my $id      = $source->{id};
    my $columns = $source->{name_id} // $source->{columns};

    open my $fh, "<:encoding(utf8)", $source->{name} or return App::DataFactory::Exception->new(
        component => 'Extractor',
        message   => "Unable to open physical JSON stream source '$source->{name}': $!"
    );
    local $/;
    my $raw_content = <$fh>;
    close $fh;

    my $parsed_data;
    eval { $parsed_data = decode_json($raw_content); };
    if ($@) {
        return App::DataFactory::Exception->new(
            component => 'Extractor',
            message   => "Failed to parse structured JSON matrix stream data for ID '$id': $@"
        );
    }

    my $records = ref($parsed_data) eq 'ARRAY' ? $parsed_data : [$parsed_data];

    if (!defined $columns || (ref($columns) eq 'ARRAY' && !@$columns)) {
        if (@$records && ref($records->[0]) eq 'HASH') {
            my @discovered_keys = sort keys %{$records->[0]};
            $columns = \@discovered_keys;

            print STDERR "Warning [Extractor]: No explicit columns schema provided for JSON source ID '$id'.\n";
            print STDERR "                    Auto-discovered object fields: " . join(', ', @$columns) . "\n";
        } else {
            return App::DataFactory::Exception->new(
                component => 'Extractor',
                message   => "JSON dataset auto-discovery failed for '$id'. Payload is not a flat object collection dictionary array."
            );
        }
    }

    my @sql_columns = map { $dbh->quote_identifier($_) . " TEXT" } @$columns;
    my $create_sql  = sprintf("CREATE TABLE %s (%s)", $dbh->quote_identifier($id), join(', ', @sql_columns));

    eval { $dbh->do($create_sql); };
    if ($@) {
        return App::DataFactory::Exception->new(
            component => 'Extractor',
            message   => "Failed to initialize SQL JSON matrix representation space '$id': $@"
        );
    }

    my $placeholders = join(', ', map { '?' } @$columns);
    my $insert_sql   = sprintf(
        "INSERT INTO %s (%s) VALUES (%s)",
        $dbh->quote_identifier($id),
        join(', ', map { $dbh->quote_identifier($_) } @$columns),
        $placeholders
    );
    my $sth = $dbh->prepare($insert_sql);

    $dbh->begin_work;
    foreach my $row_record (@$records) {
        next unless ref($row_record) eq 'HASH';
        my @bind_values = map { $row_record->{$_} } @$columns;
        $sth->execute(@bind_values);
    }
    $dbh->commit;

    return 1;
}

# Internal handler for parsing structured XML documents via XPath selection nodes
sub _import_xml {
    my ($self, $dbh, $source) = @_;
    my $id        = $source->{id};
    my $columns   = $source->{name_id} // $source->{columns};
    my $root_node = $source->{root_node} // '//*';

    if (!defined $columns || (ref($columns) eq 'ARRAY' && !@$columns)) {
        return App::DataFactory::Exception->new(
            component => 'Extractor',
            message   => "XML processing requires explicit 'name_id' or 'columns' parameter list array inside source ID '$id'"
        );
    }

    my $parser = XML::LibXML->new();
    my $doc;
    eval { $doc = $parser->parse_file($source->{name}); };
    if ($@) {
        return App::DataFactory::Exception->new(
            component => 'Extractor',
            message   => "Failed to parse physical XML file targets for ID '$id': $@"
        );
    }

    # Extract target nodes matching the specified XPath expression rule
    my @nodes = $doc->findnodes($root_node);

    my @sql_columns = map { $dbh->quote_identifier($_) . " TEXT" } @$columns;
    my $create_sql  = sprintf("CREATE TABLE %s (%s)", $dbh->quote_identifier($id), join(', ', @sql_columns));
    eval { $dbh->do($create_sql); };
    if ($@) {
        return App::DataFactory::Exception->new(
            component => 'Extractor',
            message   => "Failed to initialize SQL XML schema mapping bounds '$id': $@"
        );
    }

    my $placeholders = join(', ', map { '?' } @$columns);
    my $insert_sql   = sprintf(
        "INSERT INTO %s (%s) VALUES (%s)",
        $dbh->quote_identifier($id),
        join(', ', map { $dbh->quote_identifier($_) } @$columns),
        $placeholders
    );
    my $sth = $dbh->prepare($insert_sql);

    $dbh->begin_work;
    foreach my $node (@nodes) {
        my @bind_values;
        foreach my $col_name (@$columns) {
            # Find matching sub-node element text value contents inside current entry bounds
            my @sub_nodes = $node->findnodes("./$col_name");
            my $val = @sub_nodes ? $sub_nodes[0]->textContent : undef;
            push @bind_values, $val;
        }
        $sth->execute(@bind_values);
    }
    $dbh->commit;

    return 1;
}

1;
