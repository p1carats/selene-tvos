# Selene for tvOS

[![Build tvOS](https://github.com/p1carats/selene-tvos/actions/workflows/build.yml/badge.svg)](https://github.com/p1carats/selene-tvos/actions/workflows/build.yml)

[Selene for tvOS](https://github.com/p1carats/selene-tvos) is an open source client for [Apollo](https://github.com/ClassicOldSong/Apollo), Sunshine, DuoStream, and other NVIDIA GameStream-compatible servers.

Originally forked from the [official Moonlight for iOS/tvOS app](https://github.com/moonlight-stream/moonlight-ios), Selene lets you stream your full collection of games and apps from your powerful desktop PC to your Apple TV.

There’s no dedicated documentation/wiki yet, but for now you can refer to:
- [Moonlight Wiki](https://github.com/moonlight-stream/moonlight-docs/wiki) for general usage/setup/troubleshooting
- [Apollo Wiki](https://github.com/ClassicOldSong/Apollo/wiki) for server-specific features


## Key differences with upstream

Selene is motivated by a personal need for tvOS-specific features and improvements (as I got bored from using my SHIELD solely for Moonlight). It’s also a fun side project to modernize and experiment with the aging, decade-old original codebase.

It is **not** intended to directly compete with or replace Moonlight. Instead, it’s an opinionated and streamlined rework focused solely on delivering a polished Apple TV experience.

> [!NOTE]  
> While upstream development may appear stalled (given the large number of open issues and pending PRs), there are signs of ongoing work behind the scenes. Some activity can be seen in development forks, and core developers have even hinted at future updates in community discussions. If you prefer a more general-purpose or officially supported experience, I’d recommend keeping an eye on Moonlight instead, as Selene takes a different direction and may not be a right fit for everyone.

In this effort, iOS and iPadOS support has been removed to reduce complexity and keep development efforts focused. Dependencies have also been reduced where possible in favor of using native Apple frameworks and tools.
Over time, Selene will move away from the legacy Objective-C/C codebase towards a much more modern Swift approach.


## Preemptive FAQ

**Why is iOS support removed?**  
I’m currently only interested in tvOS and don’t have the time to maintain multiple platforms.
The codebase is a decade old, fairly large, and prone to complexity, so dropping iOS/iPadOS support helps keep the scope manageable while I focus on modernizing and cleaning things up.
Support for other platforms might return in the future — but it’s not a priority for now.

**Some feature doesn’t work?**  
Selene is still considered an open beta, so some features might not work as expected. Don't hesitate to open an issue or start a Discussion if you need help or want to report something. 
In the meantime, useful resources include:
- [r/cloudygamer](https://reddit.com/r/cloudygamer)
- [r/moonlightstreaming](https://reddit.com/r/moonlightstreaming)
- The [Moonlight Discord](https://moonlight-stream.org/discord) (especially the `#apollo` channel)

**Can I contribute?**  
Absolutely! Feel free to open a PR if you're interested. I haven’t written contribution guidelines yet, but please:
- Keep things clean, and focus on tvOS-only features for now
- Do not attempt (yet) to rewrite large portions of the codebase to Swift, but preferably focus on breaking down existing components into smaller Swift-written ones
- Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary) convention
- **AI-generated code is acceptable, but please make sure you have thoroughly reviewed and understand what it does.**


## Building

- Install Xcode from the [App Store page](https://apps.apple.com/us/app/xcode/id497799835)
- Run `git clone --recursive https://github.com/p1carats/selene-tvos.git`
  -  If you've already cloned the repo without `--recursive`, run `git submodule update --init --recursive`
- Open Selene.xcodeproj in Xcode
- To run on a real device, you will need to locally modify the signing options:
  - Click on "Selene" at the top of the left sidebar
  - Click on the "Signing & Capabilities" tab
  - Under "Targets", select "Selene"
  - In the "Team" dropdown, select your name. If your name doesn't appear, you may need to sign into Xcode with your Apple account.
  - Change the "Bundle Identifier" to something different. You can add your name or some random letters to make it unique.
  - Now you can select your Apple device in the top bar as a target and click the Play button to run.


## Licensing and credits

Licensed under the [GNU GPLv3](LICENSE).

```
Selene for tvOS
Copyright (C) 2025 Noé Barlet

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

Credits to the original [Moonlight team and contributors](https://github.com/moonlight-stream/moonlight-ios/graphs/contributors) for building the original app this project is based on.

Special thanks to [andygrundman](https://github.com/andygrundman) for his more recent work, from which many yet-to-be-upstreamed commits have been borrowed and adapted.

Some commits are also freely inspired by work from [here](https://github.com/The-Fried-Fish/moonlight-ios-NativeMultiTouchPassthrough) and [there](https://github.com/J5892/moonlight-visionos).