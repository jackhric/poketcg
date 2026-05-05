AIActionTable_PowerfulRonald:
	dw .do_turn ; unused
	dw .do_turn
	dw .start_duel
	dw .forced_switch
	dw .ko_switch
	dw .take_prize

.do_turn
	call AIMainTurnLogic
	ret

.start_duel
	call InitAIDuelVars
	call .store_list_pointers
	call SetUpBossStartingHandAndDeck
	call TrySetUpBossStartingPlayArea
	ret nc
	call AIPlayInitialBasicCards
	ret

.forced_switch
	call AIDecideBenchPokemonToSwitchTo
	ret

.ko_switch
	call AIDecideBenchPokemonToSwitchTo
	ret

.take_prize
	call AIPickPrizeCards
	ret

.list_arena
	db ELECTABUZZ_LV35
	db HITMONCHAN
	db HITMONLEE
	db KANGASKHAN
	db MR_MIME
	db TAUROS
	db MEWTWO_LV53
	db LICKITUNG
	db $00

.list_bench
	db HITMONCHAN
	db ELECTABUZZ_LV35
	db HITMONLEE
	db MR_MIME
	db MEWTWO_LV53
	db KANGASKHAN
	db TAUROS
	db LICKITUNG
	db $00

.list_retreat
	ai_retreat MR_MIME,    -3
	ai_retreat KANGASKHAN, -1
	ai_retreat LICKITUNG,  -1
	db $00

.list_energy
	ai_energy ELECTABUZZ_LV35, 2, +1
	ai_energy HITMONLEE,       3, +1
	ai_energy HITMONCHAN,      3, +1
	ai_energy MR_MIME,         1, -2
	ai_energy MEWTWO_LV53,     4, +1
	ai_energy LICKITUNG,       2, +0
	ai_energy KANGASKHAN,      3, +0
	ai_energy TAUROS,          3, +0
	db $00

.list_prize
	db MEWTWO_LV53
	db PROFESSOR_OAK
	db $00

.store_list_pointers
	store_list_pointer wAICardListAvoidPrize, .list_prize
	store_list_pointer wAICardListArenaPriority, .list_arena
	store_list_pointer wAICardListBenchPriority, .list_bench
	store_list_pointer wAICardListPlayFromHandPriority, .list_bench
	store_list_pointer wAICardListRetreatBonus, .list_retreat
	store_list_pointer wAICardListEnergyBonus, .list_energy
	ret
