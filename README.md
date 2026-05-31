[![Actions Status](https://github.com/borg-1of9/App-DataFactory/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/borg-1of9/App-DataFactory/actions?workflow=test)
# NAME

App::DataFactory - Extensible Pipeline Data Ingestion and Relational Transformation Engine

# SYNOPSIS

    use App::DataFactory;
    my $exit_code = App::DataFactory->run(@ARGV);

# DESCRIPTION

App::DataFactory securely extracts raw structured streams (CSV, JSON, XML),
compiles functional Perl validation pipelines as native SQL routines,
and executes declarative memory-mapped schema joins inside an ephemeral database.

# OPTIONS

- **-c, --config**

    Path to the target YAML configuration pipeline blueprint profile on disk.

- **-h, --help**

    Display this comprehensive application usage manuals and command interface definitions.

# LICENSE

Copyright (C) Vladislav Kantor.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Vladislav Kantor <kantor.vladislav@gmail.com>
