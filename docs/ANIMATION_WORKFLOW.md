# Explorer animation workflow

## Running the playground

Build the Debug app, then use **Animation Playground…** in its hiking menu bar menu. Or quit the running app and launch directly:

```sh
./scripts/build.sh
build/Build/Products/Debug/OtherSock.app/Contents/MacOS/OtherSock --playground
```

The playground is a normal, focusable window separate from the desktop overlay. Closing it stops its rendering. It is excluded from Release builds. The enlarged preview and the actual-size preview use the same rig, clips, clock increments, and tuning values as the desktop character.

The clip menu contains idle, walking, climbing, abseiling, parachuting, held, investigating, landing, and a nine-second edge-hesitation comic sequence. Pause freezes the clip clock but still permits manual contact editing. Restart resets the pose, clip/expression time, origin, handholds, rope anchor, and grab point. Playback ranges from 0.1× to 1×; zoom ranges from 1× to 3×. Cadence, stride, and bounce are independent tuning controls. The **Preview time (pauses)** slider seeks both animation and expression clocks to an exact time and pauses playback; Resume continues from that frame.

In Climbing, drag either green handhold. An unreachable contact is red in the joint overlay, and the status line counts clamped contacts. The arm stays within its reachable length. In Abseiling, drag the yellow rope anchor. In Held, drag the pink grab point to change the pivot. In any clip, grab the body to interrupt it with the held pose; release blends back to the selected clip. Fake terrain stays fixed during that drag, and climbing handholds and the rope anchor retain their scene positions.

## Rig and coordinates

The default finish uses cached material textures: soft gradients, restrained grain, canvas weave/flap detail, leather highlights/soles, felt hat bands, and warm face shading beneath the brim. Material-coloured outlines are 0.7 points wide, darkened for contrast. Arms and legs use restrained shading and a continuous outlined silhouette across each joint, avoiding separate borders at elbows and knees. Textures are generated at 4× resolution once per unique part/style and shared. Joint positions and physics are unchanged.

Use **Flat shading** in the playground to compare solid fills and the heavier outline against the painted finish. Pause or seek first for a comparison in the identical pose. The checkbox affects both the enlarged and actual-size previews; the desktop uses the painted finish by default.

The canonical rig faces right, with +x towards the toes and +y upwards. The backpack sits behind the body on the negative-x side. During forward walking, lifted feet swing towards +x and planted feet move towards -x relative to the body. Facing left mirrors all of these together; the playground status arrow states the selected direction. Its origin is the simulation's foot baseline. Rendered pose offsets never change simulation position, terrain collision, or the pointer grab offset.

Depth is independent of forward direction: the canonical left arm and leg are nearest the camera. The far arm draws behind the torso; the near arm draws over it. The far arm has a darker sleeve as a depth cue. Mirroring preserves these occlusion relationships. The face has no nose, per the user's preference.

| Part | Parent / pivot | Shape or length |
| --- | --- | --- |
| Presentation pivot | Simulation origin; grab point when held | Rotates the visual rig only |
| Torso | Standing hips nominally (0, 29.5) | Height follows planted-leg reach during walking |
| Head and hat | Hips + (0, 30) | Combined rig height about 74–75 points |
| Backpack | Hips + (-18, 10) | Behind the body; independent secondary rotation |
| Upper arms | Shoulders at hips + (±10, 20) | 12 points each |
| Lower arms | Child of upper arm at elbow | 12 points each; hand at endpoint |
| Upper legs | Hips + (±7, 0) | 13.5 points each |
| Lower legs | Child of upper leg at knee | 13.5 points each; ankle endpoint inside boot |
| Boots | Lower-leg endpoints | Soles three points below ankle; level and toes towards +x |
| Parachute | Visual rig | Appears after launch anticipation; does not accept input |

Two-bone IK solves each elbow/knee and endpoint. Anatomical pole targets favour knees ahead of the body and elbows behind it, rather than assigning arbitrary signs independently to each limb. Mirroring the entire rig preserves the relation between knees and toes. The hand or foot target is exact when reachable; beyond reach, the target remains visible for debugging while the actual endpoint is clamped.

Abseiling uses a forward/down elbow pole so elbows fold below the grips rather than across the face. Standing hips are higher, and walking hips follow a nearly extended planted leg across the stride range. Climbing keeps a deliberately bent posture.

## Expressions, deployment, and landing

Blinks use an independent expression clock with varied intervals and occasional double blinks. The second eye follows the first by 18 ms, with the leading eye alternating. Closing is quicker than reopening. Pause freezes expressions; clip changes preserve the expression clock, while Restart resets it. To inspect a staggered blink, seek to about 2.46 seconds in Idle.

The parachute begins deploying after 0.18 seconds and inflates over 0.55 seconds. Fabric starts as a folded bundle at the backpack, rises behind the body, and expands overhead. Four suspension lines follow the moving fabric edge and the hand targets. Both fabric and cords render behind the explorer.

The desktop recovery clock uses the same deployment timing to ease downward speed from 270 to 140 points/second. Drag release preserves filtered pointer velocity, capped at 900 points/second, then damps it with air resistance that increases as the canopy opens. Upward throws can rise briefly; sideways throws carry across the screen. A still hold before release clears stale velocity, and re-grabbing cancels flight. Display bounds constrain the trajectory and swept platform checks use the actual crossing point. Playground body dragging remains a pose-editing tool; release inertia applies to the desktop explorer.

