; ROM hack: best-of-7 boss series.
;
; Sixteen overworld duels (the eight Club Masters, the four Grand Masters,
; and the four Ronald encounters) are upgraded so that beating the NPC
; once is no longer enough -- the player and the boss play repeatedly,
; and whoever first reaches BO7_NEEDED_WINS (4) wins the series. The same
; treatment is applied to every Challenge Machine match.
;
; The series counters live in WRAM (wBossSeriesActive / wBossSeriesPlayerWins
; / wBossSeriesOpponentWins) and are persisted via WRAMToSRAMMapper, so a
; mid-series soft reset resumes from the same score on next encounter.
; The player's deck is locked for the duration: between sub-matches we go
; straight back into StartDuel_VSAIOpp without re-entering the overworld
; script, so there is no opportunity to swap decks or pick a different
; opponent. Once a side reaches 4 wins the loop exits and the existing
; AFTER_DUEL map script (or Challenge Machine outer loop) takes over with
; the final wDuelResult.

; Returns carry if the NPC ID in a is one of the bosses we want to apply
; the BO7 series to. Otherwise carry clear.
IsBossSeriesNPC::
	push bc
	push hl
	ld c, a
	ld hl, BossSeriesNPCList
.loop
	ld a, [hl]
	or a
	jr z, .not_boss
	cp c
	jr z, .is_boss
	inc hl
	jr .loop
.is_boss
	scf
	jr .done
.not_boss
	or a
.done
	pop hl
	pop bc
	ret

BossSeriesNPCList:
	db NPC_NIKKI    ; Grass Club Master
	db NPC_KEN      ; Fire Club Master
	db NPC_AMY      ; Water Club Master
	db NPC_MURRAY1  ; Psychic Club Master
	db NPC_MITCH    ; Fighting Club Master
	db NPC_GENE     ; Rock Club Master
	db NPC_ISAAC    ; Lightning Club Master
	db NPC_RICK     ; Science Club Master
	db NPC_COURTNEY ; Grand Master
	db NPC_STEVE    ; Grand Master
	db NPC_JACK     ; Grand Master
	db NPC_ROD      ; Grand Master
	db NPC_RONALD1  ; Ronald 1
	db NPC_RONALD2  ; Ronald 2
	db NPC_RONALD3  ; Ronald 3
	db NPC_MURRAY2  ; Murray's grand challenge (counted as a Ronald-tier fight)
	db 0            ; terminator

; Called from GameEvent_Duel just before the first StartDuel_VSAIOpp call.
; If wNPCDuelist is a boss and no series is in progress, start a new series.
; If a series is already active for this NPC, leave the counters alone and
; resume. If the NPC is not a boss, clear wBossSeriesActive so the post-duel
; hook becomes a no-op.
BossSeries_BeginIfBoss::
	ld a, [wNPCDuelist]
	call IsBossSeriesNPC
	jr c, .is_boss
	xor a
	ld [wBossSeriesActive], a
	ret
.is_boss
	ld c, a ; NPC ID
	ld a, [wBossSeriesActive]
	cp c
	ret z   ; already in this series, keep counters
	ld a, c
	ld [wBossSeriesActive], a
	xor a
	ld [wBossSeriesPlayerWins], a
	ld [wBossSeriesOpponentWins], a
	ret

; Called from ChallengeMachine_Duel just before the first StartDuel_VSAIOpp.
; The Challenge Machine treats every opponent as a BO7 boss, but doesn't
; care which one -- it's enough to know "we are inside a CM match". On a
; fresh match start the counters reset to 0-0; on a resume (after a soft
; reset mid-series) we keep whatever was saved.
BossSeries_BeginCMMatch::
	ld a, [wBossSeriesActive]
	cp BO7_CM_MARKER
	ret z   ; already mid-CM-series, keep counters
	ld a, BO7_CM_MARKER
	ld [wBossSeriesActive], a
	xor a
	ld [wBossSeriesPlayerWins], a
	ld [wBossSeriesOpponentWins], a
	ret

; Called after every StartDuel_VSAIOpp return. Returns nz if the caller
; should loop back into StartDuel_VSAIOpp for another sub-match, or z if
; the series is over (or never was a series) and the caller should fall
; through to its normal post-duel flow.
;
; On series exit the counters are zeroed and wBossSeriesActive is cleared
; so the next encounter starts fresh. wDuelResult is preserved so the
; outer flow sees the final match's outcome (4-X => DUEL_WIN for player,
; X-4 => DUEL_LOSS).
BossSeries_AfterDuel::
	ld a, [wBossSeriesActive]
	or a
	jr z, .not_in_series
	ld a, [wDuelResult]
	or a
	jr nz, .opponent_won_match
.player_won_match
	ld hl, wBossSeriesPlayerWins
	inc [hl]
	jr .check_series_over
.opponent_won_match
	ld hl, wBossSeriesOpponentWins
	inc [hl]
.check_series_over
	ld a, [wBossSeriesPlayerWins]
	cp BO7_NEEDED_WINS
	jr z, .series_over_player_won
	ld a, [wBossSeriesOpponentWins]
	cp BO7_NEEDED_WINS
	jr z, .series_over_opponent_won
	; series continues -- print score and loop
	call BossSeries_PrintScore
	; persist updated counters across the next match
	call SaveGeneralSaveData
	or $ff   ; nz, signal "loop"
	ret
.series_over_player_won
	xor a
	ld [wDuelResult], a       ; DUEL_WIN
	jr .clear_series
.series_over_opponent_won
	ld a, DUEL_LOSS
	ld [wDuelResult], a
