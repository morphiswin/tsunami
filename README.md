# VHS & CD Happiness (Project Zomboid mod)

Watching a VHS tape on a TV, or listening to a music CD, lowers your
character's unhappiness, the same way reading a book or comic does. Each tape
and CD only does it once, so finding new ones is worth the trip. Skill tapes
are left alone: they still only give skill XP.

## How it works

While you watch a tape or listen to a CD, every line of it that plays lowers
your unhappiness a little. A whole tape or CD gives the same amount as the
game's own reading material:

| Vanilla item / tape / CD    | Unhappiness removed  |
| --------------------------- | -------------------- |
| Comic Book                  | 20                   |
| Book                        | 40                   |
| **Music CD**                | **20**, like a comic |
| **Home VHS** (home videos)  | **20**, like a comic |
| **Retail VHS** (movies, TV) | **40**, like a book  |

- The bonus is spread over the lines, so it doesn't matter how long the tape
  or CD is or what day length you play on. Stop halfway and you get half;
  come back later and finish it for the rest.
- **Each tape and CD works once per character, forever.** Replaying one
  you've already finished gives nothing; you need one you haven't heard or
  seen yet.
- **Skill tapes give no happiness.** Any tape that teaches a skill or recipe
  (carpentry, cooking, mechanics and so on) only gives the game's normal
  skill XP. In Build 41's tape list that's 42 of the 263 tapes: 28
  retail and 14 home videos.
- **CDs:** a CD player anywhere in your inventory (even in a bag) counts
  whenever you're awake. A CD playing on something in the world uses the
  same rule as TVs.
- **TVs:** you count as watching if you're within 8 tiles of the TV, on the
  same floor, with no wall in the way, and awake.
- A green "Unhappiness ↓" note pops up with every line that cheers you up,
  alongside the game's own "Boredom" note.
- Boredom and skill XP from tapes and CDs are left to the vanilla game.

## Tapes and CDs from other mods

There's no fixed list of tapes or CDs: the mod reads each one from the game
as it plays, so ones added by other mods work the same way.

- CDs and tapes are told apart by the game's own media type, so modded ones
  count even with their own category names. A modded tape is worth 20 like a
  home video if its category name contains "home", otherwise 40 like a movie.
- Modded skill tapes are spotted the same way as the game's: any line code
  that isn't a mood code (including codes for skills other mods add) means it
  teaches something, so it gives no happiness.
- TVs, radios and CD players added by other mods work too.
- Not covered: mods that play real audio files through their own players
  instead of the game's tape and CD lines.
- If a mod's movie or music gives no happiness, it probably uses a mood code
  this mod doesn't know. Add that code to `MoodCodes`.

## Install (local mod)

1. Copy the `VHSHappiness` folder into your Zomboid mods folder:
   - Windows: `C:\Users\<you>\Zomboid\mods\`
   - Linux / macOS: `~/Zomboid/mods/`
   (Create the `mods` folder if it doesn't exist.)
2. Start the game, open **Mods** from the main menu and enable
   **VHS & CD Happiness**.
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

| Setting              | Default  | Meaning                                                    |
| -------------------- | -------- | ---------------------------------------------------------- |
| `RetailVHSTotal`     | 40       | Unhappiness removed by a whole movie / TV tape             |
| `HomeVHSTotal`       | 20       | Unhappiness removed by a whole home video tape             |
| `CDTotal`            | 20       | Unhappiness removed by a whole music CD                    |
| `MaxDistance`        | 8        | Tiles from a TV or radio that still count                  |
| `RequireLineOfSight` | true     | Walls between you and a TV or radio block the bonus        |
| `ShowHaloText`       | true     | Show the "Unhappiness ↓" note with each line               |
| `MoodCodes`          | 16 codes | Line codes that only change mood; anything else is a skill |

## Notes

- A mod that already gives happiness for tapes or CDs will stack with this
  one.
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
