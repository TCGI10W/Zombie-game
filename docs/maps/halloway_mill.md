# HALLOWAY MILL — design doc (draft for approval)

Closed classic-rules map. Replaces Kessler Junction (map id `junction` → new id `mill`).

## Setting and story
Halloway Lumber Co., a 1970s riverside sawmill in a logging valley, autumn night, fog off the river.
The company ran a night shift treating timber with an experimental fungicide ("Batch 7") trucked in
under a government contract. The vats in the kiln shed ruptured; the night shift and the bunkhouse
went first. The valley road bridge is down. The only way out is a helicopter that can land on the
log landing by the river, but the radio in the foreman's office needs mains power, and the mill's
own hydro generator sits in the power house at the far end of the site.

Goal: survive, open the mill up, restore the hydro power, call the helicopter from the office radio,
hold the landing until it arrives.

## Scale and layout (1 char ≈ 2 m, north up, river along the east edge)

```
 x: -48                         0                          +48
    +-------------------------------------------------------+ z -40
    |  ~~ timber stacks / spawn yard N1 ~~       spawn N2   |
    |  +-----------+  w1    w2  +------------------+  ~~~~  |
    |  | BOARDING  |============| KILN SHEDS (5)   |  ~R~   |
    |  | HOUSE (6) |  D5 2000   |  vats, drying    |  ~I~   |
    |  | 2 storeys |            |  racks, catwalk  |  ~V~   |
    | w3 stairs    |            +------D4 1500-----+w4 ~E~   |
    |  +----D6-----+   +----------------------------+   ~R~  |
    |       |          |  SAWMILL FLOOR (3)  2 st.  |  w5  ~  |
    | w6    |   LOG    |  head saw, carriage track, |   ~~~~  |
    |  +----+------+   |  conveyors, upper sawyer   | +-----+|
    |  | COMPANY   |D3 |  booth (catwalk loop)      | |POWER||
    |  | STORE &   |1250+-----D2 1000---------------+ |HOUSE||
    |  | CANTEEN(4)|        +----------+   w8       | | (7) ||
    | w7  +-------+  D1 750 | FOREMAN'S|            |D7 3000||
    |  spawn W    |         | OFFICE + |  MILL YARD | +-----+|
    |             |  w9     | SCALE HSE|   (2)      | LOG    |
    |   gate      |         | START (1)|  log decks | LANDING|
    |  (locked)   |         +----------+  forklift  |  LZ    |
    |  spawn S1        w10        w11     spawn S2  | dock   |
    +-------------------------------------------------------+ z +40
```
Exact coordinates go into the greybox; footprints below.

| # | Zone | Footprint (m) | Opened by | Cost |
|---|------|---------------|-----------|------|
| 1 | Foreman's office + truck scale house (START) | 16 × 12, 1 storey | — | — |
| 2 | Mill yard (outdoor, log decks) | 30 × 22 | D1 office back door | 750 |
| 3 | Sawmill floor (2 storeys, catwalk) | 34 × 18 | D2 yard → mill bay door | 1000 |
| 4 | Company store & canteen | 16 × 14 | D3 yard → store side door | 1250 |
| 5 | Kiln sheds (3 sheds + vat room) | 30 × 14 | D4 mill → kiln | 1500 |
| 6 | Boarding house (2 storeys, 6 rooms) | 18 × 14 | D5 kiln → covered walk, or D6 store → house | 2000 / 1750 |
| 7 | Power house + log landing (LZ) | 12 × 14 + landing 14 × 24 | D7 yard → river gate | 3000 |

Two routes into the boarding house (D5 or D6) make a ring: office → yard → mill → kiln → house → store → yard.

### Barricaded windows (2.0 × 2.4 m) and spawn areas behind them
| Win | Zone | Wall | Outside spawn area |
|-----|------|------|--------------------|
| w1, w2 | Kiln | north | N1 timber stacks |
| w3 | Boarding house | west, ground floor | W woodline |
| w4 | Kiln | east | N2 riverbank |
| w5 | Sawmill | east | N2 riverbank |
| w6 | Boarding house | south porch | W woodline |
| w7 | Store | west | W gate road |
| w8 | Sawmill | south (faces yard) | inside yard: zombies from S2 climb the log decks |
| w9 | Office | west | S1 road |
| w10 | Office | south | S1 road |
| w11 | Yard fence gap (boarded fence) | south | S2 parking lot |
Plus two in the power house (river side) once it is open. Start room has 2 windows (w9, w10) so round 1 is fair.

