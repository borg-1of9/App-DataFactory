# App::DataFactory - Feature Roadmap

This document outlines the planned milestones, future architecture enhancements, and upcoming features for the App::DataFactory framework.

---

## Milestone 1: Performance Optimization & Storage Affinities (Current Focus)
*Target Release: v0.3.0*

- [x] Implement flexible output format(e.g. `json`, `msgpack`, `csv`, `xml`, `yaml`) options inside `App::DataFactory`
- [ ] Implement Multi-Column/Composite Database Index Support inside `App::DataFactory::Extractor`
- [ ] Support index configuration for arrays of columns (e.g., `indexes: [ ["code", "source_type"] ]`)
- [ ] Integrate volatile database memory cache eviction and release mechanisms via `sqlite_db_config`
- [ ] Optimize database index performance parameters for ultra-large row records datasets

---

## Milestone 2: Cloud-Native Real-Time Streaming & Networking
*Target Release: v0.4.0*

- [ ] Implement asynchronous multiplexed `App::DataFactory::StreamEngine` leveraging non-blocking socket wrappers
- [ ] Establish JSON Lines (`\n` delimited objects) frame splitting protocol for continuous `STDIN` data feeds
- [ ] Build embeddable asynchronous daemon component for standalone network socket WebSocket microservice endpoints
- [ ] Support continuous live data payload injection, relational transformations, and immediate client delivery

---

## Milestone 3: Advanced Analytics & Extensible Ecosystem
*Target Release: v0.5.0+*

- [ ] Implement runtime execution pre-hooks and post-hooks allowing plugin mutation during transform phases
- [ ] Add multi-threaded processing pools execution mechanics for non-DB computational plugin tasks
- [ ] Deliver analytical extension plugin wrapper (`App::DataFactory::Plugin::AI`) for local LLM inference models
- [ ] Provide native abstract functions inside transform queries for real-time text enrichment (e.g., `AI_ANALYZE_SENTIMENT`)

---

## Technical Debt & Continuous Integration (CI/CD)
- [ ] Implement automatic version increment tag distributions using **Semantic Release** inside GitHub Actions
- [ ] Expand matrix integration testing suit coverage benchmarks to monitor raw performance throughput speeds
