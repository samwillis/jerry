# Explorer animation workflow

## Running the playground

Build the Debug app, then use **Animation Playground…** in its hiking menu bar menu. Or quit the running app and launch directly:

```sh
./scripts/build.sh
build/Build/Products/Debug/OtherSock.app/Contents/MacOS/OtherSock --playground
```

The playground is a normal, focusable window separate from the desktop overlay. Closing it stops its rendering. It is excluded from Release builds. The enlarged preview and the actual-size preview use the same rig, clips, clock increments, and tuning values as the desktop character.

The clip menu contains idle, walking, climbing, abseiling, parachuting, held, investigating, and a nine-second edge-hesitation comic sequence. Pause freezes the clip clock but still permits manual contact editing. Restart resets the pose, clip time, origin, handholds, rope anchor, and grab point. Playback ranges from 0.1× to 1×; zoom ranges from 1× to 3×. Cadence, stride, and bounce are independent tuning controls.

In Climbing, drag either green handhold. An unreachable contact is red in the joint overlay, and the status line counts clamped contacts. The arm stays within its reachable length. In Abseiling, drag the yellow rope anchor. In Held, drag the pink grab point to change the pivot. In any clip, grab the body to interrupt it with the held pose; release blends back to the selected clip. Fake terrain stays fixed during that drag, and climbing handholds and the rope anchor retain their scene positions.

## Rig and coordinates

The canonical rig faces right, with +x towards the toes and +y upwards. Its origin is the simulation's foot baseline. Facing left mirrors the complete rig, including feet, contacts, and joint bend directions. Rendered pose offsets never change simulation position, terrain collision, or the pointer grab offset.

| Part | Parent / pivot | Shape or length |
| --- | --- | --- |
| Presentation pivot | Simulation origin; grab point when held | Rotates the visual rig only |
| Torso | Hips, nominally (0, 27) | Orange shape, neck, head attachment |
| Head and hat | Hips + (0, 32) | Combined rig height about 74 points |
| Backpack | Hips + (14, 10) | Independent secondary rotation |
| Upper arms | Shoulders at hips + (±10, 20) | 12 points each |
| Lower arms | Child of upper arm at elbow | 12 points each; hand at endpoint |
| Upper legs | Hips + (±7, 0) | 15 points each |
| Lower legs | Child of upper leg at knee | 15 points each; foot at endpoint |
| Boots | Lower-leg endpoints | Level soles and toes towards +x |
| Parachute | Visual rig | Appears after launch anticipation; does not accept input |

Two-bone IK solves each elbow/knee and endpoint. Anatomical pole targets favour knees ahead of the body and elbows behind it, rather than assigning arbitrary signs independently to each limb. Mirroring the entire rig preserves the relation between knees and toes. The hand or foot target is exact when reachable; beyond reach, the target remains visible for debugging while the actual endpoint is clamped.

`RigAnimator` blends numeric poses over 0.2 seconds and owns no asynchronous animation completions. Switching clips captures the current displayed pose. Restart deliberately bypasses the blend to establish a repeatable baseline. The desktop maps held input to the held clip, recovery to the parachute clip, and resting/settling to idle. Real walking routes and climbing progression are phase five; playground clips are animation demonstrations.

## Agent tasks and review loop

1. **Shape rig:** work in `ExplorerRig.swift`, keeping root → elbow/knee → hand/foot parenting explicit. Reproduce changes in the playground before using them on the desktop. Deliver a runnable build and a screenshot or short recording at enlarged and actual size.
2. **Movement refinement:** work in the pure `AnimationClips`, `RigAnimator`, and `TwoBoneIK` code. Tune timing and joint/contact targets; use the existing sliders before hard-coding a new default. Run core tests. Review both facings, the complete clip cycle, and interruption by a grab. Keep feet planted and level during stance, knees aligned with toe direction, and hands on their contact points.
3. **Drawing reference, later:** use an image-generation tool/agent to produce one consistent character reference with a readable silhouette and oversized equipment. Review it at 74 points tall before generating all body parts. The current shape rig remains the reference for pivots and proportions.
4. **Body-part preparation, later:** prepare transparent parts with enough hidden overlap behind joints. Keep the reference palette, clothing, and proportions consistent. Inspect transparency edges and align the pieces; generated images are not assumed to be rig-ready.
5. **Artwork integration, later:** replace vector shapes with textures beneath the same joint nodes. Preserve rig anchors and the simulation contract. Keep a shape/debug mode. Review every clip in both directions on light and dark backgrounds before accepting the assets.
6. **Personality, later:** add binoculars, map, kettle, and banana-reveal poses. Add other explorers only after one rig is readable and reliable.

For each task, report what changed, what was built/tested, the preview used for visual review, and any visible issue still unresolved. Ask for style/timing feedback when it would improve the result, while continuing independent technical work. Do not turn temporary concept art into production assets without checking the assembled rig.

## Future artwork manifest

For each texture, record its relative file path, source pixel dimensions, intended point dimensions, pivot, attachment points, layer order, and hidden overlap. Coordinates must explicitly state whether y runs up or down. The manifest should map names such as `leftUpperArm`, `leftLowerArm`, `head`, and `backpack` to the existing rig nodes. Keep asset import/scaling separate from animation rules. A loader and finished bitmap artwork are subsequent work, not part of this shape-rig milestone.

## Verification

```sh
swift test --package-path Packages/ExpeditionCore
```

Numerical tests cover segment lengths, unreachable targets, finite poses, fixed climbing contacts, mirroring, anatomical pole directions, interruptions, clock pause, and deterministic restart. Use the playground to assess silhouette, soles, bend direction, contact sliding, canopy clipping, and comic timing. Numerical tests cannot establish visual quality.
