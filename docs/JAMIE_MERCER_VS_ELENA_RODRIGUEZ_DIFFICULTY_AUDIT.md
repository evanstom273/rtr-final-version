# Jamie Mercer vs Elena Rodriguez Difficulty Audit

## Case Summary

The supplied match report ends at 28:20 with Jamie Mercer defeating Elena Rodriguez by pinfall after a Rebound Satellite Facebuster. Jamie attempted nine moves and landed eight, dealt 107.7 damage, escaped two submissions, landed two weapon attacks and a table spot, used Catch Breath three times, and completed four actions from zero stamina. Elena attempted six moves, landed three, used no Catch Breath actions, and finished with zero stamina.

This report demonstrates a real structural difficulty problem, but it cannot reproduce every historical random result. The exported report contains no match RNG seed, per-action stamina snapshot, execution roll, reversal roll, control-retention roll, or AI candidate list. Conclusions below therefore distinguish confirmed resolver behavior from plausible rolls.

## Confirmed Structural Findings

### Attacker execution was not resolved

`MatchInteractionModel.build_execution_profile()` and `execution_success_chance()` calculated exhaustion-sensitive difficulty, and the AI scorer used that value while choosing moves. The live move resolver did not use it. `SimpleMatchUI.execute_move()` advanced directly to `_run_defender_response()`, and a failed defender reversal became `CLEAN_SUCCESS`.

Consequences:

- The reported 19.2% average execution penalty described difficulty that never generated an attacker failure check.
- Zero stamina made a move somewhat easier to reverse, but could not independently make the attacker mistime or botch it.
- A late finisher could land whenever the defender failed a reversal check, regardless of the execution profile.

### Weapon attacks bypassed execution and control retention

Runtime weapon moves recorded exhaustion profiles and spent fatigue-scaled stamina, but also went directly to defender response. A non-reversed weapon attack always landed. Successful legal weapon attacks assigned control directly to the attacker rather than using `MatchExhaustionModel.control_retention_chance()`.

This explains why a zero-stamina weapon attack could succeed and continue the player's initiative without an execution or retention failure.

### Late recovery pressure leaked into reversals

Defender reversal chance subtracted `build_late_match_profile().recovery_penalty`. That value was authored for recovery strength, but at 25:00 and later it also made reversals substantially less likely. Finishers and high-impact moves already reduce reversal chance, so the additional late subtraction could push the final check to its 5% floor.

### Submission input had a player-side throughput advantage

The submission widget accepted up to eight player inputs per second while AI pressure pulsed every 0.2 seconds, or five times per second. An AI pulse and a player press used comparable impulse magnitudes. At equal condition scores, maximum player force per second was therefore approximately 1.6 times AI force, regardless of whether the player was attacking or defending.

### Catch Breath could be bypassed before scoring

The AI decision engine scores Catch Breath, but `SimpleMatchUI._perform_ai_decision()` attempted optional weapon and environmental branches before asking the scored engine for a decision. A low-stamina AI could therefore choose a weapon or setup action without Catch Breath ever entering that turn's comparison. Generic setup-history penalties could also reduce Catch Breath despite it not creating a tactical setup intent.

### Several diagnostics overstated flow failures

- Mandatory state recovery called `note_forced_fallback()`, so ordinary recovery was reported as a dead-end fallback.
- Setup-loop counters incremented while candidates were scored, including candidates the AI never selected.
- Exhausted weapon attempts incremented the high-risk counter even when the move was not mechanically high risk.

These counters were useful clues but did not prove that Elena selected fourteen looping actions or encountered three genuine dead ends.

## Formula Audit

Combined exhaustion is:

`0.65 × stamina depletion + 0.35 × fatigue ratio + 0.25 × depletion × fatigue ratio`, clamped to 0–1.

Execution penalties are relative reductions with separate Basic, Standard, and Explosive curves. At zero stamina the unamplified values are 10%, 15%, and 25%; fatigue amplification raises them to caps of 15%, 22%, and 35%.

Control retention currently remains 100% for Basic moves, at least 82% for Standard moves, and at least 60% plus a momentum contribution for Explosive moves. The report's zero exhaustion-caused control losses were possible, although several actions still entered Neutral because both wrestlers were grounded.

Kickout windows already use the final visible width as AI probability and retain the count-specific `/4`, `/5`, and `/6` scaling. One successful count-one kickout is not enough evidence for another pin rebalance.

Submission pressure already incorporates match time, target-part HP, stamina/fatigue escape reduction, momentum, finisher status, and squash context. The confirmed imbalance was input throughput, not the existence of those pressure factors.

## Implemented Correction Strategy

- Every player offensive move receives a one-shot horizontal execution Control Meter with a compact one-seventh-scale target. AI offence does not make a hidden execution roll; once the AI commits to a legal move, only the player's reversal check can stop it.
- Defender response is attempted only after successful execution.
- An execution miss is treated as the defender reading and reversing the attempt, giving the defender control. There is no separate execution-botch result.
- Heavy environmental follow-ups are treated as Explosive demand.
- Weapon attacks use execution and normal control retention.
- Late recovery penalties no longer modify reversals, and attacker execution difficulty is no longer duplicated inside reversal chance.
- AI Catch Breath receives an urgent recovery gate before optional weapon/environment branches, and voluntarily surrendering time to recover favours the opponent 80/20 for the next initiative.
- AI submission pulse force is normalized by 8/5 so equal scores provide equal maximum force per second.
- New opt-in JSONL diagnostics record the missing action snapshots under `user://difficulty_diagnostics.jsonl` without flooding the Godot console.

## What Remains Deliberately Unchanged

Pin widths, count sequencing, finish pressure, body-part targeting, finisher stock, signature conversion, submission thresholds, weapon durability, and authored move resources are unchanged. Further tuning should be based on the new deterministic regressions and structured match traces rather than this single historical result.
