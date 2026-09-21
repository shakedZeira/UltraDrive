# tests/suites/test_career_economy.gd
extends GdUnitTestSuite

## Item 11 acceptance gate: the persistent Money ledger (career_money key in
## slot 0), CareerProfile (level/XP/perks, career_profile key), LicenseSystem
## discipline tracking, Championship seasons + podium payouts, and the Garage
## price/buy/sell economy. Every test snapshots slot 0 and restores it in
## after_test so the existing save stays untouched (mirrors unit_discovery).

var _slot_snapshot: Dictionary = {}

func _begin() -> void:
    _slot_snapshot = SaveManager.load_game(0)

func after_test() -> void:
    var slot := 0
    var path = SaveManager.SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
    if _slot_snapshot.is_empty() and not SaveManager.has_save(slot):
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)
    else:
        SaveManager.save_game(slot, _slot_snapshot)

func _unlocked_set(license: LicenseSystem) -> Array[String]:
    var out: Array[String] = []
    for cls in ["D", "C", "B", "A", "S"]:
        if license.is_car_unlocked(cls):
            out.append(cls)
    return out

func test_ledger_invariants_never_negative() -> void:
    var money := Money.new()
    assert_that(money.is_accounting_consistent()).is_true()
    money.add(1000)
    assert_that(money.get_credits()).is_equal(1000)
    assert_that(money.get_total_credited()).is_equal(1000)
    assert_that(money.spend(400)).is_true()
    assert_that(money.get_credits()).is_equal(600)
    assert_that(money.get_total_spent()).is_equal(400)
    assert_that(money.is_accounting_consistent()).is_true()
    assert_that(money.spend(2000)).is_false()
    assert_that(money.get_credits()).is_equal(600)
    assert_that(money.balances_to_zero()).is_false()
    assert_that(money.spend(600)).is_true()
    assert_that(money.balances_to_zero()).is_true()
    assert_that(money.is_accounting_consistent()).is_true()

func test_ledger_from_dict_clamps_spent_to_credited() -> void:
    var money := Money.new()
    money.from_dict({"total_credited": 500, "total_spent": 700})
    assert_that(money.get_total_credited()).is_equal(500)
    assert_that(money.get_total_spent()).is_equal(500)
    assert_that(money.get_credits()).is_equal(0)
    assert_that(money.is_accounting_consistent()).is_true()
    money.from_dict({"total_credited": 300, "total_spent": 100})
    assert_that(money.get_credits()).is_equal(200)
    assert_that(money.is_accounting_consistent()).is_true()
    money.from_dict({})
    assert_that(money.get_credits()).is_equal(0)
    assert_that(money.is_accounting_consistent()).is_true()

func test_xp_curve_and_level_up_progress() -> void:
    var profile := CareerProfile.new()
    assert_that(profile.xp_to_next(1)).is_equal(100)
    assert_that(profile.xp_to_next(3)).is_equal(300)
    assert_that(profile.level).is_equal(1)
    assert_that(profile.get_total_xp()).is_equal(0)
    assert_that(profile.add_xp(100)).is_equal(1)
    assert_that(profile.level).is_equal(2)
    assert_that(profile.get_total_xp()).is_equal(100)
    assert_that(profile.add_xp(250)).is_equal(1)
    assert_that(profile.level).is_equal(3)
    assert_that(profile.get_total_xp()).is_equal(350)
    assert_that(profile.add_xp(0)).is_equal(0)
    assert_that(profile.level).is_equal(3)

func test_finish_position_xp_and_economy_constants() -> void:
    assert_that(CareerProfile.race_position_xp(1)).is_equal(50)
    assert_that(CareerProfile.race_position_xp(2)).is_equal(40)
    assert_that(CareerProfile.race_position_xp(3)).is_equal(30)
    assert_that(CareerProfile.race_position_xp(4)).is_equal(20)
    assert_that(CareerProfile.race_position_xp(5)).is_equal(10)
    assert_that(CareerProfile.race_position_xp(6)).is_equal(5)
    assert_that(CareerProfile.race_position_xp(0)).is_equal(5)
    assert_that(CareerProfile.RACE_LAP_XP).is_equal(10)
    assert_that(CareerProfile.EVENT_XP).is_equal(25)
    assert_that(CareerProfile.LICENSE_TEST_XP).is_equal(50)
    assert_that(CareerProfile.PODIUM_XP).is_equal(100)

