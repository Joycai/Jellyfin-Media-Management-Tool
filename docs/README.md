# Documentation

Four kinds of document, and they answer different questions. Start with the one
that matches yours:

| Document | Answers |
|---|---|
| [`../README.md`](../README.md) | What does this app do, and how do I install it? |
| [`../CHANGELOG.md`](../CHANGELOG.md) | What changed between two versions? |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | How do I set up, build, test and submit a change? |
| [`../CLAUDE.md`](../CLAUDE.md) | Why is the code shaped like this, and what will break if I change it? |
| **`docs/`** (here) | What was the app *specified* to be? |

Everything under `docs/` is a **spec** — the design and analysis the code was
written against. Specs are a record of a source (a design project, a page
teardown), so they are not rewritten when the code moves on. Where the two
disagree, **CLAUDE.md describes what exists** and is the one to trust; the spec
carries a short note saying where it landed, and anything designed but not yet
built is listed in [`spec/ui-redesign/backlog.md`](spec/ui-redesign/backlog.md)
rather than quietly dropped.

The specs are written in Chinese; the rest of the documentation is in English.

## UI redesign spec

[`spec/ui-redesign/`](spec/ui-redesign/) — transcribed value-for-value from the
Claude Design project (6 pages, 38 artboards). Every colour, radius, height and
duration in the app should be traceable to a line in here; a number that is not
is either a bug or a deliberate one-off that says which section it came from.
[Its own index](spec/ui-redesign/README.md) maps each document to the code that
implements it:

| | |
|---|---|
| [01 通用标准](spec/ui-redesign/01-foundations.md) | Colour, type, spacing, elevation, component states, motion → `lib/theme/design_tokens.dart` |
| [02 程序外壳](spec/ui-redesign/02-shell.md) | The 48px title bar on each OS, window state, drag regions, the no-blur surfaces |
| [03 浏览与详情](spec/ui-redesign/03-browse.md) | Main screen, file table, library grid, empty states, context menus |
| [04 刮削](spec/ui-redesign/04-scrape.md) | Scrape setup, progress, review and image assignment |
| [05 整理](spec/ui-redesign/05-organize.md) | Organize preview, apply, log, undo and history |
| [06 配置](spec/ui-redesign/06-config.md) | AI services, model parameters, settings sections, onboarding |
| [Backlog](spec/ui-redesign/backlog.md) | Designed but not yet buildable, and every ruled-on conflict with existing behaviour |

## Scrape module

| | |
|---|---|
| [`spec/scrape-module-spec.md`](spec/scrape-module-spec.md) | The feasibility study and architecture for the metadata pipeline — the four-tier extraction ladder, age gates, encoding, NFO merge. Implemented; see CLAUDE.md § Metadata scraping for what shipped. |
| [`spec/scrape-giga-recipe.md`](spec/scrape-giga-recipe.md) | A worked teardown of one real site, and the verified recipe for it. This is where the traps are documented — the folded/expanded synopsis that makes a learned recipe look healthy while it stores truncated text, and why a learned recipe is therefore never saved without a human saying so. |

The trimmed fixture for that teardown lives at
`test/fixtures/giga_product_7743.html` and is what pins the parser against real
markup.
