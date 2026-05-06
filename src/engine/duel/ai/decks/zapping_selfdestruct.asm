AIActionTable_ZappingSelfdestruct:
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
	db MAGNEMITE_LV13
	db VOLTORB
	db KANGASKHAN
	db $00

.list_bench
	db MAGNEMITE_LV13
	db VOLTORB
	db ELECTABUZZ_LV35
	db KANGASKHAN
	db $00

.list_retreat
	ai_retreat VOLTORB,        -2
	ai_retreat MAGNEMITE_LV13, -1
	db $00

.list_energy
	ai_energy MAGNEMITE_LV13,  1, -1
	ai_energy MAGNETON_LV28,   3, +1
	ai_energy MAGNETON_LV35,   3, +1
	ai_energy VOLTORB,         3, +1
	ai_energy ELECTRODE_LV35,  3, +0
	ai_energy ELECTABUZZ_LV35, 2, +1
	ai_energy KANGASKHAN,      4, +0
	db $00

.list_prize
	db MAGNETON_LV35
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
