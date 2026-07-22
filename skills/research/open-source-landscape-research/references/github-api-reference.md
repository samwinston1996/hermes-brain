# GitHub REST API Reference for Landscape Research

## Search Repositories

```
GET https://api.github.com/search/repositories
```

### Key Parameters

| Param | Description | Example |
|-------|-------------|---------|
| `q` | Search query (qualifiers: `stars:>100`, `fork:true`, `language:python`) | `self-improving+agent+LLM` |
| `sort` | `stars` (default), `forks`, `updated`, `help-wanted-issues` |
| `order` | `desc` (default) or `asc` |
| `per_page` | Max 100 (default 30) |
| `page` | Page number |

### Rate Limits

| Auth | Limit | Header |
|------|-------|--------|
| None | 60 req/hr | — |
| Personal token | 5,000 req/hr | `Authorization: Bearer <token>` |
| App token | 5,000 req/hr | `Authorization: Bearer <token>` |

Response includes `total_count` and `incomplete_results` fields. If `incomplete_results` is `true`, results are truncated (usually only for very broad queries).

### Useful Qualifiers

| Qualifier | Example |
|-----------|---------|
| Stars range | `stars:>1000` |
| Language | `language:python` |
| Topic | `topic:ai-agent` |
| Updated | `pushed:>2026-01-01` |
| Not fork | `fork:true` (include forks; by default they're excluded) |
| Is template | `template:true` |

## Get Repository

```
GET https://api.github.com/repos/{owner}/{repo}
```

Returns: `stargazers_count`, `description`, `topics`, `language`, `updated_at`, `license`, `fork`, `size`, etc.

## Get Repository README

```
GET https://api.github.com/repos/{owner}/{repo}/readme
```

Returns base64-encoded content. Decode in Python:
```python
import base64
d = json.loads(resp.read())
content = base64.b64decode(d['content']).decode()
```

Also returns `download_url` (raw URL), `path`, `sha`.

## Raw File Content

```
GET https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}
```

Example: `https://raw.githubusercontent.com/aiwaves-cn/agents/main/README.md`

Note: some repos return 404 for raw URLs if they use default branch names other than `main`/`master`. Try `refs/heads/main` in the path or fall back to the README API.

## Search Code (alternative)

```
GET https://api.github.com/search/code?q={query}+repo:{owner}/{repo}
```

Requires authentication. Searches file contents within a specific repo. Useful for finding specific patterns in large codebases.

## Recommended Low-Rate-Limit Strategy

When unauthenticated (60 req/hr):

1. **Batch all search queries into one script** (each search = 1 request, ~20 queries max = 20 requests)
2. **Get metadata for top repos** (1 request per repo, ~5-10 repos = 5-10 requests)
3. **Get READMEs via raw URL** (doesn't count against API rate limit — uses GitHub CDN)
4. **Save remaining requests** for paper verification or fallback readmes from API

This leaves ~30 requests for the session and covers the full landscape in a single pass.

## Python Helper — All-in-One Search

```python
import json, urllib.request, urllib.parse, time

def search_github(query, per_page=10):
    url = f"https://api.github.com/search/repositories?q={urllib.parse.quote(query)}&sort=stars&order=desc&per_page={per_page}"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github.v3+json", "User-Agent": "research-agent"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())

# Multi-query usage
queries = ["self-improving agent", "self-evolving agent LLM", "autonomous agent"]
all_results = {}
for q in queries:
    data = search_github(q)
    all_results[q] = data['items']
    time.sleep(0.3)
```

## Avoiding 403/429 Errors

- Add `User-Agent` header (required by GitHub)
- Add `Accept: application/vnd.github.v3+json`
- Space requests by at least 0.3 seconds (unofficial but good practice)
- On 403 retry with exponential backoff (1s, 3s, 9s)
