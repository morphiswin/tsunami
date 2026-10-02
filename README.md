# VHS Happiness (Project Zomboid mod)

Watching a VHS tape on a TV lowers your character's unhappiness, the same way
reading a book or comic does. Vanilla tapes are mostly about boredom and
skill XP; this mod adds a proper mood boost on top.

## How it works

While a TV near you is playing a tape, your unhappiness drops a little every
in-game minute. The amounts match the game's own reading material:

| Vanilla item / tape         | Unhappiness removed  |
| --------------------------- | -------------------- |
| Comic Book                  | 20                   |
| Book                        | 40                   |
| **Home VHS** (home videos)  | **20**, like a comic |
| **Retail VHS** (movies, TV) | **40**, like a book  |

- The bonus builds up over 45 in-game minutes of watching. Walk away early
  and you keep what you got so far; come back later to finish the tape.
- Each tape gives its full amount once every 24 in-game hours. Rewinding the
  same tape won't keep cheering you up, but a different tape will.
- You count as watching if you're within 8 tiles of the TV, on the same
  floor, with no wall in the way, and awake.
- A green "Unhappiness ↓" note pops up when the bonus starts.
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

| Setting               | Default | Meaning                                                  |
| --------------------- | ------- | -------------------------------------------------------- |
| `RetailVHSTotal`      | 40      | Unhappiness removed by one movie / TV tape               |
| `HomeVHSTotal`        | 20      | Unhappiness removed by one home video tape               |
| `MinutesForFullBonus` | 45      | In-game minutes of watching to get the full amount       |
| `CooldownHours`       | 24      | Hours before the same tape works again (0 = no limit)    |
| `MaxDistance`         | 8       | How many tiles from the TV still counts as watching      |
| `RequireLineOfSight`  | true    | Walls between you and the TV block the bonus             |
| `ShowHaloText`        | true    | Show the "Unhappiness ↓" note when the bonus starts      |

## Notes

- Built for single-player. In multiplayer the client changes the stat
  itself, so a server that owns player stats may override it.
- Tapes play in real time, so with long day-length settings a tape can end
  before 45 in-game minutes pass. Play it again (within the 24 hours) to get
  the rest.
- Supports both stat systems: `BodyDamage` unhappiness (Build 41 to 42.12)
  and `Stats`/`CharacterStat.UNHAPPINESS` (Build 42.13+).

## Tests

The logic is tested against a mocked game API in a Lua 5.1 runtime:

```
pip install lupa
python3 tests/run_tests.py
```