func test_career_profile_round_trip_via_slot_save() -> void:
    _begin()
    assert_that(Money.wallet_add(1500)).is_true()
    var loaded := Money.load_wallet()
    assert_that(loaded.get_credits()).is_equal(1500)
    var after: Dictionary = SaveManager.load_game(0)
    assert_that(after.has(Money.SAVE_KEY)).is_true()
    assert_that(CareerProfile.grant_xp(250)).is_true()
    var profile := CareerProfile.load_profile()
    assert_that(profile.level).is_equal(2)
    assert_that(profile.get_total_xp()).is_equal(250)
    var after_profile: Dictionary = SaveManager.load_game(0)
    assert_that(after_profile.has(CareerProfile.SAVE_KEY)).is_true()

func test_license_tier_maps_to_unlocked_car_classes() -> void:
    _begin()
    var license := LicenseSystem.new()
    assert_that(license.get_license_tier()).is_equal("B")
    assert_that(_unlocked_set(license)).is_equal(["D", "C"])
    license.complete_test("B", "Gold")
    license.complete_test("A", "Gold")
    assert_that(license.get_license_tier()).is_equal("A")
    assert_that(_unlocked_set(license)).is_equal(["D", "C", "B"])
    license.complete_test("S", "Gold")
    assert_that(_unlocked_set(license)).is_equal(["D", "C", "B", "A"])
    license.complete_test("Race", "Gold")
    license.complete_test("Elite", "Gold")
    assert_that(_unlocked_set(license)).is_equal(["D", "C", "B", "A", "S"])

func test_license_ladder_requires_prior_tiers_and_keeps_best_rating() -> void:
    _begin()
    var license := LicenseSystem.new()
    license.complete_test("A", "Gold")
    assert_that(license.get_license_tier()).is_equal("B")
    assert_that(license.get_best_rating("A")).is_equal("Gold")
    license.complete_test("B", "Silver")
    assert_that(license.get_license_tier()).is_equal("A")
    license.complete_test("B", "Gold")
    assert_that(license.get_license_tier()).is_equal("A")
    license.complete_test("A", "Silver")
    assert_that(license.get_license_tier()).is_equal("A")
    assert_that(license.get_best_rating("A")).is_equal("Gold")
    license.complete_test("A", "Gold")
    assert_that(license.get_best_rating("A")).is_equal("Gold")

func test_license_disciplines_tracked_and_persisted() -> void:
    _begin()
    var license := LicenseSystem.new()
    assert_that(license.get_discipline_tier("Circuit")).is_equal("")
    assert_that(license.is_discipline_passed("Circuit", "B")).is_false()
    license.complete_discipline_test("Circuit", "B", "Gold")
    assert_that(license.is_discipline_passed("Circuit", "B")).is_true()
    license.complete_discipline_test("Circuit", "A", "Gold")
    assert_that(license.get_discipline_tier("Circuit")).is_equal("A")
    license.complete_discipline_test("Rally", "A", "Gold")
    assert_that(license.get_discipline_tier("Rally")).is_equal("")
    license.complete_discipline_test("Drill", "B", "Gold")
    assert_that(license.is_discipline_passed("Drill", "B")).is_false()
    license.save()
    var reloaded := LicenseSystem.load_from_save()
    assert_that(reloaded.is_discipline_passed("Circuit", "B")).is_true()
    assert_that(reloaded.get_discipline_tier("Circuit")).is_equal("A")
    var data: Dictionary = SaveManager.load_game(0)
    assert_that(data.has("license_results")).is_true()
    assert_that(data.has("license_discipline_results")).is_true()

func test_championship_points_and_progression() -> void:
    var champ := Championship.new()
    champ.start_championship("Cup", [
        {"track": "a"}, {"track": "b"}, {"track": "c"}, {"track": "d"},
    ])
    assert_that(champ.is_complete()).is_false()
    assert_that(champ.get_next_race()).is_equal({"track": "a"})
    champ.complete_race(1)
    champ.complete_race(3)
    champ.complete_race(10)
    champ.complete_race(2)
    assert_that(champ.get_standings()).is_equal({"player": 25 + 15 + 1 + 18})
    assert_that(champ.is_complete()).is_true()
    assert_that(champ.get_next_race()).is_equal({})

