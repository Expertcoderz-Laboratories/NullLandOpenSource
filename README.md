# [ARCHIVE] NullLandOpenSource
This repository contains an open-source copy of NullLand, the former development sandbox place of Expertcoderz officially defunct since May 2022.

**⚠️ Anything here is released on an as-is basis. You may experiment with or use in your own projects, any scripts included within NullLand, but solely at your own discretion.**

Note: Some audio or audio-dependent commands (eg. ``;ussr``) may not function as intended following Roblox's audio privacy update.

## List of notable features included in NullLand (in the form of integrated Adonis plugins):
- A variety fun, trolling and utility commands (see following list)
- Loadable maps; toggleable environment
- Economy system (currency; shop; leaderboard)
- Gun system (highly configurable; with 79 weapons for demo in NullLand)
- Death effects & tools dropping system (press Q to drop an equipped tool)
- Chat integrations (chat tags & colors; Random Facts bot) & death messages
- Global logging system (event logs per server are exported to datastores for later administrative access)
- Interaction logs for logging player actions
- Note on the couch (allows players to leave messages that save across servers)
- Wearable vest armor
- Anti-autoclicking
- Anti-command-spam
- Rankags system (see Additional Resources section)
- Custom topbar and health GUI
- Roblox services have their names scrambled
- Command to load other admin systems such as HD Admin
- Command to kick players with a customized kick dialog
- VIP game pass (access to some commands + chat tag + energy sword loadout)
- Button on the couch that has a 50% chance of giving a player a random weapon upon activation, and a 50% chance of demolishing said player
- The Recursive Hallway
- The Undiscovered Troll (easter egg)
- More.
- Amogus.

