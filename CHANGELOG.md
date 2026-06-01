# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com),
and this project adheres to [Semantic Versioning](https://semver.org).

## - 2026-05-31

### Added
- Complete memory-mapped relational architecture powered by in-memory SQLite database (`dbi:SQLite:dbname=:memory:`).
- Multi-format ingestion support in `App::DataFactory::Extractor` handling CSV (`Text::CSV_XS`), JSON (`JSON::XS`), and XML (`XML::LibXML`) natively.
- Schema auto-discovery fallback mechanism for unmapped files generating unified `col0` to `colN` sequential column names with text affinities.
- Dynamic plugin management system (`App::DataFactory::PluginManager`) for loading customizable functional extensions.
- Sequential transformation pipeline compiler (`App::DataFactory::PipelineCompiler`) registering sequence loops as native SQL functions (`PIPE_*`).
- Secure execution flow wrapped entirely using `Try::Tiny` to eliminate unsafe string `eval` vulnerabilities.
- Safe parameters binding placeholders (`?`) across all extract ingest matrices protecting the engine from SQL Injection vectors.
- Unified structured output pattern delivering JSON and MessagePack payloads with clear success status and error telemetry scopes to `STDOUT` or physical files.
- Containerization blueprint `Dockerfile` and microservices orchestration definitions.
- Comprehensive integration testing suit verifying schema deployments, fallbacks, exception handling, and core plugins inside `t/01-pipeline.t`.

### Changed
- Refactored core nomenclature to industry-standard ETL structures: `extract`, `transform`, and `load`.
- Shifted codebase variables, logic comments, terminal log prints, and documentation entirely to the English language.

### Fixed
- Fixed array mapping references initialization errors inside the final serializer load phase loop.
- Resolved XPath locator evaluations crash conditions inside the XML extractor sequence block by making root nodes parameter discovery robust.
