# Jinks

![Jinks — a little mischief for the static web](assets/jinks.png)

[![Hex](https://img.shields.io/hexpm/v/jinks?style=for-the-badge&color=6B5BA7)](https://hex.pm/packages/jinks)
[![HexDocs](https://img.shields.io/badge/HexDocs-jinks-FFB347?style=for-the-badge)](https://jinks.hexdocs.pm/)
[![Tests](https://img.shields.io/github/actions/workflow/status/peregrinefinch/jinks/test.yml?style=for-the-badge&label=tests)](https://github.com/peregrinefinch/jinks/actions/workflows/test.yml)

Jinks builds static sites from Markdown, TOML, and Tuck. Give a site a theme,
preview changes as you write, and publish the generated files anywhere.

From a Jinks checkout with [Pooka](https://pooka.run/) and Erlang installed:

```sh
pooka deps download
pooka run -- init my-site
pooka run -- serve my-site
```

Run `pooka run -- build my-site` to write the site to `my-site/public/`.

## Licence

Licensed under the [Apache License, Version 2.0](LICENSE).
