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
