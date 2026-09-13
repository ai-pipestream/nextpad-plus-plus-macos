# OpenNLP integration roadmap

This is a proposal for experiments in my Nextpad++ fork. It is not a commitment
by the upstream project, and it does not ask upstream to take on the full
integration. I would like to use the fork to test the editor experience, gather
feedback, and identify small features that might be useful upstream.

The existing [semantic heatmap PR](https://github.com/nextpad-plus-plus/nextpad-plus-plus-macos/pull/346)
is a separate, narrower change. Its Apple Natural Language and Metal/MPS
implementation does not depend on the OpenNLP integration proposed here.

## Motivation

A text editor is a useful place to explore language because every result can
lead directly back to the text being edited. I want to try an optional analysis
panel that connects words, phrases, entities, and relationships to their exact
source passages, with navigation in both directions:

- Select text to inspect its annotations and related terms.
- Select an annotation or graph node to highlight its occurrences in the editor.
- Select a relationship to inspect the source passages and analysis that support it.

The first experiment should answer whether this helps people read, search, and
understand documents without interrupting ordinary editing.

## Existing foundation

I am an Apache OpenNLP committer developing a preview that integrates upstream
work with additional research branches. This preview is not an Apache release;
some features remain under development or review.

The integration already contains an immutable document model with typed
annotation layers and mappings between original and normalized text. Alignment
supports both directions and composition across normalization stages, including
defined behavior for expansions, collapses, and deletions.

The integrated feature families include:

- Multilingual stemming, lemmatization, glossary annotations, and term vectors.
- WordNet lookup and lexical expansion.
- Named entities, dependency annotations, relation extraction, and coreference.
- Gazetteers, geographic resolution, region voting, hierarchy, and place profiles.
- PII and numeric annotations, text normalization, dehyphenation, and recasing.
- Static embeddings, embedding annotations, vector search, and evaluation.

These capabilities have different maturity levels and model requirements.
Inclusion in the preview does not establish accuracy for a particular language,
document type, or editor workflow.

An existing gRPC implementation already exposes much of the foundation,
including stemming, lexical expansion, term vectors, geocoding, dependency
parsing, and relation extraction. It returns typed annotation layers and
supports UTF-8 byte offsets, which fit Scintilla's document positions. The wider
research surface is being brought into the service incrementally; this roadmap
does not assume that every preview feature is already available over gRPC.

## Phase 1: Connect the editor to existing analysis

Start with the existing gRPC service so the editor interaction can be evaluated
independently of native-library packaging.

- Make analysis explicitly optional, with a configured local or remote endpoint.
- Explain where document text will be sent before enabling a remote endpoint.
- Query service capabilities and model availability to determine which controls
  to offer. Report unavailable features clearly.
- Send a document snapshot and associate results with its revision. Discard
  obsolete responses after edits, tab changes, or closing the analysis panel.
- Keep networking, analysis, and result preparation off the editor's UI thread.
- Present a compact inspector for the selected word or phrase, including its
  source span, available linguistic annotations, and related terms.

Evaluate this with Unicode text, normalization changes, rapid edits, document
switching, service failures, and large documents. Selection and highlighting
must remain correct, and typing must remain responsive.

## Phase 2: Explore words and relationships

Build a word map from the annotations already available. Keep relationship
types distinct so users can understand why two nodes are connected:

- Same stem or lemma: inspect word families and their occurrences.
- WordNet relationship: explore lexical neighbors with relation and lexicon provenance.
- Gazetteer identity: navigate mentions linked to a particular entry.
- Dependency or extracted relation: inspect linguistic connections in context.
- Embedding similarity: discover related passages with a visible score and model identity.
- Co-occurrence, if added: show shared context without presenting it as a
  linguistic relation or shared identity.

Keep graph positions stable during ordinary editing. Let users expand a
selected neighborhood, filter relationship types, and switch to an accessible
list view. Every document-backed node or edge should provide a route to its
supporting text; external lexical neighbors should be identified as such.

Evaluate whether users can answer concrete questions: where a concept appears,
which words describe an entity, and why two passages were considered related.

## Phase 3: Add focused document tools

Choose additions based on feedback from the first two phases:

- Entity and place navigation, followed by coreference where supported.
- Repeated-passage and terminology inspection.
- Topic navigation and a document overview.
- Optional PII inspection with explicit user review before any redaction.
- Annotation correction and export for corpus development and model evaluation.

Some of these are new editor workflows or additional analysis work, rather
than features obtained merely by connecting an existing endpoint. Each should
have a small, independently testable scope.

## Phase 4: Evaluate a local native library

Investigate compiling a selected OpenNLP analysis surface into a GraalVM shared
library with a small C interface for the Objective-C++ application. The intended
benefit is local analysis without requiring a separately managed Java server.

The analysis implementation is designed to avoid reflection, and external models
are downloadable. Those are promising starting conditions, but compatibility
must be verified for the selected components and their transitive dependencies.

The prototype should establish:

- Successful model loading and analysis on Apple Silicon and Intel macOS.
- An explicit contract for text encoding, result ownership, errors, and cleanup.
- Reuse of loaded models across requests and defined thread/isolate ownership.
- Agreement with the JVM implementation on annotations and source offsets for
  the same inputs, models, and settings, with appropriate numeric tolerances.
- Measured startup time, latency, memory consumption, and model-download behavior.
- A maintainable packaging and update process with model licensing accounted for.

Keep the editor's annotation presentation independent of transport so a native
backend can reuse the experience developed against gRPC. Start with the smallest
useful component set and expand only after the native path is demonstrated.

## Collaboration with upstream

I would welcome feedback on the overall fit, preferred extension points, UI
conventions, and how much of this belongs in an optional integration. I can
develop and test the experiments in my fork and bring back screenshots,
measurements, and narrowly scoped proposals.

Any upstream contribution would be discussed and submitted separately, with its
own dependencies, validation, and maintenance implications. This roadmap is
intended as a conversation starter, not a request to accept a large feature set.

## Status

Planning only. No OpenNLP editor integration or GraalVM compatibility test has
been performed as part of this proposal. The existing semantic heatmap PR also
still identifies native macOS validation as pending in its submitted description.

This document is intended for the fork. Keep its publication separate from the
branch used by the existing upstream PR so it is not added to that PR inadvertently.
