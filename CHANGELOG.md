# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com),
and this project adheres to [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- [x] Compact payload optimization format (`structure: "matrix"`) to strip duplicate column key definitions from large arrays
- [x] Multi-tier object mapping architecture (`structure: "grouped"`) utilizing logical grouping blocks from extraction nodes

---

## - 2026-06-01

### Added
- [x] Automatic database B-Tree single-column optimization index generator (`_build_indexes`) inside `App::DataFactory::Extractor`
- [x] Dedicated metadata tracking module (`App::DataFactory::Metadata`) to manage release lifecycle signatures dynamically
- [x] Comprehensive in-memory test coverage fix inside `t/01-pipeline.t` resolving isolation constraints under Minilla build configurations
- [x] Dedicated `-v` and `--version` command-line switches to output release lifecycle signatures dynamically
- [x] Microservices streaming ingestion preparation layers inside core factory loop processing blocks

### Changed
- [x] Incremented official application release version to 0.2.0
- [x] Refactored core nomenclature schema layout to industry-standard ETL structures: `extract`, `transform`, and `load`
- [x] Shifted codebase variables, logic comments, terminal log prints, and documentation entirely to the English language

### Fixed
- [x] Repaired fatal multi-level reference lookup index typos inside the load phase serialization loop (`$config->{load}->`)
- [x] Fixed array mapping references initialization errors inside the final serializer load phase loop
- [x] Resolved XPath locator evaluations crash conditions inside the XML extractor sequence block by making root nodes parameter discovery robust
- [x] Fixed interactive CLI terminal block freezing issues on empty `STDIN` by deploying the non-interactive `-t STDIN` guard check

---

## - 2026-05-31

### Added
- [x] Initial core memory-mapped relational architecture powered by in-memory SQLite database (`dbi:SQLite:dbname=:memory:`)
- [x] Multi-format ingestion support in `App::DataFactory::Extractor` handling CSV, JSON, and XML files natively
- [x] Schema auto-discovery fallback mechanism for unmapped files generating unified `col0` to `colN` sequential columns
- [x] Dynamic plugin management system (`App::DataFactory::PluginManager`) for loading customizable functional extensions
- [x] Sequential transformation pipeline compiler (`App::DataFactory::PipelineCompiler`) registering sequences as native SQL functions (`PIPE_*`)
- [x] Secure execution flow wrapped entirely using `Try::Tiny` to eliminate unsafe string `eval` vulnerabilities
- [x] Safe parameters binding placeholders (`?`) across all extract ingest matrices protecting the engine from SQL Injection vectors
- [x] Unified structured output pattern delivering JSON and MessagePack payloads with clear success status and error telemetry scopes to `STDOUT` or physical files
