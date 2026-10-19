# Third-party notices

FantasyGlass's application, backend and test logic were written for this project. Apple's frameworks and SDK are supplied separately by Apple under their applicable terms.

ESPN numeric statistic/team/position identifiers were corroborated using the public `cwendt94/espn-api` project and real public ESPN responses. No implementation from that project is linked or required at runtime. The community project is MIT-licensed; its [license](https://github.com/cwendt94/espn-api/blob/master/LICENSE) and contributor notices apply to that project. The identifier catalog is factual mapping data, not an official ESPN specification.

`Core/Tests/FantasyCoreTests/Fixtures/espn-scoreboard.json` is a reduced historical response fetched from ESPN's public NFL scoreboard on 2026-10-18. It is used solely as an adapter test fixture. `espn-league.json`, `sportsdata-players.json` and `scoring-contract.json` are synthetic test inputs, clearly separated from real imports. No actual private league cookies or user API keys are included.

The backend's development dependencies are TypeScript (Apache-2.0), `@types/node` (MIT), and its `undici-types` type dependency (MIT). The lockfile pins their resolved versions. There are no runtime npm packages and no remote Swift package dependencies.

The generated football icon is original to this project. Provider-supplied player photo URLs, if present, remain subject to their owner's terms; no athlete photo library or sports logo collection is bundled.

ESPN, NFL, Apple, SportsDataIO, Sportradar, Sleeper, Yahoo, AltStore and Sideloadly names are used for identification. FantasyGlass is not affiliated with or endorsed by those organizations. Source availability does not grant a sports-data, image, trademark or redistribution license.

The applicable MIT license is also included locally in [ESPN_COMMUNITY_LICENSE.txt](docs/ESPN_COMMUNITY_LICENSE.txt).
