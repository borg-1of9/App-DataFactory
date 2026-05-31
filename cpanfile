requires 'perl', '5.014000';

# Runtime application dependencies
requires 'Text::CSV_XS', '0';
requires 'YAML::XS',     '0';
requires 'JSON::XS',     '0';
requires 'DBI',          '0';
requires 'DBD::SQLite',  '0';
requires 'Try::Tiny',    '0';
requires 'XML::LibXML',  '0';

# Testing infrastructure dependencies
on 'test' => sub {
    requires 'Test::More',    '0.98';
    requires 'Capture::Tiny', '0';
};