## Power
Hydro generator in the power house (zone 7), lever on the turbine housing.
When it comes on: yard sodium floods and office/mill tube lights warm up (flicker then steady),
head saw spins (idle sound), conveyor belts move, the radio in the office lights up and becomes
usable, furnace and forge stations activate, kiln vat-room red warning beacons rotate.

## Station placement
| Thing | Where | Price |
|-------|-------|-------|
| KURZ-9 SMG | office, wall by the scale window | 1000 (ammo 500) |
| Ammo cache | office | 450 |
| COMMANDO M14A | yard, side of scale house | 1200 |
| TRENCH-12 pump | sawmill floor, by head saw | 1500 |
| .44 HAND CANNON | company store counter wall | 1750 |
| RAZORBACK LMG | kiln vat room | 3000 |
| LONGSHOT .50 | boarding house top floor hall (sightline down to yard) | 3500 |
| Ammo caches | yard, store, kiln | 450 |
| Mystery crate | 3 spots, starts in mill under the catwalk; moves to canteen kitchen, boarding house attic landing | 950 |
| Furnace | kiln shed 2 (the old drying furnace) | — |
| Forge | power house, by the turbine | 5000 |
| Second Wind | canteen, beside the soda cooler | (game default) |
| Supply depot | mill yard, forklift shed | (game default) |
| Exfil radio | foreman's office desk (needs power) | — |
| LZ | log landing on the river (`lz_pos`) | — |

### Three skulls
1. Office: on top of the scale-house filing cabinet, seen through the weighbridge window.
2. Sawmill: on a rafter beam above the head saw, only visible from the upper catwalk.
3. Boarding house: under a bunk in room 4 (top floor), behind a half-open door.

## Flow
- Training loops: (a) the mill yard around the two central log decks, wide, with a forklift and
  the scale house as anchors; (b) the sawmill floor loop around the head-saw carriage track
  (ground floor + stairs up to the catwalk and down the far end); (c) the log landing late game.
- Choke points: D2 mill bay door, the covered walk between kiln and boarding house (narrow, 3 m),
  the boarding-house stairwell.
- Sight lines: yard N–S from office to landing (40 m), sawmill catwalk over the floor,
  boarding-house top hall window over the yard (sniper perch).
- Cornering danger: canteen kitchen (dead end), kiln vat room, boarding-house upstairs rooms.

## Landmarks
| Zone | Landmark |
|------|----------|
| Office | red truck scale with the big dial and HALLOWAY LUMBER sign |
| Yard | yellow log loader / crane on the central deck, tall sodium pole |
| Sawmill | 3 m head-saw blade and the overhead carriage, sawdust chute |
| Store | COMPANY STORE painted sign, soda cooler, wood stove |
| Kiln | three brick kiln chimneys, green Batch 7 vats |
| Boarding house | two-storey clapboard house with wraparound porch |
| Power house | water-wheel / turbine penstock pipe down to the river |

## Lighting plan
- Power off: cold moonlight from the east (river), fog, burning oil drums in the yard and a
  fire at the kiln (fire_spots), flashlights; inside, only emergency kerosene lanterns in the office
  and store. Kiln vats glow faint green.
- Power on: warm sodium floods in the yard and landing, tube lights in office/mill/store,
  bare bulbs in the boarding house, rotating red beacons in the kiln, landing beacon lights
  ring the LZ.

## Not in this map
No churches, chapels, crosses, graves, bells, altars or symbols. Nothing generated or scattered by code.

## Build notes
Kit `art/blender/build_mill_kit.py` → `art/models/mill/` (one glb per building + prop sets:
mill machinery, lumber, store/canteen, bunkhouse furniture, kiln/vats, yard vehicles).
Script `scripts/world/mill/mill_map.gd`, `class_name MillMap extends BunkerArena`.
Review tool `tools/mill_shots.gd`.
