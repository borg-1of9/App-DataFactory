package App::DataFactory::Extractor;

use strict;
use warnings;
use utf8;
use Text::CSV_XS;
use JSON::XS;
use XML::LibXML;
use Encode qw(:fallbacks);
use App::DataFactory::Exception;

our $VERSION = "0.2.1";

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
  my $id = $source->{id};
  my $mapping = $source->{mapping};

  # 1. READ CONFIGURATION ENCODING WITH UTF-8 FALLBACK
  my $encoding = lc($source->{encoding} // 'utf-8');

  # Validate if Perl actually supports the requested encoding layout
  if (!Encode::find_encoding($encoding)) {
    print STDERR "Warning [Extractor]: Requested encoding '$encoding' is not supported by Perl. Falling back to 'utf-8'.\n";
    $encoding = 'utf-8';
  }

  # Dispatch analytical tracing diagnostic logs to standard error
  print STDERR "Info [Extractor]: Processing source '$id' using explicit encoding layer '$encoding'\n";

  # 2. OPEN THE FILE DESCRIPTOR WITH THE EXPLICIT ENCODING LAYER
  open my $fh, "<:encoding($encoding)", $source->{name} or return App::DataFactory::Exception->new(
    component => 'Extractor',
    message   => "Unable to open physical source data stream '$source->{name}': $!"
  );

  # CRITICAL UNIVERSAL SAFETY NET
  # If the user-defined encoding is slightly off, substitute invalid bytes with '?' instead of crashing
  local ${^ENCODING_FALLBACK} = FB_DEFAULT;

  my $csv = Text::CSV_XS->new({
    binary   => ($source->{binary}) ? 1 : 0,
    sep_char => $source->{sep_char} // ';',
  });

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

    # FIXED: Securely rewind file descriptor AND clear internal Text::CSV_XS diagnostics state
    seek($fh, 0, 0);
    $csv->SetDiag(0);
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

  # Build indexes for the table
  ##$self->_build_indexes($dbh, $source);

  return 1;
}

sub _build_indexes {
  my ($self, $dbh, $source) = @_;
  my $id = $source->{id};

  # Get column information from the table
  my $columns = $dbh->selectcol_arrayref("PRAGMA table_info(" . $dbh->quote_identifier($id) . ")");

  # Create a B-Tree index for each column
  foreach my $column (@$columns) {
    my $index_sql = sprintf("CREATE INDEX idx_%s_%s ON %s (%s)", $id, $column, $dbh->quote_identifier($id), $dbh->quote_identifier($column));
    eval { $dbh->do($index_sql); };
    if ($@) {
      return App::DataFactory::Exception->new(
        component => 'Extractor',
        message   => "Failed to create index on column '$column' for table '$id': $@"
      );
    }
  }

  return 1;
}

# Internal handler for flat or associative JSON arrays schema parsing
sub _import_json {
  my ($self, $dbh, $source) = @_;
  my $id      = $source->{id};
  my $columns = $source->{name_id} // $source->{columns};

  # 1. READ CONFIGURATION ENCODING WITH UTF-8 FALLBACK
  my $encoding = lc($source->{encoding} // 'utf-8');

  if (!Encode::find_encoding($encoding)) {
    print STDERR "Warning [Extractor]: Requested encoding '$encoding' is not supported by Perl. Falling back to 'utf-8'.\n";
    $encoding = 'utf-8';
  }

  print STDERR "Info [Extractor]: Processing JSON source '$id' using explicit encoding layer '$encoding'\n";

  open my $fh, "<:encoding($encoding)", $source->{name} or return App::DataFactory::Exception->new(
    component => 'Extractor',
    message   => "Unable to open physical JSON stream source '$source->{name}': $!"
  );

  # Enable fallback mapping to replace invalid bytes with '?'
  local ${^ENCODING_FALLBACK} = FB_DEFAULT;

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

  # Execute transactional block insertion routines for JSON records
  $dbh->begin_work;
  foreach my $row (@$records) {
    my @bind_values;
    foreach my $col_name (@$columns) {
      push @bind_values, $row->{$col_name};
    }
    $sth->execute(@bind_values);
  }
  $dbh->commit;

  # Build indexes for the table
  $self->_build_indexes($dbh, $source);

  return 1;
}

# Internal handler for hierarchically structured XML document parsing
sub _import_xml {
  my ($self, $dbh, $source) = @_;
  my $id        = $source->{id};
  my $root_node = $source->{root_node} // 'record';
  my $columns   = $source->{columns};

  # 1. READ CONFIGURATION ENCODING WITH UTF-8 FALLBACK
  my $encoding = lc($source->{encoding} // 'utf-8');

  if (!Encode::find_encoding($encoding)) {
    print STDERR "Warning [Extractor]: Requested encoding '$encoding' is not supported by Perl. Falling back to 'utf-8'.\n";
    $encoding = 'utf-8';
  }

  print STDERR "Info [Extractor]: Processing XML source '$id' using explicit encoding layer '$encoding'\n";

  open my $fh, "<:encoding($encoding)", $source->{name} or return App::DataFactory::Exception->new(
    component => 'Extractor',
    message   => "Unable to open physical XML data stream '$source->{name}': $!"
  );

  local ${^ENCODING_FALLBACK} = FB_DEFAULT;

  local $/;
  my $raw_xml = <$fh>;
  close $fh;

  my $parser = XML::LibXML->new();
  my $dom;
  eval { $dom = $parser->parse_string($raw_xml); };
  if ($@) {
    return App::DataFactory::Exception->new(
      component => 'Extractor',
      message   => "Failed to compile XML DOM structure layout for ID '$id': $@"
    );
  }

  # Extract targeted dataset loops using customizable query lookups
  my @nodes = $dom->findnodes("//$root_node");

  if (!defined $columns || (ref($columns) eq 'ARRAY' && !@$columns)) {
    if (@nodes) {
      my %discovered_fields;
      foreach my $child ($nodes[0]->childNodes()) {
        if ($child->nodeType == 1) { # XML_ELEMENT_NODE
          $discovered_fields{$child->nodeName} = 1;
        }
      }
      my @sorted_keys = sort keys %discovered_fields;
      $columns = \@sorted_keys;

      print STDERR "Warning [Extractor]: No explicit columns schema provided for XML source ID '$id'.\n";
      print STDERR "                    Auto-discovered node elements: " . join(', ', @$columns) . "\n";
    } else {
      return App::DataFactory::Exception->new(
        component => 'Extractor',
        message   => "XML dataset schema sniff failed for '$id'. Structure matches no valid elements for path '//$root_node'."
      );
    }
  }

  my @sql_columns = map { $dbh->quote_identifier($_) . " TEXT" } @$columns;
  my $create_sql  = sprintf("CREATE TABLE %s (%s)", $dbh->quote_identifier($id), join(', ', @sql_columns));

  eval { $dbh->do($create_sql); };
  if ($@) {
    return App::DataFactory::Exception->new(
      component => 'Extractor',
      message   => "Failed to initialize SQL XML relational mapping space '$id': $@"
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

  # Execute transactional block insertion routines
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

  # Build indexes for the table
  $self->_build_indexes($dbh, $source);

  return 1;
}

1;