## List of NullLand-specific commands (taken from script; non-exhaustive):
```
"<b>―――― Ranktag ―――――――――――――――――――――――――――――――</b>",
"[Players] !ranktag/!rt <on/off/toggle> - Set whether your overhead ranktag is visible",
"[Players] !setgroup/!sg <ecl/devforum/ei/pb/pbsfst/ii/ni/pi/cs>",
"- Set the group to be shown in your overhead ranktag. Compatible groups:",
"<i>ECL, DevForum, Epix Inc, Pinewood Builders, Innovation Inc, Nova Incorporated,</i>",
"<i>Pinewood Builders Special Forces Security Team #2, Pinewood Science Agency</i>",
"[Admins] ;redactranktag/;redactrt",
"<b>―――― Weapon ―――――――――――――――――――――――――――――――</b>",
"[Players] !colorsword <BrickColor> - Recolor your equipped energy sword",
"[Players] !swordtexture <ID> - Change the forcefield texture of your energy sword",
"[Players] !camo/!gunskin <BrickColor> - Change/reset the skin of your gun (if compatible)",
"[Players] !gunstats - Displays detailed statistics about your equipped gun",
"[Moderators] ;refillammo/;getammo/;refill <player>",
"[Moderators] ;droptools <player>",
"[Admins] ;tooldrops <on/off/toggle> <despawn time (default: 30-45 seconds)>",
"[Admins] ;teamkill/;tk <on/off/toggle>",
"<b>―――― VIP ―――――――――――――――――――――――――――――――――</b>",
"[VIP] !vip <on/off/toggle> - Set whether your VIP chat tag & color is enabled",
"[VIP] !r6 - Converts your character to R6",
"[VIP] !r15 - Converts your character to R15",
"[VIP] !clone - Clones your character",
"<b>―――― Miscellaneous ―――――――――――――――――――――――――――</b>",
"[Players] !acm <on/off/toggle> - Set whether the Avatar Context Menu is enabled",
"<i>To open the ACM, click on another player.</i>",
"[Players] ?adminpls - Gives you free temporary admin perms",
"[Moderators] ;customkill/;ckill <player> <cause>",
"[Admins] ;facts <on/off/toggle> <message frequency (default: 30-90 seconds)>",
"[Creators] ;loadadminsystem <hd/kohls/bae/sa/commander/0xC0FF3BAD>",
"[Creators] ;interactionlogs",
"[Creators] ;customkick/;ckick <player> <title> <message>",
"<b>―――― Economy ―――――――――――――――――――――――――――――――</b>",
"[Players] !store/!shop",
"[Players] !lb/!leaderboard",
"[Players] !remoteviewcredit <username>",
"[Players] !sendcredit <recipient player> <amount>",
"[Moderators] ;economylogs/;shoplogs <autoupdate? (default: false)>",
"[Moderators] ;viewinventory/;viewinv <player> <autoupdate? (default: false)>",
"[Admins] ;setcredit <player> <amount>",
"[Admins] ;addcredit/;givecredit <player> <amount>",
"[Admins] ;subcredit/;subtractcredit <player> <amount>",
"[Admins] ;savecredit <player>",
"[HeadAdmins] ;remotesetcredit <username> <amount>",
"[HeadAdmins] ;resetcredit <user>",
"[HeadAdmins] ;resetinventory/;resetinv <user>",
"<b>―――― Fun ――――――――――――――――――――――――――――――――――</b>",
"[Moderators] ;idk <player>",
"[Moderators] ;amogus <player>",
"[Moderators] ;particlefountain <player> <optional texture ID> <optional BrickColor>",
"[Contributors] ;communism",
"[Contributors] ;ccp",
"[Admins] ;hell <player>",
"[Admins] ;ionlaser <player> <repeat times> <destruction?> <pressure> <radius>",
"[Admins] ;demolish <player>",
"[Admins] ;ragdoll <on/off/toggle> <keep after respawns?>",
"[Admins] ;airstrike <player> <missiles (default: 30)> <area size (default: 200 studs)>",
"[HeadAdmins] ;missile/;nuclearstrike <player>",
"[HeadAdmins] ;sysadmin <player>",
"[Creators] ?ruin",
"<b>―――― Map ――――――――――――――――――――――――――――――――</b>",
"[Moderators] ;loadmap/;load <map name>",
"[Moderators] ;maplist/;maps",
"[Moderators] ;unloadmap/;clearmap <optional map name>",
"[Moderators] ;dummy <player> <respawns? (default: true)> <health (default: 100)>",
"[Moderators] ;npcs <count (max: 50)> <optional player>",
"[Moderators] ;robot <player> <count> <evil? (default: false)> <damage (default: 15)>",
"[Moderators] ;openswingdoors/;closeswingdoors",
"[Contributors] ;nullmode",
"[Contributors] ;killerpenguins <count (max: 50)> <optional player>",
"[Admins] ;regenhallway",
"[Admins] ;loadsky <Ft> <Bk> <Lf> <Rt> <Up> <Dn> <celestialBodies?> <starCount>",
"[HeadAdmins] ;locknullmode <on/off>",
"<i>Use ;clr to effectively clear any generated/summoned structures and NPCs.</i>",
"<b>―――― Logging ―――――――――――――――――――――――――――――――</b>",
"[Players] !serverid - Tells you the current server's identifier",
"<i>The NullLand Server ID is a shortened alternative to the JobId.</i>",
"[Creators] ;exportedlogs",
"[Creators] ;openexportedlog <server ID>",
"[Creators] ;delexportedlog <server ID>",
"[Creators] ;clearexportedlogs",
"[Creators] ;exportlogs",
"<i>Logs are exported automatically for every server (except in Studio).</i>",
"[Creators] ;clearnotehistory/;clearnotes",
```

## Additional Resources
These are officially-supported for public use; any issues with the scripts are guaranteed to be fixed when reported.
- [Overhead ranktags plugin for Adonis](https://www.roblox.com/library/6783672267)
- [Configurable rank doors](https://www.roblox.com/library/4832871543)
- [Configurable loadout givers](https://www.roblox.com/library/4781401905)
