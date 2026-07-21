# Contributing

Thanks for your interest in contributing. This project is developed by the
XR Future Forests Lab at the University of Freiburg. Contributions from
collaborators and the wider community are welcome.

## Ways to contribute

- **Report bugs** via the [GitHub issue tracker](https://github.com/XRFutureForests/digital-twin-db/issues).
- **Suggest features or improvements** — open an issue describing the use case.
- **Submit pull requests** for bug fixes, documentation improvements, or new
  features (see workflow below).
- **Improve documentation** — typo fixes, clearer examples, and additional
  usage guides are always appreciated.

## Development workflow

1. Fork the repository or create a feature branch.
2. Make focused changes — one logical change per pull request.
3. Keep diffs small. Split unrelated changes into separate PRs.
4. Update `CHANGELOG.md` under `[Unreleased]` if the change is user-visible.
5. Add or update tests where applicable.
6. Open a pull request with a clear description of what changed and why.

## Commit messages

Prefer short, imperative subject lines (≤ 72 chars) followed by a blank line
and a longer body if context is needed. Reference relevant issue IDs.

Example:
```
Add RLS policy for trees.measurements

Limit SELECT access to authenticated users with the `researcher` role.
Fixes XRFF-42.
```

## Code style

- **Python**: Black (88 char line length), snake_case, type hints on public
  functions.
- **SQL**: lowercase keywords, explicit JOIN syntax, schema-qualified names.
- **R**: tidyverse style, two-space indent.
- **TypeScript**: Deno-style single quotes, 2-space indent (Supabase edge
  functions).

An `.editorconfig` at the repository root enforces whitespace conventions.

## Secrets and sensitive data

- **Never commit** `.env` files, credentials, private keys, or production
  database dumps.
- Use `docker/.env.example` to document required environment variables; use
  `CHANGE_ME` placeholders.
- If you accidentally commit a secret, rotate it immediately and notify the
  maintainer before force-pushing anything to a shared branch.

## Questions

Open an issue or contact the maintainer.
