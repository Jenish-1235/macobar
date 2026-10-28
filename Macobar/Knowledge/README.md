# Knowledge
Semantic search over the user's own documents. Text is embedded by a local model server (LM Studio by default) and the index is kept on this Mac; nothing leaves it.

## Files
- `KnowledgeSettings.swift`: the embeddings server address (`knowledgeServerAddress`, default `http://localhost:1234/v1`; only localhost, 127.0.0.1 or ::1 is accepted, so document text never leaves the Mac), the model (`knowledgeEmbeddingModel`, default `text-embedding-nomic-embed-text-v1.5`) and the folders to index (`knowledgeFolders`, default ~/Documents and ~/Desktop), all in preferences.
- `EmbeddingsClient.swift`: `POST {address}/embeddings` with `{"model", "input": [texts]}` (OpenAI-compatible), 32 texts a request, 60 s timeout; decodes the vectors in input order (tested).
- `KnowledgeError.swift`: server not running, server refused (e.g. no model loaded), reply didn't match, folder can't be read; each says how to fix it.
- `DocumentFinder.swift`: walks the folders for .txt, .text, .md, .markdown, .rtf, .doc, .docx and .pdf files up to 20 MB, skipping hidden items, packages, `node_modules`, `.git`, `Library` and iCloud files that aren't downloaded; throws if a folder can't be listed.
- `DocumentText.swift`: reads a file's text: PDFKit for PDF, `NSAttributedString` with an explicit document type for RTF and Word, UTF-8 (or a detected encoding) otherwise.
- `TextChunker.swift`: collapses whitespace and splits text into passages of at most 1,200 characters that repeat about 200 characters of the one before, cutting between words (tested).
- `KnowledgeStore.swift`: the index: passages with unit-length vectors; load, save, remove documents, add a document, and cosine search with Accelerate (tested). Also `KnowledgeChunk` and `KnowledgeMatch`.
- `KnowledgeStatus.swift`: whether indexing is running, its progress, what's indexed, and why the last run stopped; `summary` says it in a sentence or two.
- `KnowledgeIndexer.swift`: the actor that owns the index: starts and cancels the background run, reports status, and answers searches.

## Public surface
- `KnowledgeIndexer(storeFolder:)`: `start(folders:) -> KnowledgeStatus`, `refreshIfIndexed()`, `stop()`, `status`, `search(_:limit:) -> [KnowledgeMatch]`
- `KnowledgeStore(model:)`, `load(from:model:)`, `save(to:)`, `removeDocuments(_:)`, `addDocument(path:modified:chunks:vectors:)`, `search(_:limit:)`
- `EmbeddingsClient(serverAddress:model:session:)`, `embed(_:)`, `vectors(from:)`
- `TextChunker.chunks(of:)`

## How indexing runs
1. Find every indexable document in the folders, with its modification date. A folder that can't be listed (missing, or access not allowed) stops the run before anything is dropped, so it can't look empty and wipe its documents.
2. Drop documents that were deleted, changed, or are no longer in the chosen folders. If nothing was dropped and nothing is new, stop without saving.
3. For each document not in the index (sorted by path): read its text off the actor, split it, embed the passages, add them. A document with no text is recorded with no passages, so it isn't read again until it changes.
4. Save every 100 documents and at the end. A failed request stops the run and its reason shows in the status; a cancelled run saves what it has.

## Storage
`~/Library/Application Support/macobar/knowledge/`: `manifest.json` (model, vector size, each document's modification date, every passage's path and text) and `vectors.f32` (raw little-endian Float32, one row per passage, in manifest order). Chosen over SQLite because search compares the query with every vector anyway, which needs them contiguous in memory for one `vDSP_mmul`; a database would add the C API and row decoding without making search faster. Rewriting both files is cheap at personal scale (10,000 passages of 768 floats is about 30 MB of vectors).

## Getting an embedding model
In LM Studio: download an embedding model (search "nomic embed text v1.5" in Discover, or `lms get nomic-embed-text-v1.5`), load it, and start the server (Developer tab, or `lms server start`). The server lists it as `text-embedding-nomic-embed-text-v1.5`. Ollama works too: `ollama pull nomic-embed-text`, then set `knowledgeServerAddress` to `http://localhost:11434/v1` and `knowledgeEmbeddingModel` to `nomic-embed-text`.

## Gotchas
- Vectors from different models can't be compared, so changing the model starts a fresh index.
- The two files are written one after the other; if macobar dies between them, their sizes disagree and the next run rebuilds the index from scratch. A damaged manifest whose vector size is negative, zero with passages, or so large the file size overflows also loads empty.
- Searching embeds the query, so the server must be running to search as well as to index.
- Only one run at a time; starting while one runs just reports its progress. Searches answer from what's indexed so far.
- iCloud Desktop & Documents files that are only in the cloud are skipped, since reading them would download them.

## Tested by
`MacobarTests/KnowledgeTests.swift`; damaged manifests in `MacobarTests/DeviceSafetyTests.swift`.

## Depends on
ModelClient (`JSONValue`), Accelerate, PDFKit, AppKit (rich text import).