.clear_series
	xor a
	ld [wBossSeriesActive], a
	ld [wBossSeriesPlayerWins], a
	ld [wBossSeriesOpponentWins], a
	xor a   ; z, signal "exit loop"
	ret
.not_in_series
	xor a   ; z
	ret

; --- ROM hack: defeated-NPC tracking and rematch / bonus-pack hooks. -------
;
; "Typical opponent" = any NPC that is not on BossSeriesNPCList. A typical
; opponent can only be dueled once: winning the first match marks them in
; wDefeatedNPCs and awards an extra booster pack. Subsequent attempts to
; trigger a duel against them (via ScriptCommand_StartDuel) are short-
; circuited with a "no rematch" textbox.

; Resolve an NPC ID into a byte address and bit mask within wDefeatedNPCs.
; Input:  a = NPC ID
; Output: hl = pointer to the NPC's byte in wDefeatedNPCs
;         d  = bitmask (single bit set, position = NPC_ID mod 8)
;         a  = NPC ID (preserved)
; Clobbers b, c, e.
DefeatedNPCsAddrAndMask:
	ld e, a            ; preserve NPC ID
	; build d = 1 << (a & 7)
	and $07
	ld d, $01
	or a
	jr z, .mask_ready
	ld b, a
.mask_shift
	sla d
	dec b
	jr nz, .mask_shift
.mask_ready
	; hl = wDefeatedNPCs + (NPC_ID >> 3)
	ld a, e
	srl a
	srl a
	srl a
	ld c, a
	ld b, 0
	ld hl, wDefeatedNPCs
	add hl, bc
	ld a, e            ; restore a
	ret

; Returns carry if the NPC ID in a is marked defeated. Clobbers a and flags.
IsNPCDefeated::
	push bc
	push de
	push hl
	call DefeatedNPCsAddrAndMask
	ld a, [hl]
	and d                ; z = not set, nz = set; carry always clear after AND
	pop hl
	pop de
	pop bc
	ret z                ; bit clear => no carry
	scf
	ret

; Sets the defeated bit for the NPC ID in a. Clobbers a and flags.
MarkNPCDefeated::
	push bc
	push de
	push hl
	call DefeatedNPCsAddrAndMask
	ld a, [hl]
	or d
	ld [hl], a
	pop hl
	pop de
	pop bc
	ret

; Returns carry if the NPC ID in a is exempt from the rematch-blocking and
; bonus-pack systems entirely: bosses (handled by BO7), plus a small set of
; gameplay-special NPCs whose script depends on being talkable repeatedly
; (Sam runs the practice duel after the tutorial; Aaron offers a legendary-
; cards challenge keyed on the deck the player picked). Clobbers a/flags;
; callers must save the NPC ID separately if they need it after the call.
IsRematchExemptNPC:
	cp NPC_SAM
	jr z, .exempt
	cp NPC_AARON
	jr z, .exempt
	cp NPC_IMAKUNI              ; multi-fight char with EVENT_IMAKUNI_WIN_COUNT rewards
	jr z, .exempt
	jp IsBossSeriesNPC          ; tail-call; carry already encodes match
.exempt
	scf
	ret

; Used by ScriptCommand_GiveBoosterPacks to decide whether to award a bonus
; booster pack at the end of a winning duel script. Returns carry, AND sets
; the NPC's defeated bit, only when ALL of:
;   - the script that's running belongs to the NPC the player just dueled
;     (wNPCDuelist == the resolved NPC ID passed in)
;   - the player won (wDuelResult == DUEL_WIN)
;   - the NPC is a regular pupil (not exempt: not boss, not Sam, not Aaron)
;   - the NPC hasn't already been marked defeated
; Input:  a = NPC ID, already resolved from wScriptNPC by the caller
; Output: carry set => caller should give one extra pack and update SRAM
;         carry clear => normal post-duel flow
TryMarkFirstDefeatOfTypical::
	push bc
	ld c, a                  ; preserve NPC ID
	ld a, [wNPCDuelist]
	cp c
	jr nz, .no
	ld a, [wDuelResult]
	or a
	jr nz, .no
	ld a, c
	call IsRematchExemptNPC
	jr c, .no
	ld a, c
	call IsNPCDefeated
	jr c, .no
	ld a, c
	call MarkNPCDefeated
	pop bc
	scf
	ret
.no
	pop bc
	or a
	ret

; Returns carry if the NPC ID in a is a typical (non-exempt) opponent that
; the player has already defeated, and so should not be re-fightable.
; Preserves a.
ShouldBlockRematch::
	push bc
	push hl
	push af
	call IsRematchExemptNPC
	jr c, .not_blocked
	; not exempt; check defeated bit
	pop af
	push af
	call IsNPCDefeated
	jr nc, .not_blocked
	pop af
	pop hl
	pop bc
	scf
	ret
.not_blocked
	pop af
	pop hl
	pop bc
	or a
	ret

; Display "Series score X-Y. First to 4 wins." textbox. Resets the wTxRam3
; cursor each call so the two <RAMNUM> placeholders pick up our two values.
BossSeries_PrintScore:
	ld a, [wBossSeriesPlayerWins]
	ld [wTxRam3], a
	xor a
	ld [wTxRam3 + 1], a
	ld a, [wBossSeriesOpponentWins]
	ld [wTxRam3_b], a
	xor a
	ld [wTxRam3_b + 1], a
	xor a
	ld [wWhichTxRam3], a
	ldtx hl, BO7BossSeriesScoreText
	call DrawWideTextBox_WaitForInput
	ret
