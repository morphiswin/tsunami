# VHS Happiness (Project Zomboid mod)

Watching a VHS tape on a TV lowers your character's unhappiness, the same way
reading a book or comic does. Vanilla tapes are mostly about boredom and
skill XP; this mod adds a proper mood boost on top.

## How it works

While you watch a tape, every line of it that plays lowers your unhappiness a
little. A whole tape gives the same amount as the game's own reading material:

| Vanilla item / tape         | Unhappiness removed  |
| --------------------------- | -------------------- |
| Comic Book                  | 20                   |
| Book                        | 40                   |
| **Home VHS** (home videos)  | **20**, like a comic |
| **Retail VHS** (movies, TV) | **40**, like a book  |

- The bonus is spread over the tape's lines, so it doesn't matter how long
  the tape is or what day length you play on. Walk away halfway and you get
  half; come back later and finish it for the rest.
- Each tape gives its full amount once every 24 in-game hours. Rewinding or
  rewatching the same tape won't keep cheering you up, but a different tape
  will.
- You count as watching if you're within 8 tiles of the TV, on the same
  floor, with no wall in the way, and awake.
- A green "Unhappiness ↓" note pops up when a tape starts cheering you up.
- Boredom and skill XP from tapes are left to the vanilla game.

## Install (local mod)

1. Copy the `VHSHappiness` folder into your Zomboid mods folder:
   - Windows: `C:\Users\<you>\Zomboid\mods\`
   - Linux / macOS: `~/Zomboid/mods/`
   (Create the `mods` folder if it doesn't exist.)
2. Start the game, open **Mods** from the main menu and enable
   **VHS Happiness**.
3. For an existing save, enable it in that save's mod list too.

The folder works on both Build 41 and Build 42:

```
VHSHappiness/
├── mod.info                          Build 41
├── media/lua/client/VHSHappiness.lua Build 41
├── 42/mod.info                       Build 42
├── 42/media/lua/client/VHSHappiness.lua
└── common/                           required by Build 42 (empty)
```

The two `VHSHappiness.lua` files are identical. If you edit one, copy it over
the other.

## Tuning

Open `VHSHappiness.lua` (the one for your build) and change the values in
`VHSHappiness.Config` at the top:

| Setting              | Default | Meaning                                               |
| -------------------- | ------- | ----------------------------------------------------- |
| `RetailVHSTotal`     | 40      | Unhappiness removed by a whole movie / TV tape        |
| `HomeVHSTotal`       | 20      | Unhappiness removed by a whole home video tape        |
| `CooldownHours`      | 24      | Hours before the same tape works again (0 = no limit) |
| `MaxDistance`        | 8       | How many tiles from the TV still counts as watching   |
| `RequireLineOfSight` | true    | Walls between you and the TV block the bonus          |
| `ShowHaloText`       | true    | Show the "Unhappiness ↓" note when a tape starts      |

## Notes

- Built for single-player. In multiplayer the client changes the stat
  itself, so a server that owns player stats may override it.
- Supports both stat systems: `BodyDamage` unhappiness (Build 41 to 42.12)
  and `Stats`/`CharacterStat.UNHAPPINESS` (Build 42.13+).
- Every game function the mod calls was checked against the game's API for
  Build 41.78 and Build 42.12 through 42.21.

## Tests

The logic is tested against a mocked game API in a Lua 5.1 runtime:

```
pip install lupa
python3 tests/run_tests.py
```
