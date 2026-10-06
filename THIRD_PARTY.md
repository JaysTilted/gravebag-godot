# Third-party source

## FSoD backend

- Upstream: https://github.com/ossimc82/fabiano-swagger-of-doom
- Pinned revision: `6fd20aad4a7905b13f25389c68368a942a2b68cb`
- License: GNU Affero General Public License v3, preserved in `LICENSE` and upstream `references/fsod/LICENSE`.
- Original source is retained as a pinned Git submodule at `references/fsod`; restore with `git submodule update --init references/fsod`.
- `references/.gdignore` keeps reference sources, Flash clients, bundled libraries and upstream assets outside Godot imports. They are not game runtime dependencies.
- Adaptations: GDScript gameplay modules carry source-path provenance and modification dates. Our visuals and audio remain separate from the upstream assets.
- The combined game incorporating these adaptations is distributed under AGPLv3; retain matching source alongside releases.

Upstream README credits: ossimc82/Fabian Fischer, C453, Trapped, Donran, creepylava, Krazyshank, Barm, Nilly, sebastianfra12, Kieron, and other contributors on MPGH or other sites.

**Status:** pinning the whole source is not a working C# server or a complete gameplay port. Runtime adapters must be integrated and tested separately. The original account, networking and database servers are not running in the Godot game.

## Claude Code Game Studios

- Upstream: https://github.com/Donchitos/Claude-Code-Game-Studios
- Copyright (c) 2026 Donchitos; MIT license retained at `third_party/licenses/CCGS-MIT.txt`.
- Studio tools and documentation retain their original notices.