func test_championship_podium_payouts_and_xp() -> void:
    var champ := Championship.new()
    var ledger := Money.new()
    var profile := CareerProfile.new()
    champ.money_ledger = ledger
    champ.profile = profile
    champ.start_championship("Season 1", [
        {"track": "a"}, {"track": "b"}, {"track": "c"},
    ])
    champ.complete_race(1)
    champ.complete_race(4)
    champ.complete_race(3)
    assert_that(champ.get_standings()).is_equal({"player": 25 + 12 + 15})
    assert_that(ledger.get_total_credited()).is_equal(5000 + 1500)
    assert_that(ledger.get_credits()).is_equal(5000 + 1500)
    assert_that(profile.get_total_xp()).is_equal(200)
    assert_that(champ.podium_payout(1)).is_equal(5000)
    assert_that(champ.podium_payout(3)).is_equal(1500)
    assert_that(champ.podium_payout(4)).is_equal(0)

func test_championship_can_enter_series_gates() -> void:
    var license := LicenseSystem.new()
    license.complete_test("B", "Gold")
    license.complete_test("A", "Gold")
    license.complete_test("S", "Gold")
    var garage := Garage.new()
    garage.load_data({"owned_cars": ["starter_car", "cc0_race"]})
    var champ := Championship.new()
    champ.set_license(license)
    champ.set_garage(garage)
    assert_that(champ.can_enter_series({"name": "D Cup", "car_class_required": "D", "races": []})).is_true()
    assert_that(champ.can_enter_series({"name": "B Cup", "car_class_required": "B", "races": []})).is_true()
    assert_that(champ.can_enter_series({"name": "S Cup", "car_class_required": "S", "races": []})).is_false()
    var weak := Garage.new()
    weak.load_data({"owned_cars": ["starter_car"]})
    champ.set_garage(weak)
    assert_that(champ.can_enter_series({"name": "C Cup", "car_class_required": "C", "races": []})).is_false()

func test_garage_price_table_on_all_car_configs() -> void:
    var expected := {
        "starter_car": 8000,
        "muscle_car": 16000,
        "rally_hatch": 28000,
        "cc0_sedan_sports": 18000,
        "cc0_hatchback_sports": 30000,
        "cc0_race": 45000,
    }
    for car_id: String in expected.keys():
        var config := load("res://resources/cars/%s.tres" % car_id) as CarConfig
        assert_that(config).is_not_null()
        assert_that(config.price).is_equal(int(expected[car_id]))
        assert_that(Garage.get_price(car_id)).is_equal(int(expected[car_id]))

func test_garage_buy_sell_and_starter_protection() -> void:
    _begin()
    var money := Money.new()
    money.add(40000)
    var garage := Garage.new()
    garage.load_data({"owned_cars": []})
    assert_that(garage.buy_car("muscle_car", money)).is_true()
    assert_that(garage.get_owned_cars()).is_equal(["muscle_car"])
    assert_that(money.get_credits()).is_equal(24000)
    assert_that(money.is_accounting_consistent()).is_true()
    assert_that(garage.buy_car("muscle_car", money)).is_true()
    assert_that(garage.buy_car("cc0_sedan_sports", money)).is_true()
    assert_that(garage.get_owned_cars()).is_equal(["muscle_car", "cc0_sedan_sports"])
    assert_that(money.get_credits()).is_equal(6000)
    assert_that(garage.sell_car("muscle_car", money)).is_false()
    assert_that(garage.get_owned_cars()).is_equal(["muscle_car", "cc0_sedan_sports"])
    assert_that(money.get_credits()).is_equal(6000)
    assert_that(garage.sell_car("cc0_sedan_sports", money)).is_true()
    assert_that(garage.get_owned_cars()).is_equal(["muscle_car"])
    assert_that(money.get_credits()).is_equal(15000)
    assert_that(money.is_accounting_consistent()).is_true()
    var starter_garage := Garage.new()
    starter_garage.load_data({"owned_cars": ["starter_car"]})
    assert_that(starter_garage.sell_car("starter_car", money)).is_false()
    assert_that(starter_garage.get_owned_cars()).is_equal(["starter_car"])
    var broke := Money.new()
    assert_that(garage.buy_car("cc0_race", broke)).is_false()
    assert_that(garage.buy_car("rally_hatch", broke)).is_false()

func test_event_completion_banks_persistent_wallet_and_xp() -> void:
    _begin()
    var session := EventSession.new()
    add_child(session)
    assert_that(session.start_event("drift_zone")).is_true()
    session.tick_drift(1.0, 45.0, true)
    var result := session.complete_drift()
    assert_that(result.has("reward")).is_true()
    var reward := int(result["reward"])
    assert_that(reward).is_greater(0)
    assert_that(Money.load_wallet().get_credits()).is_equal(reward)
    assert_that(CareerProfile.load_profile().get_total_xp()).is_equal(CareerProfile.EVENT_XP)
    assert_that(session.is_event_active()).is_false()
    session.free()