Landing keeps soles on the surface while lowering hips and hands by up to four points: compression takes 0.08 seconds and recovery 0.28 seconds. Recovery-to-settling triggers it on the desktop, and a direct platform placement uses a gentler version. Grabbing cancels a landing. The Landing preview repeats the crouch every 2.5 seconds; seek to 0.68 seconds to inspect maximum compression. These are visual offsets and do not move the terrain anchor.

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

## Desktop travel and mission integration

The desktop now consumes fixed-step walking, climbing, abseiling and recovery states from ExpeditionCore. Facing follows travel or the contacted wall. Climbing contacts stay fixed relative to their supporting window during stance and lift during the next stroke. Near/far hand heights and foot stroke heights are checked against limb reach throughout body bobbing. Abseiling rope anchors stay attached to the supporting window top; props, cords, flags and speech never enlarge the body input panel. Falling/deployment/open-canopy timing remains shared between presentation and recovery distance.

`BananaMission` drives spotting/binoculars, investigation, banana reveal, map marking and rest through fixed-clock stages. A grab cancels the mission immediately even while paused. Animation uses numeric blending and stage/state changes rather than delayed completion callbacks. Use the real-window fixture and `--movement-only` to reproduce traversal separately from the adventure; see [validation](PROTOTYPE_VALIDATION.md).


## Movement feedback — 6 November 2026

Walking's sideways displacement is the integral of the stance foot's existing cosine sweep: 20 points per half-cycle, 40 points per cycle at cadence 1. The actor and rig share this clock, so stance feet remain planted without speeding up the leg animation. Climbing similarly lifts 12 points per alternating hand pull, slowing at grip exchanges. Its contact phase is window-relative and its body bob shares the pull clock.

Climbing boots stay below their hip joints; legs use a consistent canonical knee branch instead of a pole that could change sides as a high boot crossed the hip. Arms retain their separate anatomical poles.

**Mantling**, **Lowering** and **Launching** are available in the playground and share the actual desktop root paths. Mantling pulls up with hands on the lip, brings a boot over, transfers weight over that planted boot, then stands. Lowering reverses that choreography. Launching anticipates, pushes clear, then enters recovery/chute deployment. These states are interruptible and revalidate their supporting geometry.

Rope geometry uses a top pin, a circular corner guide with one point of clearance, and a tangent free lead to the current grip. Cubic arc handles align with both straight leads; the contact angle changes as the hands descend. The playground's scaled window corner matches the guide's estimated radius.


## Grapple and shared rope modes — 6 November 2026

`RopeSession` now owns the common window/edge anchor, `RopeDynamics`, paid-out length, firing trajectory, mode and pull clock. Abseiling, hand-over-hand rope climbing and swinging all operate on this session. Motor changes do not replace the rope or reset its momentum. Landing can retain the line; reaching the lip hands off to the existing mantle. Grabbing and invalid anchors cancel it safely.

The solver integrates gravity at 240 Hz inside the fixed simulation step, projects only overstretched lines, and preserves tangential velocity. Slack lines fall freely. Reeling conserves angular momentum before friction/contact losses. The renderer hangs the body around its harness, puts the gloves along the free lead, and preserves the top/corner/free-lead tangents. A real push-off impulse starts a swing from rest against the wall.

The shared rig includes a spool launcher and aiming hands for **Grappling**, plus **Ropeclimbing** and **Ropeswinging** pose previews. The flying hook and full movement use the desktop simulation. For repeatable real-window checks, launch the fixture with `--low-only`, then the Debug app with `--fixture-terrain --activity=grapple --trace-movement`. `--freeze-grapple` freezes the hook in flight; `--freeze-swing` freezes the latched hanging pose. Omit either freeze flag to run the complete journey.


## Pointer awareness — 6 November 2026

The shared rig samples the current pointer during rendering, converts it through the real scene/head transforms, and applies a small additive gaze and head turn. This respects facing, zoom and rope sway. Eyes respond over about 90 ms, the head over 220 ms; interest fades between 120 and 220 logical rig points. Eye displacement remains within the face, blink openness still controls both eyes independently, and the existing motion pose remains the base. Firing reduces the distraction. No pointer events are intercepted or permission requested. The same response is visible in the desktop and playground; pausing rendering also pauses expressions.


## Leg-driven player jump — 6 November 2026

`JumpAnimation` shares a 120 ms ground preparation (65 ms compression, then extension) between the player physics and poses. Feet stay on their support until the legs extend; a 285 pt/s impulse and 600 pt/s² gravity give a roughly 68-point jump. Airborne poses blend from extension into a tuck and reach toward a real landing surface. A landing counter fires the existing impact compression exactly once, even when several simulation steps happen in a rendered frame. Steering accelerates at 400 pt/s² and coasts down at 120 pt/s². The first 80 ms of landing permits impact absorption before walking resumes.

The playground's **Jumping** motion uses the same preparation, ballistic height, airborne poses and landing compression, at full and actual desktop scale. Useful paused times: 0.065 s crouch, 0.12 s full extension, 0.59 s near apex, and 1.15 s impact compression. This replaces the player's fixed 0.8 s sample of the parachute-launch clip. Automatic edge launches retain their separate corner choreography.
