# Co-op (up to 8 players)

## Playing with friends over Steam
1. Everyone starts **Steam** and signs in, then launches the game.
2. Host: **CO-OP → HOST STEAM SQUAD**, then **INVITE STEAM FRIENDS**
   (or friends right-click you in Steam → *Join Game*).
3. When everyone is in the squad list, the host presses **START GAME**.

Traffic goes through Steam's relay network (Steam Datagram Relay): no port
forwarding, no IP sharing, and players in different countries get Valve's
backbone routes instead of the public internet.

Everyone needs **the same build** of the game (a version check rejects
mismatches).

## Built for bad connections
- Your movement, aim and shots are local: they react instantly whatever
  your ping. Hits on zombies are predicted and confirmed by the host.
- Zombies/teammates are smoothed with an adaptive delay that grows with
  jitter; lost packets are skipped instead of resent late.
- Purchases, doors, kills, revives and rounds use the reliable channel.

## Co-op rules
- Going down without a Second Wind: 30 s bleed-out; a teammate holds
  **[E]** on you for 3 s to revive. With a Second Wind you get up alone.
- Dying: you spectate a teammate and respawn at the next round.
- Everyone down = game over. Zombie numbers and boss health scale with the
  squad size. Power-ups apply to the whole squad; points are your own.
- Extraction: each player boards the chopper on their own; it leaves when
  everyone alive is aboard or time runs out.

## Steam App ID
The game uses Valve's public test App ID **480** ("Spacewar"), so it works
without a Steam store page; friends see you as playing "Spacewar". To ship
it, get your own App ID (Steamworks / Steam Direct) and change
`STEAM_APP_ID` in `scripts/core/net.gd` and `steam_appid.txt`.

**Exporting:** put `steam_appid.txt` next to the exported `.exe`. The
GodotSteam libraries (`addons/godotsteam`, incl. `steam_api64.dll`) are
exported automatically.

## Without Steam
**HOST DIRECT** / **JOIN IP** use a direct connection on UDP port 24680
(LAN, or the host forwards that port).
